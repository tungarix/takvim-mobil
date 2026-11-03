// Gün/hafta/ay görünümleri.
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('ilk açılışta varsayılan Kişisel takvimi vardır ve gün görünümü açılır', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    expect(s.k.veri.calendars.values.map((c) => c.name), ['Kişisel']);
    expect(find.text('3 Kasım Salı'), findsWidgets);
    expect(find.text('Gün'), findsOneWidget);
  });

  testWidgets('gün, hafta ve ay görünümleri etkinliği gösterir; görünüm tercihi kalıcı', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
    await uygulamaAc(tester, s.k);
    expect(find.text('Toplantı'), findsOneWidget);

    await tester.tap(find.text('Hafta'));
    await tester.pumpAndSettle();
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Salı'), findsNothing); // başlıkta kısa ad
    expect(find.text('Sal'), findsOneWidget);

    await tester.tap(find.text('Ay'));
    await tester.pumpAndSettle();
    expect(find.text('Kasım 2026'), findsOneWidget);
    expect(find.text('Toplantı'), findsOneWidget); // geniş ekranda başlıklı şerit
    await bekle(tester, () => s.k.ayarlar.gorunum == 'ay');
    expect(s.k.ayarlar.gorunum, 'ay');

    // Güne dokununca gün görünümü açılır.
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    expect(s.k.gorunum, Gorunum.gun);
  });

  testWidgets('telefon boyutunda üç görünüm taşma olmadan çizilir', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
    await uygulamaAc(tester, s.k);
    for (final g in ['Hafta', 'Ay', 'Gün']) {
      await tester.tap(find.text(g));
      await tester.pumpAndSettle();
    }
    await bekle(tester, () => s.k.ayarlar.gorunum == 'gun');
    expect(tester.takeException(), isNull);
  });

}
