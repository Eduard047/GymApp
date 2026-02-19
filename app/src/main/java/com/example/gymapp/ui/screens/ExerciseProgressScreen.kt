package com.example.gymapp.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.viewmodel.ExerciseProgressPoint
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.launch

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

    Box(
        modifier = modifier.fillMaxSize()
    ) {
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

            item { ProgressSummaryCard(uiState) }
            item { MaxWeightLineChartCard(uiState.progressPoints) }
            item { VolumeBarChartCard(uiState.progressPoints) }

            if (uiState.history.isEmpty()) {
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
                items(
                    items = uiState.history,
                    key = { it.setId }
                ) { historyEntry ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = DateTimeUtils.formatDate(historyEntry.sessionDate),
                                style = MaterialTheme.typography.titleSmall
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.progress_weight_value, historyEntry.weight),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.progress_reps_value, historyEntry.reps),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                IconButton(
                                    onClick = {
                                        onDeleteHistoryEntry(historyEntry.setId)
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                message = setDeletedMessage
                                            )
                                        }
                                    }
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
    val selectedName = exercises.firstOrNull { it.first == selectedExerciseId }?.second
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
                        text = { Text(exercise.second) },
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
private fun ProgressSummaryCard(uiState: ExerciseProgressUiState) {
    val totalReps = uiState.progressPoints.sumOf { it.totalReps }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_summary_title),
                style = MaterialTheme.typography.titleSmall
            )
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
                    label = stringResource(R.string.progress_stat_total_reps),
                    value = totalReps.toString(),
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
private fun MaxWeightLineChartCard(points: List<ExerciseProgressPoint>) {
    val lineColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_chart_max_weight),
                style = MaterialTheme.typography.titleSmall
            )

            if (points.isEmpty()) {
                Text(
                    text = stringResource(R.string.chart_no_data),
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(170.dp)
                        .padding(top = 4.dp)
                ) {
                    val maxValue = (points.maxOfOrNull { it.maxWeight } ?: 1.0).toFloat().coerceAtLeast(1f)
                    val chartHeight = size.height
                    val chartWidth = size.width
                    val horizontalStep = if (points.size <= 1) 0f else chartWidth / (points.size - 1)

                    repeat(4) { index ->
                        val y = chartHeight * index / 3f
                        drawLine(
                            color = gridColor,
                            start = Offset(0f, y),
                            end = Offset(chartWidth, y),
                            strokeWidth = 2f
                        )
                    }

                    val path = Path()
                    points.forEachIndexed { index, point ->
                        val x = index * horizontalStep
                        val normalized = (point.maxWeight.toFloat() / maxValue).coerceIn(0f, 1f)
                        val y = chartHeight - (normalized * chartHeight)
                        if (index == 0) {
                            path.moveTo(x, y)
                        } else {
                            path.lineTo(x, y)
                        }
                    }

                    drawPath(
                        path = path,
                        color = lineColor,
                        style = Stroke(width = 6f, cap = StrokeCap.Round)
                    )

                    points.forEachIndexed { index, point ->
                        val x = index * horizontalStep
                        val normalized = (point.maxWeight.toFloat() / maxValue).coerceIn(0f, 1f)
                        val y = chartHeight - (normalized * chartHeight)
                        drawCircle(
                            color = lineColor,
                            radius = 7f,
                            center = Offset(x, y)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VolumeBarChartCard(points: List<ExerciseProgressPoint>) {
    val barColor = MaterialTheme.colorScheme.secondary

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_chart_volume),
                style = MaterialTheme.typography.titleSmall
            )

            if (points.isEmpty()) {
                Text(
                    text = stringResource(R.string.chart_no_data),
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(155.dp)
                ) {
                    val maxValue = (points.maxOfOrNull { it.totalVolume } ?: 1.0).toFloat().coerceAtLeast(1f)
                    val slotWidth = size.width / points.size
                    val barWidth = slotWidth * 0.62f

                    points.forEachIndexed { index, point ->
                        val normalized = (point.totalVolume.toFloat() / maxValue).coerceIn(0f, 1f)
                        val barHeight = normalized * size.height
                        val left = index * slotWidth + (slotWidth - barWidth) / 2f
                        drawRoundRect(
                            color = barColor,
                            topLeft = Offset(left, size.height - barHeight),
                            size = Size(barWidth, barHeight),
                            cornerRadius = CornerRadius(10f, 10f)
                        )
                    }
                }
            }
        }
    }
}
