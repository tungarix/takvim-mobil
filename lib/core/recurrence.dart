// Tekrar açılımı (masaüstündeki core/recurrence.py'nin karşılığı).
//
// Kritik karar masaüstüyle aynı: açılım UTC'de DEĞİL, etkinliğin kendi saat
// diliminde yapılır; "her gün 09:00" DST geçişinde 09:00 kalır. `rrule` paketi
// saat dilimi bilmez, bu yüzden duvar saatini "sahte UTC" olarak verip her
// sonucu tzid ile gerçek UTC'ye çeviriyoruz.
import 'package:rrule/rrule.dart';

import 'models.dart';
import 'zaman.dart';

/// Bir pencerede materialize edilecek en çok örnek: yoğun (SECONDLY gibi) bir
/// kural uygulamayı kilitlemesin, yarım görünüm kilitli uygulamadan iyidir.
const maksOrnek = 10000;

/// Saatlik/dakikalık kuralda başlangıçtan pencere sonuna kadar gezilecek en çok dönem sayısı.
/// `rrule` paketi pencereye varmak için başlangıçtan tek tek yürür (başlangıç yıl 1 ve FREQ=HOURLY
/// olan bir kayıt ölçümde tek açılımda 37 sn, 1970'ten MINUTELY 59 sn sürdü: uygulama kilitlenirdi).
/// Aşan kural desteklenmeyen sayılır ve tek örneğe düşer (SECONDLY ile aynı yol).
/// shortcut: gerçek takvim kullanımında saatlik/dakikalık tekrar yok; ihtiyaç olursa açıcı
/// başlangıcı pencereye yaklaştıracak şekilde yeniden yazılır.
const maksDonem = 100000;

bool _taranabilir(RecurrenceRule k, DateTime dtstart, DateTime bitis) {
  final dakika = k.frequency == Frequency.minutely ? 1 : (k.frequency == Frequency.hourly ? 60 : 0);
  if (dakika == 0 || (k.count != null && k.count! <= maksDonem)) return true;
  final son = k.until != null && k.until!.isBefore(bitis) ? k.until! : bitis;
  final donem = son.difference(dtstart).inMinutes / (dakika * (k.interval ?? 1));
  return donem <= maksDonem;
}

/// Pencereye somutlaşmış tek örnek. Saklanmaz.
class Occurrence {
  Occurrence({
    required this.eventUid,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.tzid,
    required this.calendarUid,
    required this.isOverride,
    required this.recurring,
    required this.originalStart,
    this.location,
    this.description,
  });

  final String eventUid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String tzid;
  final String calendarUid;
  final bool isOverride;
  final bool recurring;
  /// Serideki ORİJİNAL başlangıç; override kaydının anahtarı bu, `start` taşınmış olabilir.
  final DateTime originalStart;
  final String? location;
  final String? description;
}

final _untilDesen = RegExp(r'UNTIL=([^;\s]+)', caseSensitive: false);

String _p2(int n) => n.toString().padLeft(2, '0');
String _duvarMetni(DateTime w) =>
    '${w.year.toString().padLeft(4, '0')}${_p2(w.month)}${_p2(w.day)}T${_p2(w.hour)}${_p2(w.minute)}${_p2(w.second)}';

/// RRULE metnini `rrule` paketinin beklediği hâle getirir ve çözer.
///
/// UNTIL "duvar saati" olarak verilir (paket saat dilimi bilmiyor): Z'li UNTIL
/// gerçek UTC'dir, tzid'e çevrilir; Z'siz UNTIL zaten yereldir; yalnız tarih
/// ise o günün sonu (masaüstüyle aynı). Çözülemezse null.
RecurrenceRule? _kuralCoz(String metin, String tzid, {bool kati = false}) {
  final loc = konumBul(tzid);
  var satir = metin.split(RegExp(r'[\r\n]+')).map((s) => s.trim()).firstWhere(
        (s) => s.isNotEmpty && (!s.contains(':') || s.toUpperCase().startsWith('RRULE:')),
        orElse: () => '',
      );
  if (satir.isEmpty) return null;
  if (satir.toUpperCase().startsWith('RRULE:')) satir = satir.substring(6);
  // RFC 5545: kural metni büyük/küçük harf duyarsız (dateutil öyle okur); paket yalnız büyük harf biliyor.
  satir = satir.toUpperCase();
  satir = _wkstAyikla(satir);
  if (satir.isEmpty) return null;
  // rrule paketi SECONDLY'de aynı anı tekrar tekrar üretiyor (doğrulandı); takvimde
  // anlamı da yok, desteklenmeyen sayılır.
  if (RegExp(r'FREQ=SECONDLY', caseSensitive: false).hasMatch(satir)) return null;
  satir = satir.replaceAllMapped(_untilDesen, (m) {
    final ham = m.group(1)!.toUpperCase();
    try {
      if (ham.endsWith('Z')) {
        final t = ham.substring(0, ham.length - 1);
        final u = DateTime.utc(int.parse(t.substring(0, 4)), int.parse(t.substring(4, 6)), int.parse(t.substring(6, 8)),
            int.parse(t.substring(9, 11)), int.parse(t.substring(11, 13)), int.parse(t.substring(13, 15)));
        return 'UNTIL=${_duvarMetni(utcdenDuvar(loc, u))}';
      }
      if (ham.length == 8) return 'UNTIL=${ham}T235959';
    } catch (_) {
      return m.group(0)!;
    }
    return m.group(0)!;
  });
  try {
    return RecurrenceRule.fromString('RRULE:$satir');
  } on FormatException catch (e) {
    // Katı kipte yalnız "desteklenmiyor" dışındaki (sözdizimi) hatalar atılır.
    if (kati && !e.message.contains('Unsupported')) rethrow;
    return null;
  } catch (_) {
    return null; // desteklenmeyen kural (ör. WKST=SU): açıcı tek örneğe düşer
  }
}

