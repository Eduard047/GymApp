package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.example.gymapp.R
import com.example.gymapp.util.EXERCISE_CUE_MAX_CODE_POINTS

/** Overflow item that opens the cue editor: "Add cue" without a cue, "Edit cue" with one. */
@Composable
internal fun ExerciseCueMenuItem(hasCue: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = {
            Text(stringResource(if (hasCue) R.string.exercise_cue_edit else R.string.exercise_cue_add))
        },
        leadingIcon = { Icon(imageVector = Icons.Default.EditNote, contentDescription = null) },
        onClick = onClick
    )
}

/** Small editor for one exercise's cue; [onSave] takes the raw text (empty removes the cue). */
@Composable
internal fun ExerciseCueDialog(
    initialCue: String?,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var text by remember { mutableStateOf(initialCue.orEmpty()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(stringResource(if (initialCue == null) R.string.exercise_cue_add else R.string.exercise_cue_edit))
        },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { next ->
                    val singleLine = next.replace('\n', ' ').replace('\r', ' ')
                    text = if (singleLine.codePointCount(0, singleLine.length) > EXERCISE_CUE_MAX_CODE_POINTS) {
                        singleLine.substring(0, singleLine.offsetByCodePoints(0, EXERCISE_CUE_MAX_CODE_POINTS))
                    } else {
                        singleLine
                    }
                },
                singleLine = true,
                label = { Text(stringResource(R.string.exercise_cue_label)) },
                placeholder = { Text(stringResource(R.string.exercise_cue_placeholder)) },
                supportingText = {
                    Text("${text.codePointCount(0, text.length)} / $EXERCISE_CUE_MAX_CODE_POINTS")
                }
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(text) }) { Text(stringResource(R.string.action_save)) }
        },
        dismissButton = {
            Row {
                if (initialCue != null) {
                    TextButton(onClick = { onSave("") }) { Text(stringResource(R.string.exercise_cue_clear)) }
                }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        }
    )
}
