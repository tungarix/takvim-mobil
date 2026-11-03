// Wi-Fi eşleştirme bağlantısı: ayrıştırma ve doğrulama (takvim/docs/senkron-wifi.md §2, §4).
//
// Saf Dart (Flutter'a bağlı değil). Bağlantı güvenilmeyen girdidir (QR, yapıştırma, App Link);
// geçerli sayılmayan HER ŞEY reddedilir, kısmi sonuç verilmez. Doğrulanan bağlantıda bile
// ağ isteği ancak kullanıcı onaydan sonra başlar (bkz. lib/ui/wifi_akisi.dart).

/// En çok kabul edilen bağlantı uzunluğu (n alanı URL-kodlu 40 karakter ~360 karaktere çıkabilir).
const wifiBaglantiEnFazlaUzunluk = 1024;

/// Bilinen bağlantı sürümü; büyüğü "Takvim'i güncelle" hatasıdır.
const wifiBaglantiSurumu = 1;

enum WifiBaglantiHataTuru {
  /// Biçim bozuk: şema/ana makine/yol/alan geçersiz, ya da girdi çok uzun.
  bicimsiz,

  /// `v` bilinenden büyük.
  surumYeni,

  /// `h` geçerli bir IPv4 ama özel/yerel aralıkta değil.
  ozelOlmayanAdres,
}

class WifiBaglantiHatasi implements Exception {
  const WifiBaglantiHatasi(this.tur);
  final WifiBaglantiHataTuru tur;

  @override
  String toString() => 'WifiBaglantiHatasi($tur)';
}

/// Doğrulanmış eşleştirme bağlantısı. `toString` token'ı içermez.
class WifiBaglanti {
  const WifiBaglanti({required this.ip, required this.port, required this.token, required this.parmakIzi, required this.ad});

  final String ip;
  final int port;

  /// 32 küçük hex; bir gizlidir, ekrana/günlüğe yazılmaz.
  final String token;

  /// Sunucu sertifikası DER'inin SHA-256'sı, base64url (dolgusuz, 43 karakter).
  final String parmakIzi;

  /// Yalnız gösterim için (en çok 40 karakter, kontrol karakterleri temiz); güvenlik kararı vermez.
  final String ad;

  String get adres => '$ip:$port';

  @override
  String toString() => 'WifiBaglanti($adres)';
}

/// 10/8, 172.16/12, 192.168/16 ve link-local 169.254/16 (loopback ve genel adresler DEĞİL).
bool ozelIpv4mi(String ip) {
  final p = _ipv4(ip);
  if (p == null) return false;
  final a = p[0], b = p[1];
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

final _ipv4Desen = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// Kesin IPv4: dört sekizli, 0-255, baştaki sıfır yok ("010" bazı ayrıştırıcılarda sekizlik sayılır).
List<int>? _ipv4(String s) {
  final m = _ipv4Desen.firstMatch(s);
  if (m == null) return null;
  final p = <int>[];
  for (var i = 1; i <= 4; i++) {
    final g = m.group(i)!;
    if (g.length > 1 && g.startsWith('0')) return null;
    final n = int.parse(g);
    if (n > 255) return null;
    p.add(n);
  }
  return p;
}

final _hDesen = RegExp(r'^([0-9.]{7,15}):(\d{1,5})$');
final _tokenDesen = RegExp(r'^[0-9a-f]{32}$');
// 43 karakter base64url = 32 bayt; son karakterin alt 2 biti sıfır olmalı (kanonik kodlama).
final _parmakDesen = RegExp(r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$');
final _intDesen = RegExp(r'^\d{1,6}$');

// Gösterimde yanıltıcı olabilen yönlendirme/biçim karakterleri (RLO vb.) de temizlenir.
final _yasakAd = RegExp(r'[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]');

/// Bağlantıyı ayrıştırır ve doğrular; geçersizse [WifiBaglantiHatasi] fırlatır.
WifiBaglanti wifiBaglantiAyristir(String girdi) {
  const bicimsiz = WifiBaglantiHatasi(WifiBaglantiHataTuru.bicimsiz);
  final s = girdi.trim();
  if (s.isEmpty || s.length > wifiBaglantiEnFazlaUzunluk) throw bicimsiz;
  // Kontrol karakteri ve boşluk kodlanmadan bulunamaz; çift fragment da burada elenir.
  for (final c in s.codeUnits) {
    if (c <= 0x20 || c >= 0x7f) throw bicimsiz;
  }
  final i = s.indexOf('#');
  if (i < 0 || s.indexOf('#', i + 1) >= 0) throw bicimsiz;
  // Şema https, ana makine TAM aktenak.tech, yol TAM /s; kullanıcı bilgisi, port, sorgu yok.
  if (s.substring(0, i).toLowerCase() != 'https://aktenak.tech/s') throw bicimsiz;

  final alan = <String, String>{};
  for (final parca in s.substring(i + 1).split('&')) {
    final e = parca.indexOf('=');
    if (e <= 0) throw bicimsiz; // anahtarsız ya da "=" yok
    final anahtar = parca.substring(0, e);
    if (!const {'v', 'h', 't', 'f', 'n'}.contains(anahtar)) continue; // bilinmeyen: yok sayılır
    if (alan.containsKey(anahtar)) throw bicimsiz; // yinelenen: belirsiz
    alan[anahtar] = parca.substring(e + 1);
  }

  // Sürüm önce: yeni sürümde diğer alanlar başka biçimde olabilir.
  final v = alan['v'];
  if (v == null || !_intDesen.hasMatch(v)) throw bicimsiz;
  final surum = int.parse(v);
  if (surum > wifiBaglantiSurumu) throw const WifiBaglantiHatasi(WifiBaglantiHataTuru.surumYeni);
  if (surum < 1) throw bicimsiz;

  final h = _hDesen.firstMatch(alan['h'] ?? '');
  if (h == null) throw bicimsiz; // IPv6, ana makine adı, portsuz...
  final ip = h.group(1)!;
  final port = int.parse(h.group(2)!);
  if (_ipv4(ip) == null || port < 1 || port > 65535 || h.group(2)!.length > 1 && h.group(2)!.startsWith('0')) throw bicimsiz;
  if (!ozelIpv4mi(ip)) throw const WifiBaglantiHatasi(WifiBaglantiHataTuru.ozelOlmayanAdres);

  final t = alan['t'] ?? '', f = alan['f'] ?? '';
  if (!_tokenDesen.hasMatch(t) || !_parmakDesen.hasMatch(f)) throw bicimsiz;

  return WifiBaglanti(ip: ip, port: port, token: t, parmakIzi: f, ad: _adTemizle(alan['n'] ?? ''));
}

String _adTemizle(String kodlu) {
  String ad;
  try {
    ad = Uri.decodeComponent(kodlu);
  } on Object {
    return ''; // bozuk kodlama: ad yalnız gösterimdir, bağlantıyı düşürmez
  }
  ad = ad.replaceAll(_yasakAd, '').trim();
  final harfler = ad.runes.toList();
  if (harfler.length > 40) ad = String.fromCharCodes(harfler.take(40)).trim();
  return ad;
}
