// Yıl görünümü: menüden açılır, 12 ay gösterir, kaydırınca yıl değişir, aya dokunmak ay görünümünü açar.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('yıl görünümü: başlıkta yıl, kaydırma yılı değiştirir, aya dokunmak ayı açar', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byTooltip('Görünüm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yıl').last);
    await tester.pumpAndSettle();
    expect(s.k.gorunum, Gorunum.yil);
    final yil = s.k.bugun.year;
    expect(find.text('$yil'), findsOneWidget);
    expect(find.text('Oca'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('${yil + 1}'), findsOneWidget);
    expect(s.k.odakGun.year, yil + 1);

    await tester.tap(find.bySemanticsLabel('Mart ${yil + 1}'));
    await tester.pumpAndSettle();
    expect(s.k.gorunum, Gorunum.ay);
    expect(s.k.odakGun.month, 3);
    expect(s.k.odakGun.year, yil + 1);
  });
}
