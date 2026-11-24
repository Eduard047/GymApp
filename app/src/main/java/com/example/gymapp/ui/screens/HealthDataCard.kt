package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
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
import java.util.Locale

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
    modifier: Modifier = Modifier,
    healthConnectSettingsIntent: () -> Intent? = { null }
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
                    BodyText(R.string.health_data_update_required)
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
                    ImportNotice(state.notice)
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
                    // Health Connect stops showing its permission screen after two declines, so the
                    // way forward is its own settings.
                    if (state.notice == HealthImportNotice.ACCESS_DENIED) {
                        TintedButton(
                            onClick = { openHealthConnectSettings(context) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                        ) {
                            Text(stringResource(R.string.health_data_open_settings))
                        }
                    }
                    // Disconnect stops the import for this account only; the Health Connect permission
                    // stays (as on iPhone), so the card offers to remove it there.
                    if (state.permissionGranted && state.notice != HealthImportNotice.ACCESS_DENIED) {
                        BodyText(R.string.health_data_permission_kept)
                        WatchCardDestructiveTextButton(
                            text = stringResource(R.string.health_data_remove_access),
                            onClick = {
                                openHealthConnectAccessSettings(context, healthConnectSettingsIntent())
                            }
                        )
                    }
                }
                // Importing keeps the connected layout (as on iPhone): the summary stays, both
                // actions are disabled and the progress sits inside "Import now".
                HealthDataCardMode.IMPORTING, HealthDataCardMode.CONNECTED -> {
                    val importing = mode == HealthDataCardMode.IMPORTING
                    val summary = connectedSummary(state)
                    if (summary.isNotEmpty()) {
                        Text(
                            text = summary,
                            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    // Right under the summary and above the actions, so a failure never reads as
                    // the description of "Disconnect".
                    if (!importing) ImportNotice(state.notice)
                    TintedButton(
                        onClick = onImportNow,
                        enabled = !importing,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                    ) {
                        if (importing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                color = LocalContentColor.current,
                                strokeWidth = 2.dp
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(stringResource(R.string.health_data_importing))
                        } else {
                            Text(stringResource(R.string.health_data_import_now))
                        }
                    }
                    WatchCardDestructiveTextButton(
                        text = stringResource(R.string.health_data_disconnect),
                        onClick = onDisconnect,
                        enabled = !importing
                    )
                }
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

/** The result of the last manual import or permission request, as the cards' inline notice. */
@Composable
private fun ImportNotice(notice: HealthImportNotice) {
    when (notice) {
        HealthImportNotice.EMPTY -> WatchCardNotice(
            text = stringResource(R.string.health_data_empty),
            isError = false
        )
        HealthImportNotice.FAILED -> WatchCardNotice(
            text = stringResource(R.string.health_data_failed),
            isError = true
        )
        HealthImportNotice.ACCESS_DENIED -> WatchCardNotice(
            text = stringResource(R.string.health_data_access_denied),
            isError = false
        )
        HealthImportNotice.NONE -> Unit
    }
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

/** In-sentence relative time: full words ("5 minutes ago"), day words in lower case ("yesterday"). */
@Composable
private fun relativeImportTime(millis: Long): String {
    val now = System.currentTimeMillis()
    return remember(millis) {
        DateUtils.getRelativeTimeSpanString(
            millis.coerceAtMost(now),
            now,
            DateUtils.MINUTE_IN_MILLIS,
            0
        ).toString().replaceFirstChar { it.lowercase(Locale.getDefault()) }
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

/**
 * Opens Health Connect where the user removes this app's access: [preferred] (the view model's
 * settings intent) first; when it is missing or nothing handles it, the [openHealthConnectSettings]
 * targets. Nothing is revoked from here; the user decides there.
 */
internal fun openHealthConnectAccessSettings(context: Context, preferred: Intent?) {
    if (preferred != null) {
        try {
            context.startActivity(preferred.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
            // Fall back to the other targets.
        } catch (_: SecurityException) {
            // Fall back to the other targets.
        }
    }
    openHealthConnectSettings(context)
}

/**
 * Opens the Health Connect permission settings: this app's page on Android 14+, otherwise the
 * Health Connect home screen. Nothing is granted from here; the user decides there.
 */
internal fun openHealthConnectSettings(context: Context) {
    val intents = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            add(
                Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
                    .putExtra(Intent.EXTRA_PACKAGE_NAME, context.packageName)
            )
            add(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))
        }
        add(Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"))
    }
    for (intent in intents) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
            // Try the next target.
        } catch (_: SecurityException) {
            // Try the next target.
        }
    }
}
