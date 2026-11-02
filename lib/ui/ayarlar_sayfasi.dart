// Ayarlar sekmesi: takvimler, hatırlatıcı izinleri, masaüstü senkronu, hakkında.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import '../platform/bildirim.dart';
import '../surum.dart';
import 'bicim.dart';
import 'metin.dart';
import 'senkron_akisi.dart';

class AyarlarSayfasi extends StatelessWidget {
  const AyarlarSayfasi({super.key, required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kontrol,
      builder: (context, _) {
        final tema = Theme.of(context);
        Widget baslik(String s) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(s, style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.primary)),
            );
        final son = kontrol.ayarlar.sonSenkron;
        final sonMetin = son == null ? null : () {
          final w = kontrol.zaman.duvar(son);
          return '${tarihTam(w)} ${saatMetni(w)}';
        }();
        return Scaffold(
          appBar: AppBar(title: const Text(M.sekmeAyarlar)),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            baslik(M.takvimler),
            for (final c in kontrol.takvimlerSirali) _TakvimSatiri(kontrol: kontrol, takvim: c),
            ListTile(leading: const Icon(Icons.add), title: const Text(M.takvimEkle), onTap: () => takvimDialogu(context, kontrol)),
            baslik(M.hatirlaticiBolumu),
            _HatirlaticiBolumu(kontrol: kontrol),
            baslik(M.senkronBolumu),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text(M.senkronGonder),
              subtitle: const Text(M.senkronGonderAciklama),
              onTap: () => senkronGonderAkisi(kontrol),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text(M.senkronAc),
              subtitle: const Text(M.senkronAcAciklama),
              onTap: () => senkronAcAkisi(context, kontrol),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(M.sonSenkron(sonMetin)),
              subtitle: const Text(M.senkronYardim),
            ),
            baslik(M.hakkindaBolumu),
            ListTile(leading: const Icon(Icons.info_outline), title: const Text(M.uygulamaAdi), subtitle: Text(M.surum(surum))),
            const ListTile(leading: Icon(Icons.lock_outline), title: Text(M.verilerYalnizTelefonda)),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text(M.lisans),
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text(M.lisans),
                  content: const SingleChildScrollView(child: Text(M.lisansMetni)),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text(M.kapat))],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _TakvimSatiri extends StatelessWidget {
  const _TakvimSatiri({required this.kontrol, required this.takvim});
  final TakvimKontrol kontrol;
  final Calendar takvim;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(width: 20, height: 20, decoration: BoxDecoration(color: renkOku(takvim.color), shape: BoxShape.circle)),
      title: Text(takvim.name),
      trailing: Semantics(
        label: '${M.takvimGorunur}: ${takvim.name}',
        child: Switch(value: takvim.visible, onChanged: (b) => kontrol.yap((v) => v.updateCalendar(takvim.copyWith(visible: b)))),
      ),
      onTap: () => takvimDialogu(context, kontrol, takvim: takvim),
    );
  }
}

