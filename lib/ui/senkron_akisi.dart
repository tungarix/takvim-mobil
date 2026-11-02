// Senkron akışları: dosya gönder, dosya aç (seçici ya da Paylaş/Birlikte aç ile gelen),
// önizleme -> onay -> uygula -> sonuç. Hata olursa anlaşılır Türkçe mesaj; veri değişmez.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../sync/import.dart';
import 'metin.dart';

Future<void> senkronGonderAkisi(TakvimKontrol k) async {
  try {
    await k.senkronGonder();
  } catch (e) {
    k.mesaj(M.gonderHatasi(e), sure: const Duration(seconds: 8));
  }
}

Future<void> senkronAcAkisi(BuildContext context, TakvimKontrol k) async {
  final String? metin;
  try {
    metin = await k.dosyalar.senkronDosyasiSec();
  } on FormatException {
    k.mesaj(M.dosyaOkunamadi); // UTF-8 olmayan dosya
    return;
  } catch (e) {
    k.mesaj(M.hata(e));
    return;
  }
  if (metin == null || !context.mounted) return;
  await senkronIceAktar(context, k, metin);
}

/// Dışarıdan (Paylaş/Birlikte aç) gelen dosya: içerik metin ya da okuma hatası.
Future<void> disaridanGelen(TakvimKontrol k, {String? metin, String? hata}) async {
  final ctx = k.navigatorAnahtari.currentContext;
  if (ctx == null || !ctx.mounted) return;
  if (metin == null) {
    await _bilgi(ctx, M.dosyaOkunamadi, hata ?? '');
    return;
  }
  await senkronIceAktar(ctx, k, metin);
}

Future<void> senkronIceAktar(BuildContext context, TakvimKontrol k, String metin) async {
  final ImportRaporu onizleme;
  try {
    onizleme = k.senkronOnizle(metin);
  } catch (e) {
    await _bilgi(context, M.dosyaOkunamadi, TakvimKontrol.senkronHataMetni(e));
    return;
  }
  if (!context.mounted) return;
  final etkinlik = onizleme.event.added + onizleme.event.updated;
  final gorev = onizleme.task.added + onizleme.task.updated;
  final onay = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text(M.onizlemeBaslik),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (onizleme.degisti) Text(M.onizlemeOzet(etkinlik, gorev, onizleme.deleted)) else const Text(M.onizlemeDegisiklikYok),
        if (onizleme.calendar.added + onizleme.calendar.updated > 0)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('${M.takvimler}: ${onizleme.calendar.added + onizleme.calendar.updated}')),
        const SizedBox(height: 12),
        Text(M.onizlemeBirlesme, style: Theme.of(c).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(M.iptal)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(M.onizlemeUygula)),
      ],
    ),
  );
  if (onay != true || !context.mounted) return;
  final ImportRaporu rapor;
  try {
    rapor = await k.senkronUygula(metin);
  } catch (e) {
    if (context.mounted) await _bilgi(context, M.dosyaOkunamadi, TakvimKontrol.senkronHataMetni(e));
    return;
  }
  if (!context.mounted) return;
  await _bilgi(context, M.sonucBaslik, M.sonucOzet(rapor.added, rapor.updated, rapor.deleted, rapor.skipped));
}

Future<void> _bilgi(BuildContext context, String baslik, String govde) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(baslik),
        content: SingleChildScrollView(child: Text(govde)),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text(M.tamam))],
      ),
    );
