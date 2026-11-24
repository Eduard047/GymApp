package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.garmin.GarminDeviceUiState
import com.example.gymapp.garmin.garminDeviceOffersConnect
import com.example.gymapp.garmin.openGymWorkoutTrackerInGarminStore
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.Button
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.theme.TintedButton
import com.example.gymapp.ui.viewmodel.HealthDataUiState
import com.example.gymapp.ui.viewmodel.WearWatchUiState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private const val GARMIN_CONNECT_PACKAGE = "com.garmin.android.apps.connectmobile"

/**
 * The Watches screen pushed from Profile: every watch connection in one place. Order: Garmin, Wear OS
 * (hidden without the Google Play services Wearable API), then Health data (Health Connect). The Profile root only shows a one-line status for it. The screen
 * keeps no connection state itself; foreground auto-import still runs from the navigation graph.
 */
@Composable
internal fun WatchesScreen(
    garminDeviceState: GarminDeviceUiState,
    healthDataState: HealthDataUiState?,
    wearWatchState: WearWatchUiState?,
    onOpened: () -> Unit,
    onResetGarminPairing: suspend () -> Boolean,
    onPairGarminDevice: suspend (deviceId: Long) -> Boolean,
    onHealthPermissionRequestFinished: () -> Unit,
    onHealthImportNow: () -> Unit,
    onHealthDisconnect: () -> Unit,
    onUnlinkWearWatch: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    // Outcome of the last reset started here: null until one finishes, then shown on the Garmin card.
    var garminResetSucceeded by rememberSaveable { mutableStateOf<Boolean?>(null) }
    var garminResetRunning by remember { mutableStateOf(false) }
    val resetScope = rememberCoroutineScope()
    // Opening the screen refreshes every source so the cards never show a stale connection.
    LaunchedEffect(Unit) { onOpened() }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.Small,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        )
    ) {
        item {
            GarminDeviceCard(
                state = garminDeviceState,
                resetSucceeded = garminResetSucceeded,
                onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) },
                onResetGarminPairing = { showGarminResetConfirmation = true },
                onPairGarminDevice = onPairGarminDevice
            )
        }
        // Wear OS, between Garmin and Health data; the card hides itself without the Wearable API.
        if (wearWatchState != null) {
            item {
                WearWatchCard(
                    state = wearWatchState,
                    onUnlink = onUnlinkWearWatch,
                    modifier = Modifier.padding(top = GymSpacing.Medium)
                )
            }
        }
        if (healthDataState != null) {
            item {
                HealthDataCard(
                    state = healthDataState,
                    onPermissionRequestFinished = onHealthPermissionRequestFinished,
                    onImportNow = onHealthImportNow,
                    onDisconnect = onHealthDisconnect,
                    modifier = Modifier.padding(top = GymSpacing.Medium)
                )
            }
        }
    }

    if (showGarminResetConfirmation) {
        GymAlertDialog(
            onDismissRequest = { showGarminResetConfirmation = false },
            title = stringResource(R.string.garmin_reset_pairing_title),
            text = { Text(stringResource(R.string.garmin_reset_pairing_description)) },
            confirmButton = {
                GymAlertDialogButton(
                    onClick = {
                        showGarminResetConfirmation = false
                        if (!garminResetRunning) {
                            garminResetRunning = true
                            garminResetSucceeded = null
                            resetScope.launch {
                                try {
                                    // The reset needs the trusted watch; its result is shown on the card.
                                    garminResetSucceeded = try {
                                        onResetGarminPairing()
                                    } catch (error: CancellationException) {
                                        throw error
                                    } catch (_: Exception) {
                                        false
                                    }
                                } finally {
                                    garminResetRunning = false
                                }
                            }
                        }
                    },
                    role = GymAlertDialogButtonRole.Destructive
                ) {
                    Text(stringResource(R.string.garmin_reset_pairing_confirm))
                }
            },
            dismissButton = {
                GymAlertDialogButton(
                    onClick = { showGarminResetConfirmation = false },
                    role = GymAlertDialogButtonRole.Cancel
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

/**
 * The cards' rare destructive action (reset, unpair, disconnect): a low-emphasis red text button.
 * It keeps a 48dp touch target but reports a smaller height, so the column's 12dp rhythm is not
 * doubled around the label; the label lines up with the card text and wraps without being clipped.
 */
@Composable
internal fun WatchCardDestructiveTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .offset(x = -DestructiveTextButtonInset)
            .trimVerticalTouchSlack(10.dp)
            .heightIn(min = 48.dp),
        shape = RoundedCornerShape(12.dp),
        contentPadding = PaddingValues(horizontal = DestructiveTextButtonInset, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = MaterialTheme.colorScheme.error
        )
    ) {
        Text(text)
    }
}

private val DestructiveTextButtonInset = 8.dp

/** Reports [slack] less height above and below while the content keeps its full size (and target). */
private fun Modifier.trimVerticalTouchSlack(slack: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val trim = slack.roundToPx().coerceAtMost(placeable.height / 4)
    layout(placeable.width, placeable.height - trim * 2) { placeable.place(0, -trim) }
}

/** Inline status inside a watch card: a flat tinted row with an icon, for errors and hints. */
@Composable
internal fun WatchCardNotice(
    text: String,
    isError: Boolean,
    modifier: Modifier = Modifier
) {
    val tint = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(tint.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = if (isError) Icons.Outlined.ErrorOutline else Icons.Outlined.Info,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = if (isError) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f)
        )
    }
}

