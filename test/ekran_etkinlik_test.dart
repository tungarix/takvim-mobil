// Etkinlik formu, tekrarlı silme/düzenleme.
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/models.dart';

import 'sahte.dart';
import 'yardimci.dart';

void main() {
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

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

}
