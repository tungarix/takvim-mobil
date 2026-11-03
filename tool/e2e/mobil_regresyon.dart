// Mobil tarafta e2e'de bulunan hatalar icin saf Dart regresyon denetimleri.
//
// Flutter'a bagli degil: `dart run tool/e2e/mobil_regresyon.dart` (flutter test GEREKMEZ; bu makinede
// flutter_tester motoru coktugu icin testler burada duz bir betik olarak duruyor). Hata varsa cikis kodu 1.
import 'dart:convert';
import 'dart:io';

import 'package:takvim/core/veri.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/import.dart';

int hatalar = 0, toplam = 0;

void kontrol(String ad, bool kosul, [Object? detay]) {
  toplam++;
  if (!kosul) {
    hatalar++;
    stdout.writeln('KALDI  $ad${detay == null ? '' : '  -> $detay'}');
  }
}

const bas = '2026-11-02T07:00:00Z', bit = '2026-11-02T08:00:00Z';

Map<String, dynamic> takvim(String uid, {String color = '#3b82f6'}) =>
    {'uid': uid, 'name': 'Kisisel $uid', 'color': color, 'visible': true, 'updated_at': bas};

Map<String, dynamic> etkinlik(
  String uid, {
  String tzid = 'Europe/Istanbul',
  String? rrule,
  bool allDay = false,
  List<Object?> reminders = const [],
  List<Object?> overrides = const [],
  String start = bas,
  String end = bit,
}) =>
    {
      'uid': uid, 'calendar_uid': 'c1', 'title': 'E', 'description': null, 'location': null,
      'start_utc': start, 'end_utc': end, 'tzid': tzid, 'all_day': allDay, 'rrule': rrule,
      'rdate': <Object?>[], 'exdate': <Object?>[], 'reminders': reminders, 'overrides': overrides,
      'created_at': bas, 'updated_at': bas,
    };

Map<String, dynamic> gorev(String uid, {String? eventUid}) => {
      'uid': uid, 'title': 'G', 'notes': null, 'plan_day': null, 'event_uid': eventUid, 'done_at': null,
      'created_at': bas, 'updated_at': bas,
    };

Map<String, dynamic> dosya({List<Object?>? calendars, List<Object?> events = const [], List<Object?> tasks = const []}) => {
      'format': 'takvim-sync', 'version': 1, 'created_at': bas, 'device': {'id': 'x', 'name': 'x', 'app': 'x'},
      'calendars': calendars ?? [takvim('c1')], 'events': events, 'tasks': tasks, 'deleted': <Object?>[],
    };

ImportSonucu iceAktar(Map<String, dynamic> d) => importEt(Veri(), jsonEncode(d));

bool reddedilir(Map<String, dynamic> d) {
  try {
    iceAktar(d);
    return false;
  } on BicimHatasi {
    return true;
  }
}

int say(Veri v, String uid) =>
    v.occurrences(utcOku('2026-09-01T00:00:00Z'), utcOku('2027-06-01T00:00:00Z')).where((o) => o.eventUid == uid).length;

