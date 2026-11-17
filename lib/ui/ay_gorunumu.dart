// Ay görünümü: Pazartesi başlangıçlı hafta satırları.
// Telefon: çizgisiz sade ızgara + altta seçili günün listesi; güne dokunmak seçer, seçili güne
// ikinci dokunuş (ya da "Güne git") gün görünümünü açar. Kart tutamacı yukarı sürüklenince ay
// seçili günün haftasına daralır, aşağı sürüklenince açılır.
// Geniş ekran: başlıklı şeritli hücreler (yer var, şerit okunur); dokunma gün görünümünü açar.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'etkinlik_islemleri.dart';
import 'gorev_islemleri.dart';
import 'gun_verisi.dart';
import 'metin.dart';

class AyGorunumu extends StatelessWidget {
  const AyGorunumu({super.key, required this.kontrol, required this.ay, this.dar = false});

  final TakvimKontrol kontrol;

  /// Telefon düzeni (seçili gün listeli, çizgisiz).
  final bool dar;

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
    if (dar) return _AyDar(kontrol: kontrol, ay: ay, ilk: ilk);

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
          decoration: BoxDecoration(border: Border(top: BorderSide(color: tema.dividerColor.withValues(alpha: .2)))),
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

/// Telefon ayı: 6 sabit satır, çizgisiz; altta seçili günün etkinlik listesi.
class _AyDar extends StatefulWidget {
  const _AyDar({required this.kontrol, required this.ay, required this.ilk});
  final TakvimKontrol kontrol;
  final DateTime ay, ilk;

  @override
  State<_AyDar> createState() => _AyDarDurumu();
}

class _AyDarDurumu extends State<_AyDar> {
  bool _hafta = false; // true: yalnız seçili günün haftası

  TakvimKontrol get k => widget.kontrol;

  /// Seçili gün = odak günü bu aydaysa o, değilse bugün (bu aydaysa) ya da ayın 1'i.
  DateTime _secili() {
    bool buAy(DateTime d) => d.year == widget.ay.year && d.month == widget.ay.month;
    if (buAy(k.odakGun)) return k.odakGun;
    return buAy(k.bugun) ? k.bugun : widget.ay;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ay = widget.ay;
    final son = DateTime.utc(ay.year, ay.month + 1, 0);
    final satir = (haftaBasi(son).difference(widget.ilk).inDays ~/ 7) + 1; // 5 ya da 6 (Xiaomi gibi ay kadar satır)
    final gunler = [for (var i = 0; i < satir * 7; i++) gunEkle(widget.ilk, i)];
    final veriler = {for (final g in gunVerileri(k, gunler)) g.gun: g};
    final secili = _secili();
    final seciliSatir = gunler.indexOf(secili) ~/ 7;
    return Column(children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(child: Text(M.gunKisa[i], style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant))),
            ),
          ),
      ]),
      // Satır yüksekliği: kalan yüksekliğin ~%58'i satırlara bölünür, 52-68 aralığında kalır.
      Expanded(
        child: LayoutBuilder(builder: (context, kisit) {
          final h = (kisit.maxHeight * .58 / satir).clamp(52.0, 68.0);
          return Column(children: [
            for (var r = 0; r < satir; r++)
              if (!_hafta || r == seciliSatir)
                SizedBox(
                  height: h,
                  child: Row(children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: _DarHucre(
                          kontrol: k,
                          veri: veriler[gunler[r * 7 + c]]!,
                          buAy: gunler[r * 7 + c].month == ay.month,
                          secili: gunler[r * 7 + c] == secili,
                        ),
                      ),
                  ]),
                ),
            Expanded(child: _GunListesi(kontrol: k, veri: veriler[secili]!, hafta: _hafta, tutamac: (v) => setState(() => _hafta = v))),
          ]);
        }),
      ),
    ]);
  }
}

