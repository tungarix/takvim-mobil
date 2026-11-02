// Masaüstünün ürettiği örnek senkron dosyası ve onun açılım çıktısıyla uyum.
// Fixture'lar masaüstü deposundan KOPYALANIR (docs/senkron-ornek.takvimsync ve
// docs/senkron-ornek-olusumlar.json -> test/fixtures/). Yoksa test atlanır.
//
// Beklenen olusumlar.json biçimi: [{"pencere": [baslangic, bitis], "olusumlar":
// [{"uid", "start_utc", "end_utc", ...}]}] ya da {"pencere": ..., "olusumlar": ...}.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/core/veri.dart';
import 'package:takvim/sync/import.dart';

void main() {
  final sync = File('test/fixtures/senkron-ornek.takvimsync');
  final olusum = File('test/fixtures/senkron-ornek-olusumlar.json');
  final yok = !sync.existsSync() || !olusum.existsSync();

  test('masaüstü örnek dosyası içe aktarılır ve açılım JSON ile birebir eşleşir', () {
    final s = importEt(Veri(), sync.readAsStringSync());
    expect(s.rapor.skipped, 0, reason: 'örnek dosyada yetim kayıt beklenmez');

    final j = jsonDecode(olusum.readAsStringSync());
    final bloklar = j is List ? j : [j];
    for (final b in bloklar) {
      final p = (b['pencere'] as List<dynamic>).cast<String>();
      final beklenen = (b['olusumlar'] as List<dynamic>)
          .map((o) => '${o['uid'] ?? o['event_uid']}|${o['start_utc']}|${o['end_utc']}')
          .toList()
        ..sort();
      final gercek = s.veri
          .occurrences(utcOku(p[0]), utcOku(p[1]), includeHidden: true)
          .map((o) => '${o.eventUid}|${utcYaz(o.start)}|${utcYaz(o.end)}')
          .toList()
        ..sort();
      expect(gercek, beklenen, reason: 'pencere $p');
    }
  }, skip: yok ? 'masaüstü fixture\'ları henüz yok (test/fixtures/senkron-ornek*)' : false);
}
