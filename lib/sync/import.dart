// İçe aktarma ve birleştirme (docs/senkron.md §2).
//
// Saf işlev: yerel durumu DEĞİŞTİRMEZ, birleşmiş yeni durumu ve raporu döndürür.
// Hata olursa (bozuk dosya, büyük sürüm) istisna fırlar ve çağıranın elinde
// hâlâ eski durum durur: "hiçbir şey değişmez" garantisi buradan gelir. Çağıran
// sonucu tek atomik yazmayla (store/) kalıcı kılar.
import 'dart:convert';

import '../core/models.dart';
import '../core/recurrence.dart';
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

final _renkDesen = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Hatırlatıcı en çok 10 yıl önce (masaüstüyle aynı sınır): fazlası `başlangıç - dakika` hesabında taşar.
const maksHatirlatici = 10 * 365 * 24 * 60;

/// Bir etkinlikte en çok override. Kaydırılmış her override her görünümde ayrıca kural açılımı
/// ister (`expand`); dosyadan gelen yüz binlercesi uygulamayı saniyelerce kilitlerdi.
const maksOverride = 5000;

/// Masaüstünün dosyayı reddettiği ama mobil modelinin sessizce kabul ettiği bozukluklar. Kabul
/// edilseydi mobilin kendi dışa aktarması masaüstünde TÜMÜYLE reddedilirdi. Yalnız içe aktarmada
/// denetlenir (depo açılışı gevşek kalır: telefondaki eski veri yüzünden uygulama açılmaz olmasın).
void _dogrula(Map<String, dynamic> j, Veri dosya) {
  void tekil(String ad, int ham, int ayristirilan) {
    if (ham != ayristirilan) throw BicimHatasi('$ad: aynı uid iki kez');
  }

  List<Object?> ham(String k) => j[k] as List<Object?>; // Veri.fromJson dizi olduğunu doğruladı
  tekil('calendars', ham('calendars').length, dosya.calendars.length);
  tekil('events', ham('events').length, dosya.events.length);
  tekil('tasks', ham('tasks').length, dosya.tasks.length);
  final hamOverride = ham('events').fold<int>(0, (n, e) => n + ((e as Map<String, dynamic>)['overrides'] as List<Object?>).length);
  final override = dosya.events.values.fold<int>(0, (n, e) => n + e.overrides.length);
  if (hamOverride != override) throw BicimHatasi('overrides: aynı örnek iki kez');
  for (final ev in dosya.events.values) {
    if (ev.overrides.length > maksOverride) {
      throw BicimHatasi('overrides: en çok $maksOverride olabilir (${ev.uid})');
    }
    if (ev.reminders.any((dk) => dk > maksHatirlatici)) {
      throw BicimHatasi('reminders: en çok $maksHatirlatici dakika (10 yıl) olabilir (${ev.uid})');
    }
    // Masaüstü Override.__post_init__ ile aynı: yalnız new_end verili, iptal değilse bitiş orijinal başlangıçtan önce olamaz.
    for (final o in ev.overrides) {
      if (!o.cancelled && o.newStart == null && o.newEnd != null && o.newEnd!.isBefore(o.originalStart)) {
        throw BicimHatasi('overrides: new_end_utc, original_start_utc\'den önce olamaz (${ev.uid})');
      }
    }
  }
  for (final c in dosya.calendars.values) {
    if (!_renkDesen.hasMatch(c.color)) throw BicimHatasi('color: #rrggbb bekleniyor (${c.name})');
  }
  for (final e in dosya.events.values.where((e) => e.rrule != null)) {
    if (kuralBozuk(e.rrule!, e.tzid)) throw BicimHatasi('rrule çözülemedi (${e.uid}): ${e.rrule}');
  }
  for (final e in dosya.events.values.where((e) => e.allDay)) {
    final loc = konumBul(e.tzid);
    for (final an in [e.start, e.end]) {
      final w = utcdenDuvar(loc, an);
      if (w.hour != 0 || w.minute != 0 || w.second != 0) {
        throw BicimHatasi('all_day etkinlikte başlangıç/bitiş yerel gece yarısı olmalı (${e.uid})');
      }
    }
  }
}

/// new_start verilip new_end verilmeyen override'ın bitişi etkinlik süresinden hesaplanıp yazılır
/// (masaüstü içe aktarmada ve Repo.put_override'da böyle; iki cihazın durumu aynı çıksın).
void _bitisleriTamamla(Veri dosya) {
  for (final e in dosya.events.values.toList()) {
    if (!e.overrides.any((o) => o.newStart != null && o.newEnd == null)) continue;
    dosya.events[e.uid] = e.copyWith(overrides: [
      for (final o in e.overrides)
        o.newStart != null && o.newEnd == null
            ? EventOverride(
                originalStart: o.originalStart, cancelled: o.cancelled, newStart: o.newStart,
                newEnd: o.newStart!.add(e.duration), newTitle: o.newTitle, newLocation: o.newLocation)
            : o,
    ]);
  }
}

/// `.takvimsync` metnini yerel durumla birleştirir. Aynı dosya ikinci kez
/// verilirse durum değişmez (idempotent).
ImportSonucu importEt(Veri yerel, String metin) {
  final j = _ayristir(metin);
  final dosya = Veri.fromJson(j, saat: yerel.saat); // bozuksa burada patlar, v'ye dokunulmadı
  _dogrula(j, dosya);
  _bitisleriTamamla(dosya);
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
    // Blok yerelde yoksa, blok olamayacak etkinlikse (tekrarlı/tüm gün) ya da başka bir görevin
    // bloğuysa görev plansıza döner (masaüstü `_blok_id` ile aynı);
    // updated_at dosyadaki değer kalır.
    final b = blok == null ? null : v.events[blok];
    if (blok != null && (b == null || b.isRecurring || b.allDay || v.tasks.values.any((t) => t.uid != ft.uid && t.eventUid == blok))) {
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
