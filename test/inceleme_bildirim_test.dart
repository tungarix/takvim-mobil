// İnceleme bulgusu: süresi geçen tek hatırlatıcı ArgumentError ile planın kalanını kurmadan keser.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/bildirim_plani.dart';
import 'package:takvim/core/recurrence.dart';
import 'package:takvim/platform/bildirim.dart';

import 'yardimci.dart';

PlanliBildirim _bildirim(int id, String tetik) {
  final o = Occurrence(
    eventUid: 'e$id',
    title: 'Toplantı',
    start: t('2026-11-20T10:00:00Z'),
    end: t('2026-11-20T11:00:00Z'),
    allDay: false,
    tzid: 'UTC',
    calendarUid: 'c1',
    isOverride: false,
    recurring: false,
    originalStart: t('2026-11-20T10:00:00Z'),
  );
  return PlanliBildirim(id, o, 10, t(tetik));
}

void main() {
  group('gelecekteOlanlar', () {
    final simdi = t('2026-11-20T10:00:00Z');

    test('tetiği geçmişte kalan bildirimleri atlar, gelecekteki planı korur', () {
      final plan = [
        _bildirim(1, '2026-11-20T09:55:00Z'), // geçmiş
        _bildirim(2, '2026-11-20T10:00:00Z'), // tam şimdi: planlayıcı gibi geçmiş sayılır
        _bildirim(3, '2026-11-20T10:00:01Z'), // 1 sn sonra
        _bildirim(4, '2026-11-21T08:00:00Z'), // yarın
      ];
      final kalan = gelecekteOlanlar(plan, simdi);
      expect(kalan.map((b) => b.id).toList(), [3, 4]);
    });

    test('tetikler hepsi geçmişteyse plan boş kalır', () {
      final plan = [_bildirim(1, '2026-11-19T09:00:00Z'), _bildirim(2, '2026-11-20T09:59:59Z')];
      expect(gelecekteOlanlar(plan, simdi), isEmpty);
    });

    test('sıra korunur ve giriş listesi değişmez', () {
      final plan = [_bildirim(5, '2026-11-20T12:00:00Z'), _bildirim(6, '2026-11-20T11:00:00Z')];
      final kalan = gelecekteOlanlar(plan, simdi);
      expect(kalan.map((b) => b.id).toList(), [5, 6]);
      expect(plan, hasLength(2));
    });
  });
}
