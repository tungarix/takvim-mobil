// Dosya seç / paylaş (file_picker + share_plus) için ince arayüz; testlerde sahtesi var.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Senkron dosyası üst sınırı (MainActivity'deki Paylaş/Birlikte aç yoluyla aynı: 16 MB).
const maksSenkronBayt = 16 * 1024 * 1024;

/// Dosyayı UTF-8 metin olarak okur; sınırı aşan dosya belleğe alınmadan reddedilir
/// (seçilen dosya yanlışlıkla çok büyük olabilir; okuma uygulamayı bellek yetersizliğiyle çökertirdi).
Future<String> sinirliOku(File dosya, {int sinir = maksSenkronBayt}) async {
  if (await dosya.length() > sinir) {
    throw FormatException('dosya çok büyük (en çok ${sinir ~/ (1024 * 1024)} MB)');
  }
  return dosya.readAsString();
}

/// Önceki paylaşımlardan kalan `.takvimsync` kopyalarını siler: her biri tüm takvimi taşır ve
/// paylaşım bitince kimse silmez. Hemen paylaşımdan sonra silinmez (alıcı uygulama dosyayı
/// geç okuyabilir), bir sonraki paylaşımda temizlenir.
Future<void> eskiSenkronDosyalariniSil(String klasor) async {
  final d = Directory(klasor);
  if (!await d.exists()) return;
  await for (final f in d.list()) {
    if (f is File && f.path.endsWith('.takvimsync')) {
      try {
        await f.delete();
      } on FileSystemException {
        // kullanımdaysa bir sonraki sefere
      }
    }
  }
}

abstract class DosyaServisi {
  /// Kullanıcıya dosya seçtirir; vazgeçerse null, aksi hâlde dosyanın metni.
  Future<String?> senkronDosyasiSec();

  /// Metni `dosyaAdi` adlı geçici dosyaya yazıp sistem Paylaş menüsünü açar.
  Future<void> paylas(String metin, String dosyaAdi);
}

class SistemDosyaServisi implements DosyaServisi {
  SistemDosyaServisi(this.geciciKlasor);

  /// Paylaşılacak dosyanın yazılacağı geçici (uygulamaya özel önbellek) klasör.
  final String geciciKlasor;

  @override
  Future<String?> senkronDosyasiSec() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    final yol = f?.path;
    if (yol == null) return null;
    try {
      return await sinirliOku(File(yol));
    } finally {
      // Seçicinin önbelleğe kopyaladığı dosya işi bitince silinir (veri kopyası kalmasın).
      await FilePicker.clearTemporaryFiles();
    }
  }

  @override
  Future<void> paylas(String metin, String dosyaAdi) async {
    await eskiSenkronDosyalariniSil(geciciKlasor);
    final dosya = File('$geciciKlasor/$dosyaAdi');
    await dosya.writeAsString(metin, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(dosya.path, mimeType: 'application/octet-stream')]));
  }
}
