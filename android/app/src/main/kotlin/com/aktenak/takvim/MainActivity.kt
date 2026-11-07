package com.aktenak.takvim

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.TimeZone

/**
 * Dart ile köprü (ek paket yok):
 *  - saatDilimi: cihazın IANA saat dilimi,
 *  - dizinler: uygulamaya özel veri ve geçici klasör yolları (path_provider yerine; o paket yerel JNI/NDK ister),
 *  - bekleyenDosya: "Birlikte aç / Paylaş" ile gelen .takvimsync içeriği (bir kez verilir),
 *  - dosyaGeldi (Kotlin -> Dart): uygulama açıkken yeni dosya gelirse içerik itilir,
 *  - bekleyenBaglanti / baglantiGeldi: Wi-Fi eşleştirme App Link'i (https://aktenak.tech/s#...); aynı mantık.
 *    Bağlantı yalnız metin olarak Dart'a verilir; Dart onay ekranını açar, kendiliğinden bağlanılmaz.
 *  - agTuru / kurulumIzniVar / kurulumIzniAc / apkKur: otomatik güncelleme (yalnız kullanıcı onayıyla çağrılır).
 *    apkKur yalnız kendi geçici klasöründeki, aynı paket adlı, daha yüksek sürüm kodlu APK'yı PackageInstaller
 *    oturumuyla kurar; son söz Android'in imza denetimindedir (farklı anahtarlı APK kurulmaz).
 * İçerik burada UTF-8 metne çevrilir; sınırı aşan ya da okunamayan dosya anlaşılır hata olur.
 */
class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var bekleyen: Map<String, String>? = null
    private var bekleyenBaglanti: String? = null

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
                    // Uygulamaya özel kalıcı klasör (veri) ve geçici klasör (paylaşılacak dosya).
                    "dizinler" -> sonuc.success(mapOf("veri" to filesDir.absolutePath, "gecici" to cacheDir.absolutePath))
                    "bekleyenDosya" -> {
                        dartHazir = true
                        val b = bekleyen
                        bekleyen = null
                        sonuc.success(b)
                    }
                    "bekleyenBaglanti" -> {
                        dartHazir = true
                        val b = bekleyenBaglanti
                        bekleyenBaglanti = null
                        sonuc.success(b)
                    }
                    "agTuru" -> sonuc.success(agTuru())
                    "kurulumIzniVar" -> sonuc.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                    "kurulumIzniAc" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        sonuc.success(null)
                    }
                    "apkKur" -> apkKur(cagri.arguments as? String, sonuc)
                    else -> sonuc.notImplemented()
                }
            }
        }
    }

    /** 'wifi' (ücretsiz/ölçüsüz ağ) | 'mobil' (ölçülü ağ: mobil veri, kota) | 'yok'. İndirme kararı için. */
    private fun agTuru(): String {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        if (cm.activeNetwork == null) return "yok"
        return if (cm.isActiveNetworkMetered) "mobil" else "wifi"
    }

    private fun apkKur(yol: String?, sonuc: MethodChannel.Result) {
        try {
            require(yol != null) { "yol yok" }
            val dosya = File(yol).canonicalFile
            val klasor = cacheDir.canonicalFile
            require(dosya.path.startsWith(klasor.path + File.separator) && dosya.isFile && dosya.name.endsWith(".apk")) { "APK uygulamanın geçici klasöründe değil" }
            val pm = packageManager
            val yeni = pm.getPackageArchiveInfo(dosya.path, 0) ?: throw IllegalStateException("APK okunamadı")
            require(yeni.packageName == packageName) { "paket adı farklı" }
            val mevcut = pm.getPackageInfo(packageName, 0)
            fun kod(p: android.content.pm.PackageInfo): Long =
                if (Build.VERSION.SDK_INT >= 28) p.longVersionCode else @Suppress("DEPRECATION") p.versionCode.toLong()
            require(kod(yeni) > kod(mevcut)) { "sürüm kodu daha yüksek değil" }

            val kurucu = pm.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(packageName)
            val id = kurucu.createSession(params)
            kurucu.openSession(id).use { oturum ->
                dosya.inputStream().use { girdi ->
                    oturum.openWrite("takvim.apk", 0, dosya.length()).use { cikti ->
                        girdi.copyTo(cikti)
                        oturum.fsync(cikti)
                    }
                }
                val niyet = Intent(this, KurulumAlici::class.java)
                val bayrak = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                oturum.commit(PendingIntent.getBroadcast(this, id, niyet, bayrak).intentSender)
            }
            sonuc.success(null)
        } catch (e: Exception) {
            sonuc.error("kurulum", e.message ?: e.javaClass.simpleName, null)
        }
    }

    /** Yalnız tam `https://aktenak.tech/s` ve `/s/` kabul edilir (manifest de tam yol eşler: "/sss", "/studyo" değil). */
    private fun baglantiyiVer(uri: Uri) {
        setIntent(Intent())
        val s = uri.toString()
        if (uri.scheme != "https" || !"aktenak.tech".equals(uri.host, ignoreCase = true) || (uri.path != "/s" && uri.path != "/s/") || uri.port != -1 || s.length > 2048) return
        if (dartHazir && kanal != null) kanal?.invokeMethod("baglantiGeldi", s) else bekleyenBaglanti = s
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
        if (uri.scheme == "https") {
            baglantiyiVer(uri)
            return
        }
        // Yalnız content:// kabul edilir. Manifest filtresi tek başına yetmez: açık (explicit) intent
        // filtreyi atlar ve file:// ile uygulamanın kendi özel dosyalarını (takvim.json) okutabilirdi.
        if (uri.scheme != "content") {
            setIntent(Intent())
            return
        }
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
