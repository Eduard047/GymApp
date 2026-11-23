package com.example.gymapp.ui.screens

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.GymModalBottomSheet
import com.example.gymapp.ui.theme.Button
import com.example.gymapp.ui.theme.GymSpacing

/**
 * Flip to true once the HealthApp Google Play listing is public (production access approved and the
 * store page resolves). While false the "Our apps" Profile group is not shown at all. This is the
 * only switch; nothing else needs to change.
 */
internal const val HEALTH_APP_PLAY_LISTING_PUBLIC = false

internal const val HEALTH_APP_ANDROID_PACKAGE = "com.eduard.healthapp"
internal const val HEALTH_APP_MARKET_URL = "market://details?id=com.eduard.healthapp"
internal const val HEALTH_APP_GOOGLE_PLAY_URL =
    "https://play.google.com/store/apps/details?id=com.eduard.healthapp"
private const val GOOGLE_PLAY_PACKAGE = "com.android.vending"

internal data class HealthAppStoreTarget(val uri: String, val packageName: String?)

/** The Play app first, then the web listing when the Play app is missing. */
internal val HEALTH_APP_STORE_TARGETS = listOf(
    HealthAppStoreTarget(uri = HEALTH_APP_MARKET_URL, packageName = GOOGLE_PLAY_PACKAGE),
    HealthAppStoreTarget(uri = HEALTH_APP_GOOGLE_PLAY_URL, packageName = null)
)

/** Opens the HealthApp store listing; returns false (and does nothing visible) when no handler exists. */
internal fun openHealthAppInGooglePlay(context: Context): Boolean {
    return HEALTH_APP_STORE_TARGETS.any { target ->
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

/**
 * Explains why the owner's other app is worth a look. The store opens only from the primary button;
 * "Not now" and a swipe-away just close the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HealthAppRecommendationSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    GymModalBottomSheet(onDismissRequest = onDismiss, skipPartiallyExpanded = true) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GymSpacing.XLarge)
                .padding(bottom = GymSpacing.XXLarge),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
        ) {
            Text(
                text = stringResource(R.string.health_app_sheet_title),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.semantics { heading() }
            )
            Text(
                text = stringResource(R.string.health_app_sheet_lead),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HealthAppBenefit(Icons.Outlined.Bedtime, stringResource(R.string.health_app_benefit_sleep))
            HealthAppBenefit(Icons.Outlined.MonitorHeart, stringResource(R.string.health_app_benefit_hrv))
            HealthAppBenefit(Icons.AutoMirrored.Outlined.TrendingUp, stringResource(R.string.health_app_benefit_sources))
            Text(
                text = stringResource(R.string.health_app_sheet_footnote),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(
                onClick = {
                    openHealthAppInGooglePlay(context)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
            ) {
                Text(stringResource(R.string.health_app_sheet_open_store))
            }
            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
            ) {
                Text(stringResource(R.string.health_app_sheet_not_now))
            }
        }
    }
}

@Composable
private fun HealthAppBenefit(icon: ImageVector, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GymSpacing.Large)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Text(text = text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
    }
}
