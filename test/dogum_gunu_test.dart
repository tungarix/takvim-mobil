// Doğum günü kaydının saf kurulumu: RRULE, DTSTART, 29 Şubat.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/yerel_zaman.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/ui/dogum_gunu.dart';

import 'yardimci.dart';

void main() {
  final bugun = DateTime.utc(2026, 11, 3);

  group('dogumGunuKur', () {
    test('yıl verilirse DTSTART o yılın tarihi, kural yalnız FREQ=YEARLY', () {
      final r = dogumGunuKur(ay: 5, gun: 3, yil: 1990, bugun: bugun);
      expect(r.baslangic, DateTime.utc(1990, 5, 3));
      expect(r.rrule, 'FREQ=YEARLY');
    });

    test('yıl yoksa bu yılın tarihi; geçmişse gelecek yıl; bugünse bugün', () {
      expect(dogumGunuKur(ay: 12, gun: 25, bugun: bugun).baslangic, DateTime.utc(2026, 12, 25));
      expect(dogumGunuKur(ay: 5, gun: 3, bugun: bugun).baslangic, DateTime.utc(2027, 5, 3));
      expect(dogumGunuKur(ay: 11, gun: 3, bugun: bugun).baslangic, DateTime.utc(2026, 11, 3));
    });

    test('29 Şubat: ayın son günü kuralı; artık olmayan yılda 28 Şubat', () {
      final a = dogumGunuKur(ay: 2, gun: 29, yil: 2000, bugun: bugun);
      expect(a.baslangic, DateTime.utc(2000, 2, 29));
      expect(a.rrule, 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1');
      expect(dogumGunuKur(ay: 2, gun: 29, bugun: bugun).baslangic, DateTime.utc(2027, 2, 28));
      expect(dogumGunuKur(ay: 2, gun: 29, bugun: DateTime.utc(2027, 11, 3)).baslangic, DateTime.utc(2028, 2, 29));
    });

    test('29 Şubat serisi artık olmayan yılda 28 Şubat, artık yılda 29 Şubat gelir', () {
      final r = dogumGunuKur(ay: 2, gun: 29, yil: 2000, bugun: bugun);
      final etz = YerelZaman('UTC');
      final e = ev('d', '2026-01-01T00:00:00Z',
          baslangic: utcYaz(etz.utc(r.baslangic)), bitis: utcYaz(etz.utc(gunEkle(r.baslangic, 1))), tzid: 'UTC', rrule: r.rrule, tumGun: true);
      final gunler = expand(e, t('2026-01-01T00:00:00Z'), t('2029-01-01T00:00:00Z')).map((o) => utcYaz(o.start).substring(0, 10));
      expect(gunler, ['2026-02-28', '2027-02-28', '2028-02-29']);
    });
  });
}
