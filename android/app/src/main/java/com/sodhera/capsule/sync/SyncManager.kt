package com.sodhera.capsule.sync

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.sodhera.capsule.data.Store
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Push tracked apps + recent usage, pull limit/name edits made on other
 * devices (last-write-wins by updated_at). Same tables as the iOS app;
 * Android rows carry platform "android" and the real package name.
 */
class SyncManager(private val store: Store) {
    private val gson = Gson()
    private val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    var lastError: String? = null
        private set

    fun loadSession(): AuthSession? =
        store.authSessionJson?.let { runCatching { gson.fromJson(it, AuthSession::class.java) }.getOrNull() }

    fun saveSession(session: AuthSession?) {
        store.authSessionJson = session?.let { gson.toJson(it) }
    }

    private suspend fun validSession(): AuthSession? {
        val current = loadSession() ?: return null
        if (current.expiresAtMs > System.currentTimeMillis() + 60_000) return current
        return runCatching { Supabase.refresh(current) }
            .onSuccess { saveSession(it) }
            .getOrNull()
    }

    private data class TrackedAppRow(
        val id: String, val user_id: String, val platform: String,
        val package_name: String?, val nickname: String, val limit_minutes: Int,
        val created_at: String, val updated_at: String,
    )

    private data class SessionDto(val start: String, val end: String)

    private data class DailyUsageRow(
        val user_id: String, val app_id: String, val day: String,
        val minutes: Int, val opens: Int, val sessions: List<SessionDto>,
    )

    suspend fun syncNow(): Boolean {
        val session = validSession() ?: return false
        return try {
            pullApps(session)
            pushApps(session)
            pushUsage(session)
            store.lastSyncAt = System.currentTimeMillis()
            lastError = null
            true
        } catch (e: Exception) {
            lastError = e.message
            false
        }
    }

    private suspend fun pushApps(session: AuthSession) {
        val rows = store.loadTrackedApps().map {
            TrackedAppRow(
                id = it.id.lowercase(), user_id = session.userId, platform = "android",
                package_name = it.packageName, nickname = it.name, limit_minutes = it.limitMinutes,
                created_at = iso.format(Date(it.createdAt)), updated_at = iso.format(Date(it.updatedAt)),
            )
        }
        if (rows.isNotEmpty()) {
            Supabase.upsert("tracked_apps", gson.toJson(rows), session, onConflict = "id")
        }
    }

    private suspend fun pullApps(session: AuthSession) {
        val json = Supabase.select(
            "tracked_apps",
            "user_id=eq.${session.userId}&platform=eq.android", session)
        val type = object : TypeToken<List<TrackedAppRow>>() {}.type
        val remote: List<TrackedAppRow> = gson.fromJson(json, type) ?: return
        val apps = store.loadTrackedApps().toMutableList()
        var changed = false
        for (row in remote) {
            val i = apps.indexOfFirst { it.id.equals(row.id, ignoreCase = true) }
            if (i < 0) continue
            val remoteUpdated = runCatching { iso.parse(row.updated_at)?.time }.getOrNull() ?: continue
            if (remoteUpdated > apps[i].updatedAt) {
                apps[i] = apps[i].copy(
                    name = row.nickname, limitMinutes = row.limit_minutes, updatedAt = remoteUpdated)
                changed = true
            }
        }
        if (changed) store.saveTrackedApps(apps)
    }

    private suspend fun pushUsage(session: AuthSession) {
        val rows = mutableListOf<DailyUsageRow>()
        for (day in store.history(7)) {
            for ((appId, usage) in day.apps) {
                if (usage.seconds <= 0) continue
                rows.add(DailyUsageRow(
                    user_id = session.userId, app_id = appId.lowercase(), day = day.day,
                    minutes = usage.minutes, opens = usage.opens,
                    sessions = usage.sessions.map {
                        SessionDto(iso.format(Date(it.startMs)), iso.format(Date(it.endMs)))
                    },
                ))
            }
        }
        if (rows.isNotEmpty()) {
            Supabase.upsert("daily_usage", gson.toJson(rows), session, onConflict = "user_id,app_id,day")
        }
    }
}
