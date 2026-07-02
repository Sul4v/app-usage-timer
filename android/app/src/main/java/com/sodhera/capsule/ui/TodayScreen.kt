package com.sodhera.capsule.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sodhera.capsule.AppViewModel
import com.sodhera.capsule.data.AppDayUsage
import com.sodhera.capsule.data.TrackedApp
import com.sodhera.capsule.data.ratio
import com.sodhera.capsule.tracking.formatMinutes

@Composable
fun TodayScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    var editing by remember { mutableStateOf<TrackedApp?>(null) }

    Column(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp)
    ) {
        Spacer(Modifier.height(24.dp))
        Text("Today", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(12.dp))
        Text(
            formatMinutes(vm.today.totalSeconds / 60),
            style = MaterialTheme.typography.displayMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            "across ${vm.trackedApps.size} tracked app${if (vm.trackedApps.size == 1) "" else "s"}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))

        if (vm.trackedApps.isEmpty()) {
            EmptyHint(
                "No apps tracked yet",
                "Add apps in Settings to start seeing your time.",
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(vm.trackedApps, key = { it.id }) { app ->
                    val usage = vm.today.apps[app.id] ?: AppDayUsage()
                    TodayCard(app, usage) { editing = app }
                }
                item { Spacer(Modifier.height(16.dp)) }
            }
        }
    }

    editing?.let { app ->
        EditAppDialog(
            app = app,
            onDismiss = { editing = null },
            onSave = { updated ->
                vm.saveTrackedApps(vm.trackedApps.map { if (it.id == updated.id) updated else it })
                editing = null
            },
            onDelete = {
                vm.saveTrackedApps(vm.trackedApps.filterNot { it.id == app.id })
                editing = null
            },
        )
    }
}

@Composable
private fun TodayCard(app: TrackedApp, usage: AppDayUsage, onClick: () -> Unit) {
    val r = ratio(usage.seconds, app.limitMinutes)
    Card(Modifier.clickable(onClick = onClick)) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppMonogram(app)
                Spacer(Modifier.size(12.dp, 0.dp))
                Column(Modifier.weight(1f)) {
                    Text(app.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    Text(
                        "${usage.opens} open${if (usage.opens == 1) "" else "s"} today",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        formatMinutes(usage.minutes),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = StateColors.forRatio(r),
                    )
                    Text(
                        "of ${formatMinutes(app.limitMinutes)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(14.dp))
            UsageBar(r)
        }
    }
}

@Composable
fun EditAppDialog(
    app: TrackedApp,
    onDismiss: () -> Unit,
    onSave: (TrackedApp) -> Unit,
    onDelete: () -> Unit,
) {
    var draft by remember { mutableStateOf(app) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(app.name) },
        text = {
            Column {
                LimitEditor(draft) { draft = it }
                TextButton(onClick = onDelete) {
                    Text("Stop tracking this app", color = StateColors.red)
                }
            }
        },
        confirmButton = { TextButton(onClick = { onSave(draft) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
