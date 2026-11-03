// Wi-Fi eşleştirme istemcisinin (lib/sync/wifi_istemci.dart) GERÇEK TLS ile sınanması.
//
// Flutter'a bağlı değil: `dart run tool/e2e/wifi_istemci_testi.dart` (flutter test GEREKMEZ: flutter_test
// HttpClient'ı sahteyle değiştirir ve bu makinede motor çöküyor). Yerel (loopback) bir HttpServer'ı
// kendi imzalı sertifikayla açar; istemci ona yalnız sertifika parmak iziyle güvenir.
//
// Sertifika CALISMA ANINDA `openssl` ile isletim sisteminin gecici klasorunde uretilir (1 gun gecerli) ve test
// bitince klasor silinir; depoya anahtar/sertifika KONMAZ. openssl yoksa TLS denetimleri acik mesajla ATLANIR ve
// komut 0 yerine 2 koduyla cikar (0 = TLS denetimleri kosup gecti, 1 = hata, 2 = TLS hic kosmadi).
// Yalniz TLS 1.1 sunucusu denetimi bu openssl'de kurulamazsa o denetim ATLANDI yazar, kod yine 0 olur.
// `--ayrinti` gecen denetimleri de listeler. CI'da (ubuntu) openssl vardir;
// Windows'ta PATH'te yoksa Git'in openssl'i denenir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:takvim/sync/wifi_baglanti.dart';
import 'package:takvim/sync/wifi_istemci.dart';

int hatalar = 0, toplam = 0, atlanan = 0;
bool ayrinti = false; // --ayrinti: gecen denetimleri de yazar
const token = 'cafe0123456789abcdef0123456789ab';

void kontrol(String ad, bool kosul, [Object? detay]) {
  toplam++;
  if (kosul && ayrinti) stdout.writeln('GECTI  $ad');
  if (!kosul) {
    hatalar++;
    stdout.writeln('KALDI  $ad${detay == null ? '' : '  -> $detay'}');
  }
}

/// Her çağrıda yakalanan istek.
class Istek {
  Istek(this.yontem, this.yol, this.yetki, this.tur, this.uzunluk, this.govde);
  final String yontem, yol;
  final String? yetki, tur;
  final int uzunluk;
  final String govde;
}

typedef Davranis = Future<void> Function(HttpRequest r, Istek i);

class Sunucu {
  Sunucu._(this.http, this.istekler);
  final HttpServer http;
  final List<Istek> istekler;
  int get port => http.port;
  Future<void> kapat() => http.close(force: true);

  static Future<Sunucu> ac(SecurityContext baglam, Davranis davranis) async {
    final http = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, baglam);
    final istekler = <Istek>[];
    http.listen((r) async {
      try {
        final govde = r.method == 'POST' ? utf8.decode(await r.fold<List<int>>([], (a, b) => a..addAll(b))) : '';
        final i = Istek(r.method, r.uri.path, r.headers.value('authorization'), r.headers.contentType?.mimeType, r.contentLength, govde);
        istekler.add(i);
        await davranis(r, i);
      } catch (_) {
        // istemci bağlantıyı kesti (boyut sınırı, zaman aşımı...): beklenen
      }
    });
    return Sunucu._(http, istekler);
  }
}

Future<void> yaz(HttpRequest r, int durum, Object? json) async {
  r.response.statusCode = durum;
  r.response.headers.contentType = ContentType.json;
  r.response.write(json is String ? json : jsonEncode(json));
  await r.response.close();
}

const helloJson = {'format': 'takvim-wifi', 'version': 1, 'device': {'name': 'MASAUSTU', 'app': 'desktop 1.9.0'}};
const durumMetni = '{"format":"takvim-sync","version":1,"calendars":[],"events":[],"tasks":[],"deleted":[]}';

