package com.sodhera.capsule.data

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

const val DEFAULT_LIMIT_MINUTES = 45

/** An app the user chose to track, with its daily limit. */
data class TrackedApp(
    val id: String = UUID.randomUUID().toString(),
    val packageName: String,
    val name: String,
    val limitMinutes: Int = DEFAULT_LIMIT_MINUTES,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

/** One continuous stretch of usage inside a tracked app. */
data class UsageSession(
    val startMs: Long,
    val endMs: Long,
) {
    val seconds: Int get() = ((endMs - startMs) / 1000).toInt().coerceAtLeast(0)
}

/** A single app's usage for one day. Android tracks precise seconds. */
data class AppDayUsage(
    val seconds: Int = 0,
    val opens: Int = 0,
    val sessions: List<UsageSession> = emptyList(),
    val notifiedNearLimit: Boolean = false,
    val notifiedOverLimit: Boolean = false,
) {
    val minutes: Int get() = seconds / 60
}

/** All tracked-app usage for one calendar day (key = yyyy-MM-dd local). */
data class DayUsage(
    val day: String,
    val apps: Map<String, AppDayUsage> = emptyMap(),
) {
    val totalSeconds: Int get() = apps.values.sumOf { it.seconds }
}

object DayKey {
    private val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    fun from(timeMs: Long): String = format.format(Date(timeMs))
    fun today(): String = from(System.currentTimeMillis())
    fun daysAgo(n: Int): String = from(System.currentTimeMillis() - n * 24L * 60 * 60 * 1000)
}

fun ratio(seconds: Int, limitMinutes: Int): Float =
    if (limitMinutes <= 0) 0f else seconds / 60f / limitMinutes
