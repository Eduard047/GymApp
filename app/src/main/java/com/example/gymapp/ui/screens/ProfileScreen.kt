package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.saveable.rememberSaveable
import com.example.gymapp.R
import com.example.gymapp.auth.LeaderboardRow
import com.example.gymapp.garmin.openGymWorkoutTrackerInGarminStore
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.SoloProgressUiModel
import com.example.gymapp.util.LocalizedText

@Composable
fun ProfileScreen(
    accountState: ExerciseListUiState,
    rows: List<LeaderboardRow>,
    soloProgress: SoloProgressUiModel,
    isLeaderboardLoading: Boolean,
    leaderboardError: LocalizedText?,
    onRefreshLeaderboard: () -> Unit,
    cloudSyncChoiceRequired: Boolean,
    cloudSyncChoiceReady: Boolean,
    onReviewCloudSync: () -> Unit,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onClearBackup: () -> Unit,
    onOpenImport: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onLogout: () -> Unit,
    isAccountActionLoading: Boolean,
    onChangePassword: (currentPassword: String, newPassword: String) -> Unit,
    onDeleteCloudAccount: () -> Unit,
    onResetGarminPairing: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    var showGarminResetConfirmation by rememberSaveable { mutableStateOf(false) }
    var showPasswordChange by rememberSaveable { mutableStateOf(false) }
    var showAccountDeletion by rememberSaveable { mutableStateOf(false) }

    LeaderboardScreen(
        rows = rows,
        soloProgress = soloProgress,
        isLoading = isLeaderboardLoading,
        error = leaderboardError,
        onRefresh = onRefreshLeaderboard,
        headerContent = {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.title_profile),
                        style = MaterialTheme.typography.headlineLarge
                    )
                    Text(
                        text = stringResource(R.string.profile_screen_subtitle),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            item {
                AccountStatusCard(
                    label = accountState.accountLabel.ifBlank {
                        context.getString(R.string.account_mode_local)
                    },
                    supporting = accountState.accountSupporting.ifBlank {
                        context.getString(R.string.account_offline_supporting)
                    },
                    isCloudAccount = accountState.isCloudAccount,
                    canLogout = accountState.canLogout,
                    logoutEnabled = !isAccountActionLoading,
                    onLogout = onLogout,
                    onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) },
                    onResetGarminPairing = { showGarminResetConfirmation = true }
                )
            }
            if (accountState.isCloudAccount && cloudSyncChoiceRequired) {
                item {
                    CloudSyncChoiceCard(
                        choiceReady = cloudSyncChoiceReady,
                        onReview = onReviewCloudSync
                    )
                }
            }
            if (accountState.isCloudAccount) {
                item {
                    CloudAccountActionsCard(
                        enabled = !isAccountActionLoading,
                        onChangePassword = { showPasswordChange = true },
                        onDeleteAccount = { showAccountDeletion = true }
                    )
                }
            }
            item {
                BackupToolsCard(
                    message = accountState.backupMessage,
                    onExportBackup = onExportBackup,
                    onExportDiagnostics = onExportDiagnostics,
                    onOpenImport = onOpenImport
                )
            }
        },
        modifier = modifier.fillMaxSize()
    )

    AccountBackupSheets(
        uiState = accountState,
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
            onDismiss = { showPasswordChange = false },
            onConfirm = { currentPassword, newPassword ->
                showPasswordChange = false
                onChangePassword(currentPassword, newPassword)
            }
        )
    }

    if (showAccountDeletion) {
        DeleteCloudAccountDialog(
            onDismiss = { showAccountDeletion = false },
            onConfirm = {
                showAccountDeletion = false
                onDeleteCloudAccount()
            }
        )
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
    onDismiss: () -> Unit,
    onConfirm: (currentPassword: String, newPassword: String) -> Unit
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var repeatedPassword by remember { mutableStateOf("") }
    var validationMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.account_change_password)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.account_change_password_supporting))
                ProfilePasswordField(
                    value = currentPassword,
                    onValueChange = {
                        currentPassword = it
                        validationMessage = null
                    },
                    label = stringResource(R.string.account_current_password)
                )
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
                onClick = {
                    val validation = validateSignedInPasswordChange(
                        currentPassword = currentPassword,
                        newPassword = newPassword,
                        repeatedPassword = repeatedPassword
                    )
                    if (validation == null) {
                        onConfirm(currentPassword, newPassword)
                    } else {
                        validationMessage = validation
                    }
                }
            ) {
                Text(stringResource(R.string.auth_update_password))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
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
        onValueChange = { onValueChange(it.take(1_024)) },
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
    onConfirm: () -> Unit
) {
    var confirmation by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.account_delete_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.account_delete_warning))
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
                enabled = confirmation == "DELETE",
                onClick = onConfirm
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
    repeatedPassword: String
): String? = when {
    currentPassword.isEmpty() -> "Enter your current password."
    currentPassword.toByteArray(Charsets.UTF_8).size > 1_024 ->
        "Current password is too long."
    currentPassword == newPassword ->
        "Choose a new password that differs from the current password."
    else -> validatePasswordUpdateInput(newPassword, repeatedPassword)
}

private fun profileAuthValidationResource(message: String): Int = when (message) {
    "Enter your current password." -> R.string.account_current_password_required
    "Current password is too long." -> R.string.account_current_password_too_long
    "Choose a new password that differs from the current password." ->
        R.string.account_new_password_must_differ
    "Enter a new password." -> R.string.auth_error_new_password_required
    "Password must contain at least 12 characters and fit within 72 UTF-8 bytes." ->
        R.string.auth_error_password_minimum
    "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol." ->
        R.string.auth_error_password_complexity
    "Passwords do not match." -> R.string.auth_error_password_mismatch
    else -> R.string.auth_password_update_failed
}
