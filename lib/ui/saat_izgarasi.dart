// Gün ve hafta görünümü: saat ızgarası + tüm gün şeridi + şimdi çizgisi.
// Gün görünümü 1 kolon, hafta görünümü 7 kolondur; telefonda hafta, kolon başına
// (genişlik/3) ile yatay kaydırılır (7 kolon sığdırılsa başlıklar okunmaz olurdu).
//
// Saat konumları duvar saatinden hesaplanır (dakika / 60 * saatYuksekligi). DST
// gününde tekrarlayan saat ayrı çizilmez; Türkiye'de DST yok, bilinen sınır.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerlesim.dart';
import 'bicim.dart';
import 'etkinlik_islemleri.dart';
import 'gorev_islemleri.dart';
import 'gun_verisi.dart';
import 'metin.dart';

const double saatYuksekligi = 56;
const double etiketGenisligi = 44;
const double _baslikYuksekligi = 52;
const double _seritSatiri = 26;
const int _seritEnFazla = 3;

class SaatIzgarasi extends StatefulWidget {
  const SaatIzgarasi({super.key, required this.kontrol, required this.gunler, this.kolonGenisligi});

  final TakvimKontrol kontrol;
  final List<DateTime> gunler;

  /// Verilirse kolonlar bu genişlikte olur ve sığmıyorsa yatay kaydırılır.
  final double? kolonGenisligi;

  @override
  State<SaatIzgarasi> createState() => _SaatIzgarasiDurumu();
}

class _SaatIzgarasiDurumu extends State<SaatIzgarasi> {
  late final ScrollController _dikey;
  final _etiketKaydirma = ScrollController();
  final _yatay = ScrollController();
  Timer? _zamanlayici;
  bool _yatayAyarlandi = false;

