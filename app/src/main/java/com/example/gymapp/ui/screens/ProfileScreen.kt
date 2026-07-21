package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.LeaderboardRow
import com.example.gymapp.garmin.openGymWorkoutTrackerInGarminStore
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
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onClearBackup: () -> Unit,
    onOpenImport: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current

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
                    onLogout = onLogout,
                    onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) }
                )
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
}
