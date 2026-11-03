// Wi-Fi eşleştirme bağlantısı ayrıştırıcısı ve SHA-256 (ağ yok, saf Dart).
// Spec: takvim/docs/senkron-wifi.md §2, §4. Ağ/TLS testleri: tool/e2e/wifi_istemci_testi.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/sync/wifi_baglanti.dart';
import 'package:takvim/sync/wifi_istemci.dart';
import 'package:takvim/ui/metin.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

final _f = base64Url.encode(sha256(utf8.encode('sertifika'))).replaceAll('=', ''); // 43 karakter
const _t = '0123456789abcdef0123456789abcdef';

String baglanti({String ana = 'https://aktenak.tech/s', String h = '192.168.1.20:51734', String t = _t, String? f, String n = 'Arda%20PC', String ek = ''}) =>
    '$ana#v=1&h=$h&t=$t&f=${f ?? _f}&n=$n$ek';

WifiBaglantiHataTuru? hata(String girdi) {
  try {
    wifiBaglantiAyristir(girdi);
    return null;
  } on WifiBaglantiHatasi catch (e) {
    return e.tur;
  }
}

void main() {
  group('geçerli bağlantı', () {
    test('alanlar çözülür', () {
      expect(_f, hasLength(43));
      final b = wifiBaglantiAyristir(baglanti());
      expect(b.ip, '192.168.1.20');
      expect(b.port, 51734);
      expect(b.token, _t);
      expect(b.parmakIzi, _f);
      expect(b.ad, 'Arda PC');
      expect(b.adres, '192.168.1.20:51734');
      expect(b.toString(), isNot(contains(_t))); // token günlüğe/hata iletisine sızmaz
    });

    test('baştaki/sondaki boşluk ve satır sonu kırpılır; şema ve ana makine büyük harf olabilir', () {
      expect(wifiBaglantiAyristir('  ${baglanti()}\n').port, 51734);
      expect(wifiBaglantiAyristir(baglanti(ana: 'HTTPS://Aktenak.Tech/s')).port, 51734);
    });

    test('site /s/ olarak da servis eder: bağlantı /s ve /s/ ile kabul', () {
      expect(wifiBaglantiAyristir(baglanti(ana: 'https://aktenak.tech/s/')).port, 51734);
    });

    test('özel ve yerel aralıkların sınırları', () {
      for (final ip in ['10.0.0.1', '10.255.255.255', '172.16.0.1', '172.31.255.255', '192.168.0.1', '192.168.255.254', '169.254.1.1']) {
        expect(hata(baglanti(h: '$ip:1')), isNull, reason: ip);
      }
      expect(hata(baglanti(h: '10.0.0.1:65535')), isNull);
    });

    test('bilinmeyen anahtarlar yok sayılır, n yoksa ad boştur', () {
      final b = wifiBaglantiAyristir('https://aktenak.tech/s#x=1&v=1&yeni=a%20b&h=10.0.0.5:5000&t=$_t&f=$_f&zz=');
      expect(b.ad, '');
      expect(b.ip, '10.0.0.5');
    });

    test('anahtar sırası önemsiz', () {
      expect(hata('https://aktenak.tech/s#f=$_f&t=$_t&h=10.0.0.5:5000&v=1'), isNull);
    });
  });

  group('reddedilen biçimler (bağlanılmaz)', () {
    final bozuklar = <String, String>{
      'boş': '',
      'yalnız boşluk': '   ',
      'http': baglanti(ana: 'http://aktenak.tech/s'),
      'şemasız': baglanti(ana: 'aktenak.tech/s'),
      'başka şema': baglanti(ana: 'javascript://aktenak.tech/s'),
      'alt alan adı': baglanti(ana: 'https://x.aktenak.tech/s'),
      'sonek tuzağı': baglanti(ana: 'https://aktenak.tech.evil.com/s'),
      'önek tuzağı': baglanti(ana: 'https://evilaktenak.tech/s'),
      'kullanıcı bilgisi': baglanti(ana: 'https://aktenak.tech@evil.com/s'),
      'kullanıcı:parola': baglanti(ana: 'https://user:pw@aktenak.tech/s'),
      'port': baglanti(ana: 'https://aktenak.tech:443/s'),
      'sondaki nokta': baglanti(ana: 'https://aktenak.tech./s'),
      'başka yol': baglanti(ana: 'https://aktenak.tech/x'),
      'yol çift eğik çizgi': baglanti(ana: 'https://aktenak.tech/s//'),
      'yol alt yolu': baglanti(ana: 'https://aktenak.tech/s/x'),
      'yol sss': baglanti(ana: 'https://aktenak.tech/sss'),
      'yol studyo': baglanti(ana: 'https://aktenak.tech/studyo/'),
      'yol uzun': baglanti(ana: 'https://aktenak.tech/shop'),
      'kodlanmış yol': baglanti(ana: 'https://aktenak.tech/%73'),
      'sorgu': baglanti(ana: 'https://aktenak.tech/s?x=1'),
      'ters eğik çizgi': baglanti(ana: r'https://aktenak.tech\@evil.com/s'),
      'fragment yok': 'https://aktenak.tech/s',
      'çift fragment': '${baglanti()}#v=1',
      'v yok': 'https://aktenak.tech/s#h=10.0.0.5:5000&t=$_t&f=$_f',
      'h yok': 'https://aktenak.tech/s#v=1&t=$_t&f=$_f',
      't yok': 'https://aktenak.tech/s#v=1&h=10.0.0.5:5000&f=$_f',
      'f yok': 'https://aktenak.tech/s#v=1&h=10.0.0.5:5000&t=$_t',
      'v=0': baglanti().replaceFirst('v=1', 'v=0'),
      'v harf': baglanti().replaceFirst('v=1', 'v=a'),
      'v çok uzun': baglanti().replaceFirst('v=1', 'v=1234567'),
      'v boş': baglanti().replaceFirst('v=1', 'v='),
      'token büyük harf': baglanti(t: _t.toUpperCase()),
      'token 31': baglanti(t: _t.substring(1)),
      'token 33': baglanti(t: '${_t}a'),
      'token hex değil': baglanti(t: 'g${_t.substring(1)}'),
      'f 42': baglanti(f: _f.substring(1)),
      'f 44': baglanti(f: '${_f}A'),
      'f dolgulu': baglanti(f: '$_f='),
      'f standart base64': baglanti(f: '${_f.substring(0, 42)}+'),
      'f kanonik değil': baglanti(f: '${_f.substring(0, 42)}B'),
      'h portsuz': baglanti(h: '192.168.1.20'),
      'h port 0': baglanti(h: '192.168.1.20:0'),
      'h port 65536': baglanti(h: '192.168.1.20:65536'),
      'h port 6 hane': baglanti(h: '192.168.1.20:100000'),
      'h port baştaki sıfır': baglanti(h: '192.168.1.20:051734'),
      'h port harf': baglanti(h: '192.168.1.20:80a'),
      'h IPv6': baglanti(h: '[fd00::1]:5000'),
      'h IPv6 çıplak': baglanti(h: 'fd00::1:5000'),
      'h IPv4-eşlemeli IPv6': baglanti(h: '[::ffff:192.168.1.20]:5000'),
      'h ana makine adı': baglanti(h: 'masaustu.local:5000'),
      'h localhost': baglanti(h: 'localhost:5000'),
      'h onlu IP': baglanti(h: '3232235796:5000'),
      'h sekizlik sıfır': baglanti(h: '192.168.001.20:5000'),
      'h sekizli 256': baglanti(h: '192.168.1.256:5000'),
      'h üç sekizli': baglanti(h: '192.168.1:5000'),
      'h beş sekizli': baglanti(h: '192.168.1.2.3:5000'),
      'h harfli sekizli': baglanti(h: '192.168.1.a:5000'),
      'h kodlanmış': baglanti(h: '192.168.1.20%3A5000'),
      'h kullanıcı bilgisi': baglanti(h: 'evil@192.168.1.20:5000'),
      'yinelenen h': baglanti(ek: '&h=10.0.0.5:5000'),
      'yinelenen t': baglanti(ek: '&t=$_t'),
      'yinelenen v': baglanti(ek: '&v=1'),
      '= yok': baglanti(ek: '&yeni'),
      'boş parça': baglanti(ek: '&&x=1'),
      'sondaki &': '${baglanti()}&',
      'anahtarsız değer': baglanti(ek: '&=1'),
      'boşluk içeride': baglanti(n: 'a b'),
      'satır sonu içeride': baglanti(ek: '&x=a${String.fromCharCode(10)}b'),
      'NUL': baglanti(ek: '&x=a${String.fromCharCode(0)}b'),
      'sekme': baglanti(ek: '&x=a${String.fromCharCode(9)}b'),
      'ASCII dışı': baglanti(ek: '&x=ğ'),
      'çok uzun': baglanti(ek: '&x=${'a' * 1100}'),
    };
    for (final e in bozuklar.entries) {
      test(e.key, () => expect(hata(e.value), WifiBaglantiHataTuru.bicimsiz));
    }

    test('uzunluk sınırı tam 1024', () {
      final taban = baglanti(ek: '&x=');
      expect(hata(taban + 'a' * (wifiBaglantiEnFazlaUzunluk - taban.length)), isNull);
      expect(hata(taban + 'a' * (wifiBaglantiEnFazlaUzunluk - taban.length + 1)), WifiBaglantiHataTuru.bicimsiz);
    });
  });

  group('genel ya da özel olmayan adres', () {
    for (final ip in [
      '8.8.8.8', '1.1.1.1', '127.0.0.1', '0.0.0.0', '255.255.255.255', '11.0.0.1', '9.255.255.255',
      '172.15.255.255', '172.32.0.1', '192.167.1.1', '192.169.1.1', '169.253.1.1', '169.255.1.1', '100.64.0.1', '224.0.0.1',
    ]) {
      test(ip, () => expect(hata(baglanti(h: '$ip:5000')), WifiBaglantiHataTuru.ozelOlmayanAdres));
    }

    test('ozelIpv4mi biçimsiz girdide false', () {
      expect(ozelIpv4mi('192.168.1.20'), isTrue);
      for (final s in ['', '192.168.1', '192.168.1.20.1', 'a.b.c.d', '192.168.01.20', '::1', '192.168.1.256']) {
        expect(ozelIpv4mi(s), isFalse, reason: s);
      }
    });
  });

  group('sürüm', () {
    test('büyük v ayrı hata verir', () {
      expect(hata(baglanti().replaceFirst('v=1', 'v=2')), WifiBaglantiHataTuru.surumYeni);
      expect(hata(baglanti().replaceFirst('v=1', 'v=999999')), WifiBaglantiHataTuru.surumYeni);
    });

    test('yeni sürümün alanları başka biçimde olabilir: v önce denetlenir', () {
      expect(hata('https://aktenak.tech/s#v=2&h=ornek.local&t=x&f=y'), WifiBaglantiHataTuru.surumYeni);
      expect(hata('https://aktenak.tech/s#h=ornek.local&v=2'), WifiBaglantiHataTuru.surumYeni);
    });

    test('ama bağlantının geri kalanı (şema/ana makine/yol) yine denetlenir', () {
      expect(hata('http://aktenak.tech/s#v=2'), WifiBaglantiHataTuru.bicimsiz);
      expect(hata('https://evil.com/s#v=2'), WifiBaglantiHataTuru.bicimsiz);
    });
  });

  group('cihaz adı (n): yalnız gösterim', () {
    String ad(String n) => wifiBaglantiAyristir(baglanti(n: n)).ad;

    test('URL-kodlu Türkçe ve emoji çözülür', () {
      expect(ad(Uri.encodeComponent("Arda'nın Bilgisayarı")), "Arda'nın Bilgisayarı");
      expect(ad(Uri.encodeComponent('PC \u{1F4BB}')), 'PC \u{1F4BB}');
    });

    test('40 karakterde kırpılır (yedek çift karakter ortadan bölünmez)', () {
      expect(ad('a' * 50), 'a' * 40);
      final emoji = Uri.encodeComponent('\u{1F600}' * 50);
      expect(ad(emoji).runes.length, 40);
      expect(ad(emoji).runes.every((r) => r == 0x1F600), isTrue);
    });

    test('kontrol ve yönlendirme karakterleri temizlenir', () {
      expect(ad('a%0Ab%00c%07d%09e'), 'abcde');
      expect(ad('PC%E2%80%AEfdp.exe'), 'PCfdp.exe'); // U+202E (RLO) gösterimi tersine çevirirdi
      expect(ad('a%E2%80%8Bb%EF%BB%BFc'), 'abc'); // sıfır genişlikli boşluk, BOM
      expect(ad('%C2%85x'), 'x'); // C1 kontrol (NEL)
    });

    test('görünmez karakterler temizlenir; yalnız onlardan oluşan ad boş sayılır (Bilinmeyen cihaz)', () {
      // U+061C ALM, U+180E, U+2800 Braille boşluğu, U+3164 Hangul dolgusu, U+FFA0, U+00AD
      for (final k in ['%D8%9C', '%E1%A0%8E', '%E2%A0%80', '%E3%85%A4', '%EF%BE%A0', '%C2%AD', '%CD%8F']) {
        expect(ad('a${k}b'), 'ab', reason: k);
        expect(ad(k * 5), '', reason: k);
      }
      expect(ad('%E2%A0%80%E3%85%A4%EF%BE%A0%20'), '');
      expect(M.wifiCihaz(ad('%E2%A0%80%E3%85%A4'), '10.0.0.5:5000'), 'Bilinmeyen cihaz (10.0.0.5:5000)');
      expect(M.wifiOnayMetni('', '10.0.0.5:5000'), contains('Bilinmeyen cihaz (10.0.0.5:5000) ile eşleşilecek'));
    });

    test('ikinci onay metni karsi cihazin adini ve IP:port bilgisini tekrar eder', () {
      final m = M.wifiOnizlemeNot('Arda PC', '192.168.1.20:51734');
      expect(m, contains('«Arda PC» (192.168.1.20:51734)'));
      expect(M.wifiOnizlemeNot('', '10.0.0.5:5000'), contains('Bilinmeyen cihaz (10.0.0.5:5000)'));
    });

    test('baştaki/sondaki boşluk kırpılır; bozuk yüzde kodu adı boşaltır ama bağlantıyı düşürmez', () {
      expect(ad('%20%20PC%20'), 'PC');
      expect(ad('%zz'), '');
      expect(ad('%E0%A4%A'), '');
    });
  });

  group('SHA-256 (yeni paket eklememek için kendi gerçeklemesi)', () {
    test('NIST vektörleri', () {
      expect(hex(sha256(<int>[])), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(hex(sha256(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(hex(sha256(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(hex(sha256(Uint8List(1000000)..fillRange(0, 1000000, 0x61))), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });

    test('0..200 bayt (blok sınırları) Python hashlib ile aynı', () {
      final acc = BytesBuilder();
      for (var n = 0; n <= 200; n++) {
        acc.add(sha256(List<int>.generate(n, (i) => (i * 7 + n) % 256)));
      }
      expect(hex(sha256(acc.takeBytes())), 'e673d33f6940a6d3856d0d305fd88363ae0ba3b96e2411d8ddd5e0dd443f4525');
    });

    test('parmak izi karşılaştırması', () {
      final der = utf8.encode('sertifika');
      expect(parmakIziUyuyor(der, _f), isTrue);
      expect(parmakIziUyuyor(utf8.encode('baska'), _f), isFalse);
      expect(parmakIziUyuyor(der, _f.substring(1)), isFalse);
      expect(parmakIziUyuyor(der, ''), isFalse);
      expect(parmakIziUyuyor(der, '${_f.substring(0, 42)}${_f[42] == 'A' ? 'E' : 'A'}'), isFalse);
    });
  });

  group('hata iletileri (Türkçe, anlaşılır)', () {
    test('her ağ hatası türünün iletisi var ve token/IP sızdırmaz', () {
      for (final t in WifiHataTuru.values) {
        final m = M.wifiHata(t, 'ayrıntı');
        expect(m, isNotEmpty, reason: t.name);
        expect(m, isNot(contains(_t)), reason: t.name);
      }
      expect(M.wifiHata(WifiHataTuru.ulasilamadi), allOf(contains('aynı Wi-Fi'), contains('Misafir')));
      expect(M.wifiHata(WifiHataTuru.parmakIzi), contains('uyuşmuyor'));
      expect(M.wifiHata(WifiHataTuru.masaustuSuresiDoldu), contains('süresi doldu'));
      expect(M.wifiHata(WifiHataTuru.reddedildi), contains('reddetti'));
      expect(M.wifiHata(WifiHataTuru.surum), contains('güncelle'));
      expect(M.wifiHata(WifiHataTuru.yetkisiz), contains('kabul etmedi'));
      for (final t in WifiBaglantiHataTuru.values) {
        expect(M.wifiBaglantiHata(t), isNotEmpty);
      }
    });
  });
}
