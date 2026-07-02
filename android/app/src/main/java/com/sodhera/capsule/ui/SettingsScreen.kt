package com.sodhera.capsule.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sodhera.capsule.AppViewModel
import com.sodhera.capsule.data.TrackedApp
import com.sodhera.capsule.data.installedApps
import com.sodhera.capsule.sync.Supabase
import java.text.DateFormat
import java.util.Date

@Composable
fun SettingsScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var showAddApps by remember { mutableStateOf(false) }

    Column(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp)
    ) {
        Spacer(Modifier.height(24.dp))
        Text("Settings", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(16.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Card(Modifier.clickable { showAddApps = true }) {
                    Text("Add or remove tracked apps", style = MaterialTheme.typography.bodyLarge)
                }
            }
            item {
                val ok = vm.hasUsagePermission() && vm.hasOverlayPermission()
                Card(Modifier.clickable {
                    context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                }) {
                    Column {
                        Text("Permissions", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            if (ok) "Usage access and overlay are granted."
                            else "Missing permissions — tracking can't run. Tap to open Settings.",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (ok) MaterialTheme.colorScheme.onSurfaceVariant else StateColors.red,
                        )
                    }
                }
            }
            item {
                Card {
                    Column {
                        Text("Account", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(4.dp))
                        val session = vm.session
                        when {
                            session != null -> {
                                Text(session.email, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                val last = vm.store.lastSyncAt
                                Text(
                                    "Last sync: " + if (last > 0)
                                        DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(last))
                                    else "never",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                vm.syncError?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall, color = StateColors.red)
                                }
                                Row {
                                    TextButton(onClick = { vm.syncNow() }) { Text("Sync now") }
                                    TextButton(onClick = { vm.signOut() }) {
                                        Text("Sign out", color = StateColors.red)
                                    }
                                }
                            }
                            Supabase.isConfigured -> {
                                Text(
                                    "You're using Capsule without an account. Data stays on this device.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(onClick = { vm.signOut() }) { Text("Sign in to sync") }
                            }
                            else -> Text(
                                "This build has no sync server configured — data stays on this device.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            item {
                Card {
                    Column {
                        Text("About", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Capsule 1.0.0 — the floating capsule appears over tracked apps: " +
                                "green when you're well under your limit, red once you're past it. Drag it anywhere.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }

    if (showAddApps) {
        AddAppsDialog(vm) { showAddApps = false }
    }
}

@Composable
private fun AddAppsDialog(vm: AppViewModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val apps = remember { installedApps(context) }
    var draft by remember { mutableStateOf(vm.trackedApps) }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Tracked apps") },
        text = {
            LazyColumn(Modifier.height(400.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(apps, key = { it.packageName }) { app ->
                    val selected = draft.any { it.packageName == app.packageName }
                    Row(
                        Modifier
                            .clickable {
                                draft = if (selected) draft.filterNot { it.packageName == app.packageName }
                                else draft + TrackedApp(packageName = app.packageName, name = app.name)
                            }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AppIcon(app.icon, 28)
                        Spacer(Modifier.size(10.dp, 0.dp))
                        Text(app.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        if (selected) {
                            Text("✓", color = StateColors.green, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { vm.saveTrackedApps(draft); onClose() }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("Cancel") } },
    )
}
