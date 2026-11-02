// Çekirdek veri tipleri (docs/senkron.md §1'deki alanlarla birebir).
//
// Hepsi değişmez (immutable); değiştirmek için copyWith. Doğrulama kurucuda:
// bozuk bir Event/Task oluşturmak mümkün değil. Anahtar her yerde `uid`;
// masaüstündeki yerel tamsayı id'ler dosyaya ve buraya girmez.
import 'zaman.dart';

Map<String, dynamic> _nesne(Object? v, String yol) {
  if (v is Map<String, dynamic>) return v;
  throw FormatException('$yol nesne olmalı');
}

String _metin(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is String) return v;
  throw FormatException('"$k" metin olmalı');
}

String? _metinYa(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is String) return v;
  throw FormatException('"$k" metin ya da null olmalı');
}

bool _mantik(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is bool) return v;
  throw FormatException('"$k" true/false olmalı');
}

DateTime _zaman(Map<String, dynamic> m, String k) => utcOku(_metin(m, k));

DateTime? _zamanYa(Map<String, dynamic> m, String k) {
  final s = _metinYa(m, k);
  return s == null ? null : utcOku(s);
}

List<Object?> _liste(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is List<Object?>) return v;
  throw FormatException('"$k" dizi olmalı');
}

List<DateTime> _zamanlar(Iterable<DateTime> v) {
  final out = {for (final d in v) saniyeye(d)}.toList()..sort();
  return List.unmodifiable(out);
}

class Calendar {
  Calendar({
    required this.uid,
    required String name,
    required this.color,
    this.visible = true,
    required DateTime updatedAt,
  })  : name = name.trim(),
        updatedAt = saniyeye(updatedAt) {
    if (this.name.isEmpty) throw ArgumentError('takvim adı boş olamaz (uid=$uid)');
  }

  final String uid;
  final String name;
  final String color;
  final bool visible;
  final DateTime updatedAt;

