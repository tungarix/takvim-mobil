package com.aktenak.takvim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * PackageInstaller oturumunun sonucunu alır (yalnız kendi uygulamamızdan, exported=false).
 * Kullanıcı onayı gerekiyorsa sistemin kurulum penceresini açar; diğer sonuçları (başarısızlık, imza
 * uyuşmazlığı...) uygulamaya iletir ki kullanıcı "hiçbir şey olmadı" demesin. Başarıda süreç zaten
 * yenisiyle değiştirilir.
 */
class KurulumAlici : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val durum = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (durum != PackageInstaller.STATUS_PENDING_USER_ACTION) {
            sonucDinleyici?.invoke(durum, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
            return
        }
        val onay: Intent? =
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
        // Yalnız sistemin kurulum onayı niyeti başlatılır (UnsafeIntentLaunch savunması).
        if (onay != null && onay.action == ONAY_EYLEMI) context.startActivity(onay.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    companion object {
        private const val ONAY_EYLEMI = "android.content.pm.action.CONFIRM_INSTALL"

        /** MainActivity açıkken ayarlanır; sonuç Dart'a `kurulumSonucu` olarak gider. */
        @Volatile
        var sonucDinleyici: ((Int, String?) -> Unit)? = null
    }
}
