package com.example.gymapp.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
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
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.push.PushUiState
import com.example.gymapp.sync.CloudSyncPhase
import com.example.gymapp.sync.CloudSyncUiStatus
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.SettingsPanel
import com.example.gymapp.ui.components.SettingsRow
import com.example.gymapp.ui.components.SettingsRowDivider
import com.example.gymapp.ui.components.SettingsRowTrailing
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay

internal const val PROFILE_SUPPORT_URL = "https://gymapptracker.com/support.html"
internal const val PROFILE_PRIVACY_URL = "https://gymapptracker.com/privacy-policy.html"

private const val COPIED_CONFIRMATION_MILLIS = 2_000L
private const val IDENTIFIER_EDGE_CHARACTERS = 8

/**
 * Everything about the signed-in identity in one sheet: who this is, cloud sync and
 * notifications (cloud) or a backup hint (local), privacy and support links, sign-out and
 * deletion. Confirmation and re-authentication dialogs stay with the caller.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountSettingsSheet(
    state: ExerciseListUiState,
    actionsEnabled: Boolean,
    pushUiState: PushUiState,
    cloudSyncStatus: CloudSyncUiStatus?,
    cloudSyncChoiceRequired: Boolean,
    cloudSyncChoiceReady: Boolean,
    onReviewCloudSync: () -> Unit,
    onSyncNow: () -> Unit,
    onEnablePush: () -> Unit,
    onDisablePush: () -> Unit,
    onOpenPushSettings: () -> Unit,
    onExportBackup: () -> Unit,
    onChangePassword: () -> Unit,
    onLogout: () -> Unit,
    onDeleteAccount: () -> Unit,
    onDeleteLocalProfile: () -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GymSpacing.XLarge)
                .padding(bottom = GymSpacing.XXLarge),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.account_sheet_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() }
                )
                TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.account_sheet_done))
                }
            }
            AccountIdentityCard(state)
            if (state.isCloudAccount) {
                if (cloudSyncChoiceRequired) {
                    CloudSyncChoiceCard(
                        choiceReady = cloudSyncChoiceReady,
                        onReview = onReviewCloudSync
                    )
                }
                if (cloudSyncStatus != null) {
                    CloudSyncStatusCard(status = cloudSyncStatus, onSyncNow = onSyncNow)
                }
                PushNotificationCard(
                    state = pushUiState,
                    onEnable = onEnablePush,
                    onDisable = onDisablePush,
                    onOpenSettings = onOpenPushSettings
                )
            } else {
                SettingsPanel {
                    SettingsRow(
                        icon = Icons.Default.Backup,
                        title = stringResource(R.string.account_backup_title),
                        subtitle = stringResource(R.string.account_backup_hint),
                        // The export opens its own sheet, so this one steps aside first.
                        onClick = {
                            onDismiss()
                            onExportBackup()
                        }
                    )
                }
            }
            AccountLinksPanel(context)
            if (state.isCloudAccount || state.canLogout) {
                SettingsPanel {
                    if (state.isCloudAccount) {
                        SettingsRow(
                            icon = Icons.Default.Lock,
                            title = stringResource(R.string.account_change_password),
                            onClick = onChangePassword,
                            enabled = actionsEnabled
                        )
                        if (state.canLogout) SettingsRowDivider()
                    }
                    if (state.canLogout) {
                        SettingsRow(
                            icon = Icons.AutoMirrored.Filled.Logout,
                            title = stringResource(
                                if (state.isCloudAccount) R.string.account_sign_out_cloud_title
                                else R.string.account_sign_out_local_title
                            ),
                            subtitle = stringResource(
                                if (state.isCloudAccount) R.string.account_sign_out_cloud_hint
                                else R.string.account_sign_out_local_hint
                            ),
                            onClick = onLogout,
                            enabled = actionsEnabled
                        )
                    }
                }
            }
            AccountDeleteRow(
                isCloudAccount = state.isCloudAccount,
                enabled = actionsEnabled,
                onDeleteAccount = onDeleteAccount,
                onDeleteLocalProfile = onDeleteLocalProfile
            )
        }
    }
}

/** Plain destructive row: no panel or filled background; each account type keeps its own flow. */
@Composable
private fun AccountDeleteRow(
    isCloudAccount: Boolean,
    enabled: Boolean,
    onDeleteAccount: () -> Unit,
    onDeleteLocalProfile: () -> Unit
) {
    if (isCloudAccount) {
        SettingsRow(
            icon = Icons.Default.Delete,
            title = stringResource(R.string.account_delete_action),
            onClick = onDeleteAccount,
            enabled = enabled,
            trailing = SettingsRowTrailing.None,
            iconTint = MaterialTheme.colorScheme.error,
            titleColor = MaterialTheme.colorScheme.error
        )
    } else {
        SettingsRow(
            icon = Icons.Default.Delete,
            title = stringResource(R.string.local_profile_delete_action),
            onClick = onDeleteLocalProfile,
            enabled = enabled,
            trailing = SettingsRowTrailing.None,
            iconTint = MaterialTheme.colorScheme.error,
            titleColor = MaterialTheme.colorScheme.error
        )
    }
}

