// İçe aktarma ve birleştirme (docs/senkron.md §2).
//
// Saf işlev: yerel durumu DEĞİŞTİRMEZ, birleşmiş yeni durumu ve raporu döndürür.
// Hata olursa (bozuk dosya, büyük sürüm) istisna fırlar ve çağıranın elinde
// hâlâ eski durum durur: "hiçbir şey değişmez" garantisi buradan gelir. Çağıran
// sonucu tek atomik yazmayla (store/) kalıcı kılar.
import 'dart:convert';

import '../core/veri.dart';
import '../core/zaman.dart';
import 'export.dart';

class TurSayaci {
  int added = 0, updated = 0, deleted = 0, skipped = 0;
  int get toplam => added + updated + deleted + skipped;
}

/// Sonuç raporu: toplamlar ve türe göre (takvim/etkinlik/görev) sayılar.
class ImportRaporu {
  final calendar = TurSayaci();
  final event = TurSayaci();
  final task = TurSayaci();

  int get added => calendar.added + event.added + task.added;
  int get updated => calendar.updated + event.updated + task.updated;
  int get deleted => calendar.deleted + event.deleted + task.deleted;
  int get skipped => calendar.skipped + event.skipped + task.skipped;
  bool get degisti => added + updated + deleted > 0;

  @override
  String toString() => '{added: $added, updated: $updated, deleted: $deleted, skipped: $skipped}';
}

class ImportSonucu {
  ImportSonucu(this.veri, this.rapor);
  final Veri veri;
  final ImportRaporu rapor;
}

String _ad(String s) => s.trim().toLowerCase();

Map<String, dynamic> _ayristir(String metin) {
  final Object? j;
  try {
    j = jsonDecode(metin.startsWith('﻿') ? metin.substring(1) : metin);
  } on FormatException catch (e) {
    throw BicimHatasi('JSON okunamadı: ${e.message}');
  }
  if (j is! Map<String, dynamic>) throw BicimHatasi('dosya bir JSON nesnesi olmalı');
  if (j['format'] != syncFormat) throw BicimHatasi('bu bir Takvim senkron dosyası değil');
  final s = j['version'];
  if (s is! int || s < 1) throw BicimHatasi('"version" pozitif tamsayı olmalı');
  if (s > syncSurum) throw SurumHatasi(s);
  return j;
}

/// `.takvimsync` metnini yerel durumla birleştirir. Aynı dosya ikinci kez
/// verilirse durum değişmez (idempotent).
ImportSonucu importEt(Veri yerel, String metin) {
  final dosya = Veri.fromJson(_ayristir(metin), saat: yerel.saat); // bozuksa burada patlar, v'ye dokunulmadı
  final v = yerel.kopya();
  final r = ImportRaporu();

  _takvimler(v, dosya, r);
  _etkinlikler(v, dosya, r);
  _gorevler(v, dosya, r);
  _silinenler(v, dosya, r);
  return ImportSonucu(v, r);
}

/// Dosyadaki canlı kayıt, yerel VEYA dosyanın kendi silme kaydından kesin ESKİYSE
/// canlanmaz (eklenip hemen silinmesin diye baştan elenir). Eşitlikte kayıt kalır/canlanır
/// (veri kaybetmemek için).
bool _silikKalir(Veri v, Veri dosya, String kind, String uid, DateTime guncelleme) {
  for (final m in [v.mezarlar['$kind:$uid'], dosya.mezarlar['$kind:$uid']]) {
    if (m != null && guncelleme.isBefore(m.deletedAt)) return true;
  }
  return false;
}

