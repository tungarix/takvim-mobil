// Resmi tatiller: gömülü verinin kendi tutarlılığı, kapsam dışı yıl ve görünüm.
// Ayrı dosya = ayrı flutter_tester süreci (bkz. ekran_gorunum_test.dart başlığı).
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';
import 'package:takvim/core/resmi_tatil.dart';
import 'package:takvim/core/resmi_tatil_veri.dart';
import 'package:takvim/sync/export.dart';

import 'sahte.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  test('gömülü tablo tutarlı: tarih sıralı, aynı gün en çok iki kayıt, her yıl 8 sabit gün', () {
    final tarihler = [for (final r in resmiTatilVerisi) r.$1];
    expect(tarihler, [...tarihler]..sort());
    for (final t in tarihler.toSet()) {
      expect(tarihler.where((x) => x == t).length, lessThanOrEqualTo(2), reason: t);
    }
    for (var y = tatilIlkYil; y <= tatilSonYil; y++) {
      final sabit = resmiTatilVerisi.where((r) => r.$1.startsWith('$y-') && !r.$4 && !r.$2.contains('Arifesi') || r.$1 == '$y-10-28').length;
      expect(sabit, 8, reason: '$y');
    }
  });

  test('arife yarım gün, aynı güne düşen tam gün yarım günü ezer', () {
    expect(resmiTatilBul(DateTime.utc(2026, 3, 19))!.yarim, isTrue);
    expect(resmiTatilBul(DateTime.utc(2026, 10, 28))!.yarim, isTrue);
    expect(resmiTatilBul(DateTime.utc(2029, 4, 23))!.yarim, isFalse); // Kurban arifesi + 23 Nisan
    expect(resmiTatilBul(DateTime.utc(2033, 1, 1))!.yarim, isFalse); // Ramazan arifesi + Yılbaşı
    expect(resmiTatilBul(DateTime.utc(2026, 11, 3)), isNull);
  });

  test('kapsam dışı yılda yalnız ulusal günler gelir, dini bayram gelmez', () {
    final ilk = DateTime.utc(2040, 1, 1);
    final gunler = [for (var i = 0; i < 366; i++) ilk.add(Duration(days: i))];
    final bulunan = [for (final g in gunler) if (resmiTatilBul(g) != null) resmiTatilBul(g)!];
    expect(bulunan.length, 8);
    expect(bulunan.any((t) => t.dini), isFalse);
    expect(resmiTatilBul(DateTime.utc(2040, 10, 29))!.ad, 'Cumhuriyet Bayramı');
  });

  testWidgets('ay görünümü tatili listede etiketler, ayar kapanınca gizler; Veri ve senkrona girmez', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    s.k.git(DateTime.utc(2026, 10, 29), gorunum: Gorunum.ay);
    await uygulamaAc(tester, s.k);
    expect(find.text('Cumhuriyet Bayramı'), findsNWidgets(2));
    expect(find.text('Resmi tatil'), findsOneWidget);
    expect(s.k.veri.events, isEmpty);
    expect(disaAktarMetin(s.k.veri, const CihazBilgisi(id: 'x', name: 'y')), isNot(contains('Cumhuriyet')));

    await gercekZaman(tester, () => s.k.resmiTatilDegistir(false));
    await tester.pumpAndSettle();
    expect(find.text('Cumhuriyet Bayramı'), findsNothing);
    expect(s.k.ayarlar.resmiTatiller, isFalse);
  });

  testWidgets('hafta görünümünde tüm gün şeridinde salt okunur etiket, arife yarım gün notuyla', (tester) async {
    telefonBoyutu(tester);
    final s = await kontrolKur(tester);
    s.k.git(DateTime.utc(2026, 10, 28), gorunum: Gorunum.gun);
    await uygulamaAc(tester, s.k);
    expect(find.text('Cumhuriyet Bayramı Arifesi (yarım gün)'), findsOneWidget);
  });
}
