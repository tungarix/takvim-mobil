// Masaüstü açıcısıyla birebir uyum: fixture'lar masaüstünün kendi çıktısından üretildi.
//  - uyum-yerel.json: tool/uyum_uret.py (masaüstü expand()'ı, çok sayıda kural/DST/override senaryosu)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/core/zaman.dart';

List<Map<String, Object?>> ozet(List<Occurrence> l) => [
      for (final o in l)
        {
          'start_utc': utcYaz(o.start),
          'end_utc': utcYaz(o.end),
          'title': o.title,
          'location': o.location,
          'is_override': o.isOverride,
          'original_start_utc': utcYaz(o.originalStart),
        }
    ];

void main() {
  final senaryolar = jsonDecode(File('test/fixtures/uyum-yerel.json').readAsStringSync()) as List<dynamic>;
  for (final s in senaryolar) {
    test('masaüstü uyumu: ${s['ad']}', () {
      final e = Event.fromJson(s['event']);
      final p = (s['pencere'] as List<dynamic>).cast<String>();
      final beklenen = (s['olusumlar'] as List<dynamic>)
          .map((o) => {
                'start_utc': o['start_utc'],
                'end_utc': o['end_utc'],
                'title': o['title'],
                'location': o['location'],
                'is_override': o['is_override'],
                'original_start_utc': o['original_start_utc'],
              })
          .toList();
      expect(ozet(expand(e, utcOku(p[0]), utcOku(p[1]))), beklenen);
    });
  }
}
