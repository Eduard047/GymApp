package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import androidx.compose.foundation.clickable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import com.example.gymapp.util.TrainingProfile
import java.util.Locale
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.gymapp.util.CurrentDaySignal
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.WeeklyReview
import com.example.gymapp.data.repository.WeeklyReviewInsight
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.formattedPluralStringResource
import androidx.compose.ui.text.font.FontWeight
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.util.formatVolumeTotal

/**
 * "This week" as grouped blocks: the week switcher with three headline numbers (workouts, sets,
 * volume with its unit) and the weekly goal row, then the comparison with last week and the week's
 * workouts, each only when there is data. Nothing is explained: an empty block is simply absent.
 */
@Composable
fun WeeklyReviewCard(
    history: List<ExerciseHistoryEntry>,
    target: Int,
    onOpenWorkout: (Long) -> Unit,
    trainingProfile: TrainingProfile = TrainingProfile(workoutsPerWeek = target.coerceIn(2, 6)),
    onTrainingProfileChange: (TrainingProfile) -> Unit = {}
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    var showTrainingSettings by rememberSaveable { mutableStateOf(false) }
    if (showTrainingSettings) {
        TrainingSettingsSheet(
            profile = trainingProfile,
            onProfileChange = onTrainingProfileChange,
            onDismiss = { showTrainingSettings = false },
            scrollToWorkoutsPerWeek = true
        )
    }
    var offset by rememberSaveable { mutableIntStateOf(0) }
    var evidence by remember { mutableStateOf<WeeklyReviewInsight?>(null) }
    // Reading the current day recomposes the card (and rebuilds the review) after midnight.
    val today = CurrentDaySignal.state.collectAsStateWithLifecycle().value.date
    val review = WeeklyReview.build(history, offset)
    // The card follows the finger between weeks (rubber-banded at the current week); the chevrons stay.
    val swipe = rememberGymTrackedSwipe(
        canPrevious = offset > -520,
        canNext = offset < 0,
        onPrevious = { offset = (offset - 1).coerceAtLeast(-520) },
        onNext = { offset = (offset + 1).coerceAtMost(0) }
    )
    val goalValue = formattedPluralStringResource(
        R.plurals.training_weekly_progress, target, review.trainingDays, target
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(swipe.gesture)
            .graphicsLayer { translationX = swipe.offset },
        verticalArrangement = Arrangement.spacedBy(GymSpacing.XXLarge)
    ) {
        GroupedSection(
            header = stringResource(if (offset == 0) R.string.progress_week_title else R.string.training_weekly_review)
        ) {
            row {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { offset = (offset - 1).coerceAtLeast(-520) }, enabled = offset > -520) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.training_previous_week))
                    }
                    val spokenRange = DateTimeUtils.formatDateRangeSpoken(review.start, review.end, locale, today)
                    Text(
                        DateTimeUtils.formatDateRange(review.start, review.end, locale, today),
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = spokenRange },
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center
                    )
                    IconButton(onClick = { offset = (offset + 1).coerceAtMost(0) }, enabled = offset < 0) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.training_next_week))
                    }
                }
            }
            row {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GroupedListDefaults.TextInset, vertical = 14.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    WeekNumber(
                        value = review.trainingDays.toString(),
                        label = stringResource(R.string.progress_lifetime_workouts),
                        modifier = Modifier.weight(1f)
                    )
                    WeekNumber(
                        value = review.totalSets.toString(),
                        label = stringResource(R.string.muscle_heatmap_sets),
                        modifier = Modifier.weight(1f)
                    )
                    WeekNumber(
                        value = formattedStringResource(
                            R.string.today_history_volume_kg,
                            formatVolumeTotal(review.totalVolume, locale)
                        ),
                        label = stringResource(R.string.focus_lens_volume),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            row {
                GroupedRow(
                    title = stringResource(R.string.progress_week_goal),
                    value = goalValue,
                    chevron = true,
                    onClick = { showTrainingSettings = true }
                )
            }
        }
        if (review.insights.isNotEmpty()) {
            GroupedSection(header = stringResource(R.string.progress_week_compare)) {
                review.insights.forEach { insight ->
                    row {
                        GroupedRow(
                            title = localizedExerciseName(insight.current.exerciseName),
                            subtitle = formattedStringResource(
                                R.string.training_rep_comparison,
                                insight.current.weight,
                                insight.previous.reps,
                                insight.current.reps
                            ),
                            chevron = true,
                            onClick = { evidence = insight }
                        )
                    }
                }
            }
        }
        if (review.sessions.isNotEmpty()) {
            GroupedSection(header = stringResource(R.string.training_week_workouts)) {
                review.sessions.forEach { (id, date) ->
                    row {
                        GroupedRow(
                            title = DateTimeUtils.formatDate(date),
                            chevron = true,
                            onClick = { onOpenWorkout(id) }
                        )
                    }
                }
            }
        }
    }
    evidence?.let { insight ->
        GymAlertDialog(onDismissRequest = { evidence = null }, title = stringResource(R.string.training_comparison),
            text = { Column { listOf(insight.previous, insight.current).forEach { entry ->
                TextButton(onClick = { evidence = null; onOpenWorkout(entry.sessionId) }) {
                    Text(DateTimeUtils.formatDate(entry.sessionDate) + " · ${entry.weight} kg × ${entry.reps}")
                }
            } } }, confirmButton = { GymAlertDialogButton(onClick = { evidence = null }) { Text(stringResource(R.string.action_close)) } })
    }
}

@Composable
private fun WeekNumber(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1
        )
    }
}
