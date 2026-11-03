// Açılımın doğrudan, elle hesaplanmış beklentileri. Masaüstüyle birebir karşılaştırma
// uyum_test.dart'ta; burası okunabilir örnekler ve masaüstünde olmayan davranışlar.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/zaman.dart';

import 'yardimci.dart';

List<String> baslangiclar(Event e, String a, String b) => expand(e, t(a), t(b)).map((o) => utcYaz(o.start)).toList();

void main() {
  const g = '2026-10-01T00:00:00Z';

  test('haftalık pazartesi 10:00 İstanbul (07:00Z)', () {
    final e = ev('e', g, baslangic: '2026-11-02T07:00:00Z', bitis: '2026-11-02T08:00:00Z', rrule: 'FREQ=WEEKLY;BYDAY=MO');
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z'), [
      '2026-11-02T07:00:00Z',
      '2026-11-09T07:00:00Z',
      '2026-11-16T07:00:00Z',
      '2026-11-23T07:00:00Z',
      '2026-11-30T07:00:00Z',
    ]);
  });

  test('aylık: ayın 31i kısa ayları atlar', () {
    final e = ev('e', g, baslangic: '2026-01-31T09:00:00Z', bitis: '2026-01-31T10:00:00Z', rrule: 'FREQ=MONTHLY;BYMONTHDAY=31');
    final gunler = baslangiclar(e, '2026-01-01T00:00:00Z', '2026-07-01T00:00:00Z').map((s) => s.substring(0, 10));
    expect(gunler, ['2026-01-31', '2026-03-31', '2026-05-31']);
  });

  test('tüm gün: yerel gece yarısı korunur, COUNT sınırlar', () {
    final e = ev('e', g,
        baslangic: '2026-11-02T21:00:00Z', bitis: '2026-11-03T21:00:00Z', tumGun: true, rrule: 'FREQ=DAILY;COUNT=3');
    final o = expand(e, t('2026-11-01T00:00:00Z'), t('2026-12-01T00:00:00Z'));
    expect(o.length, 3);
    expect(o.every((x) => x.allDay && x.end.difference(x.start) == const Duration(days: 1)), isTrue);
  });

  test('DST: New York günlük 09:00 yerel, geçişte UTC kayar (EST->EDT)', () {
    final e = ev('e', g,
        baslangic: '2026-03-06T14:00:00Z', bitis: '2026-03-06T15:00:00Z', tzid: 'America/New_York', rrule: 'FREQ=DAILY');
    expect(baslangiclar(e, '2026-03-06T00:00:00Z', '2026-03-10T00:00:00Z'), [
      '2026-03-06T14:00:00Z',
      '2026-03-07T14:00:00Z',
      '2026-03-08T13:00:00Z', // 8 Mart: DST başladı
      '2026-03-09T13:00:00Z',
    ]);
  });

  test('DST: var olmayan 02:30 geçiş öncesi ofsetle (zoneinfo fold=0), belirsiz 01:30 ilk geçişle', () {
    final bosluk = ev('e', g,
        baslangic: '2026-03-07T07:30:00Z', bitis: '2026-03-07T08:30:00Z', tzid: 'America/New_York', rrule: 'FREQ=DAILY');
    expect(baslangiclar(bosluk, '2026-03-07T00:00:00Z', '2026-03-10T00:00:00Z'), [
      '2026-03-07T07:30:00Z',
      '2026-03-08T07:30:00Z', // 02:30 yok -> EST ofsetiyle
      '2026-03-09T06:30:00Z',
    ]);
    final cift = ev('e', g,
        baslangic: '2026-10-31T05:30:00Z', bitis: '2026-10-31T06:30:00Z', tzid: 'America/New_York', rrule: 'FREQ=DAILY');
    expect(baslangiclar(cift, '2026-10-31T00:00:00Z', '2026-11-03T00:00:00Z'), [
      '2026-10-31T05:30:00Z',
      '2026-11-01T05:30:00Z', // 01:30 iki kez var, ilki (EDT)
      '2026-11-02T06:30:00Z',
    ]);
  });

  test('EXDATE çıkarır, RDATE ekler, iptal override sayıdan düşer', () {
    final e = ev('e', g,
        baslangic: '2026-11-02T07:00:00Z',
        bitis: '2026-11-02T08:00:00Z',
        rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4',
        exdate: ['2026-11-09T07:00:00Z'],
        rdate: ['2026-11-12T09:00:00Z'],
        overrides: [EventOverride(originalStart: t('2026-11-16T07:00:00Z'), cancelled: true)]);
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-31T00:00:00Z'), [
      '2026-11-02T07:00:00Z',
      '2026-11-12T09:00:00Z',
      '2026-11-23T07:00:00Z',
    ]);
  });

  test('taşıma override: yeni yer, yeni başlık/konum; pencere dışından içeri giren örnek bulunur', () {
    final e = ev('e', g,
        baslangic: '2026-11-02T07:00:00Z',
        bitis: '2026-11-02T08:00:00Z',
        rrule: 'FREQ=WEEKLY;BYDAY=MO',
        overrides: [
          EventOverride(originalStart: t('2026-11-09T07:00:00Z'), newStart: t('2026-11-20T10:00:00Z'), newTitle: 'Telafi', newLocation: 'B1'),
        ]);
    final ici = expand(e, t('2026-11-19T00:00:00Z'), t('2026-11-22T00:00:00Z'));
    expect(ici.length, 1);
    expect(ici.single.title, 'Telafi');
    expect(ici.single.location, 'B1');
    expect(ici.single.isOverride, isTrue);
    expect(ici.single.originalStart, t('2026-11-09T07:00:00Z'));
    expect(ici.single.end, t('2026-11-20T11:00:00Z')); // süre korunur
    // orijinal yerinde artık yok
    expect(baslangiclar(e, '2026-11-09T00:00:00Z', '2026-11-10T00:00:00Z'), isEmpty);
  });

  test('seriye ait olmayan (hayalet) override görünmez', () {
    final e = ev('e', g,
        baslangic: '2026-11-02T07:00:00Z',
        bitis: '2026-11-02T08:00:00Z',
        rrule: 'FREQ=WEEKLY;BYDAY=MO',
        overrides: [EventOverride(originalStart: t('2026-11-10T07:00:00Z'), newStart: t('2026-11-11T07:00:00Z'))]);
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z').length, 5);
    expect(baslangiclar(e, '2026-11-11T00:00:00Z', '2026-11-12T00:00:00Z'), isEmpty);
  });

  test('sonucu değiştirmeyen WKST=SU atılır, kural normal açılır (Google .ics WKST=SU yazar)', () {
    final e = ev('e', g, baslangic: '2026-11-02T07:00:00Z', bitis: '2026-11-02T08:00:00Z', rrule: 'FREQ=WEEKLY;WKST=SU;BYDAY=MO;COUNT=3');
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z'),
        ['2026-11-02T07:00:00Z', '2026-11-09T07:00:00Z', '2026-11-16T07:00:00Z']);
  });

  test('kural metni büyük/küçük harf duyarsız (RFC 5545, dateutil gibi)', () {
    final e = ev('e', g, baslangic: '2026-11-02T07:00:00Z', bitis: '2026-11-02T08:00:00Z', rrule: 'freq=weekly;count=2');
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z'), ['2026-11-02T07:00:00Z', '2026-11-09T07:00:00Z']);
  });

  test('sonucu DEĞİŞTİREN WKST=SU (aralıklı haftalık) desteklenmez: çökmez, tek örneğe düşer', () {
    final e = ev('e', g, baslangic: '2026-11-02T07:00:00Z', bitis: '2026-11-02T08:00:00Z', rrule: 'FREQ=WEEKLY;INTERVAL=2;WKST=SU;BYDAY=MO');
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z'), ['2026-11-02T07:00:00Z']);
  });

  test('yoğun kural pencerede maksOrnek ile kırpılır (uygulama kilitlenmez)', () {
    final e = ev('e', g, baslangic: '2026-11-02T00:00:00Z', bitis: '2026-11-02T00:00:30Z', rrule: 'FREQ=MINUTELY');
    final sayi = expand(e, t('2026-11-02T00:00:00Z'), t('2026-11-12T00:00:00Z')).length; // 14400 dakika
    expect(sayi, maksOrnek);
  });

  test('SECONDLY desteklenmez: tek örneğe düşer', () {
    final e = ev('e', g, baslangic: '2026-11-02T00:00:00Z', bitis: '2026-11-02T00:00:01Z', rrule: 'FREQ=SECONDLY');
    expect(expand(e, t('2026-11-02T00:00:00Z'), t('2026-11-03T00:00:00Z')).length, 1);
  });

  test('"RRULE:" önekli ve çok satırlı metin kabul edilir', () {
    final e = ev('e', g, baslangic: '2026-11-02T07:00:00Z', bitis: '2026-11-02T08:00:00Z', rrule: 'RRULE:FREQ=DAILY;COUNT=2');
    expect(baslangiclar(e, '2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z').length, 2);
  });
}
