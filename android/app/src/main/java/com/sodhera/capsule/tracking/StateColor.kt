package com.sodhera.capsule.tracking

import android.graphics.Color

/**
 * Shared green→yellow→red color ramp (same stops as iOS):
 * 0…0.5 green, 0.5…0.8 green→yellow, 0.8…1.0 yellow→red, ≥1 red.
 */
object StateColor {
    val GREEN = Color.rgb(51, 199, 89)
    val YELLOW = Color.rgb(255, 204, 0)
    val ORANGE = Color.rgb(255, 149, 0)
    val RED = Color.rgb(255, 59, 48)

    fun forRatio(ratio: Float): Int = when {
        ratio < 0.5f -> GREEN
        ratio < 0.8f -> blend(GREEN, YELLOW, (ratio - 0.5f) / 0.3f)
        ratio < 1.0f -> {
            val t = (ratio - 0.8f) / 0.2f
            if (t < 0.5f) blend(YELLOW, ORANGE, t * 2) else blend(ORANGE, RED, (t - 0.5f) * 2)
        }
        else -> RED
    }

    private fun blend(a: Int, b: Int, t: Float): Int {
        val c = t.coerceIn(0f, 1f)
        return Color.rgb(
            (Color.red(a) + (Color.red(b) - Color.red(a)) * c).toInt(),
            (Color.green(a) + (Color.green(b) - Color.green(a)) * c).toInt(),
            (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * c).toInt(),
        )
    }
}

fun formatMinutes(minutes: Int): String = when {
    minutes < 60 -> "${minutes}m"
    minutes % 60 == 0 -> "${minutes / 60}h"
    else -> "${minutes / 60}h ${minutes % 60}m"
}

fun formatSecondsShort(seconds: Int): String =
    if (seconds < 60) "${seconds}s" else formatMinutes(seconds / 60)
