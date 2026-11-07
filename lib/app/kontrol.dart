// Uygulamanın tek durum nesnesi (ChangeNotifier; ek durum yönetimi paketi yok).
//
// Veri değişikliklerinin TEK kapısı `yap`: kopyada çalışır, TakvimStore'un atomik
// yazmasından geçer, başarısızsa bellek ve dosya eski hâlinde kalır ve hata
// kullanıcıya görünür. Başarıdan sonra ekranlar yenilenir ve bildirimler yeniden kurulur.
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bildirim_plani.dart';
import '../core/models.dart';
import '../core/veri.dart';
import '../core/yerel_zaman.dart';
import '../core/zaman.dart';
import '../platform/bildirim.dart';
import '../platform/dosya_servisi.dart';
import '../guncelleme/hizmet.dart';
import '../platform/kopru.dart';
import '../store/ayarlar.dart';
import '../store/takvim_store.dart';
import '../sync/export.dart';
import '../sync/import.dart';
import '../sync/wifi_baglanti.dart';
import '../sync/wifi_istemci.dart';
import '../ui/bicim.dart';
import '../ui/metin.dart';

enum Gorunum { gun, hafta, ay }

class TakvimKontrol extends ChangeNotifier {
  TakvimKontrol({
    required this.store,
    required this.ayarlar,
    required this.zaman,
    required this.bildirim,
    required this.dosyalar,
    DateTime Function()? saat,
    this.wifiOturumu = WifiIstemci.yeni,
    this.guncelleyici,
    this.kopru,
  }) : saat = saat ?? DateTime.now,
       gorunum = Gorunum.values.firstWhere(
         (g) => g.name == ayarlar.gorunum,
         orElse: () => Gorunum.gun,
       ),
       temaModu = ValueNotifier(_temaModu(ayarlar.tema)) {
    odakGun = bugun;
  }

  final TakvimStore store;
  final Ayarlar ayarlar;
  final YerelZaman zaman;
  final BildirimServisi bildirim;
  final DosyaServisi dosyalar;
  final DateTime Function() saat;

  /// Otomatik güncelleme (null = bu kurulumda yok, ör. bazı testler). Ağ yalnız kullanıcı izniyle.
  final Guncelleyici? guncelleyici;

  /// Android köprüsü (güncelleme: ağ türü, kurulum izni, APK kurulumu); testler sahtesini verir.
  final Kopru? kopru;

  /// Wi-Fi eşleştirme oturumu üretici; testler sahtesini verir.
  final WifiOturum Function(WifiBaglanti) wifiOturumu;

  /// Bir Wi-Fi eşleştirme akışı sürerken ikinci bağlantı (ör. yeni App Link) başlatılmaz.
  bool wifiMesgul = false;

  final mesajci = GlobalKey<ScaffoldMessengerState>();
  final navigatorAnahtari = GlobalKey<NavigatorState>();

  /// Alt gezinme sekmesi (0 takvim, 1 görevler, 2 ayarlar); arama gibi yerler takvime atlatır.
  final sekme = ValueNotifier<int>(0);

  /// Görünüm tercihi (Ayarlar → Görünüm); uygulama kökü bunu dinler.
  final ValueNotifier<ThemeMode> temaModu;

  static ThemeMode _temaModu(String t) => t == 'koyu'
      ? ThemeMode.dark
      : (t == 'acik' ? ThemeMode.light : ThemeMode.system);

  late DateTime odakGun; // duvar günü
  Gorunum gorunum;

  Veri get veri => store.veri;
  DateTime get simdi => saniyeye(saat());
  DateTime get bugun => gunDuvar(zaman.duvar(simdi));

  // ------------------------------------------------------------ açılış

  /// İlk açılışta varsayılan "Kişisel" takvimini açar (senkron ad eşleşmesi buna bağlı) ve
  /// bildirimleri kurar.
  Future<void> baslat() async {
    if (veri.calendars.isEmpty) {
      await yap(
        (v) => v.addCalendar(varsayilanTakvimAdi, varsayilanTakvimRengi),
      );
    }
    try {
      await bildirim.baslat();
    } catch (e) {
      mesaj(M.bildirimHatasi(e));
    }
    await bildirimleriYenile();
  }

  // ------------------------------------------------------------ yazma

  /// Veriyi değiştirir. Başarılıysa true; hata görünür bir mesajla bildirilir.
  Future<bool> yap(void Function(Veri) f) async {
    try {
      await store.degistir<void>(f);
    } catch (e) {
      mesaj(
        M.kaydedilemedi(e is ArgumentError ? '${e.message}' : e),
        sure: const Duration(seconds: 8),
      );
      return false;
    }
    notifyListeners();
    unawaited(bildirimleriYenile());
    return true;
  }

