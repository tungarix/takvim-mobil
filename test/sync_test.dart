import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/export.dart';
import 'package:takvim/sync/import.dart';

import 'yardimci.dart';

const eski = '2026-11-01T08:00:00Z';
const orta = '2026-11-01T12:00:00Z';
const yeni = '2026-11-02T08:00:00Z';

ImportSonucu iceri(Veri yerel, Veri uzak) => importEt(yerel, dosya(uzak));

void main() {
  group('kayıt kuralı (son yazan kazanır)', () {
    test('dosya kesin yeniyse yerel değişir, etkinlik overrides+reminders ile birlikte', () {
      final yerel = veri(takvimler: [cal('c1', 'Kişisel', eski)], etkinlikler: [ev('e1', orta, baslik: 'Yerel')]);
      final uzak = veri(takvimler: [cal('c1', 'Kişisel', eski)], etkinlikler: [
        ev('e1', yeni,
            baslik: 'Uzak',
            rrule: 'FREQ=WEEKLY',
            hatirlatici: [10, 60],
            overrides: [EventOverride(originalStart: t('2026-11-10T07:00:00Z'), cancelled: true)]),
      ]);
      final s = iceri(yerel, uzak);
      final e = s.veri.events['e1']!;
      expect(e.title, 'Uzak');
      expect(e.reminders, [10, 60]);
      expect(e.overrides.single.cancelled, isTrue);
      expect(e.updatedAt, t(yeni)); // dosyadaki değer, şimdi değil
      expect(s.rapor.updated, 1);
    });

    test('yerel yeniyse yerel kalır (ters yön)', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', yeni, baslik: 'Yerel')]);
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta, baslik: 'Uzak')]);
      final s = iceri(yerel, uzak);
      expect(s.veri.events['e1']!.title, 'Yerel');
      expect(s.rapor.degisti, isFalse);
    });

    test('eşit updated_at: yerel kalır', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta, baslik: 'Yerel')]);
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta, baslik: 'Uzak')]);
      expect(iceri(yerel, uzak).veri.events['e1']!.title, 'Yerel');
    });

    test('yerelde olmayan eklenir; takvim ve görev için de', () {
      final uzak = veri(
        takvimler: [cal('c1', 'İş', eski)],
        etkinlikler: [ev('e1', eski)],
        gorevler: [gorev('g1', eski, gun: '2026-11-03')],
      );
      final s = iceri(veri(), uzak);
      expect(s.veri.calendars.keys, ['c1']);
      expect(s.veri.events.keys, ['e1']);
      expect(s.veri.tasks['g1']!.planDay, '2026-11-03');
      expect([s.rapor.added, s.rapor.updated, s.rapor.deleted, s.rapor.skipped], [3, 0, 0, 0]);
      expect([s.rapor.calendar.added, s.rapor.event.added, s.rapor.task.added], [1, 1, 1]);
    });

    test('görev LWW iki yön', () {
      final yerel = veri(gorevler: [gorev('g1', orta, baslik: 'Yerel')]);
      expect(iceri(yerel, veri(gorevler: [gorev('g1', yeni, baslik: 'Uzak')])).veri.tasks['g1']!.title, 'Uzak');
      expect(iceri(yerel, veri(gorevler: [gorev('g1', eski, baslik: 'Uzak')])).veri.tasks['g1']!.title, 'Yerel');
    });
  });

  group('silme kuralı', () {
    Veri yerelKayit() => veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta)]);
    Veri uzakSilme(String an) => veri(takvimler: [cal('c1', 'K', eski)], mezarlar: [mezar('event', 'e1', an)]);

    test('silme kayıttan kesin yeni: silinir, mezar taşına DOSYADAKİ an yazılır', () {
      final s = iceri(yerelKayit(), uzakSilme(yeni));
      expect(s.veri.events, isEmpty);
      expect(s.veri.mezarlar['event:e1']!.deletedAt, t(yeni));
      expect(s.rapor.deleted, 1);
    });

    test('kayıt silmeden yeni: kayıt kalır, yerel silme izi kalkar', () {
      final yerel = yerelKayit()..mezarlar['event:e1'] = mezar('event', 'e1', eski);
      final s = iceri(yerel, uzakSilme(eski));
      expect(s.veri.events.containsKey('e1'), isTrue);
      expect(s.veri.mezarlar, isEmpty);
    });

    test('eşitlikte kayıt kalır', () {
      final s = iceri(yerelKayit(), uzakSilme(orta));
      expect(s.veri.events.containsKey('e1'), isTrue);
      expect(s.rapor.deleted, 0);
    });

    test('yerelde silme izi var, dosyada canlı: kayıt yeniyse canlanır, eskiyse silik kalır, eşitse canlanır', () {
      Veri silikYerel() => veri(takvimler: [cal('c1', 'K', eski)], mezarlar: [mezar('event', 'e1', orta)]);
      Veri canliUzak(String an) => veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', an)]);
      final canlanan = iceri(silikYerel(), canliUzak(yeni));
      expect(canlanan.veri.events.containsKey('e1'), isTrue);
      expect(canlanan.veri.mezarlar, isEmpty);
      expect(canlanan.rapor.event.added, 1);
      expect(iceri(silikYerel(), canliUzak(eski)).veri.events, isEmpty);
      expect(iceri(silikYerel(), canliUzak(orta)).veri.events.containsKey('e1'), isTrue);
    });

    test('yerelde olmayan kaydın mezar taşı taşınır (üçüncü cihaza ulaşsın); eskisi yenisini ezmez', () {
      final s = iceri(veri(mezarlar: [mezar('task', 'g9', yeni)]), veri(mezarlar: [mezar('task', 'g9', eski)]));
      expect(s.veri.mezarlar['task:g9']!.deletedAt, t(yeni));
      final s2 = iceri(veri(), veri(mezarlar: [mezar('task', 'g9', eski)]));
      expect(s2.veri.mezarlar['task:g9']!.deletedAt, t(eski));
      expect(s2.rapor.deleted, 0);
    });

    test('dosyanın kendi mezar taşından eski canlı kayıt eklenmez (ekle-sonra-sil sayımı yok)', () {
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta)], mezarlar: [mezar('event', 'e1', yeni)]);
      final s = iceri(veri(takvimler: [cal('c1', 'K', eski)]), uzak);
      expect(s.veri.events, isEmpty);
      expect(s.veri.mezarlar['event:e1']!.deletedAt, t(yeni));
      expect([s.rapor.added, s.rapor.deleted], [0, 0]);
    });

    test('görev silme (iki yön)', () {
      final yerel = veri(gorevler: [gorev('g1', orta)]);
      expect(iceri(yerel, veri(mezarlar: [mezar('task', 'g1', yeni)])).veri.tasks, isEmpty);
      expect(iceri(yerel, veri(mezarlar: [mezar('task', 'g1', eski)])).veri.tasks.keys, ['g1']);
    });

    test('takvim silinince etkinlikleri de gider, her biri için mezar taşı', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski), cal('c2', 'Diğer', eski)], etkinlikler: [
        ev('e1', orta),
        ev('e2', orta),
        ev('e3', orta, takvim: 'c2'),
      ]);
      final s = iceri(yerel, veri(takvimler: [cal('c2', 'Diğer', eski)], mezarlar: [mezar('calendar', 'c1', yeni)]));
      expect(s.veri.calendars.keys, ['c2']);
      expect(s.veri.events.keys, ['e3']);
      expect(s.veri.mezarlar['calendar:c1']!.deletedAt, t(yeni));
      expect(s.veri.mezarlar['event:e1']!.deletedAt, t(yeni));
      expect(s.veri.mezarlar['event:e2']!.deletedAt, t(yeni));
      expect([s.rapor.calendar.deleted, s.rapor.event.deleted], [1, 2]);
    });
  });

  group('takvim ad eşleşmesi', () {
    test('aynı ad (büyük/küçük harf, kenar boşluğu fark etmez): uid benimsenir, etkinlikler taşınır, ikilenmez', () {
      final yerel = veri(takvimler: [cal('yerel-kisisel', 'Kişisel', orta, renk: '#111111')], etkinlikler: [
        ev('e1', orta, takvim: 'yerel-kisisel'),
      ]);
      final uzak = veri(takvimler: [cal('uzak-kisisel', '  kişisel ', eski, renk: '#222222')], etkinlikler: [
        ev('e2', yeni, takvim: 'uzak-kisisel'),
      ]);
      final s = iceri(yerel, uzak);
      expect(s.veri.calendars.keys, ['uzak-kisisel']);
      expect(s.veri.calendars['uzak-kisisel']!.color, '#111111'); // yerel daha yeniydi
      expect(s.veri.events['e1']!.calendarUid, 'uzak-kisisel');
      expect(s.veri.events['e2']!.calendarUid, 'uzak-kisisel');
      expect(s.rapor.skipped, 0);
      // ikinci kez: değişiklik yok
      final s2 = importEt(s.veri, dosya(uzak));
      expect(s2.rapor.degisti, isFalse);
      expect(ozet(s2.veri), ozet(s.veri));
    });

    test('dosya takvimi daha yeniyse ad/renk dosyadan gelir', () {
      final yerel = veri(takvimler: [cal('a', 'Kişisel', eski, renk: '#111111')]);
      final uzak = veri(takvimler: [cal('b', 'kişisel', yeni, renk: '#222222')]);
      final s = iceri(yerel, uzak);
      expect(s.veri.calendars['b']!.color, '#222222');
      expect(s.veri.calendars.length, 1);
    });

    test('dosyadaki iki takvim aynı yerel takvimi kapışamaz', () {
      final yerel = veri(takvimler: [cal('a', 'Kişisel', eski)]);
      final uzak = veri(takvimler: [cal('b', 'Kişisel', eski), cal('c', 'kişisel', eski)]);
      final s = iceri(yerel, uzak);
      expect(s.veri.calendars.keys.toSet(), {'b', 'c'});
    });

    test('farklı ad: ayrı takvim olarak eklenir', () {
      final s = iceri(veri(takvimler: [cal('a', 'Kişisel', eski)]), veri(takvimler: [cal('b', 'İş', eski)]));
      expect(s.veri.calendars.keys.toSet(), {'a', 'b'});
    });
  });

  group('yetim ve görev-blok', () {
    test('takvimi olmayan etkinlik eklenmez, atlandı sayılır', () {
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', yeni, takvim: 'yok')]);
      final s = iceri(veri(takvimler: [cal('c1', 'K', eski)]), uzak);
      expect(s.veri.events, isEmpty);
      expect([s.rapor.added, s.rapor.skipped, s.rapor.event.skipped], [0, 1, 1]);
    });

    test('silinmiş (mezar taşlı) takvime ait dosya etkinliği yetim kalır', () {
      final yerel = veri(mezarlar: [mezar('calendar', 'c1', yeni)]);
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', orta)]);
      final s = iceri(yerel, uzak);
      expect(s.veri.calendars, isEmpty);
      expect(s.veri.events, isEmpty);
      expect(s.rapor.skipped, 1);
    });

    test('event_uid yerelde yoksa görev plansıza döner (updated_at dosyadaki kalır)', () {
      final uzak = veri(gorevler: [gorev('g1', yeni, blok: 'yok-blok')]);
      final g = iceri(veri(), uzak).veri.tasks['g1']!;
      expect([g.planDay, g.eventUid], [null, null]);
      expect(g.updatedAt, t(yeni));
    });

    test('blok silinirse görev yerelde de plansıza döner', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('b1', orta)], gorevler: [gorev('g1', orta, blok: 'b1')]);
      final s = iceri(yerel, veri(takvimler: [cal('c1', 'K', eski)], mezarlar: [mezar('event', 'b1', yeni)]));
      expect(s.veri.events, isEmpty);
      expect(s.veri.tasks['g1']!.eventUid, isNull);
      expect(s.veri.tasks['g1']!.planDay, isNull);
    });

    test('blok ve görev aynı dosyada gelir, bağ korunur', () {
      final uzak = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('b1', yeni)], gorevler: [gorev('g1', yeni, blok: 'b1')]);
      final s = iceri(veri(takvimler: [cal('c1', 'K', eski)]), uzak);
      expect(s.veri.tasks['g1']!.eventUid, 'b1');
    });
  });

  group('idempotency ve atomiklik', () {
    Veri zengin() => veri(
          takvimler: [cal('c1', 'Kişisel', eski), cal('c2', 'İş', orta)],
          etkinlikler: [
            ev('e1', orta,
                rrule: 'FREQ=WEEKLY;BYDAY=MO',
                hatirlatici: [10],
                overrides: [EventOverride(originalStart: t('2026-11-10T07:00:00Z'), newStart: t('2026-11-10T09:00:00Z'))]),
            ev('b1', orta, takvim: 'c2'),
            ev('yetim', orta, takvim: 'yok'),
          ],
          gorevler: [gorev('g1', orta, blok: 'b1'), gorev('g2', eski, gun: '2026-11-04')],
          mezarlar: [mezar('event', 'olu', yeni), mezar('task', 'olu2', orta)],
        );

    test('aynı dosya ikinci kez içe aktarılınca hiçbir şey değişmez', () {
      final d = dosya(zengin());
      final ilk = importEt(veri(takvimler: [cal('c9', 'kişisel', eski)]), d);
      final ikinci = importEt(ilk.veri, d);
      expect(ikinci.rapor.degisti, isFalse);
      expect(ikinci.rapor.skipped, 1); // yetim her seferinde atlanır, durum değişmez
      expect(ozet(ikinci.veri), ozet(ilk.veri));
      final ucuncu = importEt(ikinci.veri, d);
      expect(ozet(ucuncu.veri), ozet(ilk.veri));
    });

    test('yerel durum içe aktarmada mutasyona uğramaz', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', eski)]);
      final once = ozet(yerel);
      importEt(
          yerel,
          dosya(veri(
              takvimler: [cal('c1', 'K', yeni)],
              etkinlikler: [ev('e1', yeni, baslik: 'X')],
              mezarlar: [mezar('event', 'z', yeni)])));
      expect(ozet(yerel), once);
    });

    test('ortada bozuk kayıt: istisna, HİÇBİR şey değişmez', () {
      final yerel = veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', eski)]);
      final once = ozet(yerel);
      final m = jsonDecode(dosya(veri(
              takvimler: [cal('c1', 'K', yeni)], etkinlikler: [ev('e1', yeni, baslik: 'X'), ev('e2', yeni)])))
          as Map<String, dynamic>;
      ((m['events'] as List).last as Map)['start_utc'] = '2026-11-03 07:00'; // sabit genişlikli UTC değil
      expect(() => importEt(yerel, jsonEncode(m)), throwsA(isA<BicimHatasi>()));
      expect(ozet(yerel), once);
    });

    test('bitiş başlangıçtan önce / bilinmeyen tzid / görev hem gün hem blok / bilinmeyen tür: reddedilir', () {
      final yerel = veri();
      final bozuklar = <void Function(Map<String, dynamic>)>[
        (m) => (m['events'] as List).first['end_utc'] = '2026-11-03T06:00:00Z',
        (m) => (m['events'] as List).first['tzid'] = 'Mars/Olympus',
        (m) => (m['tasks'] as List).first['event_uid'] = 'e1',
        (m) => (m['deleted'] as List).first['kind'] = 'sandalye',
        (m) => (m['events'] as List).first['reminders'] = [-5],
        (m) => (m['tasks'] as List).first['plan_day'] = '2026-13-45',
      ];
      for (final bozuk in bozuklar) {
        final m = jsonDecode(dosya(veri(
          takvimler: [cal('c1', 'K', eski)],
          etkinlikler: [ev('e1', eski)],
          gorevler: [gorev('g1', eski, gun: '2026-11-03')],
          mezarlar: [mezar('event', 'x', eski)],
        ))) as Map<String, dynamic>;
        bozuk(m);
        expect(() => importEt(yerel, jsonEncode(m)), throwsA(isA<BicimHatasi>()));
      }
    });
  });

  group('dosya doğrulaması', () {
    test('sürüm bilinenden büyükse SurumHatasi', () {
      final m = jsonDecode(dosya(veri())) as Map<String, dynamic>;
      m['version'] = 2;
      expect(() => importEt(veri(), jsonEncode(m)), throwsA(isA<SurumHatasi>()));
    });

    test('bozuk JSON, yanlış format, eksik alan reddedilir', () {
      expect(() => importEt(veri(), '{bozuk'), throwsA(isA<BicimHatasi>()));
      expect(() => importEt(veri(), '[]'), throwsA(isA<BicimHatasi>()));
      expect(() => importEt(veri(), '{"format":"baska","version":1}'), throwsA(isA<BicimHatasi>()));
      final m = jsonDecode(dosya(veri())) as Map<String, dynamic>;
      m.remove('events');
      expect(() => importEt(veri(), jsonEncode(m)), throwsA(isA<BicimHatasi>()));
    });

    test('bilinmeyen alanlar yok sayılır (ileri uyum)', () {
      final m = jsonDecode(dosya(veri(takvimler: [cal('c1', 'K', eski)], etkinlikler: [ev('e1', eski)]))) as Map<String, dynamic>;
      m['gelecek'] = {'x': 1};
      (m['events'] as List).first['yeni_alan'] = 42;
      (m['calendars'] as List).first['ikon'] = 'x';
      expect(importEt(veri(), jsonEncode(m)).veri.events.keys, ['e1']);
    });

    test('UTF-8 BOM kabul edilir', () {
      expect(importEt(veri(), '﻿${dosya(veri())}').rapor.degisti, isFalse);
    });
  });

  group('dışa aktarma', () {
    test('tüm zamanlar sabit genişlikli saniye hassasiyetli UTC; anahtarlar spec ile aynı', () {
      final v = veri(
        takvimler: [cal('c1', 'K', eski)],
        etkinlikler: [
          ev('e1', orta,
              rrule: 'FREQ=DAILY',
              hatirlatici: [60, 10],
              overrides: [EventOverride(originalStart: t('2026-11-10T07:00:00Z'), newStart: t('2026-11-10T09:00:00Z'))],
              rdate: ['2026-12-01T07:00:00Z'])
        ],
        gorevler: [gorev('g1', orta, bitti: '2026-11-02T09:00:00Z')],
        mezarlar: [mezar('event', 'x', yeni)],
      );
      final j = jsonDecode(disaAktarMetin(v, cihaz, simdi: t('2026-11-02T10:00:00Z'))) as Map<String, dynamic>;
      expect(j.keys, ['format', 'version', 'created_at', 'device', 'calendars', 'events', 'tasks', 'deleted']);
      expect(j['format'], 'takvim-sync');
      expect(j['version'], 1);
      expect((j['device'] as Map).keys, ['id', 'name', 'app']);
      final e = (j['events'] as List).first as Map<String, dynamic>;
      expect(e.keys, [
        'uid', 'calendar_uid', 'title', 'description', 'location', 'start_utc', 'end_utc', 'tzid', 'all_day', 'rrule',
        'rdate', 'exdate', 'reminders', 'overrides', 'created_at', 'updated_at'
      ]);
      expect(e['reminders'], [10, 60]);
      expect((e['overrides'] as List).first.keys,
          ['original_start_utc', 'cancelled', 'new_start_utc', 'new_end_utc', 'new_title', 'new_location']);
      expect(((j['tasks'] as List).first as Map).keys,
          ['uid', 'title', 'notes', 'plan_day', 'event_uid', 'done_at', 'created_at', 'updated_at']);
      final desen = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');
      final tum = <String>[];
      void topla(Object? o) {
        if (o is Map) {
          for (final MapEntry(:key, :value) in o.entries) {
            if (value is String && (key.toString().endsWith('_utc') || key.toString().endsWith('_at'))) tum.add(value);
            topla(value);
          }
        } else if (o is List) {
          for (final x in o) {
            if (x is String && x.contains('T') && x.endsWith('Z')) tum.add(x);
            topla(x);
          }
        }
      }

      topla(j);
      expect(tum, isNotEmpty);
      expect(tum.where((s) => !desen.hasMatch(s)), isEmpty);
    });

    test('dışa aktar -> boş cihaza içe aktar -> aynı durum; mikrosaniye dosyaya girmez', () {
      final v = veri(
        takvimler: [cal('c1', 'K', eski)],
        etkinlikler: [
          Event(
            uid: 'e1',
            calendarUid: 'c1',
            title: 'Hassas',
            start: DateTime.utc(2026, 11, 3, 7, 0, 0, 123, 456),
            end: DateTime.utc(2026, 11, 3, 8),
            tzid: 'Europe/Istanbul',
            createdAt: t(eski),
            updatedAt: t(orta),
          ),
        ],
        gorevler: [gorev('g1', orta)],
        mezarlar: [mezar('calendar', 'z', yeni)],
      );
      final s = importEt(veri(), disaAktarMetin(v, cihaz));
      expect(ozet(s.veri), ozet(v));
      expect(disaAktarMetin(v, cihaz), isNot(contains('.123')));
    });

    test('aynı durum aynı çıktıyı verir (sıralı)', () {
      final a = veri(takvimler: [cal('b', 'B', eski), cal('a', 'A', eski)]);
      final b = veri(takvimler: [cal('a', 'A', eski), cal('b', 'B', eski)]);
      expect(disaAktarMetin(a, cihaz, simdi: t(eski)), disaAktarMetin(b, cihaz, simdi: t(eski)));
    });
  });
}
