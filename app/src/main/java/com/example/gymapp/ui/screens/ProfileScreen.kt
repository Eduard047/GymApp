package com.example.gymapp.ui.screens

import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.ui.components.gymSwitchColors
import com.example.gymapp.ui.components.trainingSettingsSummary
import com.example.gymapp.ui.components.TrainingSettingsSheet
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.example.gymapp.ui.components.AppleBackButton
import com.example.gymapp.ui.components.GroupedRow
import com.example.gymapp.ui.components.GroupedSection
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.components.GymMotion
import com.example.gymapp.ui.components.rememberReduceMotion
import com.example.gymapp.util.asString
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.material3.Badge
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.TextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Campaign
import androidx.compose.material.icons.outlined.HowToReg
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GroupOff
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material.icons.filled.UnfoldMore
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
import androidx.compose.foundation.selection.toggleable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.semantics.Role
import com.example.gymapp.ui.components.rememberConversionAnalytics
import com.example.gymapp.util.rememberHapticsPreference
import com.example.gymapp.util.rememberKeepScreenOnPreference
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
import com.example.gymapp.auth.NEW_PASSWORD_POLICY_ERROR
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
import com.example.gymapp.ui.components.SettingsPanel
import com.example.gymapp.ui.components.SettingsRow
import com.example.gymapp.ui.components.SettingsRowDivider
import com.example.gymapp.ui.components.SettingsRowTrailing
import com.example.gymapp.ui.components.appLanguageOptions
import com.example.gymapp.ui.components.nativeName
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import com.example.gymapp.sync.CloudSyncUiStatus
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.getString
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.ui.theme.TintedButton

/** The Profile root and the screens it pushes: Friends & live, the Garmin watch and the optional tip jar. */
private enum class ProfileDestination {
    Root,
    Friends,
    Garmin,
    Support
}