  /// SnackBar; öncekini kaldırır (üst üste yığılmasın). `eylem` tek adım geri alma içindir.
  void mesaj(
    String metin, {
    String? eylem,
    VoidCallback? eylemFn,
    Duration sure = const Duration(seconds: 5),
  }) {
    final m = mesajci.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(metin),
          duration: sure,
          action: eylem == null
              ? null
              : SnackBarAction(label: eylem, onPressed: eylemFn ?? () {}),
        ),
      );
  }

  // ------------------------------------------------------------ gezinme

  void git(DateTime gun, {Gorunum? gorunum}) {
    odakGun = gunDuvar(gun);
    if (gorunum != null) this.gorunum = gorunum;
    sekme.value = 0;
    notifyListeners();
  }

  void odakAyarla(DateTime gun) {
    if (gunDuvar(gun) == odakGun) return;
    odakGun = gunDuvar(gun);
    notifyListeners();
  }

  /// [t]: 'sistem' | 'koyu' | 'acik'. Ekran hemen değişir, kayıt hatası yalnız bildirilir.
  Future<void> temaDegistir(String t) async {
    temaModu.value = _temaModu(t);
    try {
      await ayarlar.temaYaz(t);
    } catch (e) {
      mesaj(M.hata(e));
    }
  }

  Future<void> gorunumDegistir(Gorunum g) async {
    gorunum = g;
    notifyListeners();
    try {
      await ayarlar.gorunumYaz(g.name);
    } catch (e) {
      mesaj(
        M.hata(e),
      ); // görünüm tercihi kaydedilemedi: veri değil, yine de görünür
    }
  }

  // ------------------------------------------------------------ takvimler

  /// Yeni etkinlik/görev bloğu için takvim: görünür olanlar arasında "Kişisel" yoksa ilk (ada göre).
  Calendar? get varsayilanTakvim {
    final hepsi = veri.calendars.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final gorunur = hepsi.where((c) => c.visible).toList();
    final aday = gorunur.isNotEmpty ? gorunur : hepsi;
    if (aday.isEmpty) return null;
    return aday.firstWhere(
      (c) => c.name == varsayilanTakvimAdi,
      orElse: () => aday.first,
    );
  }

  List<Calendar> get takvimlerSirali =>
      veri.calendars.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  // ------------------------------------------------------------ bildirimler

  /// Gün değişimi gibi dış olaylarda ekranları tazeler.
  void yenile() => notifyListeners();

  bool _izinSoruldu = false;

  Future<void> bildirimleriYenile() async {
    try {
      final plan = bildirimPlani(veri, simdi);
      // Hatırlatıcı olan ilk anda (oturum başına bir kez) bildirim izni istenir;
      // reddedilirse uygulama çalışmaya devam eder, Ayarlar'da uyarı görünür.
      if (plan.isNotEmpty &&
          !_izinSoruldu &&
          bildirim.durum.value.bildirimIzni == false) {
        _izinSoruldu = true;
        await bildirim.izinIste();
      }
      await bildirim.yenile(plan, zaman);
    } catch (e) {
      mesaj(M.bildirimHatasi(e));
    }
  }

  // ------------------------------------------------------------ senkron

  String senkronDosyaAdi() {
    final w = zaman.duvar(simdi);
    String i2(int n) => n.toString().padLeft(2, '0');
    return '${M.dosyaAdiOnek}-${w.year}${i2(w.month)}${i2(w.day)}-${i2(w.hour)}${i2(w.minute)}.takvimsync';
  }

  /// Telefonun tam durumu (`.takvimsync` metni); Wi-Fi'da birleşmeden sonra masaüstüne gider.
  String senkronMetni() => disaAktarMetin(veri, store.cihaz);

  Future<void> senkronGonder() =>
      dosyalar.paylas(disaAktarMetin(veri, store.cihaz), senkronDosyaAdi());

  /// Dosyayı mevcut veriyle birleştirmeyi DENER ve raporu verir; hiçbir şeyi değiştirmez.
  /// Bozuk/büyük sürüm dosyası BicimHatasi/SurumHatasi fırlatır.
  ImportRaporu senkronOnizle(String metin) => importEt(veri, metin).rapor;

  /// Birleştirmeyi uygular. Önizlemeden sonra veri değişmiş olabileceğinden birleştirme
  /// BURADA, güncel veriyle yeniden hesaplanır (bayat önizleme sonucu yazılıp araya giren
  /// düzenlemeyi ezmesin) ve tek atomik yazmayla kalıcı olur.
  Future<ImportRaporu> senkronUygula(String metin) async {
    final sonuc = importEt(veri, metin);
    await store.uygula(sonuc.veri);
    notifyListeners();
    unawaited(bildirimleriYenile());
    try {
      await ayarlar.sonSenkronYaz(simdi);
    } catch (e) {
      mesaj(
        M.hata(e),
      ); // veri uygulandı; yalnızca "son senkron" zamanı yazılamadı
    }
    notifyListeners();
    return sonuc.rapor;
  }

  /// Hata nesnesini kullanıcıya anlaşılır Türkçe metne çevirir.
  static String senkronHataMetni(Object e) {
    if (e is SurumHatasi) return M.surumBuyuk(e.dosyaSurumu);
    if (e is BicimHatasi) {
      return e.mesaj.contains('senkron dosyası değil') ||
              e.mesaj.startsWith('JSON okunamadı')
          ? M.dosyaTakvimSyncDegil
          : M.dosyaBozuk(e.mesaj);
    }
    if (e is FormatException) return M.dosyaOkunamadi;
    return M.hata(e);
  }
}
