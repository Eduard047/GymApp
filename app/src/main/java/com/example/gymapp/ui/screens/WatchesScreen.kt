package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * The Watches screen pushed from Profile: every watch connection in one place. Order: Garmin, then
 * Health data (Health Connect). The Profile root only shows a one-line status for it. The screen
 * keeps no connection state itself; foreground auto-import still runs from the navigation graph.
 */
@Composable
internal fun WatchesScreen(
    garminDeviceState: GarminDeviceUiState,
    healthDataState: HealthDataUiState?,
    onOpened: () -> Unit,
    onResetGarminPairing: () -> Unit,
    onPairGarminDevice: suspend (deviceId: Long) -> Boolean,
    onHealthPermissionRequestFinished: () -> Unit,
    onHealthImportNow: () -> Unit,
    onHealthDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    // Opening the screen refreshes both sources so the cards never show a stale connection.
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
                onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) },
                onResetGarminPairing = { showGarminResetConfirmation = true },
                onPairGarminDevice = onPairGarminDevice
            )
        }
        // Future "Wear OS" watch card (stage 4) goes here, between Garmin and Health data.
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
                        onResetGarminPairing()
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

@Composable
private fun GarminDeviceCard(
    state: GarminDeviceUiState,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit,
    onPairGarminDevice: suspend (deviceId: Long) -> Boolean
) {
    val pairingScope = rememberCoroutineScope()
    var connectingDeviceId by remember { mutableStateOf<Long?>(null) }
    var failedDeviceId by remember { mutableStateOf<Long?>(null) }
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
                        if (state.sdkReady) R.string.garmin_profile_no_devices
                        else R.string.garmin_profile_unavailable
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                state.devices.forEach { device ->
                    val connecting = connectingDeviceId == device.deviceId
                    val failed = failedDeviceId == device.deviceId && !connecting
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
                        // A failed attempt keeps the watch pinned (the pin precedes the first sync),
                        // so a retry stays available after the tag already reads "Paired".
                        val offersConnect = garminDeviceOffersConnect(state, device) ||
                            (failed && state.canPair && !state.pairingResetPending && device.connected)
                        if (connecting) {
                            Text(
                                text = stringResource(R.string.garmin_connecting),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else if (offersConnect) {
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
                                modifier = Modifier.heightIn(min = 48.dp),
                                elevation = null
                            ) {
                                Text(stringResource(R.string.garmin_connect_action))
                            }
                        } else if (device.trustedForActiveAccount) {
                            Text(
                                text = stringResource(R.string.garmin_profile_paired),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                    if (failed) {
                        Text(
                            text = stringResource(R.string.garmin_connect_failed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
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
            // Without the Garmin SDK there is nothing to open, so the card only states that.
            if (state.sdkReady) {
                TintedButton(
                    onClick = onOpenGarminApp,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.garmin_open_app))
                }
            }
            // Always available: the reset is also the explicit user action that clears a pending
            // reset left by an account change, and the SDK device list can be empty while it is not ready.
            // Rare and destructive, so it is a low-emphasis text button (the app's destructive text style).
            TextButton(
                onClick = onResetGarminPairing,
                modifier = Modifier.heightIn(min = 48.dp),
                contentPadding = PaddingValues(horizontal = 0.dp),
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text(stringResource(R.string.garmin_reset_pairing_action))
            }
        }
    }
}