/** Where the "С другом" pill on Today asks Profile to open. */
enum class ProfileFocusRequest {
    Account,
    Friends,
    Invites
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
    focusRequest: ProfileFocusRequest? = null,
    onFocusRequestHandled: () -> Unit = {},
    trainingProfile: TrainingProfile? = null,
    onTrainingProfileChange: (TrainingProfile) -> Unit = {},
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
    onImportFile: (open: () -> java.io.InputStream?) -> Unit,
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
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    onRetryLoad: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    var showPasswordChange by rememberSaveable { mutableStateOf(false) }
    var showAccountDeletion by rememberSaveable { mutableStateOf(false) }
    var showLocalProfileDeletion by rememberSaveable { mutableStateOf(false) }
    var showLocalProfileDeletionConfirmation by rememberSaveable { mutableStateOf(false) }
    var destination by rememberSaveable { mutableStateOf(ProfileDestination.Root) }
    var showTrainingSettings by rememberSaveable { mutableStateOf(false) }
    var showAccountSettings by rememberSaveable { mutableStateOf(false) }
    if (showTrainingSettings && trainingProfile != null) {
        TrainingSettingsSheet(
            profile = trainingProfile,
            onProfileChange = onTrainingProfileChange,
            onDismiss = { showTrainingSettings = false }
        )
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) onEnablePush()
    }
    val enablePushWithPermission: () -> Unit = {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            onEnablePush()
        }
    }
    if (showAccountSettings) {
        AccountSettingsSheet(
            state = accountState,
            actionsEnabled = !isAccountActionLoading,
            pushUiState = pushUiState,
            cloudSyncStatus = cloudSyncStatus,
            cloudSyncChoiceRequired = cloudSyncChoiceRequired,
            cloudSyncChoiceReady = cloudSyncChoiceReady,
            onReviewCloudSync = onReviewCloudSync,
            onSyncNow = onSyncNow,
            onEnablePush = enablePushWithPermission,
            onDisablePush = onDisablePush,
            onOpenPushSettings = onOpenPushSettings,
            onExportBackup = onExportBackup,
            onChangePassword = { showPasswordChange = true },
            onLogout = onLogout,
            onDeleteAccount = { showAccountDeletion = true },
            onDeleteLocalProfile = { showLocalProfileDeletion = true },
            onDismiss = { showAccountSettings = false }
        )
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
    LaunchedEffect(focusRequest) {
        val request = focusRequest ?: return@LaunchedEffect
        // Account and cloud sign-in live on the root; friends and live invitations in Friends & live.
        destination = if (request == ProfileFocusRequest.Account) {
            ProfileDestination.Root
        } else {
            ProfileDestination.Friends
        }
        onFocusRequestHandled()
    }
    LaunchedEffect(focusedSocialPush, focusedLiveRoomId) {
        if (focusedSocialPush != null || focusedLiveRoomId != null) {
            destination = ProfileDestination.Friends
        }
    }

    // A local profile has no cloud account to sync friends through, so it never leaves the root.
    val visibleDestination = if (!accountState.isCloudAccount && destination == ProfileDestination.Friends) {
        ProfileDestination.Root
    } else {
        destination
    }
    BackHandler(enabled = visibleDestination != ProfileDestination.Root) {
        destination = ProfileDestination.Root
    }

    val pendingAttentionCount = (friendsState.dashboard?.incoming?.size ?: 0) +
        (friendsState.workoutInbox?.pendingIncomingCount ?: 0) +
        (liveWorkoutState.inbox?.invitations?.size ?: 0)
    val identityLabel = accountState.accountLabel.ifBlank {
        stringResource(R.string.title_profile)
    }
    val identityFriendCount = friendsState.dashboard?.friends?.size ?: 0
    Column(modifier = modifier.fillMaxSize()) {
        when (visibleDestination) {
            ProfileDestination.Friends -> {
                ProfileSubScreenHeader(
                    title = stringResource(R.string.profile_friends_live_title),
                    onBack = { destination = ProfileDestination.Root }
                )
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
                    onOpenAccountSettings = { showAccountSettings = true },
                    focusedSocialPush = focusedSocialPush,
                    focusedLiveRoomId = focusedLiveRoomId,
                    modifier = Modifier.weight(1f)
                )
            }
            ProfileDestination.Garmin -> {
                ProfileSubScreenHeader(
                    title = stringResource(R.string.garmin_row_title),
                    onBack = { destination = ProfileDestination.Root }
                )
                LazyColumn(
                    modifier = Modifier.weight(1f),
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
                            onResetGarminPairing = { showGarminResetConfirmation = true }
                        )
                    }
                }
            }
            ProfileDestination.Support -> {
                ProfileSubScreenHeader(
                    title = stringResource(R.string.support_tips_title),
                    onBack = { destination = ProfileDestination.Root }
                )
                SupportTipsScreen(modifier = Modifier.weight(1f))
            }
            ProfileDestination.Root -> {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(
                        start = screenHorizontalPadding,
                        top = GymSpacing.ScreenTop,
                        end = screenHorizontalPadding,
                        bottom = GymSpacing.ScreenBottom
                    ),
                    verticalArrangement = Arrangement.spacedBy(ProfileSectionGap)
                ) {
                    profileRootContent(
                        accountState = accountState,
                        context = context,
                        identityLabel = identityLabel,
                        identityFriendCount = identityFriendCount,
                        pendingAttentionCount = pendingAttentionCount,
                        onOpenFriends = { destination = ProfileDestination.Friends },
                        onOpenAccountSettings = { showAccountSettings = true },
                        onOpenGarmin = { destination = ProfileDestination.Garmin },
                        onOpenSupport = { destination = ProfileDestination.Support },
                        garminDeviceState = garminDeviceState,
                        backupMessage = accountState.backupMessage,
                        onExportBackup = onExportBackup,
                        onExportDiagnostics = onExportDiagnostics,
                        onOpenImport = onOpenImport,
                        onShowTutorial = onShowTutorial,
                        onRetryLoad = onRetryLoad,
                        trainingProfile = trainingProfile,
                        onEditTrainingSettings = { showTrainingSettings = true },
                        selectedLanguage = selectedLanguage,
                        onLanguageSelected = onLanguageSelected
                    )
                }
            }
        }
    }

    AccountBackupSheets(
        uiState = accountState,
        backupShareOwnerKey = backupShareOwnerKey,
        onClearBackup = onClearBackup,
        onCloseImport = onCloseImport,
        onImportJsonChange = onImportJsonChange,
        onImportFile = onImportFile,
        onImportBackup = onImportBackup
    )

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
        GymAlertDialog(
            onDismissRequest = {
                if (!isAccountActionLoading) showLocalProfileDeletion = false
            },
            title = stringResource(R.string.local_profile_delete_confirm_title),
            text = {
                Text(formattedStringResource(R.string.local_profile_delete_warning, localProfileName))
            },
            confirmButton = {
                GymAlertDialogButton(
                    onClick = {
                        showLocalProfileDeletion = false
                        showLocalProfileDeletionConfirmation = true
                    },
                    enabled = !isAccountActionLoading,
                    role = GymAlertDialogButtonRole.Destructive
                ) {
                    Text(stringResource(R.string.local_profile_delete_confirm))
                }
            },
            dismissButton = {
                GymAlertDialogButton(
                    onClick = { showLocalProfileDeletion = false },
                    enabled = !isAccountActionLoading,
                    role = GymAlertDialogButtonRole.Cancel
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
    if (showLocalProfileDeletionConfirmation && localProfileName != null) {
        DeleteLocalProfileConfirmationDialog(
            profileName = localProfileName,
            actionsEnabled = !isAccountActionLoading,
            onDismiss = { showLocalProfileDeletionConfirmation = false },
            onConfirm = {
                showLocalProfileDeletionConfirmation = false
                onDeleteLocalProfile()
            }
        )
    }
}

private const val DELETE_CONFIRMATION_WORD = "DELETE"

/**
 * Mirrors the iPhone rule: surrounding whitespace is ignored, the word is case-sensitive. Shared by
 * the local-profile and the cloud-account deletion dialogs.
 */
internal fun localProfileDeletionConfirmationMatches(input: String): Boolean =
    input.trim() == DELETE_CONFIRMATION_WORD

@Composable
private fun DeleteLocalProfileConfirmationDialog(
    profileName: String,
    actionsEnabled: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    var confirmation by rememberSaveable { mutableStateOf("") }
    val confirmationLabel = stringResource(R.string.local_profile_delete_typed_label)
    val matches = localProfileDeletionConfirmationMatches(confirmation)
    GymAlertDialog(
        onDismissRequest = {
            if (actionsEnabled) onDismiss()
        },
        title = stringResource(R.string.local_profile_delete_action),
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = profileName,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(stringResource(R.string.local_profile_delete_typed_explanation))
                TextField(
                    value = confirmation,
                    onValueChange = { confirmation = it.take(16) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = confirmationLabel },
                    label = { Text(confirmationLabel) },
                    placeholder = { Text(DELETE_CONFIRMATION_WORD) },
                    supportingText = {
                        Text(stringResource(R.string.local_profile_delete_typed_hint))
                    },
                    singleLine = true,
                    shape = GymControlShape,
                    colors = planEditorFieldColors(),
                    textStyle = MaterialTheme.typography.bodyLarge,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Characters,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Done
                    )
                )
            }
        },
        confirmButton = {
            GymAlertDialogButton(
                onClick = onConfirm,
                enabled = matches && actionsEnabled,
                role = GymAlertDialogButtonRole.Destructive
            ) {
                Text(stringResource(R.string.local_profile_delete_typed_confirm))
            }
        },
        dismissButton = {
            GymAlertDialogButton(
                onClick = onDismiss,
                enabled = actionsEnabled,
                role = GymAlertDialogButtonRole.Cancel
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}

private val ProfileSectionGap = 28.dp

/** The Profile header group: person glyph, name, one status line, and the "waiting for you" count. */
@Composable
private fun ProfileIdentityHeader(
    label: String,
    isCloudAccount: Boolean,
    friendCount: Int,
    pendingCount: Int,
    modifier: Modifier = Modifier
) {
    GroupedSection(modifier = modifier) {
        row {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleLarge
                    )
                    Text(
                        text = if (isCloudAccount) {
                            formattedStringResource(R.string.profile_cloud_friend_count, friendCount)
                        } else {
                            stringResource(R.string.profile_local_storage_status)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (pendingCount > 0) {
                    val attentionLabel = formattedStringResource(R.string.profile_attention_count, pendingCount)
                    Badge(modifier = Modifier.clearAndSetSemantics { contentDescription = attentionLabel }) {
                        Text(pendingCount.coerceAtMost(99).toString())
                    }
                }
            }
        }
    }
}

/** Header of a screen pushed from the Profile root: accent back chevron and a one-line title. */
@Composable
private fun ProfileSubScreenHeader(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(end = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AppleBackButton(
            onClick = onBack,
            contentDescription = stringResource(R.string.cd_back)
        )
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
    }
}

/**
 * The Profile root as grouped sections: identity, Account, Workouts, Devices, App, Data and Help. Rows
 * carry a status at most; the Garmin watch card and Friends & live open as their own screens.
 */
private fun LazyListScope.profileRootContent(
    accountState: ExerciseListUiState,
    context: android.content.Context,
    identityLabel: String,
    identityFriendCount: Int,
    pendingAttentionCount: Int,
    onOpenFriends: () -> Unit,
    onOpenAccountSettings: () -> Unit,
    onOpenGarmin: () -> Unit,
    onOpenSupport: () -> Unit,
    garminDeviceState: GarminDeviceUiState,
    backupMessage: com.example.gymapp.util.LocalizedText?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit,
    onShowTutorial: () -> Unit,
    onRetryLoad: () -> Unit,
    trainingProfile: TrainingProfile?,
    onEditTrainingSettings: () -> Unit,
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
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
    item {
        ProfileIdentityHeader(
            label = identityLabel,
            isCloudAccount = accountState.isCloudAccount,
            friendCount = identityFriendCount,
            pendingCount = pendingAttentionCount
        )
    }
    item {
        // Identity, sync, notifications, sign-out and deletion live in the account sheet.
        val friendsTitle = stringResource(R.string.profile_friends_live_title)
        val friendsSubtitle = if (accountState.isCloudAccount) {
            null
        } else {
            stringResource(R.string.profile_friends_live_requires_cloud)
        }
        val accountTitle = stringResource(R.string.account_sheet_title)
        GroupedSection(header = stringResource(R.string.profile_group_account)) {
            row(
                title = friendsTitle,
                subtitle = friendsSubtitle,
                chevron = true,
                onClick = if (accountState.isCloudAccount) onOpenFriends else onOpenAccountSettings
            )
            row(
                title = accountTitle,
                chevron = true,
                onClick = onOpenAccountSettings
            )
        }
    }
    item {
        val trainingTitle = stringResource(R.string.training_settings_title)
        val trainingSummary = trainingProfile?.trainingSettingsSummary()
        GroupedSection(header = stringResource(R.string.profile_group_workouts)) {
            if (trainingSummary != null) {
                row(
                    title = trainingTitle,
                    subtitle = trainingSummary,
                    chevron = true,
                    onClick = onEditTrainingSettings
                )
            }
            row { ProfileKeepScreenOnRow() }
            row { ProfileHapticsRow() }
        }
    }
    item {
        val watchConnected = garminDeviceState.sdkReady && garminDeviceState.devices.any { it.connected }
        val watchTitle = stringResource(R.string.garmin_row_title)
        val watchStatus = stringResource(
            if (watchConnected) R.string.garmin_status_connected
            else R.string.garmin_status_not_connected
        )
        GroupedSection(header = stringResource(R.string.profile_group_devices)) {
            row(
                title = watchTitle,
                value = watchStatus,
                chevron = true,
                onClick = onOpenGarmin
            )
        }
    }
    item {
        val analytics = rememberConversionAnalytics()
        GroupedSection(
            header = stringResource(R.string.profile_group_app),
            footer = if (analytics.available) stringResource(R.string.analytics_setting_subtitle) else null
        ) {
            row {
                ProfileLanguageRow(
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = onLanguageSelected
                )
            }
            if (analytics.available) {
                row { ProfileAdMeasurementRow() }
            }
        }
    }
    item {
        ProfileDataSection(
            message = backupMessage,
            onExportBackup = onExportBackup,
            onExportDiagnostics = onExportDiagnostics,
            onOpenImport = onOpenImport
        )
    }
    item {
        val helpTitle = stringResource(R.string.profile_help_title)
        val helpSubtitle = stringResource(R.string.profile_help_replay_tour)
        val supportTitle = stringResource(R.string.support_tips_title)
        GroupedSection(header = stringResource(R.string.profile_group_help)) {
            row(
                title = helpTitle,
                subtitle = helpSubtitle,
                chevron = true,
                onClick = onShowTutorial
            )
            row(
                title = supportTitle,
                chevron = true,
                onClick = onOpenSupport
            )
        }
    }
}

/**
 * Backup and diagnostics: one row that unfolds the three export / import actions as plain accent rows
 * inside the same group; the last backup status, when there is one, is the group footer.
 */
@Composable
private fun ProfileDataSection(
    message: com.example.gymapp.util.LocalizedText?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val reduceMotion = rememberReduceMotion()
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 90f else 0f,
        animationSpec = if (reduceMotion) snap() else GymMotion.snappySpring(),
        label = "profileDataChevron"
    )
    val accent = MaterialTheme.colorScheme.primary
    val toolsTitle = stringResource(R.string.backup_tools_title)
    val exportTitle = stringResource(R.string.backup_export_json)
    val importTitle = stringResource(R.string.backup_import_json)
    val diagnosticsTitle = stringResource(R.string.backup_export_diagnostics)
    val chevronTint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    GroupedSection(
        header = stringResource(R.string.profile_group_data),
        footer = message?.asString()
    ) {
        row(
            title = toolsTitle,
            onClick = { expanded = !expanded },
            trailing = {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp).rotate(chevronRotation),
                    tint = chevronTint
                )
            }
        )
        if (expanded) {
            row(title = exportTitle, titleColor = accent, onClick = onExportBackup)
            row(title = importTitle, titleColor = accent, onClick = onOpenImport)
            row(
                title = diagnosticsTitle,
                titleColor = accent,
                onClick = onExportDiagnostics
            )
        }
    }
}

