// Seri bölme (masaüstündeki store/repo.py `_seriyi_bol`un portu, AGENTS 57-58).
//
// "Bu ve sonrakiler" = RFC 5545 RANGE=THISANDFUTURE: eski seri [.., split),
// yeni seri [split, ..). Saf işlev: durum yazmaz. Kurallar masaüstüyle aynı:
//  - COUNT'lu kuralda sayaç KURAL düzeyinde bölünür (EXDATE düşülmeden); görünür
//    sayıya bakmak dışlanmış örnek kadar eski tarafı kısa yazıp örnek kaybettirir.
//  - COUNT'suz kuralda eskiye UNTIL (bölmeden 1 sn önce, UTC) yazılır; var olan
//    UNTIL değiştirilir, eklenmez (çift UNTIL'de sonuncu kazanır, sınır yanlış olur).
//  - Yeni seri DESEN ÜSTÜNDEN başlar: bölme anı RDATE ise sonraki kural örneği,
//    kural metni değişmez; INTERVAL fazı ve saat ızgarası kaymaz.
//  - RDATE/EXDATE ve override'lar bölme anına göre iki tarafa ayrılır.
import 'models.dart';
import 'recurrence.dart';
import 'zaman.dart';

class SeriBolSonucu {
  const SeriBolSonucu(this.eski, this.yeni);
  final Event eski;
  final Event yeni;
}

const _uzak = Duration(days: 36500);

/// Gövdesi tek RRULE satırı olan kuralı döndürür (RRULE: önekli ya da çıplak
/// satır kuraldır). Birden çok kural varsa bölünemez.
String _tekKural(String rrule) {
  final kurallar = <String>[];
  for (final satir in rrule.split(RegExp(r'[\r\n]+'))) {
    final s = satir.trim();
    if (s.isEmpty) continue;
    final i = s.indexOf(':');
    if (i >= 0) {
      if (s.substring(0, i).trim().toUpperCase().split(';').first != 'RRULE') continue;
      kurallar.add(s.substring(i + 1));
    } else {
      kurallar.add(s);
    }
  }
  if (kurallar.length != 1) throw ArgumentError('çok kurallı seriler bölünemez');
  return kurallar.first;
}

/// Gövdesi `eski` olan İLK RRULE satırını `yeni` ile değiştirir (satır bazlı:
/// kural gövdesi metnin başka yerinde de geçebilir).
String _satirDegistir(String metin, String eski, String yeni) {
  final cikti = <String>[];
  var yapildi = false;
  for (final satir in metin.split(RegExp(r'\r?\n'))) {
    final s = satir.trim();
    var govde = s, onek = '';
    final i = s.indexOf(':');
    if (i >= 0) {
      final p = s.substring(0, i);
      if (p.trim().toUpperCase().split(';').first != 'RRULE') {
        cikti.add(satir);
        continue;
      }
      govde = s.substring(i + 1);
      onek = '$p:';
    }
    if (!yapildi && govde == eski) {
      cikti.add('$onek$yeni');
      yapildi = true;
    } else {
      cikti.add(satir);
    }
  }
  return cikti.join('\n');
}

Event _kopya(
  Event e, {
  required String uid,
  required DateTime start,
  String? rrule,
  required Iterable<DateTime> rdate,
  required Iterable<DateTime> exdate,
  required Iterable<EventOverride> overrides,
  required DateTime createdAt,
  required DateTime updatedAt,
}) =>
    Event(
      uid: uid, calendarUid: e.calendarUid, title: e.title, description: e.description, location: e.location,
      start: start, end: ornekBitisi(e, start), tzid: e.tzid, allDay: e.allDay, rrule: rrule, rdate: rdate,
      exdate: exdate, reminders: e.reminders, overrides: overrides, createdAt: createdAt, updatedAt: updatedAt,
    );

/// Kural örnekleri (RDATE/EXDATE'siz yalın kural), [after, before].
List<DateTime> _yalinOrnekler(Event e, DateTime after, DateTime before) => kuralBaslangiclari(
      _kopya(e, uid: e.uid, start: e.start, rrule: e.rrule, rdate: const [], exdate: const [], overrides: const [],
          createdAt: e.createdAt, updatedAt: e.updatedAt),
      after,
      before,
    );

/// `at` anındaki ya da sonrasındaki ilk KURAL örneği (RDATE/EXDATE yok sayılır).
DateTime? _sonrakiKuralBasi(Event e, DateTime at) {
  final l = _yalinOrnekler(e, at, at.add(const Duration(days: 3660)));
  return l.isEmpty ? null : l.first;
}

