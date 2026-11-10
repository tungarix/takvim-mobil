// İnceleme bulguları: etkinlik formu (tekrar bitişi, tek örnekte konum boşaltma).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';

import 'sahte.dart';
import 'yardimci.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('tekrar bitiş tarihi başlangıçtan önceyse kaydedilmez', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), 'Kurs');
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Her gün').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hiç bitmesin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hiç bitmesin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarihte bitsin').last);
    await tester.pumpAndSettle();
    // Varsayılan bitiş başlangıç+30 gün (Aralık); seçiciyi iki ay geriye alıp 1'ini seç (Eylül, başlangıçtan önce).
    await tester.ensureVisible(find.textContaining('Bitiş tarihi:'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bitiş tarihi:'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Tekrar bitiş tarihi, başlangıçtan önce olamaz'), findsOneWidget);
    expect(s.k.veri.events, isEmpty);
  });

  testWidgets('yalnız bu örnekte konum boşaltılınca override boş metin taşır', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      final e = etkinlik(s.k, 'e1', 'Ders', rrule: 'FREQ=DAILY');
      v.addEvent(Event(
          uid: e.uid, calendarUid: e.calendarUid, title: e.title, location: 'Ofis', start: t('2026-11-02T11:00:00Z'),
          end: t('2026-11-02T12:00:00Z'), tzid: e.tzid, rrule: e.rrule, createdAt: e.createdAt, updatedAt: e.updatedAt));
    });
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yalnızca bu etkinlik'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Konum'), '');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester, () => s.k.veri.events['e1']!.overrides.isNotEmpty);
    expect(s.k.veri.events['e1']!.overrides.single.newLocation, '');
  });
}
