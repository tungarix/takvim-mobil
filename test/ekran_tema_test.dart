// Görünüm (Sistem / Koyu / Açık) seçeneği. Ayrı dosya = ayrı flutter_tester süreci.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sahte.dart';

Finder _segment(String ad) => find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text(ad));

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('varsayılan Sistem; Koyu seçilince tema değişir ve ayara yazılır', (tester) async {
    final s = await kontrolKur(tester);
    expect(s.k.ayarlar.tema, 'sistem');
    expect(s.k.temaModu.value, ThemeMode.system);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();

    await tester.tap(_segment('Koyu'));
    await bekle(tester, () => s.k.ayarlar.tema == 'koyu');
    await tester.pumpAndSettle();
    expect(s.k.temaModu.value, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary, const Color(0xFFFF563C));

    await tester.tap(_segment('Açık'));
    await bekle(tester, () => s.k.ayarlar.tema == 'acik');
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary, const Color(0xFFC2331D));
  });

  testWidgets('tanınmayan kayıtlı değer Sistem sayılır', (tester) async {
    final s = await kontrolKur(tester);
    await gercekZaman(tester, () => s.k.ayarlar.temaYaz('mor'));
    expect(s.k.ayarlar.tema, 'sistem');
  });
}
