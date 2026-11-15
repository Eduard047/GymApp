package com.example.gymapp.ui.components

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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.util.formattedStringResource

/**
 * The app-wide resume bar shows while a workout is active but minimised: never on the Today tab
 * (its focus card already offers continue and, in its menu, discard) and never on the active-workout screen.
 */
internal fun shouldShowContinueWorkoutBar(
    hasActiveWorkout: Boolean,
    isActiveWorkoutRoute: Boolean,
    isTodayRoute: Boolean
): Boolean = hasActiveWorkout && !isActiveWorkoutRoute && !isTodayRoute

/**
 * Inset tonal resume row (iOS `Continue workout` bar): play icon, "Continue workout", the completed /
 * planned sets as secondary text, and a chevron. The whole row is the tap target. There is no discard
 * action here: discarding is one tap from "Continue", so it lives on the Today card menu and the active
 * workout menu, both behind a confirmation.
 */
@Composable
fun ContinueWorkoutBar(
    completedSets: Int,
    totalSets: Int,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        color = HeroTone.surface,
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clickable(role = Role.Button, onClick = onContinue)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.PlayCircle,
                contentDescription = null,
                tint = HeroTone.actionLabel,
                modifier = Modifier.size(28.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.action_continue_workout),
                    style = MaterialTheme.typography.bodyLarge,
                    color = HeroTone.actionLabel,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = formattedStringResource(
                        R.string.continue_workout_bar_progress,
                        completedSets,
                        totalSets
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = HeroTone.supporting,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = HeroTone.supporting,
                modifier = Modifier.size(20.dp)
            )
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
