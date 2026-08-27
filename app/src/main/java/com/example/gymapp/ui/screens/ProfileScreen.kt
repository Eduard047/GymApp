package com.example.gymapp.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.compose.runtime.saveable.rememberSaveable
import com.example.gymapp.R
import com.example.gymapp.auth.SocialBlockedProfile
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendRequest
import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialOutgoingWorkoutInvite
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.LiveInvitation
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.garmin.openGymWorkoutTrackerInGarminStore
import com.example.gymapp.garmin.GarminDeviceUiState
import com.example.gymapp.push.PushUiState
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import com.example.gymapp.sync.CloudSyncPhase
import com.example.gymapp.sync.CloudSyncUiStatus
import com.example.gymapp.util.getString
import java.text.DateFormat
import java.util.Date

private enum class ProfileSection {
    Training,
    Settings
}

@Composable
internal fun ProfileScreen(
    accountState: ExerciseListUiState,
    backupShareOwnerKey: String,
    pushUiState: PushUiState,
    onEnablePush: () -> Unit,
    onDisablePush: () -> Unit,
    onOpenPushSettings: () -> Unit,
    friendsState: FriendsUiState,
    liveWorkoutState: LiveWorkoutUiState,
    onRefreshFriends: () -> Unit,
    onSendFriendRequest: (String) -> Unit,
    onAcceptFriendRequest: (SocialFriendRequest) -> Unit,
    onDeclineFriendRequest: (SocialFriendRequest) -> Unit,
    onCancelFriendRequest: (SocialFriendRequest) -> Unit,
    onOpenFriend: (SocialFriend) -> Unit,
    onBlockProfile: (String) -> Unit,
    onUnblockProfile: (SocialBlockedProfile) -> Unit,
    onUpdatePrivacy: (SocialPrivacy, Boolean?) -> Unit,
    onAcceptWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onDeclineWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onReuseWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onCancelWorkoutInvite: (SocialOutgoingWorkoutInvite) -> Unit,
    onLoadMoreWorkoutInvites: () -> Unit,
    onClearFriendsMessages: () -> Unit,
    onAcceptLiveInvitation: (LiveInvitation) -> Unit,
    onDeclineLiveInvitation: (LiveInvitation) -> Unit,
    onCloseLiveRoom: (LiveInboxRoom) -> Unit,
    onOpenLiveRoom: (LiveInboxRoom) -> Unit,
    onClearLiveMessages: () -> Unit,
    focusedSocialPush: PushNavigationTarget.Social? = null,
    focusedLiveRoomId: String? = null,
    cloudSyncStatus: CloudSyncUiStatus?,
    onSyncNow: () -> Unit,
    cloudSyncChoiceRequired: Boolean,
    cloudSyncChoiceReady: Boolean,
    onReviewCloudSync: () -> Unit,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onClearBackup: () -> Unit,
    onOpenImport: () -> Unit,
    onShowTutorial: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onLogout: () -> Unit,
    isAccountActionLoading: Boolean,
    passwordReauthenticationRequired: Boolean,
    passwordChangeSuccessVersion: Long,
    onChangePassword: (
        currentPassword: String,
        newPassword: String,
        nonce: String?
    ) -> Unit,
    onDeleteCloudAccount: (String) -> Unit,
    localProfileName: String?,
    onDeleteLocalProfile: () -> Unit,
    garminDeviceState: GarminDeviceUiState,
    onRefreshGarminDevices: () -> Unit,
    onResetGarminPairing: () -> Unit,
    onRetryLoad: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    var showPasswordChange by rememberSaveable { mutableStateOf(false) }
    var showAccountDeletion by rememberSaveable { mutableStateOf(false) }
    var showLocalProfileDeletion by rememberSaveable { mutableStateOf(false) }
    var selectedSection by rememberSaveable { mutableStateOf(ProfileSection.Training) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) onEnablePush()
    }

    LaunchedEffect(passwordReauthenticationRequired) {
        if (passwordReauthenticationRequired) showPasswordChange = true
    }
    LaunchedEffect(passwordChangeSuccessVersion) {
        if (passwordChangeSuccessVersion > 0L) showPasswordChange = false
    }
    LaunchedEffect(Unit) {
        onRefreshGarminDevices()
    }
    LaunchedEffect(focusedSocialPush, focusedLiveRoomId) {
        if (focusedSocialPush != null || focusedLiveRoomId != null) {
            selectedSection = ProfileSection.Training
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        ProfileSectionSwitcher(
            selected = selectedSection,
            onSelected = { selectedSection = it }
        )
        if (selectedSection == ProfileSection.Training) {
            FriendsScreen(
                uiState = friendsState,
                liveUiState = liveWorkoutState,
                onRefresh = onRefreshFriends,
                onSendFriendRequest = onSendFriendRequest,
                onAcceptFriendRequest = onAcceptFriendRequest,
                onDeclineFriendRequest = onDeclineFriendRequest,
                onCancelFriendRequest = onCancelFriendRequest,
                onOpenFriend = onOpenFriend,
                onBlockProfile = onBlockProfile,
                onUnblockProfile = onUnblockProfile,
                onUpdatePrivacy = onUpdatePrivacy,
                onAcceptWorkoutInvite = onAcceptWorkoutInvite,
                onDeclineWorkoutInvite = onDeclineWorkoutInvite,
                onReuseWorkoutInvite = onReuseWorkoutInvite,
                onCancelWorkoutInvite = onCancelWorkoutInvite,
                onLoadMoreWorkoutInvites = onLoadMoreWorkoutInvites,
                onClearMessages = onClearFriendsMessages,
                onAcceptLiveInvitation = onAcceptLiveInvitation,
                onDeclineLiveInvitation = onDeclineLiveInvitation,
                onCloseLiveRoom = onCloseLiveRoom,
                onOpenLiveRoom = onOpenLiveRoom,
                onClearLiveMessages = onClearLiveMessages,
                onOpenAccountSettings = { selectedSection = ProfileSection.Settings },
                focusedSocialPush = focusedSocialPush,
                focusedLiveRoomId = focusedLiveRoomId,
                modifier = Modifier.weight(1f)
            )
        } else if (selectedSection == ProfileSection.Settings) {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(
                    start = screenHorizontalPadding,
                    top = GymSpacing.ScreenTop,
                    end = screenHorizontalPadding,
                    bottom = GymSpacing.ScreenBottom
                ),
                verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
            ) {
                profileSettingsContent(
                    accountState = accountState,
                    context = context,
                    isAccountActionLoading = isAccountActionLoading,
                    onLogout = onLogout,
                    onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) },
                    onResetGarminPairing = { showGarminResetConfirmation = true },
                    garminDeviceState = garminDeviceState,
                    cloudSyncChoiceRequired = cloudSyncChoiceRequired,
                    cloudSyncChoiceReady = cloudSyncChoiceReady,
                    onReviewCloudSync = onReviewCloudSync,
                    cloudSyncStatus = cloudSyncStatus,
                    onSyncNow = onSyncNow,
                    pushUiState = pushUiState,
                    onEnablePush = {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            notificationPermissionLauncher.launch(
                                Manifest.permission.POST_NOTIFICATIONS
                            )
                        } else {
                            onEnablePush()
                        }
                    },
                    onDisablePush = onDisablePush,
                    onOpenPushSettings = onOpenPushSettings,
                    onChangePassword = { showPasswordChange = true },
                    onDeleteAccount = { showAccountDeletion = true },
                    onDeleteLocalProfile = { showLocalProfileDeletion = true },
                    backupMessage = accountState.backupMessage,
                    onExportBackup = onExportBackup,
                    onExportDiagnostics = onExportDiagnostics,
                    onOpenImport = onOpenImport,
                    onShowTutorial = onShowTutorial,
                    onRetryLoad = onRetryLoad
                )
            }
        }
    }

    AccountBackupSheets(
        uiState = accountState,
        backupShareOwnerKey = backupShareOwnerKey,
        onClearBackup = onClearBackup,
        onCloseImport = onCloseImport,
        onImportJsonChange = onImportJsonChange,
        onImportBackup = onImportBackup
    )

    if (showGarminResetConfirmation) {
        AlertDialog(
            onDismissRequest = { showGarminResetConfirmation = false },
            title = { Text(stringResource(R.string.garmin_reset_pairing_title)) },
            text = { Text(stringResource(R.string.garmin_reset_pairing_description)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showGarminResetConfirmation = false
                        onResetGarminPairing()
                    }
                ) {
                    Text(stringResource(R.string.garmin_reset_pairing_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showGarminResetConfirmation = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }

    if (showPasswordChange) {
        ChangePasswordDialog(
            reauthenticationRequired = passwordReauthenticationRequired,
            isLoading = isAccountActionLoading,
            onDismiss = {
                if (!isAccountActionLoading) showPasswordChange = false
            },
            onConfirm = { currentPassword, newPassword, nonce ->
                onChangePassword(currentPassword, newPassword, nonce)
            }
        )
    }

    if (showAccountDeletion) {
        DeleteCloudAccountDialog(
            onDismiss = { showAccountDeletion = false },
            onConfirm = { currentPassword ->
                showAccountDeletion = false
                onDeleteCloudAccount(currentPassword)
            }
        )
    }
    if (showLocalProfileDeletion && localProfileName != null) {
        AlertDialog(
            onDismissRequest = {
                if (!isAccountActionLoading) showLocalProfileDeletion = false
            },
            title = {
                Text(stringResource(R.string.local_profile_delete_confirm_title, localProfileName))
            },
            text = { Text(stringResource(R.string.local_profile_delete_warning)) },
            confirmButton = {
                Button(
                    onClick = {
                        showLocalProfileDeletion = false
                        onDeleteLocalProfile()
                    },
                    enabled = !isAccountActionLoading,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError
                    )
                ) {
                    Text(stringResource(R.string.local_profile_delete_confirm))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showLocalProfileDeletion = false },
                    enabled = !isAccountActionLoading
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun ProfileSectionSwitcher(
    selected: ProfileSection,
    onSelected: (ProfileSection) -> Unit
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = screenHorizontalPadding,
                top = GymSpacing.Small,
                end = screenHorizontalPadding,
                bottom = GymSpacing.XSmall
            ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)
    ) {
        GymSegmentedControl(
            items = listOf(
                GymSegmentItem(
                    ProfileSection.Training,
                    stringResource(R.string.profile_section_training)
                ),
                GymSegmentItem(
                    ProfileSection.Settings,
                    stringResource(R.string.profile_section_settings)
                )
            ),
            selected = selected,
            onSelected = onSelected
        )
    }
}

private fun LazyListScope.profileSettingsContent(
    accountState: ExerciseListUiState,
    context: android.content.Context,
    isAccountActionLoading: Boolean,
    onLogout: () -> Unit,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit,
    garminDeviceState: GarminDeviceUiState,
    cloudSyncChoiceRequired: Boolean,
    cloudSyncChoiceReady: Boolean,
    onReviewCloudSync: () -> Unit,
    cloudSyncStatus: CloudSyncUiStatus?,
    onSyncNow: () -> Unit,
    pushUiState: PushUiState,
    onEnablePush: () -> Unit,
    onDisablePush: () -> Unit,
    onOpenPushSettings: () -> Unit,
    onChangePassword: () -> Unit,
    onDeleteAccount: () -> Unit,
    onDeleteLocalProfile: () -> Unit,
    backupMessage: com.example.gymapp.util.LocalizedText?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit,
    onShowTutorial: () -> Unit,
    onRetryLoad: () -> Unit
) {
    if (accountState.isLoading) {
        item {
            LoadingStatePanel(label = context.getString(R.string.exercises_loading))
        }
    }
    accountState.loadError?.let { error ->
        item {
            EmptyStatePanel(
                title = context.getString(error),
                actionLabel = context.getString(R.string.action_retry),
                onAction = onRetryLoad
            )
        }
    }
    item { SettingsSectionHeader(stringResource(R.string.profile_settings_account)) }
    item {
        AccountStatusCard(
            label = accountState.accountLabel.ifBlank {
                if (accountState.isLoading || accountState.loadError != null) {
                    context.getString(R.string.profile_settings_account)
                } else {
                    context.getString(R.string.account_mode_local)
                }
            },
            supporting = accountState.accountSupporting.ifBlank {
                when {
                    accountState.isLoading -> context.getString(R.string.exercises_loading)
                    accountState.loadError != null -> context.getString(accountState.loadError)
                    else -> context.getString(R.string.account_offline_supporting)
                }
            },
            isCloudAccount = accountState.isCloudAccount,
            canLogout = accountState.canLogout,
            logoutEnabled = !isAccountActionLoading,
            onLogout = onLogout,
            onOpenGarminApp = onOpenGarminApp,
            onResetGarminPairing = onResetGarminPairing
        )
    }
    item { SettingsSectionHeader(stringResource(R.string.profile_settings_devices_sync)) }
    item { GarminDeviceCard(garminDeviceState) }
    if (accountState.isCloudAccount && cloudSyncChoiceRequired) {
        item {
            CloudSyncChoiceCard(
                choiceReady = cloudSyncChoiceReady,
                onReview = onReviewCloudSync
            )
        }
    }
    if (accountState.isCloudAccount && cloudSyncStatus != null) {
        item { CloudSyncStatusCard(status = cloudSyncStatus, onSyncNow = onSyncNow) }
    }
    if (accountState.isCloudAccount) {
        item {
            PushNotificationCard(
                state = pushUiState,
                onEnable = onEnablePush,
                onDisable = onDisablePush,
                onOpenSettings = onOpenPushSettings
            )
        }
        item {
            CloudAccountActionsCard(
                enabled = !isAccountActionLoading,
                onChangePassword = onChangePassword,
                onDeleteAccount = onDeleteAccount
            )
        }
    } else {
        item {
            LocalProfileActionsCard(
                enabled = !isAccountActionLoading,
                onDeleteProfile = onDeleteLocalProfile
            )
        }
    }
    item { SettingsSectionHeader(stringResource(R.string.profile_settings_data)) }
    item {
        BackupToolsCard(
            message = backupMessage,
            onExportBackup = onExportBackup,
            onExportDiagnostics = onExportDiagnostics,
            onOpenImport = onOpenImport
        )
    }
    item { SettingsSectionHeader(stringResource(R.string.profile_settings_help_support)) }
    item { TutorialHelpCard(onShowTutorial = onShowTutorial) }
}

@Composable
private fun SettingsSectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(top = GymSpacing.Small, start = GymSpacing.XSmall)
    )
}

@Composable
private fun TutorialHelpCard(onShowTutorial: () -> Unit) {
    val context = LocalContext.current
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = "",
                title = stringResource(R.string.profile_help_title),
                supporting = stringResource(R.string.profile_help_supporting)
            )
            OutlinedButton(
                onClick = onShowTutorial,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                Text(stringResource(R.string.tutorial_show_action))
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)
            ) {
                TextButton(
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROFILE_SUPPORT_URL)))
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.profile_support_action))
                }
                TextButton(
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROFILE_PRIVACY_URL)))
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.auth_privacy_policy))
                }
            }
        }
    }
}