@Composable
private fun AccountIdentityCard(state: ExerciseListUiState) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = if (state.isCloudAccount) {
                        Icons.Default.AccountCircle
                    } else {
                        Icons.Default.PhoneAndroid
                    },
                    contentDescription = null,
                    modifier = Modifier.size(28.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = state.accountLabel.ifBlank { stringResource(R.string.title_profile) },
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = accountSubtitle(state),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (state.accountId.isNotBlank()) {
                AccountIdentifierRow(
                    label = stringResource(
                        if (state.isCloudAccount) R.string.account_id_user
                        else R.string.account_id_profile
                    ),
                    value = state.accountId
                )
            }
        }
    }
}

/**
 * The subtitle under the name: the email for cloud, the storage note for local. The compact form
 * (the Profile row) drops the storage note; the sheet's identity card keeps it.
 */
@Composable
internal fun accountSubtitle(state: ExerciseListUiState, compact: Boolean = false): String = when {
    state.isCloudAccount ->
        state.accountSupporting.ifBlank { stringResource(R.string.account_cloud_fallback) }
    compact -> stringResource(R.string.profile_account_local_subtitle)
    else -> stringResource(R.string.account_local_subtitle)
}

@Composable
private fun AccountIdentifierRow(label: String, value: String) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(COPIED_CONFIRMATION_MILLIS)
            copied = false
        }
    }
    val copyLabel = stringResource(if (copied) R.string.account_id_copied else R.string.account_id_copy)
    val copyHint = stringResource(R.string.account_id_copy_hint)
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = middleTruncatedIdentifier(value),
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.semantics { contentDescription = value }
            )
        }
        FilledTonalButton(
            onClick = { if (copyAccountIdentifier(context, label, value)) copied = true },
            modifier = Modifier.semantics {
                contentDescription = "$copyLabel. $copyHint"
                if (copied) liveRegion = LiveRegionMode.Polite
            }
        ) {
            Text(copyLabel)
        }
    }
}

/** Keeps the start and end of a long identifier so two ids stay tellable apart on one line. */
internal fun middleTruncatedIdentifier(
    value: String,
    edgeCharacters: Int = IDENTIFIER_EDGE_CHARACTERS
): String = if (value.length <= edgeCharacters * 2 + 1) {
    value
} else {
    value.take(edgeCharacters) + "…" + value.takeLast(edgeCharacters)
}

private fun copyAccountIdentifier(context: Context, label: String, value: String): Boolean {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
    return runCatching {
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
    }.isSuccess
}

@Composable
private fun AccountLinksPanel(context: Context) {
    val openLabel = stringResource(R.string.account_open_in_browser)
    Column(verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)) {
        SettingsPanel {
            SettingsRow(
                icon = Icons.Default.PrivacyTip,
                title = stringResource(R.string.auth_privacy_policy),
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROFILE_PRIVACY_URL)))
                },
                onClickLabel = openLabel,
                trailing = SettingsRowTrailing.ExternalLink
            )
            SettingsRowDivider()
            SettingsRow(
                icon = Icons.Default.SupportAgent,
                title = stringResource(R.string.profile_support_action),
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROFILE_SUPPORT_URL)))
                },
                onClickLabel = openLabel,
                trailing = SettingsRowTrailing.ExternalLink
            )
        }
        Text(
            text = stringResource(R.string.account_privacy_caption),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = GymSpacing.XSmall)
        )
    }
}

