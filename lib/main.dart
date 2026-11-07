// Giriş noktası: veri klasörünü aç, depoyu oku, kontrolü kur, arayüzü başlat.
// Depo okunamazsa (bozuk ya da daha yeni sürüm) boş veriyle BAŞLAMAYIZ: bir sonraki
// kayıt kullanıcı verisini ezerdi; açıklayıcı bir hata ekranı gösterilir.
import 'dart:io';

import 'package:flutter/material.dart';

import 'app/kontrol.dart';
import 'core/yerel_zaman.dart';
import 'core/zaman.dart';
import 'guncelleme/ag.dart';
import 'guncelleme/hizmet.dart';
import 'platform/bildirim.dart';
import 'platform/dosya_servisi.dart';
import 'platform/kopru.dart';
import 'store/ayarlar.dart';
import 'store/takvim_store.dart';
import 'surum.dart';
import 'ui/metin.dart';
import 'ui/uygulama.dart';

/// YALNIZ geliştirme/uçtan uca deneme: `--dart-define=GUNCELLEME_TABAN=http://10.0.2.2:PORT` derlemesi
/// güncelleme denetimini yerel sahte bir GitHub'a yöneltir. Boşsa (release.yml hiç tanımlamaz) üretim
/// davranışı: yalnız `api.github.com`. Çalışma zamanında değiştirilemez (derleme sabiti).
const _guncellemeTaban = String.fromEnvironment('GUNCELLEME_TABAN');

/// Tanım yalnız yerel/emülatör adreslerinde kabul edilir (release derlemesine yanlışlıkla verilse bile
/// düz HTTP ile rastgele sunucuya güvenmez).
bool _taban() {
  if (_guncellemeTaban.isEmpty) return false;
  final host = Uri.tryParse(_guncellemeTaban)?.host;
  return host == '10.0.2.2' || host == 'localhost' || host == '127.0.0.1';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final kopru = AndroidKopru();
  try {
    final dizinler = await kopru.dizinler();
    var tzid = 'Europe/Istanbul';
    try {
      tzid = await kopru.saatDilimi();
      konumBul(tzid); // tanınmayan ad varsayılana düşer
    } on FormatException {
      // Veritabanında olmayan ad (ör. "GMT"): sapma sıfırsa Etc/UTC, değilse masaüstüyle aynı varsayılan.
      tzid = DateTime.now().timeZoneOffset == Duration.zero ? 'Etc/UTC' : 'Europe/Istanbul';
    }
    final store = await TakvimStore.ac(File('${dizinler.veri}/takvim.json'));
    final ayarlar = await Ayarlar.ac(File('${dizinler.veri}/ayarlar.json'));
    final kontrol = TakvimKontrol(
      store: store,
      ayarlar: ayarlar,
      zaman: YerelZaman(tzid),
      bildirim: YerelBildirimler(),
      dosyalar: SistemDosyaServisi(dizinler.gecici),
      kopru: kopru,
      guncelleyici: Guncelleyici(
        ayarlar: ayarlar,
        klasor: Directory('${dizinler.gecici}/guncelleme'),
        surum: surum,
        ag: !_taban()
            ? null
            : Ag(surum: surum, apiTaban: _guncellemeTaban, ekSunucular: {Uri.parse(_guncellemeTaban).host}),
      ),
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