void main() {
  // --- saat dilimi takma adlari (timezone paketi bilmiyor, masaustu zoneinfo biliyor)
  for (final ad in ['UTC', 'GMT', 'Etc/UTC', 'Europe/Amsterdam', 'Asia/Calcutta', 'US/Eastern', 'Europe/Kiev', 'Turkey']) {
    try {
      konumBul(ad);
      kontrol('tz takma adi $ad cozulur', true);
    } on FormatException catch (e) {
      kontrol('tz takma adi $ad cozulur', false, e.message);
    }
  }
  kontrol('gecersiz tz hala reddedilir', () {
    try {
      konumBul('Mars/Phobos');
      return false;
    } on FormatException {
      return true;
    }
  }());
  kontrol('UTC tzidli etkinlik iceri alinir ve tzid korunur', () {
    final s = iceAktar(dosya(events: [etkinlik('e', tzid: 'UTC')]));
    return s.veri.events['e']!.tzid == 'UTC';
  }());
  // takma ad ile asil bolge ayni duvar saatini verir (Amsterdam = Brussels kurallari)
  final ams = konumBul('Europe/Amsterdam'), bru = konumBul('Europe/Brussels');
  kontrol('Amsterdam == Brussels ofsetleri', [for (final m in [1, 4, 7, 10]) utcdenDuvar(ams, DateTime.utc(2026, m, 15, 12))]
      .toString() == [for (final m in [1, 4, 7, 10]) utcdenDuvar(bru, DateTime.utc(2026, m, 15, 12))].toString());

  // --- masaustunun reddettigi bozukluklar mobilde de reddedilir
  kontrol('gecerli taban dosya kabul', !reddedilir(dosya(events: [etkinlik('e')])));
  kontrol('ayni uid iki takvim', reddedilir(dosya(calendars: [takvim('c1'), takvim('c1')])));
  kontrol('ayni uid iki etkinlik', reddedilir(dosya(events: [etkinlik('e'), etkinlik('e')])));
  kontrol('ayni uid iki gorev', reddedilir(dosya(tasks: [gorev('g'), gorev('g')])));
  final ovTek = {'original_start_utc': bas, 'cancelled': true, 'new_start_utc': null, 'new_end_utc': null, 'new_title': null, 'new_location': null};
  kontrol('ayni ornek iki override', reddedilir(dosya(events: [etkinlik('e', rrule: 'FREQ=DAILY', overrides: [ovTek, ovTek])])));
  kontrol('takvim rengi #rrggbb degil', reddedilir(dosya(calendars: [takvim('c1', color: 'kirmizi')])));
  kontrol('takvim rengi CSS enjeksiyonu', reddedilir(dosya(calendars: [takvim('c1', color: 'red;} body{display:none')])));
  kontrol('all_day yerel gece yarisi degil', reddedilir(dosya(events: [etkinlik('e', allDay: true)])));
  kontrol('all_day yerel gece yarisi tamam', !reddedilir(dosya(events: [etkinlik('e', allDay: true, start: '2026-11-01T21:00:00Z', end: '2026-11-02T21:00:00Z')])));
  kontrol('rrule cozulemez FREQ=BOGUS', reddedilir(dosya(events: [etkinlik('e', rrule: 'FREQ=BOGUS;;;')])));
  kontrol('rrule cozulemez COUNT=x', reddedilir(dosya(events: [etkinlik('e', rrule: 'FREQ=DAILY;COUNT=x')])));
  kontrol('rrule cozulemez BYDAY=XX', reddedilir(dosya(events: [etkinlik('e', rrule: 'FREQ=WEEKLY;BYDAY=XX')])));
  kontrol('hatirlatici 10 yil + 1 dakika', reddedilir(dosya(events: [etkinlik('e', reminders: [maksHatirlatici + 1])])));
  kontrol('hatirlatici tam 10 yil kabul', !reddedilir(dosya(events: [etkinlik('e', reminders: [maksHatirlatici])])));

  // --- gecerli ama paketin acamadigi kurallar: bozuk SAYILMAZ, acilim masaustuyle ayni
  final wkst = iceAktar(dosya(events: [etkinlik('e', rrule: 'FREQ=WEEKLY;WKST=SU;BYDAY=SU,MO;COUNT=6')])).veri;
  kontrol('WKST=SU (haftalik, aralik yok) 6 ornek acar', say(wkst, 'e') == 6, say(wkst, 'e'));
  final kucuk = iceAktar(dosya(events: [etkinlik('e', rrule: 'freq=weekly;count=3')])).veri;
  kontrol('kucuk harfli kural 3 ornek acar', say(kucuk, 'e') == 3, say(kucuk, 'e'));
  final onek = iceAktar(dosya(events: [etkinlik('e', rrule: 'RRULE:FREQ=WEEKLY;COUNT=3')])).veri;
  kontrol('RRULE: onekli kural 3 ornek acar', say(onek, 'e') == 3, say(onek, 'e'));
  kontrol('WKST=SU + INTERVAL=2 bozuk sayilmaz (tek ornege duser)', !reddedilir(dosya(events: [etkinlik('e', rrule: 'FREQ=WEEKLY;INTERVAL=2;WKST=SU;COUNT=4')])));

  // --- new_start verilip new_end verilmeyen override bitisi iceri alirken doldurulur
  final ovBitissiz = {
    'original_start_utc': bas, 'cancelled': false, 'new_start_utc': '2026-11-02T09:00:00Z', 'new_end_utc': null,
    'new_title': null, 'new_location': null,
  };
  final dolu = iceAktar(dosya(events: [etkinlik('e', rrule: 'FREQ=DAILY;COUNT=3', overrides: [ovBitissiz])])).veri;
  kontrol('override bitisi etkinlik suresinden doldurulur', utcYaz(dolu.events['e']!.overrides.single.newEnd!) == '2026-11-02T10:00:00Z');

  // --- gorev blogu tekrarli/tum gun ise gorev plansiz olur (masaustu _blok_id ile ayni)
  final blokTekrarli = iceAktar(dosya(
    events: [etkinlik('blok', rrule: 'FREQ=DAILY;COUNT=3')], tasks: [gorev('g', eventUid: 'blok')])).veri;
  kontrol('tekrarli blok: gorev plansiz', blokTekrarli.tasks['g']!.eventUid == null && blokTekrarli.tasks['g']!.planDay == null);
  final blokNormal = iceAktar(dosya(events: [etkinlik('blok')], tasks: [gorev('g', eventUid: 'blok')])).veri;
  kontrol('normal blok: gorev bagli kalir', blokNormal.tasks['g']!.eventUid == 'blok');

  stdout.writeln('$toplam denetim, $hatalar hata');
  exit(hatalar == 0 ? 0 : 1);
}
