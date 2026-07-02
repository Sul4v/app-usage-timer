package com.sodhera.capsule.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import com.sodhera.capsule.data.Store

/** Restart tracking after a reboot, if the user finished setup. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val store = Store.get(context)
        if (store.hasCompletedOnboarding &&
            store.loadTrackedApps().isNotEmpty() &&
            Settings.canDrawOverlays(context)
        ) {
            TrackingService.start(context)
        }
    }
}
