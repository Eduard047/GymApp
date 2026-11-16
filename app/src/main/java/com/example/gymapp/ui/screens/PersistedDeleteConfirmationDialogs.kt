package com.example.gymapp.ui.screens

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
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
import com.example.gymapp.util.formatWeightDisplay
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.formattedPluralStringResource

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
        message = formattedStringResource(R.string.dialog_delete_exercise_message, exerciseName),
        impact = if (snapshot.workoutCount == 0) {
            stringResource(R.string.dialog_delete_exercise_impact_unused)
        } else {
            val workouts = formattedPluralStringResource(
                R.plurals.dialog_delete_exercise_impact_workouts,
                snapshot.workoutCount,
                snapshot.workoutCount
            )
            val sets = formattedPluralStringResource(
                R.plurals.dialog_delete_exercise_impact_sets,
                snapshot.setCount,
                snapshot.setCount
            )
            if (snapshot.emptiedWorkoutCount > 0) {
                formattedStringResource(
                    R.string.dialog_delete_exercise_impact_with_emptied,
                    workouts,
                    sets,
                    formattedPluralStringResource(
                        R.plurals.dialog_delete_exercise_emptied_workouts,
                        snapshot.emptiedWorkoutCount,
                        snapshot.emptiedWorkoutCount
                    )
                )
            } else {
                formattedStringResource(R.string.dialog_delete_exercise_impact, workouts, sets)
            }
        },
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
    val weight = formatWeightDisplay(snapshot.weight, Locale.getDefault())
    val impact = stringResource(
        if (snapshot.retainsRecordedActivity) R.string.dialog_delete_set_impact_watch_activity
        else setDeleteImpactTextResource(snapshot.impact)
    )
    PersistedDeleteConfirmationDialog(
        title = stringResource(R.string.dialog_delete_set_title),
        message = formattedStringResource(
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
    GymAlertDialog(
        onDismissRequest = {
            if (!isDeleting) onDismiss()
        },
        title = title,
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(message)
                Text(
                    text = impact,
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
            GymAlertDialogButton(
                onClick = onConfirm,
                enabled = !isDeleting && error == null,
                role = GymAlertDialogButtonRole.Destructive
            ) {
                // Both labels are always laid out, so the button keeps one width (and the dialog one
                // button arrangement) when "Delete" turns into the "Deleting…" progress label.
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = stringResource(R.string.action_delete),
                        maxLines = 1,
                        modifier = if (isDeleting) HiddenLabel else Modifier
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = if (isDeleting) Modifier else HiddenLabel
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = MaterialTheme.colorScheme.error,
                            strokeWidth = 2.dp
                        )
                        Text(stringResource(R.string.action_deleting), maxLines = 1)
                    }
                }
            }
        },
        dismissButton = {
            GymAlertDialogButton(
                onClick = onDismiss,
                enabled = !isDeleting,
                role = GymAlertDialogButtonRole.Cancel
            ) {
                Text(stringResource(R.string.dialog_cancel), maxLines = 1)
            }
        }
    )
}

/** Keeps a label's size in the layout while hiding it from sight and from accessibility services. */
private val HiddenLabel = Modifier
    .alpha(0f)
    .clearAndSetSemantics { }
