// Güncelleyici: denetim zamanı, ETag ve bulunan sürümün saklanması + indirme/doğrulama.
// Durum `ayarlar.json`'da (kullanıcı verisi değil: bozuksa "hiç denetlenmedi" sayılır).
// Kurulum (PackageInstaller) burada DEĞİL: `Kopru.apkKur`; akışı `ui/guncelleme_akisi.dart` yönetir.
import 'dart:io';

import '../store/ayarlar.dart';
import '../sync/sha256.dart';
import 'ag.dart';
import 'saf.dart';

/// Günde en çok bir denetim. "Şimdi denetle" bu sınıra takılmaz: o, kullanıcının kendi isteği.
const denetimAraligi = Duration(hours: 24);

class Guncelleyici {
  Guncelleyici({required this.ayarlar, required this.klasor, required this.surum, Ag? ag, DateTime Function()? saat})
    : ag = ag ?? Ag(surum: surum),
      _saat = saat ?? DateTime.now;

  final Ayarlar ayarlar;

  /// İndirilen APK'nın klasörü (uygulamaya özel geçici dizin).
  final Directory klasor;
  final String surum;
  final Ag ag;
  final DateTime Function() _saat;

  /// `null` = hiç sorulmadı (ağ isteği YOK), true/false = kullanıcının seçimi.
  bool? get denetim => ayarlar.guncellemeDenetimi;

  Future<void> denetimYaz(bool acik) => ayarlar.guncellemeDenetimiYaz(acik);

  DateTime? get sonDenetim {
    final s = ayarlar.guncellemeKaydi['son_denetim'];
    if (s is! String) return null;
    final an = DateTime.tryParse(s);
    return (an != null && an.isUtc) ? an : null;
  }

  String? get hataKodu {
    final k = ayarlar.guncellemeKaydi['hata_kodu'];
    return k is String ? k : null;
  }

  /// Saklı teklif; yalnızca şimdikinden KESİN yüksek ve adresi hâlâ geçerliyse (dosya elle bozulmuş olabilir).
  Yayin? get teklif {
    final y = Yayin.fromJson(ayarlar.guncellemeKaydi['yayin']);
    if (y == null || !dahaYeniMi(y.surum, surum)) return null;
    if (!adresUygun(y.apkUrl, ag.depo, ag.ekSunucular) || !adresUygun(y.ozetUrl, ag.depo, ag.ekSunucular)) return null;
    return y;
  }

  /// Son denetimden en az 24 saat geçti mi (ya da hiç denetlenmedi mi).
  bool get denetimZamaniGeldi {
    final son = sonDenetim, simdi = _saat().toUtc();
    // Saat geriye alındıysa (son gelecekte) beklemek yerine yeniden denetle.
    return son == null || son.isAfter(simdi) || simdi.difference(son) >= denetimAraligi;
  }

  /// GitHub'a sorar ve sonucu saklar. İstisna atmaz: hata `hata_kodu` olarak saklanır (mevcut sürümle
  /// devam). Hatada da `son_denetim` yazılır: kötü ağda her açılışta yeniden denenmesin.
  Future<void> denetle() async {
    final kayit = ayarlar.guncellemeKaydi;
    final etagSakli = kayit['etag'];
    final etag = teklif != null && etagSakli is String ? etagSakli : null;
    try {
      final (sonuc, yayin, yeniEtag) = await ag.sonYayin(etag);
      kayit.remove('hata_kodu');
      if (sonuc == 'yeni' && yayin != null) {
        kayit['yayin'] = yayin.toJson();
        kayit['etag'] = yeniEtag;
      } else if (sonuc == 'yok') {
        kayit
          ..remove('yayin')
          ..remove('etag');
      }
      // "degismedi": saklı sürüm olduğu gibi kalır
    } on GuncellemeHatasi catch (e) {
      kayit['hata_kodu'] = e.kod;
    }
    kayit['son_denetim'] = _saat().toUtc().toIso8601String();
    await ayarlar.guncellemeKaydiYaz(kayit);
  }

  /// Arka plan kuralı (plan §1.1): kullanıcı denetimi açmadıysa (kapalı ya da hiç sorulmadı) ağ isteği
  /// YOK; açıksa en çok günde bir. Ağa GİTTİYSE true.
  Future<bool> otomatikAdim() async {
    if (denetim != true || !denetimZamaniGeldi) return false;
    await denetle();
    return true;
  }

  /// [y]'yi indirip DOĞRULAR; doğrulanmış APK'nın dosyasını verir. Özet bulunamaz/belirsizse ya da
  /// tutmazsa dosya silinir ve kurulum iptal olur. Önceki indirmeler önce temizlenir.
  Future<File> hazirla(Yayin y, {void Function(int alinan)? ilerleme}) async {
    await klasor.create(recursive: true);
    await for (final f in klasor.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('Takvim-')) {
        try {
          await f.delete();
        } on FileSystemException {
          // kilitli eski indirme: yenisi farklı adla iner
        }
      }
    }
    final beklenen = ozetCoz(await ag.metinIndir(y.ozetUrl), y.apkAdi);
    if (beklenen == null) throw const GuncellemeHatasi('ozet_bulunamadi', 'SHA256SUMS.txt\'te APK satırı yok/belirsiz');
    final hedef = File('${klasor.path}/${y.apkAdi}');
    final gelen = await ag.indir(y.apkUrl, hedef, y.apkBoyut, ilerleme: ilerleme);
    if (gelen != beklenen) {
      try {
        await hedef.delete();
      } on FileSystemException {
        // silinemeyen dosya kurulmaz: çağıran hata alır
      }
      throw GuncellemeHatasi('ozet_uyusmuyor', '$gelen != $beklenen');
    }
    return hedef;
  }

  /// Dosyanın SHA-256'sı (test ve kurulum öncesi yeniden doğrulama için).
  static Future<String> dosyaOzeti(File f) async {
    final ozet = Sha256Akis();
    await for (final parca in f.openRead()) {
      ozet.ekle(parca);
    }
    return onaltilik(ozet.bitir());
  }
}
