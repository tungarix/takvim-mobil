// Ana ekranlar: görünümler, etkinlik formu, görev, tekrarlı silme/geri alma, senkron akışı.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/app/kontrol.dart';
import 'package:takvim/core/models.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/platform/bildirim.dart';
import 'package:takvim/platform/kopru.dart';

import 'sahte.dart';
import 'yardimci.dart';

Event etkinlik(TakvimKontrol k, String uid, String baslik, {String? rrule, List<int> hatirlatici = const []}) => Event(
      uid: uid,
      calendarUid: k.varsayilanTakvim!.uid,
      title: baslik,
      start: t('2026-11-03T11:00:00Z'), // 14:00 yerel
      end: t('2026-11-03T12:00:00Z'),
      tzid: 'Europe/Istanbul',
      rrule: rrule,
      reminders: hatirlatici,
      createdAt: t('2026-11-03T10:00:00Z'),
      updatedAt: t('2026-11-03T10:00:00Z'),
    );

Future<void> ekle(WidgetTester tester, TakvimKontrol k, void Function(Veri) f) async {
  await tester.runAsync(() => k.yap(f));
  await tester.pump();
}

String ornekDosya() => File('test/fixtures/senkron-ornek.takvimsync').readAsStringSync();

void main() {
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

  testWidgets('etkinlik ekleme formu kaydeder', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), 'Diş randevusu');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester, () => s.k.veri.events.isNotEmpty);
    await tester.pumpAndSettle();
    final e = s.k.veri.events.values.single;
    expect(e.title, 'Diş randevusu');
    expect(e.start, t('2026-11-03T11:00:00Z')); // şimdiden sonraki tam saat (14:00 yerel)
    expect(find.text('Diş randevusu'), findsOneWidget);
    expect(s.bildirim.planlar, isNotEmpty); // kayıt sonrası bildirimler yeniden kuruldu
  });

  testWidgets('başlıksız etkinlik kaydedilmez', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Başlık gerekli'), findsOneWidget);
    expect(s.k.veri.events, isEmpty);
  });

  testWidgets('tekrarlı etkinlikte yalnız bu örnek silinir ve geri alınır', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) => v.addEvent(etkinlik(s.k, 'e1', 'Ders', rrule: 'FREQ=WEEKLY')));
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Tekrarlı etkinliği sil'), findsOneWidget);
    await tester.tap(find.text('Yalnızca bu etkinlik'));
    await bekle(tester, () => s.k.veri.events['e1']!.overrides.isNotEmpty);
    await tester.pumpAndSettle();
    expect(s.k.veri.events['e1']!.overrides.single.cancelled, isTrue);
    expect(find.text('Ders'), findsNothing);

    await tester.tap(find.text('Geri al'));
    await bekle(tester, () => s.k.veri.events['e1']!.overrides.isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Ders'), findsOneWidget);
  });

  testWidgets('bu ve sonrakiler silinince seri kısalır; tümü silinince etkinlik geri alınabilir', (tester) async {
    final s = await kontrolKur(tester);
    // Seri dünden başlıyor: bugünkü örnek ilk örnek değil.
    await ekle(tester, s.k, (v) {
      final e = etkinlik(s.k, 'e1', 'Ders', rrule: 'FREQ=DAILY');
      v.addEvent(Event(uid: e.uid, calendarUid: e.calendarUid, title: e.title, start: t('2026-11-02T11:00:00Z'), end: t('2026-11-02T12:00:00Z'), tzid: e.tzid, rrule: e.rrule, createdAt: e.createdAt, updatedAt: e.updatedAt));
    });
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu ve sonrakiler'));
    await bekle(tester, () => s.k.veri.events['e1']!.rrule!.contains('UNTIL'));
    await tester.pumpAndSettle();
    expect(s.k.veri.events['e1']!.rrule, 'FREQ=DAILY;UNTIL=20261103T105959Z');
    expect(find.text('Ders'), findsNothing);
    await tester.tap(find.text('Geri al'));
    await bekle(tester, () => s.k.veri.events['e1']!.rrule == 'FREQ=DAILY');
    await tester.pumpAndSettle();
    expect(find.text('Ders'), findsOneWidget);
  });

  group('tekrarlı düzenleme', () {
    Future<void> duzenleBaslat(WidgetTester tester, String kapsamMetni) async {
      await tester.tap(find.text('Ders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kapsamMetni));
      await tester.pumpAndSettle();
    }

    Future<void> kaydet(WidgetTester tester, String yeniBaslik) async {
      await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), yeniBaslik);
      await tester.tap(find.text('Kaydet'));
    }

    // Seri dünden başlar: bugünkü örnek ilk örnek değildir, üç kapsam da kullanılabilir.
    Future<Kurulum> seriKur(WidgetTester tester) async {
      final s = await kontrolKur(tester);
      await ekle(tester, s.k, (v) {
        final e = etkinlik(s.k, 'e1', 'Ders', rrule: 'FREQ=DAILY');
        v.addEvent(Event(
            uid: e.uid, calendarUid: e.calendarUid, title: e.title, start: t('2026-11-02T11:00:00Z'),
            end: t('2026-11-02T12:00:00Z'), tzid: e.tzid, rrule: e.rrule, createdAt: e.createdAt, updatedAt: e.updatedAt));
      });
      await uygulamaAc(tester, s.k);
      return s;
    }

    testWidgets('yalnız bu örnek: override yazılır, seri değişmez', (tester) async {
      final s = await seriKur(tester);
      await duzenleBaslat(tester, 'Yalnızca bu etkinlik');
      await kaydet(tester, 'Ders (ek)');
      await bekle(tester, () => s.k.veri.events['e1']!.overrides.isNotEmpty);
      final e = s.k.veri.events['e1']!;
      expect(e.title, 'Ders');
      expect(e.overrides.single.originalStart, t('2026-11-03T11:00:00Z'));
      expect(e.overrides.single.newTitle, 'Ders (ek)');
    });

    testWidgets('bu ve sonrakiler: seri bölünür, yeni parça yeni başlığı taşır', (tester) async {
      final s = await seriKur(tester);
      await duzenleBaslat(tester, 'Bu ve sonrakiler');
      await kaydet(tester, 'Yeni ders');
      await bekle(tester, () => s.k.veri.events.length == 2);
      final eski = s.k.veri.events['e1']!;
      final yeni = s.k.veri.events.values.firstWhere((e) => e.uid != 'e1');
      expect(eski.title, 'Ders');
      expect(eski.rrule, 'FREQ=DAILY;UNTIL=20261103T105959Z');
      expect(yeni.title, 'Yeni ders');
      expect(yeni.rrule, 'FREQ=DAILY');
      expect(yeni.start, t('2026-11-03T11:00:00Z'));
    });

    testWidgets('tüm seri: başlık değişir, kural ve başlangıç aynı kalır', (tester) async {
      final s = await seriKur(tester);
      await duzenleBaslat(tester, 'Tüm seri');
      await kaydet(tester, 'Yeni ad');
      await bekle(tester, () => s.k.veri.events['e1']!.title == 'Yeni ad');
      final e = s.k.veri.events['e1']!;
      expect(e.rrule, 'FREQ=DAILY');
      expect(e.start, t('2026-11-02T11:00:00Z'));
      expect(s.k.veri.events.length, 1);
    });
  });

  testWidgets('görev eklenir ve tamamlanır', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Görevler').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rapor yaz');
    await tester.tap(find.byTooltip('Görevi ekle'));
    await bekle(tester, () => s.k.veri.tasks.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Rapor yaz'), findsOneWidget);
    expect(find.text('Plansız (1)'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await bekle(tester, () => s.k.veri.tasks.values.single.done);
    await tester.pumpAndSettle();
    expect(find.text('Tamamlananlar (1)'), findsOneWidget);
  });

  testWidgets('gün planlı görev takvimde tüm gün şeridinde, saat planlı görev blok olarak görünür', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      final g1 = v.addTask('Fatura öde');
      v.planTaskDay(g1.uid, '2026-11-03');
      final g2 = v.addTask('Rapor bitir');
      v.planTaskSlot(g2.uid, t('2026-11-03T11:00:00Z'), t('2026-11-03T12:00:00Z'), s.k.varsayilanTakvim!.uid, 'Europe/Istanbul');
    });
    await uygulamaAc(tester, s.k);
    expect(find.text('Fatura öde'), findsOneWidget);
    expect(find.text('Rapor bitir'), findsOneWidget);
  });

  testWidgets('arama etkinlik ve görevleri bulur', (tester) async {
    final s = await kontrolKur(tester);
    await ekle(tester, s.k, (v) {
      v.addEvent(etkinlik(s.k, 'e1', 'Algoritma dersi'));
      v.addTask('Algoritma ödevi');
    });
    await uygulamaAc(tester, s.k);
    await tester.tap(find.byTooltip('Ara'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ALGORITMA');
    await tester.pumpAndSettle();
    expect(find.text('Algoritma dersi'), findsOneWidget);
    expect(find.text('Algoritma ödevi'), findsOneWidget);
  });

  testWidgets('takvim eklenir, gizlenir ve silinir (son takvim silinemez)', (tester) async {
    final s = await kontrolKur(tester);
    await uygulamaAc(tester, s.k);
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Takvim ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ders');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester, () => s.k.veri.calendars.length == 2);
    await tester.pumpAndSettle();
    expect(find.text('Ders'), findsOneWidget);

    final ders = s.k.veri.calendars.values.firstWhere((c) => c.name == 'Ders');
    await tester.tap(find.byType(Switch).first); // "Ders" (alfabetik ilk)
    await bekle(tester, () => !s.k.veri.calendars[ders.uid]!.visible);
    expect(s.k.veri.calendars[ders.uid]!.visible, isFalse);

    await tester.tap(find.text('Ders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('geri alınamaz'), findsOneWidget);
    await tester.tap(find.text('Sil').last);
    await bekle(tester, () => s.k.veri.calendars.length == 1);
    expect(s.k.veri.calendars.values.single.name, 'Kişisel');
  });

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

  group('kontrol', () {
    test('hatalı değişiklik veriyi değiştirmez ve false döner', () async {
      final s = await kontrolKurDuz();
      final once = ozet(s.k.veri);
      final ok = await s.k.yap((v) => v.updateEvent(etkinlik(s.k, 'yok', 'x')));
      expect(ok, isFalse);
      expect(ozet(s.k.veri), once);
    });

    test('her başarılı değişiklikten sonra bildirimler yeniden planlanır', () async {
      final s = await kontrolKurDuz();
      final once = s.bildirim.planlar.length;
      await s.k.yap((v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı', hatirlatici: [10, 30])));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.bildirim.planlar.length, greaterThan(once));
      expect(s.bildirim.planlar.last.map((p) => p.dakikaOnce), [30, 10]); // şimdi 13:00, etkinlik 14:00: 13:30 ve 13:50
    });

    test('hatırlatıcılı etkinlik varken bildirim izni kapalıysa izin istenir', () async {
      final s = await kontrolKurDuz();
      s.bildirim.durum.value = const BildirimDurumu(bildirimIzni: false, tamZamanli: false);
      await s.k.yap((v) => v.addEvent(etkinlik(s.k, 'e1', 'Toplantı', hatirlatici: [10])));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.bildirim.izinIstendi, isTrue);
    });
  });
}