class _DarHucre extends StatelessWidget {
  const _DarHucre({required this.kontrol, required this.veri, required this.buAy, required this.secili});
  final TakvimKontrol kontrol;
  final GunVerisi veri;
  final bool buAy, secili;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = tema.colorScheme;
    final gun = veri.gun;
    final bugunMu = gun == kontrol.bugun;
    final renkler = [
      for (final t in veri.tumGun) t.renk,
      for (final y in veri.saatli) y.oge.renk,
    ];
    final adet = renkler.length;
    final yazi = bugunMu ? renk.onPrimary : (buAy ? renk.onSurface : renk.onSurface.withValues(alpha: .25));
    return Semantics(
      button: true,
      selected: secili,
      label: adet == 0 ? tarihTam(gun) : '${tarihTam(gun)}, $adet',
      excludeSemantics: true,
      child: InkWell(
        // Seçili güne ikinci dokunuş gün görünümünü açar.
        onTap: () => secili ? kontrol.git(gun, gorunum: Gorunum.gun) : kontrol.odakAyarla(gun),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              width: 46,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: bugunMu ? renk.primary : null,
                border: secili && !bugunMu ? Border.all(color: renk.primary, width: 1.5) : null,
              ),
              child: Stack(alignment: Alignment.center, children: [
                Text('${gun.day}', style: tema.textTheme.titleLarge?.copyWith(color: yazi, fontWeight: bugunMu ? FontWeight.w700 : FontWeight.w500)),
                Positioned(
                  bottom: 6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final r in renkler.take(3))
                      Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: bugunMu ? renk.onPrimary : r, shape: BoxShape.circle)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seçili günün etkinlikleri: tüm gün olanlar önde, sonra saatliler.
class _GunListesi extends StatelessWidget {
  const _GunListesi({required this.kontrol, required this.veri, required this.hafta, required this.tutamac});
  final TakvimKontrol kontrol;
  final GunVerisi veri;
  final bool hafta;

  /// Tutamaç: true = haftaya daralt, false = ayı aç.
  final void Function(bool) tutamac;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final soluk = tema.colorScheme.onSurfaceVariant;
    final satirlar = <Widget>[
      for (final t in veri.tumGun)
        _Satir(
          renk: t.renk,
          baslik: t.baslik,
          saat: M.tumGun,
          onTap: () => t.gorev != null ? gorevEylemleri(context, kontrol, t.gorev!) : etkinlikDetayGoster(context, kontrol, t.ornek!),
        ),
      for (final y in veri.saatli)
        _Satir(
          renk: y.oge.renk,
          baslik: y.oge.ornek.title,
          saat: '${saatMetni(y.oge.bas)} – ${saatMetni(y.oge.bit)}',
          onTap: () => y.oge.gorev != null ? gorevEylemleri(context, kontrol, y.oge.gorev!) : etkinlikDetayGoster(context, kontrol, y.oge.ornek),
        ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(color: tema.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Tutamaç: yukarı sürükle/dokun = haftaya daralt, aşağı sürükle/dokun = ayı aç.
        Semantics(
          button: true,
          label: hafta ? M.ayiAc : M.haftayaDaralt,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => tutamac(!hafta),
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -150) tutamac(true);
              if (v > 150) tutamac(false);
            },
            child: SizedBox(
              height: 24,
              child: Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: soluk.withValues(alpha: .5), borderRadius: BorderRadius.circular(2)))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 4, 0),
          child: Row(children: [
            Expanded(child: Text(gunUzun(veri.gun), style: tema.textTheme.titleSmall?.copyWith(color: soluk))),
            IconButton(tooltip: M.guneGit, icon: const Icon(Icons.arrow_forward), onPressed: () => kontrol.git(veri.gun, gorunum: Gorunum.gun)),
          ]),
        ),
        Expanded(
          child: satirlar.isEmpty
              ? Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: Align(alignment: Alignment.topLeft, child: Text(M.etkinlikYok, style: tema.textTheme.bodyMedium?.copyWith(color: soluk.withValues(alpha: .7)))))
              : ListView(padding: const EdgeInsets.only(bottom: 80), children: satirlar), // alt boşluk: + düğmesinin altına kaydırılabilsin
        ),
      ]),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.renk, required this.baslik, required this.saat, required this.onTap});
  final Color renk;
  final String baslik, saat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: tema.textTheme.bodyLarge),
                Text(saat, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
