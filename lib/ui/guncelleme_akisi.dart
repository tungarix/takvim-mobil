// Otomatik güncelleme akışları: ilk açılış sorusu, arka plan denetimi, "Şimdi denetle", kurulum.
// Kurallar (takvim/docs/guncelleme.md): seçim yapılmadan AĞ İSTEĞİ YOK; kurulumdan önce HER ZAMAN onay;
// mobil veride ayrı onay; indirilen APK doğrulanmadan kurulum penceresi açılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/kontrol.dart';
import '../guncelleme/ag.dart';
import '../guncelleme/hizmet.dart';
import 'metin.dart';

/// Açılışta ve arka plandan dönüşte: seçim yoksa (yalnız açılışta) sorar; açıksa günde en çok bir denetim.
/// Hata uygulamanın işini bozmamalı: tümü yutulur, durum Ayarlar'da görünür.
Future<void> guncellemeAcilis(TakvimKontrol k, {bool sor = true}) async {
  final g = k.guncelleyici;
  if (g == null) return;
  try {
    if (g.denetim == null) {
      if (!sor) return;
      final evet = await _ilkSoru(k);
      if (evet == null) return;
      await g.denetimYaz(evet);
      if (!evet) return;
      await g.denetle(); // kullanıcı az önce onayladı: ilk denetimi hemen yap
    } else {
      await g.otomatikAdim();
    }
    final y = g.teklif;
    if (y != null) k.mesaj(M.guncellemeHazirMesaj(y.surum), sure: const Duration(seconds: 8));
  } on Object catch (_) {
    // sessiz: güncelleme bilgisi uygulamanın açılışını bozmaz
  }
}

/// Mobilde seçim ZORUNLU (geri tuşu kapatmaz): Evet → true, Hayır → false. Pencere kurulamazsa null.
Future<bool?> _ilkSoru(TakvimKontrol k) async {
  final ctx = k.navigatorAnahtari.currentContext;
  if (ctx == null || !ctx.mounted) return null;
  return showDialog<bool>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text(M.guncellemeSoruBaslik),
        content: const SingleChildScrollView(child: Text(M.guncellemeSoruMetin)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(M.guncellemeSoruHayir)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(M.guncellemeSoruEvet)),
        ],
      ),
    ),
  );
}

/// Ayarlar → "Şimdi denetle": kullanıcının kendi isteği (otomatik denetim kapalıyken de çalışır).
Future<void> guncellemeSimdiDenetle(TakvimKontrol k) async {
  final g = k.guncelleyici;
  if (g == null) return;
  await g.denetle();
  final kod = g.hataKodu;
  if (kod != null) {
    k.mesaj(M.guncellemeHata(kod));
  } else {
    final y = g.teklif;
    k.mesaj(y != null ? M.guncellemeHazirMesaj(y.surum) : M.guncellemeGuncel);
  }
}

Future<bool> _soru(BuildContext c, String baslik, String metin, String onay) async {
  final s = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(baslik),
      content: SingleChildScrollView(child: Text(metin)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text(M.iptal)),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(onay)),
      ],
    ),
  );
  return s == true;
}

/// Kullanıcı onayıyla kurar: onay → ağ türü → izin → indir + doğrula → sistemin kurulum penceresi.
/// Her adımda vazgeçilebilir; hata mevcut sürümle devam demektir (veri değişmez).
Future<void> guncellemeKurAkisi(BuildContext context, TakvimKontrol k) async {
  final g = k.guncelleyici, kopru = k.kopru;
  final y = g?.teklif;
  if (g == null || kopru == null || y == null) return;
  final mb = (y.apkBoyut / (1024 * 1024)).toStringAsFixed(0);

  if (!await _soru(context, M.guncellemeKurBaslik, M.guncellemeKurMetin(y.surum, mb), M.guncellemeKurOnay) || !context.mounted) return;

  final ag = await kopru.agTuru();
  if (ag == 'yok') {
    k.mesaj(M.guncellemeCevrimdisi);
    return;
  }
  if (ag == 'mobil' && (!await _soru(context, M.guncellemeMobilBaslik, M.guncellemeMobilMetin(mb), M.guncellemeMobilOnay) || !context.mounted)) return;

  if (!await kopru.kurulumIzniVar()) {
    if (!context.mounted) return;
    if (await _soru(context, M.guncellemeIzinBaslik, M.guncellemeIzinMetin, M.guncellemeIzinAc)) await kopru.kurulumIzniAc();
    return; // izin verildikten sonra kullanıcı düğmeye yeniden basar
  }

  if (!context.mounted) return;
  final nav = Navigator.of(context, rootNavigator: true);
  final alinan = ValueNotifier<int>(0);
  ModalRoute<Object?>? ilerlemeRotasi;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: Builder(builder: (c2) {
          ilerlemeRotasi = ModalRoute.of(c2);
          return AlertDialog(
          title: const Text(M.guncellemeIndiriliyor),
          content: ValueListenableBuilder<int>(
            valueListenable: alinan,
            builder: (_, n, _) => LinearProgressIndicator(value: y.apkBoyut == 0 ? null : (n / y.apkBoyut).clamp(0.0, 1.0)),
          ),
        );
        }),
      ),
    ),
  );
  var pencereAcik = true;
  void ilerlemeyiKapat() {
    if (!pencereAcik) return;
    pencereAcik = false;
    // Yalnızca KENDİ penceremizi kapat: üstüne başka bir rota (ör. Wi-Fi onayı) binmiş olabilir.
    final r = ilerlemeRotasi;
    if (r != null && r.isActive) nav.removeRoute(r);
  }

  try {
    final apk = await g.hazirla(y, ilerleme: (n) => alinan.value = n);
    ilerlemeyiKapat();
    // Doğrulama ile kurulum arasında dosya değişmiş mi (derinlemesine savunma; asıl koruma Android imzası).
    if (await Guncelleyici.dosyaOzeti(apk) != g.sonDogrulananOzet) throw const GuncellemeHatasi('ozet_uyusmuyor', 'kurulumdan önce yeniden doğrulama');
    await kopru.apkKur(apk.path);
    // Kurulum penceresi açıldı; sonrası Android'in işi (başarıda uygulama yenisiyle değiştirilir).
  } on GuncellemeHatasi catch (e) {
    ilerlemeyiKapat();
    k.mesaj(M.guncellemeHata(e.kod), sure: const Duration(seconds: 8));
  } on PlatformException catch (e) {
    ilerlemeyiKapat();
    k.mesaj(M.guncellemeKurulamadi(e.message ?? e.code), sure: const Duration(seconds: 8));
  } on Object catch (e) {
    ilerlemeyiKapat();
    k.mesaj(M.hata(e));
  } finally {
    alinan.dispose();
  }
}

/// Sistem kurulum oturumunun sonucu: başarısız/engellenen kurulumda sessiz kalma (0 = başarı, -1 = onay bekliyor).
void guncellemeKurulumSonucu(TakvimKontrol k, int durum, String? mesaj) {
  if (durum == 0 || durum == -1) return;
  k.mesaj(M.guncellemeKurulamadi(M.kurulumDurumu(durum, mesaj)), sure: const Duration(seconds: 10));
}
