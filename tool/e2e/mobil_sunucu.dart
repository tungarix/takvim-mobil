// E2E harness: mobil cekirdegini (lib/core + lib/sync + lib/store) satir satir JSON
// komutlarla suren kucuk sunucu. Python orkestratoru (e2e.py) stdin'den komut yollar,
// stdout'tan yanit okur. Flutter'a bagli degil: `dart run tool/e2e/mobil_sunucu.dart`.
//
// Protokol: her satir bir JSON nesnesi. Istek: {"id":1,"op":"...","k":"<cihaz>",...}.
// Yanit: {"id":1,"ok":true,"veri":...} ya da {"id":1,"ok":false,"tur":"BicimHatasi","hata":"..."}.
// Yanitlar ASCII'ye kacirilir (Windows konsol kod sayfasindan bagimsiz olsun diye).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:takvim/core/models.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/store/takvim_store.dart';
import 'package:takvim/sync/export.dart';
import 'package:takvim/sync/import.dart';

class Cihaz {
  Cihaz(this.ofset);
  Duration ofset;
  Event? sonSilinen; // "geri al" icin (arayuzdeki silme-geri alma)
  late TakvimStore store;
  DateTime saat() => DateTime.now().toUtc().add(ofset);
}

final cihazlar = <String, Cihaz>{};

String ascii(String s) {
  final b = StringBuffer();
  for (final u in s.codeUnits) {
    b.write(u < 128 ? String.fromCharCode(u) : '\\u${u.toRadixString(16).padLeft(4, '0')}');
  }
  return b.toString();
}

Map<String, dynamic> raporJson(ImportRaporu r) {
  Map<String, int> tur(TurSayaci t) => {'added': t.added, 'updated': t.updated, 'deleted': t.deleted, 'skipped': t.skipped};
  return {
    'added': r.added,
    'updated': r.updated,
    'deleted': r.deleted,
    'skipped': r.skipped,
    'calendar': tur(r.calendar),
    'event': tur(r.event),
    'task': tur(r.task),
  };
}

Map<String, dynamic> olusumJson(dynamic o) => {
      'event_uid': o.eventUid,
      'calendar_uid': o.calendarUid,
      'title': o.title,
      'start_utc': utcYaz(o.start),
      'end_utc': utcYaz(o.end),
      'all_day': o.allDay,
      'location': o.location,
      'is_override': o.isOverride,
      'original_start_utc': utcYaz(o.originalStart),
    };

Event etkinlikBirlestir(Event e, Map<String, dynamic> alanlar) {
  final j = Map<String, dynamic>.from(e.toJson())..addAll(alanlar);
  return Event.fromJson(j);
}

