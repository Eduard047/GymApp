package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.health.HealthConnectAvailability
import com.example.gymapp.health.HealthConnectImporter
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.theme.Button
import com.example.gymapp.ui.theme.TintedButton
import com.example.gymapp.ui.viewmodel.HealthDataCardMode
import com.example.gymapp.ui.viewmodel.HealthDataUiState
import com.example.gymapp.ui.viewmodel.HealthImportNotice
import com.example.gymapp.ui.viewmodel.healthDataCardMode
import com.example.gymapp.util.formattedPluralStringResource
import com.example.gymapp.util.formattedStringResource

private const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"

/**
 * Health Connect import card on the Watches screen. Self-contained (state + callbacks). It never asks
 * for permissions by itself: the Health Connect permission screen opens only from the Connect button,
 * and [onPermissionRequestFinished] reports its return.
 */
@Composable
internal fun HealthDataCard(
    state: HealthDataUiState,
    onPermissionRequestFinished: () -> Unit,
    onImportNow: () -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val mode = healthDataCardMode(state)
    // The permission contract exists only when Health Connect can run on this phone (API 26+).
    val permissionContract = if (state.availability == HealthConnectAvailability.AVAILABLE) {
        remember { HealthConnectImporter.permissionRequestContract() }
    } else {
        null
    }
    val permissionLauncher = if (permissionContract != null) {
        rememberLauncherForActivityResult(permissionContract) { onPermissionRequestFinished() }
    } else {
        null
    }

    AppPanel(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = "",
                title = stringResource(R.string.health_data_title),
                supporting = stringResource(R.string.watches_health_capability)
            )
            when (mode) {
                HealthDataCardMode.UNAVAILABLE -> BodyText(R.string.health_data_unavailable)
                HealthDataCardMode.INSTALL_REQUIRED -> {
                    BodyText(R.string.health_data_unavailable)
                    TintedButton(
                        onClick = { openHealthConnectInstallPage(context) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                    ) {
                        Text(stringResource(R.string.health_data_install))
                    }
                }
                HealthDataCardMode.NOT_CONNECTED -> {
                    Button(
                        onClick = {
                            permissionLauncher?.launch(HealthConnectImporter.REQUIRED_PERMISSIONS)
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp),
                        elevation = null
                    ) {
                        Text(stringResource(R.string.health_data_connect))
                    }
                }
                HealthDataCardMode.IMPORTING -> BodyText(R.string.health_data_importing)
                HealthDataCardMode.CONNECTED -> {
                    val summary = connectedSummary(state)
                    if (summary.isNotEmpty()) {
                        Text(
                            text = summary,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    TintedButton(
                        onClick = onImportNow,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                    ) {
                        Text(stringResource(R.string.health_data_import_now))
                    }
                    TextButton(
                        onClick = onDisconnect,
                        modifier = Modifier.heightIn(min = 48.dp),
                        contentPadding = PaddingValues(horizontal = 0.dp),
                        colors = ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.error
                        )
                    ) {
                        Text(stringResource(R.string.health_data_disconnect))
                    }
                }
            }
            when (state.notice) {
                HealthImportNotice.EMPTY -> BodyText(R.string.health_data_empty)
                HealthImportNotice.FAILED -> BodyText(
                    R.string.health_data_failed,
                    color = MaterialTheme.colorScheme.error
                )
                HealthImportNotice.NONE -> Unit
            }
            Text(
                text = stringResource(R.string.health_data_caption),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun BodyText(
    resource: Int,
    color: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurfaceVariant
) {
    Text(
        text = stringResource(resource),
        style = MaterialTheme.typography.bodyMedium,
        color = color
    )
}

/** "Imported N workouts · last import 5 minutes ago"; without a count (or time) a shorter line. */
@Composable
private fun connectedSummary(state: HealthDataUiState): String {
    val last = state.lastImportAtMillis
    val total = state.importedTotal
    val relative = last?.let { relativeImportTime(it) }
    return when {
        relative != null && total != null ->
            formattedPluralStringResource(R.plurals.health_data_summary, total, total, relative)
        relative != null -> formattedStringResource(R.string.health_data_last_import, relative)
        else -> ""
    }
}

@Composable
private fun relativeImportTime(millis: Long): String {
    val now = System.currentTimeMillis()
    return remember(millis) {
        DateUtils.getRelativeTimeSpanString(
            millis.coerceAtMost(now),
            now,
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE
        ).toString()
    }
}

/** Opens the Health Connect page in Play Store (market:// first, the web page as fallback). */
internal fun openHealthConnectInstallPage(context: Context) {
    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$HEALTH_CONNECT_PACKAGE"))
    val web = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("https://play.google.com/store/apps/details?id=$HEALTH_CONNECT_PACKAGE")
    )
    for (intent in listOf(market, web)) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
            // Try the next target.
        }
    }
}
