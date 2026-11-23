package com.example.gymapp.wear.health

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/** Runtime permissions for heart rate (and calories) during a workout. */
object WearHealthPermissions {
    const val READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"

    /** Wear OS 6 (API 36) replaced BODY_SENSORS with the granular health permission. */
    fun heartRatePermission(sdk: Int = Build.VERSION.SDK_INT): String =
        if (sdk >= 36) READ_HEART_RATE else Manifest.permission.BODY_SENSORS

    fun hasHeartRate(context: Context): Boolean =
        isGranted(context, heartRatePermission()) ||
            // A device that still honours the legacy permission is fine as well.
            isGranted(context, Manifest.permission.BODY_SENSORS)

    fun hasActivityRecognition(context: Context): Boolean =
        isGranted(context, Manifest.permission.ACTIVITY_RECOGNITION)

    /** What still has to be asked for; empty when everything is granted. */
    fun missing(context: Context): List<String> = buildList {
        if (!hasHeartRate(context)) add(heartRatePermission())
        if (!hasActivityRecognition(context)) add(Manifest.permission.ACTIVITY_RECOGNITION)
    }

    private fun isGranted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}
