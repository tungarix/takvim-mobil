// Güncelleme ekranları: ilk açılış sorusu (zorunlu seçim, seçmeden ağ yok), Ayarlar bölümü, kurulum akışı.
// Ayrı dosya = ayrı flutter_tester süreci (bkz. ekran_gorev_ayar_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/guncelleme/ag.dart';

import 'sahte.dart';

SahteAg teklifli() => SahteAg(teklif: SahteAg.yayin('0.4.0', 2048));

Future<void> ayarlaraGit(WidgetTester t) async {
  await t.tap(find.text('Ayarlar').last);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.text('Güncellemeler'), 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

/// Gerçek G/Ç ile biten bir işlemin ekrandaki sonucunu bekler.
Future<void> metniBekle(WidgetTester t, Finder f) => bekle(t, () => f.evaluate().isNotEmpty);

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  group('ilk açılış sorusu', () {
    testWidgets('çıkar; yanıt verilmeden ağ isteği yok; geri tuşu kapatmaz', (tester) async {
      final ag = teklifli();
      final s = await kontrolKur(tester, ag: ag, kopru: SahteKopru());
      await uygulamaAc(tester, s.k, kopru: SahteKopru());
      expect(find.text('Evet, denetle'), findsOneWidget);
      expect(find.text('Hayır'), findsOneWidget);
      expect(s.guncelleyici!.denetim, isNull);
      await tester.binding.handlePopRoute(); // Android geri tuşu
      await tester.pumpAndSettle();
      expect(find.text('Evet, denetle'), findsOneWidget); // seçim zorunlu
      expect(ag.denetimler, 0);
    });

    testWidgets('Evet: seçim kaydedilir, ilk denetim yapılır, teklif bildirilir', (tester) async {
      final ag = teklifli();
      final s = await kontrolKur(tester, ag: ag, kopru: SahteKopru());
      await uygulamaAc(tester, s.k, kopru: SahteKopru());
      await tester.tap(find.text('Evet, denetle'));
      await bekle(tester, () => s.guncelleyici!.teklif != null);
      await tester.pumpAndSettle();
      expect(s.guncelleyici!.denetim, isTrue);
      expect(s.guncelleyici!.teklif!.surum, '0.4.0');
      expect(find.textContaining('Takvim 0.4.0 hazır'), findsOneWidget);
    });

    testWidgets('Hayır: seçim kaydedilir, ağ isteği yok, bir daha sorulmaz', (tester) async {
      final ag = teklifli();
      final s = await kontrolKur(tester, ag: ag, kopru: SahteKopru());
      await uygulamaAc(tester, s.k, kopru: SahteKopru());
      await tester.tap(find.text('Hayır'));
      await bekle(tester, () => s.guncelleyici!.denetim == false);
      await tester.pumpAndSettle();
      expect(s.guncelleyici!.denetim, isFalse);
      expect(ag.denetimler, 0);
      expect(find.text('Evet, denetle'), findsNothing);
    });

    testWidgets('seçim varsa soru çıkmaz', (tester) async {
      final ag = SahteAg();
      final s = await kontrolKur(tester, ag: ag, kopru: SahteKopru());
      await tester.runAsync(() => s.guncelleyici!.denetimYaz(false));
      await uygulamaAc(tester, s.k, kopru: SahteKopru());
      expect(find.text('Evet, denetle'), findsNothing);
      expect(ag.denetimler, 0);
    });
  });

  group('ayarlar ve kurulum', () {
    Future<(Kurulum, SahteKopru, SahteAg)> hazir(WidgetTester tester, {SahteAg? ag, String net = 'wifi', bool izin = true}) async {
      final a = ag ?? teklifli();
      final kopru = SahteKopru()
        ..ag = net
        ..izin = izin;
      final s = await kontrolKur(tester, ag: a, kopru: kopru);
      await tester.runAsync(() => s.guncelleyici!.denetimYaz(false)); // soru çıkmasın
      await tester.runAsync(() => s.guncelleyici!.denetle()); // teklif saklı
      await uygulamaAc(tester, s.k, kopru: kopru);
      await ayarlaraGit(tester);
      return (s, kopru, a);
    }

    testWidgets('bölüm durumu ve düğmeleri gösterir; anahtar seçimi kaydeder', (tester) async {
      final (s, _, _) = await hazir(tester);
      expect(find.text('Takvim 0.4.0 hazır.'), findsOneWidget);
      expect(find.text('Şimdi denetle'), findsOneWidget);
      expect(find.text('0.4.0 sürümünü kur'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile).last);
      await bekle(tester, () => s.guncelleyici!.denetim == true);
      expect(s.guncelleyici!.denetim, isTrue);
    });

    testWidgets('Şimdi denetle: otomatik kapalıyken de çalışır (kullanıcının isteği)', (tester) async {
      final ag = SahteAg();
      final (s, _, _) = await hazir(tester, ag: ag);
      final once = ag.denetimler;
      await tester.tap(find.text('Şimdi denetle'));
      await metniBekle(tester, find.text('Takvim güncel.'));
      await tester.pumpAndSettle();
      expect(ag.denetimler, once + 1);
      expect(s.guncelleyici!.denetim, isFalse); // seçimi değiştirmez
      expect(find.text('Takvim güncel.'), findsOneWidget);
    });

    testWidgets('denetim hatası mesaj olarak görünür', (tester) async {
      final ag = SahteAg(hata: const GuncellemeHatasi('limit'));
      await hazir(tester, ag: ag);
      await tester.tap(find.text('Şimdi denetle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('çok fazla istek'), findsWidgets);
    });

    testWidgets('kurulum: onay -> indir -> doğrula -> sistem kurulum penceresi (APK yolu verilir)', (tester) async {
      final (s, kopru, ag) = await hazir(tester);
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      expect(find.text('Güncelle'), findsOneWidget); // onay penceresi
      expect(ag.indirmeler, 0); // onaydan önce indirme yok
      await tester.tap(find.text('İndir ve kur'));
      await bekle(tester, () => kopru.kurulanlar.isNotEmpty);
      await tester.pumpAndSettle();
      expect(ag.indirmeler, 1);
      expect(kopru.kurulanlar.single, endsWith('Takvim-0.4.0.apk'));
      expect(kopru.kurulanlar.single, startsWith(s.guncelleyici!.klasor.path));
    });

    testWidgets('onay verilmezse hiçbir şey indirilmez', (tester) async {
      final (_, kopru, ag) = await hazir(tester);
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(ag.indirmeler, 0);
      expect(kopru.kurulanlar, isEmpty);
    });

    testWidgets('mobil veride ayrı onay ister; reddedilirse indirmez', (tester) async {
      final (_, kopru, ag) = await hazir(tester, net: 'mobil');
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await tester.pumpAndSettle();
      expect(find.text('Mobil veri kullanılacak'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(ag.indirmeler, 0);
      expect(kopru.kurulanlar, isEmpty);
    });

    testWidgets('mobil veride onaylanırsa indirir ve kurar', (tester) async {
      final (_, kopru, ag) = await hazir(tester, net: 'mobil');
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobil veriyle indir'));
      await bekle(tester, () => kopru.kurulanlar.isNotEmpty);
      expect(ag.indirmeler, 1);
    });

    testWidgets('bağlantı yoksa indirmez', (tester) async {
      final (_, kopru, ag) = await hazir(tester, net: 'yok');
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await tester.pumpAndSettle();
      expect(find.text('İnternet bağlantısı yok.'), findsOneWidget);
      expect(ag.indirmeler, 0);
      expect(kopru.kurulanlar, isEmpty);
    });

    testWidgets('kurulum izni yoksa izin ekranına yönlendirir, indirmez', (tester) async {
      final (_, kopru, ag) = await hazir(tester, izin: false);
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await tester.pumpAndSettle();
      expect(find.text('Kurulum izni gerekli'), findsOneWidget);
      await tester.tap(find.text("Ayarlar'ı aç"));
      await tester.pumpAndSettle();
      expect(kopru.izinAcildi, 1);
      expect(ag.indirmeler, 0);
      expect(kopru.kurulanlar, isEmpty);
    });

    testWidgets('sistem kurulumu başarısız olursa kullanıcıya söylenir; başarı/onay bekleme sessiz', (tester) async {
      final (_, kopru, _) = await hazir(tester);
      kopru.kurulumSonucuF!(0, null);
      kopru.kurulumSonucuF!(-1, null);
      await tester.pump();
      expect(find.textContaining('Kurulum başlatılamadı'), findsNothing);
      kopru.kurulumSonucuF!(7, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('farklı bir anahtarla imzalı'), findsOneWidget);
    });

    testWidgets('çok hızlı hata: ilerleme penceresi açık kalmaz', (tester) async {
      final (_, kopru, ag) = await hazir(tester, ag: SahteAg(teklif: SahteAg.yayin('0.4.0', 2048))..metinHatasi = const GuncellemeHatasi('ag_hatasi'));
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await metniBekle(tester, find.textContaining('ulaşılamadı'));
      await tester.pumpAndSettle();
      expect(find.text('Güncelleme indiriliyor ve doğrulanıyor…'), findsNothing); // pencere kapandı
      expect(find.textContaining('ulaşılamadı'), findsWidgets);
      expect(ag.indirmeler, 0);
      expect(kopru.kurulanlar, isEmpty);
    });

    testWidgets('özet tutmazsa kurulum penceresi HİÇ açılmaz', (tester) async {
      final (_, kopru, ag) = await hazir(tester, ag: SahteAg(teklif: SahteAg.yayin('0.4.0', 2048), ozetYanlis: true));
      await tester.tap(find.text('0.4.0 sürümünü kur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir ve kur'));
      await metniBekle(tester, find.textContaining('özeti doğrulanamadı'));
      await tester.pumpAndSettle();
      expect(ag.indirmeler, 1);
      expect(kopru.kurulanlar, isEmpty);
      expect(find.textContaining('özeti doğrulanamadı'), findsWidgets);
    });
  });
}
