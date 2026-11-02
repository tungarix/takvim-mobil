package com.aktenak.takvim

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.TimeZone

/**
 * Dart ile köprü (ek paket yok):
 *  - saatDilimi: cihazın IANA saat dilimi,
 *  - bekleyenDosya: "Birlikte aç / Paylaş" ile gelen .takvimsync içeriği (bir kez verilir),
 *  - dosyaGeldi (Kotlin -> Dart): uygulama açıkken yeni dosya gelirse içerik itilir.
 * İçerik burada UTF-8 metne çevrilir; sınırı aşan ya da okunamayan dosya anlaşılır hata olur.
 */
class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var bekleyen: Map<String, String>? = null

    // Dart ilk kez "bekleyenDosya" sorduktan sonra dinleyici hazırdır; öncesinde itme kaybolurdu.
    private var dartHazir = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Süreç yeniden yaratıldıysa aynı intent'i ikinci kez işleme.
        if (savedInstanceState == null) dosyayiOku(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dosyayiOku(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kanal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aktenak.takvim/kopru").also { k ->
            k.setMethodCallHandler { cagri, sonuc ->
                when (cagri.method) {
                    "saatDilimi" -> sonuc.success(TimeZone.getDefault().id)
                    "bekleyenDosya" -> {
                        dartHazir = true
                        val b = bekleyen
                        bekleyen = null
                        sonuc.success(b)
                    }
                    else -> sonuc.notImplemented()
                }
            }
        }
    }

    private fun dosyayiOku(i: Intent?) {
        if (i == null) return
        val uri: Uri? = when (i.action) {
            Intent.ACTION_VIEW -> i.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        val sonuc: Map<String, String> = try {
            val sinir = 16 * 1024 * 1024
            val cikti = ByteArrayOutputStream()
            contentResolver.openInputStream(uri).use { girdi ->
                if (girdi == null) throw IllegalStateException("dosya açılamadı")
                val tampon = ByteArray(64 * 1024)
                while (true) {
                    val n = girdi.read(tampon)
                    if (n < 0) break
                    cikti.write(tampon, 0, n)
                    if (cikti.size() > sinir) throw IllegalStateException("dosya çok büyük (en çok 16 MB)")
                }
            }
            mapOf("metin" to cikti.toString(Charsets.UTF_8.name()))
        } catch (e: Exception) {
            mapOf("hata" to (e.message ?: e.javaClass.simpleName))
        }
        // Aynı dosya ikinci kez (ör. ön plana dönüşte) işlenmesin.
        setIntent(Intent())
        if (dartHazir && kanal != null) kanal?.invokeMethod("dosyaGeldi", sonuc) else bekleyen = sonuc
    }
}
