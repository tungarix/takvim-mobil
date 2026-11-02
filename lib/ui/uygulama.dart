// Kök uygulama: Material 3 tema (sistem açık/koyu), Türkçe yerelleştirme, alt gezinme,
// yaşam döngüsü (arka plandan dönüşte bildirimleri yeniden kur) ve dışarıdan gelen dosya.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/kontrol.dart';
import '../platform/kopru.dart';
import 'ayarlar_sayfasi.dart';
import 'etkinlik_islemleri.dart';
import 'gorevler_sayfasi.dart';
import 'metin.dart';
import 'senkron_akisi.dart';
import 'takvim_sayfasi.dart';

ThemeData _tema(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), brightness: b),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

class TakvimUygulamasi extends StatefulWidget {
  const TakvimUygulamasi({super.key, required this.kontrol, this.kopru});
  final TakvimKontrol kontrol;

  /// Dışarıdan gelen dosyalar (Paylaş/Birlikte aç); testlerde null olabilir.
  final Kopru? kopru;

  @override
  State<TakvimUygulamasi> createState() => _TakvimUygulamasiDurumu();
}

class _TakvimUygulamasiDurumu extends State<TakvimUygulamasi> with WidgetsBindingObserver {
  TakvimKontrol get k => widget.kontrol;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final kopru = widget.kopru;
    if (kopru != null) {
      kopru.dosyaDinle(_gelen);
      // Uygulama dosyayla açıldıysa ilk karede (gezgin hazırken) önizleme gösterilir.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final g = await kopru.bekleyenDosya();
        if (g != null) await _gelen(g);
      });
    }
  }

  Future<void> _gelen(GelenDosya g) => disaridanGelen(k, metin: g.metin, hata: g.hata);

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: M.uygulamaAdi,
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      scaffoldMessengerKey: k.mesajci,
      navigatorKey: k.navigatorAnahtari,
      home: AnaIskele(kontrol: k),
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
        body: IndexedStack(index: i, children: [
          TakvimSayfasi(kontrol: kontrol),
          GorevlerSayfasi(kontrol: kontrol),
          AyarlarSayfasi(kontrol: kontrol),
        ]),
        // Etkinlik ekleme düğmesi dış iskelede: SnackBar onu üstüne kaydırır, örtmez.
        floatingActionButton: i == 0
            ? FloatingActionButton(tooltip: M.etkinlikEkle, onPressed: () => yeniEtkinlikAc(context, kontrol), child: const Icon(Icons.add))
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (x) => kontrol.sekme.value = x,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: M.sekmeTakvim),
            NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: M.sekmeGorevler),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: M.sekmeAyarlar),
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
        body: Padding(padding: const EdgeInsets.all(24), child: SelectableText(mesaj)),
      ),
    );
  }
}
