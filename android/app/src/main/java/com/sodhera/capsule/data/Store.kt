package com.sodhera.capsule.data

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Persistence shared between the UI and the tracking service: tracked apps +
 * flags in SharedPreferences, usage history as one JSON file per day —
 * the same shape the iOS app uses, so both sync to the same tables.
 */
class Store private constructor(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("capsule", Context.MODE_PRIVATE)
    private val usageDir = File(context.filesDir, "usage").apply { mkdirs() }
    private val gson = Gson()

    companion object {
        @Volatile private var instance: Store? = null
        fun get(context: Context): Store =
            instance ?: synchronized(this) {
                instance ?: Store(context.applicationContext).also { instance = it }
            }
    }

    // MARK: tracked apps

    fun loadTrackedApps(): List<TrackedApp> {
        val json = prefs.getString("trackedApps", null) ?: return emptyList()
        val type = object : TypeToken<List<TrackedApp>>() {}.type
        return runCatching { gson.fromJson<List<TrackedApp>>(json, type) }.getOrNull() ?: emptyList()
    }

    fun saveTrackedApps(apps: List<TrackedApp>) {
        prefs.edit().putString("trackedApps", gson.toJson(apps)).apply()
    }

    // MARK: flags

    var hasCompletedOnboarding: Boolean
        get() = prefs.getBoolean("hasCompletedOnboarding", false)
        set(v) = prefs.edit().putBoolean("hasCompletedOnboarding", v).apply()

    var localMode: Boolean
        get() = prefs.getBoolean("localMode", false)
        set(v) = prefs.edit().putBoolean("localMode", v).apply()

    var authSessionJson: String?
        get() = prefs.getString("authSession", null)
        set(v) = prefs.edit().putString("authSession", v).apply()

    var lastSyncAt: Long
        get() = prefs.getLong("lastSyncAt", 0)
        set(v) = prefs.edit().putLong("lastSyncAt", v).apply()

    // MARK: usage

    @Synchronized
    fun usage(day: String): DayUsage {
        val file = File(usageDir, "$day.json")
        if (!file.exists()) return DayUsage(day)
        return runCatching { gson.fromJson(file.readText(), DayUsage::class.java) }
            .getOrNull() ?: DayUsage(day)
    }

    @Synchronized
    fun save(usage: DayUsage) {
        File(usageDir, "${usage.day}.json").writeText(gson.toJson(usage))
    }

    fun todayUsage(): DayUsage = usage(DayKey.today())

    /** Most recent [days] days, oldest first, including empty days. */
    fun history(days: Int): List<DayUsage> =
        (days - 1 downTo 0).map { usage(DayKey.daysAgo(it)) }

    /**
     * Merge a finished (or still-running) session into today's record.
     * Called by the tracking service on every tick while a tracked app is
     * open; `sessionStartMs` identifies the running session so ticks extend
     * it instead of appending duplicates.
     */
    @Synchronized
    fun recordSession(appId: String, sessionStartMs: Long, nowMs: Long) {
        val day = usage(DayKey.from(nowMs))
        val app = day.apps[appId] ?: AppDayUsage()
        val sessions = app.sessions.toMutableList()
        val last = sessions.lastOrNull()
        val isSameSession = last != null && last.startMs == sessionStartMs
        if (isSameSession) {
            sessions[sessions.size - 1] = last.copy(endMs = nowMs)
        } else {
            sessions.add(UsageSession(sessionStartMs, nowMs))
        }
        val opens = if (isSameSession) app.opens else app.opens + 1
        val seconds = sessions.sumOf { it.seconds }
        save(day.copy(apps = day.apps + (appId to app.copy(
            seconds = seconds, opens = opens, sessions = sessions))))
    }

    @Synchronized
    fun markNotified(appId: String, overLimit: Boolean) {
        val day = todayUsage()
        val app = day.apps[appId] ?: AppDayUsage()
        val updated = if (overLimit) app.copy(notifiedOverLimit = true)
                      else app.copy(notifiedNearLimit = true)
        save(day.copy(apps = day.apps + (appId to updated)))
    }
}