private const val PROFILE_SUPPORT_URL = "https://gymapptracker.com/support.html"
private const val PROFILE_PRIVACY_URL = "https://gymapptracker.com/privacy-policy.html"

@Composable
private fun LocalProfileActionsCard(
    enabled: Boolean,
    onDeleteProfile: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.local_profile_delete_title),
                style = MaterialTheme.typography.titleLarge
            )
            Button(
                onClick = onDeleteProfile,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                )
            ) {
                Text(stringResource(R.string.local_profile_delete_action))
            }
        }
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
private fun GarminDeviceCard(state: GarminDeviceUiState) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.garmin_profile_eyebrow),
                title = stringResource(R.string.garmin_profile_title),
                supporting = stringResource(R.string.garmin_profile_supporting)
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
                        if (device.trustedForActiveAccount) {
                            Text(
                                text = stringResource(R.string.garmin_profile_paired),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
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

@Composable
private fun CloudAccountActionsCard(
    enabled: Boolean,
    onChangePassword: () -> Unit,
    onDeleteAccount: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.account_management_eyebrow),
                title = stringResource(R.string.account_management_title),
                supporting = stringResource(R.string.account_management_supporting)
            )
            OutlinedButton(
                onClick = onChangePassword,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.account_change_password))
            }
            Button(
                onClick = onDeleteAccount,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                )
            ) {
                Text(stringResource(R.string.account_delete_action))
            }
        }
    }
}

