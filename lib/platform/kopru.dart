// Android ile köprü: MainActivity'nin method channel'ı (ek paket yok).
//  - saatDilimi: cihazın IANA saat dilimi (DateTime.timeZoneName güvenilmez),
//  - bekleyenDosya: uygulama "Birlikte aç / Paylaş" ile .takvimsync alınarak açıldıysa içeriği,
//  - dosyaGeldi: uygulama açıkken yeni dosya gelirse Kotlin'in Dart'a göndermesi.
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
  Future<GelenDosya?> bekleyenDosya();
  void dosyaDinle(void Function(GelenDosya) f);
}

class AndroidKopru implements Kopru {
  AndroidKopru() : _kanal = const MethodChannel('com.aktenak.takvim/kopru');
  final MethodChannel _kanal;

  @override
  Future<String> saatDilimi() async => (await _kanal.invokeMethod<String>('saatDilimi')) ?? 'Europe/Istanbul';

  @override
  Future<GelenDosya?> bekleyenDosya() async => _coz(await _kanal.invokeMethod<Object?>('bekleyenDosya'));

  @override
  void dosyaDinle(void Function(GelenDosya) f) {
    _kanal.setMethodCallHandler((c) async {
      if (c.method == 'dosyaGeldi') {
        final g = _coz(c.arguments);
        if (g != null) f(g);
      }
    });
  }

  static GelenDosya? _coz(Object? o) {
    if (o is! Map) return null;
    final metin = o['metin'], hata = o['hata'];
    if (metin is String) return GelenDosya.metin(metin);
    if (hata is String) return GelenDosya.hata(hata);
    return null;
  }
}
