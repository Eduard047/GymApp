package com.example.gymapp.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.util.formattedStringResource

/**
 * The app-wide resume bar shows while a workout is active but minimised: never on the Today tab
 * (its focus card already offers continue / discard) and never on the active-workout screen.
 */
internal fun shouldShowContinueWorkoutBar(
    hasActiveWorkout: Boolean,
    isActiveWorkoutRoute: Boolean,
    isTodayRoute: Boolean
): Boolean = hasActiveWorkout && !isActiveWorkoutRoute && !isTodayRoute

/**
 * Inset tonal resume panel (iOS `Continue workout` bar): play icon, "Continue workout", completed
 * / planned sets, and a discard action that opens the existing discard confirmation. The discard
 * action is hidden while the workout is attached to a live room, as on iOS.
 */
@Composable
fun ContinueWorkoutBar(
    completedSets: Int,
    totalSets: Int,
    showsDiscard: Boolean,
    onContinue: () -> Unit,
    onDiscard: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        color = HeroTone.surface,
        shape = RoundedCornerShape(20.dp),
        border = BorderStroke(1.dp, HeroTone.outline)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 58.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 58.dp)
                    .clickable(role = Role.Button, onClick = onContinue)
                    .padding(start = 16.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayCircle,
                    contentDescription = null,
                    tint = HeroTone.actionLabel,
                    modifier = Modifier.size(28.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = stringResource(R.string.action_continue_workout),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = HeroTone.actionLabel
                    )
                    Text(
                        text = formattedStringResource(
                            R.string.continue_workout_bar_progress,
                            completedSets,
                            totalSets
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = HeroTone.supporting
                    )
                }
            }
            if (showsDiscard) {
                IconButton(
                    onClick = onDiscard,
                    modifier = Modifier.padding(end = 4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = stringResource(R.string.continue_workout_bar_discard),
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}

/** The discard-active-workout confirmation shared by the Today focus card and the resume bar. */
@Composable
fun ActiveWorkoutDiscardDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.active_workout_discard_title)) },
        text = { Text(stringResource(R.string.active_workout_discard_message)) },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text(stringResource(R.string.active_workout_discard_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.active_workout_discard_keep))
            }
        }
    )
}