@Composable
private fun ChangePasswordDialog(
    reauthenticationRequired: Boolean,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (currentPassword: String, newPassword: String, nonce: String?) -> Unit
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var repeatedPassword by remember { mutableStateOf("") }
    var nonce by remember { mutableStateOf("") }
    var validationMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.account_change_password)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(
                        if (reauthenticationRequired) {
                            R.string.account_password_reauthentication_supporting
                        } else {
                            R.string.account_change_password_supporting
                        }
                    )
                )
                ProfilePasswordField(
                    value = currentPassword,
                    onValueChange = {
                        currentPassword = it
                        validationMessage = null
                    },
                    label = stringResource(R.string.account_current_password)
                )
                if (reauthenticationRequired) {
                    OutlinedTextField(
                        value = nonce,
                        onValueChange = {
                            nonce = it.filter { character -> character in '0'..'9' }.take(8)
                            validationMessage = null
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = {
                            Text(stringResource(R.string.account_password_verification_code))
                        },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.NumberPassword
                        )
                    )
                }
                ProfilePasswordField(
                    value = newPassword,
                    onValueChange = {
                        newPassword = it
                        validationMessage = null
                    },
                    label = stringResource(R.string.auth_new_password)
                )
                ProfilePasswordField(
                    value = repeatedPassword,
                    onValueChange = {
                        repeatedPassword = it
                        validationMessage = null
                    },
                    label = stringResource(R.string.auth_repeat_password)
                )
                validationMessage?.let { message ->
                    Text(
                        text = stringResource(profileAuthValidationResource(message)),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Text(
                    text = stringResource(R.string.auth_new_password_requirements),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = !isLoading,
                onClick = {
                    val validation = validateSignedInPasswordChange(
                        currentPassword = currentPassword,
                        newPassword = newPassword,
                        repeatedPassword = repeatedPassword,
                        nonce = nonce.takeIf { reauthenticationRequired },
                        nonceRequired = reauthenticationRequired
                    )
                    if (validation == null) {
                        onConfirm(
                            currentPassword,
                            newPassword,
                            nonce.takeIf { reauthenticationRequired }
                        )
                    } else {
                        validationMessage = validation
                    }
                }
            ) {
                Text(stringResource(R.string.auth_update_password))
            }
        },
        dismissButton = {
            TextButton(enabled = !isLoading, onClick = onDismiss) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}

@Composable
private fun ProfilePasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String
) {
    OutlinedTextField(
        value = value,
        onValueChange = { onValueChange(boundedAuthPasswordDraft(it)) },
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
    )
}

