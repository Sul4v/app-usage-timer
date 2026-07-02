package com.sodhera.capsule.data

import android.content.Context
import android.content.Intent
import android.graphics.drawable.Drawable

data class InstalledApp(val packageName: String, val name: String, val icon: Drawable)

/** All launchable apps on the device (excluding ourselves), for the picker. */
fun installedApps(context: Context): List<InstalledApp> {
    val pm = context.packageManager
    val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    return pm.queryIntentActivities(intent, 0)
        .asSequence()
        .map { it.activityInfo }
        .filter { it.packageName != context.packageName }
        .distinctBy { it.packageName }
        .map {
            InstalledApp(
                packageName = it.packageName,
                name = it.loadLabel(pm).toString(),
                icon = it.loadIcon(pm),
            )
        }
        .sortedBy { it.name.lowercase() }
        .toList()
}
