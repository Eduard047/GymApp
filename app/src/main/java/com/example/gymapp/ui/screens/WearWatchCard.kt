package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.viewmodel.WearWatchCardMode
import com.example.gymapp.ui.viewmodel.WearWatchUiState
import com.example.gymapp.ui.viewmodel.wearWatchCardMode
import com.example.gymapp.ui.viewmodel.wearWatchDisplayName

/**
 * Wear OS card on the Watches screen, between Garmin and Health data. Hidden entirely when the
 * Google Play services Wearable API is unavailable. The watch links itself (the phone pins the
 * first watch that asks for a full sync); the card shows that link and offers "Unpair watch".
 * After an unpair the watch links again only from its own "Link to phone" action.
 */
@Composable
internal fun WearWatchCard(
    state: WearWatchUiState,
    onUnlink: () -> Unit,
    modifier: Modifier = Modifier
) {
    val mode = wearWatchCardMode(state)
    if (mode == WearWatchCardMode.HIDDEN) return
    var showUnlinkConfirmation by rememberSaveable { mutableStateOf(false) }

    AppPanel(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = "",
                title = stringResource(R.string.watches_wear_title),
                // The same capability as the Garmin watch app, so the same string.
                supporting = stringResource(R.string.watches_garmin_capability)
            )
            if (mode == WearWatchCardMode.NOT_LINKED) {
                Text(
                    text = stringResource(R.string.watches_wear_not_linked),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    // Narrow card or large text: the "Paired" tag becomes a line under the status, as on
                    // Garmin, instead of squeezing the name and status into a few characters per line.
                    val tagUnderStatus = state.linkConfirmed &&
                        watchRowIsNarrow(maxWidth, LocalDensity.current.fontScale)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Watch,
                            contentDescription = null,
                            tint = if (state.connected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = wearWatchDisplayName(
                                    state,
                                    stringResource(R.string.watches_wear_default_name)
                                ),
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = stringResource(
                                    if (state.connected) R.string.garmin_profile_connected
                                    else R.string.garmin_profile_offline
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = if (state.connected) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                }
                            )
                            if (tagUnderStatus) WearLinkedTag(Modifier.padding(top = 2.dp))
                        }
                        // The same tag and word as Garmin's "Paired", shown once the watch has proved
                        // that it follows this phone; until then the line below says what is missing.
                        if (state.linkConfirmed && !tagUnderStatus) WearLinkedTag()
                    }
                }
                if (!state.linkConfirmed) {
                    Text(
                        text = stringResource(R.string.watches_wear_link_pending),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                // Rare and destructive: the app's low-emphasis destructive text style, as on Garmin.
                WatchCardDestructiveTextButton(
                    text = stringResource(R.string.watches_wear_unlink_action),
                    onClick = { showUnlinkConfirmation = true }
                )
            }
            Text(
                text = stringResource(R.string.watches_wear_caption),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    if (showUnlinkConfirmation && mode == WearWatchCardMode.LINKED) {
        GymAlertDialog(
            onDismissRequest = { showUnlinkConfirmation = false },
            title = stringResource(R.string.watches_wear_unlink_title),
            text = { Text(stringResource(R.string.watches_wear_unlink_body)) },
            confirmButton = {
                GymAlertDialogButton(
                    onClick = {
                        showUnlinkConfirmation = false
                        onUnlink()
                    },
                    role = GymAlertDialogButtonRole.Destructive
                ) {
                    Text(stringResource(R.string.watches_wear_unlink_confirm))
                }
            },
            dismissButton = {
                GymAlertDialogButton(
                    onClick = { showUnlinkConfirmation = false },
                    role = GymAlertDialogButtonRole.Cancel
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

/** The "Paired" tag of a linked Wear OS watch (the same tag and word as Garmin's). */
@Composable
private fun WearLinkedTag(modifier: Modifier = Modifier) {
    Text(
        text = stringResource(R.string.watches_wear_linked),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier
    )
}