void _takvimler(Veri v, Veri dosya, ImportRaporu r) {
  final dosyaUidleri = dosya.calendars.keys.toSet();
  for (final fc in dosya.calendars.values) {
    final yerel = v.calendars[fc.uid];
    if (yerel != null) {
      if (fc.updatedAt.isAfter(yerel.updatedAt)) {
        v.calendars[fc.uid] = fc;
        r.calendar.updated++;
      }
      continue;
    }
    // Uid bulunamadı: aynı adlı yerel takvimin uid'ini dosyadakine çevirip benimse
    // (iki cihazda ayrı oluşturulan "Kişisel" ikilenmesin). Dosyanın kendi uid'leri
    // benimsenmez, yoksa iki dosya takvimi aynı yerel takvimi kapışırdı.
    final aday = v.calendars.values.where((c) => !dosyaUidleri.contains(c.uid) && _ad(c.name) == _ad(fc.name));
    if (aday.isNotEmpty) {
      final a = aday.first;
      v.calendars.remove(a.uid);
      for (final e in v.events.values.where((e) => e.calendarUid == a.uid).toList()) {
        v.events[e.uid] = e.copyWith(calendarUid: fc.uid);
      }
      v.calendars[fc.uid] = fc.updatedAt.isAfter(a.updatedAt) ? fc : a.copyWith(uid: fc.uid);
      r.calendar.updated++;
      continue;
    }
    if (_silikKalir(v, dosya, 'calendar', fc.uid, fc.updatedAt)) continue;
    v.calendars[fc.uid] = fc;
    v.mezarlar.remove('calendar:${fc.uid}');
    r.calendar.added++;
  }
}

void _etkinlikler(Veri v, Veri dosya, ImportRaporu r) {
  for (final fe in dosya.events.values) {
    final yerel = v.events[fe.uid];
    if (yerel != null && !fe.updatedAt.isAfter(yerel.updatedAt)) continue;
    if (yerel == null && _silikKalir(v, dosya, 'event', fe.uid, fe.updatedAt)) continue;
    // Yetim: takvimi yerelde yok (silinmiş). Eklenmez, "atlandı" sayılır.
    if (!v.calendars.containsKey(fe.calendarUid)) {
      r.event.skipped++;
      continue;
    }
    // Etkinlik tek birim: overrides + reminders onunla birlikte değişir.
    v.events[fe.uid] = fe;
    if (yerel == null) {
      v.mezarlar.remove('event:${fe.uid}');
      r.event.added++;
    } else {
      r.event.updated++;
    }
  }
}

void _gorevler(Veri v, Veri dosya, ImportRaporu r) {
  for (final ft in dosya.tasks.values) {
    final yerel = v.tasks[ft.uid];
    if (yerel != null && !ft.updatedAt.isAfter(yerel.updatedAt)) continue;
    if (yerel == null && _silikKalir(v, dosya, 'task', ft.uid, ft.updatedAt)) continue;

    var gelen = ft;
    final blok = ft.eventUid;
    // Blok yerelde yoksa (ya da başka bir görevin bloğuysa) görev plansıza döner;
    // updated_at dosyadaki değer kalır.
    if (blok != null && (!v.events.containsKey(blok) || v.tasks.values.any((t) => t.uid != ft.uid && t.eventUid == blok))) {
      gelen = ft.kopya(plan: (planDay: null, eventUid: null));
    }
    v.tasks[ft.uid] = gelen;
    if (yerel == null) {
      v.mezarlar.remove('task:${ft.uid}');
      r.task.added++;
    } else {
      r.task.updated++;
    }
  }
}

void _silinenler(Veri v, Veri dosya, ImportRaporu r) {
  for (final m in dosya.mezarlar.values) {
    final DateTime? guncelleme = switch (m.kind) {
      'calendar' => v.calendars[m.uid]?.updatedAt,
      'event' => v.events[m.uid]?.updatedAt,
      _ => v.tasks[m.uid]?.updatedAt,
    };
    if (guncelleme == null) {
      // Yerelde kayıt yok: mezar taşını (daha yeniyse) taşı ki silme üçüncü cihaza ulaşsın.
      final eski = v.mezarlar[m.anahtar];
      if (eski == null || m.deletedAt.isAfter(eski.deletedAt)) v.mezarlar[m.anahtar] = m;
    } else if (m.deletedAt.isAfter(guncelleme)) {
      // Silme kayıttan kesin yeni: uygula; mezar taşına dosyadaki an AYNEN yazılır.
      switch (m.kind) {
        case 'calendar':
          r.event.deleted += v.silTakvim(m.uid, m.deletedAt);
          r.calendar.deleted++;
        case 'event':
          v.silEtkinlik(m.uid, m.deletedAt);
          r.event.deleted++;
        default:
          v.silGorev(m.uid, m.deletedAt);
          r.task.deleted++;
      }
    } else {
      v.mezarlar.remove(m.anahtar); // kayıt kalır, varsa yerel silme izi kalkar
    }
  }
}