  @override
  void initState() {
    super.initState();
    final k = widget.kontrol;
    final bugunMu = widget.gunler.contains(k.bugun);
    final saat = bugunMu ? (k.zaman.duvar(k.simdi).hour - 1).clamp(0, 18) : 7;
    _dikey = ScrollController(initialScrollOffset: saat * saatYuksekligi)..addListener(_etiketleriEsle);
    // Şimdi çizgisi dakikada bir ilerler; widget kalkınca iptal edilir.
    _zamanlayici = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _etiketleriEsle() {
    if (_etiketKaydirma.hasClients) {
      _etiketKaydirma.jumpTo(_dikey.offset.clamp(0.0, _etiketKaydirma.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _dikey.dispose();
    _etiketKaydirma.dispose();
    _yatay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kontrol;
    final tema = Theme.of(context);
    final gunler = widget.gunler;
    final veriler = gunVerileri(k, gunler);
    final enCokSerit = veriler.map((g) => g.tumGun.length).fold(0, (a, b) => a > b ? a : b);
    final seritYuk = enCokSerit == 0 ? 0.0 : (enCokSerit > _seritEnFazla ? _seritEnFazla : enCokSerit) * _seritSatiri + 6;
    final ustYuk = _baslikYuksekligi + seritYuk;

    return LayoutBuilder(builder: (context, kisit) {
      final alan = kisit.maxWidth - etiketGenisligi;
      final kolonW = widget.kolonGenisligi ?? alan / gunler.length;
      final icerikW = kolonW * gunler.length;
      final kayar = icerikW > alan + 0.5;
      if (kayar && !_yatayAyarlandi) {
        // Telefonda hafta: odak gününün kolonu solda başlasın (bir kez).
        _yatayAyarlandi = true;
        final i = gunler.indexOf(k.odakGun);
        if (i > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_yatay.hasClients) _yatay.jumpTo((i * kolonW).clamp(0.0, _yatay.position.maxScrollExtent));
          });
        }
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: etiketGenisligi,
          child: Column(children: [
            SizedBox(height: ustYuk),
            Expanded(
              child: SingleChildScrollView(
                controller: _etiketKaydirma,
                physics: const NeverScrollableScrollPhysics(),
                child: const _SaatEtiketleri(),
              ),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _yatay,
            scrollDirection: Axis.horizontal,
            physics: kayar ? null : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: icerikW,
              child: Column(children: [
                SizedBox(
                  height: _baslikYuksekligi,
                  child: Row(children: [
                    for (final g in veriler) SizedBox(width: kolonW, child: _GunBasligi(kontrol: k, gun: g.gun, tek: gunler.length == 1)),
                  ]),
                ),
                if (seritYuk > 0)
                  SizedBox(
                    height: seritYuk,
                    child: Row(children: [for (final g in veriler) SizedBox(width: kolonW, child: _TumGunSeridi(kontrol: k, veri: g))]),
                  ),
                Divider(height: 1, color: tema.dividerColor),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _dikey,
                    child: SizedBox(
                      height: 24 * saatYuksekligi,
                      child: Row(children: [for (final g in veriler) SizedBox(width: kolonW, child: _GunKolonu(kontrol: k, veri: g, genislik: kolonW))]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]);
    });
  }
}

class _SaatEtiketleri extends StatelessWidget {
  const _SaatEtiketleri();

  @override
  Widget build(BuildContext context) {
    final stil = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ExcludeSemantics(
      child: SizedBox(
        height: 24 * saatYuksekligi,
        child: Stack(children: [
          for (var s = 1; s < 24; s++)
            Positioned(top: s * saatYuksekligi - 7, left: 0, right: 6, child: Text('${s.toString().padLeft(2, '0')}:00', textAlign: TextAlign.right, style: stil)),
        ]),
      ),
    );
  }
}

class _GunBasligi extends StatelessWidget {
  const _GunBasligi({required this.kontrol, required this.gun, required this.tek});
  final TakvimKontrol kontrol;
  final DateTime gun;
  final bool tek;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bugunMu = gun == kontrol.bugun;
    final renk = bugunMu ? tema.colorScheme.primary : tema.colorScheme.onSurface;
    final icerik = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(M.gunKisa[gun.weekday - 1], style: tema.textTheme.labelMedium?.copyWith(color: renk)),
      const SizedBox(height: 2),
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bugunMu ? tema.colorScheme.primary : null),
        child: Text('${gun.day}',
            style: tema.textTheme.titleSmall?.copyWith(color: bugunMu ? tema.colorScheme.onPrimary : tema.colorScheme.onSurface)),
      ),
    ]);
    if (tek) return Semantics(label: tarihTam(gun), child: icerik);
    // Haftada başlığa dokunmak o günü gün görünümünde açar.
    return Semantics(
      button: true,
      label: tarihTam(gun),
      child: InkWell(onTap: () => kontrol.git(gun, gorunum: Gorunum.gun), child: icerik),
    );
  }
}

class _TumGunSeridi extends StatelessWidget {
  const _TumGunSeridi({required this.kontrol, required this.veri});
  final TakvimKontrol kontrol;
  final GunVerisi veri;

  @override
  Widget build(BuildContext context) {
    final ogeler = veri.tumGun;
    final fazla = ogeler.length - _seritEnFazla;
    final gosterilen = fazla > 0 ? ogeler.take(_seritEnFazla - 1).toList() : ogeler;
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 3, 1, 3),
      child: Column(children: [
        for (final o in gosterilen) SizedBox(height: _seritSatiri, child: _TumGunChip(kontrol: kontrol, oge: o)),
        if (fazla > 0)
          SizedBox(
            height: _seritSatiri,
            child: Center(child: Text('+${fazla + 1}', style: Theme.of(context).textTheme.labelSmall)),
          ),
      ]),
    );
  }
}

class _TumGunChip extends StatelessWidget {
  const _TumGunChip({required this.kontrol, required this.oge});
  final TakvimKontrol kontrol;
  final TumGunOgesi oge;

