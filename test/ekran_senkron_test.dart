// Senkron akışları (dosya aç, gelen dosya, gönder).
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/platform/kopru.dart';

import 'sahte.dart';
import 'yardimci.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  group('senkron', () {
    testWidgets('dosya aç: önizleme, içe aktar, sonuç; veri birleşir ve bildirimler yeniden kurulur', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      s.dosyalar.secilecek = ornekDosya();
      await uygulamaAc(tester, s.k);
      await tester.tap(find.text('Ayarlar').last);
      await tester.pumpAndSettle();
      final planOnce = s.bildirim.planlar.length;

      await tester.tap(find.text('Senkron dosyası aç'));
      await tester.pumpAndSettle();
      expect(find.text('Senkron önizleme'), findsOneWidget);
      expect(find.textContaining('mevcut veriyle birleşecek'), findsOneWidget);
      expect(s.k.veri.events, isEmpty); // önizleme hiçbir şeyi değiştirmez

      await tester.tap(find.text('İçe aktar'));
      await bekle(tester, () => s.k.ayarlar.sonSenkron != null);
      await tester.pumpAndSettle();
      expect(find.text('Senkron tamamlandı'), findsOneWidget);
      expect(find.textContaining('Eklenen:'), findsOneWidget);
      expect(s.k.veri.calendars.values.where((c) => c.name == 'Kişisel'), hasLength(1)); // ad eşleşmesi
      expect(s.bildirim.planlar.length, greaterThan(planOnce));
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Son senkron: '), findsOneWidget);
    });

    testWidgets('bozuk dosya anlaşılır hata verir, veri değişmez', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      s.dosyalar.secilecek = '{"bu": "senkron dosyası değil"}';
      await uygulamaAc(tester, s.k);
      await tester.tap(find.text('Ayarlar').last);
      await tester.pumpAndSettle();
      final once = ozet(s.k.veri);
      await tester.tap(find.text('Senkron dosyası aç'));
      await tester.pumpAndSettle();
      expect(find.text('Dosya okunamadı'), findsOneWidget);
      expect(find.textContaining('Veriniz değişmedi'), findsOneWidget);
      expect(ozet(s.k.veri), once);
    });

    testWidgets('daha yeni sürümlü dosya güncelleme uyarısı verir', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      s.dosyalar.secilecek = ornekDosya().replaceFirst('"version": 1', '"version": 9');
      await uygulamaAc(tester, s.k);
      await tester.tap(find.text('Ayarlar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senkron dosyası aç'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Uygulamayı güncelleyin'), findsOneWidget);
      expect(s.k.veri.events, isEmpty);
    });

    testWidgets('Paylaş/Birlikte aç ile gelen dosya (uygulama dosyayla açıldı) önizlemeyi gösterir', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      final kopru = SahteKopru()..bekleyen = GelenDosya.metin(ornekDosya());
      await uygulamaAc(tester, s.k, kopru: kopru);
      await tester.pumpAndSettle();
      expect(find.text('Senkron önizleme'), findsOneWidget);
      await tester.tap(find.text('İçe aktar'));
      await bekle(tester, () => s.k.ayarlar.sonSenkron != null);
      await tester.pumpAndSettle();
      expect(find.text('Senkron tamamlandı'), findsOneWidget);
      expect(s.k.veri.events, isNotEmpty);
    });

    testWidgets('uygulama açıkken gelen dosya ve okunamayan dosya', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      final kopru = SahteKopru();
      await uygulamaAc(tester, s.k, kopru: kopru);
      kopru.dinleyici!(const GelenDosya.hata('dosya çok büyük'));
      await tester.pumpAndSettle();
      expect(find.text('Dosya okunamadı'), findsOneWidget);
      expect(find.text('dosya çok büyük'), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      kopru.dinleyici!(GelenDosya.metin(ornekDosya()));
      await tester.pumpAndSettle();
      expect(find.text('Senkron önizleme'), findsOneWidget);
    });

    testWidgets('senkron dosyası gönder: tam durum .takvimsync olarak paylaşılır', (tester) async {
      uzunEkran(tester);
      final s = await kontrolKur(tester);
      await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı')));
      await uygulamaAc(tester, s.k);
      await tester.tap(find.text('Ayarlar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senkron dosyası gönder'));
      await tester.pumpAndSettle();
      final (ad, metin) = s.dosyalar.paylasilan.single;
      expect(ad, matches(RegExp(r'^takvim-\d{8}-\d{4}\.takvimsync$')));
      expect(metin, contains('"format":"takvim-sync"'));
      expect(metin, contains('Toplantı'));
    });
  });

}