/**
 * Haptics row: one in-app switch (default on) for every haptic the app generates. The whole row is the
 * toggle; the OS touch-feedback setting still applies on top of it.
 */
@Composable
private fun ProfileHapticsRow() {
    val preference = rememberHapticsPreference()
    val enabled by preference.enabled.collectAsState()
    GroupedRow(
        title = stringResource(R.string.settings_haptics_title),
        modifier = Modifier.toggleable(
            value = enabled,
            role = Role.Switch,
            onValueChange = preference::setEnabled
        ),
        trailing = { Switch(checked = enabled, onCheckedChange = null, colors = gymSwitchColors()) }
    )
}

/**
 * Keep-screen-on row: a device-local switch (default on) that holds the screen awake while the active
 * workout screen is visible. The whole row is the toggle.
 */
@Composable
private fun ProfileKeepScreenOnRow() {
    val preference = rememberKeepScreenOnPreference()
    val enabled by preference.enabled.collectAsState()
    GroupedRow(
        title = stringResource(R.string.keep_awake_setting_title),
        modifier = Modifier.toggleable(
            value = enabled,
            role = Role.Switch,
            onValueChange = preference::setEnabled
        ),
        trailing = { Switch(checked = enabled, onCheckedChange = null, colors = gymSwitchColors()) }
    )
}

