// Hatırlatıcı bildirim planı (saf Dart): hangi bildirim ne zaman çalacak.
//
// Android, uygulama kapalıyken de bildirimi göstermek için alarmı önceden
// ister; bu yüzden "şimdi tetiklenmesi gerekenler" (reminders.dart) yetmez,
// önümüzdeki bir pencere planlanır ve her veri değişiminde yeniden kurulur.
import 'recurrence.dart';
import 'reminders.dart';
import 'veri.dart';

class PlanliBildirim {
  const PlanliBildirim(this.id, this.ornek, this.dakikaOnce, this.tetik);

  /// Bildirim kimliği: (etkinlik, dakika, örnek) üçlüsünden kararlı türetilir;
  /// aynı plan yeniden kurulunca aynı kimlikleri üretir.
  final int id;
  final Occurrence ornek;
  final int dakikaOnce;
  final DateTime tetik;
}

/// Bir etkinlik için planlanacak en çok hatırlatıcı sayısı (küçükten başlayarak). Dosyadan gelen
/// binlerce hatırlatıcılı bir kayıt planı kilitlemesin; arayüz zaten bu kadarını sunmuyor.
const maksHatirlaticiAdedi = 20;

/// FNV-1a, 31 bit pozitif (Android bildirim kimliği int).
int _kimlik(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// `simdi`den sonraki `pencere` içinde tetiklenecek hatırlatıcılar, en erken
/// `maks` tanesi. Gizli takvimler ve tamamlanmış görev blokları susar
/// (masaüstü kural 71/hidden ile aynı).
List<PlanliBildirim> bildirimPlani(
  Veri v,
  DateTime simdi, {
  Duration pencere = const Duration(days: 14),
  int maks = 60,
}) {
  final simdiU = simdi.toUtc();
  final sinir = simdiU.add(pencere);
  final bittiBlok = {
    for (final t in v.tasks.values)
      if (t.done && t.eventUid != null) t.eventUid!,
  };
  final hat = {
    for (final e in v.events.values)
      if (e.reminders.isNotEmpty && !bittiBlok.contains(e.uid)) e.uid: e,
  };
  if (hat.isEmpty) return [];

  final out = <PlanliBildirim>[];
  final gorulen = <int>{};
  for (final e in hat.values) {
    // Gizli takvimler susar (Veri.occurrences ile aynı kural).
    final c = v.calendars[e.calendarUid];
    if (c == null || !c.visible) continue;
    // Her hatırlatıcı için yalnız tetiğin düşeceği başlangıç aralığı açılır: [şimdi+m, sınır+m].
    // Eskiden TÜM etkinlikler en uzun hatırlatıcı (10 yıla kadar) kadar uzun pencerede açılıyordu:
    // dosyadan gelen tek büyük hatırlatıcı 2000 etkinlikte planı 23 sn kilitledi.
    for (final m in e.reminders.take(maksHatirlaticiAdedi)) {
      final fark = Duration(minutes: m);
      for (final o in expand(e, simdiU.add(fark), sinir.add(fark).add(const Duration(seconds: 1)))) {
        final tetik = o.start.subtract(fark);
        if (!tetik.isAfter(simdiU) || tetik.isAfter(sinir)) continue;
        final id = _kimlik(fireKey(o.eventUid, m, o));
        if (gorulen.add(id)) out.add(PlanliBildirim(id, o, m, tetik));
      }
    }
  }
  out.sort((a, b) {
    final c = a.tetik.compareTo(b.tetik);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out.length > maks ? out.sublist(0, maks) : out;
}
