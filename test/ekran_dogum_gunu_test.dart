// Etkinlik formunda doğum günü türü ve gün kartındaki gösterimi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/yerel_zaman.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  Future<void> ayGorunumu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Görünüm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ay').last);
    await tester.pumpAndSettle();
  }

  testWidgets('tür seçici: doğum günü formu sadeleşir, geri dönülür; düzenlemede seçici yok', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Ders')));
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Başlangıç'), findsOneWidget);
    await tester.tap(find.text('Doğum günü'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Kişi adı'), findsOneWidget);
    expect(find.text('Başlangıç'), findsNothing);
    expect(find.text('Tekrar'), findsNothing);
    expect(find.text('Doğum yılı biliniyor'), findsOneWidget);
    expect(find.text('Önceki gün 09:00'), findsOneWidget); // varsayılan hatırlatıcı
    await tester.tap(find.text('Etkinlik'));
    await tester.pumpAndSettle();
    expect(find.text('Başlangıç'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Başlık'), findsOneWidget);
    await tester.tap(find.byTooltip('İptal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('doğum günü kaydı: tüm gün, yıllık, "<Ad> doğum günü", hatırlatıcı; ay kartında pasta', (tester) async {
    telefonBoyutu(tester); // gün kartı yalnız telefon düzeninde
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doğum günü'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Ad gerekli'), findsOneWidget);
    expect(s.k.veri.events, isEmpty);
    await tester.enterText(find.widgetWithText(TextFormField, 'Kişi adı'), 'Ayşe');
    await tester.tap(find.byTooltip('Kaydet'));
    await bekle(tester, () => s.k.veri.events.isNotEmpty);
    await tester.pumpAndSettle();
    final e = s.k.veri.events.values.single;
    expect(e.title, 'Ayşe doğum günü');
    expect(e.allDay, isTrue);
    expect(e.rrule, 'FREQ=YEARLY');
    expect(e.reminders, [900]);
    expect(e.start, YerelZaman('Europe/Istanbul').utc(DateTime.utc(2026, 11, 3))); // yıl yok: bugünün tarihi
    await ayGorunumu(tester);
    expect(find.text('Ayşe doğum günü'), findsOneWidget);
    expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    expect(find.textContaining('yaşına'), findsNothing); // yıl bilinmiyor
  });

  testWidgets('yıl biliniyorsa "N yaşına giriyor"; kalıba uymayan tüm gün etkinlikte pasta yok', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    final z = YerelZaman('Europe/Istanbul');
    await ekle(tester, s.k, (v) {
      final d = etkinlik(s.k, 'd', 'Ali doğum günü', rrule: 'FREQ=YEARLY');
      v.addEvent(d.copyWith(start: z.utc(DateTime.utc(1990, 11, 3)), end: z.utc(DateTime.utc(1990, 11, 4)), allDay: true));
      final b = etkinlik(s.k, 'b', 'Bayram');
      v.addEvent(b.copyWith(start: z.utc(DateTime.utc(2026, 11, 3)), end: z.utc(DateTime.utc(2026, 11, 4)), allDay: true));
    });
    await uygulamaAc(tester, s.k);
    await ayGorunumu(tester);
    expect(find.text('36 yaşına giriyor'), findsOneWidget);
    expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    expect(find.text('Tüm gün'), findsOneWidget); // Bayram
    await tester.tap(find.text('Ali doğum günü'));
    await tester.pumpAndSettle();
    expect(find.text('36 yaşına giriyor'), findsNWidgets(2)); // kart + ayrıntı
  });
}
