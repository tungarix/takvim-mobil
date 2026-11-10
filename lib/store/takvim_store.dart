// Kalıcılık: tek JSON dosyası + bellekte Veri (shortcut: JSON dosya deposu,
// 50 bin+ etkinlikte SQLite'a geç).
//
// Yazma atomik: önce `.tmp`, doğrulanır, sonra `.tmp` -> asıl dosya rename'i
// (aynı dizinde atomik). Her yazmadan önce son sağlam hâl `.bak`'a kopyalanır.
// Açılışta asıl dosya bozuksa sırayla `.tmp` ve `.bak` denenir; bozuk dosya
// silinmez, `.bozuk-<zaman>` adıyla yanında saklanır. Hiçbiri okunamazsa boş
// veriyle BAŞLAMAYIZ (bir sonraki kayıt kullanıcı verisini ezerdi): hata fırlar.
import 'dart:convert';
import 'dart:io';

import '../core/veri.dart';
import '../core/zaman.dart';
import '../sync/export.dart';

const depoFormat = 'takvim-store';
const depoSurum = 1;

class BozukDepoHatasi implements Exception {
  BozukDepoHatasi(this.mesaj);
  final String mesaj;
  @override
  String toString() => 'BozukDepoHatasi: $mesaj';
}

class _Okunan {
  _Okunan(this.cihazId, this.cihazAdi, this.veri);
  final String cihazId;
  final String cihazAdi;
  final Veri veri;
}

_Okunan _coz(String metin, DateTime Function()? saat) {
  final Object? j;
  try {
    j = jsonDecode(metin);
  } on FormatException catch (e) {
    throw BicimHatasi('JSON okunamadı: ${e.message}');
  }
  if (j is! Map<String, dynamic> || j['format'] != depoFormat) throw BicimHatasi('depo dosyası değil');
  final s = j['version'];
  if (s is! int || s < 1) throw BicimHatasi('"version" geçersiz');
  if (s > depoSurum) throw SurumHatasi(s);
  final id = j['device_id'], ad = j['device_name'], veri = j['data'];
  if (id is! String || ad is! String || veri is! Map<String, dynamic>) throw BicimHatasi('depo alanları eksik');
  return _Okunan(id, ad, Veri.fromJson(veri, saat: saat));
}

class TakvimStore {
  TakvimStore._(this._dosya, this._cihazId, this.cihazAdi, this._veri, this._saat);

  final File _dosya;
  final String _cihazId;
  final DateTime Function()? _saat;
  Veri _veri;

  /// Senkron dosyasında görünen cihaz adı.
  String cihazAdi;

  /// Mevcut durum; DEĞİŞTİRME, `degistir`/`uygula` kullan (kayıt atomik olsun).
  Veri get veri => _veri;

  CihazBilgisi get cihaz => CihazBilgisi(id: _cihazId, name: cihazAdi);

  File get _tmp => File('${_dosya.path}.tmp');
  File get _bak => File('${_dosya.path}.bak');

  /// Depoyu açar; dosya yoksa boş durumla (yeni cihaz kimliğiyle) başlar.
  static Future<TakvimStore> ac(File dosya, {DateTime Function()? saat, String? cihazAdi}) async {
    final adaylar = [dosya, File('${dosya.path}.tmp'), File('${dosya.path}.bak')];
    var varOlan = false;
    _Okunan? okunan;
    final hatalar = <String>[];
    for (final f in adaylar) {
      if (!await f.exists()) continue;
      varOlan = true;
      try {
        okunan = _coz(await f.readAsString(), saat);
        break;
      } on BicimHatasi catch (e) {
        hatalar.add('${f.path}: ${e.mesaj}');
      } on SurumHatasi {
        rethrow; // yeni sürümün verisini "bozuk" sayıp ezmeyiz
      } on FileSystemException catch (e) {
        hatalar.add('${f.path}: ${e.message}');
      }
    }
    if (okunan == null) {
      if (varOlan) throw BozukDepoHatasi('depo okunamadı, hiçbir şey değiştirilmedi: ${hatalar.join('; ')}');
      return TakvimStore._(dosya, yeniUuid(), cihazAdi ?? 'Android', Veri(saat: saat), saat);
    }
    final depo = TakvimStore._(dosya, okunan.cihazId, okunan.cihazAdi, okunan.veri, saat);
    if (hatalar.isNotEmpty && await dosya.exists()) {
      // Asıl dosya bozuktu, yedekten döndük: bozuğu sakla, sağlam hâli geri yaz.
      await dosya.rename('${dosya.path}.bozuk-${DateTime.now().millisecondsSinceEpoch}');
      await depo._yaz(depo._veri);
    } else if (hatalar.isNotEmpty) {
      await depo._yaz(depo._veri);
    }
    return depo;
  }

  // Yazmalar sıraya girer: art arda iki çağrı aynı tabandan kopya alıp birbirinin
  // değişikliğini ezmesin, aynı .tmp dosyasına da birlikte yazmasın.
  Future<void> _sira = Future.value();

  Future<T> _sirala<T>(Future<T> Function() is_) {
    final c = _sira.then((_) => is_());
    _sira = c.then((_) {}, onError: (_) {}); // bir hata sonraki çağrıları zehirlemesin
    return c; // hata kendi çağırana gider
  }

  Future<void> _uygula(Veri yeni) async {
    await _yaz(yeni);
    _veri = yeni;
  }

  /// `degistir`in düz hâli: hazır bir durumu yazar; yazma başarısızsa bellek eskisi kalır.
  Future<void> uygula(Veri yeni) => _sirala(() => _uygula(yeni));

  /// Durumun kopyasında değişiklik yapar, kopyayı atomik yazar, sonra benimser.
  /// `f` ya da yazma hata verirse hem bellek hem dosya olduğu gibi kalır.
  /// Kopya sıranın İÇİNDE alınır: her çağrı önceki yazmanın sonucunu görür.
  Future<T> degistir<T>(T Function(Veri) f) => _sirala(() async {
        final kopya = _veri.kopya();
        final sonuc = f(kopya);
        await _uygula(kopya);
        return sonuc;
      });

  Future<void> _yaz(Veri v) async {
    final metin = jsonEncode({
      'format': depoFormat,
      'version': depoSurum,
      'device_id': _cihazId,
      'device_name': cihazAdi,
      'data': v.toJson(),
    });
    await _dosya.parent.create(recursive: true);
    await _tmp.writeAsString(metin, flush: true);
    _coz(await _tmp.readAsString(), _saat); // yarım/bozuk yazım asıl dosyaya geçmesin
    if (await _dosya.exists()) {
      try {
        _coz(await _dosya.readAsString(), _saat);
        await _dosya.copy(_bak.path); // yalnız sağlam hâl yedeğin üstüne yazılır
      } on BicimHatasi {
        // asıl dosya zaten bozuk: eski sağlam yedeğe dokunma
      }
    }
    await _tmp.rename(_dosya.path);
  }
}
