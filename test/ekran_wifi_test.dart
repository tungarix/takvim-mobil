// Wi-Fi eşleştirme akışı (sahte oturum, ağ yok): onaylar, vazgeçme, hata iletileri, "hata olunca veri değişmez".
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

  testWidgets('geçersiz bağlantı bağlanmaz; App Link yalnız onay ekranını açar, İptal ağa hiçbir şey göndermez', (tester) async {
    final h = await hazirla(tester);
    final once = ozet(h.s.k.veri);
    await _eslestirSayfasi(tester);
    await _yapistir(tester, 'https://aktenak.tech/s#v=1&h=8.8.8.8:5000&t=${'ab' * 16}&f=$_f');
    expect(find.text('Bağlantı geçersiz'), findsOneWidget);
    expect(find.textContaining('yerel bir ağ adresi değil'), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(h.uretilen, isEmpty);

    // App Link: uygulama açıkken bağlantı gelir -> yalnız onay ekranı.
    final kopru = SahteKopru();
    await tester.pumpWidget(const SizedBox());
    await uygulamaAc(tester, h.s.k, kopru: kopru);
    kopru.baglantiDinleyici!(_baglanti);
    await tester.pumpAndSettle();
    expect(find.text('Bu bilgisayarla eşleşilsin mi?'), findsOneWidget);
    expect(find.textContaining('«Arda PC» (192.168.1.20:51734) ile eşleşilecek'), findsOneWidget);
    expect(find.textContaining('senin açtığın eşleştirme ekranından'), findsOneWidget);
    expect(h.uretilen, isEmpty); // onaydan önce oturum bile kurulmaz
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(h.uretilen, isEmpty);
    expect(h.oturum.cagrilar, isEmpty);
    expect(ozet(h.s.k.veri), once);
    expect(h.s.k.wifiMesgul, isFalse);
  });

  testWidgets('başarılı akış: iki onay, telefona uygula, tam durumu gönder, iki rapor, bildirimler yeniden kurulur', (tester) async {
    final h = await hazirla(tester);
    final planOnce = h.s.bildirim.planlar.length;
    await _eslestirSayfasi(tester);
    await _yapistir(tester, _baglanti);
    expect(find.textContaining('«Arda PC»'), findsOneWidget);
    expect(h.oturum.cagrilar, isEmpty); // onaydan önce ağ isteği yok

    await tester.tap(find.text('Bağlan'));
    await bekle(tester, () => h.oturum.cagrilar.contains('al'));
    await tester.pumpAndSettle();
    expect(h.uretilen.single.ip, '192.168.1.20');
    expect(h.oturum.cagrilar, ['hello', 'al']);
    expect(find.text('Bilgisayardan gelen değişiklikler'), findsOneWidget);
    expect(find.textContaining('mevcut veriyle birleşecek'), findsOneWidget);
    expect(find.textContaining('Karşı cihaz: «Arda PC» (192.168.1.20:51734)'), findsOneWidget); // 2. onayda da kimlik
    expect(h.s.k.veri.events, isEmpty); // önizleme veriyi değiştirmez
    expect(h.oturum.gonderilen, isEmpty); // ikinci onaydan önce hiçbir şey gönderilmez

    await tester.tap(find.text('Birleştir ve gönder'));
    await bekle(tester, () => h.oturum.gonderilen.isNotEmpty);
    await tester.pumpAndSettle();
    expect(h.s.k.veri.events, isNotEmpty);
    final giden = jsonDecode(h.oturum.gonderilen.single) as Map<String, dynamic>;
    expect(giden['format'], 'takvim-sync'); // telefonun BİRLEŞMİŞ tam durumu
    expect((giden['events'] as List).length, h.s.k.veri.events.length);
    expect(h.oturum.gonderilen.single, contains('Haftalık toplantı'));

    expect(find.text('Wi-Fi senkronu tamamlandı'), findsOneWidget);
    expect(find.textContaining('Telefona'), findsOneWidget);
    expect(find.textContaining('Bilgisayara'), findsOneWidget);
    expect(find.textContaining('Eklenen: 2'), findsWidgets); // sahte rapor: added 2, updated 1
    expect(h.s.k.ayarlar.sonSenkron, isNotNull);
    expect(h.s.bildirim.planlar.length, greaterThan(planOnce));
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(h.oturum.kapatildi, isTrue); // iş bitince bağlantı kapanır
    expect(h.s.k.wifiMesgul, isFalse);
  });

  testWidgets('önizlemede vazgeç: veri değişmez, bilgisayara hiçbir şey gönderilmez', (tester) async {
    final h = await hazirla(tester);
    final once = ozet(h.s.k.veri);
    await _eslestirSayfasi(tester);
    await _yapistir(tester, _baglanti);
    await tester.tap(find.text('Bağlan'));
    await bekle(tester, () => h.oturum.cagrilar.contains('al'));
    await tester.pumpAndSettle();
    expect(find.text('Birleştir ve gönder'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(h.oturum.gonderilen, isEmpty);
    expect(h.oturum.cagrilar, ['hello', 'al']);
    expect(ozet(h.s.k.veri), once);
    expect(h.s.k.ayarlar.sonSenkron, isNull);
    expect(h.oturum.kapatildi, isTrue);
  });
}
