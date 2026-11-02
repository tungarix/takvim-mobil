// Arayüz aşamasında eklenen saf mantık: yerleşim, tekrar formu, arama, bildirim
// planı, seri bölme, sürüm eşitliği.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/arama.dart';
import 'package:takvim/core/bildirim_plani.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/seri_bol.dart';
import 'package:takvim/core/tekrar.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/core/yerel_zaman.dart';
import 'package:takvim/core/yerlesim.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/surum.dart';

import 'yardimci.dart';

void main() {
  group('yerlesim', () {
    List<(String, int, int)> sonuc(List<(String, String, String)> o) => [
          for (final y in yerlestir<(String, String, String)>(o, (x) => t(x.$2), (x) => t(x.$3))) (y.oge.$1, y.kolon, y.kolonSayisi),
        ];

    test('çakışanlar yan yana, bitişik olanlar ayrı kümede tam genişlik', () {
      final r = sonuc([
        ('a', '2026-11-03T10:00:00Z', '2026-11-03T12:00:00Z'),
        ('b', '2026-11-03T11:00:00Z', '2026-11-03T12:30:00Z'),
        ('c', '2026-11-03T12:30:00Z', '2026-11-03T13:00:00Z'), // b ile bitişik: yeni küme
      ]);
      expect(r, [('a', 0, 2), ('b', 1, 2), ('c', 0, 1)]);
    });

    test('aynı başlangıçta uzun olan önce; çıktı kararlı', () {
      final girdi = [
        ('kisa', '2026-11-03T10:00:00Z', '2026-11-03T10:30:00Z'),
        ('uzun', '2026-11-03T10:00:00Z', '2026-11-03T12:00:00Z'),
      ];
      expect(sonuc(girdi), [('uzun', 0, 2), ('kisa', 1, 2)]);
      expect(sonuc(girdi.reversed.toList()), sonuc(girdi));
    });

    test('boş girdi boş çıktı', () {
      expect(sonuc([]), isEmpty);
    });
  });

  group('tekrar formu', () {
    final loc = YerelZaman('Europe/Istanbul').loc;
    final pzt = DateTime.utc(2026, 11, 2, 9); // Pazartesi

    test('gidiş-dönüş: haftalık gün seçimi + tarihte bitiş', () {
      final a = TekrarAyari(
          tur: TekrarTuru.haftalik, gunler: {1, 3}, bitis: TekrarBitisi.tarih, bitisGunu: DateTime.utc(2026, 12, 31));
      final s = tekrarYaz(a, baslangic: pzt, loc: loc)!;
      expect(s, 'FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T205959Z'); // 23:59:59 yerel = 20:59:59Z
      final geri = tekrarOku(s, baslangic: pzt, loc: loc)!;
      expect(geri.tur, TekrarTuru.haftalik);
      expect(geri.gunler, {1, 3});
      expect(geri.bitisGunu, DateTime.utc(2026, 12, 31));
    });

    test('tek gün başlangıç gününe eşitse BYDAY yazılmaz; sayıyla bitiş', () {
      final s = tekrarYaz(const TekrarAyari(tur: TekrarTuru.haftalik, gunler: {1}, bitis: TekrarBitisi.sayi, sayi: 5),
          baslangic: pzt, loc: loc);
      expect(s, 'FREQ=WEEKLY;COUNT=5');
      expect(tekrarOku(s, baslangic: pzt, loc: loc)!.gunler, {1});
    });

    test('yok -> null; masaüstü "hafta içi" kuralı tanınır; özel kural null (korunur)', () {
      expect(tekrarYaz(const TekrarAyari(), baslangic: pzt, loc: loc), isNull);
      expect(tekrarOku(null, baslangic: pzt, loc: loc)!.tur, TekrarTuru.yok);
      expect(tekrarOku('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', baslangic: pzt, loc: loc)!.gunler, {1, 2, 3, 4, 5});
      expect(tekrarOku('FREQ=DAILY;INTERVAL=2', baslangic: pzt, loc: loc), isNull);
      expect(tekrarOku('FREQ=MONTHLY;BYMONTHDAY=15', baslangic: pzt, loc: loc), isNull);
      expect(tekrarOku('RRULE:FREQ=DAILY;COUNT=3', baslangic: pzt, loc: loc)!.sayi, 3);
    });

    test('yazılan kural açıcıdan geçer ve beklenen günleri üretir', () {
      final s = tekrarYaz(const TekrarAyari(tur: TekrarTuru.haftalik, gunler: {1, 3}, bitis: TekrarBitisi.sayi, sayi: 4),
          baslangic: pzt, loc: loc)!;
      final e = ev('e1', '2026-10-01T00:00:00Z', baslangic: '2026-11-02T06:00:00Z', bitis: '2026-11-02T07:00:00Z', rrule: s);
      final gunler = expand(e, t('2026-11-01T00:00:00Z'), t('2026-12-31T00:00:00Z')).map((o) => utcYaz(o.start).substring(0, 10));
      expect(gunler, ['2026-11-02', '2026-11-04', '2026-11-09', '2026-11-11']);
    });
  });

  group('arama', () {
    late Veri v;
    setUp(() {
      v = veri(takvimler: [cal('c1', 'Kişisel', '2026-10-01T00:00:00Z')], etkinlikler: [
        ev('e1', '2026-10-01T00:00:00Z', baslik: 'Algoritma dersi'),
        ev('e2', '2026-10-01T00:00:00Z', baslik: 'Toplantı', baslangic: '2026-11-04T07:00:00Z', bitis: '2026-11-04T08:00:00Z'),
        ev('blok', '2026-10-01T00:00:00Z', baslik: 'Algoritma ödevi'),
      ], gorevler: [
        gorev('g1', '2026-10-01T00:00:00Z', baslik: 'Algoritma ödevi', blok: 'blok'),
        gorev('g2', '2026-10-01T00:00:00Z', baslik: 'Çarşamba pazarı'),
      ]);
    });

    test('I ailesi ve şapkalar katlanır', () {
      expect(etkinlikAra(v, 'ALGORITMA').map((e) => e.uid), ['e1']); // blok ayıklanır
      expect(gorevAra(v, 'carsamba').map((g) => g.uid), ['g2']);
      expect(aramaAnahtari('İSTANBUL'), 'istanbul');
    });

    test('boş sorgu boş döner; açıklama ve konum da aranır', () {
      expect(etkinlikAra(v, '  '), isEmpty);
      v.events['e2'] = Event(
          uid: 'e2', calendarUid: 'c1', title: 'Toplantı', location: 'Kadıköy', start: t('2026-11-04T07:00:00Z'),
          end: t('2026-11-04T08:00:00Z'), tzid: 'Europe/Istanbul', createdAt: t('2026-10-01T00:00:00Z'), updatedAt: t('2026-10-01T00:00:00Z'));
      expect(etkinlikAra(v, 'kadikoy').map((e) => e.uid), ['e2']);
    });
  });

  group('bildirim planı', () {
    test('pencere, sıralama, üst sınır ve susturulanlar', () {
      final simdi = t('2026-11-03T10:00:00Z');
      final v = veri(takvimler: [
        cal('c1', 'Kişisel', '2026-10-01T00:00:00Z'),
        cal('gizli', 'Gizli', '2026-10-01T00:00:00Z', gorunur: false),
      ], etkinlikler: [
        ev('gunluk', '2026-10-01T00:00:00Z',
            baslangic: '2026-11-04T07:00:00Z', bitis: '2026-11-04T08:00:00Z', rrule: 'FREQ=DAILY', hatirlatici: [10, 60]),
        ev('gizliEv', '2026-10-01T00:00:00Z', takvim: 'gizli', baslangic: '2026-11-04T09:00:00Z', bitis: '2026-11-04T10:00:00Z', hatirlatici: [5]),
        ev('bitmisBlok', '2026-10-01T00:00:00Z', baslangic: '2026-11-04T11:00:00Z', bitis: '2026-11-04T12:00:00Z', hatirlatici: [5]),
        ev('gecmis', '2026-10-01T00:00:00Z', baslangic: '2026-11-03T10:05:00Z', bitis: '2026-11-03T11:00:00Z', hatirlatici: [10]), // tetik geçmişte
      ], gorevler: [
        gorev('g', '2026-10-01T00:00:00Z', blok: 'bitmisBlok', bitti: '2026-11-03T09:00:00Z'),
      ]);
      final plan = bildirimPlani(v, simdi);
      expect(plan.length, 28); // 14 gün x 2 hatırlatıcı
      expect(plan.every((p) => p.ornek.eventUid == 'gunluk'), isTrue);
      expect(plan.first.tetik, t('2026-11-04T06:00:00Z'));
      expect(plan.map((p) => p.tetik).toList(), [...plan.map((p) => p.tetik)]..sort());
      expect(plan.map((p) => p.id).toSet().length, plan.length);
      expect(bildirimPlani(v, simdi, maks: 5).length, 5);
      // Aynı veri -> aynı kimlikler (yeniden kurulunca çift bildirim olmasın).
      expect(bildirimPlani(v, simdi).map((p) => p.id), plan.map((p) => p.id));
    });

    test('pencerenin hemen ötesindeki örneğin pencere içine düşen uzun hatırlatıcısı alınır', () {
      final simdi = t('2026-11-03T10:00:00Z');
      final v = veri(takvimler: [cal('c1', 'Kişisel', '2026-10-01T00:00:00Z')], etkinlikler: [
        ev('e', '2026-10-01T00:00:00Z', baslangic: '2026-11-17T12:00:00Z', bitis: '2026-11-17T13:00:00Z', hatirlatici: [1440]),
      ]);
      expect(bildirimPlani(v, simdi).single.tetik, t('2026-11-16T12:00:00Z'));
    });
  });

  group('seri bölme', () {
    final simdi = t('2026-11-03T10:00:00Z');

    test('COUNT yoksa: eskiye UNTIL, yeni desen üstünden başlar', () {
      final e = ev('s', '2026-10-01T00:00:00Z', rrule: 'FREQ=WEEKLY', hatirlatici: [10]);
      final r = seriBol(e, t('2026-11-17T07:00:00Z'), yeniUid: 'yeni', simdi: simdi);
      expect(r.eski.rrule, 'FREQ=WEEKLY;UNTIL=20261117T065959Z');
      expect(r.yeni.rrule, 'FREQ=WEEKLY');
      expect(r.yeni.start, t('2026-11-17T07:00:00Z'));
      expect(r.yeni.reminders, [10]);
      final eskiGunler = expand(r.eski, t('2026-11-01T00:00:00Z'), t('2026-12-31T00:00:00Z')).map((o) => o.start).toList();
      final yeniGunler = expand(r.yeni, t('2026-11-01T00:00:00Z'), t('2026-12-15T00:00:00Z')).map((o) => o.start).toList();
      expect(eskiGunler, [t('2026-11-03T07:00:00Z'), t('2026-11-10T07:00:00Z')]);
      expect(yeniGunler, [t('2026-11-17T07:00:00Z'), t('2026-11-24T07:00:00Z'), t('2026-12-01T07:00:00Z'), t('2026-12-08T07:00:00Z')]);
    });

    test('COUNT kural düzeyinde bölünür: EXDATE örnek kaybettirmez; override ve exdate taraflara ayrılır', () {
      final e = ev('s', '2026-10-01T00:00:00Z',
          rrule: 'FREQ=DAILY;COUNT=6',
          exdate: ['2026-11-04T07:00:00Z'],
          overrides: [
            EventOverride(originalStart: t('2026-11-03T07:00:00Z'), cancelled: true),
            EventOverride(originalStart: t('2026-11-07T07:00:00Z'), newTitle: 'Değişik'),
          ]);
      // Kural: 3,4,5,6,7,8 Kasım. Bölme 6 Kasım: eski 2 kural örneği (3,4), yeni 4 (6,7,8 + 5? hayır: 5,6,7,8 -> 5'ten önce 3,4)
      final r = seriBol(e, t('2026-11-06T07:00:00Z'), yeniUid: 'yeni', simdi: simdi);
      expect(r.eski.rrule, 'FREQ=DAILY;COUNT=3'); // 3,4,5
      expect(r.yeni.rrule, 'FREQ=DAILY;COUNT=3'); // 6,7,8
      expect(r.eski.exdate, [t('2026-11-04T07:00:00Z')]);
      expect(r.yeni.exdate, isEmpty);
      expect(r.eski.overrides.single.cancelled, isTrue);
      expect(r.yeni.overrides.single.newTitle, 'Değişik');
      final hepsi = [
        ...expand(r.eski, t('2026-11-01T00:00:00Z'), t('2026-12-01T00:00:00Z')),
        ...expand(r.yeni, t('2026-11-01T00:00:00Z'), t('2026-12-01T00:00:00Z')),
      ].map((o) => o.start.day).toList();
      expect(hepsi, [5, 6, 7, 8]); // 3 iptal, 4 exdate; geri kalan hepsi korunur
    });

    test('ilk örnekten ve örnek olmayan noktadan bölünemez; tekrarsız bölünemez', () {
      final e = ev('s', '2026-10-01T00:00:00Z', rrule: 'FREQ=DAILY');
      expect(() => seriBol(e, e.start, yeniUid: 'y', simdi: simdi), throwsArgumentError);
      expect(() => seriBol(e, t('2026-11-05T08:00:00Z'), yeniUid: 'y', simdi: simdi), throwsArgumentError);
      expect(() => seriBol(ev('x', '2026-10-01T00:00:00Z'), t('2026-11-05T07:00:00Z'), yeniUid: 'y', simdi: simdi), throwsArgumentError);
    });

    test('Veri.seriyiBol yeni uid ekler; seriyiKes sonrasını yazmaz', () {
      final saat = Saat();
      final v = Veri(saat: saat.call);
      final c = v.addCalendar('Kişisel', '#3b82f6');
      v.addEvent(ev('s', '2026-10-01T00:00:00Z', takvim: c.uid, rrule: 'FREQ=DAILY'));
      final yeni = v.seriyiBol('s', t('2026-11-05T07:00:00Z'));
      expect(v.events.length, 2);
      expect(yeni.uid, isNot('s'));
      expect(v.mezarlar, isEmpty);
      v.seriyiKes(yeni.uid, t('2026-11-08T07:00:00Z'));
      expect(expand(v.events[yeni.uid]!, t('2026-11-01T00:00:00Z'), t('2026-11-30T00:00:00Z')).map((o) => o.start.day), [5, 6, 7]);
    });

    test('Veri.geriYukleGorev görevi ve bloğunu mezarsız geri koyar', () {
      final saat = Saat();
      final v = Veri(saat: saat.call);
      final c = v.addCalendar('Kişisel', '#3b82f6');
      final g = v.addTask('Rapor');
      v.planTaskSlot(g.uid, t('2026-11-03T07:00:00Z'), t('2026-11-03T08:00:00Z'), c.uid, 'Europe/Istanbul');
      final gorev = v.tasks[g.uid]!;
      final blok = v.events[gorev.eventUid]!;
      v.deleteTask(g.uid);
      expect(v.mezarlar, isNotEmpty);
      saat.ilerle();
      v.geriYukleGorev(gorev, blok: blok);
      expect(v.mezarlar, isEmpty);
      expect(v.tasks[g.uid]!.eventUid, blok.uid);
      expect(v.events.containsKey(blok.uid), isTrue);
    });
  });

  test('sürüm sabiti pubspec.yaml ile aynı', () {
    final satir = File('pubspec.yaml').readAsLinesSync().firstWhere((s) => s.startsWith('version:'));
    expect(satir.replaceFirst('version:', '').trim().split('+').first, surum);
  });
}
