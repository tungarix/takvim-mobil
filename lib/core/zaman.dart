// Zaman dönüşümlerinin tek doğruluk kaynağı (masaüstündeki core/timeutil.py).
//
// Kural: dosyada ve bellekte her an UTC, `YYYY-MM-DDTHH:MM:SSZ` (saniye
// hassasiyeti). Yerel saat yalnızca tekrar açılımında ve gösterimde, tzid ile.
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Dosya/model biçimi bozuk (bilinmeyen alan değil; eksik, yanlış tip, geçersiz değer).
class BicimHatasi implements Exception {
  BicimHatasi(this.mesaj);
  final String mesaj;
  @override
  String toString() => 'BicimHatasi: $mesaj';
}

/// Dosya sürümü bu uygulamanınkinden büyük: kullanıcıdan uygulamayı güncellemesi istenir.
class SurumHatasi implements Exception {
  SurumHatasi(this.dosyaSurumu);
  final int dosyaSurumu;
  @override
  String toString() =>
      'Bu dosya daha yeni bir Takvim sürümüyle oluşturulmuş (sürüm $dosyaSurumu); uygulamayı güncelleyin.';
}

final _isoDesen = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$');
final _gunDesen = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Sabit genişlikli UTC metnini okur; başka her biçim FormatException.
DateTime utcOku(String s) {
  final m = _isoDesen.firstMatch(s);
  if (m == null) throw FormatException('UTC zamanı YYYY-MM-DDTHH:MM:SSZ olmalı: "$s"');
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final d = DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]);
  // DateTime.utc taşmayı sessizce kaydırır (ay 13 -> ertesi yıl); bunu geçersiz say.
  if (d.year != p[0] || d.month != p[1] || d.day != p[2] || d.hour != p[3] || d.minute != p[4] || d.second != p[5]) {
    throw FormatException('Geçersiz zaman: "$s"');
  }
  return d;
}

String _iki(int n) => n.toString().padLeft(2, '0');

/// UTC'ye çevirip saniyeye keserek yazar (mikrosaniye dosyaya girmez).
String utcYaz(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${_iki(u.month)}-${_iki(u.day)}'
      'T${_iki(u.hour)}:${_iki(u.minute)}:${_iki(u.second)}Z';
}

/// Zamanı saniyeye keser (UTC); eşitlik karşılaştırmaları hep bu hassasiyette.
DateTime saniyeye(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

/// `plan_day` (YYYY-MM-DD) doğrulaması; duvar günüdür, an değil.
String gunDogrula(String s) {
  final m = _gunDesen.firstMatch(s);
  if (m == null) throw FormatException('Gün YYYY-MM-DD olmalı: "$s"');
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), g = int.parse(m.group(3)!);
  final d = DateTime.utc(y, mo, g);
  if (d.year != y || d.month != mo || d.day != g) throw FormatException('Geçersiz gün: "$s"');
  return s;
}

bool _basladi = false;

/// IANA adından saat dilimi; bilinmiyorsa FormatException.
tz.Location konumBul(String tzid) {
  if (!_basladi) {
    tzdata.initializeTimeZones();
    _basladi = true;
  }
  try {
    return tz.getLocation(tzid);
  } catch (_) {
    throw FormatException('Geçersiz IANA saat dilimi: "$tzid"');
  }
}

const _gunMs = 86400000;

// Verilen UTC anındaki ofset (ms).
int _ofset(tz.Location loc, int utcMs) => loc.timeZone(utcMs).offset.inMilliseconds;

/// Duvar saati (UTC işaretli "sahte" tarih-saat) -> gerçek UTC anı.
///
/// zoneinfo/fold=0 ile aynı kural, masaüstüyle sonuç aynı olsun diye:
/// çakışan saatte (sonbahar) İLK geçiş, var olmayan saatte (ilkbahar) geçiş
/// ÖNCESİ ofset kullanılır.
DateTime duvardanUtc(tz.Location loc, DateTime duvar) {
  final w = duvar.millisecondsSinceEpoch;
  // Geçişin iki yanındaki ofsetler; ±1 gün, geçişi sarmalayacak kadar geniş.
  final once = _ofset(loc, w - _gunMs);
  final sonra = _ofset(loc, w + _gunMs);
  int? secilen;
  for (final off in {once, sonra}) {
    if (_ofset(loc, w - off) != off) continue;
    // Çakışmada iki aday da geçerli: daha erken UTC (daha büyük ofset) kazanır.
    if (secilen == null || off > secilen) secilen = off;
  }
  return DateTime.fromMillisecondsSinceEpoch(w - (secilen ?? once), isUtc: true);
}

/// Gerçek UTC anı -> duvar saati ("sahte" UTC işaretli tarih-saat).
DateTime utcdenDuvar(tz.Location loc, DateTime utc) {
  final ms = utc.millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(ms + _ofset(loc, ms), isUtc: true);
}
