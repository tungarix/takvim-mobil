// Gün/hafta/ay görünümleri.
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';

import 'sahte.dart';

// Görünüm seçimi AppBar'daki açılır menüde: menüyü aç, öğeyi seç.
Future<void> _gorunumSec(WidgetTester tester, String ad) async {
  await tester.tap(find.byTooltip('Görünüm'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(ad).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('ilk açılışta varsayılan Kişisel takvimi vardır ve gün görünümü açılır', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    expect(s.k.veri.calendars.values.map((c) => c.name), ['Kişisel']);
    expect(find.text('3 Kasım Salı'), findsWidgets);
    expect(find.byTooltip('Görünüm'), findsOneWidget);
  });

  testWidgets('gün, hafta ve ay görünümleri etkinliği gösterir; görünüm tercihi kalıcı', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
    await uygulamaAc(tester, s.k);
    expect(find.text('Toplantı'), findsOneWidget);

    await _gorunumSec(tester, 'Hafta');
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Salı'), findsNothing); // başlıkta kısa ad
    expect(find.text('Sal'), findsOneWidget);

    await _gorunumSec(tester, 'Ay');
    expect(find.text('Kasım 2026'), findsOneWidget);
    expect(find.textContaining('Toplantı'), findsOneWidget); // geniş ekranda saatli başlıklı şerit
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
      await _gorunumSec(tester, g);
    }
    await bekle(tester, () => s.k.ayarlar.gorunum == 'gun');
    expect(tester.takeException(), isNull);
  });

}
