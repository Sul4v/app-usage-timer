package com.sodhera.capsule

import android.app.Application
import android.provider.Settings
import com.sodhera.capsule.data.Store
import com.sodhera.capsule.tracking.TrackingService

class CapsuleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Resume tracking if the app process was killed and recreated.
        val store = Store.get(this)
        if (store.hasCompletedOnboarding &&
            store.loadTrackedApps().isNotEmpty() &&
            Settings.canDrawOverlays(this)
        ) {
            runCatching { TrackingService.start(this) }
        }
    }
}
