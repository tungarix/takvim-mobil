// Yerel bildirimler (flutter_local_notifications). Ne zaman çalacağına
// core/bildirim_plani.dart karar verir; burası yalnızca Android'e kurar.
//
// İzin yoksa uygulama çökmez: bildirim izni yoksa durum "kapalı" gösterilir,
// tam zamanlı alarm izni yoksa yaklaşık zamanlı (inexact) bildirime düşülür.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/bildirim_plani.dart';
import '../core/yerel_zaman.dart';
import '../ui/bicim.dart';
import '../ui/metin.dart';

class BildirimDurumu {
  const BildirimDurumu({this.bildirimIzni, this.tamZamanli, this.planli = 0, this.hata});
  final bool? bildirimIzni; // null: henüz bilinmiyor
  final bool? tamZamanli;
  final int planli;
  final String? hata;

  BildirimDurumu kopya({bool? bildirimIzni, bool? tamZamanli, int? planli, String? hata, bool hataTemizle = false}) =>
      BildirimDurumu(
        bildirimIzni: bildirimIzni ?? this.bildirimIzni,
        tamZamanli: tamZamanli ?? this.tamZamanli,
        planli: planli ?? this.planli,
        hata: hataTemizle ? null : (hata ?? this.hata),
      );
}

abstract class BildirimServisi {
  final ValueNotifier<BildirimDurumu> durum = ValueNotifier(const BildirimDurumu());

  Future<void> baslat();

  /// Bildirim iznini ve tam zamanlı alarm iznini ister (kullanıcı eylemiyle çağrılır).
  Future<void> izinIste();

  /// Önceki planı iptal edip `plan`ı kurar.
  Future<void> yenile(List<PlanliBildirim> plan, YerelZaman zaman);
}

/// Tetiği `simdi`den geçmiş olanları eler. Plan izin penceresinde bayatlayabilir; geçmişteki
/// tetik zonedSchedule'da ArgumentError verir ve kalan bildirimleri kurmadan keser.
List<PlanliBildirim> gelecekteOlanlar(List<PlanliBildirim> plan, DateTime simdi) =>
    [for (final b in plan) if (b.tetik.isAfter(simdi)) b];

class YerelBildirimler extends BildirimServisi {
  final _p = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> baslat() async {
    await _p.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _durumOku();
  }

  Future<void> _durumOku() async {
    final a = _android;
    durum.value = durum.value.kopya(
      bildirimIzni: await a?.areNotificationsEnabled(),
      tamZamanli: await a?.canScheduleExactNotifications(),
    );
  }

  @override
  Future<void> izinIste() async {
    final a = _android;
    await a?.requestNotificationsPermission();
    // Android 13+ta USE_EXACT_ALARM kendiliğinden verilir; 12'de ayar ekranı açılır.
    if (!(await a?.canScheduleExactNotifications() ?? true)) await a?.requestExactAlarmsPermission();
    await _durumOku();
  }

  @override
  Future<void> yenile(List<PlanliBildirim> plan, YerelZaman zaman) async {
    await _durumOku();
    await _p.cancelAllPendingNotifications();
    final tam = durum.value.tamZamanli ?? false;
    const detay = NotificationDetails(
      android: AndroidNotificationDetails(
        'hatirlatici',
        M.bildirimKanal,
        channelDescription: M.bildirimKanalAciklama,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    var kurulan = 0;
    String? hata;
    for (final b in gelecekteOlanlar(plan, DateTime.now())) {
      final o = b.ornek;
      final govde = o.allDay ? M.bildirimGovdeTumGun : M.bildirimGovde(b.dakikaOnce, saatMetni(zaman.duvar(o.start)));
      Future<void> kur(AndroidScheduleMode mod) => _p.zonedSchedule(
            id: b.id,
            scheduledDate: tz.TZDateTime.from(b.tetik, tz.UTC),
            notificationDetails: detay,
            androidScheduleMode: mod,
            title: o.title,
            body: govde,
          );
      try {
        try {
          await kur(tam ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
        } on PlatformException catch (e) {
          // Tam zamanlı alarm izni arada geri alınmış olabilir: yaklaşık zamana düş.
          if (e.code != 'exact_alarms_not_permitted') rethrow;
          await kur(AndroidScheduleMode.inexactAllowWhileIdle);
        }
        kurulan++;
      } on PlatformException catch (e) {
        hata = e.message ?? e.code; // tek bildirim patlarsa diğerleri kurulmaya devam eder
      } on ArgumentError {
        // Tetik kurulma anında geçmişe düştüyse atlanır; kalanlar kurulmaya devam eder.
      }
    }
    durum.value = durum.value.kopya(planli: kurulan, hata: hata, hataTemizle: hata == null);
  }
}
