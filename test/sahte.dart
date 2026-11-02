// Ekran testleri için sahte platform servisleri ve ortak kurulum.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';
import 'package:takvim/core/bildirim_plani.dart';
import 'package:takvim/core/yerel_zaman.dart';
import 'package:takvim/platform/bildirim.dart';
import 'package:takvim/platform/dosya_servisi.dart';
import 'package:takvim/platform/kopru.dart';
import 'package:takvim/store/ayarlar.dart';
import 'package:takvim/store/takvim_store.dart';
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

  @override
  Future<GelenDosya?> bekleyenDosya() async => bekleyen;

  @override
  void dosyaDinle(void Function(GelenDosya) f) => dinleyici = f;

  @override
  Future<String> saatDilimi() async => 'Europe/Istanbul';
}

typedef Kurulum = ({TakvimKontrol k, SahteBildirim bildirim, SahteDosyalar dosyalar, Directory dizin});

/// Gerçek dosya G/Ç'si olan kontrol (TakvimStore atomik yazması test edilsin diye gerçek).
/// Saat sabit: 2026-11-03 13:00 yerel (10:00Z), Salı.
Future<Kurulum> kontrolKurGercek() async {
  final dizin = await Directory.systemTemp.createTemp('takvim_test');
  _dizinler.add(dizin);
  final saat = Saat('2026-11-03T10:00:00Z');
  final store = await TakvimStore.ac(File('${dizin.path}/takvim.json'), saat: saat.call);
  final ayarlar = await Ayarlar.ac(File('${dizin.path}/ayarlar.json'));
  final bildirim = SahteBildirim();
  final dosyalar = SahteDosyalar();
  final k = TakvimKontrol(
    store: store,
    ayarlar: ayarlar,
    zaman: YerelZaman('Europe/Istanbul'),
    bildirim: bildirim,
    dosyalar: dosyalar,
    saat: saat.call,
  );
  await k.baslat();
  return (k: k, bildirim: bildirim, dosyalar: dosyalar, dizin: dizin);
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

Future<Kurulum> kontrolKur(WidgetTester t) async => (await t.runAsync(kontrolKurGercek))!;

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
