// Ay görünümü: Pazartesi başlangıçlı hafta satırları.
// Telefon: çizgisiz sade ızgara (hücrede başlıklı şeritler, sığmazsa noktalar) + altta seçili günün listesi; güne dokunmak seçer, seçili güne
// ikinci dokunuş (ya da "Güne git") gün görünümünü açar. Kart tutamacı yukarı sürüklenince ay
// seçili günün haftasına daralır, aşağı sürüklenince açılır.
// Geniş ekran: başlıklı şeritli hücreler (yer var, şerit okunur); dokunma gün görünümünü açar.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'dogum_gunu.dart';
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
    return Semantics(
      button: true,
      label: _hucreEtiketi(veri),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => kontrol.git(veri.gun, gorunum: Gorunum.gun),
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .2)))),
          padding: const EdgeInsets.all(2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: _GunSayisi(veri: veri, bugunMu: veri.gun == kontrol.bugun, buAy: buAy)),
            const SizedBox(height: 2),
            Expanded(child: _Seritler(kontrol: kontrol, veri: veri, buAy: buAy)),
          ]),
        ),
      ),
    );
  }
}

String _hucreEtiketi(GunVerisi veri) {
  final basliklar = [for (final t in veri.tumGun) t.baslik, for (final y in veri.saatli) y.oge.ornek.title];
  final tatil = veri.tatil == null ? '' : ', ${veri.tatil!.ad}';
  final adet = basliklar.isEmpty ? '' : ', ${basliklar.length}: ${basliklar.join(', ')}';
  return '${tarihTam(veri.gun)}$tatil$adet';
}

class _GunSayisi extends StatelessWidget {
  const _GunSayisi({required this.veri, required this.bugunMu, required this.buAy});
  final GunVerisi veri;
  final bool bugunMu, buAy;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = tema.colorScheme;
    final tatil = veri.tatil != null;
    final yazi = bugunMu ? renk.onPrimary : (tatil ? renk.error : renk.onSurface).withValues(alpha: buAy ? 1 : .38);
    return Container(
      width: 24,
      height: 22,
      alignment: Alignment.center,
      decoration: bugunMu ? BoxDecoration(color: renk.primary, borderRadius: BorderRadius.circular(8)) : null,
      child: Text('${veri.gun.day}', style: tema.textTheme.labelMedium?.copyWith(color: yazi, fontWeight: bugunMu || tatil ? FontWeight.w700 : null)),
    );
  }
}

/// Hücrenin kalan alanına sığdığı kadar şerit; "+N"; hiç sığmazsa renkli noktalar.
/// Sıra: resmi tatil, tüm gün (doğum günü/görev dahil), saatliler (başlangıca göre).
/// Saat yalnız geniş hücrede başlığa eklenir (telefonda yer dar, başlık daha değerli).
class _Seritler extends StatelessWidget {
  const _Seritler({required this.kontrol, required this.veri, required this.buAy});
  final TakvimKontrol kontrol;
  final GunVerisi veri;
  final bool buAy;

  static const _yuk = 14.0, _ara = 2.0, _artiYuk = 12.0;

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, kisit) {
      final genis = kisit.maxWidth >= 80;
      final seritler = <_Serit>[
        if (veri.tatil != null) _Serit(veri.tatil!.ad, renk.error, tatil: true),
        for (final t in veri.tumGun)
          () {
            final pasta = t.ornek != null && dogumGunuBilgisi(kontrol, t.ornek!) != null;
            final ad = pasta && !genis && t.baslik.endsWith(M.dogumGunuSonek) ? t.baslik.substring(0, t.baslik.length - M.dogumGunuSonek.length) : t.baslik;
            return _Serit(ad, t.renk, pasta: pasta);
          }(),
        for (final y in ([...veri.saatli]..sort((a, b) => a.oge.bas.compareTo(b.oge.bas))))
          _Serit('${genis && !y.oge.oncedenGelir ? '${saatMetni(y.oge.bas)} ' : ''}${y.oge.ornek.title}', y.oge.renk),
      ];
      final t = seritler.length;
      if (t == 0) return const SizedBox.shrink();
      var k = t;
      while (k > 0 && k * (_yuk + _ara) + (t > k ? _artiYuk : 0) > kisit.maxHeight) {
        k--;
      }
      if (k == 0) return _Noktalar(renkler: [for (final s in seritler) s.renk], genislik: kisit.maxWidth, yer: kisit.maxHeight);
      return ClipRect(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in seritler.take(k))
            Padding(padding: const EdgeInsets.only(bottom: _ara), child: SizedBox(height: _yuk, child: _SeritCubugu(s, ellipsis: genis))),
          if (t > k)
            SizedBox(height: _artiYuk, child: Text('+${t - k}', style: TextStyle(fontSize: 9, height: 1.2, color: renk.onSurfaceVariant.withValues(alpha: buAy ? 1 : .6)))),
        ]),
      );
    });
  }
}

class _Serit {
  const _Serit(this.metin, this.renk, {this.tatil = false, this.pasta = false});
  final String metin;
  final Color renk;
  final bool tatil, pasta;
}