  factory Calendar.fromJson(Object? j) {
    final m = _nesne(j, 'takvim');
    return Calendar(
      uid: _metin(m, 'uid'),
      name: _metin(m, 'name'),
      color: _metin(m, 'color'),
      visible: _mantik(m, 'visible'),
      updatedAt: _zaman(m, 'updated_at'),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'color': color,
        'visible': visible,
        'updated_at': utcYaz(updatedAt),
      };

  Calendar copyWith({String? uid, String? name, String? color, bool? visible, DateTime? updatedAt}) => Calendar(
        uid: uid ?? this.uid,
        name: name ?? this.name,
        color: color ?? this.color,
        visible: visible ?? this.visible,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// RFC 5545 RECURRENCE-ID karşılığı: serinin tek bir örneğini iptal eder/değiştirir.
/// `originalStart` hedeflenen örneğin ORİJİNAL başlangıcıdır (kaydırılmış hâli değil).
class EventOverride {
  EventOverride({
    required DateTime originalStart,
    this.cancelled = false,
    DateTime? newStart,
    DateTime? newEnd,
    this.newTitle,
    this.newLocation,
  })  : originalStart = saniyeye(originalStart),
        newStart = newStart == null ? null : saniyeye(newStart),
        newEnd = newEnd == null ? null : saniyeye(newEnd) {
    if (this.newStart != null && this.newEnd != null && this.newEnd!.isBefore(this.newStart!)) {
      throw ArgumentError('new_end_utc, new_start_utc\'den önce olamaz');
    }
  }

  final DateTime originalStart;
  final bool cancelled;
  final DateTime? newStart;
  final DateTime? newEnd;
  final String? newTitle;
  final String? newLocation;

  factory EventOverride.fromJson(Object? j) {
    final m = _nesne(j, 'override');
    return EventOverride(
      originalStart: _zaman(m, 'original_start_utc'),
      cancelled: _mantik(m, 'cancelled'),
      newStart: _zamanYa(m, 'new_start_utc'),
      newEnd: _zamanYa(m, 'new_end_utc'),
      newTitle: _metinYa(m, 'new_title'),
      newLocation: _metinYa(m, 'new_location'),
    );
  }

  Map<String, dynamic> toJson() => {
        'original_start_utc': utcYaz(originalStart),
        'cancelled': cancelled,
        'new_start_utc': newStart == null ? null : utcYaz(newStart!),
        'new_end_utc': newEnd == null ? null : utcYaz(newEnd!),
        'new_title': newTitle,
        'new_location': newLocation,
      };
}

class Event {
  Event({
    required this.uid,
    required this.calendarUid,
    required this.title,
    this.description,
    this.location,
    required DateTime start,
    required DateTime end,
    required this.tzid,
    this.allDay = false,
    String? rrule,
    Iterable<DateTime> rdate = const [],
    Iterable<DateTime> exdate = const [],
    Iterable<int> reminders = const [],
    Iterable<EventOverride> overrides = const [],
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : start = saniyeye(start),
        end = saniyeye(end),
        rrule = rrule?.trim(),
        rdate = _zamanlar(rdate),
        exdate = _zamanlar(exdate),
        reminders = List.unmodifiable(({...reminders}.toList()..sort())),
        overrides = List.unmodifiable(_overrideSirala(overrides)),
        createdAt = saniyeye(createdAt),
        updatedAt = saniyeye(updatedAt) {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('end_utc > start_utc olmalı (uid=$uid)');
    }
    if (this.rrule != null && this.rrule!.isEmpty) {
      throw ArgumentError('rrule boş metin olamaz; tekrar yoksa null kullan');
    }
    for (final r in this.reminders) {
      if (r < 0) throw ArgumentError('hatırlatıcı negatif olamaz: $r');
    }
    konumBul(tzid); // geçersiz IANA adı burada patlar
  }

  final String uid;
  final String calendarUid;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final String tzid;
  final bool allDay;
  final String? rrule;
  final List<DateTime> rdate;
  final List<DateTime> exdate;
  final List<int> reminders; // dakika cinsinden "ne kadar önce"
  final List<EventOverride> overrides;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get duration => end.difference(start);
  bool get isRecurring => (rrule != null) || rdate.isNotEmpty;

  static List<EventOverride> _overrideSirala(Iterable<EventOverride> v) {
    // Aynı orijinal başlangıca ikinci kayıt ilkinin üstüne yazar (UNIQUE kuralı).
    final m = <DateTime, EventOverride>{for (final o in v) o.originalStart: o};
    return (m.values.toList()..sort((a, b) => a.originalStart.compareTo(b.originalStart)));
  }

  factory Event.fromJson(Object? j) {
    final m = _nesne(j, 'etkinlik');
    final rem = _liste(m, 'reminders').map((e) {
      if (e is int) return e;
      throw const FormatException('"reminders" tamsayı dizisi olmalı');
    });
    return Event(
      uid: _metin(m, 'uid'),
      calendarUid: _metin(m, 'calendar_uid'),
      title: _metin(m, 'title'),
      description: _metinYa(m, 'description'),
      location: _metinYa(m, 'location'),
      start: _zaman(m, 'start_utc'),
      end: _zaman(m, 'end_utc'),
      tzid: _metin(m, 'tzid'),
      allDay: _mantik(m, 'all_day'),
      rrule: _metinYa(m, 'rrule'),
      rdate: _liste(m, 'rdate').map((e) => e is String ? utcOku(e) : throw const FormatException('"rdate" metin dizisi olmalı')),
      exdate: _liste(m, 'exdate').map((e) => e is String ? utcOku(e) : throw const FormatException('"exdate" metin dizisi olmalı')),
      reminders: rem,
      overrides: _liste(m, 'overrides').map(EventOverride.fromJson),
      createdAt: _zaman(m, 'created_at'),
      updatedAt: _zaman(m, 'updated_at'),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'calendar_uid': calendarUid,
        'title': title,
        'description': description,
        'location': location,
        'start_utc': utcYaz(start),
        'end_utc': utcYaz(end),
        'tzid': tzid,
        'all_day': allDay,
        'rrule': rrule,
        'rdate': [for (final d in rdate) utcYaz(d)],
        'exdate': [for (final d in exdate) utcYaz(d)],
        'reminders': reminders,
        'overrides': [for (final o in overrides) o.toJson()],
        'created_at': utcYaz(createdAt),
        'updated_at': utcYaz(updatedAt),
      };

  /// Null'a çekilebilen alanlar için `Function()` yerine yalın kural: bu alanlar
  /// (description/location/rrule) copyWith ile null yapılamaz, yeni Event kur.
  Event copyWith({
    String? calendarUid,
    String? title,
    DateTime? start,
    DateTime? end,
    String? tzid,
    bool? allDay,
    List<DateTime>? rdate,
    List<DateTime>? exdate,
    List<int>? reminders,
    List<EventOverride>? overrides,
    DateTime? updatedAt,
  }) =>
      Event(
        uid: uid,
        calendarUid: calendarUid ?? this.calendarUid,
        title: title ?? this.title,
        description: description,
        location: location,
        start: start ?? this.start,
        end: end ?? this.end,
        tzid: tzid ?? this.tzid,
        allDay: allDay ?? this.allDay,
        rrule: rrule,
        rdate: rdate ?? this.rdate,
        exdate: exdate ?? this.exdate,
        reminders: reminders ?? this.reminders,
        overrides: overrides ?? this.overrides,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Yapılacaklar listesindeki görev. Ne zaman yapılacağı üç hâlden biri:
/// plansız / gün planlı (`planDay`) / saat planlı (`eventUid` zaman bloğunu
/// gösterir; saat blokta durur). `planDay` ve `eventUid` aynı anda dolu olamaz.
class Task {
  Task({
    required this.uid,
    required String title,
    String? notes,
    String? planDay,
    this.eventUid,
    DateTime? doneAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : title = title.trim(),
        notes = (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        planDay = planDay == null ? null : gunDogrula(planDay),
        doneAt = doneAt == null ? null : saniyeye(doneAt),
        createdAt = saniyeye(createdAt),
        updatedAt = saniyeye(updatedAt) {
    if (this.title.isEmpty) throw ArgumentError('görev başlığı boş olamaz (uid=$uid)');
    if (this.planDay != null && eventUid != null) {
      throw ArgumentError('görev hem gün hem saat planlı olamaz (uid=$uid)');
    }
  }

  final String uid;
  final String title;
  final String? notes;
  final String? planDay; // YYYY-MM-DD duvar günü
  final String? eventUid;
  final DateTime? doneAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get done => doneAt != null;

  factory Task.fromJson(Object? j) {
    final m = _nesne(j, 'görev');
    return Task(
      uid: _metin(m, 'uid'),
      title: _metin(m, 'title'),
      notes: _metinYa(m, 'notes'),
      planDay: _metinYa(m, 'plan_day'),
      eventUid: _metinYa(m, 'event_uid'),
      doneAt: _zamanYa(m, 'done_at'),
      createdAt: _zaman(m, 'created_at'),
      updatedAt: _zaman(m, 'updated_at'),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'notes': notes,
        'plan_day': planDay,
        'event_uid': eventUid,
        'done_at': doneAt == null ? null : utcYaz(doneAt!),
        'created_at': utcYaz(createdAt),
        'updated_at': utcYaz(updatedAt),
      };

  /// Plan alanları (planDay/eventUid) null'lanabilsin diye ayrı kurucu yerine
  /// açık parametre: `plan: ...` verilirse ikisi birden bu değerlerle yazılır.
  Task kopya({
    String? title,
    String? notes,
    DateTime? doneAt,
    bool doneTemizle = false,
    ({String? planDay, String? eventUid})? plan,
    DateTime? updatedAt,
  }) =>
      Task(
        uid: uid,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        planDay: plan != null ? plan.planDay : planDay,
        eventUid: plan != null ? plan.eventUid : eventUid,
        doneAt: doneTemizle ? null : (doneAt ?? this.doneAt),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Silinen kaydın mezar taşı: `kind` calendar | event | task. Budanmaz.
class Mezar {
  Mezar(this.kind, this.uid, DateTime deletedAt) : deletedAt = saniyeye(deletedAt) {
    if (!turler.contains(kind)) throw ArgumentError('bilinmeyen silinen türü: "$kind"');
  }

  static const turler = {'calendar', 'event', 'task'};

  final String kind;
  final String uid;
  final DateTime deletedAt;

  String get anahtar => '$kind:$uid';

  factory Mezar.fromJson(Object? j) {
    final m = _nesne(j, 'silinen');
    return Mezar(_metin(m, 'kind'), _metin(m, 'uid'), _zaman(m, 'deleted_at'));
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'uid': uid, 'deleted_at': utcYaz(deletedAt)};
}