String _untilMetni(DateTime u) {
  String i2(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${i2(u.month)}${i2(u.day)}T${i2(u.hour)}${i2(u.minute)}${i2(u.second)}Z';
}

/// Seriyi `splitUtc` (bir örneğin ORİJİNAL başlangıcı) noktasında böler.
/// İlk örnekten bölünemez ("tümünü düzenle"); hata ArgumentError.
SeriBolSonucu seriBol(Event e, DateTime splitUtc, {required String yeniUid, required DateTime simdi}) {
  final split = saniyeye(splitUtc);
  if (!e.isRecurring) throw ArgumentError('tekrarsız seri bölünemez');

  void dogrula(List<DateTime> baslangiclar) {
    if (!baslangiclar.contains(split)) throw ArgumentError('bölme noktası serinin bir örneği olmalı');
    if (!baslangiclar.any((s) => s.isBefore(split))) throw ArgumentError('ilk örnekten bölünemez; tümünü düzenle');
  }

  String? eskiRrule, yeniRrule;
  late DateTime yeniBas;

  if (e.rrule != null) {
    final kural = _tekKural(e.rrule!);
    final sayi = RegExp(r'COUNT=(\d+)', caseSensitive: false).firstMatch(kural);
    String eskiGovde, yeniGovde;
    if (sayi != null) {
      dogrula(kuralBaslangiclari(e, e.start, e.start.add(_uzak)));
      final kuralOrnekleri = _yalinOrnekler(e, e.start, e.start.add(_uzak));
      final onceKural = kuralOrnekleri.where((s) => s.isBefore(split)).length;
      final yeniSayi = kuralOrnekleri.length - onceKural;
      final sonraki = kuralOrnekleri.where((s) => !s.isBefore(split));
      yeniBas = sonraki.isEmpty ? split : sonraki.first;
      String sayac(int n) => kural.replaceAllMapped(RegExp(r'COUNT=\d+', caseSensitive: false), (_) => 'COUNT=$n');
      eskiGovde = onceKural <= 0 ? '' : sayac(onceKural);
      yeniGovde = yeniSayi <= 0 ? '' : sayac(yeniSayi);
    } else {
      dogrula(kuralBaslangiclari(e, e.start, split));
      final sinir = 'UNTIL=${_untilMetni(split.subtract(const Duration(seconds: 1)))}';
      eskiGovde = RegExp(r'UNTIL=', caseSensitive: false).hasMatch(kural)
          ? kural.replaceAllMapped(RegExp(r'UNTIL=[^;]+', caseSensitive: false), (_) => sinir)
          : '$kural;$sinir';
      yeniGovde = kural;
      yeniBas = e.rdate.contains(split) ? (_sonrakiKuralBasi(e, split) ?? split) : split;
    }
    eskiRrule = eskiGovde.isEmpty ? null : _satirDegistir(e.rrule!, kural, eskiGovde);
    yeniRrule = yeniGovde.isEmpty ? null : _satirDegistir(e.rrule!, kural, yeniGovde);
  } else {
    // Yalnız RDATE: liste sonlu, kural/faz sorunu yok.
    dogrula(kuralBaslangiclari(e, e.start, e.start.add(_uzak)));
    yeniBas = split;
  }

  final eski = _kopya(
    e,
    uid: e.uid,
    start: e.start,
    rrule: eskiRrule,
    rdate: e.rdate.where((d) => d.isBefore(split)),
    exdate: e.exdate.where((d) => d.isBefore(split)),
    overrides: e.overrides.where((o) => o.originalStart.isBefore(split)),
    createdAt: e.createdAt,
    updatedAt: simdi,
  );
  // RRULE'lu seride bölme anı RDATE ise yeni tarafta TUTULUR (>=): yeni DTSTART desen
  // üstünde olduğu için kural onu üretmeyebilir; RRULE'suzda DTSTART zaten bölme anıdır (>).
  final yeni = _kopya(
    e,
    uid: yeniUid,
    start: yeniBas,
    rrule: yeniRrule,
    rdate: e.rdate.where((d) => e.rrule == null ? d.isAfter(split) : !d.isBefore(split)),
    exdate: e.exdate.where((d) => !d.isBefore(split)),
    overrides: e.overrides.where((o) => !o.originalStart.isBefore(split)),
    createdAt: simdi,
    updatedAt: simdi,
  );
  return SeriBolSonucu(eski, yeni);
}