  @override
  Widget build(BuildContext context) {
    final gorev = oge.gorev;
    final bitti = gorev?.done ?? false;
    final renk = bitti ? oge.renk.withValues(alpha: .45) : oge.renk;
    final yazi = yaziRengi(renk);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        label: '${M.tumGun}: ${oge.baslik}',
        child: Material(
          color: renk,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => gorev != null ? gorevEylemleri(context, kontrol, gorev) : etkinlikDetayGoster(context, kontrol, oge.ornek!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                if (gorev != null) Icon(bitti ? Icons.check_circle : Icons.radio_button_unchecked, size: 12, color: yazi),
                if (gorev != null) const SizedBox(width: 2),
                Expanded(
                  child: Text(oge.baslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: yazi, decoration: bitti ? TextDecoration.lineThrough : null)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _GunKolonu extends StatelessWidget {
  const _GunKolonu({required this.kontrol, required this.veri, required this.genislik});
  final TakvimKontrol kontrol;
  final GunVerisi veri;
  final double genislik;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bugunMu = veri.gun == kontrol.bugun;
    final simdi = kontrol.zaman.duvar(kontrol.simdi);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        // Boş saate dokunma: o gün, 30 dk'ya yuvarlanmış saatte yeni etkinlik.
        final dakika = ((d.localPosition.dy / saatYuksekligi * 60) / 30).floor() * 30;
        yeniEtkinlikAc(context, kontrol, baslangic: DateTime.utc(veri.gun.year, veri.gun.month, veri.gun.day, 0, dakika.clamp(0, 23 * 60 + 30)));
      },
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(child: CustomPaint(painter: _IzgaraCizici(tema.dividerColor.withValues(alpha: .6)))),
        for (final y in veri.saatli) _Blok(kontrol: kontrol, y: y, kolonGenisligi: genislik, gun: veri.gun),
        if (bugunMu)
          Positioned(
            top: (simdi.hour * 60 + simdi.minute) / 60 * saatYuksekligi - 1,
            left: 0,
            right: 0,
            child: ExcludeSemantics(
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: tema.colorScheme.error)),
                Expanded(child: Container(height: 2, color: tema.colorScheme.error)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _IzgaraCizici extends CustomPainter {
  _IzgaraCizici(this.renk);
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = renk
      ..strokeWidth = 1;
    for (var s = 0; s < 24; s++) {
      canvas.drawLine(Offset(0, s * saatYuksekligi), Offset(size.width, s * saatYuksekligi), p);
    }
    canvas.drawLine(Offset.zero, Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(_IzgaraCizici o) => o.renk != renk;
}

class _Blok extends StatelessWidget {
  const _Blok({required this.kontrol, required this.y, required this.kolonGenisligi, required this.gun});
  final TakvimKontrol kontrol;
  final YerlesimOgesi<SaatliParca> y;
  final double kolonGenisligi;
  final DateTime gun;

  @override
  Widget build(BuildContext context) {
    final p = y.oge;
    final basDk = p.bas.difference(gun).inMinutes;
    final bitDk = p.bit.difference(gun).inMinutes;
    final yukseklik = ((bitDk - basDk) / 60 * saatYuksekligi).clamp(22.0, double.infinity);
    final w = kolonGenisligi / y.kolonSayisi;
    final bitti = p.gorev?.done ?? false;
    final zemin = bitti ? p.renk.withValues(alpha: .5) : p.renk;
    final yazi = yaziRengi(zemin);
    final o = p.ornek;
    final saatler = M.saatAraligi(saatMetni(kontrol.zaman.duvar(o.start)), saatMetni(kontrol.zaman.duvar(o.end)));
    final takvimAdi = kontrol.veri.calendars[o.calendarUid]?.name ?? '';
    return Positioned(
      top: basDk / 60 * saatYuksekligi,
      left: y.kolon * w,
      width: w,
      height: yukseklik,
      child: Semantics(
        button: true,
        label: '${o.title}, $saatler, $takvimAdi',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(1, 0, 1, 1),
          child: Material(
            color: zemin,
            borderRadius: BorderRadius.vertical(top: Radius.circular(p.oncedenGelir ? 0 : 5), bottom: Radius.circular(p.sonrayaSurer ? 0 : 5)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => p.gorev != null ? gorevEylemleri(context, kontrol, p.gorev!) : etkinlikDetayGoster(context, kontrol, o),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (p.gorev != null) Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(bitti ? Icons.check_circle : Icons.radio_button_unchecked, size: 12, color: yazi),
                    ),
                    Expanded(
                      child: Text(o.title,
                          maxLines: yukseklik > 40 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: yazi, decoration: bitti ? TextDecoration.lineThrough : null)),
                    ),
                  ]),
                  if (yukseklik > 44 && w > 70)
                    Text(saatler, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: yazi.withValues(alpha: .85))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

