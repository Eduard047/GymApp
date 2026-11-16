package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.ui.components.tabularDigits
import com.example.gymapp.ui.theme.GymControlShape
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

/**
 * Small editor for one exercise's cue; [onSave] takes the raw text (empty removes the cue). While
 * [limitReached] the dialog stays open with an inline error until the text changes ([onEdited]).
 *
 * Laid out like the iPhone cue sheet: a borderless tonal field with an example placeholder, the
 * counter (or the error) under it, and "Clear" as a separate red text action above Cancel / Save.
 */
@Composable
internal fun ExerciseCueDialog(
    initialCue: String?,
    limitReached: Boolean = false,
    onEdited: () -> Unit = {},
    onSave: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var text by remember { mutableStateOf(initialCue.orEmpty()) }
    val cueLabel = stringResource(R.string.exercise_cue_label)
    GymAlertDialog(
        onDismissRequest = onDismiss,
        title = stringResource(if (initialCue == null) R.string.exercise_cue_add else R.string.exercise_cue_edit),
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                TextField(
                    value = text,
                    onValueChange = { next ->
                        onEdited()
                        val singleLine = next.replace('\n', ' ').replace('\r', ' ')
                        text = if (singleLine.codePointCount(0, singleLine.length) > EXERCISE_CUE_MAX_CODE_POINTS) {
                            singleLine.substring(0, singleLine.offsetByCodePoints(0, EXERCISE_CUE_MAX_CODE_POINTS))
                        } else {
                            singleLine
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = cueLabel },
                    textStyle = MaterialTheme.typography.bodyLarge,
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.exercise_cue_placeholder)) },
                    isError = limitReached,
                    shape = GymControlShape,
                    colors = planEditorFieldColors()
                )
                if (limitReached) {
                    Text(
                        text = stringResource(R.string.exercise_cue_too_many),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                } else {
                    Text(
                        text = "${text.codePointCount(0, text.length)} / $EXERCISE_CUE_MAX_CODE_POINTS",
                        style = MaterialTheme.typography.bodySmall.tabularDigits(),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (initialCue != null) {
                    TextButton(
                        onClick = { onSave("") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp),
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text(
                            text = stringResource(R.string.exercise_cue_clear),
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                }
            }
        },
        confirmButton = {
            GymAlertDialogButton(onClick = { onSave(text) }) { Text(stringResource(R.string.action_save)) }
        },
        dismissButton = {
            GymAlertDialogButton(onClick = onDismiss, role = GymAlertDialogButtonRole.Cancel) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}
