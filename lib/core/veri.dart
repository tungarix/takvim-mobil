// Bellekteki tüm takvim durumu ve değişiklik kuralları (saf Dart).
//
// Masaüstünde mezar taşlarını SQLite tetikleyicileri yazıyor; burada aynı
// kurallar mutasyon yöntemlerinde duruyor (docs/senkron.md §3):
//  - silme (etkinlik/görev/takvim; takvim silinince etkinlikleri de) mezar taşı yazar,
//  - yeniden ekleme / geri alma mezar taşını siler,
//  - override ve hatırlatıcı değişince etkinliğin updated_at'i şimdiye çekilir,
//  - mezar taşları asla budanmaz.
import 'dart:math';

import 'models.dart';
import 'recurrence.dart';
import 'seri_bol.dart';
import 'zaman.dart';

String _hex(Random r, int bayt) => List.generate(bayt, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Rastgele (v4) UUID.
String yeniUuid() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class Veri {
  Veri({DateTime Function()? saat}) : saat = saat ?? DateTime.now;

  /// Şimdiki an kaynağı; testlerde sabitlenir.
  final DateTime Function() saat;

  // shortcut: bellekte Map'ler, tek JSON dosyası; 50 bin+ etkinlikte SQLite'a geç.
  final Map<String, Calendar> calendars = {};
  final Map<String, Event> events = {};
  final Map<String, Task> tasks = {};
  final Map<String, Mezar> mezarlar = {}; // anahtar "kind:uid"

  DateTime get simdi => saniyeye(saat());

  /// Modeller değişmez olduğundan harita kopyası yeterli.
  Veri kopya() => Veri(saat: saat)
    ..calendars.addAll(calendars)
    ..events.addAll(events)
    ..tasks.addAll(tasks)
    ..mezarlar.addAll(mezarlar);

  /// Dosya gövdesi: sıralı (aynı durum -> aynı çıktı).
  Map<String, dynamic> toJson() {
    List<Map<String, dynamic>> sirali<T>(Iterable<T> v, String Function(T) anahtar, Map<String, dynamic> Function(T) json) =>
        (v.toList()..sort((a, b) => anahtar(a).compareTo(anahtar(b)))).map(json).toList();
    return {
      'calendars': sirali<Calendar>(calendars.values, (c) => c.uid, (c) => c.toJson()),
      'events': sirali<Event>(events.values, (e) => e.uid, (e) => e.toJson()),
      'tasks': sirali<Task>(tasks.values, (t) => t.uid, (t) => t.toJson()),
      'deleted': sirali<Mezar>(mezarlar.values, (m) => m.anahtar, (m) => m.toJson()),
    };
  }

  /// Ayrıştırma: herhangi bir kayıt bozuksa BicimHatasi (hiçbir şey dönmez).
  static Veri fromJson(Map<String, dynamic> j, {DateTime Function()? saat}) {
    List<Object?> liste(String k) {
      final v = j[k];
      if (v is List<Object?>) return v;
      throw BicimHatasi('"$k" dizi olmalı');
    }

    final v = Veri(saat: saat);
    try {
      for (final c in liste('calendars').map(Calendar.fromJson)) {
        v.calendars[c.uid] = c;
      }
      for (final e in liste('events').map(Event.fromJson)) {
        v.events[e.uid] = e;
      }
      for (final t in liste('tasks').map(Task.fromJson)) {
        v.tasks[t.uid] = t;
      }
      for (final m in liste('deleted').map(Mezar.fromJson)) {
        v.mezarlar[m.anahtar] = m;
      }
    } on BicimHatasi {
      rethrow;
    } on FormatException catch (e) {
      throw BicimHatasi(e.message);
    } on ArgumentError catch (e) {
      throw BicimHatasi('${e.message}');
    } on TypeError catch (e) {
      throw BicimHatasi('beklenmeyen tip: $e');
    }
    return v;
  }

  // ------------------------------------------------------------ iç yardımcılar

  void _mezarKaldir(String kind, String uid) => mezarlar.remove('$kind:$uid');

  void _mezarYaz(String kind, String uid, DateTime at) => mezarlar['$kind:$uid'] = Mezar(kind, uid, at);

  /// Etkinlik silinince ona bağlı görev plansıza döner (masaüstünde FK SET NULL;
  /// updated_at değişmez, çünkü diğer cihazda da aynı silme aynı sonucu verir).
  void _bloguBirak(String eventUid) {
    for (final t in tasks.values.toList()) {
      if (t.eventUid == eventUid) tasks[t.uid] = t.kopya(plan: (planDay: null, eventUid: null));
    }
  }

  /// Görevi `at` anlı mezar taşıyla siler (bağlı bloğa dokunmaz).
  void silGorev(String uid, DateTime at) {
    tasks.remove(uid);
    _mezarYaz('task', uid, at);
  }

  Event _etkinlik(String uid) => events[uid] ?? (throw StateError('Etkinlik bulunamadı: $uid'));
  Task _gorev(String uid) => tasks[uid] ?? (throw StateError('Görev bulunamadı: $uid'));

  // ----------------------------------------------------------------- takvim

  Calendar addCalendar(String name, String color, {bool visible = true, String? uid}) {
    final c = Calendar(uid: uid ?? _hex(Random.secure(), 16), name: name, color: color, visible: visible, updatedAt: simdi);
    calendars[c.uid] = c;
    _mezarKaldir('calendar', c.uid);
    return c;
  }

  void updateCalendar(Calendar c) {
    if (!calendars.containsKey(c.uid)) throw StateError('Takvim bulunamadı: ${c.uid}');
    calendars[c.uid] = c.copyWith(updatedAt: simdi);
  }

  /// Takvimi ve etkinliklerini siler; her biri için mezar taşı yazar.
  void deleteCalendar(String uid) {
    if (!calendars.containsKey(uid)) throw StateError('Takvim bulunamadı: $uid');
    silTakvim(uid, simdi);
  }

  /// Mezar taşını `at` anıyla yazarak takvimi ve etkinliklerini siler (içe
  /// aktarmada dosyadaki an aynen gelir). Silinen etkinlik sayısını döndürür.
  int silTakvim(String uid, DateTime at) {
    calendars.remove(uid);
    final silinecek = events.values.where((e) => e.calendarUid == uid).map((e) => e.uid).toList();
    for (final e in silinecek) {
      silEtkinlik(e, at);
    }
    _mezarYaz('calendar', uid, at);
    return silinecek.length;
  }

  // -------------------------------------------------------------- etkinlik

  /// Etkinlik ekler (created/updated şimdi). Aynı uid ile çağrılırsa geri alma /
  /// yeniden ekleme olur: mezar taşı silinir, updated_at şimdiye çekilir ki
  /// diğer cihazdaki silme kazanmasın.
  Event addEvent(Event e) {
    if (!calendars.containsKey(e.calendarUid)) throw StateError('Takvim bulunamadı: ${e.calendarUid}');
    final now = simdi;
    final yeni = Event(
      uid: e.uid, calendarUid: e.calendarUid, title: e.title, description: e.description, location: e.location,
      start: e.start, end: e.end, tzid: e.tzid, allDay: e.allDay, rrule: e.rrule, rdate: e.rdate, exdate: e.exdate,
      reminders: e.reminders, overrides: e.overrides, createdAt: events[e.uid]?.createdAt ?? e.createdAt, updatedAt: now,
    );
    events[yeni.uid] = yeni;
    _mezarKaldir('event', yeni.uid);
    return yeni;
  }

  /// Etkinliği günceller; bağlı görev bloğuysa başlık/açıklama göreve de yansır
  /// (masaüstüyle aynı), tekrarlı/tüm gün yapılamaz.
  void updateEvent(Event e) {
    final eski = _etkinlik(e.uid);
    if (!calendars.containsKey(e.calendarUid)) throw StateError('Takvim bulunamadı: ${e.calendarUid}');
    final now = simdi;
    final bagli = tasks.values.where((t) => t.eventUid == e.uid).toList();
    if (bagli.isNotEmpty && (e.isRecurring || e.allDay)) {
      throw ArgumentError('görev bloğu tekrarlı ya da tüm gün olamaz');
    }
    events[e.uid] = Event(
      uid: e.uid, calendarUid: e.calendarUid, title: e.title, description: e.description, location: e.location,
      start: e.start, end: e.end, tzid: e.tzid, allDay: e.allDay, rrule: e.rrule, rdate: e.rdate, exdate: e.exdate,
      reminders: e.reminders, overrides: e.overrides, createdAt: eski.createdAt, updatedAt: now,
    );
    for (final t in bagli) {
      tasks[t.uid] = Task(
        uid: t.uid, title: e.title, notes: e.description, planDay: t.planDay, eventUid: t.eventUid,
        doneAt: t.doneAt, createdAt: t.createdAt, updatedAt: now,
      );
    }
  }

  /// "Bu ve sonrakiler": seriyi `split` (bir örneğin ORİJİNAL başlangıcı) noktasında
  /// böler; eski seri kısalır, yeni seri (yeni uid) eklenir ve döndürülür.
  /// Hatırlatıcılar etkinliğin parçası olduğundan iki tarafa da kopyalanır.
  /// İlk örnekten bölünemez (ArgumentError).
  Event seriyiBol(String eventUid, DateTime split) {
    final e = _etkinlik(eventUid);
    final r = seriBol(e, split, yeniUid: '${yeniUuid()}@takvim.local', simdi: simdi);
    events[e.uid] = r.eski;
    events[r.yeni.uid] = r.yeni;
    _mezarKaldir('event', r.yeni.uid);
    return r.yeni;
  }

  /// "Bu ve sonrakileri sil": seriyi `split`te keser, sonrasını yazmaz.
  void seriyiKes(String eventUid, DateTime split) {
    final e = _etkinlik(eventUid);
    events[e.uid] = seriBol(e, split, yeniUid: '', simdi: simdi).eski;
  }

  void deleteEvent(String uid) {
    _etkinlik(uid);
    silEtkinlik(uid, simdi);
  }

  /// Etkinliği `at` anlı mezar taşıyla siler; bağlı görev plansıza döner.
  void silEtkinlik(String uid, DateTime at) {
    events.remove(uid);
    _mezarYaz('event', uid, at);
    _bloguBirak(uid);
  }

  // Override ve hatırlatıcı etkinliğin parçasıdır: değişince updated_at şimdi.
  void _etkinlikGuncelle(String uid, {List<EventOverride>? overrides, List<int>? reminders}) {
    final e = _etkinlik(uid);
    events[uid] = e.copyWith(overrides: overrides, reminders: reminders, updatedAt: simdi);
  }

  /// Override ekler ya da orijinal başlangıç üzerinden günceller. new_start verilip
  /// new_end verilmediyse bitiş etkinlik süresinden hesaplanıp yazılır (masaüstüyle aynı).
  void putOverride(String eventUid, EventOverride ov) {
    final e = _etkinlik(eventUid);
    final cozulmus = (ov.newStart != null && ov.newEnd == null)
        ? EventOverride(
            originalStart: ov.originalStart, cancelled: ov.cancelled, newStart: ov.newStart,
            newEnd: ov.newStart!.add(e.duration), newTitle: ov.newTitle, newLocation: ov.newLocation)
        : ov;
    _etkinlikGuncelle(eventUid, overrides: [...e.overrides.where((o) => o.originalStart != ov.originalStart), cozulmus]);
  }

  void deleteOverride(String eventUid, DateTime originalStart) {
    final e = _etkinlik(eventUid);
    final o = saniyeye(originalStart);
    _etkinlikGuncelle(eventUid, overrides: e.overrides.where((x) => x.originalStart != o).toList());
  }

  void cancelOccurrence(String eventUid, DateTime originalStart) =>
      putOverride(eventUid, EventOverride(originalStart: originalStart, cancelled: true));

  void moveOccurrence(String eventUid, DateTime originalStart, DateTime newStart, [DateTime? newEnd]) =>
      putOverride(eventUid, EventOverride(originalStart: originalStart, newStart: newStart, newEnd: newEnd));

  void addReminder(String eventUid, int minutesBefore) {
    if (minutesBefore < 0) throw ArgumentError('hatırlatıcı negatif olamaz');
    final e = _etkinlik(eventUid);
    if (e.reminders.contains(minutesBefore)) return; // aynısı varsa dokunma
    _etkinlikGuncelle(eventUid, reminders: [...e.reminders, minutesBefore]);
  }

  void deleteReminder(String eventUid, int minutesBefore) {
    final e = _etkinlik(eventUid);
    if (!e.reminders.contains(minutesBefore)) return;
    _etkinlikGuncelle(eventUid, reminders: e.reminders.where((m) => m != minutesBefore).toList());
  }

  // ------------------------------------------------------------------ görev

  Task addTask(String title, {String? notes, String? uid}) {
    final now = simdi;
    final t = Task(uid: uid ?? '${yeniUuid()}@takvim.local', title: title, notes: notes, createdAt: now, updatedAt: now);
    tasks[t.uid] = t;
    _mezarKaldir('task', t.uid);
    return t;
  }

  /// Başlık/not günceller; bağlı blok varsa onunki de aynı olur. Plan ve tamamlanma
  /// ayrı yöntemlerle değişir (bayat nesne planı sessizce geri almasın).
  void updateTask(String uid, {String? title, String? notes}) {
    final t = _gorev(uid);
    final now = simdi;
    final yeni = Task(
      uid: uid, title: title ?? t.title, notes: notes ?? t.notes, planDay: t.planDay, eventUid: t.eventUid,
      doneAt: t.doneAt, createdAt: t.createdAt, updatedAt: now,
    );
    tasks[uid] = yeni;
    final blok = yeni.eventUid == null ? null : events[yeni.eventUid];
    if (blok != null) {
      events[blok.uid] = Event(
        uid: blok.uid, calendarUid: blok.calendarUid, title: yeni.title, description: yeni.notes, location: blok.location,
        start: blok.start, end: blok.end, tzid: blok.tzid, allDay: blok.allDay, rrule: blok.rrule, rdate: blok.rdate,
        exdate: blok.exdate, reminders: blok.reminders, overrides: blok.overrides, createdAt: blok.createdAt, updatedAt: now,
      );
    }
  }

  void setTaskDone(String uid, bool done, {DateTime? at}) {
    final t = _gorev(uid);
    tasks[uid] = t.kopya(doneAt: done ? (at ?? simdi) : null, doneTemizle: !done, updatedAt: simdi);
  }

  /// Görevi bir GÜNE planlar (saatsiz); varsa bağlı blok silinir (mezar taşıyla).
  void planTaskDay(String uid, String day) {
    final t = _gorev(uid);
    final now = simdi;
    if (t.eventUid != null && events.containsKey(t.eventUid)) silEtkinlik(t.eventUid!, now);
    tasks[uid] = _gorev(uid).kopya(plan: (planDay: day, eventUid: null), updatedAt: now);
  }

  void clearTaskPlan(String uid) {
    final t = _gorev(uid);
    final now = simdi;
    if (t.eventUid != null && events.containsKey(t.eventUid)) silEtkinlik(t.eventUid!, now);
    tasks[uid] = _gorev(uid).kopya(plan: (planDay: null, eventUid: null), updatedAt: now);
  }

  /// Görevi belirli SAATLERE planlar: göreve bağlı bir blok olur. Blok zaten
  /// varsa yenisi açılmaz, mevcut blok taşınır (eski override'lar silinir).
  void planTaskSlot(String uid, DateTime start, DateTime end, String calendarUid, String tzid) {
    final t = _gorev(uid);
    if (!calendars.containsKey(calendarUid)) throw StateError('Takvim bulunamadı: $calendarUid');
    final now = simdi;
    final mevcut = t.eventUid == null ? null : events[t.eventUid];
    final blokUid = mevcut?.uid ?? '${yeniUuid()}@takvim.local';
    events[blokUid] = Event(
      uid: blokUid, calendarUid: calendarUid, title: t.title, description: t.notes, start: start, end: end, tzid: tzid,
      createdAt: mevcut?.createdAt ?? now, updatedAt: now,
    );
    _mezarKaldir('event', blokUid);
    tasks[uid] = t.kopya(plan: (planDay: null, eventUid: blokUid), updatedAt: now);
  }

  /// Görevi siler; bağlı blok da gider (ikisi için mezar taşı).
  void deleteTask(String uid) {
    final t = _gorev(uid);
    final now = simdi;
    silGorev(uid, now);
    if (t.eventUid != null && events.containsKey(t.eventUid)) silEtkinlik(t.eventUid!, now);
  }

  /// Silinen görevi (ve varsa bloğunu) geri koyar; plan/tamamlanma korunur.
  /// Mezar taşları kalkar, updated_at şimdi olur (diğer cihazdaki silme kazanmasın).
  void geriYukleGorev(Task t, {Event? blok}) {
    if (blok != null) addEvent(blok);
    tasks[t.uid] = t.kopya(updatedAt: simdi);
    _mezarKaldir('task', t.uid);
  }

  // --------------------------------------------------------------- sorgular

  /// Pencereye düşen tüm örnekler, başlangıca göre sıralı. Gizli takvimler
  /// varsayılan olarak dışarıda.
  List<Occurrence> occurrences(
    DateTime windowStart,
    DateTime windowEnd, {
    Set<String>? calendarUids,
    bool includeHidden = false,
  }) {
    final out = <Occurrence>[];
    for (final e in events.values) {
      final c = calendars[e.calendarUid];
      if (c == null || (!includeHidden && !c.visible)) continue;
      if (calendarUids != null && !calendarUids.contains(e.calendarUid)) continue;
      // shortcut: her etkinlik açılıyor (series_end ön süzgeci yok), küçük veride yeter.
      out.addAll(expand(e, windowStart, windowEnd));
    }
    out.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      final d = a.end.compareTo(b.end);
      return d != 0 ? d : a.eventUid.compareTo(b.eventUid);
    });
    return out;
  }
}
