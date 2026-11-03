// Wi-Fi eşleştirme akışı: hata yolları (sahte oturum, ağ yok). "Hata olunca veri değişmez, hiçbir şey gönderilmez".
// Ayrı dosya = ayrı flutter_tester süreci (bkz. ekran_senkron_test.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/sync/wifi_baglanti.dart';
import 'package:takvim/sync/wifi_istemci.dart';

import 'sahte.dart';
import 'yardimci.dart';

final _f = base64Url.encode(sha256(utf8.encode('sertifika'))).replaceAll('=', '');
final _baglanti = 'https://aktenak.tech/s#v=1&h=192.168.1.20:51734&t=${'ab' * 16}&f=$_f&n=Arda%20PC';

Future<void> _eslestirSayfasi(WidgetTester tester) async {
  await tester.tap(find.text('Ayarlar').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Wi-Fi ile eşleştir'));
  await tester.pumpAndSettle();
}

Future<void> _yapistir(WidgetTester tester, String metin) async {
  await tester.enterText(find.byType(TextField), metin);
  await tester.tap(find.text('Devam'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  // Bağlantı onaylanır, önizleme açılır (ortak başlangıç).
  Future<({Kurulum s, SahteWifi oturum, List<WifiBaglanti> uretilen})> hazirla(
    WidgetTester tester, {
    SahteWifi? oturum,
  }) async {
    uzunEkran(tester);
    final o = oturum ?? SahteWifi(durum: ornekDosya());
    final uretilen = <WifiBaglanti>[];
    final s = await kontrolKur(tester, wifi: (b) {
      uretilen.add(b);
      return o;
    });
    await uygulamaAc(tester, s.k);
    return (s: s, oturum: o, uretilen: uretilen);
  }

  testWidgets('bozuk veri bilgisayardan gelirse: anlaşılır hata, veri değişmez, gönderilmez', (tester) async {
    final h = await hazirla(tester, oturum: SahteWifi(durum: '{"bu": "senkron dosyası değil"}'));
    final once = ozet(h.s.k.veri);
    await _eslestirSayfasi(tester);
    await _yapistir(tester, _baglanti);
    await tester.tap(find.text('Bağlan'));
    await bekle(tester, () => h.oturum.cagrilar.contains('al'));
    await tester.pumpAndSettle();
    expect(find.text('Bilgisayardan gelen veri okunamadı'), findsOneWidget);
    expect(find.textContaining('Veriniz değişmedi'), findsOneWidget);
    expect(ozet(h.s.k.veri), once);
    expect(h.oturum.gonderilen, isEmpty);
  });

  for (final c in <(WifiHataTuru, String, String)>[
    (WifiHataTuru.parmakIzi, 'Güvenlik uyarısı', 'kimliği QR koddakiyle uyuşmuyor'),
    (WifiHataTuru.ulasilamadi, 'Wi-Fi eşleştirme tamamlanamadı', 'aynı Wi-Fi ağında mı'),
  ]) {
    testWidgets('bağlanma hatası ${c.$1.name}: anlaşılır ileti, veri değişmez, hiçbir şey gönderilmez', (tester) async {
      final h = await hazirla(tester, oturum: SahteWifi(durum: ornekDosya(), durumHatasi: WifiHatasi(c.$1)));
      final once = ozet(h.s.k.veri);
      await _eslestirSayfasi(tester);
      await _yapistir(tester, _baglanti);
      await tester.tap(find.text('Bağlan'));
      await bekle(tester, () => h.oturum.cagrilar.contains('al'));
      await tester.pumpAndSettle();
      expect(find.text(c.$2), findsOneWidget);
      expect(find.textContaining(c.$3), findsOneWidget);
      expect(find.text('Birleştir ve gönder'), findsNothing);
      expect(ozet(h.s.k.veri), once);
      expect(h.oturum.gonderilen, isEmpty);
      expect(h.s.k.ayarlar.sonSenkron, isNull);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(h.s.k.wifiMesgul, isFalse); // pencere kapanınca yeni eşleştirme başlatılabilir
    });
  }

  testWidgets('masaüstü reddetti: telefondaki birleştirme yapıldığı söylenir, rapor gösterilmez', (tester) async {
    final h = await hazirla(tester, oturum: SahteWifi(durum: ornekDosya(), gonderHatasi: const WifiHatasi(WifiHataTuru.reddedildi)));
    await _eslestirSayfasi(tester);
    await _yapistir(tester, _baglanti);
    await tester.tap(find.text('Bağlan'));
    await bekle(tester, () => h.oturum.cagrilar.contains('al'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Birleştir ve gönder'));
    await bekle(tester, () => h.oturum.gonderilen.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi eşleştirme tamamlanamadı'), findsOneWidget);
    expect(find.textContaining('Bilgisayar gönderilen veriyi reddetti'), findsOneWidget);
    expect(find.textContaining('Telefondaki birleştirme yapıldı'), findsOneWidget);
    expect(find.text('Wi-Fi senkronu tamamlandı'), findsNothing);
    expect(h.s.k.veri.events, isNotEmpty); // birleştirme idempotent; yeniden denenebilir
  });
}
