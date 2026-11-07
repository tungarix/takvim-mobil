// Wi-Fi eşleştirme istemcisi (takvim/docs/senkron-wifi.md §3, §4): sabitlenmiş sertifikalı HTTPS.
//
// Saf Dart (dart:io). Güven modeli: sistem güven deposu YOK; sunucu sertifikası kendi imzalı olduğundan
// her bağlantıda doğrulama "başarısız" olur ve `badCertificateCallback` çağrılır; o yalnız sunulan
// sertifikanın DER SHA-256'sı QR'daki `f` ile eşleşirse true döner. Başka hiçbir durumda güvenilmez.
// Token yalnız `Authorization` başlığında gider; hata iletilerine ve günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sha256.dart';
import 'wifi_baglanti.dart';

// Testler ve eski çağrı yerleri `sha256`yı buradan alıyor.
export 'sha256.dart' show sha256;

const wifiGetEnFazlaBayt = 16 * 1024 * 1024;
const _durumGovdeSiniri = 64 * 1024; // hello ve hata gövdeleri
const _raporSiniri = 1024 * 1024; // POST yanıtı

enum WifiHataTuru {
  ozelOlmayanAdres,
  ulasilamadi,
  sureDoldu,
  tlsKurulamadi,
  parmakIzi,
  yetkisiz,
  reddedildi,
  masaustuSuresiDoldu,
  surum,
  gecersizDosya,
  cokBuyuk,
  beklenmeyen,
  iptal,
}

class WifiHatasi implements Exception {
  const WifiHatasi(this.tur, [this.ayrinti = '']);
  final WifiHataTuru tur;

  /// Kısa teknik ayrıntı (token içermez); kullanıcıya yalnız ek bilgi olarak gösterilir.
  final String ayrinti;

  @override
  String toString() => 'WifiHatasi($tur${ayrinti.isEmpty ? '' : ', $ayrinti'})';
}

class WifiHello {
  const WifiHello({required this.ad, required this.uygulama});
  final String ad;
  final String uygulama;
}

/// Masaüstünün birleştirme raporu (POST /v1/state yanıtı).
class WifiRapor {
  const WifiRapor({this.added = 0, this.updated = 0, this.deleted = 0, this.skipped = 0});
  final int added, updated, deleted, skipped;

  /// `{"added":..,"updated":..,"deleted":..,"skipped":..}`: her alan düz sayı YA DA tür bazlı nesne
  /// (masaüstü `senkron/ice.py`: `{"calendar":n,"event":n,"task":n}`; değerler toplanır). Eksik, negatif,
  /// bozuk ya da bilinmeyen alan güvenle 0 sayılır; ayrıştırma hiçbir zaman hata fırlatmaz.
  factory WifiRapor.jsondan(Object? j) {
    if (j is! Map) return const WifiRapor();
    int n(Object? v) {
      if (v is int) return v < 0 ? 0 : v;
      if (v is Map) return v.values.whereType<int>().fold(0, (a, b) => b < 0 ? a : a + b);
      return 0;
    }

    return WifiRapor(added: n(j['added']), updated: n(j['updated']), deleted: n(j['deleted']), skipped: n(j['skipped']));
  }
}

/// Arayüzün konuştuğu soyutlama (testlerde sahtesi var).
abstract class WifiOturum {
  Future<WifiHello> hello();

  /// Masaüstünün tam durumu: `.takvimsync` JSON metni.
  Future<String> durumAl();

  /// Telefonun tam durumunu gönderir; masaüstü onayı bekler.
  Future<WifiRapor> durumGonder(String metin);

  /// Süren isteği keser ve oturumu kapatır (kullanıcı vazgeçti ya da iş bitti).
  void kapat();
}

class WifiIstemci implements WifiOturum {
  /// `adresIzinli`: bağlanmadan önce hedefin özel IP olduğunu bir kez daha denetler (ayrıştırıcıdan
  /// bağımsız ikinci kapı); yalnız testler loopback için değiştirir.
  WifiIstemci(
    this.baglanti, {
    this.adresIzinli = ozelIpv4mi,
    this.baglanmaSuresi = const Duration(seconds: 10),
    this.getSuresi = const Duration(seconds: 30),
    this.postSuresi = const Duration(seconds: 90),
    this.getEnFazlaBayt = wifiGetEnFazlaBayt,
  });