/// RRULE metni sözdizimi bakımından bozuk mu (ör. `FREQ=BOGUS`, `COUNT=x`)? Geçerli ama açıcının
/// desteklemediği kurallar (ör. aralıklı haftalık + WKST=SU) bozuk SAYILMAZ: bunlar tek örneğe düşer.
bool kuralBozuk(String metin, String tzid) {
  try {
    _kuralCoz(metin, tzid, kati: true);
    return false;
  } on FormatException {
    return true;
  }
}

/// `rrule` paketi yalnız WKST=MO'yu tanıyor; Google gibi üreticiler `WKST=SU` yazar. WKST yalnızca
/// aralıklı haftalık (INTERVAL>1) ve BYWEEKNO'lu kuralın sonucunu değiştirir (RFC 5545); onun dışında
/// WKST atılır ve kural normal açılır. Sonucu değiştirecek ise boş döner: açıcı tek örneğe düşer.
String _wkstAyikla(String satir) {
  final w = RegExp(r'(?:^|;)WKST=([A-Z]{2})(?=;|$)').firstMatch(satir);
  if (w == null || w.group(1) == 'MO') return satir;
  final aralikli = RegExp(r'(?:^|;)INTERVAL=(\d+)').firstMatch(satir);
  final etkili = (satir.contains('FREQ=WEEKLY') && aralikli != null && int.parse(aralikli.group(1)!) > 1) ||
      satir.contains('BYWEEKNO=');
  if (etkili) return '';
  return satir.replaceFirst(RegExp(r'(?:^|;)WKST=[A-Z]{2}(?=;|$)'), '').replaceFirst(RegExp(r'^;'), '');
}

DateTime _kaydir(DateTime d, int yil) => yil == 0
    ? d
    : DateTime.utc(d.year + yil, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);

/// Kural düzeyinde örnek başlangıçları (UTC, sıralı), [after, before] KAPALI.
/// RRULE + RDATE - EXDATE; override'lar uygulanmaz.
List<DateTime> kuralBaslangiclari(Event e, DateTime after, DateTime before) {
  after = after.toUtc();
  before = before.toUtc();
  final loc = konumBul(e.tzid);
  final sonuc = <DateTime>{};
  bool icinde(DateTime u) => !u.isBefore(after) && !u.isAfter(before);

  var kural = e.rrule == null ? null : _kuralCoz(e.rrule!, e.tzid);
  final dtstart = utcdenDuvar(loc, e.start);
  if (kural != null && !_taranabilir(kural, dtstart, utcdenDuvar(loc, before).add(const Duration(days: 1)))) kural = null;
  if (kural == null) {
    if (icinde(e.start)) sonuc.add(e.start);
  } else {
    // Duvar saati sınırları ±1 gün genişletilir; kesin süzme UTC'de yapılır.
    var ws = utcdenDuvar(loc, after).subtract(const Duration(days: 1));
    if (ws.isBefore(dtstart)) ws = dtstart; // paket after >= start ister
    final we = utcdenDuvar(loc, before).add(const Duration(days: 1));
    if (!we.isBefore(ws)) {
      // `rrule` paketi sonuç üretmeyen (imkânsız: ör. BYMONTH=2;BYMONTHDAY=30) kuralda `before`'a
      // bakmaz, takvimin sonuna (yıl 9999) kadar tarar: günlük kuralda tek açılım ~2 sn sürdü.
      // 400 yıl Gregorian takvimin tam döngüsüdür (gün/ay/hafta günü/artık yıl aynı); bütün tarihleri
      // 400'ün katı yıl ileri taşıyıp pencereyi 9999'un dibine yaklaştırınca boş tarama ~100 ms'ye
      // iner. Sonuçlar aynı yıl sayısı kadar geri alınır.
      final yil = ((9998 - we.year) ~/ 400) * 400;
      final bitis = kural.until;
      final k = yil == 0
          ? kural
          : kural.copyWith(
              // Pencereden sonraki UNTIL zaten sonucu değiştirmez; atılır (taşıma yılı 9999'u aşmasın).
              until: bitis != null && bitis.isBefore(we) ? _kaydir(bitis, yil) : null,
              clearUntil: bitis == null || !bitis.isBefore(we),
            );
      for (final w in k
          .getInstances(start: _kaydir(dtstart, yil), after: _kaydir(ws, yil), includeAfter: true, before: _kaydir(we, yil), includeBefore: true)
          .take(maksOrnek)) {
        final u = duvardanUtc(loc, _kaydir(w, -yil));
        if (icinde(u)) sonuc.add(u);
      }
    }
  }
  for (final r in e.rdate) {
    if (icinde(r)) sonuc.add(r);
  }
  sonuc.removeAll(e.exdate);
  return sonuc.toList()..sort();
}

