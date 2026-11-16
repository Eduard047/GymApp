package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.ui.theme.Button

@Composable
internal fun CloudSyncConflictDialog(
    cloudVersionAvailable: Boolean,
    cloudVersionNeedsRepair: Boolean,
    resolving: Boolean,
    backingUp: Boolean,
    onBackupFirst: () -> Unit,
    onKeepDeviceVersion: () -> Unit,
    onUseCloudVersion: () -> Unit,
    onDismiss: () -> Unit
) {
    // GymAlertDialog scrolls its text itself and gives a lone confirm slot the full width, so the
    // three choices stack as capsules: one filled primary, a red-label neutral one, a neutral "not now".
    GymAlertDialog(
        onDismissRequest = { if (!resolving) onDismiss() },
        title = stringResource(R.string.cloud_sync_conflict_title),
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = stringResource(R.string.cloud_sync_conflict_description),
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = stringResource(R.string.cloud_sync_conflict_backup_hint),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (!cloudVersionAvailable) {
                    Text(
                        text = stringResource(
                            if (cloudVersionNeedsRepair) {
                                R.string.cloud_sync_conflict_cloud_unverified
                            } else {
                                R.string.cloud_sync_conflict_cloud_missing
                            }
                        ),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(
                        R.string.cloud_sync_conflict_keep_device_description
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Button(
                    onClick = onKeepDeviceVersion,
                    enabled = !resolving && !backingUp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 52.dp)
                ) {
                    Text(stringResource(
                        if (resolving) R.string.cloud_sync_conflict_resolving
                        else R.string.cloud_sync_conflict_keep_device
                    ))
                }
                if (cloudVersionAvailable) {
                    Text(
                        text = stringResource(
                            R.string.cloud_sync_conflict_use_cloud_description
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    GymAlertDialogButton(
                        onClick = onUseCloudVersion,
                        enabled = !resolving && !backingUp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp),
                        role = GymAlertDialogButtonRole.Destructive
                    ) {
                        Text(stringResource(R.string.cloud_sync_conflict_use_cloud))
                    }
                }
                GymAlertDialogButton(
                    onClick = onBackupFirst,
                    enabled = !resolving && !backingUp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp),
                    role = GymAlertDialogButtonRole.Cancel
                ) {
                    Text(stringResource(R.string.cloud_sync_conflict_not_now))
                }
            }
        }
    )
}
