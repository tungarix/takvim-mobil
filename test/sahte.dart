// Ekran testleri için sahte platform servisleri ve ortak kurulum.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';
import 'package:takvim/core/bildirim_plani.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/core/yerel_zaman.dart';
import 'package:takvim/guncelleme/ag.dart';
import 'package:takvim/guncelleme/hizmet.dart';
import 'package:takvim/guncelleme/saf.dart';
import 'package:takvim/platform/bildirim.dart';
import 'package:takvim/platform/dosya_servisi.dart';
import 'package:takvim/platform/kopru.dart';
import 'package:takvim/store/ayarlar.dart';
import 'package:takvim/store/takvim_store.dart';
import 'package:takvim/sync/sha256.dart';
import 'package:takvim/sync/wifi_baglanti.dart';
import 'package:takvim/sync/wifi_istemci.dart';
import 'package:takvim/ui/uygulama.dart';

import 'yardimci.dart';

class SahteBildirim extends BildirimServisi {
  final planlar = <List<PlanliBildirim>>[];
  bool izinIstendi = false;
  bool izinVerildi = true;

  @override
  Future<void> baslat() async {
    durum.value = BildirimDurumu(bildirimIzni: izinVerildi, tamZamanli: izinVerildi);
  }

  @override
  Future<void> izinIste() async {
    izinIstendi = true;
    durum.value = const BildirimDurumu(bildirimIzni: true, tamZamanli: true);
  }

  @override
  Future<void> yenile(List<PlanliBildirim> plan, YerelZaman zaman) async {
    planlar.add(plan);
    durum.value = durum.value.kopya(planli: plan.length);
  }
}

class SahteDosyalar implements DosyaServisi {
  String? secilecek;
  final paylasilan = <(String, String)>[];

  @override
  Future<String?> senkronDosyasiSec() async => secilecek;

  @override
  Future<void> paylas(String metin, String dosyaAdi) async => paylasilan.add((dosyaAdi, metin));
}

class SahteKopru implements Kopru {
  GelenDosya? bekleyen;
  void Function(GelenDosya)? dinleyici;
  String? bekleyenBag;
  void Function(String)? baglantiDinleyici;

  String ag = 'wifi';
  bool izin = true;
  final kurulanlar = <String>[];
  var izinAcildi = 0;
  Object? kurHatasi;

  @override
  Future<String> agTuru() async => ag;

  @override
  Future<bool> kurulumIzniVar() async => izin;

  @override
  Future<void> kurulumIzniAc() async => izinAcildi++;

  @override
  Future<void> apkKur(String yol) async {
    if (kurHatasi != null) throw kurHatasi!;
    kurulanlar.add(yol);
  }

  @override
  Future<String?> bekleyenBaglanti() async => bekleyenBag;

  @override
  void baglantiDinle(void Function(String) f) => baglantiDinleyici = f;

  @override
  Future<GelenDosya?> bekleyenDosya() async => bekleyen;

  @override
  void dosyaDinle(void Function(GelenDosya) f) => dinleyici = f;

  @override
  Future<String> saatDilimi() async => 'Europe/Istanbul';

  @override
  Future<({String veri, String gecici})> dizinler() async => (veri: '.', gecici: '.');
}

/// Wi-Fi oturumu sahtesi: ağa çıkmaz; çağrıları kaydeder, hatayı/yanıtı teste göre verir.
class SahteWifi implements WifiOturum {
  SahteWifi({this.durum = '', this.bekle, this.helloHatasi, this.durumHatasi, this.gonderHatasi, this.rapor = const WifiRapor(added: 2, updated: 1)});
  final String durum;

  /// Verilirse durumAl bu tamamlanana dek bekler (ilerleme penceresi açık kalır); kapat() iptal hatasıyla bitirir.
  final Completer<String>? bekle;
  final WifiHatasi? helloHatasi, durumHatasi, gonderHatasi;
  final WifiRapor rapor;
  final cagrilar = <String>[];
  final gonderilen = <String>[];
  var kapatildi = false;

