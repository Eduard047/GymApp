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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.util.formattedPluralStringResource

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
    // 16 dp inset on phones; in landscape / on tablets the bar is capped to the shared max content width and centred.
    val horizontalInset = adaptiveHorizontalPadding(
        windowWidth = LocalConfiguration.current.screenWidthDp.dp,
        minimumPadding = 16.dp
    )
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = horizontalInset, vertical = 6.dp),
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
            val largeText = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.5f
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.action_continue_workout),
                    style = MaterialTheme.typography.bodyLarge,
                    color = HeroTone.actionLabel,
                    // Largest text sizes: the title wraps instead of ending as "Продолжить трен…".
                    maxLines = if (largeText) 2 else 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = formattedPluralStringResource(
                        R.plurals.active_workout_hero_sets_done,
                        totalSets,
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
    GymAlertDialog(
        onDismissRequest = onDismiss,
        title = stringResource(R.string.active_workout_discard_title),
        text = { Text(stringResource(R.string.active_workout_discard_message)) },
        confirmButton = {
            GymAlertDialogButton(onClick = onConfirm, role = GymAlertDialogButtonRole.Destructive) {
                Text(stringResource(R.string.active_workout_discard_confirm))
            }
        },
        dismissButton = {
            GymAlertDialogButton(onClick = onDismiss, role = GymAlertDialogButtonRole.Cancel) {
                Text(stringResource(R.string.active_workout_discard_keep))
            }
        }
    )
}