private fun isGarminConnectInstalled(context: Context): Boolean = try {
    context.packageManager.getPackageInfo(GARMIN_CONNECT_PACKAGE, 0)
    true
} catch (_: PackageManager.NameNotFoundException) {
    false
}

/** Opens the Garmin Connect page in Play Store (market:// first, the web page as fallback). */
private fun openGarminConnectInstallPage(context: Context) {
    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$GARMIN_CONNECT_PACKAGE"))
    val web = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("https://play.google.com/store/apps/details?id=$GARMIN_CONNECT_PACKAGE")
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

@Composable
private fun GarminDeviceCard(
    state: GarminDeviceUiState,
    resetSucceeded: Boolean?,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit,
    onPairGarminDevice: suspend (deviceId: Long) -> Boolean
) {
    val context = LocalContext.current
    val pairingScope = rememberCoroutineScope()
    var connectingDeviceId by remember { mutableStateOf<Long?>(null) }
    var failedDeviceId by remember { mutableStateOf<Long?>(null) }
    // Without the SDK the usual reason is a missing Garmin Connect app; that state gets a way forward.
    val garminConnectMissing = !state.sdkReady && remember(state.sdkReady) { !isGarminConnectInstalled(context) }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = "",
                title = stringResource(R.string.garmin_profile_title),
                supporting = stringResource(R.string.watches_garmin_capability)
            )
            if (!state.sdkReady || state.devices.isEmpty()) {
                Text(
                    text = stringResource(
                        when {
                            state.sdkReady -> R.string.garmin_profile_no_devices
                            garminConnectMissing -> R.string.garmin_profile_not_installed
                            else -> R.string.garmin_profile_unavailable
                        }
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                state.devices.forEach { device ->
                    val connecting = connectingDeviceId == device.deviceId
                    val failed = failedDeviceId == device.deviceId && !connecting
                    // A failed attempt keeps the watch pinned (the pin precedes the first sync),
                    // so a retry stays available after the tag already reads "Paired".
                    val offersConnect = garminDeviceOffersConnect(state, device) ||
                        (failed && state.canPair && !state.pairingResetPending && device.connected)
                    val action: (@Composable (Modifier) -> Unit)? = when {
                        connecting -> { actionModifier ->
                            Text(
                                text = stringResource(R.string.garmin_connecting),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = actionModifier
                            )
                        }
                        offersConnect -> { actionModifier ->
                            Button(
                                onClick = {
                                    if (connectingDeviceId == null) {
                                        val deviceId = device.deviceId
                                        connectingDeviceId = deviceId
                                        failedDeviceId = null
                                        pairingScope.launch {
                                            val paired = try {
                                                onPairGarminDevice(deviceId)
                                            } catch (error: CancellationException) {
                                                throw error
                                            } catch (_: Exception) {
                                                false
                                            }
                                            failedDeviceId = if (paired) null else deviceId
                                            connectingDeviceId = null
                                        }
                                    }
                                },
                                modifier = actionModifier.heightIn(min = 48.dp),
                                elevation = null
                            ) {
                                Text(stringResource(R.string.garmin_connect_action))
                            }
                        }
                        device.trustedForActiveAccount -> { actionModifier ->
                            Text(
                                text = stringResource(R.string.garmin_profile_paired),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = actionModifier
                            )
                        }
                        else -> null
                    }
                    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                        // Narrow card or large text: the Connect button goes under the name instead of
                        // squeezing the name and status into a few characters per line.
                        val stackAction = (connecting || offersConnect) &&
                            maxWidth < 300.dp * LocalDensity.current.fontScale
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Watch,
                                    contentDescription = null,
                                    tint = if (device.connected) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(device.name, style = MaterialTheme.typography.titleMedium)
                                    Text(
                                        text = stringResource(
                                            if (device.connected) R.string.garmin_profile_connected
                                            else R.string.garmin_profile_offline
                                        ),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = if (device.connected) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            MaterialTheme.colorScheme.onSurfaceVariant
                                        }
                                    )
                                }
                                if (!stackAction) action?.invoke(Modifier)
                            }
                            if (stackAction) action?.invoke(Modifier.fillMaxWidth())
                        }
                    }
                    if (failed) {
                        WatchCardNotice(
                            text = stringResource(R.string.garmin_connect_failed),
                            isError = true
                        )
                    }
                    if (device.liteMode) {
                        Text(
                            text = stringResource(R.string.garmin_lite_free_only_notice),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            if (state.sdkReady && state.pairingResetPending) {
                Text(
                    text = stringResource(R.string.garmin_connect_reset_pending),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            when (resetSucceeded) {
                true -> WatchCardNotice(
                    text = stringResource(R.string.garmin_reset_pairing_done),
                    isError = false
                )
                false -> WatchCardNotice(
                    text = stringResource(R.string.garmin_reset_pairing_failed),
                    isError = true
                )
                null -> Unit
            }
            if (state.sdkReady) {
                TintedButton(
                    onClick = onOpenGarminApp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.garmin_open_app))
                }
            } else if (garminConnectMissing) {
                TintedButton(
                    onClick = { openGarminConnectInstallPage(context) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.garmin_install_connect))
                }
            }
            // Shown only when there is something to reset: a watch paired for this account, a reset
            // left pending by an account change, or a reset that just failed and can be retried.
            // Rare and destructive, so it is a low-emphasis text button (the app's destructive text style).
            val hasPairing = state.devices.any { it.trustedForActiveAccount }
            if (hasPairing || state.pairingResetPending || resetSucceeded == false) {
                WatchCardDestructiveTextButton(
                    text = stringResource(R.string.garmin_reset_pairing_action),
                    onClick = onResetGarminPairing
                )
            }
        }
    }
}