  @override
  Future<WifiHello> hello() async {
    cagrilar.add('hello');
    if (helloHatasi != null) throw helloHatasi!;
    return const WifiHello(ad: 'PC', uygulama: 'desktop 1.9.0');
  }

  @override
  Future<String> durumAl() async {
    cagrilar.add('al');
    if (durumHatasi != null) throw durumHatasi!;
    if (bekle != null) return bekle!.future;
    return durum;
  }

  @override
  Future<WifiRapor> durumGonder(String metin) async {
    cagrilar.add('gonder');
    gonderilen.add(metin);
    if (gonderHatasi != null) throw gonderHatasi!;
    return rapor;
  }

  @override
  void kapat() {
    kapatildi = true;
    if (bekle != null && !bekle!.isCompleted) bekle!.completeError(const WifiHatasi(WifiHataTuru.iptal));
  }
}

/// Güncelleme ağı sahtesi: gerçek ağa çıkmaz, çağrıları sayar. `apk` indirilecek içerik.
class SahteAg extends Ag {
  SahteAg({this.teklif, this.hata, List<int>? apk, this.ozetYanlis = false})
      : apk = apk ?? List<int>.generate(2048, (i) => i % 251),
        super(depo: 'tungarix/takvim-mobil', surum: '0.3.0');

  /// Denetimde bulunacak sürüm (null = teklif yok).
  Yayin? teklif;
  GuncellemeHatasi? hata;
  final List<int> apk;
  bool ozetYanlis;
  var denetimler = 0;
  var indirmeler = 0;

  static Yayin yayin(String surum, int boyut) => Yayin(
        surum: surum,
        apkUrl: 'https://github.com/tungarix/takvim-mobil/releases/download/v$surum/Takvim-$surum.apk',
        apkBoyut: boyut,
        ozetUrl: 'https://github.com/tungarix/takvim-mobil/releases/download/v$surum/SHA256SUMS.txt',
        sayfaUrl: 'https://github.com/tungarix/takvim-mobil/releases/tag/v$surum',
      );

  @override
  Future<SonYayinSonucu> sonYayin([String? etag]) async {
    denetimler++;
    if (hata != null) throw hata!;
    return teklif == null ? ('yok', null, null) : ('yeni', teklif, '"e1"');
  }

  @override
  Future<String> metinIndir(String url) async =>
      '${ozetYanlis ? '0' * 64 : onaltilik(sha256(apk))}  Takvim-${teklif!.surum}.apk\n';

  @override
  Future<String> indir(String url, File hedef, int beklenenBoyut, {void Function(int alinan)? ilerleme}) async {
    indirmeler++;
    await hedef.writeAsBytes(apk);
    ilerleme?.call(apk.length);
    return onaltilik(sha256(apk));
  }
}

typedef Kurulum = ({TakvimKontrol k, SahteBildirim bildirim, SahteDosyalar dosyalar, Directory dizin, Guncelleyici? guncelleyici});

/// Gerçek dosya G/Ç'si olan kontrol (TakvimStore atomik yazması test edilsin diye gerçek).
/// Saat sabit: 2026-11-03 13:00 yerel (10:00Z), Salı.
Future<Kurulum> kontrolKurGercek({WifiOturum Function(WifiBaglanti)? wifi, SahteAg? ag, SahteKopru? kopru}) async {
  final dizin = await Directory.systemTemp.createTemp('takvim_test');
  _dizinler.add(dizin);
  final saat = Saat('2026-11-03T10:00:00Z');
  final store = await TakvimStore.ac(File('${dizin.path}/takvim.json'), saat: saat.call);
  final ayarlar = await Ayarlar.ac(File('${dizin.path}/ayarlar.json'));
  final bildirim = SahteBildirim();
  final dosyalar = SahteDosyalar();
  final guncelleyici = ag == null ? null : Guncelleyici(ayarlar: ayarlar, klasor: Directory('${dizin.path}/g'), surum: '0.3.0', ag: ag, saat: saat.call);
  final k = TakvimKontrol(
    store: store,
    ayarlar: ayarlar,
    zaman: YerelZaman('Europe/Istanbul'),
    bildirim: bildirim,
    dosyalar: dosyalar,
    saat: saat.call,
    wifiOturumu: wifi ?? WifiIstemci.yeni,
    guncelleyici: guncelleyici,
    kopru: kopru,
  );
  await k.baslat();
  return (k: k, bildirim: bildirim, dosyalar: dosyalar, dizin: dizin, guncelleyici: guncelleyici);
}

