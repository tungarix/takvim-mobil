// Telefon boyutunda ay görünümü: seçim, günün listesi, haftaya daralma, ikinci dokunuşta gün görünümü.
// Ayrı dosya = ayrı flutter_tester süreci (bkz. ekran_gorunum_test.dart başlığı).
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  Future<void> gorunumSec(WidgetTester tester, String ad) async {
    await tester.tap(find.byTooltip('Görünüm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ad).last);
    await tester.pumpAndSettle();
  }

  testWidgets('telefon ay görünümü: dokunmak seçer, liste güne döner, ikinci dokunuş gün görünümünü açar', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
    await uygulamaAc(tester, s.k);
    await gorunumSec(tester, 'Ay');
    // Bugün (3 Kasım) seçili açılır: liste etkinliği ve saatini gösterir.
    expect(find.text('Toplantı'), findsNWidgets(2));
    expect(find.text('14:00 – 15:00'), findsOneWidget);

    // Etkinliksiz bir gün seçilince liste boşalır, görünüm değişmez.
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Etkinlik yok'), findsOneWidget);
    expect(s.k.gorunum, Gorunum.ay);
    expect(s.k.odakGun.day, 10);

    // Seçili gün bugün değilken başlıkta göreli metin ve bugüne dön düğmesi görünür.
    expect(find.text('7 gün içinde'), findsOneWidget);
    expect(find.byTooltip('Bugün'), findsNWidgets(2)); // AppBar'daki + yüzen düğme

    // Tutamaç ayı haftaya daraltır; liste yine çalışır.
    await tester.tap(find.bySemanticsLabel('Ayı haftaya daralt'));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsNothing); // seçili haftanın (9-15) dışı
    expect(find.text('11'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Ayı aç'));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);

    // Etkinlikli güne dokununca seçilir, listedeki etkinliğe dokunmak ayrıntıyı açar.
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    expect(find.text('Toplantı'), findsNWidgets(2));
    await tester.tap(find.text('Toplantı').last);
    await tester.pumpAndSettle();
    expect(find.text('Toplantı'), findsWidgets);
    await tester.tapAt(const Offset(5, 5)); // ayrıntı sayfasını kapat
    await tester.pumpAndSettle();

    // Seçili güne ikinci dokunuş gün görünümünü açar.
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    expect(s.k.gorunum, Gorunum.gun);
  });

  testWidgets('haftaya daralmış telefon ayında yatay kaydırma haftayı değiştirir, açıkken ayı', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await gorunumSec(tester, 'Ay');
    await tester.tap(find.text('10'));
    await tester.tap(find.bySemanticsLabel('Ayı haftaya daralt'));
    await tester.pumpAndSettle();

    await tester.fling(find.text('11'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(s.k.odakGun, DateTime.utc(2026, 11, 17)); // aynı hafta günü, bir sonraki hafta
    expect(s.k.ayDaraldi, isTrue);
    await tester.fling(find.text('18'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(s.k.odakGun, DateTime.utc(2026, 11, 10));

    // Hafta ay sınırını geçince başlık ve ay sayfası da ilerler, daralma korunur.
    s.k.odakAyarla(DateTime.utc(2026, 11, 24)); // sayfada görünmeyen güne elle taşı
    await tester.pumpAndSettle();
    await tester.fling(find.text('25'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(s.k.odakGun, DateTime.utc(2026, 12, 1));
    expect(find.text('Aralık 2026'), findsOneWidget);
    expect(s.k.ayDaraldi, isTrue);

    // Açık halde kaydırma ayı değiştirir.
    s.k.ayDaralt(false);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Etkinlik yok'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(s.k.odakGun.month, 1);
    expect(s.k.odakGun.year, 2027);
  });
}
