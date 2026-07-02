package com.sodhera.capsule

import android.app.AppOpsManager
import android.content.Context
import android.os.Process
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sodhera.capsule.data.DayUsage
import com.sodhera.capsule.data.Store
import com.sodhera.capsule.data.TrackedApp
import com.sodhera.capsule.sync.AuthSession
import com.sodhera.capsule.sync.Supabase
import com.sodhera.capsule.sync.SyncManager
import com.sodhera.capsule.tracking.TrackingService
import kotlinx.coroutines.launch

enum class Phase { AUTH, ONBOARDING, MAIN }

class AppViewModel(private val context: Context) : ViewModel() {
    val store = Store.get(context)
    val sync = SyncManager(store)

    var session by mutableStateOf(sync.loadSession())
        private set
    var phase by mutableStateOf(initialPhase())
        private set
    var trackedApps by mutableStateOf(store.loadTrackedApps())
        private set
    var today by mutableStateOf(store.todayUsage())
        private set
    var syncError by mutableStateOf<String?>(null)

    private fun initialPhase(): Phase = when {
        sync.loadSession() == null && !store.localMode && Supabase.isConfigured -> Phase.AUTH
        !store.hasCompletedOnboarding -> Phase.ONBOARDING
        else -> Phase.MAIN
    }

    fun refresh() {
        trackedApps = store.loadTrackedApps()
        today = store.todayUsage()
    }

    fun saveTrackedApps(apps: List<TrackedApp>) {
        val old = trackedApps.associateBy { it.id }
        val stamped = apps.map {
            if (old[it.id] != it) it.copy(updatedAt = System.currentTimeMillis()) else it
        }
        store.saveTrackedApps(stamped)
        trackedApps = stamped
        maybeStartTracking()
        viewModelScope.launch { sync.syncNow(); syncError = sync.lastError }
    }

    fun maybeStartTracking() {
        if (store.hasCompletedOnboarding &&
            trackedApps.isNotEmpty() &&
            hasOverlayPermission() && hasUsagePermission()
        ) {
            TrackingService.start(context)
        }
    }

    // MARK: auth

    suspend fun signUp(email: String, password: String) {
        val s = Supabase.signUp(email, password)
        sync.saveSession(s); session = s; store.localMode = false
        advanceAfterAuth()
    }

    suspend fun signIn(email: String, password: String) {
        val s = Supabase.signIn(email, password)
        sync.saveSession(s); session = s; store.localMode = false
        advanceAfterAuth()
    }

    fun continueWithoutAccount() {
        store.localMode = true
        advanceAfterAuth()
    }

    fun signOut() {
        sync.saveSession(null); session = null; store.localMode = false
        phase = Phase.AUTH
    }

    private fun advanceAfterAuth() {
        phase = if (store.hasCompletedOnboarding) Phase.MAIN else Phase.ONBOARDING
        viewModelScope.launch { sync.syncNow(); refresh() }
    }

    fun completeOnboarding() {
        store.hasCompletedOnboarding = true
        phase = Phase.MAIN
        maybeStartTracking()
        viewModelScope.launch { sync.syncNow() }
    }

    fun syncNow() {
        viewModelScope.launch {
            sync.syncNow()
            syncError = sync.lastError
            refresh()
        }
    }

    // MARK: permissions

    fun hasOverlayPermission(): Boolean = Settings.canDrawOverlays(context)

    fun hasUsagePermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