Occurrence _duz(Event e, DateTime start) => Occurrence(
      eventUid: e.uid,
      title: e.title,
      start: start,
      end: start.add(e.duration),
      allDay: e.allDay,
      tzid: e.tzid,
      calendarUid: e.calendarUid,
      isOverride: false,
      recurring: e.isRecurring,
      location: e.location,
      description: e.description,
      originalStart: start,
    );

/// Override uygulanmış örnek; verilmeyen alanlar seriden miras alınır.
/// Bitiş başlangıçtan önceye düşerse (yalnız new_end verilmişse) null.
Occurrence? _degisik(Event e, DateTime orijinal, EventOverride ov) {
  final start = ov.newStart ?? orijinal;
  final end = ov.newEnd ?? start.add(e.duration);
  if (end.isBefore(start)) return null;
  return Occurrence(
    eventUid: e.uid,
    title: ov.newTitle ?? e.title,
    start: start,
    end: end,
    allDay: e.allDay,
    tzid: e.tzid,
    calendarUid: e.calendarUid,
    isOverride: true,
    recurring: e.isRecurring,
    location: ov.newLocation ?? e.location,
    description: e.description,
    originalStart: orijinal,
  );
}

// Yarı açık kesişim: [start, end) ile [ws, we). Bitişi pencere başına denk
// gelen örnek içeride değil; gün görünümlerinin sızmaması bu seçime bağlı.
bool _kesisir(Occurrence o, DateTime ws, DateTime we) => o.start.isBefore(we) && o.end.isAfter(ws);

/// Etkinliği (kendi override'larıyla) pencere içindeki örneklerine açar;
/// `start`'a göre sıralı.
List<Occurrence> expand(Event e, DateTime windowStart, DateTime windowEnd) {
  final ws = windowStart.toUtc(), we = windowEnd.toUtc();
  if (!we.isAfter(ws)) return [];

  final ovHarita = {for (final o in e.overrides) o.originalStart: o};
  final ham = (e.rrule != null || e.rdate.isNotEmpty || e.exdate.isNotEmpty)
      // Pencereden ÖNCE başlayıp içine sarkanları kaçırmamak için süre kadar geri.
      ? kuralBaslangiclari(e, ws.subtract(e.duration), we)
      : [e.start];

  final out = <Occurrence>[];
  final islenen = <DateTime>{};
  for (final s in ham) {
    final ov = ovHarita[s];
    Occurrence? occ;
    if (ov != null) {
      islenen.add(s);
      if (ov.cancelled) continue;
      occ = _degisik(e, s, ov);
    } else {
      occ = _duz(e, s);
    }
    if (occ != null && _kesisir(occ, ws, we)) out.add(occ);
  }

  // Kaydırılmış örnek pencere DIŞINDAN içeri girmiş olabilir: orijinali
  // sorgulanan aralığa düşmediği için yukarıdaki döngü onu görmedi.
  for (final MapEntry(key: orijinal, value: ov) in ovHarita.entries) {
    if (islenen.contains(orijinal) || ov.cancelled || ov.newStart == null) continue;
    final occ = _degisik(e, orijinal, ov);
    if (occ == null || !_kesisir(occ, ws, we)) continue;
    if (!_seriOrnegi(e, orijinal)) continue; // seriye ait olmayan hayalet override
    out.add(occ);
  }
  out.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    final d = a.end.compareTo(b.end);
    return d != 0 ? d : a.eventUid.compareTo(b.eventUid);
  });
  return out;
}

bool _seriOrnegi(Event e, DateTime baslangic) {
  if (e.rrule == null && e.rdate.isEmpty && e.exdate.isEmpty) return baslangic == e.start;
  return kuralBaslangiclari(e, baslangic, baslangic).contains(baslangic);
}
