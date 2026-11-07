// Güncelleme mantığının SAF kısmı: sürüm karşılaştırma, release çözümleme, özet ayrıştırma.
// Ağ ve dosya yok; kurallar masaüstü uygulamayla (takvim/guncelleme/saf.py) aynıdır ve
// takvim/docs/guncelleme.md'de yazılıdır. Güvenlik kararları (hangi adres, hangi ad, hangi boyut) burada.
const apkEnFazlaBayt = 150 * 1024 * 1024;

/// Yalnızca GitHub: API, release sayfası ve varlıkların yönlendirildiği depolama.
const izinliSunucular = {
  'api.github.com',
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

final _surum = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');
final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// `v0.4.0` / `0.4.0` -> (0, 4, 0). Yalnız düz X.Y.Z: "0.4.0-beta" ya da "0.4" tanınmaz,
/// çünkü yalnızca kararlı sürüm teklif edilir.
(int, int, int)? surumCoz(Object? metin) {
  if (metin is! String) return null;
  final m = _surum.firstMatch(metin.trim());
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// [aday] KESİN daha yüksekse true (sayısal: 0.10.0 > 0.9.0). Eşit/eski/çözülemeyen = false.
bool dahaYeniMi(String aday, String mevcut) {
  final a = surumCoz(aday), m = surumCoz(mevcut);
  if (a == null || m == null) return false;
  if (a.$1 != m.$1) return a.$1 > m.$1;
  if (a.$2 != m.$2) return a.$2 > m.$2;
  return a.$3 > m.$3;
}

/// GitHub'daki "Latest" sürümden uygulamanın ihtiyacı olan kısım.
class Yayin {
  const Yayin({required this.surum, required this.apkUrl, required this.apkBoyut, required this.ozetUrl, required this.sayfaUrl});

  final String surum; // "0.4.0" (başında v yok)
  final String apkUrl;
  final int apkBoyut;
  final String ozetUrl;
  final String sayfaUrl;

  /// APK varlığının beklenen adı (yayın hattı sözleşmesi): `Takvim-<sürüm>.apk`.
  String get apkAdi => 'Takvim-$surum.apk';

  Map<String, Object?> toJson() => {'surum': surum, 'apk_url': apkUrl, 'apk_boyut': apkBoyut, 'ozet_url': ozetUrl, 'sayfa_url': sayfaUrl};

  /// Saklı kayıt elle bozulmuş olabilir: tip ve alan denetimi, bozuksa null.
  static Yayin? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['surum'], a = j['apk_url'], b = j['apk_boyut'], o = j['ozet_url'], p = j['sayfa_url'];
    if (s is! String || a is! String || b is! int || o is! String || p is! String) return null;
    if (surumCoz(s) == null || b <= 0 || b > apkEnFazlaBayt) return null;
    return Yayin(surum: s, apkUrl: a, apkBoyut: b, ozetUrl: o, sayfaUrl: p);
  }
}

/// https + izinli sunucu; github.com'da yol bu deponun release'i olmalı.
/// [ekSunucular] yalnız testler içindir (yerel sahte sunucu, http de olur); üretimde boş.
bool adresUygun(Object? url, String depo, Set<String> ekSunucular) {
  if (url is! String) return false;
  final Uri u;
  try {
    u = Uri.parse(url);
  } on FormatException {
    return false;
  }
  final sunucu = u.host.toLowerCase();
  if (ekSunucular.contains(sunucu)) return u.scheme == 'http' || u.scheme == 'https';
  if (u.scheme != 'https' || !izinliSunucular.contains(sunucu) || u.userInfo.isNotEmpty) return false;
  if (sunucu == 'github.com') return u.path.startsWith('/$depo/releases/');
  return true;
}

/// `releases/latest` JSON'unu doğrular; uygun değilse null (sessizce teklif yok).
/// Reddedilenler: sözlük olmayan gövde, taslak/ön sürüm, düz X.Y.Z olmayan etiket, beklenen adlı
/// APK (`Takvim-<sürüm>.apk`) ya da `SHA256SUMS.txt` eksikliği, sıfır/aşırı büyük boyut, izinsiz adres.
Yayin? yayinCoz(Object? veri, String depo, {Set<String> ekSunucular = const {}}) {
  if (veri is! Map || veri['draft'] == true || veri['prerelease'] == true) return null;
  final sayi = surumCoz(veri['tag_name']);
  if (sayi == null) return null;
  final surum = '${sayi.$1}.${sayi.$2}.${sayi.$3}';
  final varliklar = veri['assets'];
  if (varliklar is! List) return null;
  final apkAdi = 'Takvim-$surum.apk';
  Map? apk, ozet;
  for (final v in varliklar) {
    if (v is! Map) continue;
    // Aynı adlı ikinci varlık yok sayılır (ilk eşleşme).
    if (v['name'] == apkAdi) apk ??= v;
    if (v['name'] == 'SHA256SUMS.txt') ozet ??= v;
  }
  if (apk == null || ozet == null) return null;
  final boyut = apk['size'];
  if (boyut is! int || boyut <= 0 || boyut > apkEnFazlaBayt) return null;
  final apkUrl = apk['browser_download_url'], ozetUrl = ozet['browser_download_url'];
  if (!adresUygun(apkUrl, depo, ekSunucular) || !adresUygun(ozetUrl, depo, ekSunucular)) return null;
  final sayfa = veri['html_url'];
  return Yayin(
    surum: surum,
    apkUrl: apkUrl as String,
    apkBoyut: boyut,
    ozetUrl: ozetUrl as String,
    sayfaUrl: adresUygun(sayfa, depo, ekSunucular) ? sayfa as String : 'https://github.com/$depo/releases',
  );
}

/// `SHA256SUMS.txt` içinden [ad] dosyasının küçük harfli SHA-256'sı. Biçim `sha256sum`'unki:
/// `<64 hex>  <ad>` (ikinci ayraç ` *` de olabilir). Aynı ad iki kez geçerse belirsizlik güvenli
/// değildir: null.
String? ozetCoz(String metin, String ad) {
  final bulunan = <String>[];
  for (final satir in metin.split('\n')) {
    final t = satir.trim();
    final bosluk = t.indexOf(RegExp(r'\s'));
    if (bosluk < 0) continue;
    final hash = t.substring(0, bosluk);
    var dosya = t.substring(bosluk).trim();
    if (dosya.startsWith('*')) dosya = dosya.substring(1).trim();
    if (dosya == ad && _hex64.hasMatch(hash)) bulunan.add(hash.toLowerCase());
  }
  return bulunan.length == 1 ? bulunan.first : null;
}
