// Testlerin ortak kurucuları.
import 'dart:convert';

import 'package:takvim/core/models.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/export.dart';

DateTime t(String s) => utcOku(s);

/// Elle ilerletilen saat.
class Saat {
  Saat([String baslangic = '2026-11-02T10:00:00Z']) : simdi = t(baslangic);
  DateTime simdi;
  DateTime call() => simdi;
  void ilerle([Duration d = const Duration(minutes: 1)]) => simdi = simdi.add(d);
}

Calendar cal(String uid, String ad, String guncel, {String renk = '#3b82f6', bool gorunur = true}) =>
    Calendar(uid: uid, name: ad, color: renk, visible: gorunur, updatedAt: t(guncel));

Event ev(
  String uid,
  String guncel, {
  String takvim = 'c1',
  String baslik = 'Toplantı',
  String baslangic = '2026-11-03T07:00:00Z',
  String bitis = '2026-11-03T08:00:00Z',
  String tzid = 'Europe/Istanbul',
  String? rrule,
  List<int> hatirlatici = const [],
  List<EventOverride> overrides = const [],
  List<String> exdate = const [],
  List<String> rdate = const [],
  bool tumGun = false,
}) =>
    Event(
      uid: uid,
      calendarUid: takvim,
      title: baslik,
      start: t(baslangic),
      end: t(bitis),
      tzid: tzid,
      allDay: tumGun,
      rrule: rrule,
      rdate: rdate.map(t),
      exdate: exdate.map(t),
      reminders: hatirlatici,
      overrides: overrides,
      createdAt: t('2026-10-01T00:00:00Z'),
      updatedAt: t(guncel),
    );

Task gorev(String uid, String guncel, {String baslik = 'Rapor', String? gun, String? blok, String? bitti}) => Task(
      uid: uid,
      title: baslik,
      planDay: gun,
      eventUid: blok,
      doneAt: bitti == null ? null : t(bitti),
      createdAt: t('2026-10-01T00:00:00Z'),
      updatedAt: t(guncel),
    );

Mezar mezar(String tur, String uid, String an) => Mezar(tur, uid, t(an));

/// Elle kurulmuş durum (mutasyon yöntemleri atlanır: zamanlar tam kontrol altında).
Veri veri({
  List<Calendar> takvimler = const [],
  List<Event> etkinlikler = const [],
  List<Task> gorevler = const [],
  List<Mezar> mezarlar = const [],
  DateTime Function()? saat,
}) {
  final v = Veri(saat: saat ?? Saat().call);
  for (final c in takvimler) {
    v.calendars[c.uid] = c;
  }
  for (final e in etkinlikler) {
    v.events[e.uid] = e;
  }
  for (final g in gorevler) {
    v.tasks[g.uid] = g;
  }
  for (final m in mezarlar) {
    v.mezarlar[m.anahtar] = m;
  }
  return v;
}

/// Karşılaştırma için kanonik metin.
String ozet(Veri v) => jsonEncode(v.toJson());

const cihaz = CihazBilgisi(id: 'cihaz-1', name: 'Test');

String dosya(Veri v, {Map<String, dynamic>? ek}) =>
    jsonEncode({...disaAktar(v, cihaz, simdi: t('2026-11-02T10:00:00Z')), ...?ek});
