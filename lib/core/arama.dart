// Arama (masaüstü /api/search davranışı, AGENTS kural 20 ve 81).
//
// Katlama dilbilimsel Türkçe küçültme DEĞİLDİR: I ailesi (I/İ/ı/i) tek harfe
// iner ve şapkalılar düzlenir; "ALGORITMA" yazan "Algoritma"yı, "carsamba"
// "Çarşamba"yı bulur. Arama niyet eşleştirir, dil kuralı uygulamaz.
import 'models.dart';
import 'veri.dart';

const _katlama = {
  'I': 'i', 'İ': 'i', 'ı': 'i',
  'Ş': 's', 'ş': 's',
  'Ğ': 'g', 'ğ': 'g',
  'Ç': 'c', 'ç': 'c',
  'Ö': 'o', 'ö': 'o',
  'Ü': 'u', 'ü': 'u',
};

String aramaAnahtari(String metin) {
  final b = StringBuffer();
  for (final r in metin.runes) {
    final h = String.fromCharCode(r);
    b.write(_katlama[h] ?? h);
  }
  return b.toString().toLowerCase();
}

/// Başlık, açıklama ve konumda geçen etkinlikler (başlangıca göre sıralı).
/// Saat planlı görevin bloğu ayıklanır: görev sonuçlarında zaten çıkıyor.
List<Event> etkinlikAra(Veri v, String sorgu, {int limit = 50}) {
  final anahtar = aramaAnahtari(sorgu).trim();
  if (anahtar.isEmpty) return [];
  final bloklar = {for (final t in v.tasks.values) if (t.eventUid != null) t.eventUid!};
  final adaylar = v.events.values.where((e) => !bloklar.contains(e.uid)).toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.uid.compareTo(b.uid);
    });
  final out = <Event>[];
  for (final e in adaylar) {
    final havuz = [e.title, e.description, e.location].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    if (aramaAnahtari(havuz).contains(anahtar)) {
      out.add(e);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// Başlığında ya da notunda geçen görevler (tamamlananlar dahil), eklenme sırasıyla.
List<Task> gorevAra(Veri v, String sorgu, {int limit = 50}) {
  final anahtar = aramaAnahtari(sorgu).trim();
  if (anahtar.isEmpty) return [];
  final adaylar = v.tasks.values.toList()
    ..sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.uid.compareTo(b.uid);
    });
  final out = <Task>[];
  for (final g in adaylar) {
    final havuz = [g.title, g.notes].whereType<String>().join(' ');
    if (aramaAnahtari(havuz).contains(anahtar)) {
      out.add(g);
      if (out.length >= limit) break;
    }
  }
  return out;
}
