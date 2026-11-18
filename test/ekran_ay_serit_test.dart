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

  testWidgets('seçili gün hücresi komşularıyla aynı sayıda şerit gösterir (çerçeve alanı küçültmez)', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    // Bugünün komşusu 4 Kasım'a iki etkinlik; sonra 4'ü seç.
    await ekle(tester, s.k, (v) {
      for (var i = 1; i <= 2; i++) {
        v.addEvent(etkinlik(s.k, 'e$i', 'Etkinlik$i'));
      }
    });
    await ayAc(tester, s.k);
    expect(find.text('+1'), findsNothing); // bugün (seçili) iki etkinlik: ikisi de şeritte, "+1" yok
    expect(find.text('Etkinlik2'), findsNWidgets(2));
  });

  testWidgets('alçak telefonda (320x568, yazı ölçeği 2) ay ve daralmış hafta taşmaz', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      for (var i = 1; i <= 5; i++) {
        v.addEvent(etkinlik(s.k, 'e$i', 'Etkinlik$i'));
      }
    });
    await ayAc(tester, s.k);
    expect(tester.takeException(), isNull);
    s.k.ayDaralt(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    // Noktalara düşüş: 6x6 renkli daire var.
    expect(find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 6 && w.constraints?.maxHeight == 6), findsWidgets);
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
