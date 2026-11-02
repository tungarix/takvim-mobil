// Dosya seç / paylaş (file_picker + share_plus) için ince arayüz; testlerde sahtesi var.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

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
      return await File(yol).readAsString();
    } finally {
      // Seçicinin önbelleğe kopyaladığı dosya işi bitince silinir (veri kopyası kalmasın).
      await FilePicker.clearTemporaryFiles();
    }
  }

  @override
  Future<void> paylas(String metin, String dosyaAdi) async {
    final dosya = File('$geciciKlasor/$dosyaAdi');
    await dosya.writeAsString(metin, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(dosya.path, mimeType: 'application/octet-stream')]));
  }
}
