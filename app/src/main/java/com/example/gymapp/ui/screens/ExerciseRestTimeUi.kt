package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.util.EXERCISE_REST_MAX_SECONDS
import com.example.gymapp.util.EXERCISE_REST_MIN_SECONDS
import com.example.gymapp.util.EXERCISE_REST_STEP_SECONDS
import com.example.gymapp.util.formattedStringResource

/** Overflow item that opens the rest-time picker for one exercise. */
@Composable
internal fun ExerciseRestTimeMenuItem(onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(stringResource(R.string.exercise_rest_menu)) },
        leadingIcon = { Icon(imageVector = Icons.Default.Timer, contentDescription = null) },
        onClick = onClick
    )
}

/**
 * Small picker for one exercise's rest: a 15 s stepper between 0:15 and 10:00 that starts at the
 * custom rest, else at the [defaultSeconds]. [onSave] takes the chosen seconds, or null for "Use default".
 */
@Composable
internal fun ExerciseRestTimeDialog(
    customSeconds: Int?,
    defaultSeconds: Int,
    limitReached: Boolean = false,
    onEdited: () -> Unit = {},
    onSave: (Int?) -> Unit,
    onDismiss: () -> Unit
) {
    val initial = (customSeconds ?: defaultSeconds).coerceIn(EXERCISE_REST_MIN_SECONDS, EXERCISE_REST_MAX_SECONDS)
    var seconds by remember { mutableIntStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.exercise_rest_title)) },
        text = {
            Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        enabled = seconds > EXERCISE_REST_MIN_SECONDS,
                        onClick = {
                            onEdited()
                            seconds = (seconds - EXERCISE_REST_STEP_SECONDS).coerceAtLeast(EXERCISE_REST_MIN_SECONDS)
                        }
                    ) {
                        Icon(Icons.Default.Remove, contentDescription = stringResource(R.string.active_workout_rest_subtract))
                    }
                    Text(
                        text = restClockLabel(seconds).orEmpty(),
                        style = MaterialTheme.typography.headlineMedium,
                        textAlign = TextAlign.Center
                    )
                    IconButton(
                        enabled = seconds < EXERCISE_REST_MAX_SECONDS,
                        onClick = {
                            onEdited()
                            seconds = (seconds + EXERCISE_REST_STEP_SECONDS).coerceAtMost(EXERCISE_REST_MAX_SECONDS)
                        }
                    ) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.active_workout_rest_add))
                    }
                }
                if (limitReached) {
                    Text(
                        text = stringResource(R.string.exercise_rest_too_many),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                } else if (customSeconds != null) {
                    Text(
                        text = formattedStringResource(R.string.exercise_rest_default_hint, restClockLabel(defaultSeconds).orEmpty()),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { if (customSeconds == null && seconds == initial) onDismiss() else onSave(seconds) }) {
                Text(stringResource(R.string.action_save))
            }
        },
        dismissButton = {
            Row {
                if (customSeconds != null) {
                    TextButton(onClick = { onSave(null) }) { Text(stringResource(R.string.exercise_rest_use_default)) }
                }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        }
    )
}
