// Takvim sekmesi: gün/hafta/ay arasında geçiş, kaydırarak önceki/sonraki, Bugün düğmesi.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/yerel_zaman.dart';
import 'arama_sayfasi.dart';
import 'ay_gorunumu.dart';
import 'bicim.dart';
import 'metin.dart';
import 'saat_izgarasi.dart';

const _merkez = 5000;

/// Telefon eşiği: altında hafta görünümü 3 kolon gösterip yatay kaydırılır.
const telefonEsigi = 600.0;

class TakvimSayfasi extends StatefulWidget {
  const TakvimSayfasi({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  State<TakvimSayfasi> createState() => _TakvimSayfasiDurumu();
}

class _TakvimSayfasiDurumu extends State<TakvimSayfasi> {
  late final DateTime _baz = widget.kontrol.bugun;
  PageController? _pc;
  Gorunum? _pcGorunum;

  TakvimKontrol get k => widget.kontrol;

  DateTime _sayfaGunu(Gorunum g, int sayfa) {
    final n = sayfa - _merkez;
    return switch (g) {
      Gorunum.gun => gunEkle(_baz, n),
      Gorunum.hafta => gunEkle(haftaBasi(_baz), 7 * n),
      Gorunum.ay => DateTime.utc(_baz.year, _baz.month + n, 1),
    };
  }

  int _sayfaNo(Gorunum g, DateTime gun) => _merkez +
      switch (g) {
        Gorunum.gun => gun.difference(_baz).inDays,
        Gorunum.hafta => haftaBasi(gun).difference(haftaBasi(_baz)).inDays ~/ 7,
        Gorunum.ay => (gun.year - _baz.year) * 12 + gun.month - _baz.month,
      };

  /// Kaydırınca yeni odak günü: hafta/ayda mümkünse aynı hafta günü / ay günü korunur.
  DateTime _yeniOdak(Gorunum g, int sayfa) {
    final s = _sayfaGunu(g, sayfa);
    return switch (g) {
      Gorunum.gun => s,
      Gorunum.hafta => gunEkle(s, k.odakGun.weekday - 1),
      Gorunum.ay => () {
          final son = DateTime.utc(s.year, s.month + 1, 0).day;
          return DateTime.utc(s.year, s.month, k.odakGun.day > son ? son : k.odakGun.day);
        }(),
    };
  }

  PageController _denetleyici(Gorunum g) {
    if (_pc == null || _pcGorunum != g) {
      _pc?.dispose();
      _pc = PageController(initialPage: _sayfaNo(g, k.odakGun));
      _pcGorunum = g;
    }
    return _pc!;
  }

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  void _adim(int yon) {
    final g = k.gorunum;
    k.odakAyarla(switch (g) {
      Gorunum.gun => gunEkle(k.odakGun, yon),
      Gorunum.hafta => gunEkle(k.odakGun, 7 * yon),
      Gorunum.ay => DateTime.utc(k.odakGun.year, k.odakGun.month + yon, 1),
    });
  }

  String _baslik() {
    final d = k.odakGun;
    final bugun = k.bugun;
    switch (k.gorunum) {
      case Gorunum.gun:
        return d.year == bugun.year ? gunUzun(d) : tarihTam(d);
      case Gorunum.hafta:
        final b = haftaBasi(d), s = gunEkle(b, 6);
        final ay = b.month == s.month ? '${b.day}' : gunKisaMetin(b);
        return '$ay – ${gunKisaMetin(s)} ${s.year}';
      case Gorunum.ay:
        return ayYil(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) {
        final g = k.gorunum;
        final dar = MediaQuery.sizeOf(context).width < telefonEsigi;
        return Scaffold(
          appBar: AppBar(
            title: Text(_baslik()),
            actions: [
              IconButton(tooltip: M.ara, icon: const Icon(Icons.search), onPressed: () => aramaAc(context, k)),
              IconButton(tooltip: M.bugun, icon: const Icon(Icons.today), onPressed: () => k.odakAyarla(k.bugun)),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(children: [
                Expanded(
                  child: SegmentedButton<Gorunum>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact, minimumSize: WidgetStatePropertyAll(Size(0, 48))),
                    segments: const [
                      ButtonSegment(value: Gorunum.gun, label: Text(M.gorunumGun)),
                      ButtonSegment(value: Gorunum.hafta, label: Text(M.gorunumHafta)),
                      ButtonSegment(value: Gorunum.ay, label: Text(M.gorunumAy)),
                    ],
                    selected: {g},
                    onSelectionChanged: (s) => k.gorunumDegistir(s.first),
                  ),
                ),
                IconButton(tooltip: M.onceki, icon: const Icon(Icons.chevron_left), onPressed: () => _adim(-1)),
                IconButton(tooltip: M.sonraki, icon: const Icon(Icons.chevron_right), onPressed: () => _adim(1)),
              ]),
            ),
            Expanded(child: _icerik(g, dar, MediaQuery.sizeOf(context).width)),
          ]),
        );
      },
    );
  }

  Widget _icerik(Gorunum g, bool dar, double genislik) {
    // Telefonda hafta: kolonlar yatay kaydırıldığı için sayfa kaydırma yok, oklarla gezilir.
    if (g == Gorunum.hafta && dar) {
      final b = haftaBasi(k.odakGun);
      return SaatIzgarasi(
        key: ValueKey('hafta-$b'),
        kontrol: k,
        gunler: [for (var i = 0; i < 7; i++) gunEkle(b, i)],
        kolonGenisligi: (genislik - etiketGenisligi) / 3,
      );
    }
    final pc = _denetleyici(g);
    final hedef = _sayfaNo(g, k.odakGun);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !pc.hasClients || _pc != pc) return;
      final p = pc.page;
      if (p == null || p.round() == hedef) return;
      (p - hedef).abs() <= 1 ? pc.animateToPage(hedef, duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : pc.jumpToPage(hedef);
    });
    return PageView.builder(
      controller: pc,
      onPageChanged: (s) => k.odakAyarla(_yeniOdak(g, s)),
      itemBuilder: (context, sayfa) {
        final gun = _sayfaGunu(g, sayfa);
        return switch (g) {
          Gorunum.gun => SaatIzgarasi(key: ValueKey('gun-$gun'), kontrol: k, gunler: [gun]),
          Gorunum.hafta => SaatIzgarasi(key: ValueKey('hafta-$gun'), kontrol: k, gunler: [for (var i = 0; i < 7; i++) gunEkle(gun, i)]),
          Gorunum.ay => AyGorunumu(key: ValueKey('ay-$gun'), kontrol: k, ay: gun),
        };
      },
    );
  }
}