@Composable
private fun DeleteCloudAccountDialog(
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var confirmation by rememberSaveable { mutableStateOf("") }
    // Credentials must never enter SavedState/Bundle persistence.
    var currentPassword by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.account_delete_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.account_delete_warning))
                ProfilePasswordField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    label = stringResource(R.string.account_current_password)
                )
                OutlinedTextField(
                    value = confirmation,
                    onValueChange = { confirmation = it.take(16) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.account_delete_confirmation_label)) },
                    supportingText = {
                        Text(stringResource(R.string.account_delete_confirmation_hint))
                    },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = confirmation == "DELETE" && currentPassword.isNotEmpty(),
                onClick = { onConfirm(currentPassword) }
            ) {
                Text(
                    text = stringResource(R.string.account_delete_confirm),
                    color = MaterialTheme.colorScheme.error
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}

internal fun validateSignedInPasswordChange(
    currentPassword: String,
    newPassword: String,
    repeatedPassword: String,
    nonce: String? = null,
    nonceRequired: Boolean = false
): String? = when {
    currentPassword.isEmpty() -> "Enter your current password."
    currentPassword.toByteArray(Charsets.UTF_8).size > 1_024 ->
        "Current password is too long."
    currentPassword == newPassword ->
        "Choose a new password that differs from the current password."
    nonceRequired && (nonce == null || !nonce.matches(Regex("^[0-9]{6,8}$"))) ->
        "Enter the verification code sent to your email."
    else -> validatePasswordUpdateInput(newPassword, repeatedPassword)
}

private fun profileAuthValidationResource(message: String): Int = when (message) {
    "Enter your current password." -> R.string.account_current_password_required
    "Current password is too long." -> R.string.account_current_password_too_long
    "Choose a new password that differs from the current password." ->
        R.string.account_new_password_must_differ
    "Enter the verification code sent to your email." ->
        R.string.account_password_verification_code_required
    "Enter a new password." -> R.string.auth_error_new_password_required
    "Password must contain at least 12 characters and fit within 72 UTF-8 bytes." ->
        R.string.auth_error_password_minimum
    "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol." ->
        R.string.auth_error_password_complexity
    "Passwords do not match." -> R.string.auth_error_password_mismatch
    else -> R.string.auth_password_update_failed
}