/**
 * Ad-measurement row: the same consent the first-launch prompt asks for, changeable at any time. The
 * caller only adds it in builds that can measure. The whole row is the toggle.
 */
@Composable
private fun ProfileAdMeasurementRow() {
    val analytics = rememberConversionAnalytics()
    val consent by analytics.consent.collectAsState()
    val enabled = consent == true
    GroupedRow(
        title = stringResource(R.string.analytics_setting_title),
        modifier = Modifier.toggleable(
            value = enabled,
            role = Role.Switch,
            onValueChange = analytics::setConsent
        ),
        trailing = { Switch(checked = enabled, onCheckedChange = null, colors = gymSwitchColors()) }
    )
}

/**
 * Language row: the trailing value is the current language's own name, and the whole row opens
 * the same three-language menu the sign-in screen offers, anchored under the value.
 */
@Composable
private fun ProfileLanguageRow(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val languageLabel = stringResource(R.string.cd_language)
    Box {
        GroupedRow(
            title = stringResource(R.string.language_button),
            value = selectedLanguage.nativeName(),
            trailing = {
                Icon(
                    imageVector = Icons.Default.UnfoldMore,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            onClick = { expanded = true },
            modifier = Modifier.semantics { onClick(label = languageLabel, action = null) }
        )
        Box(Modifier.align(Alignment.CenterEnd)) {
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                appLanguageOptions().forEach { (language, label) ->
                    val isSelected = language == selectedLanguage
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = label,
                                color = if (isSelected) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                }
                            )
                        },
                        trailingIcon = if (isSelected) {
                            {
                                Icon(
                                    imageVector = Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        } else {
                            null
                        },
                        onClick = {
                            expanded = false
                            onLanguageSelected(language)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun GarminDeviceCard(
    state: GarminDeviceUiState,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit
) {
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
                    if (device.liteMode) {
                        Text(
                            text = stringResource(R.string.garmin_lite_free_only_notice),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
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

    GymAlertDialog(
        onDismissRequest = onDismiss,
        title = stringResource(R.string.account_change_password),
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
                    TextField(
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
                        shape = GymControlShape,
                        colors = planEditorFieldColors(),
                        textStyle = MaterialTheme.typography.bodyLarge,
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
            GymAlertDialogButton(
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
            GymAlertDialogButton(
                enabled = !isLoading,
                onClick = onDismiss,
                role = GymAlertDialogButtonRole.Cancel
            ) {
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
    TextField(
        value = value,
        onValueChange = { onValueChange(boundedAuthPasswordDraft(it)) },
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        shape = GymControlShape,
        colors = planEditorFieldColors(),
        textStyle = MaterialTheme.typography.bodyLarge,
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
    GymAlertDialog(
        onDismissRequest = onDismiss,
        title = stringResource(R.string.account_delete_title),
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.account_delete_warning))
                ProfilePasswordField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    label = stringResource(R.string.account_current_password)
                )
                TextField(
                    value = confirmation,
                    onValueChange = { confirmation = it.take(16) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.account_delete_confirmation_label)) },
                    supportingText = {
                        Text(stringResource(R.string.account_delete_confirmation_hint))
                    },
                    singleLine = true,
                    shape = GymControlShape,
                    colors = planEditorFieldColors(),
                    textStyle = MaterialTheme.typography.bodyLarge
                )
            }
        },
        confirmButton = {
            GymAlertDialogButton(
                enabled = localProfileDeletionConfirmationMatches(confirmation) &&
                    currentPassword.isNotEmpty(),
                onClick = { onConfirm(currentPassword) },
                role = GymAlertDialogButtonRole.Destructive
            ) {
                Text(stringResource(R.string.account_delete_confirm))
            }
        },
        dismissButton = {
            GymAlertDialogButton(onClick = onDismiss, role = GymAlertDialogButtonRole.Cancel) {
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
    NEW_PASSWORD_POLICY_ERROR -> R.string.auth_error_password_minimum
    "Passwords do not match." -> R.string.auth_error_password_mismatch
    else -> R.string.auth_password_update_failed
}
