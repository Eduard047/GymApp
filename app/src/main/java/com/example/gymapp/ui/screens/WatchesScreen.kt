package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.gymapp.ui.viewmodel.GarminConnectUiState
import com.example.gymapp.ui.viewmodel.GarminConnectViewModel
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
    modifier: Modifier = Modifier,
    healthConnectSettingsIntent: () -> Intent? = { null }
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    // Connect and reset run in an activity-scoped ViewModel: rotation, leaving the screen or Back never
    // cancels a pairing after the watch was pinned, and the connecting/failed state is kept there.
    val garminConnectViewModel: GarminConnectViewModel = viewModel(
        viewModelStoreOwner = garminConnectViewModelOwner(),
        key = "garmin-connect"
    )
    val garminConnectState by garminConnectViewModel.state.collectAsStateWithLifecycle()
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
                connectState = garminConnectState,
                onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) },
                onResetGarminPairing = { showGarminResetConfirmation = true },
                onConnect = { deviceId -> garminConnectViewModel.connect(deviceId, onPairGarminDevice) }
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
                    modifier = Modifier.padding(top = GymSpacing.Medium),
                    healthConnectSettingsIntent = healthConnectSettingsIntent
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
                        // Without the old watch (or before it acknowledged) the reset releases only this
                        // phone's pin; the result is shown on the card.
                        garminConnectViewModel.reset(onResetGarminPairing)
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

/**
 * A watch row (Garmin, Wear OS) is too narrow for a trailing action or tag beside the name and
 * status: a narrow card or large text. The action then moves under the name and status.
 */
internal fun watchRowIsNarrow(rowWidth: Dp, fontScale: Float): Boolean = rowWidth < 300.dp * fontScale

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

/** The activity's ViewModel store (survives rotation and leaving the screen), else the local owner. */
@Composable
private fun garminConnectViewModelOwner(): ViewModelStoreOwner {
    var context: Context? = LocalContext.current
    while (context is ContextWrapper && context !is ComponentActivity) context = context.baseContext
    return (context as? ComponentActivity)
        ?: checkNotNull(LocalViewModelStoreOwner.current) { "No ViewModelStoreOwner" }
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
    connectState: GarminConnectUiState,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit,
    onConnect: (deviceId: Long) -> Unit
) {
    val context = LocalContext.current
    val resetSucceeded = connectState.resetSucceeded
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
                    val connecting = connectState.connectingDeviceId == device.deviceId
                    val failed = connectState.failedDeviceId == device.deviceId && !connecting &&
                        !device.trustedForActiveAccount
                    // "Paired" needs the watch's acknowledgement; until then (failed, interrupted or
                    // never acknowledged) the pinned watch keeps offering Connect as a retry.
                    val offersConnect = garminDeviceOffersConnect(state, device)
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
                                onClick = { onConnect(device.deviceId) },
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
                        // Narrow card or large text: the trailing action leaves the row instead of
                        // squeezing the name and status into a few characters per line. The Connect
                        // button (or "Connecting") goes full-width under the row, the "Paired" tag
                        // becomes a line under the status.
                        val narrow = watchRowIsNarrow(maxWidth, LocalDensity.current.fontScale)
                        val stackAction = (connecting || offersConnect) && narrow
                        val tagUnderStatus = !connecting && !offersConnect && action != null && narrow
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
                                    if (tagUnderStatus) action?.invoke(Modifier.padding(top = 2.dp))
                                }
                                if (!stackAction && !tagUnderStatus) action?.invoke(Modifier)
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
                    text = stringResource(
                        if (state.pairingReleasedWithoutWatch) R.string.garmin_reset_pairing_released_offline
                        else R.string.garmin_reset_pairing_done
                    ),
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
            // A pin counts even when it was never acknowledged or the watch is gone (replacement watch).
            val hasPairing = state.hasPinnedWatch || state.devices.any { it.trustedForActiveAccount }
            if (hasPairing || state.pairingResetPending || resetSucceeded == false) {
                WatchCardDestructiveTextButton(
                    text = stringResource(R.string.garmin_reset_pairing_action),
                    onClick = onResetGarminPairing
                )
            }
        }
    }
}
