// Görevler sekmesi: Bugün / Plansız / Planlı listeleri, satır içi ekleme, tamamlama.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import 'gorev_islemleri.dart';
import 'metin.dart';

class GorevlerSayfasi extends StatefulWidget {
  const GorevlerSayfasi({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  State<GorevlerSayfasi> createState() => _GorevlerSayfasiDurumu();
}

class _GorevlerSayfasiDurumu extends State<GorevlerSayfasi> {
  final _yeni = TextEditingController();
  final _odak = FocusNode();
  bool _bitenAcik = false;

  TakvimKontrol get k => widget.kontrol;

  @override
  void dispose() {
    _yeni.dispose();
    _odak.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final baslik = _yeni.text.trim();
    if (baslik.isEmpty) return;
    if (await k.yap((v) => v.addTask(baslik))) {
      _yeni.clear();
      _odak.requestFocus(); // art arda görev yazmak için odak kalır
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) {
        final bugun = k.bugun;
        final hepsi = k.veri.tasks.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final bugunL = <Task>[], plansiz = <Task>[], planli = <Task>[], biten = <Task>[];
        for (final t in hepsi) {
          if (t.done) {
            biten.add(t);
            continue;
          }
          final g = gorevGunu(k, t);
          if (g == null) {
            plansiz.add(t);
          } else if (g == bugun) {
            bugunL.add(t);
          } else {
            planli.add(t);
          }
        }
        planli.sort((a, b) {
          final c = gorevGunu(k, a)!.compareTo(gorevGunu(k, b)!);
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
        biten.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));

        Widget bolum(String baslik, List<Task> liste, {bool bosGoster = true}) {
          if (liste.isEmpty && !bosGoster) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('$baslik (${liste.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            if (liste.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(M.gorevBosBolum, style: Theme.of(context).textTheme.bodySmall)),
            for (final t in liste) _GorevSatiri(kontrol: k, gorev: t),
          ]);
        }

        return Scaffold(
          appBar: AppBar(title: const Text(M.sekmeGorevler)),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _yeni,
                    focusNode: _odak,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: M.gorevEkleIpucu, prefixIcon: Icon(Icons.add_task)),
                    onSubmitted: (_) => _ekle(),
                  ),
                ),
                IconButton(tooltip: M.gorevEkleAria, icon: const Icon(Icons.add_circle), iconSize: 32, onPressed: _ekle),
              ]),
            ),
            Expanded(
              child: hepsi.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(M.gorevBos, textAlign: TextAlign.center)))
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      bolum(M.gorevBugun, bugunL),
                      bolum(M.gorevPlansiz, plansiz),
                      bolum(M.gorevPlanli, planli),
                      if (biten.isNotEmpty) ...[
                        ListTile(
                          title: Text('${M.gorevTamamlanan} (${biten.length})'),
                          trailing: Icon(_bitenAcik ? Icons.expand_less : Icons.expand_more),
                          onTap: () => setState(() => _bitenAcik = !_bitenAcik),
                        ),
                        if (_bitenAcik) for (final t in biten) _GorevSatiri(kontrol: k, gorev: t),
                      ],
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

class _GorevSatiri extends StatelessWidget {
  const _GorevSatiri({required this.kontrol, required this.gorev});
  final TakvimKontrol kontrol;
  final Task gorev;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final g = gorevGunu(kontrol, gorev);
    final gecikmis = !gorev.done && g != null && g.isBefore(kontrol.bugun);
    final plan = gorevPlanMetni(kontrol, gorev);
    return ListTile(
      minVerticalPadding: 4,
      leading: Semantics(
        label: M.gorevKutuAria(gorev.title, gorev.done),
        child: Checkbox(value: gorev.done, onChanged: (b) => gorevTamamla(kontrol, gorev, b ?? false)),
      ),
      title: Text(gorev.title, style: gorev.done ? TextStyle(decoration: TextDecoration.lineThrough, color: tema.colorScheme.onSurfaceVariant) : null),
      subtitle: gorev.done && g == null
          ? null
          : Text(plan, style: gecikmis ? TextStyle(color: tema.colorScheme.error) : null),
      trailing: gorev.eventUid != null ? const Icon(Icons.schedule, size: 18) : null,
      onTap: () => gorevEylemleri(context, kontrol, gorev),
    );
  }
}
