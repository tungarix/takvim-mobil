// Ay görünümü: Pazartesi başlangıçlı hafta satırları. Hücrede telefonda renkli
// noktalar, geniş ekranda başlıklı şeritler; güne dokununca gün görünümü açılır.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'gun_verisi.dart';
import 'metin.dart';

class AyGorunumu extends StatelessWidget {
  const AyGorunumu({super.key, required this.kontrol, required this.ay});

  final TakvimKontrol kontrol;

  /// Ayın 1'i (duvar günü).
  final DateTime ay;

  @override
  Widget build(BuildContext context) {
    final ilk = haftaBasi(ay);
    final sonGun = DateTime.utc(ay.year, ay.month + 1, 0);
    final satirSayisi = (haftaBasi(sonGun).difference(ilk).inDays ~/ 7) + 1;
    final gunler = [for (var i = 0; i < satirSayisi * 7; i++) gunEkle(ilk, i)];
    final veriler = {for (final g in gunVerileri(kontrol, gunler)) g.gun: g};
    final tema = Theme.of(context);

    return Column(children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(child: Text(M.gunKisa[i], style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant))),
            ),
          ),
      ]),
      Divider(height: 1, color: tema.dividerColor),
      Expanded(
        child: Column(children: [
          for (var r = 0; r < satirSayisi; r++)
            Expanded(
              child: Row(children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _Hucre(kontrol: kontrol, veri: veriler[gunler[r * 7 + c]]!, buAy: gunler[r * 7 + c].month == ay.month)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _Hucre extends StatelessWidget {
  const _Hucre({required this.kontrol, required this.veri, required this.buAy});
  final TakvimKontrol kontrol;
  final GunVerisi veri;
  final bool buAy;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final gun = veri.gun;
    final bugunMu = gun == kontrol.bugun;
    // Saatlilar başlangıca göre, tüm gün olanlar önde.
    final ogeler = [
      for (final t in veri.tumGun) (t.baslik, t.renk, true),
      for (final y in veri.saatli) (y.oge.ornek.title, y.oge.renk, false),
    ];
    final adet = ogeler.length;
    return Semantics(
      button: true,
      label: adet == 0 ? tarihTam(gun) : '${tarihTam(gun)}, $adet',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => kontrol.git(gun, gorunum: Gorunum.gun),
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: tema.dividerColor.withValues(alpha: .5)), left: BorderSide(color: tema.dividerColor.withValues(alpha: .3)))),
          padding: const EdgeInsets.all(2),
          child: LayoutBuilder(builder: (context, kisit) {
            final sol = buAy ? tema.colorScheme.onSurface : tema.colorScheme.onSurface.withValues(alpha: .38);
            final sayi = Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bugunMu ? tema.colorScheme.primary : null),
              child: Text('${gun.day}', style: tema.textTheme.labelMedium?.copyWith(color: bugunMu ? tema.colorScheme.onPrimary : sol)),
            );
            // Geniş hücrede başlıklı şerit, dar hücrede nokta.
            final serit = kisit.maxWidth >= 84;
            final kalan = kisit.maxHeight - 28;
            if (serit) {
              final n = (kalan / 17).floor().clamp(0, 4);
              final gosterilen = adet > n && n > 0 ? n - 1 : n;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(alignment: Alignment.centerLeft, child: sayi),
                for (final (baslik, renk, _) in ogeler.take(gosterilen))
                  Container(
                    height: 15,
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3)),
                    child: Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: yaziRengi(renk))),
                  ),
                if (adet > gosterilen && n > 0) Padding(padding: const EdgeInsets.only(top: 1), child: Text('+${adet - gosterilen}', style: tema.textTheme.labelSmall)),
              ]);
            }
            final nokta = ((kisit.maxWidth - 2) / 9).floor().clamp(1, 5);
            return Column(children: [
              sayi,
              const SizedBox(height: 3),
              if (kalan > 6)
                Wrap(spacing: 3, runSpacing: 3, alignment: WrapAlignment.center, children: [
                  for (final (_, renk, _) in ogeler.take(adet > nokta ? nokta - 1 : nokta)) Container(width: 6, height: 6, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
                  if (adet > nokta) Text('+${adet - nokta + 1}', style: const TextStyle(fontSize: 8, height: .75)),
                ]),
            ]);
          }),
        ),
      ),
    );
  }
}
