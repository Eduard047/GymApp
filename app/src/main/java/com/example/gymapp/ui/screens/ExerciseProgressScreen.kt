package com.example.gymapp.ui.screens

import com.example.gymapp.ui.components.GymProgressBar
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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
import com.example.gymapp.ui.components.GymMonthNavigator
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
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
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    val selectedRawExerciseName = uiState.selectedExerciseName
    val selectedDisplayExerciseName = if (selectedRawExerciseName != null) {
        localizedExerciseName(selectedRawExerciseName)
    } else {
        null
    }
    val spotlightSubtitle = stringResource(
        R.string.progress_spotlight_subtitle,
        pluralStringResource(
            R.plurals.progress_sessions_count,
            uiState.progressPoints.size,
            uiState.progressPoints.size
        )
    )
    val localizedSpotlight = uiState.spotlight.copy(
        title = selectedDisplayExerciseName ?: uiState.spotlight.title,
        subtitle = spotlightSubtitle
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
            start = screenHorizontalPadding,
            top = GymSpacing.ScreenTop,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
    ) {
            item {
                GymMonthNavigator(
                    monthLabel = uiState.monthLabel,
                    isCurrentMonth = uiState.monthOffset == 0,
                    onPrevious = onPreviousMonth,
                    onCurrent = onCurrentMonth,
                    onNext = onNextMonth,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            item {
                ExerciseSelectorCard(
                    uiState = uiState,
                    exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                    onSelectExercise = onSelectExercise
                )
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

                if (sessionGroups.isEmpty()) {
                    item {
                        EmptyStatePanel(
                            title = stringResource(R.string.progress_empty_month_title),
                            supporting = stringResource(R.string.progress_empty_month_text),
                            icon = Icons.AutoMirrored.Filled.ShowChart,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                } else {
                    item {
                        ExerciseSpotlightCard(spotlight = localizedSpotlight)
                    }

                    item {
                        ExerciseTrendChartsCard(chart = uiState.trendChart)
                    }

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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProgressMuscleBreakdownCard(
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
    val largeText = LocalDensity.current.fontScale >= 1.4f
    val title: @Composable (Modifier) -> Unit = { titleModifier ->
        Text(
            text = stringResource(R.string.progress_muscle_breakdown_title),
            modifier = titleModifier.semantics { heading() },
            style = MaterialTheme.typography.titleMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
    val groupsPill: @Composable () -> Unit = {
        InfoPill(
            text = pluralStringResource(
                R.plurals.progress_muscle_groups_count,
                sortedMuscles.size,
                sortedMuscles.size
            ),
            leadingIcon = Icons.Default.FitnessCenter
        )
    }

    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (largeText) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    title(Modifier)
                    groupsPill()
                }
            } else {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    title(Modifier.padding(end = 10.dp))
                    groupsPill()
                }
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
                    GymProgressBar(
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
private fun ExerciseSelectorCard(
    uiState: ExerciseProgressUiState,
    exerciseMediaOwnerKey: String,
    onSelectExercise: (Long) -> Unit
) {
    val selectedExercise = uiState.exercises.firstOrNull { it.id == uiState.selectedExerciseId }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_choose_exercise),
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleMedium
            )
            ExerciseCatalogSelector(
                selectedExerciseId = uiState.selectedExerciseId,
                exercises = uiState.exercises,
                frequentExerciseIds = uiState.frequentExerciseIds,
                exerciseWorkoutCounts = uiState.exerciseWorkoutCounts,
                exerciseMuscleIds = uiState.exerciseMuscleIds,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onExerciseSelected = onSelectExercise,
                trigger = selectedExercise?.let { exercise ->
                    { openPicker ->
                        val sessionCount = uiState.exerciseWorkoutCounts[exercise.id] ?: 0
                        val exerciseName = localizedExerciseName(exercise.name)
                        val changeLabel = stringResource(R.string.cd_change_exercise)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            ExerciseMediaPreview(
                                exerciseId = exercise.id,
                                exerciseName = exercise.name,
                                ownerKey = exerciseMediaOwnerKey,
                                width = 84.dp,
                                height = 68.dp
                            )
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 48.dp)
                                    .clickable(role = Role.Button, onClick = openPicker)
                                    .semantics(mergeDescendants = true) {
                                        contentDescription = changeLabel
                                        stateDescription = exerciseName
                                    },
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Text(
                                        text = exerciseName,
                                        style = MaterialTheme.typography.titleMedium,
                                        maxLines = 3,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = stringResource(
                                            R.string.progress_logged_sessions,
                                            sessionCount
                                        ),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .size(38.dp)
                                        .clip(CircleShape)
                                        .background(
                                            MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                                        ),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Search,
                                        contentDescription = null,
                                        modifier = Modifier.size(20.dp),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }
                }
            )
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
                    modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
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
