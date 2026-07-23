package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R

@Composable
internal fun CloudSyncConflictDialog(
    cloudVersionAvailable: Boolean,
    cloudVersionNeedsRepair: Boolean,
    resolving: Boolean,
    onKeepDeviceVersion: () -> Unit,
    onUseCloudVersion: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = { if (!resolving) onDismiss() },
        title = { Text(stringResource(R.string.cloud_sync_conflict_title)) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(stringResource(R.string.cloud_sync_conflict_description))
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
                    enabled = !resolving,
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
                    OutlinedButton(
                        onClick = onUseCloudVersion,
                        enabled = !resolving,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp),
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error
                        )
                    ) {
                        Text(stringResource(R.string.cloud_sync_conflict_use_cloud))
                    }
                }
                TextButton(
                    onClick = onDismiss,
                    enabled = !resolving,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.cloud_sync_conflict_not_now))
                }
            }
        }
    )
}
