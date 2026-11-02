// Küçük cihaz ayarları (görünüm, son senkron zamanı). Kullanıcı verisi DEĞİL:
// bozuksa varsayılana dönmek güvenli. Yazma atomik (tmp -> rename), hata fırlar.
import 'dart:convert';
import 'dart:io';

import '../core/zaman.dart';

class Ayarlar {
  Ayarlar._(this._dosya, this._m);

  final File _dosya;
  final Map<String, Object?> _m;

  static Future<Ayarlar> ac(File dosya) async {
    try {
      if (await dosya.exists()) {
        final j = jsonDecode(await dosya.readAsString());
        if (j is Map<String, dynamic>) return Ayarlar._(dosya, {...j});
      }
    } on FormatException {
      // bozuk ayar dosyası: varsayılanla başla, ilk yazma düzeltir
    }
    return Ayarlar._(dosya, {});
  }

  /// 'gun' | 'hafta' | 'ay'
  String get gorunum {
    final g = _m['gorunum'];
    return g == 'hafta' || g == 'ay' ? g as String : 'gun';
  }

  DateTime? get sonSenkron {
    final s = _m['son_senkron'];
    if (s is! String) return null;
    try {
      return utcOku(s);
    } on FormatException {
      return null;
    }
  }

  Future<void> gorunumYaz(String g) => _yaz({'gorunum': g});

  Future<void> sonSenkronYaz(DateTime an) => _yaz({'son_senkron': utcYaz(an)});

  // Yazmalar sıraya girer: art arda iki çağrı aynı .tmp dosyasını ezip birbirinin
  // anahtarını kaybettirmesin.
  Future<void> _kuyruk = Future.value();

  Future<void> _yaz(Map<String, Object?> degisen) {
    final is_ = _kuyruk.then((_) async {
      final yeni = {..._m, ...degisen};
      await _dosya.parent.create(recursive: true);
      final tmp = File('${_dosya.path}.tmp');
      await tmp.writeAsString(jsonEncode(yeni), flush: true);
      await tmp.rename(_dosya.path);
      _m
        ..clear()
        ..addAll(yeni);
    });
    // Bir yazmanın hatası sonrakileri engellemesin; hatayı yine çağıran görür.
    _kuyruk = is_.catchError((_) {});
    return is_;
  }
}
