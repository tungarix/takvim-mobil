// Etkinlik ayrıntı sayfası, tekrarlı etkinlik kapsam sorusu, silme (geri alınabilir).
//
// Masaüstü kuralları: tekrarsız etkinlikte "bu örneği sil" KAYDI SİLER (AGENTS 49);
// tek örnek iptal/taşıma = override; "bu ve sonrakiler" = seri bölme (kural 57-58).
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import '../core/recurrence.dart';
import '../core/tekrar.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'etkinlik_formu.dart';
import 'metin.dart';

enum Kapsam { tumu, buOrnek, buVeSonrakiler }

/// Bu örnek serinin ilk örneği mi (ilkinden bölünemez: "bu ve sonrakiler" = tümü).
bool ilkOrnekMi(Event e, DateTime orijinalBaslangic) {
  final l = kuralBaslangiclari(e, e.start, orijinalBaslangic);
  return l.isEmpty || l.first == orijinalBaslangic;
}

Future<Kapsam?> kapsamSor(BuildContext context, {required bool silme, required bool ilkOrnek}) {
  return showDialog<Kapsam>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(silme ? M.kapsamSilBaslik : M.kapsamDuzenleBaslik),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(silme ? M.kapsamSilBilgi : M.kapsamDuzenleBilgi),
        ),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, Kapsam.buOrnek), child: const _SecenekMetni(M.kapsamBuOrnek)),
        if (!ilkOrnek) SimpleDialogOption(onPressed: () => Navigator.pop(c, Kapsam.buVeSonrakiler), child: const _SecenekMetni(M.kapsamBuVeSonrakiler)),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, Kapsam.tumu), child: const _SecenekMetni(M.kapsamTumu)),
      ],
    ),
  );
}

class _SecenekMetni extends StatelessWidget {
  const _SecenekMetni(this.metin);
  final String metin;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Align(alignment: Alignment.centerLeft, child: Text(metin, style: Theme.of(context).textTheme.titleMedium)),
      );
}

/// Yeni etkinlik formu; `baslangic` duvar saati (verilmezse odak günü, bir sonraki tam saat).
Future<void> yeniEtkinlikAc(BuildContext context, TakvimKontrol k, {DateTime? baslangic}) {
  if (k.takvimlerSirali.isEmpty) {
    k.mesaj(M.takvimYok);
    return Future.value();
  }
  var bas = baslangic;
  if (bas == null) {
    final g = k.odakGun;
    if (g == k.bugun) {
      final s = k.zaman.duvar(k.simdi);
      bas = DateTime.utc(g.year, g.month, g.day, s.hour + 1);
    } else {
      bas = DateTime.utc(g.year, g.month, g.day, 9);
    }
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => EtkinlikFormu(kontrol: k, baslangic: bas)));
}

/// Düzenleme: tekrarlıysa önce kapsam sorulur.
Future<void> etkinlikDuzenle(BuildContext context, TakvimKontrol k, Occurrence o) async {
  final e = k.veri.events[o.eventUid];
  if (e == null) return;
  var kapsam = Kapsam.tumu;
  if (o.recurring) {
    final s = await kapsamSor(context, silme: false, ilkOrnek: ilkOrnekMi(e, o.originalStart));
    if (s == null || !context.mounted) return;
    kapsam = s;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => EtkinlikFormu(kontrol: k, ornek: o, kapsam: kapsam)));
}

/// Silme: kapsam sor, uygula, tek adım geri alma sun. Başarılıysa true.
Future<bool> etkinlikSil(BuildContext context, TakvimKontrol k, Occurrence o) async {
  final e = k.veri.events[o.eventUid];
  if (e == null) return false;
  var kapsam = Kapsam.tumu;
  if (o.recurring) {
    final s = await kapsamSor(context, silme: true, ilkOrnek: ilkOrnekMi(e, o.originalStart));
    if (s == null) return false;
    kapsam = s;
  }
  final oncekiOv = e.overrides.where((x) => x.originalStart == o.originalStart).firstOrNull;
  final bool ok;
  final String mesaj;
  final Future<bool> Function() geri;
  switch (kapsam) {
    case Kapsam.buOrnek:
      ok = await k.yap((v) => v.cancelOccurrence(e.uid, o.originalStart));
      mesaj = M.ornekSilindi;
      geri = () => k.yap((v) => oncekiOv != null ? v.putOverride(e.uid, oncekiOv) : v.deleteOverride(e.uid, o.originalStart));
    case Kapsam.buVeSonrakiler:
      ok = await k.yap((v) => v.seriyiKes(e.uid, o.originalStart));
      mesaj = M.sonrakilerSilindi;
      geri = () => k.yap((v) => v.updateEvent(e));
    case Kapsam.tumu:
      ok = await k.yap((v) => v.deleteEvent(e.uid));
      mesaj = o.recurring ? M.seriSilindi : M.etkinlikSilindi(e.title);
      geri = () => k.yap((v) => v.addEvent(e));
  }
  if (ok) {
    k.mesaj(mesaj, eylem: M.geriAl, eylemFn: () async {
      if (await geri()) k.mesaj(M.geriAlindi);
    });
  }
  return ok;
}

