// Gün/hafta görünümünün veri hazırlığı: örnekleri günlere böler, tüm gün şeridini
// ve saatli blokları ayırır, çakışanları kolonlara yerleştirir.
//
// Masaüstü kuralları: kırpma yerleşimden ÖNCE yapılır (gece yarısını aşan etkinlik
// her güne kırpılıp öyle yerleştirilir, AGENTS 15); saatsiz görev ızgarada görünmez
// ama GÜN planlı görev tüm gün şeridinde görünür.
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import '../core/recurrence.dart';
import '../core/yerel_zaman.dart';
import '../core/yerlesim.dart';
import 'bicim.dart';

/// Izgarada çizilen saatli blok; `bas`/`bit` o güne KIRPILMIŞ duvar saatidir.
class SaatliParca {
  const SaatliParca(this.ornek, this.bas, this.bit, this.renk, this.gorev, {required this.oncedenGelir, required this.sonrayaSurer});
  final Occurrence ornek;
  final DateTime bas;
  final DateTime bit;
  final Color renk;
  final Task? gorev; // saat planlı görev bloğuysa görevi
  final bool oncedenGelir;
  final bool sonrayaSurer;
}

/// Tüm gün şeridindeki öge: tüm gün etkinliği ya da gün planlı görev.
class TumGunOgesi {
  const TumGunOgesi({this.ornek, this.gorev, required this.baslik, required this.renk});
  final Occurrence? ornek;
  final Task? gorev;
  final String baslik;
  final Color renk;
}

class GunVerisi {
  const GunVerisi(this.gun, this.saatli, this.tumGun);
  final DateTime gun;
  final List<YerlesimOgesi<SaatliParca>> saatli;
  final List<TumGunOgesi> tumGun;
}

Color takvimRengi(TakvimKontrol k, String calendarUid) => renkOku(k.veri.calendars[calendarUid]?.color ?? '#6b7280');

/// `gunler` ardışık olmak zorunda değil ama sıralı beklenir.
List<GunVerisi> gunVerileri(TakvimKontrol k, List<DateTime> gunler) {
  final z = k.zaman;
  final v = k.veri;
  const pay = Duration(days: 1); // tüm gün etkinlikleri kendi saat diliminde: pencere geniş tutulur
  final ornekler = v.occurrences(z.gunBasiUtc(gunler.first).subtract(pay), z.gunBasiUtc(gunEkle(gunler.last, 1)).add(pay));
  final blokGorev = {for (final t in v.tasks.values) if (t.eventUid != null) t.eventUid!: t};
  final tzler = <String, YerelZaman>{};
  YerelZaman tzDe(String id) => tzler.putIfAbsent(id, () => YerelZaman(id));

  return [
    for (final d in gunler)
      () {
        final sonraki = gunEkle(d, 1);
        final tumGun = <TumGunOgesi>[];
        final parcalar = <SaatliParca>[];
        for (final o in ornekler) {
          final renk = takvimRengi(k, o.calendarUid);
          if (o.allDay) {
            final tz = tzDe(o.tzid);
            final bas = gunDuvar(tz.duvar(o.start)), bit = gunDuvar(tz.duvar(o.end)); // bitiş dışlayıcı
            if (!d.isBefore(bas) && d.isBefore(bit)) tumGun.add(TumGunOgesi(ornek: o, baslik: o.title, renk: renk));
            continue;
          }
          final ws = z.duvar(o.start), we = z.duvar(o.end);
          if (!we.isAfter(d) || !ws.isBefore(sonraki)) continue;
          parcalar.add(SaatliParca(
            o,
            ws.isBefore(d) ? d : ws,
            we.isAfter(sonraki) ? sonraki : we,
            renk,
            blokGorev[o.eventUid],
            oncedenGelir: ws.isBefore(d),
            sonrayaSurer: we.isAfter(sonraki),
          ));
        }
        final anahtar = gunAnahtari(d);
        for (final t in v.tasks.values) {
          if (t.planDay == anahtar) tumGun.add(TumGunOgesi(gorev: t, baslik: t.title, renk: const Color(0xFF64748B)));
        }
        return GunVerisi(
          d,
          yerlestir<SaatliParca>(parcalar, (p) => p.bas, (p) => p.bit, esitlikKirici: (a, b) => a.ornek.eventUid.compareTo(b.ornek.eventUid)),
          tumGun,
        );
      }(),
  ];
}
