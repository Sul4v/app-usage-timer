package com.sodhera.capsule.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Calm, neutral palette — near-monochrome so the only saturated color on
 * screen is the usage-state green→red.
 */
private val Light = lightColorScheme(
    primary = Color(0xFF17171A),
    onPrimary = Color.White,
    background = Color(0xFFF7F7F5),
    onBackground = Color(0xFF17171A),
    surface = Color.White,
    onSurface = Color(0xFF17171A),
    surfaceVariant = Color(0xFFEFEFEC),
    onSurfaceVariant = Color(0xFF77777D),
    secondaryContainer = Color(0xFFE9E9E5),
    onSecondaryContainer = Color(0xFF17171A),
    outline = Color(0xFFDDDDD8),
)

private val Dark = darkColorScheme(
    primary = Color(0xFFF3F3F0),
    onPrimary = Color(0xFF17171A),
    background = Color(0xFF121214),
    onBackground = Color(0xFFF3F3F0),
    surface = Color(0xFF1C1C1F),
    onSurface = Color(0xFFF3F3F0),
    surfaceVariant = Color(0xFF26262A),
    onSurfaceVariant = Color(0xFF9A9AA1),
    secondaryContainer = Color(0xFF2A2A2E),
    onSecondaryContainer = Color(0xFFF3F3F0),
    outline = Color(0xFF3A3A3F),
)

object StateColors {
    val green = Color(0xFF33C759)
    val yellow = Color(0xFFFFCC00)
    val orange = Color(0xFFFF9500)
    val red = Color(0xFFFF3B30)

    /** Same stops as iOS/overlay: 0…0.5 green, →0.8 yellow, →1.0 red. */
    fun forRatio(ratio: Float): Color = when {
        ratio < 0.5f -> green
        ratio < 0.8f -> lerp(green, yellow, (ratio - 0.5f) / 0.3f)
        ratio < 1.0f -> {
            val t = (ratio - 0.8f) / 0.2f
            if (t < 0.5f) lerp(yellow, orange, t * 2) else lerp(orange, red, (t - 0.5f) * 2)
        }
        else -> red
    }

    private fun lerp(a: Color, b: Color, t: Float): Color {
        val c = t.coerceIn(0f, 1f)
        return Color(
            red = a.red + (b.red - a.red) * c,
            green = a.green + (b.green - a.green) * c,
            blue = a.blue + (b.blue - a.blue) * c,
        )
    }
}

@Composable
fun CapsuleTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) Dark else Light,
        content = content,
    )
}
