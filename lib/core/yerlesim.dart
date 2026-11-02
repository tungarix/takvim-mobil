// Çakışan etkinliklerin kolon yerleşimi (masaüstündeki core/layout.py'nin portu).
//
// Saf işlev: piksel yok. Çıktı (öge, kolon, kolonSayisi); arayüz genişliği
// 1/kolonSayisi, soldan uzaklığı kolon/kolonSayisi olarak hesaplar.
class YerlesimOgesi<T> {
  const YerlesimOgesi(this.oge, this.kolon, this.kolonSayisi);
  final T oge;
  final int kolon;
  final int kolonSayisi;
}

/// Bitişi başka etkinliğin başlangıcına eşit olanlar çakışmaz (10-11 ile 11-12
/// ayrı kümelerdir). Sıralama kararlı: aynı girdi hep aynı kolonları üretir,
/// yoksa ekran her çizimde titrer.
List<YerlesimOgesi<T>> yerlestir<T>(
  List<T> ogeler,
  DateTime Function(T) basla,
  DateTime Function(T) bitis, {
  int Function(T, T)? esitlikKirici,
}) {
  final sirali = [for (var i = 0; i < ogeler.length; i++) (i, ogeler[i])]..sort((a, b) {
      var c = basla(a.$2).compareTo(basla(b.$2));
      if (c != 0) return c;
      // Eşit başlangıçta uzun olan önce.
      c = bitis(b.$2).difference(basla(b.$2)).compareTo(bitis(a.$2).difference(basla(a.$2)));
      if (c != 0) return c;
      if (esitlikKirici != null) {
        c = esitlikKirici(a.$2, b.$2);
        if (c != 0) return c;
      }
      return a.$1.compareTo(b.$1);
    });

  final sonuc = <YerlesimOgesi<T>>[];
  var kume = <(T, int)>[];
  var kolonBitisleri = <DateTime>[];
  DateTime? kumeBitisi;

  void bosalt() {
    for (final (oge, kolon) in kume) {
      sonuc.add(YerlesimOgesi(oge, kolon, kolonBitisleri.length));
    }
  }

  for (final (_, oge) in sirali) {
    if (kumeBitisi != null && !basla(oge).isBefore(kumeBitisi)) {
      bosalt();
      kume = [];
      kolonBitisleri = [];
      kumeBitisi = null;
    }
    var kolon = kolonBitisleri.indexWhere((b) => !b.isAfter(basla(oge)));
    if (kolon < 0) {
      kolonBitisleri.add(bitis(oge));
      kolon = kolonBitisleri.length - 1;
    } else {
      kolonBitisleri[kolon] = bitis(oge);
    }
    kume.add((oge, kolon));
    final b = bitis(oge);
    kumeBitisi = kumeBitisi == null || b.isAfter(kumeBitisi) ? b : kumeBitisi;
  }
  bosalt();
  return sonuc;
}
