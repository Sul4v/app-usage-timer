package com.sodhera.capsule.tracking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import com.sodhera.capsule.MainActivity
import com.sodhera.capsule.data.DayKey
import com.sodhera.capsule.data.Store
import com.sodhera.capsule.data.TrackedApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Foreground service that watches which app is in front (UsageStatsManager
 * events, polled once a second while the screen is on), keeps the floating
 * capsule in sync, logs sessions, and fires the near-limit/over-limit nudges.
 */
class TrackingService : Service() {

    companion object {
        private const val CHANNEL_TRACKING = "tracking"
        private const val CHANNEL_ALERTS = "alerts"
        private const val NOTIF_ID = 1

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TrackingService::class.java))
        }
    }

    // Main dispatcher: WindowManager (overlay) calls must run on a Looper
    // thread, and the per-second work is light.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loop: Job? = null
    private lateinit var store: Store
    private lateinit var overlay: OverlayCapsule
    private lateinit var usageStats: UsageStatsManager

    // Poll state
    private var lastEventQueryMs = 0L
    private var foregroundPackage: String? = null

    // Current session in a tracked app
    private var sessionApp: TrackedApp? = null
    private var sessionStartMs = 0L
    private var baseSecondsToday = 0
    private var baseDay = ""

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> endSession()
                Intent.ACTION_SCREEN_ON -> { /* loop picks it back up */ }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = Store.get(this)
        overlay = OverlayCapsule(this)
        usageStats = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        createChannels()
        registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildPersistentNotification())
        if (loop == null) {
            lastEventQueryMs = System.currentTimeMillis() - 5_000
            loop = scope.launch { runLoop() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        endSession()
        overlay.hide()
        unregisterReceiver(screenReceiver)
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // MARK: - Main loop

    private suspend fun runLoop() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        while (scope.isActive) {
            if (power.isInteractive) {
                tick()
            } else if (sessionApp != null) {
                endSession()
            }
            delay(1_000)
        }
    }

    private fun tick() {
        pollForegroundApp()
        val tracked = store.loadTrackedApps().firstOrNull { it.packageName == foregroundPackage }
        val now = System.currentTimeMillis()

        if (tracked == null) {
            if (sessionApp != null) endSession()
            return
        }

        if (sessionApp?.packageName != tracked.packageName) {
            endSession()
            startSession(tracked, now)
        }

        // Persist the running session so a crash loses at most a second,
        // and today's total stays correct across midnight (base resets).
        if (DayKey.from(now) != baseDay) startSession(tracked, now)
        store.recordSession(tracked.id, sessionStartMs, now)

        val secondsToday = baseSecondsToday + ((now - sessionStartMs) / 1000).toInt()
        val r = com.sodhera.capsule.data.ratio(secondsToday, tracked.limitMinutes)
        overlay.update(formatSecondsShort(secondsToday), StateColor.forRatio(r))
        checkMilestones(tracked, secondsToday)
    }

    private fun pollForegroundApp() {
        val now = System.currentTimeMillis()
        val events: UsageEvents = usageStats.queryEvents(lastEventQueryMs, now)
        lastEventQueryMs = now
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> foregroundPackage = event.packageName
                UsageEvents.Event.ACTIVITY_PAUSED ->
                    if (event.packageName == foregroundPackage) foregroundPackage = null
            }
        }
    }

    private fun startSession(app: TrackedApp, now: Long) {
        sessionApp = app
        sessionStartMs = now
        baseDay = DayKey.from(now)
        baseSecondsToday = store.todayUsage().apps[app.id]?.seconds ?: 0
    }

    private fun endSession() {
        val app = sessionApp ?: return
        store.recordSession(app.id, sessionStartMs, System.currentTimeMillis())
        sessionApp = null
        overlay.hide()
    }

    private fun checkMilestones(app: TrackedApp, secondsToday: Int) {
        val usage = store.todayUsage().apps[app.id] ?: return
        val limitSeconds = app.limitMinutes * 60
        if (secondsToday >= limitSeconds && !usage.notifiedOverLimit) {
            store.markNotified(app.id, overLimit = true)
            alert("${app.name}: limit reached",
                "You've used ${app.name} for ${formatMinutes(secondsToday / 60)} today — that's your ${formatMinutes(app.limitMinutes)} limit.")
        } else if (secondsToday >= limitSeconds * 0.8 && !usage.notifiedNearLimit) {
            store.markNotified(app.id, overLimit = false)
            val left = (limitSeconds - secondsToday) / 60
            alert("${app.name}: ${formatMinutes(left.coerceAtLeast(1))} left",
                "You're at ${formatMinutes(secondsToday / 60)} of your ${formatMinutes(app.limitMinutes)} daily limit.")
        }
    }

    // MARK: - Notifications

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_TRACKING, "Usage tracking", NotificationManager.IMPORTANCE_MIN)
                .apply { description = "Keeps the usage timer running" })
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERTS, "Limit alerts", NotificationManager.IMPORTANCE_DEFAULT))
    }

    private fun buildPersistentNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL_TRACKING)
            .setContentTitle("Capsule is watching your tracked apps")
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun alert(title: String, body: String) {
        val nm = getSystemService(NotificationManager::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        nm.notify(title.hashCode(), Notification.Builder(this, CHANNEL_ALERTS)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build())
    }
}