/// Takvim ekle / yeniden adlandır / renk / sil.
Future<void> takvimDialogu(BuildContext context, TakvimKontrol k, {Calendar? takvim}) async {
  final ad = TextEditingController(text: takvim?.name ?? '');
  var renk = takvim?.color ?? takvimRenkleri[k.veri.calendars.length % takvimRenkleri.length];
  String? hata;
  final sonuc = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(takvim == null ? M.takvimEkle : M.takvimDuzenle),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: ad, autofocus: true, decoration: InputDecoration(labelText: M.takvimAd, errorText: hata)),
            const SizedBox(height: 16),
            Text(M.takvimRenk, style: Theme.of(c).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in takvimRenkleri)
                Semantics(
                  button: true,
                  selected: h == renk,
                  label: '${M.takvimRenk} $h',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setS(() => renk = h),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: renkOku(h),
                          shape: BoxShape.circle,
                          border: h == renk ? Border.all(color: Theme.of(c).colorScheme.onSurface, width: 3) : null,
                        ),
                        child: h == renk ? Icon(Icons.check, size: 20, color: yaziRengi(renkOku(h))) : null,
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          if (takvim != null) TextButton(onPressed: () => Navigator.pop(c, 'sil'), child: Text(M.sil, style: TextStyle(color: Theme.of(c).colorScheme.error))),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text(M.iptal)),
          FilledButton(
            onPressed: () {
              final s = ad.text.trim();
              // Ad eşleşmesi senkronda takvim kimliğini bağlar: aynı adlı iki takvim karışıklık yaratır.
              if (s.isEmpty) {
                setS(() => hata = M.takvimAdBos);
              } else if (k.veri.calendars.values.any((x) => x.uid != takvim?.uid && x.name.toLowerCase() == s.toLowerCase())) {
                setS(() => hata = M.takvimAdVar);
              } else {
                Navigator.pop(c, 'kaydet');
              }
            },
            child: const Text(M.kaydet),
          ),
        ],
      ),
    ),
  );
  // ad.dispose() çağrılmaz: kapanış animasyonu sürerken TextField hâlâ onu okur (dinleyicisi yok, çöp toplanır).
  final yeniAd = ad.text.trim();
  if (sonuc == 'kaydet') {
    await k.yap((v) => takvim == null ? v.addCalendar(yeniAd, renk) : v.updateCalendar(takvim.copyWith(name: yeniAd, color: renk)));
  } else if (sonuc == 'sil' && takvim != null && context.mounted) {
    await _takvimSil(context, k, takvim);
  }
}

Future<void> _takvimSil(BuildContext context, TakvimKontrol k, Calendar takvim) async {
  // Son takvim silinemez (AGENTS 53): takvimsiz veride etkinlik eklenemez, kullanıcı çıkışsız kalır.
  if (k.veri.calendars.length <= 1) {
    k.mesaj(M.sonTakvimSilinemez);
    return;
  }
  final sayi = k.veri.events.values.where((e) => e.calendarUid == takvim.uid).length;
  final onay = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text(M.takvimSilBaslik),
      content: Text(M.takvimSilOnay(takvim.name, sayi)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(M.iptal)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, foregroundColor: Theme.of(c).colorScheme.onError),
          onPressed: () => Navigator.pop(c, true),
          child: const Text(M.sil),
        ),
      ],
    ),
  );
  if (onay == true && await k.yap((v) => v.deleteCalendar(takvim.uid))) k.mesaj(M.takvimSilindi(takvim.name));
}

class _HatirlaticiBolumu extends StatelessWidget {
  const _HatirlaticiBolumu({required this.kontrol});
  final TakvimKontrol kontrol;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BildirimDurumu>(
      valueListenable: kontrol.bildirim.durum,
      builder: (context, d, _) {
        final tema = Theme.of(context);
        Widget durumSatiri(String ad, bool? acik) => ListTile(
              leading: Icon(acik == true ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: acik == true ? null : tema.colorScheme.error),
              title: Text(ad),
              subtitle: Text(acik == true ? M.izinAcik : M.izinKapali),
              trailing: acik == true ? null : OutlinedButton(onPressed: () => kontrol.bildirim.izinIste().then((_) => kontrol.bildirimleriYenile()), child: const Text(M.izinVer)),
            );
        return Column(children: [
          durumSatiri(M.izinBildirim, d.bildirimIzni),
          durumSatiri(M.izinTamZamanli, d.tamZamanli),
          if (d.bildirimIzni == false)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(M.bildirimKapaliUyari, style: TextStyle(color: tema.colorScheme.error))),
          if (d.bildirimIzni != false && d.tamZamanli == false)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(M.tamZamanliUyari, style: TextStyle(color: tema.colorScheme.error))),
          if (d.hata != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(M.bildirimHatasi(d.hata!), style: TextStyle(color: tema.colorScheme.error))),
          ListTile(leading: const Icon(Icons.notifications_none), title: Text(M.planliBildirim(d.planli))),
        ]);
      },
    );
  }
}
