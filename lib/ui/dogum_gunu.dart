// Doğum günü = tüm gün, yıllık tekrarlayan NORMAL etkinlik; veri biçimi değişmez (masaüstüyle
// senkron uyumu için ayrı bir tür yok). Burası hem kaydı kurar hem de böyle bir etkinliği tanır.
import '../app/kontrol.dart';
import '../core/recurrence.dart';
import '../core/yerel_zaman.dart';
import 'metin.dart';

const _yillik = 'FREQ=YEARLY';
// 29 Şubat: ayın SON günü; artık olmayan yılda 28 Şubat'ta kutlanır (dateutil ve rrule ikisi de çözer).
const _subatSonu = 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1';

/// Yeni doğum günü kaydı: ilk günün duvar tarihi (00:00, sahte UTC) ve RRULE.
class DogumGunuKaydi {
  const DogumGunuKaydi(this.baslangic, this.rrule);
  final DateTime baslangic;
  final String rrule;
}

/// `yil` verilirse DTSTART o yılın tarihi; verilmezse bu yılın, geçmişse gelecek yılın tarihi.
/// `bugun` duvar günü. 29 Şubat artık olmayan yılda 28 Şubat'a iner.
DogumGunuKaydi dogumGunuKur({required int ay, required int gun, int? yil, required DateTime bugun}) {
  final subat29 = ay == 2 && gun == 29;
  DateTime gunuKur(int y) => DateTime.utc(y, ay, subat29 ? DateTime.utc(y, 3, 0).day : gun);
  var bas = gunuKur(yil ?? bugun.year);
  if (yil == null && bas.isBefore(gunDuvar(bugun))) bas = gunuKur(bugun.year + 1);
  return DogumGunuKaydi(bas, subat29 ? _subatSonu : _yillik);
}

/// Doğum günü kalıbına uyan etkinlikte `yas` (yıl biliniyorsa ve bu örnekte 0'dan büyükse).
/// Yıl bilinmiyorsa DTSTART yılı kayıt yılıdır (ya da ertesi yıl); kayıt yılından küçükse
/// gerçek doğum yılıdır. Aynı yıl doğan bebek için yaş gösterilmez (ayırt edilemez).
({int? yas})? dogumGunuBilgisi(TakvimKontrol k, Occurrence o) {
  final e = k.veri.events[o.eventUid];
  if (e == null || !e.allDay || !e.title.endsWith(M.dogumGunuSonek)) return null;
  final kural = e.rrule?.toUpperCase();
  if (kural != _yillik && kural != _subatSonu) return null;
  final tz = YerelZaman(e.tzid);
  final dogum = tz.duvar(e.start).year;
  if (dogum >= tz.duvar(e.createdAt).year) return (yas: null);
  final yas = tz.duvar(o.start).year - dogum;
  return (yas: yas > 0 ? yas : null);
}
