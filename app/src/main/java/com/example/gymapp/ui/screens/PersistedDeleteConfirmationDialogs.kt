package com.example.gymapp.ui.screens

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.repository.ExerciseDeletionSnapshot
import com.example.gymapp.data.repository.SetDeletionImpact
import com.example.gymapp.data.repository.SetDeletionSnapshot
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString
import java.util.Locale

@Composable
internal fun ExerciseDeleteConfirmationDialog(
    snapshot: ExerciseDeletionSnapshot,
    isDeleting: Boolean,
    error: LocalizedText?,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val exerciseName = localizedExerciseName(snapshot.exerciseName)
    PersistedDeleteConfirmationDialog(
        title = stringResource(R.string.dialog_delete_exercise_title),
        message = stringResource(R.string.dialog_delete_exercise_message, exerciseName),
        impact = stringResource(
            R.string.dialog_delete_exercise_impact,
            snapshot.workoutCount,
            snapshot.exerciseBlockCount,
            snapshot.setCount
        ),
        isDeleting = isDeleting,
        error = error,
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
internal fun SetDeleteConfirmationDialog(
    snapshot: SetDeletionSnapshot,
    isDeleting: Boolean,
    error: LocalizedText?,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val exerciseName = localizedExerciseName(snapshot.exerciseName)
    val weight = String.format(Locale.getDefault(), "%.1f", snapshot.weight)
    val impact = stringResource(setDeleteImpactTextResource(snapshot.impact))
    PersistedDeleteConfirmationDialog(
        title = stringResource(R.string.dialog_delete_set_title),
        message = stringResource(
            R.string.dialog_delete_set_message,
            snapshot.displayOrdinal,
            exerciseName,
            DateTimeUtils.formatDate(snapshot.sessionDate),
            weight,
            snapshot.reps
        ),
        impact = impact,
        isDeleting = isDeleting,
        error = error,
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@StringRes
internal fun setDeleteImpactTextResource(impact: SetDeletionImpact): Int = when (impact) {
    SetDeletionImpact.SetOnly -> R.string.dialog_delete_set_impact_set_only
    SetDeletionImpact.ExerciseBlock -> R.string.dialog_delete_set_impact_exercise
    SetDeletionImpact.WorkoutSession -> R.string.dialog_delete_set_impact_workout
}

@Composable
private fun PersistedDeleteConfirmationDialog(
    title: String,
    message: String,
    impact: String,
    isDeleting: Boolean,
    error: LocalizedText?,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = {
            if (!isDeleting) onDismiss()
        },
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(message)
                Text(
                    text = impact,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
                if (error != null) {
                    Text(
                        text = error.asString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                enabled = !isDeleting && error == null,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                )
            ) {
                if (isDeleting) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = MaterialTheme.colorScheme.onError,
                            strokeWidth = 2.dp
                        )
                        Text(stringResource(R.string.action_deleting))
                    }
                } else {
                    Text(stringResource(R.string.action_delete))
                }
            }
        },
        dismissButton = {
            OutlinedButton(
                onClick = onDismiss,
                enabled = !isDeleting
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}
