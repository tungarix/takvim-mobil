// Cihazın saat dilimiyle "duvar saati" çevirileri (saf Dart).
//
// Duvar saati, UTC işaretli "sahte" DateTime ile taşınır (zaman.dart ile aynı
// kural): 14:30 yerel saat -> DateTime.utc(.., 14, 30). Gerçek an hep UTC'dir.
import 'package:timezone/timezone.dart' as tz;

import 'zaman.dart';

class YerelZaman {
  YerelZaman(this.tzid) : loc = konumBul(tzid);

  final String tzid;
  final tz.Location loc;

  /// Gerçek UTC anı -> yerel duvar saati.
  DateTime duvar(DateTime utc) => utcdenDuvar(loc, utc.toUtc());

  /// Yerel duvar saati -> gerçek UTC anı.
  DateTime utc(DateTime duvar) => duvardanUtc(loc, duvar);

  /// Duvar gününün (00:00) gerçek UTC anı; DST günlerinde 24 saat varsaymaz.
  DateTime gunBasiUtc(DateTime gun) => utc(DateTime.utc(gun.year, gun.month, gun.day));
}

/// Duvar günü (saat sıfırlanmış).
DateTime gunDuvar(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// `n` gün sonrası (taşmalar DateTime.utc'de normalleşir; DST'den etkilenmez).
DateTime gunEkle(DateTime gun, int n) => DateTime.utc(gun.year, gun.month, gun.day + n);

/// Task.planDay biçimi: YYYY-MM-DD.
String gunAnahtari(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime gunOku(String s) {
  gunDogrula(s);
  return DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));
}

/// Haftanın ilk günü (Pazartesi) — masaüstüyle aynı.
DateTime haftaBasi(DateTime gun) => gunEkle(gunDuvar(gun), 1 - gun.weekday);
