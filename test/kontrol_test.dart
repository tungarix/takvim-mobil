// Kontrol: yazma hatası, bildirim yeniden planlama (düz test, widget yok).
// Ayrı dosya = ayrı flutter_tester süreci: tek süreçte çok sayıda kare çizmek bu makinedeki
// (Windows) motor çökmesine (0xC0000005) daha sık denk geliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/platform/bildirim.dart';

import 'sahte.dart';
import 'yardimci.dart';

void main() {
  // TakvimKontrol.mesaj GlobalKey kullanır: düz test() içinde de widget bağlayıcısı hazır olmalı.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(eskiDizinleriTemizle);
  tearDownAll(dizinleriTemizle);

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
