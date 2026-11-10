import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/sync/import.dart';

import 'yardimci.dart';

/// Tek override'lı bir dosya metni; `degistir` override'ın ham JSON haritasını değiştirir.
String _overrideli(void Function(Map<String, dynamic> o) degistir) {
  final m = jsonDecode(dosya(veri(
    takvimler: [cal('c1', 'K', '2026-11-01T08:00:00Z')],
    etkinlikler: [
      ev('e1', '2026-11-01T08:00:00Z', overrides: [EventOverride(originalStart: t('2026-11-03T07:00:00Z'), cancelled: true)]),
    ],
  ))) as Map<String, dynamic>;
  final o = ((m['events'] as List).first as Map<String, dynamic>)['overrides'] as List;
  degistir(o.first as Map<String, dynamic>);
  return jsonEncode(m);
}

void main() {
  group('override new_end, original_start\'dan önce (masaüstü reddeder)', () {
    test('iptal değil, new_start boş, new_end önce: reddedilir ve yerel durum değişmez', () {
      final yerel = veri(takvimler: [cal('c1', 'K', '2026-11-01T08:00:00Z')], etkinlikler: [ev('e1', '2026-11-01T08:00:00Z')]);
      final once = ozet(yerel);
      final metin = _overrideli((o) {
        o['cancelled'] = false;
        o['new_start_utc'] = null;
        o['new_end_utc'] = '2026-11-03T06:00:00Z';
      });
      expect(() => importEt(yerel, metin), throwsA(isA<BicimHatasi>()));
      expect(ozet(yerel), once);
    });

    test('iptal edilmiş override aynı zamanlarla kabul edilir (masaüstü kuralı yalnız iptal değilse uygular)', () {
      final metin = _overrideli((o) {
        o['cancelled'] = true;
        o['new_start_utc'] = null;
        o['new_end_utc'] = '2026-11-03T06:00:00Z';
      });
      expect(() => importEt(veri(), metin), returnsNormally);
    });

    test('new_end orijinal başlangıçtan sonra ise kabul edilir', () {
      final metin = _overrideli((o) {
        o['cancelled'] = false;
        o['new_start_utc'] = null;
        o['new_end_utc'] = '2026-11-03T09:00:00Z';
      });
      expect(() => importEt(veri(), metin), returnsNormally);
    });
  });
}
