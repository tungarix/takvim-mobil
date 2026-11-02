// Tarih/saat/renk biçimleme yardımcıları. Duvar saatleri (UTC işaretli sahte
// DateTime) üzerinde çalışır; intl kullanmaz, adlar metin.dart'tan gelir.
import 'package:flutter/material.dart';

import '../core/yerel_zaman.dart';
import 'metin.dart';

String _iki(int n) => n.toString().padLeft(2, '0');

String saatMetni(DateTime duvar) => '${_iki(duvar.hour)}:${_iki(duvar.minute)}';

String gunAdi(DateTime d) => M.gunAdlari[d.weekday - 1];

/// "3 Kasım Salı"
String gunUzun(DateTime d) => '${d.day} ${M.ayAdlari[d.month - 1]} ${gunAdi(d)}';

/// "3 Kas"
String gunKisaMetin(DateTime d) => '${d.day} ${M.ayKisa[d.month - 1]}';

/// "3 Kasım 2026 Salı"
String tarihTam(DateTime d) => '${d.day} ${M.ayAdlari[d.month - 1]} ${d.year} ${gunAdi(d)}';

/// "Kasım 2026"
String ayYil(DateTime d) => '${M.ayAdlari[d.month - 1]} ${d.year}';

/// Yıl, bugünün yılından farklıysa eklenir.
String gunBaglamli(DateTime d, DateTime bugun) =>
    d.year == bugun.year ? gunKisaMetin(d) : '${gunKisaMetin(d)} ${d.year}';

/// Plan günü etiketi: Bugün / Yarın / 5 Kas Per.
String planGunu(DateTime gun, DateTime bugun) {
  final fark = gun.difference(gunDuvar(bugun)).inDays;
  if (fark == 0) return M.bugun;
  if (fark == 1) return M.yarin;
  return '${gunBaglamli(gun, bugun)} ${M.gunKisa[gun.weekday - 1]}';
}

/// "#rrggbb" -> Color; geçersizse gri (renk metni dosyadan gelir, çökertmesin).
Color renkOku(String hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex);
  if (m == null) return const Color(0xFF6B7280);
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

String renkYaz(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// Zemin renginin üstüne okunur yazı rengi.
Color yaziRengi(Color zemin) =>
    ThemeData.estimateBrightnessForColor(zemin) == Brightness.dark ? Colors.white : const Color(0xFF111827);

/// Takvim rengi seçenekleri (ilki masaüstü varsayılanı).
const takvimRenkleri = [
  '#3b82f6', '#e0524a', '#16a34a', '#f59e0b', '#8b5cf6',
  '#ec4899', '#0891b2', '#65a30d', '#ea580c', '#64748b',
];

const varsayilanTakvimAdi = 'Kişisel';
const varsayilanTakvimRengi = '#3b82f6';