@Composable
private fun PushNotificationCard(
    state: PushUiState,
    onEnable: () -> Unit,
    onDisable: () -> Unit,
    onOpenSettings: () -> Unit
) {
    val systemBlocked = !state.permissionGranted || !state.channelEnabled
    val blockedBySystem = state.enabled && systemBlocked
    val supporting = stringResource(
        when {
            !state.configured -> R.string.push_status_unavailable
            state.hasError -> R.string.push_status_error
            !state.enabled -> R.string.push_status_disabled
            !state.permissionGranted -> R.string.push_status_permission_required
            !state.channelEnabled -> R.string.push_status_channel_blocked
            state.isSyncing -> R.string.push_status_syncing
            state.registered -> R.string.push_status_ready
            else -> R.string.push_status_waiting
        }
    )
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = state.registered) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.push_settings_eyebrow),
                title = stringResource(R.string.push_settings_title),
                supporting = supporting
            )
            Button(
                onClick = when {
                    blockedBySystem -> onOpenSettings
                    state.enabled -> onDisable
                    else -> onEnable
                },
                enabled = state.configured && !state.isSyncing,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(
                        when {
                            blockedBySystem -> R.string.push_open_settings
                            state.enabled -> R.string.push_disable_action
                            else -> R.string.push_enable_action
                        }
                    )
                )
            }
            if (blockedBySystem) {
                OutlinedButton(
                    onClick = onDisable,
                    enabled = !state.isSyncing,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.push_disable_action))
                }
            } else if (state.configured && systemBlocked) {
                OutlinedButton(
                    onClick = onOpenSettings,
                    enabled = !state.isSyncing,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.push_open_settings))
                }
            }
        }
    }
}

@Composable
private fun CloudSyncStatusCard(
    status: CloudSyncUiStatus,
    onSyncNow: () -> Unit
) {
    val statusText = stringResource(
        when (status.phase) {
            CloudSyncPhase.Checking -> R.string.cloud_sync_status_checking
            CloudSyncPhase.Pending -> R.string.cloud_sync_status_pending
            CloudSyncPhase.Synced -> R.string.cloud_sync_status_synced
            CloudSyncPhase.Conflict -> R.string.cloud_sync_status_conflict
            CloudSyncPhase.Error -> R.string.cloud_sync_status_error
        }
    )
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.cloud_sync_status_eyebrow),
                title = statusText,
                supporting = status.lastSuccessAt?.let { timestamp ->
                    stringResource(
                        R.string.cloud_sync_status_last_success,
                        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
                            .format(Date(timestamp))
                    )
                } ?: stringResource(R.string.cloud_sync_status_never)
            )
            Button(
                onClick = onSyncNow,
                enabled = status.phase != CloudSyncPhase.Checking &&
                    status.phase != CloudSyncPhase.Conflict,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
            ) {
                Text(
                    stringResource(
                        if (status.phase == CloudSyncPhase.Error) {
                            R.string.cloud_sync_retry_action
                        } else {
                            R.string.cloud_sync_now_action
                        }
                    )
                )
            }
        }
    }
}

@Composable
private fun CloudSyncChoiceCard(
    choiceReady: Boolean,
    onReview: () -> Unit
) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.cloud_sync_choice_card_title),
                style = MaterialTheme.typography.titleLarge
            )
            Text(
                text = stringResource(R.string.cloud_sync_choice_card_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(
                onClick = onReview,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
            ) {
                Text(
                    stringResource(
                        if (choiceReady) R.string.cloud_sync_choice_card_review
                        else R.string.cloud_sync_choice_card_check
                    )
                )
            }
        }
    }
}
