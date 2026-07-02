package com.sodhera.capsule.ui

import android.content.Intent
import android.graphics.drawable.Drawable
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sodhera.capsule.AppViewModel
import com.sodhera.capsule.data.DEFAULT_LIMIT_MINUTES
import com.sodhera.capsule.data.TrackedApp
import com.sodhera.capsule.data.installedApps
import com.sodhera.capsule.tracking.formatMinutes

@Composable
fun OnboardingScreen(vm: AppViewModel) {
    var step by remember { mutableIntStateOf(0) }
    var draft by remember { mutableStateOf(vm.trackedApps) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(24.dp)
    ) {
        // Progress dots
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(4) { i ->
                Spacer(
                    Modifier
                        .weight(1f)
                        .height(4.dp)
                        .background(
                            if (i <= step) MaterialTheme.colorScheme.onBackground
                            else MaterialTheme.colorScheme.onBackground.copy(alpha = 0.12f),
                            CircleShape,
                        )
                )
            }
        }
        Spacer(Modifier.height(24.dp))

        when (step) {
            0 -> Welcome { step = 1 }
            1 -> Permissions(vm) { step = 2 }
            2 -> PickApps(vm, draft, onChange = { draft = it }) { step = 3 }
            3 -> Limits(draft, onChange = { draft = it }) {
                vm.saveTrackedApps(draft)
                vm.completeOnboarding()
            }
        }
    }
}

@Composable
private fun Welcome(onNext: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Text(
            "A gentle timer for the apps that eat your day",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Spacer(Modifier.height(12.dp))
        Text(
            "Pick the apps you want to be conscious of. Whenever you use one, a small floating capsule keeps count — green while you're fine, red when you've had enough.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(0.3f, 0.75f, 1.1f).forEach { r ->
                Row(
                    Modifier
                        .background(MaterialTheme.colorScheme.surface, CircleShape)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Spacer(Modifier.size(8.dp).background(StateColors.forRatio(r), CircleShape))
                    Spacer(Modifier.size(8.dp, 0.dp))
                    Text(
                        formatMinutes((r * 40).toInt()),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Button(
            onClick = onNext,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = CircleShape,
        ) { Text("Set it up") }
    }
}

@Composable
private fun Permissions(vm: AppViewModel, onNext: () -> Unit) {
    val context = LocalContext.current
    var tick by remember { mutableIntStateOf(0) }
    // Re-check when returning from Settings.
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()) { tick++ }
    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { tick++ }

    val hasUsage = remember(tick) { vm.hasUsagePermission() }
    val hasOverlay = remember(tick) { vm.hasOverlayPermission() }

    Column(Modifier.fillMaxSize()) {
        Text("Two permissions", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text(
            "Android needs your explicit OK for an app to see usage time and to float a timer over other apps. Both live in system Settings.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))

        PermissionRow(
            title = "Usage access",
            body = "Lets Capsule measure how long tracked apps are open.",
            granted = hasUsage,
        ) {
            launcher.launch(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }
        Spacer(Modifier.height(10.dp))
        PermissionRow(
            title = "Display over other apps",
            body = "Lets the floating capsule appear while you use them.",
            granted = hasOverlay,
        ) {
            launcher.launch(Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")))
        }
        Spacer(Modifier.height(10.dp))
        PermissionRow(
            title = "Notifications",
            body = "One quiet heads-up near and at your limit.",
            granted = androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.POST_NOTIFICATIONS
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED,
        ) {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                notifLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        Spacer(Modifier.weight(1f))
        Button(
            onClick = onNext,
            enabled = hasUsage && hasOverlay,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = CircleShape,
        ) { Text("Continue") }
        TextButton(onClick = onNext, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text("Skip for now", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PermissionRow(title: String, body: String, granted: Boolean, onClick: () -> Unit) {
    Card(Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(
                    body,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (granted) {
                Icon(Icons.Filled.CheckCircle, null, tint = StateColors.green)
            } else {
                Icon(Icons.Outlined.Circle, null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PickApps(
    vm: AppViewModel,
    draft: List<TrackedApp>,
    onChange: (List<TrackedApp>) -> Unit,
    onNext: () -> Unit,
) {
    val context = LocalContext.current
    val apps = remember { installedApps(context) }

    Column(Modifier.fillMaxSize()) {
        Text("Which apps?", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
        Text(
            "Pick the apps you want to keep an eye on.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(apps, key = { it.packageName }) { app ->
                val selected = draft.any { it.packageName == app.packageName }
                Card(Modifier.clickable {
                    onChange(
                        if (selected) draft.filterNot { it.packageName == app.packageName }
                        else draft + TrackedApp(packageName = app.packageName, name = app.name)
                    )
                }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        AppIcon(app.icon)
                        Spacer(Modifier.size(12.dp, 0.dp))
                        Text(app.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        if (selected) Icon(Icons.Filled.CheckCircle, null, tint = StateColors.green)
                        else Icon(Icons.Outlined.Circle, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = onNext,
            enabled = draft.isNotEmpty(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = CircleShape,
        ) { Text("Continue") }
    }
}

@Composable
fun AppIcon(drawable: Drawable, size: Int = 36) {
    Image(
        bitmap = drawable.toBitmap(96, 96).asImageBitmap(),
        contentDescription = null,
        modifier = Modifier.size(size.dp),
    )
}

@Composable
private fun Limits(
    draft: List<TrackedApp>,
    onChange: (List<TrackedApp>) -> Unit,
    onDone: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Text("Daily limits", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
        Text(
            "How much is enough? $DEFAULT_LIMIT_MINUTES minutes is a sensible default — adjust anytime.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(draft, key = { it.id }) { app ->
                LimitEditor(app) { updated ->
                    onChange(draft.map { if (it.id == updated.id) updated else it })
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = CircleShape,
        ) { Text("Start tracking") }
    }
}

@Composable
fun LimitEditor(app: TrackedApp, onChange: (TrackedApp) -> Unit) {
    Card {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppMonogram(app, 36)
                Spacer(Modifier.size(12.dp, 0.dp))
                Text(app.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Text(
                    formatMinutes(app.limitMinutes),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Slider(
                value = app.limitMinutes.toFloat(),
                onValueChange = { onChange(app.copy(limitMinutes = (it / 5).toInt() * 5)) },
                valueRange = 5f..240f,
                colors = SliderDefaults.colors(
                    thumbColor = MaterialTheme.colorScheme.onBackground,
                    activeTrackColor = MaterialTheme.colorScheme.onBackground,
                ),
            )
        }
    }
}