/// "Her hafta (Pzt, Çar) · 10 kez" gibi tek satırlık özet.
String tekrarOzeti(Event e) {
  final tz = YerelZaman(e.tzid);
  final a = tekrarOku(e.rrule, baslangic: tz.duvar(e.start), loc: tz.loc);
  if (a == null) return M.tekrarlanir;
  var s = switch (a.tur) {
    TekrarTuru.yok => (e.rdate.isNotEmpty ? M.tekrarlanir : M.tekrarYok),
    TekrarTuru.gunluk => M.tekrarGunluk,
    TekrarTuru.haftalik => '${M.tekrarHaftalik} (${(a.gunler.toList()..sort()).map((g) => M.gunKisa[g - 1]).join(', ')})',
    TekrarTuru.aylik => M.tekrarAylik,
    TekrarTuru.yillik => M.tekrarYillik,
  };
  if (a.bitis == TekrarBitisi.sayi) s += ' · ${a.sayi} kez';
  if (a.bitis == TekrarBitisi.tarih && a.bitisGunu != null) s += ' · ${gunKisaMetin(a.bitisGunu!)} ${a.bitisGunu!.year}\'e kadar';
  return s;
}

Future<void> etkinlikDetayGoster(BuildContext context, TakvimKontrol k, Occurrence o) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _Detay(kontrol: k, ornek: o),
  );
}

class _Detay extends StatelessWidget {
  const _Detay({required this.kontrol, required this.ornek});
  final TakvimKontrol kontrol;
  final Occurrence ornek;

  String _zamanMetni() {
    final o = ornek;
    if (o.allDay) {
      final tz = YerelZaman(o.tzid);
      final bas = gunDuvar(tz.duvar(o.start));
      final son = gunEkle(gunDuvar(tz.duvar(o.end)), -1);
      return son.isAfter(bas) ? '${tarihTam(bas)} – ${tarihTam(son)}' : '${tarihTam(bas)} · ${M.tumGun}';
    }
    final z = kontrol.zaman;
    final bas = z.duvar(o.start), bit = z.duvar(o.end);
    final ayniGun = gunDuvar(bas) == gunDuvar(bit);
    return ayniGun
        ? '${tarihTam(bas)}\n${M.saatAraligi(saatMetni(bas), saatMetni(bit))}'
        : '${tarihTam(bas)} ${saatMetni(bas)}\n${tarihTam(bit)} ${saatMetni(bit)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final e = kontrol.veri.events[ornek.eventUid];
    final takvim = e == null ? null : kontrol.veri.calendars[e.calendarUid];
    Widget satir(IconData ikon, String metin) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ikon, size: 20, color: tema.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(metin)),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: renkOku(takvim?.color ?? '#6b7280'), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(takvim?.name ?? '', style: tema.textTheme.labelLarge),
          ]),
          const SizedBox(height: 8),
          Text(ornek.title, style: tema.textTheme.headlineSmall),
          satir(Icons.schedule, _zamanMetni()),
          if ((ornek.location ?? '').isNotEmpty) satir(Icons.place_outlined, ornek.location!),
          if ((ornek.description ?? '').isNotEmpty) satir(Icons.notes, ornek.description!),
          if (e != null && e.isRecurring) satir(Icons.repeat, tekrarOzeti(e)),
          if (e != null && e.reminders.isNotEmpty) satir(Icons.notifications_none, e.reminders.map(M.hatirlaticiMetni).join(', ')),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text(M.sil),
              onPressed: () async {
                final nav = Navigator.of(context);
                final k = kontrol;
                // Kapsam sorusu sayfa kapanmadan, aynı bağlamda sorulur.
                final ok = await etkinlikSil(context, k, ornek);
                if (ok && nav.mounted) nav.pop();
              },
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text(M.duzenle),
              onPressed: () async {
                final nav = Navigator.of(context);
                final k = kontrol;
                final o = ornek;
                nav.pop();
                // Sayfa kapandıktan sonra gezgin bağlamıyla forma geçilir.
                final ctx = k.navigatorAnahtari.currentContext;
                if (ctx != null && ctx.mounted) await etkinlikDuzenle(ctx, k, o);
              },
            ),
          ]),
        ]),
      ),
    );
  }
}
