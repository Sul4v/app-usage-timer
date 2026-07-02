package com.sodhera.capsule.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sodhera.capsule.AppViewModel
import com.sodhera.capsule.data.DayUsage
import com.sodhera.capsule.data.TrackedApp
import com.sodhera.capsule.tracking.formatMinutes

@Composable
fun StatsScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    var rangeDays by remember { mutableIntStateOf(7) }
    val history = remember(rangeDays, vm.today) { vm.store.history(rangeDays) }

    Column(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp)
    ) {
        Spacer(Modifier.height(24.dp))
        Text("Stats", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(16.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(rangeDays == 7, { rangeDays = 7 },
                        SegmentedButtonDefaults.itemShape(0, 2)) { Text("Week") }
                    SegmentedButton(rangeDays == 30, { rangeDays = 30 },
                        SegmentedButtonDefaults.itemShape(1, 2)) { Text("Month") }
                }
            }
            item { SummaryRow(history) }
            item { ChartCard(history, vm.trackedApps) }
            item { AdherenceCard(history, vm.trackedApps) }
            items(vm.trackedApps, key = { it.id }) { app ->
                PerAppCard(app, history)
            }
            item { Spacer(Modifier.height(16.dp)) }
        }
    }
}

@Composable
private fun SummaryRow(history: List<DayUsage>) {
    val total = history.sumOf { it.totalSeconds } / 60
    val activeDays = history.count { it.totalSeconds > 0 }.coerceAtLeast(1)
    val opens = history.sumOf { day -> day.apps.values.sumOf { it.opens } }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StatPill(formatMinutes(total), "total", Modifier.weight(1f))
        StatPill(formatMinutes(total / activeDays), "avg / day", Modifier.weight(1f))
        StatPill("$opens", "opens", Modifier.weight(1f))
    }
}

@Composable
private fun StatPill(value: String, caption: String, modifier: Modifier = Modifier) {
    Surface(modifier, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier.padding(vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(caption, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ChartCard(history: List<DayUsage>, apps: List<TrackedApp>) {
    val limitMinutes = apps.sumOf { it.limitMinutes }
    val axisColor = MaterialTheme.colorScheme.onSurfaceVariant

    Card {
        Column {
            Text("Minutes per day", style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.height(14.dp))
            Canvas(Modifier.fillMaxWidth().height(160.dp)) {
                val maxValue = maxOf(
                    history.maxOfOrNull { it.totalSeconds / 60 } ?: 0,
                    limitMinutes,
                    1,
                ) * 1.15f
                val gap = 6f
                val barWidth = (size.width - gap * (history.size - 1)) / history.size

                history.forEachIndexed { i, day ->
                    val minutes = day.totalSeconds / 60
                    val h = (minutes / maxValue) * size.height
                    val r = if (limitMinutes > 0) minutes.toFloat() / limitMinutes else 0f
                    drawRoundRect(
                        color = StateColors.forRatio(r),
                        topLeft = Offset(i * (barWidth + gap), size.height - h),
                        size = Size(barWidth, h.coerceAtLeast(3f)),
                        cornerRadius = CornerRadius(6f, 6f),
                    )
                }
                if (limitMinutes > 0) {
                    val y = size.height - (limitMinutes / maxValue) * size.height
                    drawLine(
                        color = axisColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 2f,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f)),
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            Text(
                "dashed line = combined daily limit (${formatMinutes(limitMinutes)})",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun AdherenceCard(history: List<DayUsage>, apps: List<TrackedApp>) {
    val activeDays = history.filter { it.apps.isNotEmpty() }
    val underDays = activeDays.count { day ->
        apps.all { app -> (day.apps[app.id]?.minutes ?: 0) <= app.limitMinutes }
    }
    val pct = if (activeDays.isEmpty()) 100 else underDays * 100 / activeDays.size
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Sticking to your limits", style = MaterialTheme.typography.titleSmall)
                Text(
                    "$underDays of ${activeDays.size.coerceAtLeast(1)} days fully under limit",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                "$pct%",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                color = StateColors.forRatio(1f - pct / 100f * 0.9f),
            )
        }
    }
}

@Composable
private fun PerAppCard(app: TrackedApp, history: List<DayUsage>) {
    val minutes = history.sumOf { it.apps[app.id]?.minutes ?: 0 }
    val activeDays = history.count { (it.apps[app.id]?.seconds ?: 0) > 0 }
    val avg = if (activeDays > 0) minutes / activeDays else 0
    val sessionsToday = history.lastOrNull()?.apps?.get(app.id)?.sessions ?: emptyList()

    Card {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppMonogram(app, 36)
                Spacer(Modifier.size(12.dp, 0.dp))
                Column(Modifier.weight(1f)) {
                    Text(app.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    Text(
                        "avg ${formatMinutes(avg)} on active days",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(formatMinutes(minutes), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
            }
            if (sessionsToday.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text(
                    "Today's sessions",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val fmt = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
                sessionsToday.takeLast(6).forEach { s ->
                    Row(Modifier.padding(top = 4.dp)) {
                        Text(
                            "${fmt.format(java.util.Date(s.startMs))} – ${fmt.format(java.util.Date(s.endMs))}",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            com.sodhera.capsule.tracking.formatSecondsShort(s.seconds),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
