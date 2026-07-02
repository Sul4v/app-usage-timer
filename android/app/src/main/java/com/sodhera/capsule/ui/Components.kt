package com.sodhera.capsule.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sodhera.capsule.data.TrackedApp

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Box(Modifier.padding(18.dp)) { content() }
    }
}

/** In-app usage bar, same color language as the floating capsule. */
@Composable
fun UsageBar(ratio: Float, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(6.dp)
            .background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f), CircleShape)
    ) {
        Box(
            Modifier
                .fillMaxWidth(ratio.coerceIn(0.015f, 1f))
                .fillMaxHeight()
                .background(StateColors.forRatio(ratio), CircleShape)
        )
    }
}

/** Neutral monogram circle (used where we don't render the real icon). */
@Composable
fun AppMonogram(app: TrackedApp, size: Int = 40) {
    Box(
        Modifier
            .size(size.dp)
            .background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            app.name.take(1).uppercase(),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
fun EmptyHint(title: String, body: String, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(
            body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

val CapsuleGreen = Color(0xFF33C759)
