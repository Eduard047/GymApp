package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.ExerciseSpotlightCard
import com.example.gymapp.ui.components.ExerciseTrendChartsCard
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.util.DateTimeUtils
import java.util.Locale

private data class ProgressSessionHistoryGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

private data class ProgressMetricUi(
    val label: String,
    val value: String,
    val emphasized: Boolean = false
)

@Composable
fun ExerciseProgressScreen(
    uiState: ExerciseProgressUiState,
    exerciseMediaOwnerKey: String,
    onSelectExercise: (Long) -> Unit,
    onPreviousMonth: () -> Unit,
    onCurrentMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier
) {
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

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = GymSpacing.ScreenHorizontal,
            top = GymSpacing.ScreenTop,
            end = GymSpacing.ScreenHorizontal,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
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
                ExerciseCatalogSelector(
                    selectedExerciseId = uiState.selectedExerciseId,
                    exercises = uiState.exercises,
                    frequentExerciseIds = uiState.frequentExerciseIds,
                    exerciseWorkoutCounts = uiState.exerciseWorkoutCounts,
                    exerciseMuscleIds = uiState.exerciseMuscleIds,
                    exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                    onExerciseSelected = onSelectExercise
                )
            }

            uiState.exercises.firstOrNull { it.id == uiState.selectedExerciseId }?.let { exercise ->
                item(key = "selected_exercise_media_${exercise.id}") {
                    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            ExerciseMediaPreview(
                                exerciseId = exercise.id,
                                exerciseName = exercise.name,
                                ownerKey = exerciseMediaOwnerKey,
                                width = 96.dp,
                                height = 80.dp
                            )
                            Text(
                                text = localizedExerciseName(exercise.name),
                                style = MaterialTheme.typography.titleLarge,
                                modifier = Modifier.weight(1f),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }

            if (selectedDisplayExerciseName == null) {
                item {
                    EmptyStatePanel(
                        title = stringResource(R.string.empty_exercises),
                        supporting = stringResource(R.string.chart_no_data),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } else {
                if (selectedMuscleIntensities.isNotEmpty()) {
                    item {
                        ProgressMuscleBreakdownCard(
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
                        EmptyStatePanel(
                            title = stringResource(R.string.empty_progress),
                            supporting = stringResource(
                                R.string.progress_log_sets_hint,
                                selectedDisplayExerciseName
                            ),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                } else {
                    item {
                        SectionTitle(
                            eyebrow = stringResource(R.string.progress_recent_sessions_title),
                            title = stringResource(R.string.progress_history_title),
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }

                    items(
                        items = sessionGroups,
                        key = { it.sessionId }
                    ) { sessionGroup ->
                        ProgressSessionHistoryCard(
                            sessionGroup = sessionGroup
                        )
                    }
                }
            }
    }
}

@Composable
private fun ProgressMuscleBreakdownCard(
    exerciseName: String,
    muscleIntensities: Map<String, Float>,
    modifier: Modifier = Modifier
) {
    val languageTag = currentAppLanguageTag()
    val sortedMuscles = remember(muscleIntensities, languageTag) {
        muscleIntensities
            .filterValues { it > 0f }
            .toList()
            .sortedByDescending { it.second }
    }

    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    text = stringResource(R.string.muscle_heatmap_top_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = localizedExerciseName(exerciseName),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            sortedMuscles.forEach { (muscleId, intensity) ->
                val normalizedIntensity = intensity.coerceIn(0f, 1f)
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = localizedMuscleName(muscleId, languageTag),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "${(normalizedIntensity * 100f).toInt()}%",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    LinearProgressIndicator(
                        progress = { normalizedIntensity },
                        modifier = Modifier.fillMaxWidth(),
                        color = if (normalizedIntensity >= 0.75f) {
                            MaterialTheme.colorScheme.tertiary
                        } else {
                            MaterialTheme.colorScheme.primary
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
    val metrics = listOf(
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_sessions),
            value = sessionCount.toString()
        ),
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_total_sets),
            value = setCount.toString()
        ),
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_total_reps),
            value = totalReps.toString()
        ),
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_best_weight),
            value = uiState.bestWeight?.let {
                stringResource(R.string.progress_weight_value, it)
            } ?: "—",
            emphasized = true
        ),
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_avg_weight),
            value = uiState.averageWeight?.let {
                stringResource(R.string.progress_weight_value, it)
            } ?: "—"
        ),
        ProgressMetricUi(
            label = stringResource(R.string.progress_stat_total_volume),
            value = String.format(Locale.getDefault(), "%.0f", totalVolume)
        )
    )

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_summary_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.progress_summary_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            metrics.chunked(2).forEach { rowMetrics ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    rowMetrics.forEach { metric ->
                        MetricTile(
                            label = metric.label,
                            value = metric.value,
                            modifier = Modifier.weight(1f),
                            emphasized = metric.emphasized
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProgressSessionHistoryCard(
    sessionGroup: ProgressSessionHistoryGroup
) {
    val totalVolume = sessionGroup.sets.sumOf { it.weight * it.reps }
    val totalReps = sessionGroup.sets.sumOf { it.reps }

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = DateTimeUtils.formatDate(sessionGroup.sessionDate),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                InfoPill(text = stringResource(R.string.stats_sets, sessionGroup.sets.size))
            }

            Text(
                text = "${stringResource(R.string.progress_reps_value, totalReps)} • " +
                    stringResource(R.string.stats_volume, totalVolume),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f))

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
                }
                if (setIndex < sessionGroup.sets.lastIndex) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
                    )
                }
            }
        }
    }
}
