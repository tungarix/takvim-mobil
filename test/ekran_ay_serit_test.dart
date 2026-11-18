// Ay hücresindeki başlıklı şeritler: telefon (saatsiz), sığmayınca "+N", çok küçük hücrede noktalar,
// resmi tatil şeridi ve ayarla gizlenmesi. Ayrı dosya = ayrı flutter_tester süreci.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  Future<void> ayAc(WidgetTester tester, TakvimKontrol k) async {
    k.git(k.bugun, gorunum: Gorunum.ay);
    await uygulamaAc(tester, k);
  }

  testWidgets('telefon ayı: etkinlik başlığı şeritte görünür (saatsiz), çoğu "+N" olur, etiket başlıkları sayar', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      for (var i = 1; i <= 5; i++) {
        v.addEvent(etkinlik(s.k, 'e$i', 'Etkinlik$i'));
      }
    });
    await ayAc(tester, s.k);
    // Bugün (3 Kasım) hem hücrede hem alttaki listede: şerit + liste = 2.
    expect(find.text('Etkinlik1'), findsNWidgets(2));
    expect(find.textContaining('14:00 Etkinlik'), findsNothing); // telefonda saat yok
    expect(find.textContaining(RegExp(r'^\+\d$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'3 Kasım.*5: Etkinlik1')), findsOneWidget);
  });

  testWidgets('daralmış haftada daha çok şerit sığar; çok küçük hücrede noktalara düşer', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      for (var i = 1; i <= 3; i++) {
        v.addEvent(etkinlik(s.k, 'e$i', 'Etkinlik$i'));
      }
    });
    await ayAc(tester, s.k);
    s.k.ayDaralt(true);
    await tester.pumpAndSettle();
    expect(find.text('Etkinlik3'), findsNWidgets(2)); // hafta satırında üçü de sığar

  });

  testWidgets('geniş ekranda şeritte saat + başlık; hücre çok alçaksa noktalara düşer', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
    await ayAc(tester, s.k);
    expect(find.text('14:00 Toplantı'), findsOneWidget);

    tester.view.physicalSize = const Size(900, 400);
    await tester.pumpAndSettle();
    expect(find.text('14:00 Toplantı'), findsNothing);
  });

  testWidgets('resmi tatil şeridi görünür, ayar kapanınca kaybolur', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    s.k.git(DateTime.utc(2026, 10, 29), gorunum: Gorunum.ay);
    await uygulamaAc(tester, s.k);
    expect(find.text('Cumhuriyet Bayramı'), findsNWidgets(2)); // şerit + gün listesi
    await gercekZaman(tester, () => s.k.resmiTatilDegistir(false));
    await tester.pumpAndSettle();
    expect(find.text('Cumhuriyet Bayramı'), findsNothing);
  });
}
