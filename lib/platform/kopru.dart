// Android ile köprü: MainActivity'nin method channel'ı (ek paket yok).
//  - saatDilimi: cihazın IANA saat dilimi (DateTime.timeZoneName güvenilmez),
//  - dizinler: uygulamaya özel veri/geçici klasör (path_provider yerine: o paket yerel JNI/NDK derlemesi ister),
//  - bekleyenDosya: uygulama "Birlikte aç / Paylaş" ile .takvimsync alınarak açıldıysa içeriği,
//  - dosyaGeldi: uygulama açıkken yeni dosya gelirse Kotlin'in Dart'a göndermesi,
//  - bekleyenBaglanti / baglantiGeldi: Wi-Fi eşleştirme App Link'i (https://aktenak.tech/s#...), aynı mantık.
import 'package:flutter/services.dart';

/// Dışarıdan gelen dosya: ya metin ya da anlaşılır hata.
class GelenDosya {
  const GelenDosya.metin(String this.metin) : hata = null;
  const GelenDosya.hata(String this.hata) : metin = null;
  final String? metin;
  final String? hata;
}

abstract class Kopru {
  Future<String> saatDilimi();
  Future<({String veri, String gecici})> dizinler();
  Future<GelenDosya?> bekleyenDosya();
  void dosyaDinle(void Function(GelenDosya) f);
  Future<String?> bekleyenBaglanti();
  void baglantiDinle(void Function(String) f);
}

class AndroidKopru implements Kopru {
  AndroidKopru() : _kanal = const MethodChannel('com.aktenak.takvim/kopru');
  final MethodChannel _kanal;

  @override
  Future<String> saatDilimi() async => (await _kanal.invokeMethod<String>('saatDilimi')) ?? 'Europe/Istanbul';

  @override
  Future<({String veri, String gecici})> dizinler() async {
    final m = await _kanal.invokeMapMethod<String, String>('dizinler');
    return (veri: m!['veri']!, gecici: m['gecici']!);
  }

  @override
  Future<GelenDosya?> bekleyenDosya() async => _coz(await _kanal.invokeMethod<Object?>('bekleyenDosya'));

  void Function(GelenDosya)? _dosyaF;
  void Function(String)? _baglantiF;

  // Tek işleyici iki olayı da dinler (setMethodCallHandler yenisi eskisini siler).
  void _isleyiciKur() => _kanal.setMethodCallHandler((c) async {
        if (c.method == 'dosyaGeldi') {
          final g = _coz(c.arguments);
          if (g != null) _dosyaF?.call(g);
        } else if (c.method == 'baglantiGeldi' && c.arguments is String) {
          _baglantiF?.call(c.arguments as String);
        }
      });

  @override
  void dosyaDinle(void Function(GelenDosya) f) {
    _dosyaF = f;
    _isleyiciKur();
  }

  @override
  Future<String?> bekleyenBaglanti() => _kanal.invokeMethod<String>('bekleyenBaglanti');

  @override
  void baglantiDinle(void Function(String) f) {
    _baglantiF = f;
    _isleyiciKur();
  }

  static GelenDosya? _coz(Object? o) {
    if (o is! Map) return null;
    final metin = o['metin'], hata = o['hata'];
    if (metin is String) return GelenDosya.metin(metin);
    if (hata is String) return GelenDosya.hata(hata);
    return null;
  }
}
