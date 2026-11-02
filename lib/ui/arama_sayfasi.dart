// Arama: başlık/açıklama/konum etkinlik + görev (masaüstü /api/search davranışı).
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/arama.dart';
import '../core/models.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'gorev_islemleri.dart';
import 'metin.dart';

Future<void> aramaAc(BuildContext context, TakvimKontrol k) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AramaSayfasi(kontrol: k)));

class AramaSayfasi extends StatefulWidget {
  const AramaSayfasi({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  State<AramaSayfasi> createState() => _AramaSayfasiDurumu();
}

class _AramaSayfasiDurumu extends State<AramaSayfasi> {
  final _c = TextEditingController();

  TakvimKontrol get k => widget.kontrol;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorgu = _c.text;
    final etkinlikler = etkinlikAra(k.veri, sorgu);
    final gorevler = gorevAra(k.veri, sorgu);
    final bos = sorgu.trim().isEmpty;
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: M.aramaIpucu, border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (!bos) IconButton(tooltip: M.kapat, icon: const Icon(Icons.clear), onPressed: () => setState(_c.clear)),
        ],
      ),
      body: bos
          ? const Center(child: Text(M.aramaBaslangic))
          : (etkinlikler.isEmpty && gorevler.isEmpty)
              ? const Center(child: Text(M.aramaBos))
              : ListView(children: [
                  if (etkinlikler.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(M.aramaEtkinlikler, style: tema.textTheme.titleSmall)),
                  for (final e in etkinlikler)
                    ListTile(
                      leading: Container(width: 14, height: 14, decoration: BoxDecoration(color: renkOku(k.veri.calendars[e.calendarUid]?.color ?? '#6b7280'), shape: BoxShape.circle)),
                      title: Text(e.title),
                      subtitle: Text(_etkinlikMetni(e)),
                      onTap: () {
                        final tz = e.allDay ? YerelZaman(e.tzid) : k.zaman;
                        Navigator.of(context).pop();
                        k.git(gunDuvar(tz.duvar(e.start)), gorunum: Gorunum.gun);
                      },
                    ),
                  if (gorevler.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(M.aramaGorevler, style: tema.textTheme.titleSmall)),
                  for (final g in gorevler)
                    ListTile(
                      leading: Icon(g.done ? Icons.check_circle : Icons.radio_button_unchecked),
                      title: Text(g.title, style: g.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                      subtitle: Text(gorevPlanMetni(k, g)),
                      onTap: () => gorevEylemleri(context, k, g),
                    ),
                ]),
    );
  }

  String _etkinlikMetni(Event e) {
    final tz = e.allDay ? YerelZaman(e.tzid) : k.zaman;
    final bas = tz.duvar(e.start);
    final tarih = '${gunBaglamli(gunDuvar(bas), k.bugun)} ${M.gunKisa[bas.weekday - 1]}';
    final saat = e.allDay ? M.tumGun : saatMetni(bas);
    return '$tarih · $saat${e.isRecurring ? ' · ${M.aramaTekrarli}' : ''}';
  }
}
