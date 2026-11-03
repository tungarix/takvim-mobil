// Wi-Fi akışı sürerken dışarıdan gelen dosya/bağlantı ilerleme penceresini bozmamalı; "İptal" pencereyi kapatmalı.
// Ayrı dosya = ayrı flutter_tester süreci (bkz. ekran_senkron_test.dart).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/platform/kopru.dart';
import 'package:takvim/sync/wifi_istemci.dart';

import 'sahte.dart';
import 'yardimci.dart';

final _f = base64Url.encode(sha256(utf8.encode('sertifika'))).replaceAll('=', '');
final _baglanti = 'https://aktenak.tech/s#v=1&h=192.168.1.20:51734&t=${'ab' * 16}&f=$_f&n=Arda%20PC';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

  testWidgets('ilerleme açıkken gelen dosya/bağlantı reddedilir; İptal oturumu keser ve pencereyi kapatır', (tester) async {
    uzunEkran(tester);
    final oturum = SahteWifi(bekle: Completer<String>());
    final s = await kontrolKur(tester, wifi: (_) => oturum);
    final kopru = SahteKopru();
    await uygulamaAc(tester, s.k, kopru: kopru);
    final once = ozet(s.k.veri);

    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi ile eşleştir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _baglanti);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bağlan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bilgisayara bağlanılıyor…'), findsOneWidget);
    expect(s.k.wifiMesgul, isTrue);

    // Araya dışarıdan dosya girer: ilerleme penceresi yerinde kalır, önizleme AÇILMAZ.
    kopru.dinleyici!(GelenDosya.metin(ornekDosya()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Senkron önizleme'), findsNothing);
    expect(find.text('Bir Wi-Fi eşleştirme işlemi zaten sürüyor.'), findsOneWidget);
    expect(find.text('Bilgisayara bağlanılıyor…'), findsOneWidget);
    // ...okunamayan dosya da aynı: hata penceresi de binmez.
    kopru.dinleyici!(const GelenDosya.hata('dosya çok büyük'));
    kopru.baglantiDinleyici!(_baglanti); // ikinci bağlantı da ikinci onay ekranı açmaz
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dosya okunamadı'), findsNothing);
    expect(find.text('Bu bilgisayarla eşleşilsin mi?'), findsNothing);
    expect(find.text('Bilgisayara bağlanılıyor…'), findsOneWidget);
    expect(ozet(s.k.veri), once);

    // İptal: oturum kesilir ve pencere kapanır (en üstteki rota körlemesine pop edilmez).
    await tester.tap(find.text('İptal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bilgisayara bağlanılıyor…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(oturum.kapatildi, isTrue);
    expect(find.text('Wi-Fi eşleştirme tamamlanamadı'), findsNothing); // vazgeçmek hata değildir
    expect(s.k.wifiMesgul, isFalse);
    expect(oturum.gonderilen, isEmpty);
    expect(ozet(s.k.veri), once);
    expect(find.text('Wi-Fi ile eşleştir'), findsWidgets); // Wi-Fi sayfası hâlâ yerinde (yanlış rota kapanmadı)
  });
}
