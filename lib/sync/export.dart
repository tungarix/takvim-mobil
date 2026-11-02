// Tam durum dışa aktarma (docs/senkron.md §1). Delta değil: dosya her zaman
// cihazın bütün takvim/etkinlik/görev/silinen kayıtlarını taşır.
import 'dart:convert';

import '../core/veri.dart';
import '../core/zaman.dart';
import '../surum.dart';

const syncFormat = 'takvim-sync';
const syncSurum = 1;
const uygulamaSurumu = 'mobile $surum';

class CihazBilgisi {
  const CihazBilgisi({required this.id, required this.name, this.app = uygulamaSurumu});
  final String id;
  final String name;
  final String app;
}

Map<String, dynamic> disaAktar(Veri veri, CihazBilgisi cihaz, {DateTime? simdi}) => {
      'format': syncFormat,
      'version': syncSurum,
      'created_at': utcYaz(simdi ?? veri.simdi),
      'device': {'id': cihaz.id, 'name': cihaz.name, 'app': cihaz.app},
      ...veri.toJson(),
    };

/// `.takvimsync` dosyasının UTF-8 JSON metni.
String disaAktarMetin(Veri veri, CihazBilgisi cihaz, {DateTime? simdi}) =>
    jsonEncode(disaAktar(veri, cihaz, simdi: simdi));
