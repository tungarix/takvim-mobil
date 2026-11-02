// Hatırlatıcı mantığı, saf (masaüstündeki core/reminders.py). Ne zaman
// tetikleneceğine burası karar verir; bildirimi kimin göstereceğini bilmez.
import 'recurrence.dart';

class DueReminder {
  DueReminder(this.occurrence, this.minutesBefore, this.fireAt);
  final Occurrence occurrence;
  final int minutesBefore;
  final DateTime fireAt;
}

/// Hatırlatıcı-örnek çiftinin tekil anahtarı (cihaza özel "tetiklendi" kaydı için).
String fireKey(String eventUid, int minutesBefore, Occurrence o) =>
    '$eventUid|$minutesBefore|${o.start.toUtc().millisecondsSinceEpoch}';

/// Şu an tetiklenmesi gerekenler: `fire_at <= now`, örnek henüz BİTMEMİŞ ve daha
/// önce tetiklenmemiş. Bitmiş örnekler atlanır: uygulama bir hafta kapalı kalıp
/// açılınca geçmişin tüm bildirimlerini yığmak işe yaramaz.
List<DueReminder> dueReminders(
  List<Occurrence> occurrences,
  Map<String, List<int>> remindersByEvent,
  DateTime now, {
  Set<String> alreadyFired = const {},
}) {
  now = now.toUtc();
  final out = <DueReminder>[];
  for (final o in occurrences) {
    for (final m in remindersByEvent[o.eventUid] ?? const <int>[]) {
      final fireAt = o.start.subtract(Duration(minutes: m));
      if (fireAt.isAfter(now)) continue;
      if (!o.end.isAfter(now)) continue;
      if (alreadyFired.contains(fireKey(o.eventUid, m, o))) continue;
      out.add(DueReminder(o, m, fireAt));
    }
  }
  out.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    if (c != 0) return c;
    final d = a.occurrence.start.compareTo(b.occurrence.start);
    return d != 0 ? d : a.occurrence.eventUid.compareTo(b.occurrence.eventUid);
  });
  return out;
}

/// Gelecekteki en yakın tetiklenme anı; yoksa null (arka plan uykusu için).
DateTime? nextFireTime(List<Occurrence> occurrences, Map<String, List<int>> remindersByEvent, DateTime now) {
  now = now.toUtc();
  DateTime? en;
  for (final o in occurrences) {
    for (final m in remindersByEvent[o.eventUid] ?? const <int>[]) {
      final t = o.start.subtract(Duration(minutes: m));
      if (t.isAfter(now) && (en == null || t.isBefore(en))) en = t;
    }
  }
  return en;
}
