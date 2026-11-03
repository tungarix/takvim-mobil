// Wi-Fi eşleştirme akışı (takvim/docs/senkron-wifi.md §1, §4):
// bağlantı -> doğrula -> 1. onay (bu bilgisayarla eşleşilsin mi) -> bağlan, bilgisayarın durumunu al
// -> önizleme + 2. onay (Birleştir ve gönder) -> telefona uygula -> telefonun tam durumunu gönder -> iki rapor.
//
// İlke: kullanıcı onaylamadan ağ isteği yok; ikinci onaydan önce hiçbir veri gönderilmez ve telefon
// verisi değişmez. Bağlantı (App Link, yapıştırma) bu akışı yalnız BAŞLATIR, kendiliğinden bağlanmaz.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../sync/import.dart';
import '../sync/wifi_baglanti.dart';
import '../sync/wifi_istemci.dart';
import 'metin.dart';
import 'senkron_akisi.dart';

/// Ayarlar > Wi-Fi ile eşleştir: anlatım + "bağlantıyı yapıştır" alanı.
Future<void> wifiEslestirSayfasiAc(BuildContext context, TakvimKontrol k) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WifiEslestirSayfasi(kontrol: k)));

class WifiEslestirSayfasi extends StatefulWidget {
  const WifiEslestirSayfasi({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  State<WifiEslestirSayfasi> createState() => _WifiEslestirDurumu();
}

class _WifiEslestirDurumu extends State<WifiEslestirSayfasi> {
  final _alan = TextEditingController();

  @override
  void dispose() {
    _alan.dispose();
    super.dispose();
  }

  Future<void> _devam() async {
    final s = _alan.text;
    if (s.trim().isEmpty) return;
    await wifiBaglantiIsle(context, widget.kontrol, s);
    if (mounted && !widget.kontrol.wifiMesgul) _alan.clear(); // bağlantı (token) alanda kalmasın
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(M.wifiSayfaBaslik)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(M.wifiAdimlar),
        const SizedBox(height: 16),
        TextField(
          controller: _alan,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: M.wifiBaglantiAlan, hintText: M.wifiBaglantiIpucu),
        ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _devam, child: const Text(M.wifiDevam))),
        const SizedBox(height: 16),
        Text(M.wifiYedekYol, style: tema.textTheme.bodySmall),
      ]),
    );
  }
}

/// Bağlantı App Link'ten geldi: gezgin hazırsa onay ekranını açar.
Future<void> wifiBaglantiGeldi(TakvimKontrol k, String baglanti) async {
  final ctx = k.navigatorAnahtari.currentContext;
  if (ctx == null || !ctx.mounted) return;
  await wifiBaglantiIsle(ctx, k, baglanti);
}

/// Bağlantıyı doğrular, onay ister, onaylanırsa tüm akışı yürütür. Hata ve vazgeçmede veri değişmez.
Future<void> wifiBaglantiIsle(BuildContext context, TakvimKontrol k, String girdi) async {
  if (k.wifiMesgul) {
    k.mesaj(M.wifiMesgul);
    return;
  }
  k.wifiMesgul = true;
  try {
    final WifiBaglanti b;
    try {
      b = wifiBaglantiAyristir(girdi);
    } on WifiBaglantiHatasi catch (e) {
      if (context.mounted) await bilgiPenceresi(context, M.wifiBaglantiGecersizBaslik, M.wifiBaglantiHata(e.tur));
      return;
    }
    if (!context.mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(M.wifiOnayBaslik),
        content: SingleChildScrollView(child: Text(M.wifiOnayMetni(b.ad, b.adres))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(M.iptal)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(M.wifiBaglan)),
        ],
      ),
    );
    if (onay != true || !context.mounted) return;
    final oturum = k.wifiOturumu(b);
    try {
      await _oturumuYurut(context, k, oturum);
    } finally {
      oturum.kapat();
    }
  } finally {
    k.wifiMesgul = false;
  }
}

Future<void> _oturumuYurut(BuildContext context, TakvimKontrol k, WifiOturum oturum) async {
  // 1) Bilgisayarın durumunu al (henüz hiçbir veri gönderilmedi).
  final String metin;
  final kapat1 = _ilerlemeAc(context, M.wifiBaglaniyor, oturum.kapat);
  try {
    await oturum.hello();
    metin = await oturum.durumAl();
  } catch (e) {
    kapat1();
    if (context.mounted) await _hataGoster(context, e, ek: '');
    return;
  }
  kapat1();
  if (!context.mounted) return;

  // 2) Önizleme + ikinci onay. Vazgeçilirse ya da dosya geçersizse ağa hiçbir şey gitmez, veri değişmez.
  final ImportRaporu onizleme;
  try {
    onizleme = k.senkronOnizle(metin);
  } catch (e) {
    await bilgiPenceresi(context, M.wifiDosyaGecersiz, TakvimKontrol.senkronHataMetni(e));
    return;
  }
  if (!context.mounted) return;
  final devam = await onizlemeSor(context, onizleme,
      baslik: M.wifiOnizlemeBaslik, onay: M.wifiBirlestirGonder, not: M.wifiOnizlemeNot);
  if (!devam || !context.mounted) return;

  // 3) Telefona uygula (güncel veriyle yeniden birleştirir; bildirimler yeniden kurulur, son senkron yazılır).
  final ImportRaporu yerel;
  try {
    yerel = await k.senkronUygula(metin);
  } catch (e) {
    if (context.mounted) await bilgiPenceresi(context, M.dosyaOkunamadi, TakvimKontrol.senkronHataMetni(e));
    return;
  }
  if (!context.mounted) return;

  // 4) Birleşmiş tam durumu gönder; bilgisayar kendi ekranında onay sorar.
  final kapat2 = _ilerlemeAc(context, M.wifiOnayBekleniyor, oturum.kapat);
  final WifiRapor uzak;
  try {
    uzak = await oturum.durumGonder(k.senkronMetni());
  } catch (e) {
    kapat2();
    if (context.mounted) await _hataGoster(context, e, ek: M.wifiGonderilemediEk, iptalEk: M.wifiGonderIptalEk);
    return;
  }
  kapat2();
  if (!context.mounted) return;
  await bilgiPenceresi(context, M.wifiSonucBaslik, M.wifiSonucOzet(yerel, uzak));
}

Future<void> _hataGoster(BuildContext context, Object e, {required String ek, String? iptalEk}) async {
  // Çağıran context.mounted denetledi.
  final h = e is WifiHatasi ? e : WifiHatasi(WifiHataTuru.beklenmeyen, e.runtimeType.toString());
  if (h.tur == WifiHataTuru.iptal) {
    if (iptalEk != null) await bilgiPenceresi(context, M.wifiHataBaslik, iptalEk);
    return; // bağlanma aşamasında vazgeçmek sessizdir
  }
  await bilgiPenceresi(
    context,
    h.tur == WifiHataTuru.parmakIzi ? M.wifiGuvenlikBaslik : M.wifiHataBaslik,
    M.wifiHata(h.tur, h.ayrinti) + ek,
  );
}

/// Dönen ilerleme penceresi; kapatma işlevini verir. "İptal" oturumu keser (bekleyen istek hata ile biter).
VoidCallback _ilerlemeAc(BuildContext context, String metin, VoidCallback iptal) {
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Expanded(child: Text(metin)),
        ]),
        actions: [TextButton(onPressed: iptal, child: const Text(M.iptal))],
      ),
    ),
  ));
  var kapali = false;
  return () {
    if (kapali) return;
    kapali = true;
    if (context.mounted) Navigator.of(context).pop();
  };
}
