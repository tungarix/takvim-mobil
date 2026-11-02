// Formdaki tekrar seçeneği <-> RRULE metni (saf Dart).
//
// Masaüstü gibi KAPALI bir küme sunar (AGENTS kural 50): yok / her gün / her
// hafta (+ gün seçimi) / her ay / her yıl, bitiş: hiç / tarih / n kez. Bunun
// dışındaki kurallar (INTERVAL, BYMONTHDAY...) `tekrarOku`dan null döner; form
// onları "özel" gösterip olduğu gibi korur, sessizce değiştirmez.
import 'package:timezone/timezone.dart' as tz;

import 'zaman.dart';

enum TekrarTuru { yok, gunluk, haftalik, aylik, yillik }

enum TekrarBitisi { hic, tarih, sayi }

class TekrarAyari {
  const TekrarAyari({
    this.tur = TekrarTuru.yok,
    this.gunler = const {},
    this.bitis = TekrarBitisi.hic,
    this.bitisGunu,
    this.sayi = 10,
  });

  final TekrarTuru tur;

  /// Haftalıkta seçili günler, DateTime.weekday (1=Pazartesi .. 7=Pazar).
  final Set<int> gunler;
  final TekrarBitisi bitis;

  /// Duvar günü (00:00, sahte UTC); bitiş günü DAHİL.
  final DateTime? bitisGunu;
  final int sayi;

  TekrarAyari kopya({TekrarTuru? tur, Set<int>? gunler, TekrarBitisi? bitis, DateTime? bitisGunu, int? sayi}) => TekrarAyari(
        tur: tur ?? this.tur,
        gunler: gunler ?? this.gunler,
        bitis: bitis ?? this.bitis,
        bitisGunu: bitisGunu ?? this.bitisGunu,
        sayi: sayi ?? this.sayi,
      );
}

const _gunKodlari = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _iki(int n) => n.toString().padLeft(2, '0');

/// Ayardan RRULE gövdesi (öneksiz); tekrar yoksa null. `baslangic` etkinliğin
/// duvar başlangıcı, `loc` etkinliğin saat dilimi (UNTIL günün sonuna göre UTC'ye çevrilir).
String? tekrarYaz(TekrarAyari a, {required DateTime baslangic, required tz.Location loc}) {
  final freq = switch (a.tur) {
    TekrarTuru.yok => null,
    TekrarTuru.gunluk => 'DAILY',
    TekrarTuru.haftalik => 'WEEKLY',
    TekrarTuru.aylik => 'MONTHLY',
    TekrarTuru.yillik => 'YEARLY',
  };
  if (freq == null) return null;
  final parcalar = ['FREQ=$freq'];
  if (a.tur == TekrarTuru.haftalik && a.gunler.isNotEmpty && !(a.gunler.length == 1 && a.gunler.first == baslangic.weekday)) {
    final sirali = a.gunler.toList()..sort();
    parcalar.add('BYDAY=${sirali.map((g) => _gunKodlari[g - 1]).join(',')}');
  }
  switch (a.bitis) {
    case TekrarBitisi.hic:
      break;
    case TekrarBitisi.sayi:
      parcalar.add('COUNT=${a.sayi < 1 ? 1 : a.sayi}');
    case TekrarBitisi.tarih:
      final g = a.bitisGunu ?? baslangic;
      final u = duvardanUtc(loc, DateTime.utc(g.year, g.month, g.day, 23, 59, 59));
      parcalar.add('UNTIL=${u.year.toString().padLeft(4, '0')}${_iki(u.month)}${_iki(u.day)}T${_iki(u.hour)}${_iki(u.minute)}${_iki(u.second)}Z');
  }
  return parcalar.join(';');
}

/// RRULE metnini forma çevirir; formun ifade edemediği (özel) kural için null.
/// Kural yoksa (null/boş) `TekrarTuru.yok` ayarı döner.
TekrarAyari? tekrarOku(String? rrule, {required DateTime baslangic, required tz.Location loc}) {
  if (rrule == null || rrule.trim().isEmpty) return const TekrarAyari();
  final satirlar = rrule.split(RegExp(r'[\r\n]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (satirlar.length != 1) return null;
  var govde = satirlar.first;
  if (govde.toUpperCase().startsWith('RRULE:')) govde = govde.substring(6);
  final alanlar = <String, String>{};
  for (final p in govde.split(';')) {
    final i = p.indexOf('=');
    if (i <= 0) return null;
    alanlar[p.substring(0, i).toUpperCase()] = p.substring(i + 1);
  }
  const izinli = {'FREQ', 'BYDAY', 'COUNT', 'UNTIL'};
  if (!alanlar.keys.every(izinli.contains)) return null;
  final tur = switch (alanlar['FREQ']?.toUpperCase()) {
    'DAILY' => TekrarTuru.gunluk,
    'WEEKLY' => TekrarTuru.haftalik,
    'MONTHLY' => TekrarTuru.aylik,
    'YEARLY' => TekrarTuru.yillik,
    _ => null,
  };
  if (tur == null) return null;
  var gunler = <int>{};
  final byday = alanlar['BYDAY'];
  if (byday != null) {
    if (tur != TekrarTuru.haftalik) return null;
    for (final k in byday.toUpperCase().split(',')) {
      final i = _gunKodlari.indexOf(k);
      if (i < 0) return null;
      gunler.add(i + 1);
    }
  } else if (tur == TekrarTuru.haftalik) {
    gunler = {baslangic.weekday};
  }
  if (alanlar.containsKey('COUNT') && alanlar.containsKey('UNTIL')) return null;
  if (alanlar.containsKey('COUNT')) {
    final n = int.tryParse(alanlar['COUNT']!);
    if (n == null || n < 1) return null;
    return TekrarAyari(tur: tur, gunler: gunler, bitis: TekrarBitisi.sayi, sayi: n);
  }
  if (alanlar.containsKey('UNTIL')) {
    final ham = alanlar['UNTIL']!.toUpperCase();
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$').firstMatch(ham);
    if (m == null) return null;
    var gun = DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    if (m.group(7) == 'Z') {
      final u = DateTime.utc(gun.year, gun.month, gun.day, int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
      final w = utcdenDuvar(loc, u);
      gun = DateTime.utc(w.year, w.month, w.day);
    }
    return TekrarAyari(tur: tur, gunler: gunler, bitis: TekrarBitisi.tarih, bitisGunu: gun);
  }
  return TekrarAyari(tur: tur, gunler: gunler);
}
