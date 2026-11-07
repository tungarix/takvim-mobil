package com.aktenak.takvim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * PackageInstaller oturumunun sonucunu alır (yalnız kendi uygulamamızdan, exported=false).
 * Kullanıcı onayı gerekiyorsa sistemin kurulum penceresini açar; başarıda süreç zaten yenisiyle
 * değiştirilir, hatada sistem penceresi nedenini kendisi gösterir. Dart tarafına geri bildirim yok:
 * "kurulum penceresi açıldı" noktasında uygulamanın işi biter.
 */
class KurulumAlici : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1) != PackageInstaller.STATUS_PENDING_USER_ACTION) return
        val onay: Intent? =
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
        if (onay != null) context.startActivity(onay.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
