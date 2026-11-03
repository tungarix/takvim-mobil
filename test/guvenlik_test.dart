// Güvenlik incelemesinde (guvenlik/incelemeler/v0.2.0.md) bulunan sorunların regresyon testleri.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/bildirim_plani.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/export.dart';
import 'package:takvim/sync/import.dart';
import 'package:takvim/platform/dosya_servisi.dart';

import 'yardimci.dart';

void main() {
  group('saatlik/dakikalık kural kilitlemez', () {
    // Eski davranışta bu açılımlar dakikalarca sürerdi; şimdi anında tek örneğe düşer.
    for (final kural in ['FREQ=HOURLY', 'FREQ=MINUTELY', 'FREQ=MINUTELY;INTERVAL=2', 'FREQ=HOURLY;BYMONTH=2;BYMONTHDAY=30']) {
      test('0001 başlangıçlı $kural hızlı açılır', () {
        final sw = Stopwatch()..start();
        final e = ev('e', '2026-01-01T00:00:00Z',
            baslangic: '0001-01-01T00:00:00Z', bitis: '0001-01-01T01:00:00Z', rrule: kural);
        final o = expand(e, t('2026-11-01T00:00:00Z'), t('2026-12-13T00:00:00Z'));
        expect(sw.elapsedMilliseconds, lessThan(2000));
        expect(o, isEmpty); // tek örneğe düştü ve o örnek pencere dışında
      });
    }

    test('yakın başlangıçlı saatlik kural hâlâ açılır', () {
      final e = ev('e', '2026-01-01T00:00:00Z',
          baslangic: '2026-11-02T08:00:00Z', bitis: '2026-11-02T08:30:00Z', rrule: 'FREQ=HOURLY;COUNT=5');
      expect(expand(e, t('2026-11-02T00:00:00Z'), t('2026-11-03T00:00:00Z')), hasLength(5));
    });

    test('COUNT ile sınırlı eski başlangıçlı kural da açılır', () {
      final e = ev('e', '2026-01-01T00:00:00Z',
          baslangic: '0001-01-01T08:00:00Z', bitis: '0001-01-01T08:30:00Z', rrule: 'FREQ=HOURLY;COUNT=3');
      expect(expand(e, t('0001-01-01T00:00:00Z'), t('0001-01-02T00:00:00Z')), hasLength(3));
    });
  });

  group('imkânsız kural pencereyi aşıp yıl 9999 sonuna kadar taramaz', () {
    test('30 Şubat kuralı hızlı biter ve örnek üretmez', () {
      final sw = Stopwatch()..start();
      final e = ev('e', '2026-01-01T00:00:00Z', rrule: 'FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30');
      expect(expand(e, t('2026-11-01T00:00:00Z'), t('2026-12-13T00:00:00Z')), isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(1000)); // eski kod ~1.9 sn
    });

    test('yıl kaydırması sonucu değiştirmez: artık yıl, hafta günü ve UNTIL', () {
      Iterable<String> gunler(String kural, String baslangic, String a, String b) => expand(
              ev('e', '2026-01-01T00:00:00Z',
                  baslangic: baslangic,
                  bitis: baslangic.replaceFirst('T07:00:00Z', 'T08:00:00Z'),
                  tzid: 'UTC',
                  rrule: kural),
              t(a),
              t(b))
          .map((o) => utcYaz(o.start));
      expect(gunler('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29', '2024-02-29T07:00:00Z', '2026-01-01T00:00:00Z', '2033-01-01T00:00:00Z'),
          ['2028-02-29T07:00:00Z', '2032-02-29T07:00:00Z']);
      expect(gunler('FREQ=WEEKLY;BYDAY=MO', '2026-01-05T07:00:00Z', '2026-11-01T00:00:00Z', '2026-11-16T00:00:00Z'),
          ['2026-11-02T07:00:00Z', '2026-11-09T07:00:00Z']);
      expect(gunler('FREQ=DAILY;UNTIL=20261103T235959Z', '2026-01-01T07:00:00Z', '2026-11-02T00:00:00Z', '2026-11-10T00:00:00Z'),
          ['2026-11-02T07:00:00Z', '2026-11-03T07:00:00Z']);
      expect(gunler('FREQ=DAILY;UNTIL=20991231T000000Z', '2026-01-01T07:00:00Z', '2026-11-02T00:00:00Z', '2026-11-04T00:00:00Z'),
          ['2026-11-02T07:00:00Z', '2026-11-03T07:00:00Z']);
    });
  });

  group('bildirim planı dosyadan gelen aşırı değerlerle kilitlenmez', () {
    final simdi = t('2026-11-03T10:00:00Z');

    test('çok sayıda günlük etkinlik + 10 yıllık hatırlatıcı hızlı planlanır', () {
      final sw = Stopwatch()..start();
      final v = veri(takvimler: [cal('c1', 'Kişisel', '2026-10-01T00:00:00Z')], etkinlikler: [
        for (var i = 0; i < 500; i++)
          ev('e$i', '2026-10-01T00:00:00Z',
              baslangic: '2000-01-01T07:00:00Z', bitis: '2000-01-01T08:00:00Z', rrule: 'FREQ=DAILY', hatirlatici: [5000000]),
      ]);
      expect(bildirimPlani(v, simdi), hasLength(60));
      expect(sw.elapsedMilliseconds, lessThan(5000)); // eski kod 500 etkinlikte ~6 sn
    });

    test('tek etkinlikte binlerce hatırlatıcıdan yalnız ilk $maksHatirlaticiAdedi planlanır', () {
      final v = veri(takvimler: [cal('c1', 'Kişisel', '2026-10-01T00:00:00Z')], etkinlikler: [
        ev('e', '2026-10-01T00:00:00Z',
            baslangic: '2026-11-04T07:00:00Z', bitis: '2026-11-04T08:00:00Z', hatirlatici: [for (var i = 1; i <= 5000; i++) i]),
      ]);
      expect(bildirimPlani(v, simdi), hasLength(maksHatirlaticiAdedi));
    });
  });

  group('içe aktarma sınırları', () {
    String dosyaOverride(int n) => disaAktarMetin(
          veri(takvimler: [cal('c1', 'Kişisel', '2026-10-01T00:00:00Z')], etkinlikler: [
            ev('e', '2026-10-01T00:00:00Z', rrule: 'FREQ=DAILY', overrides: [
              for (var i = 0; i < n; i++)
                EventOverride(
                    originalStart: t('2026-11-03T07:00:00Z').add(Duration(days: i)), newStart: t('2026-11-03T09:00:00Z')),
            ]),
          ]),
          const CihazBilgisi(id: 'x', name: 'y'),
        );

    test('etkinlik başına $maksOverride override aşılırsa dosya reddedilir, veri değişmez', () {
      final yerel = veri();
      expect(() => importEt(yerel, dosyaOverride(maksOverride + 1)), throwsA(isA<BicimHatasi>()));
      expect(yerel.events, isEmpty);
    });

    test('sınırdaki dosya kabul edilir', () {
      expect(importEt(veri(), dosyaOverride(maksOverride)).rapor.event.added, 1);
    });
  });

  group('senkron dosyası boyut sınırı', () {
    late Directory klasor;
    setUp(() => klasor = Directory.systemTemp.createTempSync('takvim_gvn_'));
    tearDown(() => klasor.deleteSync(recursive: true));

    test('sınırı aşan dosya okunmadan reddedilir', () async {
      final f = File('${klasor.path}/buyuk.takvimsync')..writeAsStringSync('x' * 100);
      await expectLater(sinirliOku(f, sinir: 99), throwsFormatException);
      expect(await sinirliOku(f, sinir: 100), hasLength(100));
    });

    test('eski paylaşım kopyaları silinir, başka dosyaya dokunulmaz', () async {
      File('${klasor.path}/takvim-20261102-1000.takvimsync').writeAsStringSync('{}');
      File('${klasor.path}/baska.txt').writeAsStringSync('dur');
      await eskiSenkronDosyalariniSil(klasor.path);
      expect(File('${klasor.path}/takvim-20261102-1000.takvimsync').existsSync(), isFalse);
      expect(File('${klasor.path}/baska.txt').existsSync(), isTrue);
    });
  });
}
