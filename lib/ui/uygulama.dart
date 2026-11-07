// Kök uygulama: Material 3 tema (Ayarlar'da Sistem/Koyu/Açık), Türkçe yerelleştirme, alt gezinme,
// yaşam döngüsü (arka plandan dönüşte bildirimleri yeniden kur) ve dışarıdan gelen dosya.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/kontrol.dart';
import '../platform/kopru.dart';
import 'ayarlar_sayfasi.dart';
import 'etkinlik_islemleri.dart';
import 'guncelleme_akisi.dart';
import 'gorevler_sayfasi.dart';
import 'metin.dart';
import 'senkron_akisi.dart';
import 'takvim_sayfasi.dart';
import 'wifi_akisi.dart';

// Tek kimlik: koyu zemin + mercan vurgu ("A yönü") ve açık "Kâğıt" paleti. Renkler masaüstüyle
// aynı değerler; açık temada vurgu #C2331D (mockup'taki #E5412A kâğıt zeminde 3.7:1, AA 4.5 ister).
const _koyu = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFF563C),
  onPrimary: Color(0xFF14161A),
  primaryContainer: Color(0xFF5A2218),
  onPrimaryContainer: Color(0xFFFFDAD3),
  secondary: Color(0xFFB9BFCB),
  onSecondary: Color(0xFF101114),
  secondaryContainer: Color(0xFF2B2F38),
  onSecondaryContainer: Color(0xFFEDEEF1),
  error: Color(0xFFFF8F7A),
  onError: Color(0xFF14161A),
  surface: Color(0xFF171A20),
  onSurface: Color(0xFFEDEEF1),
  onSurfaceVariant: Color(0xFFB9BFCB),
  surfaceContainerHighest: Color(0xFF22252C),
  outline: Color(0xFF8B919F),
  outlineVariant: Color(0xFF333844),
);

const _acik = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFC2331D),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFBD9D2),
  onPrimaryContainer: Color(0xFF5A1308),
  secondary: Color(0xFF4A463F),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFECE7DD),
  onSecondaryContainer: Color(0xFF1D1B18),
  error: Color(0xFFA32616),
  onError: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFDF9),
  onSurface: Color(0xFF1D1B18),
  onSurfaceVariant: Color(0xFF4A463F),
  surfaceContainerHighest: Color(0xFFECE7DD),
  outline: Color(0xFF6B665C),
  outlineVariant: Color(0xFFD6CFC1),
);

ThemeData _tema(Brightness b) {
  final k = b == Brightness.dark ? _koyu : _acik;
  return ThemeData(
    useMaterial3: true,
    colorScheme: k,
    scaffoldBackgroundColor: b == Brightness.dark
        ? const Color(0xFF101114)
        : const Color(0xFFF5F2EC),
    appBarTheme: AppBarTheme(
      backgroundColor: k.surface,
      foregroundColor: k.onSurface,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: k.surface,
      indicatorColor: k.primaryContainer,
    ),
    cardTheme: CardThemeData(
      color: k.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: k.outlineVariant),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

class TakvimUygulamasi extends StatefulWidget {
  const TakvimUygulamasi({super.key, required this.kontrol, this.kopru});
  final TakvimKontrol kontrol;

  /// Dışarıdan gelen dosyalar (Paylaş/Birlikte aç); testlerde null olabilir.
  final Kopru? kopru;

  @override
  State<TakvimUygulamasi> createState() => _TakvimUygulamasiDurumu();
}

class _TakvimUygulamasiDurumu extends State<TakvimUygulamasi>
    with WidgetsBindingObserver {
  TakvimKontrol get k => widget.kontrol;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final kopru = widget.kopru;
    if (kopru != null) {
      kopru.dosyaDinle(_gelen);
      kopru.baglantiDinle((b) => wifiBaglantiGeldi(k, b));
      kopru.kurulumSonucuDinle((durum, mesaj) => guncellemeKurulumSonucu(k, durum, mesaj));
      // Uygulama dosyayla açıldıysa ilk karede (gezgin hazırken) önizleme gösterilir.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final g = await kopru.bekleyenDosya();
        if (g != null) await _gelen(g);
        final b = await kopru.bekleyenBaglanti();
        if (b != null) await wifiBaglantiGeldi(k, b);
      });
    }
    // Güncelleme: seçim yoksa tek seferlik soru, açıksa günde en çok bir denetim (ağ yalnız seçimle).
    WidgetsBinding.instance.addPostFrameCallback((_) => guncellemeAcilis(k));
  }

  Future<void> _gelen(GelenDosya g) =>
      disaridanGelen(k, metin: g.metin, hata: g.hata);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState durum) {
    if (durum == AppLifecycleState.resumed) {
      // Arka planda gün değişmiş olabilir; izin ayarlardan değişmiş olabilir.
      k.yenile();
      k.bildirimleriYenile();
      guncellemeAcilis(k, sor: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: k.temaModu,
      builder: (context, mod, _) => MaterialApp(
        title: M.uygulamaAdi,
        debugShowCheckedModeBanner: false,
        theme: _tema(Brightness.light),
        darkTheme: _tema(Brightness.dark),
        themeMode: mod,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        scaffoldMessengerKey: k.mesajci,
        navigatorKey: k.navigatorAnahtari,
        home: AnaIskele(kontrol: k),
      ),
    );
  }
}

class AnaIskele extends StatelessWidget {
  const AnaIskele({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: kontrol.sekme,
      builder: (context, i, _) => Scaffold(
        body: IndexedStack(
          index: i,
          children: [
            TakvimSayfasi(kontrol: kontrol),
            GorevlerSayfasi(kontrol: kontrol),
            AyarlarSayfasi(kontrol: kontrol),
          ],
        ),
        // Etkinlik ekleme düğmesi dış iskelede: SnackBar onu üstüne kaydırır, örtmez.
        floatingActionButton: i == 0
            ? FloatingActionButton(
                tooltip: M.etkinlikEkle,
                onPressed: () => yeniEtkinlikAc(context, kontrol),
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (x) => kontrol.sekme.value = x,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: M.sekmeTakvim,
            ),
            NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: M.sekmeGorevler,
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: M.sekmeAyarlar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Veri açılamadığında gösterilen ekran: hiçbir şey silinmez, üzerine yazılmaz.
class AcilisHataEkrani extends StatelessWidget {
  const AcilisHataEkrani({super.key, required this.mesaj});
  final String mesaj;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
      home: Scaffold(
        appBar: AppBar(title: const Text(M.acilisHataBaslik)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(mesaj),
        ),
      ),
    );
  }
}
