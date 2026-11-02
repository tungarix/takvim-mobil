// Görev eylemleri: sayfa, düzenleme, güne/saate planlama, silme (geri alınabilir).
//
// Masaüstü kuralları: görev takvim etkinliği DEĞİL, saat blokta durur (AGENTS 67);
// saat planlı görevin gerçek saati bloğun override'ını da hesaba katar; saat planlama
// göreve bağlı bir blok (zaman bloğu etkinliği) açar, veri katmanı kuralları uygular.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import '../core/veri.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'metin.dart';

/// Saat planlı görevin geçerli saatleri (blok + olası taşıma override'ı); yoksa null.
({DateTime bas, DateTime bit})? gorevSaati(Veri v, Task t) {
  final b = t.eventUid == null ? null : v.events[t.eventUid];
  if (b == null) return null;
  final ov = b.overrides.where((o) => o.originalStart == b.start).firstOrNull;
  if (ov != null && ov.cancelled) return null;
  final bas = ov?.newStart ?? b.start;
  return (bas: bas, bit: ov?.newEnd ?? bas.add(b.duration));
}

/// Görevin planlandığı duvar günü (gün planı ya da blok saati), yoksa null.
DateTime? gorevGunu(TakvimKontrol k, Task t) {
  if (t.planDay != null) return gunOku(t.planDay!);
  final s = gorevSaati(k.veri, t);
  return s == null ? null : gunDuvar(k.zaman.duvar(s.bas));
}

String gorevPlanMetni(TakvimKontrol k, Task t) {
  final s = gorevSaati(k.veri, t);
  if (s != null) {
    final bas = k.zaman.duvar(s.bas), bit = k.zaman.duvar(s.bit);
    return '${planGunu(gunDuvar(bas), k.bugun)} ${M.saatAraligi(saatMetni(bas), saatMetni(bit))}';
  }
  if (t.planDay != null) return planGunu(gunOku(t.planDay!), k.bugun);
  return M.gorevPlansiz;
}

Future<void> gorevEylemleri(BuildContext context, TakvimKontrol k, Task t) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(gorevPlanMetni(k, t), style: Theme.of(c).textTheme.bodyMedium),
              if (t.notes != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.notes!)),
            ]),
          ),
          _Eylem(Icons.check_circle_outline, t.done ? M.gorevYenidenAc : M.gorevTamamla, () {
            Navigator.pop(c);
            gorevTamamla(k, t, !t.done);
          }),
          _Eylem(Icons.edit_outlined, M.duzenle, () {
            Navigator.pop(c);
            _sonra(k, (ctx) => gorevDuzenle(ctx, k, t));
          }),
          _Eylem(Icons.today, M.gorevBugunePlanla, () {
            Navigator.pop(c);
            k.yap((v) => v.planTaskDay(t.uid, gunAnahtari(k.bugun)));
          }),
          _Eylem(Icons.event, M.gorevGuneP, () {
            Navigator.pop(c);
            _sonra(k, (ctx) => gunPlanla(ctx, k, t));
          }),
          _Eylem(Icons.schedule, M.gorevSaateP, () {
            Navigator.pop(c);
            _sonra(k, (ctx) => saatPlanla(ctx, k, t));
          }),
          if (t.planDay != null || t.eventUid != null)
            _Eylem(Icons.event_busy, M.gorevPlaniKaldir, () {
              Navigator.pop(c);
              k.yap((v) => v.clearTaskPlan(t.uid));
            }),
          _Eylem(Icons.delete_outline, M.sil, () {
            Navigator.pop(c);
            gorevSil(k, t);
          }),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

/// Sayfa kapandıktan sonra gezgin bağlamıyla iş yapar (kapanan sayfanın bağlamı geçersiz).
void _sonra(TakvimKontrol k, Future<void> Function(BuildContext) is_) {
  final ctx = k.navigatorAnahtari.currentContext;
  if (ctx != null && ctx.mounted) is_(ctx);
}

class _Eylem extends StatelessWidget {
  const _Eylem(this.ikon, this.metin, this.onTap);
  final IconData ikon;
  final String metin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(ikon), title: Text(metin), onTap: onTap);
}

Future<bool> gorevTamamla(TakvimKontrol k, Task t, bool bitti) => k.yap((v) => v.setTaskDone(t.uid, bitti));