  /// Varsayılan üretici (arayüz bunu kullanır).
  static WifiOturum yeni(WifiBaglanti b) => WifiIstemci(b);

  final WifiBaglanti baglanti;
  final bool Function(String ip) adresIzinli;
  final Duration baglanmaSuresi, getSuresi, postSuresi;
  final int getEnFazlaBayt;

  HttpClient? _istemci;
  bool _kapali = false;
  bool _uyusmadi = false;

  HttpClient _istemciAl() {
    final baglam = SecurityContext(withTrustedRoots: false)..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    return _istemci ??= HttpClient(context: baglam)
      ..connectionTimeout = baglanmaSuresi
      ..findProxy = ((_) => 'DIRECT') // sistem/ortam vekili sertifika sabitlemeyi dolanmasın
      ..badCertificateCallback = (cert, host, port) {
        final tamam = host == baglanti.ip && port == baglanti.port && parmakIziUyuyor(cert.der, baglanti.parmakIzi);
        if (!tamam) _uyusmadi = true;
        return tamam;
      };
  }

  void _baglantiyiKes() {
    _istemci?.close(force: true);
    _istemci = null;
  }

  @override
  void kapat() {
    _kapali = true;
    _baglantiyiKes();
  }

  @override
  Future<WifiHello> hello() async {
    final j = _json(await _istek('GET', '/v1/hello', sure: getSuresi, sinir: _durumGovdeSiniri));
    if (j is! Map || j['format'] != 'takvim-wifi') throw const WifiHatasi(WifiHataTuru.beklenmeyen, 'Takvim yanıtı değil');
    final s = j['version'];
    if (s is! int || s < 1) throw const WifiHatasi(WifiHataTuru.beklenmeyen, 'sürüm okunamadı');
    if (s > wifiBaglantiSurumu) throw WifiHatasi(WifiHataTuru.surum, 'masaüstü protokol sürümü $s');
    final d = j['device'];
    String metin(Object? o) => o is String ? o : '';
    return WifiHello(ad: d is Map ? metin(d['name']) : '', uygulama: d is Map ? metin(d['app']) : '');
  }

  @override
  Future<String> durumAl() async {
    final govde = await _istek('GET', '/v1/state', sure: getSuresi, sinir: getEnFazlaBayt);
    try {
      return utf8.decode(govde);
    } on FormatException {
      throw const WifiHatasi(WifiHataTuru.beklenmeyen, 'yanıt UTF-8 değil');
    }
  }

  @override
  Future<WifiRapor> durumGonder(String metin) async {
    final bayt = Uint8List.fromList(utf8.encode(metin));
    if (bayt.length > wifiGetEnFazlaBayt) throw const WifiHatasi(WifiHataTuru.cokBuyuk, 'gönderilecek veri 16 MB sınırını aşıyor');
    final j = _json(await _istek('POST', '/v1/state', sure: postSuresi, sinir: _raporSiniri, govde: bayt));
    // Masaüstü uyguladı ama rapor okunamadı: hata sayılmaz (sayılar 0 görünür).
    return WifiRapor.jsondan(j is Map ? j['report'] : null);
  }

  Object? _json(Uint8List govde) {
    try {
      return jsonDecode(utf8.decode(govde));
    } on FormatException {
      throw const WifiHatasi(WifiHataTuru.beklenmeyen, 'yanıt JSON değil');
    }
  }

  /// Tek istek: ikinci adres denetimi, zaman aşımı, sınırlı okuma, durum kodu eşlemesi.
  /// Her hata [WifiHatasi]'dır; başarıda yanıt gövdesi döner.
  Future<Uint8List> _istek(String yontem, String yol, {required Duration sure, required int sinir, Uint8List? govde}) async {
    if (!adresIzinli(baglanti.ip)) throw const WifiHatasi(WifiHataTuru.ozelOlmayanAdres);
    if (_kapali) throw const WifiHatasi(WifiHataTuru.iptal);
    _uyusmadi = false;
    try {
      final (durum, bayt) = await _degis(yontem, yol, govde, sinir).timeout(sure);
      if (durum == 200) return bayt;
      throw _durumHatasi(durum, bayt);
    } on WifiHatasi catch (e) {
      if (e.tur == WifiHataTuru.cokBuyuk) _baglantiyiKes();
      rethrow;
    } catch (e) {
      final hata = _esle(e);
      _baglantiyiKes(); // yarım kalan istek açık kalmasın
      throw hata;
    }
  }

