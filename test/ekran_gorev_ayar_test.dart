// Görevler, arama, takvim yönetimi.
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sahte.dart';
import 'yardimci.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('görev eklenir ve tamamlanır', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Görevler').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rapor yaz');
    await tester.tap(find.byTooltip('Görevi ekle'));
    await bekle(tester, () => s.k.veri.tasks.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Rapor yaz'), findsOneWidget);
    expect(find.text('Plansız (1)'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await bekle(tester, () => s.k.veri.tasks.values.single.done);
    await tester.pumpAndSettle();
    expect(find.text('Tamamlananlar (1)'), findsOneWidget);
  });

  testWidgets('gün planlı görev takvimde tüm gün şeridinde, saat planlı görev blok olarak görünür', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      final g1 = v.addTask('Fatura öde');
      v.planTaskDay(g1.uid, '2026-11-03');
      final g2 = v.addTask('Rapor bitir');
      v.planTaskSlot(g2.uid, t('2026-11-03T11:00:00Z'), t('2026-11-03T12:00:00Z'), s.k.varsayilanTakvim!.uid, 'Europe/Istanbul');
    });
    await uygulamaAc(tester, s.k);
    expect(find.text('Fatura öde'), findsOneWidget);
    expect(find.text('Rapor bitir'), findsOneWidget);
  });

  testWidgets('arama etkinlik ve görevleri bulur', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      v.addEvent(etkinlik(s.k, 'e1', 'Algoritma dersi'));
      v.addTask('Algoritma ödevi');
    });
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byTooltip('Ara'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ALGORITMA');
    await tester.pumpAndSettle();
    expect(find.text('Algoritma dersi'), findsOneWidget);
    expect(find.text('Algoritma ödevi'), findsOneWidget);
  });

  testWidgets('takvim eklenir, gizlenir ve silinir (son takvim silinemez)', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Takvim ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ders');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester, () => s.k.veri.calendars.length == 2);
    await tester.pumpAndSettle();
    expect(find.text('Ders'), findsOneWidget);

    final ders = s.k.veri.calendars.values.firstWhere((c) => c.name == 'Ders');
    await tester.tap(find.byType(Switch).first); // "Ders" (alfabetik ilk)
    await bekle(tester, () => !s.k.veri.calendars[ders.uid]!.visible);
    expect(s.k.veri.calendars[ders.uid]!.visible, isFalse);

    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('geri alınamaz'), findsOneWidget);
    await tester.tap(find.text('Sil').last);
    await bekle(tester, () => s.k.veri.calendars.length == 1);
    expect(s.k.veri.calendars.values.single.name, 'Kişisel');
  });

}
