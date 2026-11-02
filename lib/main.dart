// Giriş noktası: veri klasörünü aç, depoyu oku, kontrolü kur, arayüzü başlat.
// Depo okunamazsa (bozuk ya da daha yeni sürüm) boş veriyle BAŞLAMAYIZ: bir sonraki
// kayıt kullanıcı verisini ezerdi; açıklayıcı bir hata ekranı gösterilir.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/kontrol.dart';
import 'core/yerel_zaman.dart';
import 'core/zaman.dart';
import 'platform/bildirim.dart';
import 'platform/dosya_servisi.dart';
import 'platform/kopru.dart';
import 'store/ayarlar.dart';
import 'store/takvim_store.dart';
import 'ui/metin.dart';
import 'ui/uygulama.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final kopru = AndroidKopru();
  try {
    final dizin = await getApplicationSupportDirectory();
    var tzid = 'Europe/Istanbul';
    try {
      tzid = await kopru.saatDilimi();
      konumBul(tzid); // tanınmayan ad varsayılana düşer
    } on FormatException {
      tzid = 'Europe/Istanbul';
    }
    final store = await TakvimStore.ac(File('${dizin.path}/takvim.json'));
    final ayarlar = await Ayarlar.ac(File('${dizin.path}/ayarlar.json'));
    final kontrol = TakvimKontrol(
      store: store,
      ayarlar: ayarlar,
      zaman: YerelZaman(tzid),
      bildirim: YerelBildirimler(),
      dosyalar: SistemDosyaServisi(),
    );
    runApp(TakvimUygulamasi(kontrol: kontrol, kopru: kopru));
    await kontrol.baslat();
  } on SurumHatasi {
    runApp(const AcilisHataEkrani(mesaj: M.acilisSurumHata));
  } on BozukDepoHatasi catch (e) {
    runApp(AcilisHataEkrani(mesaj: M.acilisHata(e.mesaj)));
  } catch (e) {
    runApp(AcilisHataEkrani(mesaj: M.acilisHata(e)));
  }
}
