// Türkiye resmi tatilleri: kullanıcı verisi DEĞİL, görünüm katmanında üst üste bindirilen salt okunur
// bilgi (Veri'ye, senkron dosyasına, aramaya, hatırlatıcılara girmez). Tablo gömülüdür.
import 'resmi_tatil_veri.dart';

class ResmiTatil {
  const ResmiTatil(this.ad, {required this.yarim, required this.dini});
  final String ad;
  final bool yarim; // arife: öğleden sonra yarım gün
  final bool dini;
}

/// Tablonun kapsadığı yıllar (sabit günler hepsinde tam). Dışında yalnız ulusal günler hesaplanır.
const tatilIlkYil = 2024, tatilSonYil = 2035;

// Ulusal günler 2429 sayılı Kanun'a göre her yıl aynı tarihte: (ay, gün, ad, yarım gün).
const _ulusal = <(int, int, String, bool)>[
  (1, 1, 'Yılbaşı', false),
  (4, 23, 'Ulusal Egemenlik ve Çocuk Bayramı', false),
  (5, 1, 'Emek ve Dayanışma Günü', false),
  (5, 19, "Atatürk'ü Anma, Gençlik ve Spor Bayramı", false),
  (7, 15, 'Demokrasi ve Milli Birlik Günü', false),
  (8, 30, 'Zafer Bayramı', false),
  (10, 28, 'Cumhuriyet Bayramı Arifesi', true),
  (10, 29, 'Cumhuriyet Bayramı', false),
];

String _anahtar(DateTime g) => '${g.year.toString().padLeft(4, '0')}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';

final _tablo = () {
  final m = <String, ResmiTatil>{};
  for (final (tarih, ad, yarim, dini) in resmiTatilVerisi) {
    final onceki = m[tarih];
    // Aynı gün iki kayıt (ör. 23 Nisan + Kurban arifesi): tam gün yarım günü ezer.
    if (onceki != null && !onceki.yarim) continue;
    m[tarih] = ResmiTatil(ad, yarim: yarim, dini: dini);
  }
  return m;
}();

/// `gun` duvar günü (UTC gece yarısı). O gün resmi tatilse kaydı, değilse null.
ResmiTatil? resmiTatilBul(DateTime gun) {
  if (gun.year >= tatilIlkYil && gun.year <= tatilSonYil) return _tablo[_anahtar(gun)];
  for (final (ay, g, ad, yarim) in _ulusal) {
    if (gun.month == ay && gun.day == g) return ResmiTatil(ad, yarim: yarim, dini: false);
  }
  return null;
}
