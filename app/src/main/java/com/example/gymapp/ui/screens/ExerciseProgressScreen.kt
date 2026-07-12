package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.components.ExerciseSpotlightCard
import com.example.gymapp.ui.components.ExerciseTrendChartsCard
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.launch
import java.util.Locale

private data class ProgressSessionHistoryGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

@Composable
fun ExerciseProgressScreen(
    uiState: ExerciseProgressUiState,
    onSelectExercise: (Long) -> Unit,
    onDeleteHistoryEntry: (Long) -> Unit,
    onPreviousMonth: () -> Unit,
    onCurrentMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val coroutineScope = rememberCoroutineScope()
    val setDeletedMessage = stringResource(R.string.message_set_deleted)
    val selectedRawExerciseName = uiState.selectedExerciseName
    val selectedDisplayExerciseName = if (selectedRawExerciseName != null) {
        localizedExerciseName(selectedRawExerciseName)
    } else {
        null
    }
    val localizedSpotlight = uiState.spotlight.copy(
        title = selectedDisplayExerciseName ?: uiState.spotlight.title,
        subtitle = if (selectedDisplayExerciseName != null && uiState.progressPoints.isEmpty()) {
            stringResource(R.string.progress_log_sets_hint, selectedDisplayExerciseName)
        } else {
            uiState.spotlight.subtitle
        }
    )
    val selectedMuscleIntensities = remember(uiState.selectedExerciseName) {
        uiState.selectedExerciseName
            ?.let { defaultContributionsForExercise(it) }
            .orEmpty()
            .associate { contribution -> contribution.muscleId to contribution.weight.toFloat() }
    }

    val sessionGroups = remember(uiState.history) {
        uiState.history
            .groupBy { it.sessionId }
            .values
            .map { entries ->
                ProgressSessionHistoryGroup(
                    sessionId = entries.first().sessionId,
                    sessionDate = entries.first().sessionDate,
                    sets = entries.sortedBy { it.setOrderIndex }
                )
            }
            .sortedByDescending { it.sessionDate }
    }

    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 12.dp,
                top = 10.dp,
                end = 12.dp,
                bottom = 24.dp
            ),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                MonthSwitcher(
                    monthLabel = uiState.monthLabel,
                    isCurrentMonth = uiState.monthOffset == 0,
                    onPreviousMonth = onPreviousMonth,
                    onCurrentMonth = onCurrentMonth,
                    onNextMonth = onNextMonth,
                    modifier = Modifier.padding(horizontal = 0.dp)
                )
            }

            item {
                ExerciseProgressSelector(
                    selectedExerciseId = uiState.selectedExerciseId,
                    exercises = uiState.exercises.map { it.id to it.name },
                    onSelectExercise = onSelectExercise
                )
            }

            if (selectedMuscleIntensities.isNotEmpty()) {
                item {
                    ExerciseMuscleBreakdownCard(
                        exerciseName = uiState.selectedExerciseName.orEmpty(),
                        muscleIntensities = selectedMuscleIntensities
                    )
                }
            }

            item {
                ProgressSummaryCard(
                    uiState = uiState,
                    sessionCount = sessionGroups.size,
                    setCount = uiState.history.size,
                    totalVolume = uiState.history.sumOf { it.weight * it.reps }
                )
            }

            item {
                ExerciseSpotlightCard(spotlight = localizedSpotlight)
            }

            item {
                ExerciseTrendChartsCard(chart = uiState.trendChart)
            }

            if (sessionGroups.isEmpty()) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = stringResource(R.string.empty_progress),
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.padding(14.dp)
                        )
                    }
                }
            } else {
                item {
                    Text(
                        text = stringResource(R.string.progress_history_title),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                }

                items(
                    items = sessionGroups,
                    key = { it.sessionId }
                ) { sessionGroup ->
                    ProgressSessionHistoryCard(
                        sessionGroup = sessionGroup,
                        onDeleteHistoryEntry = { setId ->
                            onDeleteHistoryEntry(setId)
                            coroutineScope.launch {
                                snackbarHostState.showSnackbar(message = setDeletedMessage)
                            }
                        }
                    )
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(12.dp)
        )
    }
}

@Composable
private fun ExerciseProgressSelector(
    selectedExerciseId: Long?,
    exercises: List<Pair<Long, String>>,
    onSelectExercise: (Long) -> Unit
) {
    var expanded by remember(selectedExerciseId, exercises) { mutableStateOf(false) }
    val selectedRawName = exercises.firstOrNull { it.first == selectedExerciseId }?.second
    val selectedName = selectedRawName?.let { localizedExerciseName(it) }
        ?: stringResource(R.string.label_select_exercise)

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = stringResource(R.string.label_exercise),
            style = MaterialTheme.typography.labelLarge
        )
        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                onClick = { expanded = true },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = selectedName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                exercises.forEach { exercise ->
                    DropdownMenuItem(
                        text = { Text(localizedExerciseName(exercise.second)) },
                        onClick = {
                            onSelectExercise(exercise.first)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ProgressSummaryCard(
    uiState: ExerciseProgressUiState,
    sessionCount: Int,
    setCount: Int,
    totalVolume: Double
) {
    val totalReps = uiState.progressPoints.sumOf { it.totalReps }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_summary_title),
                style = MaterialTheme.typography.titleSmall
            )
            Text(
                text = stringResource(R.string.progress_summary_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_sessions),
                    value = sessionCount.toString(),
                    modifier = Modifier.weight(1f)
                )
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_total_sets),
                    value = setCount.toString(),
                    modifier = Modifier.weight(1f)
                )
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_total_reps),
                    value = totalReps.toString(),
                    modifier = Modifier.weight(1f)
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_best_weight),
                    value = uiState.bestWeight?.let {
                        stringResource(R.string.progress_weight_value, it)
                    } ?: stringResource(R.string.chart_no_data),
                    modifier = Modifier.weight(1f)
                )
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_avg_weight),
                    value = uiState.averageWeight?.let {
                        stringResource(R.string.progress_weight_value, it)
                    } ?: stringResource(R.string.chart_no_data),
                    modifier = Modifier.weight(1f)
                )
                ProgressMetric(
                    label = stringResource(R.string.progress_stat_total_volume),
                    value = String.format(Locale.getDefault(), "%.0f", totalVolume),
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun ProgressMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ProgressSessionHistoryCard(
    sessionGroup: ProgressSessionHistoryGroup,
    onDeleteHistoryEntry: (Long) -> Unit
) {
    val totalVolume = sessionGroup.sets.sumOf { it.weight * it.reps }
    val totalReps = sessionGroup.sets.sumOf { it.reps }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = DateTimeUtils.formatDate(sessionGroup.sessionDate),
                style = MaterialTheme.typography.titleSmall
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.stats_sets, sessionGroup.sets.size),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = stringResource(R.string.progress_reps_value, totalReps),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.stats_volume, totalVolume),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_set_short),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_weight_kg),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_reps),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = "",
                    modifier = Modifier.weight(0.55f)
                )
            }

            sessionGroup.sets.forEachIndexed { setIndex, set ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_set, setIndex + 1),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = String.format(Locale.getDefault(), "%.1f", set.weight),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = set.reps.toString(),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    IconButton(
                        onClick = { onDeleteHistoryEntry(set.setId) },
                        modifier = Modifier.weight(0.55f)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = stringResource(R.string.cd_delete)
                        )
                    }
                }
            }
        }
    }
}