class _SeritCubugu extends StatelessWidget {
  const _SeritCubugu(this.s, {required this.ellipsis});
  final _Serit s;
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final yazi = s.tatil ? renk.error : renk.onSurface;
    final metin = Text(s.metin,
        maxLines: 1, softWrap: false, overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.fade, style: TextStyle(fontSize: 10, height: 1.1, color: yazi));
    final icerik = Row(children: [
      if (s.pasta) Padding(padding: const EdgeInsets.only(right: 2), child: Icon(Icons.cake_outlined, size: 9, color: yazi)),
      Expanded(child: metin),
    ]);
    if (s.tatil) {
      return CustomPaint(painter: _KesikKenar(s.renk), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: icerik));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: s.renk.withValues(alpha: .24),
        child: Row(children: [
          Container(width: 2.5, color: s.renk),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: icerik)),
        ]),
      ),
    );
  }
}

class _KesikKenar extends CustomPainter {
  _KesikKenar(this.renk);
  final Color renk;

  @override
  void paint(Canvas canvas, Size boyut) {
    final yol = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & boyut).deflate(.5), const Radius.circular(4)));
    final boya = Paint()
      ..color = renk.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in yol.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 5) {
        canvas.drawPath(m.extractPath(d, d + 3), boya);
      }
    }
  }

  @override
  bool shouldRepaint(_KesikKenar eski) => eski.renk != renk;
}

class _Noktalar extends StatelessWidget {
  const _Noktalar({required this.renkler, required this.genislik, required this.yer});
  final List<Color> renkler;
  final double genislik, yer;

  @override
  Widget build(BuildContext context) {
    if (yer < 6) return const SizedBox.shrink();
    final sigan = ((genislik - 2) / 9).floor().clamp(1, 5);
    final adet = renkler.length;
    return Wrap(spacing: 3, runSpacing: 3, alignment: WrapAlignment.center, children: [
      for (final r in renkler.take(adet > sigan ? sigan - 1 : sigan)) Container(width: 6, height: 6, decoration: BoxDecoration(color: r, shape: BoxShape.circle)),
      if (adet > sigan) Text('+${adet - sigan + 1}', style: const TextStyle(fontSize: 8, height: .75)),
    ]);
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
  TakvimKontrol get k => widget.kontrol;
  bool get _hafta => k.ayDaraldi; // true: yalnız seçili günün haftası

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
      // Satır yüksekliği: kalan yüksekliğin ~%60'ı satırlara bölünür (60-78); daralmış haftada şeritler için 130.
      Expanded(
        child: LayoutBuilder(builder: (context, kisit) {
          final h = _hafta ? 130.0 : (kisit.maxHeight * .6 / satir).clamp(60.0, 78.0);
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
            Expanded(child: _GunListesi(kontrol: k, veri: veriler[secili]!, hafta: _hafta, tutamac: k.ayDaralt)),
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
    final renk = Theme.of(context).colorScheme;
    final gun = veri.gun;
    return Semantics(
      button: true,
      selected: secili,
      label: _hucreEtiketi(veri),
      excludeSemantics: true,
      child: InkWell(
        // Seçili güne ikinci dokunuş gün görünümünü açar.
        onTap: () => secili ? kontrol.git(gun, gorunum: Gorunum.gun) : kontrol.odakAyarla(gun),
        child: Container(
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.fromLTRB(2, 3, 2, 1),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: secili ? Border.all(color: renk.primary, width: 1.5) : null),
          child: Column(children: [
            _GunSayisi(veri: veri, bugunMu: gun == kontrol.bugun, buAy: buAy),
            const SizedBox(height: 2),
            Expanded(child: _Seritler(kontrol: kontrol, veri: veri, buAy: buAy)),
          ]),
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
    String tumGunAlt(TumGunOgesi t) {
      final yas = t.ornek == null ? null : dogumGunuBilgisi(kontrol, t.ornek!)?.yas;
      return yas == null ? M.tumGun : M.yasinaGiriyor(yas);
    }

    final tatil = veri.tatil;
    final satirlar = <Widget>[
      if (tatil != null) _Satir(renk: tema.colorScheme.error, baslik: tatil.ad, saat: tatil.yarim ? M.resmiTatilYarim : M.resmiTatil, onTap: null),
      for (final t in veri.tumGun)
        _Satir(
          renk: t.renk,
          baslik: t.baslik,
          saat: tumGunAlt(t),
          pasta: t.ornek != null && dogumGunuBilgisi(kontrol, t.ornek!) != null,
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
  const _Satir({required this.renk, required this.baslik, required this.saat, required this.onTap, this.pasta = false});
  final Color renk;
  final bool pasta;
  final String baslik, saat;
  final VoidCallback? onTap; // null: salt okunur (resmi tatil)

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
            if (pasta) Icon(Icons.cake_outlined, size: 20, color: renk), // süs: anlam başlıkta ve alt metinde
          ]),
        ),
      ),
    );
  }
}