/// Yetkiyi sabit zamanlı olmasa da doğrulayan, yollara göre cevap veren varsayılan sunucu.
Future<void> normal(HttpRequest r, Istek i) async {
  if (i.yetki != 'Bearer $token') return yaz(r, 401, {'error': 'yetkisiz'});
  if (i.yol == '/v1/hello' && i.yontem == 'GET') return yaz(r, 200, helloJson);
  if (i.yol == '/v1/state' && i.yontem == 'GET') return yaz(r, 200, durumMetni);
  if (i.yol == '/v1/state' && i.yontem == 'POST') {
    return yaz(r, 200, {'report': {'added': 3, 'updated': 2, 'deleted': 1, 'skipped': 4}});
  }
  return yaz(r, 404, {'error': 'yok'});
}

WifiBaglanti baglanti(int port, String pin, {String tok = token}) =>
    WifiBaglanti(ip: '127.0.0.1', port: port, token: tok, parmakIzi: pin, ad: 'test');

WifiIstemci istemci(int port, String pin, {String tok = token, Duration get = const Duration(seconds: 5), Duration post = const Duration(seconds: 5), int? sinir}) =>
    WifiIstemci(baglanti(port, pin, tok: tok),
        adresIzinli: (_) => true, // test: loopback (ürün yalnız özel LAN adreslerine bağlanır)
        baglanmaSuresi: const Duration(seconds: 3),
        getSuresi: get,
        postSuresi: post,
        getEnFazlaBayt: sinir ?? wifiGetEnFazlaBayt);

/// Çağrıyı çalıştırır; WifiHatasi türünü döndürür (hata yoksa null, başka istisna ise 'baska:...').
Future<String?> tur(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } on WifiHatasi catch (e) {
    kontrol('hata iletisi token içermez (${e.tur.name})', !e.toString().contains(token) && !e.ayrinti.contains(token));
    return e.tur.name;
  } catch (e) {
    return 'baska:$e';
  }
}

