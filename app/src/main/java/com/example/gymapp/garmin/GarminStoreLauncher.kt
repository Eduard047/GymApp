package com.example.gymapp.garmin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

internal data class GarminStoreLaunchTarget(
    val uri: String,
    val packageName: String?
)

internal const val GARMIN_STORE_APP_URL =
    "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f"
internal const val CONNECT_IQ_ANDROID_PACKAGE = "com.garmin.connectiq"
internal const val GOOGLE_PLAY_ANDROID_PACKAGE = "com.android.vending"
internal const val CONNECT_IQ_MARKET_URL = "market://details?id=com.garmin.connectiq"
internal const val CONNECT_IQ_GOOGLE_PLAY_URL =
    "https://play.google.com/store/apps/details?id=com.garmin.connectiq"

internal val GARMIN_STORE_LAUNCH_TARGETS = listOf(
    GarminStoreLaunchTarget(
        uri = GARMIN_STORE_APP_URL,
        packageName = CONNECT_IQ_ANDROID_PACKAGE
    ),
    GarminStoreLaunchTarget(
        uri = CONNECT_IQ_MARKET_URL,
        packageName = GOOGLE_PLAY_ANDROID_PACKAGE
    ),
    GarminStoreLaunchTarget(
        uri = CONNECT_IQ_GOOGLE_PLAY_URL,
        packageName = null
    )
)

fun openGymWorkoutTrackerInGarminStore(context: Context): Boolean {
    return GARMIN_STORE_LAUNCH_TARGETS.any { target ->
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(target.uri)).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            target.packageName?.let(::setPackage)
            if (context !is Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
