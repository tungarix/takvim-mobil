// İnceleme bulgusu 1: tüm gün tekrarında DST gününde bitiş yerel gece yarısında kalmalı.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/seri_bol.dart';

import 'yardimci.dart';

void main() {
  // Berlin yerel gece yarısı: yaz (UTC+2) 22:00Z, kış (UTC+1) 23:00Z.
  final e = ev('b', '2026-10-01T00:00:00Z',
      baslangic: '2026-10-20T22:00:00Z', bitis: '2026-10-21T22:00:00Z', tzid: 'Europe/Berlin', tumGun: true, rrule: 'FREQ=DAILY');

  test('sonbahar geçişi (25 Ekim, 25 saatlik gün): bitiş ertesi yerel gece yarısı', () {
    final o = expand(e, t('2026-10-24T00:00:00Z'), t('2026-10-27T00:00:00Z'));
    final g25 = o.firstWhere((x) => x.start == t('2026-10-24T22:00:00Z'));
    expect(g25.end, t('2026-10-25T23:00:00Z'));
    expect(o.map((x) => x.end).toSet().length, o.length); // örnekler çakışmaz
  });

  test('ilkbahar geçişi (29 Mart, 23 saatlik gün): bitiş ertesi yerel gece yarısı', () {
    final e2 = ev('b', '2026-10-01T00:00:00Z',
        baslangic: '2026-03-26T23:00:00Z', bitis: '2026-03-27T23:00:00Z', tzid: 'Europe/Berlin', tumGun: true, rrule: 'FREQ=DAILY');
    final o = expand(e2, t('2026-03-27T00:00:00Z'), t('2026-04-01T00:00:00Z'));
    final g29 = o.firstWhere((x) => x.start == t('2026-03-28T23:00:00Z'));
    expect(g29.end, t('2026-03-29T22:00:00Z'));
    final g30 = o.firstWhere((x) => x.start == t('2026-03-29T22:00:00Z'));
    expect(g30.end, t('2026-03-30T22:00:00Z'));
  });

  test('zamanlı etkinlikte sabit süre korunur', () {
    final z = ev('z', '2026-10-01T00:00:00Z',
        baslangic: '2026-10-20T08:00:00Z', bitis: '2026-10-20T09:00:00Z', tzid: 'Europe/Berlin', rrule: 'FREQ=DAILY');
    expect(ornekBitisi(z, t('2026-10-25T08:00:00Z')), t('2026-10-25T09:00:00Z'));
  });

  test('seriBol: yeni seri DST gününe düşen tüm gün başlangıcında da yerel gece yarısında biter', () {
    final r = seriBol(e, t('2026-10-24T22:00:00Z'), yeniUid: 'y', simdi: t('2026-10-02T00:00:00Z'));
    expect(r.yeni.end, t('2026-10-25T23:00:00Z'));
  });
}