Future<void> baglamsiz() async {
  stdout.writeln('-- sertifikasız denetimler');
  // Varsayılan adres denetimi özel olmayan (loopback dahil) adrese HİÇ bağlanmaz.
  final dinle = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  var gelen = 0;
  dinle.listen((s) {
    gelen++;
    s.destroy();
  });
  final varsayilan = WifiIstemci(baglanti(dinle.port, 'A' * 43));
  kontrol('varsayılan: loopback reddedilir', await tur(varsayilan.hello) == 'ozelOlmayanAdres');
  for (final ip in ['8.8.8.8', '127.0.0.1', '100.64.0.1', '172.32.0.1']) {
    final w = WifiIstemci(WifiBaglanti(ip: ip, port: 1, token: token, parmakIzi: 'A' * 43, ad: ''));
    kontrol('varsayılan: $ip reddedilir', await tur(w.durumAl) == 'ozelOlmayanAdres');
    kontrol('varsayılan: $ip POST reddedilir', await tur(() => w.durumGonder('{}')) == 'ozelOlmayanAdres');
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  kontrol('reddedilen adrese TCP bağlantısı açılmadı', gelen == 0, gelen);

  final bos = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final kapaliPort = bos.port;
  await bos.close();
  kontrol('kapalı port -> ulasilamadi', await tur(istemci(kapaliPort, 'A' * 43).hello) == 'ulasilamadi');

  // TLS konuşmayan sunucu (düz HTTP): güvenli bağlantı kurulamaz, hiçbir şey gönderilmez.
  final duz = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final duzGelen = BytesBuilder();
  duz.listen((s) {
    s.listen(duzGelen.add, onError: (_) {}, onDone: () {});
    s.write('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{}');
    s.flush().then((_) => s.destroy(), onError: (_) {});
  });
  kontrol('TLS olmayan sunucu -> tlsKurulamadi', await tur(istemci(duz.port, 'A' * 43).hello) == 'tlsKurulamadi');
  kontrol('düz sunucu token görmedi', !latin1.decode(duzGelen.toBytes(), allowInvalid: true).contains(token));
  await duz.close();

  // Susan sunucu: bağlanır, el sıkışmaya yanıt vermez -> süre doldu.
  final sus = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final susSoketler = <Socket>[];
  sus.listen(susSoketler.add);
  final sw = Stopwatch()..start();
  kontrol('susan sunucu GET -> sureDoldu', await tur(istemci(sus.port, 'A' * 43, get: const Duration(milliseconds: 400)).hello) == 'sureDoldu');
  kontrol('GET süresi kısa tutuldu', sw.elapsedMilliseconds < 3000, sw.elapsedMilliseconds);
  kontrol('susan sunucu POST -> sureDoldu', await tur(() => istemci(sus.port, 'A' * 43, post: const Duration(milliseconds: 400)).durumGonder('{}')) == 'sureDoldu');

  // Süren isteği kapat() keser.
  final w = istemci(sus.port, 'A' * 43);
  final bekleyen = tur(w.durumAl);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  w.kapat();
  kontrol('kapat() süren isteği keser -> iptal', await bekleyen == 'iptal');
  kontrol('kapatılmış istemci yeni istek açmaz', await tur(w.hello) == 'iptal');
  for (final s in susSoketler) {
    s.destroy();
  }
  await sus.close();
  await dinle.close();
}

Future<void> tlsli(SecurityContext baglam, String pin) async {
  stdout.writeln('-- TLS denetimleri (sertifika sabitleme)');
  const yanlisPin = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopA';

  // 1) Mutlu yol + istek biçimi
  var s = await Sunucu.ac(baglam, normal);
  var c = istemci(s.port, pin);
  final h = await c.hello();
  kontrol('hello: ad ve uygulama', h.ad == 'MASAUSTU' && h.uygulama == 'desktop 1.9.0', '${h.ad} ${h.uygulama}');
  kontrol('state: gövde birebir', await c.durumAl() == durumMetni);
  final giden = jsonEncode({'format': 'takvim-sync', 'version': 1, 'not': 'Türkçe ğüşiöç'});
  final r = await c.durumGonder(giden);
  kontrol('POST raporu', r.added == 3 && r.updated == 2 && r.deleted == 1 && r.skipped == 4);
  kontrol('3 istek geldi', s.istekler.length == 3, s.istekler.length);
  kontrol('her istekte Bearer token', s.istekler.every((i) => i.yetki == 'Bearer $token'));
  final post = s.istekler.last;
  kontrol('POST gövdesi birebir (UTF-8)', post.govde == giden, post.govde);
  kontrol('POST Content-Type json ve Content-Length', post.tur == 'application/json' && post.uzunluk == utf8.encode(giden).length);
  c.kapat();

  // 2) Yanlış parmak izi: el sıkışma reddedilir, sunucu HİÇ HTTP isteği görmez (token gitmez).
  s.istekler.clear();
  for (final yontem in ['hello', 'durumAl', 'durumGonder']) {
    final w = istemci(s.port, yanlisPin);
    final t = await tur(() => yontem == 'hello' ? w.hello() : yontem == 'durumAl' ? w.durumAl() : w.durumGonder('{}'));
    kontrol('yanlış parmak izi $yontem -> parmakIzi', t == 'parmakIzi', t);
  }
  kontrol('yanlış parmak izinde sunucu hiçbir HTTP isteği görmedi', s.istekler.isEmpty, s.istekler.length);
  // Parmak izi büyük/küçük harf ya da dolgulu hâliyle de eşleşmez
  kontrol('dolgulu parmak izi eşleşmez', await tur(istemci(s.port, '$pin=').hello) == 'parmakIzi');
  kontrol('kısaltılmış parmak izi eşleşmez', await tur(istemci(s.port, pin.substring(0, 42)).hello) == 'parmakIzi');

  // 3) Sistem güven deposu YOK: sabitlenmiş doğru parmak izi olmadan hiçbir sertifika kabul edilmez
  // (kendi imzalı sertifika zaten sistemde güvenilmez; doğru parmak izi tek geçiş yoludur).
  kontrol('doğru parmak izi çalışır', await tur(istemci(s.port, pin).hello) == null);

  // 4) Yetki
  kontrol('yanlış token -> yetkisiz (401)', await tur(istemci(s.port, pin, tok: '0' * 32).durumAl) == 'yetkisiz');
  kontrol('yanlış token POST -> yetkisiz', await tur(() => istemci(s.port, pin, tok: '0' * 32).durumGonder('{}')) == 'yetkisiz');
  await s.kapat();

  // 5) Durum kodu eşlemeleri (GET ve POST)
  final esler = <(int, Object, String)>[
    (403, {'error': 'reddedildi'}, 'reddedildi'),
    (408, {'error': 'zaman'}, 'masaustuSuresiDoldu'),
    (400, {'error': 'gecersiz_dosya'}, 'gecersizDosya'),
    (400, {'error': 'surum_yeni'}, 'surum'),
    (400, 'JSON degil', 'gecersizDosya'),
    (401, {'error': 'yetkisiz'}, 'yetkisiz'),
    (404, {'error': 'yok'}, 'beklenmeyen'),
    (405, {'error': 'metot'}, 'beklenmeyen'),
    (500, {'error': 'x'}, 'beklenmeyen'),
    (413, {'error': 'buyuk'}, 'cokBuyuk'),
  ];
  for (final (kod, govde, beklenen) in esler) {
    s = await Sunucu.ac(baglam, (r, i) => yaz(r, kod, govde));
    kontrol('GET $kod -> $beklenen', await tur(istemci(s.port, pin).durumAl) == beklenen);
    kontrol('POST $kod -> $beklenen', await tur(() => istemci(s.port, pin).durumGonder('{}')) == beklenen);
    await s.kapat();
  }

  // 6) hello biçimi
  for (final (ad, j, beklenen) in <(String, Object, String)>[
    ('hello sürüm 2', {'format': 'takvim-wifi', 'version': 2}, 'surum'),
    ('hello başka biçim', {'format': 'baska', 'version': 1}, 'beklenmeyen'),
    ('hello sürümsüz', {'format': 'takvim-wifi'}, 'beklenmeyen'),
    ('hello JSON değil', 'merhaba', 'beklenmeyen'),
  ]) {
    s = await Sunucu.ac(baglam, (r, i) => yaz(r, 200, j));
    kontrol('$ad -> $beklenen', await tur(istemci(s.port, pin).hello) == beklenen);
    await s.kapat();
  }

  // 7) Yönlendirme izlenmez (token başka yere gitmesin)
  s = await Sunucu.ac(baglam, (r, i) async {
    r.response.statusCode = 302;
    r.response.headers.set('location', '/v1/baska');
    await r.response.close();
  });
  kontrol('GET 302 -> beklenmeyen (izlenmez)', await tur(istemci(s.port, pin).durumAl) == 'beklenmeyen');
  kontrol('POST 307 de izlenmez', await tur(() => istemci(s.port, pin).durumGonder('{}')) == 'beklenmeyen');
  kontrol('yönlendirme izlenmedi: yalnız ilk istekler geldi', s.istekler.length == 2 && s.istekler.every((i) => i.yol == '/v1/state'), s.istekler.map((i) => i.yol).toList());
  await s.kapat();

  // 8) Yanıt boyutu sınırı: GET gövdesi 16 MiB'ı aşarsa kesilir ve reddedilir
  Future<void> buyuk(HttpRequest r, int n, {required bool uzunlukluk}) async {
    r.response.statusCode = 200;
    r.response.headers.contentType = ContentType.json;
    if (uzunlukluk) r.response.contentLength = n;
    final parca = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x61);
    for (var yazilan = 0; yazilan < n; yazilan += parca.length) {
      r.response.add(n - yazilan >= parca.length ? parca : Uint8List.sublistView(parca, 0, n - yazilan));
    }
    await r.response.close();
  }

  const mib = 1024 * 1024;
  s = await Sunucu.ac(baglam, (r, i) => buyuk(r, 16 * mib + 1, uzunlukluk: true));
  kontrol('16 MiB + 1 (Content-Length) -> cokBuyuk', await tur(istemci(s.port, pin).durumAl) == 'cokBuyuk');
  await s.kapat();
  s = await Sunucu.ac(baglam, (r, i) => buyuk(r, 20 * mib, uzunlukluk: false));
  kontrol('20 MiB (parçalı, uzunluksuz) -> cokBuyuk', await tur(istemci(s.port, pin).durumAl) == 'cokBuyuk');
  await s.kapat();
  s = await Sunucu.ac(baglam, (r, i) => buyuk(r, 16 * mib, uzunlukluk: true));
  final tam = await istemci(s.port, pin).durumAl();
  kontrol('tam 16 MiB kabul edilir', tam.length == 16 * mib, tam.length);
  await s.kapat();
  s = await Sunucu.ac(baglam, (r, i) => buyuk(r, 5000, uzunlukluk: true));
  kontrol('küçük sınır (test parametresi) uygulanır', await tur(istemci(s.port, pin, sinir: 4096).durumAl) == 'cokBuyuk');
  await s.kapat();
  // Hata gövdesi sınırsız büyüse de durum kodu okunur (bellek şişmez)
  s = await Sunucu.ac(baglam, (r, i) async {
    r.response.statusCode = 403;
    await buyuk403(r);
  });
  kontrol('devasa 403 gövdesi -> yine reddedildi', await tur(istemci(s.port, pin).durumAl) == 'reddedildi');
  await s.kapat();
  // Gönderilecek veri 16 MiB'ı aşarsa hiç gönderilmez
  s = await Sunucu.ac(baglam, normal);
  kontrol('16 MiB üstü gönderim istemcide reddedilir', await tur(() => istemci(s.port, pin).durumGonder('a' * (16 * mib + 1))) == 'cokBuyuk');
  kontrol('...ve sunucuya hiçbir şey gitmedi', s.istekler.isEmpty);
  await s.kapat();

  // 9) Zaman aşımı: yanıt gelmezse
  s = await Sunucu.ac(baglam, (r, i) => Future<void>.delayed(const Duration(seconds: 3)));
  kontrol('GET yanıt gelmez -> sureDoldu', await tur(istemci(s.port, pin, get: const Duration(milliseconds: 500)).durumAl) == 'sureDoldu');
  kontrol('POST yanıt gelmez -> sureDoldu', await tur(() => istemci(s.port, pin, post: const Duration(milliseconds: 500)).durumGonder('{}')) == 'sureDoldu');
  // POST süresi GET'ten uzun olabilir: GET 300 ms'de dolar, POST 2 sn bekler ve yanıtı alır
  await s.kapat();
  s = await Sunucu.ac(baglam, (r, i) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await normal(r, i);
  });
  kontrol('POST, GET süresinden uzun beklenir', await tur(() => istemci(s.port, pin, get: const Duration(milliseconds: 300), post: const Duration(seconds: 3)).durumGonder('{}')) == null);
  kontrol('GET kısa süreyle dolar', await tur(istemci(s.port, pin, get: const Duration(milliseconds: 300), post: const Duration(seconds: 3)).durumAl) == 'sureDoldu');
  final portu = s.port; // kapatmadan ÖNCE: kapalı sunucuda port okunamaz
  await s.kapat();

  // 10) Sunucu kapanmışsa
  kontrol('sunucu kapalı -> ulasilamadi', await tur(istemci(portu, pin).hello) == 'ulasilamadi');
}

