// Mutasyon kuralları (mezar taşları, updated_at) ve iki cihaz senaryosu.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/reminders.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/sync/import.dart';

import 'yardimci.dart';

Event yeniEtkinlik(String uid, String takvim, {String? rrule}) => ev(uid, '2026-10-01T00:00:00Z', takvim: takvim, rrule: rrule);

void main() {
  late Saat saat;
  late Veri v;
  late Calendar kisisel;

  setUp(() {
    saat = Saat();
    v = Veri(saat: saat.call);
    kisisel = v.addCalendar('Kişisel', '#3b82f6');
    saat.ilerle();
  });

  group('mezar taşları', () {
    test('etkinlik silme mezar taşı yazar; yeniden ekleme / geri alma mezar taşını siler ve updated_at şimdi olur', () {
      final e = v.addEvent(yeniEtkinlik('e1', kisisel.uid));
      saat.ilerle();
      v.deleteEvent('e1');
      expect(v.events, isEmpty);
      expect(v.mezarlar['event:e1']!.deletedAt, saat.simdi);
      saat.ilerle();
      final geri = v.addEvent(e);
      expect(v.mezarlar, isEmpty);
      expect(geri.updatedAt, saat.simdi); // eski değil: diğer cihazdaki silme kazanmasın
    });

    test('takvim silinince etkinlikleri için de mezar taşı yazılır', () {
      v.addEvent(yeniEtkinlik('e1', kisisel.uid));
      v.addEvent(yeniEtkinlik('e2', kisisel.uid));
      saat.ilerle();
      v.deleteCalendar(kisisel.uid);
      expect(v.calendars, isEmpty);
      expect(v.events, isEmpty);
      expect(v.mezarlar.keys.toSet(), {'calendar:${kisisel.uid}', 'event:e1', 'event:e2'});
    });

    test('görev silme: bağlı blok da gider, ikisi için mezar taşı', () {
      final g = v.addTask('Rapor');
      v.planTaskSlot(g.uid, t('2026-11-03T07:00:00Z'), t('2026-11-03T08:00:00Z'), kisisel.uid, 'Europe/Istanbul');
      final blok = v.tasks[g.uid]!.eventUid!;
      expect(v.events.containsKey(blok), isTrue);
      v.deleteTask(g.uid);
      expect(v.tasks, isEmpty);
      expect(v.events, isEmpty);
      expect(v.mezarlar.keys.toSet(), {'task:${g.uid}', 'event:$blok'});
    });

    test('etkinlik silinince bağlı görev plansıza döner; gün planı bloğu siler', () {
      final g = v.addTask('Rapor');
      v.planTaskSlot(g.uid, t('2026-11-03T07:00:00Z'), t('2026-11-03T08:00:00Z'), kisisel.uid, 'Europe/Istanbul');
      final blok = v.tasks[g.uid]!.eventUid!;
      v.deleteEvent(blok);
      expect(v.tasks[g.uid]!.eventUid, isNull);
      expect(v.tasks[g.uid]!.planDay, isNull);

      v.planTaskSlot(g.uid, t('2026-11-03T07:00:00Z'), t('2026-11-03T08:00:00Z'), kisisel.uid, 'Europe/Istanbul');
      final blok2 = v.tasks[g.uid]!.eventUid!;
      v.planTaskDay(g.uid, '2026-11-05');
      expect(v.events.containsKey(blok2), isFalse);
      expect(v.mezarlar.containsKey('event:$blok2'), isTrue);
      expect(v.tasks[g.uid]!.planDay, '2026-11-05');
    });

    test('mezar taşı budanmaz: sonradan başka işlemler onu silmez', () {
      v.addEvent(yeniEtkinlik('e1', kisisel.uid));
      v.deleteEvent('e1');
      for (var i = 0; i < 5; i++) {
        saat.ilerle(const Duration(days: 40));
        v.addEvent(yeniEtkinlik('x$i', kisisel.uid));
      }
      expect(v.mezarlar.containsKey('event:e1'), isTrue);
    });
  });

  group('updated_at', () {
    test('override ve hatırlatıcı değişince etkinliğin updated_at i şimdiye çekilir', () {
      v.addEvent(yeniEtkinlik('e1', kisisel.uid, rrule: 'FREQ=WEEKLY'));
      saat.ilerle();
      v.cancelOccurrence('e1', t('2026-11-10T07:00:00Z'));
      expect(v.events['e1']!.updatedAt, saat.simdi);
      expect(v.events['e1']!.overrides.single.cancelled, isTrue);

      saat.ilerle();
      v.moveOccurrence('e1', t('2026-11-17T07:00:00Z'), t('2026-11-17T09:00:00Z'));
      expect(v.events['e1']!.updatedAt, saat.simdi);
      // new_end verilmediyse etkinlik süresinden hesaplanıp yazılır
      expect(v.events['e1']!.overrides.last.newEnd, t('2026-11-17T10:00:00Z'));

      saat.ilerle();
      v.addReminder('e1', 15);
      expect(v.events['e1']!.updatedAt, saat.simdi);
      expect(v.events['e1']!.reminders, [15]);

      saat.ilerle();
      v.deleteReminder('e1', 15);
      expect(v.events['e1']!.updatedAt, saat.simdi);

      saat.ilerle();
      v.deleteOverride('e1', t('2026-11-10T07:00:00Z'));
      expect(v.events['e1']!.updatedAt, saat.simdi);
      expect(v.events['e1']!.overrides.length, 1);
    });

    test('aynı override ikinci kez konunca üstüne yazar (UNIQUE)', () {
      v.addEvent(yeniEtkinlik('e1', kisisel.uid, rrule: 'FREQ=WEEKLY'));
      v.cancelOccurrence('e1', t('2026-11-10T07:00:00Z'));
      v.moveOccurrence('e1', t('2026-11-10T07:00:00Z'), t('2026-11-10T12:00:00Z'));
      expect(v.events['e1']!.overrides.length, 1);
      expect(v.events['e1']!.overrides.single.cancelled, isFalse);
    });

    test('blok olan etkinlik tekrarlı yapılamaz; blok başlığı göreve yansır', () {
      final g = v.addTask('Rapor');
      v.planTaskSlot(g.uid, t('2026-11-03T07:00:00Z'), t('2026-11-03T08:00:00Z'), kisisel.uid, 'Europe/Istanbul');
      final blok = v.events[v.tasks[g.uid]!.eventUid]!;
      expect(() => v.updateEvent(ev(blok.uid, '2026-11-02T00:00:00Z', takvim: kisisel.uid, rrule: 'FREQ=DAILY')), throwsArgumentError);
      v.updateEvent(ev(blok.uid, '2026-11-02T00:00:00Z', takvim: kisisel.uid, baslik: 'Yeni ad'));
      expect(v.tasks[g.uid]!.title, 'Yeni ad');
    });
  });

  group('görev', () {
    test('plan_day ve event_uid birlikte dolu olamaz; boş başlık reddedilir', () {
      expect(() => gorev('g', '2026-11-01T00:00:00Z', gun: '2026-11-03', blok: 'e'), throwsArgumentError);
      expect(() => v.addTask('   '), throwsArgumentError);
    });

    test('tamamla / geri al', () {
      final g = v.addTask('Rapor');
      v.setTaskDone(g.uid, true);
      expect(v.tasks[g.uid]!.done, isTrue);
      v.setTaskDone(g.uid, false);
      expect(v.tasks[g.uid]!.done, isFalse);
    });
  });

  group('iki cihaz', () {
    test('silme yayılır, geri alma (yeniden ekleme) silmeyi yener, yankılanmaz', () {
      final saatB = Saat();
      final b = Veri(saat: saatB.call);
      final a = v;
      a.addEvent(yeniEtkinlik('e1', kisisel.uid));
      final disA = dosya(a);
      var bs = importEt(b, disA);
      expect(bs.veri.events.keys, ['e1']);

      saat.ilerle();
      final silinen = a.events['e1']!;
      a.deleteEvent('e1');
      bs = importEt(bs.veri, dosya(a));
      expect(bs.veri.events, isEmpty);
      expect(bs.veri.mezarlar['event:e1']!.deletedAt, a.mezarlar['event:e1']!.deletedAt); // aynen
      // B'nin dosyası A'ya dönünce yankı yok
      final yanki = importEt(a, dosya(bs.veri));
      expect(yanki.rapor.degisti, isFalse);

      saat.ilerle();
      a.addEvent(silinen); // geri al
      bs = importEt(bs.veri, dosya(a));
      expect(bs.veri.events.keys, ['e1']);
      expect(bs.veri.mezarlar, isEmpty);
    });

    test('aynı etkinlik iki cihazda düzenlendi: sonraki kazanır, her iki yönde aynı sonuca yakınsar', () {
      final b = Veri(saat: Saat('2026-11-02T10:30:00Z').call);
      v.addEvent(yeniEtkinlik('e1', kisisel.uid));
      var bs = importEt(b, dosya(v)).veri;
      saat.ilerle(const Duration(hours: 2));
      v.updateEvent(ev('e1', '2026-01-01T00:00:00Z', takvim: kisisel.uid, baslik: 'A düzenledi'));
      final saatB = Saat('2026-11-02T14:00:00Z');
      final b2 = bs.kopya();
      final b3 = Veri(saat: saatB.call)..calendars.addAll(b2.calendars)..events.addAll(b2.events);
      b3.updateEvent(ev('e1', '2026-01-01T00:00:00Z', takvim: kisisel.uid, baslik: 'B düzenledi'));
      final aSon = importEt(v, dosya(b3)).veri;
      final bSon = importEt(b3, dosya(v)).veri;
      expect(aSon.events['e1']!.title, 'B düzenledi');
      expect(bSon.events['e1']!.title, 'B düzenledi');
    });
  });

  group('açılım ve hatırlatıcı', () {
    test('occurrences: gizli takvim varsayılan dışarıda', () {
      v.addEvent(ev('e1', '2026-10-01T00:00:00Z', takvim: kisisel.uid));
      final gizli = v.addCalendar('Gizli', '#000000', visible: false);
      v.addEvent(ev('e2', '2026-10-01T00:00:00Z', takvim: gizli.uid));
      final p = (t('2026-11-01T00:00:00Z'), t('2026-11-10T00:00:00Z'));
      expect(v.occurrences(p.$1, p.$2).map((o) => o.eventUid), ['e1']);
      expect(v.occurrences(p.$1, p.$2, includeHidden: true).map((o) => o.eventUid).toSet(), {'e1', 'e2'});
    });

    test('hatırlatıcılar: zamanı gelen, bitmemiş, tetiklenmemiş', () {
      final e = ev('e1', '2026-10-01T00:00:00Z', takvim: kisisel.uid, rrule: 'FREQ=DAILY;COUNT=3', hatirlatici: [10, 60]);
      v.events['e1'] = e;
      final occs = v.occurrences(t('2026-11-03T00:00:00Z'), t('2026-11-07T00:00:00Z'));
      expect(occs.length, 3);
      final map = {'e1': e.reminders};
      // 06:30Z: 60 dk öncesi (06:00) geçti, 10 dk öncesi (06:50) henüz değil
      var due = dueReminders(occs, map, t('2026-11-03T06:30:00Z'));
      expect(due.map((d) => d.minutesBefore), [60]);
      // tetiklenmiş sayılırsa çıkmaz
      due = dueReminders(occs, map, t('2026-11-03T06:30:00Z'), alreadyFired: {fireKey('e1', 60, occs.first)});
      expect(due, isEmpty);
      // etkinlik bitmiş: geçmiş bildirilmez
      expect(dueReminders(occs.take(1).toList(), map, t('2026-11-03T09:00:00Z')), isEmpty);
      expect(nextFireTime(occs, map, t('2026-11-03T06:30:00Z')), t('2026-11-03T06:50:00Z'));
    });
  });
}