final _dizinler = <Directory>[];

/// Dosya sonunda (tearDownAll) geçici klasörleri siler. Test başına addTearDown kullanılmaz:
/// runAsync içinde ya da sahte-zamanlı bölgede kaydedilen temizlik testi "tamamlanmadı" yapıyordu.
Future<void> dizinleriTemizle() async {
  for (final d in _dizinler) {
    try {
      await d.delete(recursive: true);
    } on FileSystemException {
      // Windows: bir tutamaç açıksa silinemez; geçici klasörü sistem temizler.
    }
  }
  _dizinler.clear();
}

Future<Kurulum> kontrolKur(WidgetTester t, {WifiOturum Function(WifiBaglanti)? wifi, SahteAg? ag, SahteKopru? kopru}) async =>
    (await t.runAsync(() => kontrolKurGercek(wifi: wifi, ag: ag, kopru: kopru)))!;

Future<Kurulum> kontrolKurDuz() => kontrolKurGercek();

/// Dosya G/Ç'si gerçek zamanlı biter ama devamı sahte-zamanlı bölgede kalır: bekleme sırasında
/// gerçek zamanı ilerletip sahte mikro görevleri de pompalamak gerekir.
Future<void> bekle(WidgetTester t, bool Function() kosul) async {
  for (var i = 0; i < 300 && !kosul(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 400));
}

/// Gerçek G/Ç gerektiren bir eylemi (koşul sağlanana dek) bekler.
Future<void> gercekZaman(WidgetTester t, Future<void> Function() is_) async {
  await t.runAsync(is_);
  await t.pump();
}

/// Ayarlar listesinin tamamı ekrana sığsın (kaydırma gerektirmeden dokunulabilsin).
void uzunEkran(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void telefonBoyutu(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> uygulamaAc(WidgetTester t, TakvimKontrol k, {SahteKopru? kopru}) async {
  await t.pumpWidget(TakvimUygulamasi(kontrol: k, kopru: kopru));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Event etkinlik(TakvimKontrol k, String uid, String baslik, {String? rrule, List<int> hatirlatici = const []}) => Event(
      uid: uid,
      calendarUid: k.varsayilanTakvim!.uid,
      title: baslik,
      start: t('2026-11-03T11:00:00Z'), // 14:00 yerel
      end: t('2026-11-03T12:00:00Z'),
      tzid: 'Europe/Istanbul',
      rrule: rrule,
      reminders: hatirlatici,
      createdAt: t('2026-11-03T10:00:00Z'),
      updatedAt: t('2026-11-03T10:00:00Z'),
    );

Future<void> ekle(WidgetTester tester, TakvimKontrol k, void Function(Veri) f) async {
  await tester.runAsync(() => k.yap(f));
  await tester.pump();
}

String ornekDosya() => File('test/fixtures/senkron-ornek.takvimsync').readAsStringSync();

/// Önceki (çöken ya da yarıda kesilen) koşulardan kalan geçici klasörleri siler: tearDownAll
/// süreç çökünce hiç çalışmaz, klasörler %TEMP%'te birikirdi.
Future<void> eskiDizinleriTemizle() async {
  final sinir = DateTime.now().subtract(const Duration(minutes: 10));
  await for (final e in Directory.systemTemp.list()) {
    if (e is Directory && e.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('takvim_test') && e.statSync().modified.isBefore(sinir)) {
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // başka bir koşu kullanıyor olabilir; sonraki sefer silinir
      }
    }
  }
}