Future<Object?> calistir(String op, Map<String, dynamic> m) async {
  if (op == 'ac') {
    final c = Cihaz(Duration(seconds: (m['ofset'] as int?) ?? 0));
    c.store = await TakvimStore.ac(File(m['yol'] as String), saat: c.saat, cihazAdi: m['ad'] as String? ?? 'Mobil');
    cihazlar[m['k'] as String] = c;
    return {'cihaz_id': c.store.cihaz.id};
  }
  final c = cihazlar[m['k']] ?? (throw StateError('cihaz acik degil: ${m['k']}'));
  final s = c.store;
  switch (op) {
    case 'ofset':
      c.ofset = Duration(seconds: m['saniye'] as int);
      return null;
    case 'takvim_ekle':
      return s.degistir((v) => v.addCalendar(m['name'] as String, m['color'] as String, visible: (m['visible'] as bool?) ?? true, uid: m['uid'] as String?).uid);
    case 'takvim_duzenle':
      await s.degistir<void>((v) {
        final k = v.calendars[m['uid']] ?? (throw StateError('takvim yok'));
        v.updateCalendar(k.copyWith(name: m['name'] as String?, color: m['color'] as String?, visible: m['visible'] as bool?));
      });
      return null;
    case 'takvim_sil':
      return s.degistir((v) => v.deleteCalendar(m['uid'] as String));
    case 'etkinlik_ekle':
      // Override'lar UI'daki gibi putOverride ile (new_end bos ise etkinlik suresinden doldurulur).
      return s.degistir((v) {
        final j = Map<String, dynamic>.from(m['event'] as Map);
        final ovler = (j['overrides'] as List).map(EventOverride.fromJson).toList();
        j['overrides'] = <Object?>[];
        final e = v.addEvent(Event.fromJson(j));
        for (final o in ovler) {
          v.putOverride(e.uid, o);
        }
        return e.uid;
      });
    case 'etkinlik_duzenle':
      await s.degistir<void>((v) {
        final e = v.events[m['uid']] ?? (throw StateError('etkinlik yok'));
        v.updateEvent(etkinlikBirlestir(e, (m['alanlar'] as Map).cast<String, dynamic>()));
      });
      return null;
    case 'etkinlik_sil':
      return s.degistir((v) => v.deleteEvent(m['uid'] as String));
    case 'etkinlik_sil_geri_alinabilir':
      await s.degistir<void>((v) {
        c.sonSilinen = v.events[m['uid']];
        v.deleteEvent(m['uid'] as String);
      });
      return null;
    case 'geri_al':
      return s.degistir((v) => v.addEvent(c.sonSilinen ?? (throw StateError('geri alinacak yok'))).uid);
    case 'override_koy':
      return s.degistir((v) => v.putOverride(m['uid'] as String, EventOverride.fromJson(m['ov'])));
    case 'override_sil':
      return s.degistir((v) => v.deleteOverride(m['uid'] as String, utcOku(m['original_start_utc'] as String)));
    case 'hatirlatici_ekle':
      return s.degistir((v) => v.addReminder(m['uid'] as String, m['dakika'] as int));
    case 'hatirlatici_sil':
      return s.degistir((v) => v.deleteReminder(m['uid'] as String, m['dakika'] as int));
    case 'gorev_ekle':
      return s.degistir((v) => v.addTask(m['title'] as String, notes: m['notes'] as String?, uid: m['uid'] as String?).uid);
    case 'gorev_guncelle':
      return s.degistir((v) => v.updateTask(m['uid'] as String, title: m['title'] as String?, notes: m['notes'] as String?));
    case 'gorev_tamamla':
      return s.degistir((v) => v.setTaskDone(m['uid'] as String, m['done'] as bool));
    case 'gorev_gun':
      return s.degistir((v) => v.planTaskDay(m['uid'] as String, m['day'] as String));
    case 'gorev_plan_temizle':
      return s.degistir((v) => v.clearTaskPlan(m['uid'] as String));
    case 'gorev_saat':
      return s.degistir((v) => v.planTaskSlot(m['uid'] as String, utcOku(m['start_utc'] as String), utcOku(m['end_utc'] as String),
          m['calendar_uid'] as String, m['tzid'] as String));
    case 'gorev_sil':
      return s.degistir((v) => v.deleteTask(m['uid'] as String));
    case 'disa':
      // Dosyayi ham UTF-8 baytlariyla yaz (uygulamadaki paylasim ayni metni yazar).
      await File(m['yol'] as String).writeAsBytes(utf8.encode(disaAktarMetin(s.veri, s.cihaz, simdi: c.saat())));
      return null;
    case 'ice':
      final String metin;
      try {
        metin = utf8.decode(await File(m['yol'] as String).readAsBytes());
      } on FormatException catch (e) {
        throw FormatException('UTF-8 degil: ${e.message}');
      }
      final sonuc = importEt(s.veri, metin); // hata -> istisna, store'a dokunulmaz
      await s.uygula(sonuc.veri);
      return raporJson(sonuc.rapor);
    case 'acilim':
      final l = s.veri.occurrences(utcOku(m['bas'] as String), utcOku(m['bit'] as String), includeHidden: true);
      return [for (final o in l) olusumJson(o)];
    case 'toplu_uret':
      // Olcek: n etkinlik (her 5'te biri haftalik tekrarli, her 10'da biri hatirlaticili) + g gorev.
      final n = m['etkinlik'] as int, g = m['gorev'] as int, kal = m['calendar_uid'] as String;
      await s.degistir<void>((v) {
        final bas = utcOku('2026-03-01T06:00:00Z');
        for (var i = 0; i < n; i++) {
          final b = bas.add(Duration(days: i % 365, hours: i % 12));
          v.addEvent(Event(
            uid: 'mob-olcek-$i@takvim.local',
            calendarUid: kal,
            title: 'Mobil olcek $i \u{1F4C5} Toplantı',
            description: i % 7 == 0 ? 'Açıklama ' * 20 : null,
            start: b,
            end: b.add(const Duration(hours: 1)),
            tzid: i % 3 == 0 ? 'America/New_York' : 'Europe/Istanbul',
            rrule: i % 5 == 0 ? 'FREQ=WEEKLY;COUNT=20' : null,
            reminders: i % 10 == 0 ? [10, 60] : const [],
            createdAt: b,
            updatedAt: b,
          ));
        }
        for (var i = 0; i < g; i++) {
          v.addTask('Mobil gorev $i', notes: i % 4 == 0 ? 'not $i' : null, uid: 'mob-gorev-$i@takvim.local');
        }
      });
      return null;
    case 'depo_yolu':
      return s.cihaz.id;
    default:
      throw StateError('bilinmeyen op: $op');
  }
}

Future<void> main() async {
  final satirlar = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final satir in satirlar) {
    if (satir.trim().isEmpty) continue;
    final m = jsonDecode(satir) as Map<String, dynamic>;
    Map<String, dynamic> yanit;
    try {
      yanit = {'id': m['id'], 'ok': true, 'veri': await calistir(m['op'] as String, m)};
    } catch (e) {
      yanit = {'id': m['id'], 'ok': false, 'tur': e.runtimeType.toString(), 'hata': e.toString()};
    }
    stdout.writeln(ascii(jsonEncode(yanit)));
    await stdout.flush();
  }
}
