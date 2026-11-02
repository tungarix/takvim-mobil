// Masaüstünün ürettiği örnek senkron dosyası ve onun Repo.occurrences çıktısıyla uyum.
// Fixture'lar masaüstü deposundan kopyalandı (docs/senkron-ornek.takvimsync ve
// docs/senkron-ornek-olusumlar.json -> test/fixtures/). Pencere UTC ve bitiş HARİÇ.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/import.dart';

void main() {
  final sync = File('test/fixtures/senkron-ornek.takvimsync');
  final olusum = File('test/fixtures/senkron-ornek-olusumlar.json');
  final yok = !sync.existsSync() || !olusum.existsSync();

  group('masaüstü örnek dosyası', () {
    late ImportSonucu s;
    late Map<String, dynamic> beklenen;
    setUp(() {
      s = importEt(Veri(), sync.readAsStringSync());
      beklenen = jsonDecode(olusum.readAsStringSync()) as Map<String, dynamic>;
    });

    test('temiz cihaza hatasız içe aktarılır, yetim yok, mezar taşları taşınır, görev-blok bağı korunur', () {
      expect(s.rapor.skipped, 0);
      expect([s.rapor.calendar.added, s.rapor.event.added, s.rapor.task.added], [2, 8, 4]);
      expect(s.veri.mezarlar.keys.length, 2);
      expect(s.veri.tasks.values.where((t) => t.eventUid != null).length, 1);
      // aynı dosya ikinci kez: değişiklik yok
      expect(importEt(s.veri, sync.readAsStringSync()).rapor.degisti, isFalse);
    });

    test('açılım masaüstü Repo.occurrences ile birebir aynı', () {
      final w = beklenen['window'] as Map<String, dynamic>;
      final ws = utcOku(w['start_utc'] as String), we = utcOku(w['end_utc'] as String);
      Map<String, Object?> ozet(String uid, String cal, String title, String bas, String bit, bool tum, String? yer,
              bool ov, String orijinal) =>
          {
            'event_uid': uid, 'calendar_uid': cal, 'title': title, 'start_utc': bas, 'end_utc': bit,
            'all_day': tum, 'location': yer, 'is_override': ov, 'original_start_utc': orijinal,
          };
      final gercek = [
        for (final o in s.veri.occurrences(ws, we))
          ozet(o.eventUid, o.calendarUid, o.title, utcYaz(o.start), utcYaz(o.end), o.allDay, o.location, o.isOverride,
              utcYaz(o.originalStart))
      ];
      final bek = [
        for (final o in (beklenen['occurrences'] as List<dynamic>).cast<Map<String, dynamic>>())
          ozet(o['event_uid'], o['calendar_uid'], o['title'], o['start_utc'], o['end_utc'], o['all_day'], o['location'],
              o['is_override'], o['original_start_utc'])
      ];
      expect(bek, isNotEmpty);
      expect(gercek.length, bek.length);
      for (var i = 0; i < bek.length; i++) {
        expect(gercek[i], bek[i], reason: 'sıra $i');
      }
    });

    test('penceredeki iptal override\'ları masaüstüyle aynı', () {
      final w = beklenen['window'] as Map<String, dynamic>;
      final ws = utcOku(w['start_utc'] as String), we = utcOku(w['end_utc'] as String);
      final gercek = <String>[];
      for (final e in s.veri.events.values) {
        // exdate ile dışlananlar ve pencere dışı olanlar sayılmaz: seri örneği olmalı.
        final ornekler = kuralBaslangiclari(e, ws, we.subtract(const Duration(seconds: 1))).toSet();
        for (final ov in e.overrides.where((o) => o.cancelled && ornekler.contains(o.originalStart))) {
          gercek.add('${e.uid}|${utcYaz(ov.originalStart)}');
        }
      }
      final bek = [
        for (final c in (beklenen['cancelled'] as List<dynamic>).cast<Map<String, dynamic>>())
          '${c['event_uid']}|${c['original_start_utc']}'
      ];
      expect(bek, isNotEmpty);
      expect(gercek..sort(), bek..sort());
    });
  }, skip: yok ? 'masaüstü fixture\'ları yok (test/fixtures/senkron-ornek*)' : false);
}
