import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/zaman.dart';

import 'yardimci.dart';

void main() {
  test('zaman: sabit genişlikli UTC yaz/oku, taşan ve yanlış biçim reddedilir', () {
    expect(utcYaz(utcOku('2026-11-02T10:00:00Z')), '2026-11-02T10:00:00Z');
    expect(utcYaz(DateTime.utc(2026, 1, 2, 3, 4, 5, 678, 9)), '2026-01-02T03:04:05Z');
    expect(utcYaz(DateTime.parse('2026-11-02T13:00:00+03:00')), '2026-11-02T10:00:00Z');
    for (final kotu in ['2026-11-02T10:00:00', '2026-11-02T10:00:00.000Z', '2026-13-02T10:00:00Z', '2026-02-30T10:00:00Z', '2026-11-02T25:00:00Z', '']) {
      expect(() => utcOku(kotu), throwsFormatException, reason: kotu);
    }
  });

  test('Event JSON gidiş-dönüş: spec örneğindeki alanlar birebir', () {
    final j = jsonDecode('''
      {"uid":"u1","calendar_uid":"c1","title":"Toplantı","description":null,"location":null,
       "start_utc":"2026-11-03T07:00:00Z","end_utc":"2026-11-03T08:00:00Z","tzid":"Europe/Istanbul","all_day":false,
       "rrule":"FREQ=WEEKLY;BYDAY=MO","rdate":[],"exdate":["2026-11-09T07:00:00Z"],"reminders":[10,60],
       "overrides":[{"original_start_utc":"2026-11-10T07:00:00Z","cancelled":false,"new_start_utc":"2026-11-10T09:00:00Z",
                     "new_end_utc":null,"new_title":"Yeni","new_location":null}],
       "created_at":"2026-11-01T08:00:00Z","updated_at":"2026-11-01T09:00:00Z"}''') as Map<String, dynamic>;
    expect(Event.fromJson(j).toJson(), j);
  });

  test('Calendar, Task, Mezar JSON gidiş-dönüş', () {
    final c = {'uid': 'c', 'name': 'Kişisel', 'color': '#3b82f6', 'visible': true, 'updated_at': '2026-11-01T08:00:00Z'};
    expect(Calendar.fromJson(c).toJson(), c);
    final g = {
      'uid': 'g', 'title': 'Rapor', 'notes': 'n', 'plan_day': '2026-11-03', 'event_uid': null,
      'done_at': '2026-11-02T09:00:00Z', 'created_at': '2026-11-01T08:00:00Z', 'updated_at': '2026-11-01T08:00:00Z'
    };
    expect(Task.fromJson(g).toJson(), g);
    final m = {'kind': 'event', 'uid': 'x', 'deleted_at': '2026-11-02T09:00:00Z'};
    expect(Mezar.fromJson(m).toJson(), m);
  });

  test('rdate/exdate/reminders normalize edilir (sıralı, tekil)', () {
    final e = ev('e', '2026-11-01T00:00:00Z',
        hatirlatici: [60, 10, 60], exdate: ['2026-11-09T07:00:00Z', '2026-11-02T07:00:00Z', '2026-11-09T07:00:00Z']);
    expect(e.reminders, [10, 60]);
    expect(e.exdate, [t('2026-11-02T07:00:00Z'), t('2026-11-09T07:00:00Z')]);
  });

  test('Event doğrulaması: bitiş sonra, geçerli tzid, boş rrule yok', () {
    expect(() => ev('e', '2026-11-01T00:00:00Z', bitis: '2026-11-03T07:00:00Z'), throwsArgumentError);
    expect(() => ev('e', '2026-11-01T00:00:00Z', tzid: 'X/Y'), throwsFormatException);
    expect(() => ev('e', '2026-11-01T00:00:00Z', rrule: '  '), throwsArgumentError);
  });

  test('yanlış tipli alan FormatException (Veri.fromJson bunu BicimHatasi yapar)', () {
    expect(() => Calendar.fromJson({'uid': 1}), throwsFormatException);
    expect(() => Event.fromJson('metin'), throwsFormatException);
  });
}