Future<void> gorevDuzenle(BuildContext context, TakvimKontrol k, Task t) async {
  final baslik = TextEditingController(text: t.title);
  final not = TextEditingController(text: t.notes ?? '');
  String? hata;
  final kaydet = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text(M.gorevDuzenleBaslik),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: baslik, autofocus: true, decoration: InputDecoration(labelText: M.baslik, errorText: hata)),
          const SizedBox(height: 8),
          TextField(controller: not, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: M.gorevNot)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(M.iptal)),
          FilledButton(
            onPressed: () {
              if (baslik.text.trim().isEmpty) {
                setS(() => hata = M.baslikGerekli);
                return;
              }
              Navigator.pop(c, true);
            },
            child: const Text(M.kaydet),
          ),
        ],
      ),
    ),
  );
  // Denetleyiciler dispose edilmez: kapanış animasyonu sürerken TextField hâlâ okur (dinleyicisi yok).
  final b = baslik.text.trim(), n = not.text;
  if (kaydet == true) await k.yap((v) => v.updateTask(t.uid, title: b, notes: n));
}

Future<void> gunPlanla(BuildContext context, TakvimKontrol k, Task t) async {
  final bas = gorevGunu(k, t) ?? k.bugun;
  final r = await showDatePicker(context: context, initialDate: DateTime(bas.year, bas.month, bas.day), firstDate: DateTime(2000), lastDate: DateTime(2100));
  if (r != null) await k.yap((v) => v.planTaskDay(t.uid, gunAnahtari(DateTime.utc(r.year, r.month, r.day))));
}

Future<void> saatPlanla(BuildContext context, TakvimKontrol k, Task t) async {
  final mevcut = gorevSaati(k.veri, t);
  final ilk = mevcut != null ? k.zaman.duvar(mevcut.bas) : DateTime.utc(k.bugun.year, k.bugun.month, k.bugun.day, k.zaman.duvar(k.simdi).hour + 1);
  final ilkSure = mevcut != null ? mevcut.bit.difference(mevcut.bas).inMinutes : 60;
  final sonuc = await showDialog<({DateTime bas, int sure})>(context: context, builder: (c) => _SaatPlanDialog(ilk: ilk, ilkSure: ilkSure));
  if (sonuc == null) return;
  final blokTakvim = t.eventUid == null ? null : k.veri.events[t.eventUid]?.calendarUid;
  final takvim = blokTakvim ?? k.varsayilanTakvim?.uid;
  if (takvim == null) {
    k.mesaj(M.takvimYok);
    return;
  }
  final bas = k.zaman.utc(sonuc.bas);
  await k.yap((v) => v.planTaskSlot(t.uid, bas, bas.add(Duration(minutes: sonuc.sure)), takvim, k.zaman.tzid));
}

class _SaatPlanDialog extends StatefulWidget {
  const _SaatPlanDialog({required this.ilk, required this.ilkSure});
  final DateTime ilk;
  final int ilkSure;
  @override
  State<_SaatPlanDialog> createState() => _SaatPlanDialogDurumu();
}

class _SaatPlanDialogDurumu extends State<_SaatPlanDialog> {
  late DateTime _bas = widget.ilk;
  late int _sure = widget.ilkSure;
  static const _sureler = [15, 30, 45, 60, 90, 120, 180, 240];

  @override
  Widget build(BuildContext context) {
    final sureler = {..._sureler, _sure}.toList()..sort();
    return AlertDialog(
      title: const Text(M.saatPlanBaslik),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          icon: const Icon(Icons.event),
          label: Text(tarihTam(_bas)),
          onPressed: () async {
            final r = await showDatePicker(context: context, initialDate: DateTime(_bas.year, _bas.month, _bas.day), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (r != null) setState(() => _bas = DateTime.utc(r.year, r.month, r.day, _bas.hour, _bas.minute));
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          icon: const Icon(Icons.schedule),
          label: Text(saatMetni(_bas)),
          onPressed: () async {
            final s = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: _bas.hour, minute: _bas.minute),
              builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
            );
            if (s != null) setState(() => _bas = DateTime.utc(_bas.year, _bas.month, _bas.day, s.hour, s.minute));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _sure,
          decoration: const InputDecoration(labelText: M.sure),
          items: [for (final s in sureler) DropdownMenuItem(value: s, child: Text(M.sureMetni(s)))],
          onChanged: (s) => setState(() => _sure = s ?? _sure),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(M.iptal)),
        FilledButton(onPressed: () => Navigator.pop(context, (bas: _bas, sure: _sure)), child: const Text(M.kaydet)),
      ],
    );
  }
}

/// Görevi (ve varsa bloğunu) siler; tek adım geri alma sunar.
Future<void> gorevSil(TakvimKontrol k, Task t) async {
  final blok = t.eventUid == null ? null : k.veri.events[t.eventUid];
  if (await k.yap((v) => v.deleteTask(t.uid))) {
    k.mesaj(M.gorevSilindi(t.title), eylem: M.geriAl, eylemFn: () async {
      if (await k.yap((v) => v.geriYukleGorev(t, blok: blok))) k.mesaj(M.geriAlindi);
    });
  }
}