  Future<(int, Uint8List)> _degis(String yontem, String yol, Uint8List? govde, int sinir) async {
    final istek = await _istemciAl().openUrl(yontem, Uri(scheme: 'https', host: baglanti.ip, port: baglanti.port, path: yol));
    istek.followRedirects = false;
    istek.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${baglanti.token}')
      ..set(HttpHeaders.acceptHeader, 'application/json');
    if (govde != null) {
      istek.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      istek.contentLength = govde.length;
      istek.add(govde);
    }
    final yanit = await istek.close();
    final durum = yanit.statusCode;
    final ust = durum == 200 ? sinir : _durumGovdeSiniri;
    if (durum == 200 && yanit.contentLength > ust) throw const WifiHatasi(WifiHataTuru.cokBuyuk, 'yanıt çok büyük');
    final tampon = BytesBuilder(copy: false);
    await for (final parca in yanit) {
      tampon.add(parca);
      if (tampon.length > ust) {
        if (durum == 200) throw const WifiHatasi(WifiHataTuru.cokBuyuk, 'yanıt çok büyük');
        break; // hata gövdesi gereğinden uzun: yalnız durum kodu yeter
      }
    }
    return (durum, tampon.takeBytes());
  }

  WifiHatasi _durumHatasi(int durum, Uint8List govde) {
    switch (durum) {
      case 401:
        return const WifiHatasi(WifiHataTuru.yetkisiz);
      case 403:
        return const WifiHatasi(WifiHataTuru.reddedildi);
      case 408:
        return const WifiHatasi(WifiHataTuru.masaustuSuresiDoldu);
      case 413:
        return const WifiHatasi(WifiHataTuru.cokBuyuk, 'masaüstü reddetti (413)');
      case 400:
        var kod = '';
        try {
          final j = jsonDecode(utf8.decode(govde));
          if (j is Map && j['error'] is String) kod = (j['error'] as String).replaceAll(RegExp(r'[^\w .:-]'), '');
          if (kod.length > 80) kod = kod.substring(0, 80);
        } on FormatException {
          // gövde yok ya da JSON değil
        }
        final k = kod.toLowerCase();
        return WifiHatasi(k.contains('surum') || k.contains('version') ? WifiHataTuru.surum : WifiHataTuru.gecersizDosya, kod);
      default:
        return WifiHatasi(WifiHataTuru.beklenmeyen, durum >= 300 && durum < 400 ? 'yönlendirme reddedildi ($durum)' : 'HTTP $durum');
    }
  }

  WifiHatasi _esle(Object e) {
    if (_kapali) return const WifiHatasi(WifiHataTuru.iptal);
    if (_uyusmadi) return const WifiHatasi(WifiHataTuru.parmakIzi);
    if (e is WifiHatasi) return e;
    if (e is TimeoutException) return const WifiHatasi(WifiHataTuru.sureDoldu);
    if (e is HandshakeException || e is TlsException) return const WifiHatasi(WifiHataTuru.tlsKurulamadi);
    if (e is SocketException) return WifiHatasi(WifiHataTuru.ulasilamadi, e.osError?.message ?? e.message);
    if (e is HttpException) return const WifiHatasi(WifiHataTuru.beklenmeyen, 'bağlantı beklenmedik biçimde kapandı');
    return WifiHatasi(WifiHataTuru.beklenmeyen, e.runtimeType.toString());
  }
}

/// Sertifika DER'inin SHA-256'sı, base64url (dolgusuz) olarak beklenen parmak iziyle birebir aynı mı.
bool parmakIziUyuyor(List<int> der, String beklenen) {
  final a = base64Url.encode(sha256(der)).replaceAll('=', '').codeUnits;
  final b = beklenen.codeUnits;
  if (a.length != b.length) return false;
  var fark = 0;
  for (var i = 0; i < a.length; i++) {
    fark |= a[i] ^ b[i];
  }
  return fark == 0;
}