Future<void> buyuk403(HttpRequest r) async {
  final parca = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x62);
  for (var i = 0; i < 200; i++) {
    r.response.add(parca); // ~12 MiB
  }
  await r.response.close();
}

Future<String?> opensslBul() async {
  for (final aday in ['openssl', 'C:/Program Files/Git/usr/bin/openssl.exe', '/usr/bin/openssl', '/opt/homebrew/bin/openssl']) {
    try {
      if ((await Process.run(aday, ['version'])).exitCode == 0) return aday;
    } on ProcessException {
      // sıradaki aday
    }
  }
  return null;
}

/// TLS 1.0/1.1'e inen bir sunucuya (openssl s_server) bağlanmamalı. Sunucunun gerçekten <1.2 konuştuğu
/// s_client ile doğrulanamazsa denetim ATLANIR (boş geçmesin diye).
Future<void> eskiTls(String openssl, String sert, String anahtar, String pin) async {
  stdout.writeln('-- TLS 1.0/1.1 sunucusu');
  final ger = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = ger.port;
  await ger.close();
  final env = {'MSYS_NO_PATHCONV': '1'};
  final sunucu = await Process.start(
      openssl,
      ['s_server', '-accept', '$port', '-cert', sert, '-key', anahtar, '-min_protocol', 'TLSv1', '-max_protocol', 'TLSv1.1', '-cipher', 'DEFAULT:@SECLEVEL=0', '-www', '-quiet'],
      environment: env);
  sunucu.stdout.drain<void>();
  sunucu.stderr.drain<void>();
  try {
    var hazir = false;
    for (var i = 0; i < 30 && !hazir; i++) {
      try {
        (await Socket.connect(InternetAddress.loopbackIPv4, port)).destroy();
        hazir = true;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    var dogrulandi = false;
    if (hazir) {
      final r = await Process.run(openssl, ['s_client', '-connect', '127.0.0.1:$port', '-tls1_1', '-cipher', 'DEFAULT:@SECLEVEL=0'], stdoutEncoding: latin1, environment: env)
          .timeout(const Duration(seconds: 10));
      dogrulandi = '${r.stdout}'.contains('TLSv1.1');
    }
    if (!dogrulandi) {
      atlanan++;
      stdout.writeln('ATLANDI  TLS 1.1 sunucusu bu openssl ile kurulamadı/doğrulanamadı; denetim koşmadı.');
      return;
    }
    final t = await tur(istemci(port, pin).hello);
    kontrol('TLS 1.1 sunucusuna bağlanılmaz (tlsKurulamadi)', t == 'tlsKurulamadi', t);
    kontrol('TLS 1.1 sunucusuna POST de gitmez', await tur(() => istemci(port, pin).durumGonder('{}')) == 'tlsKurulamadi');
  } finally {
    sunucu.kill();
  }
}

Future<void> main(List<String> args) async {
  ayrinti = args.contains('--ayrinti');
  await baglamsiz();

  final openssl = await opensslBul();
  var tlsKostu = false;
  if (openssl == null) {
    atlanan++;
    stdout.writeln('ATLANDI  TLS denetimleri: openssl bulunamadı (PATH ya da Git usr bin).');
  } else {
    final dizin = await Directory.systemTemp.createTemp('takvim_tls');
    try {
      final sert = '${dizin.path}${Platform.pathSeparator}sertifika.crt';
      final anahtar = '${dizin.path}${Platform.pathSeparator}anahtar.key';
      final r = await Process.run(
          openssl,
          [
            'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', '-days', '1',
            '-subj', '/CN=takvim-test', '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', anahtar, '-out', sert,
          ],
          environment: {'MSYS_NO_PATHCONV': '1'});
      if (r.exitCode != 0) {
        atlanan++;
        stdout.writeln('ATLANDI  TLS denetimleri: openssl sertifika üretemedi: ${r.stderr}');
      } else {
        final metin = await File(sert).readAsString();
        final b64 = const LineSplitter().convert(metin).where((s) => s.isNotEmpty && !s.startsWith('-----')).join();
        final pin = base64UrlDolgusuz(sha256(base64.decode(b64)));
        final baglam = SecurityContext(withTrustedRoots: false)
          ..useCertificateChain(sert)
          ..usePrivateKey(anahtar);
        await tlsli(baglam, pin);
        tlsKostu = true;
        await eskiTls(openssl, sert, anahtar, pin);
      }
    } finally {
      try {
        await dizin.delete(recursive: true); // özel anahtar diskte kalmaz
      } on FileSystemException {
        // Windows: bir tutamaç açıksa silinemez; 1 günlük test anahtarı, sistem geçici klasörü temizler
      }
    }
  }

  stdout.writeln('$toplam denetim, $hatalar hata${atlanan > 0 ? ', $atlanan grup ATLANDI' : ''}');
  exit(hatalar > 0 ? 1 : !tlsKostu ? 2 : 0); // yalniz TLS 1.1 denetimi atlandiysa 0 (CI kirmizi olmasin)
}

String base64UrlDolgusuz(List<int> b) => base64Url.encode(b).replaceAll('=', '');
