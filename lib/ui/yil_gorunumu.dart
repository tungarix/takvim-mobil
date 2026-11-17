// Yıl görünümü: üç sütunda 12 küçük ay (kısa ad, hafta günü başlıkları, gün numaraları).
// Aya dokunmak o ayın ay görünümünü açar; içinde bulunulan ay vurgu renginde, bugün küçük vurgu karesinde.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerel_zaman.dart';
import 'metin.dart';

class YilGorunumu extends StatelessWidget {
  const YilGorunumu({super.key, required this.kontrol, required this.yil});

  final TakvimKontrol kontrol;
  final int yil;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Column(children: [
        for (var r = 0; r < 4; r++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var c = 0; c < 3; c++) Expanded(child: _Ay(kontrol: kontrol, yil: yil, ay: r * 3 + c + 1)),
          ]),
      ]),
    );
  }
}

class _Ay extends StatelessWidget {
  const _Ay({required this.kontrol, required this.yil, required this.ay});
  final TakvimKontrol kontrol;
  final int yil;
  final int ay;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = tema.colorScheme;
    final bugun = kontrol.bugun;
    final buAy = bugun.year == yil && bugun.month == ay;
    final ilk = DateTime.utc(yil, ay, 1);
    final bas = haftaBasi(ilk);
    final gunSayisi = DateTime.utc(yil, ay + 1, 0).day;
    final satir = (ilk.difference(bas).inDays + gunSayisi + 6) ~/ 7;
    final kucuk = tema.textTheme.labelSmall?.copyWith(fontSize: 10, height: 1.1);

    Widget hucre(String? metin, {bool bugunMu = false, Color? renkli}) => Expanded(
          child: Container(
            height: 16,
            margin: const EdgeInsets.all(.5),
            alignment: Alignment.center,
            decoration: bugunMu ? BoxDecoration(color: renk.primary, borderRadius: BorderRadius.circular(4)) : null,
            child: metin == null
                ? null
                : Text(metin, style: kucuk?.copyWith(color: bugunMu ? renk.onPrimary : renkli ?? renk.onSurface, fontWeight: bugunMu ? FontWeight.w700 : null)),
          ),
        );

    return Semantics(
      button: true,
      label: '${M.ayAdlari[ay - 1]} $yil',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => kontrol.git(buAy ? bugun : ilk, gorunum: Gorunum.ay),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(M.ayKisa[ay - 1],
                  style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: buAy ? renk.primary : renk.onSurface)),
            ),
            Row(children: [for (var i = 0; i < 7; i++) hucre(M.gunTek[i], renkli: renk.onSurfaceVariant)]),
            for (var r = 0; r < satir; r++)
              Row(children: [
                for (var c = 0; c < 7; c++)
                  () {
                    final g = gunEkle(bas, r * 7 + c);
                    if (g.month != ay) return hucre(null);
                    return hucre('${g.day}', bugunMu: g == bugun, renkli: c >= 5 ? renk.primary : null);
                  }(),
              ]),
          ]),
        ),
      ),
    );
  }
}
