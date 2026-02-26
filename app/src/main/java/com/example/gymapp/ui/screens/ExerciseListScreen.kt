package com.example.gymapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private data class ExerciseHistorySessionGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExerciseListScreen(
    uiState: ExerciseListUiState,
    onNameChange: (String) -> Unit,
    onAddExercise: () -> Unit,
    onExerciseClick: (Long) -> Unit,
    onDeleteExercise: (ExerciseEntity) -> Unit,
    onDismissHistory: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = uiState.newExerciseName,
                onValueChange = onNameChange,
                modifier = Modifier.weight(1f),
                label = { Text(stringResource(R.string.label_exercise_name)) },
                placeholder = { Text(stringResource(R.string.hint_exercise_name)) },
                singleLine = true
            )
            OutlinedButton(onClick = onAddExercise) {
                Text(text = stringResource(R.string.action_add_exercise))
            }
        }

        if (uiState.hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }

        if (uiState.exercises.isEmpty()) {
            Text(
                text = stringResource(R.string.empty_exercises),
                style = MaterialTheme.typography.bodyLarge
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(
                    items = uiState.exercises,
                    key = { it.id }
                ) { exercise ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onExerciseClick(exercise.id) }
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = exercise.name,
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge
                            )
                            IconButton(onClick = { onDeleteExercise(exercise) }) {
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

    val selectedExerciseId = uiState.selectedExerciseId
    val selectedExerciseName = uiState.selectedExerciseName
    if (selectedExerciseId != null && selectedExerciseName != null) {
        ModalBottomSheet(onDismissRequest = onDismissHistory) {
            ExerciseHistoryBottomSheetContent(
                exerciseName = selectedExerciseName,
                history = uiState.selectedExerciseHistory
            )
        }
    }
}

@Composable
private fun ExerciseHistoryBottomSheetContent(
    exerciseName: String,
    history: List<ExerciseHistoryEntry>
) {
    val locale = Locale.getDefault()
    val zoneId = ZoneId.systemDefault()
    val monthFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    val dayFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEEE, d MMMM", locale) }
    val timeFormatter = remember(locale) { DateTimeFormatter.ofPattern("HH:mm", locale) }

    val sessionGroups = remember(history) {
        history
            .groupBy { it.sessionId }
            .values
            .map { entries ->
                ExerciseHistorySessionGroup(
                    sessionId = entries.first().sessionId,
                    sessionDate = entries.first().sessionDate,
                    sets = entries.sortedBy { it.setOrderIndex }
                )
            }
            .sortedByDescending { it.sessionDate }
    }

    val sessionsByMonth = remember(sessionGroups, zoneId) {
        sessionGroups.groupBy { group ->
            YearMonth.from(Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate())
        }.toSortedMap(compareByDescending { it })
    }

    val totalVolume = remember(history) { history.sumOf { it.weight * it.reps } }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = exerciseName,
                style = MaterialTheme.typography.headlineSmall
            )
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sessions),
                        value = sessionGroups.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sets),
                        value = history.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_volume),
                        value = String.format(locale, "%.0f", totalVolume),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        if (history.isEmpty()) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = stringResource(R.string.exercise_history_empty),
                        modifier = Modifier.padding(14.dp),
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
            }
            return@LazyColumn
        }

        sessionsByMonth.forEach { (month, monthSessions) ->
            item(key = "month_$month") {
                Text(
                    text = month.format(monthFormatter).replaceFirstChar {
                        if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            val sessionsByDay = monthSessions.groupBy { group ->
                Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate()
            }.toSortedMap(compareByDescending { it })

            sessionsByDay.forEach { (day, daySessions) ->
                item(key = "day_${month}_$day") {
                    Text(
                        text = day.format(dayFormatter).replaceFirstChar {
                            if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                        },
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                items(
                    items = daySessions,
                    key = { group -> group.sessionId }
                ) { sessionGroup ->
                    val timeText = Instant.ofEpochMilli(sessionGroup.sessionDate)
                        .atZone(zoneId)
                        .toLocalTime()
                        .format(timeFormatter)
                    ExerciseHistorySessionCard(
                        sessionGroup = sessionGroup,
                        timeText = timeText
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ExerciseHistorySessionCard(
    sessionGroup: ExerciseHistorySessionGroup,
    timeText: String
) {
    val locale = Locale.getDefault()
    val totalVolume = sessionGroup.sets.sumOf { it.weight * it.reps }
    val maxWeight = sessionGroup.sets.maxOfOrNull { it.weight } ?: 0.0

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.session_item_title, timeText),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.progress_weight_value, maxWeight),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.exercise_history_sets_inline, sessionGroup.sets.size),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = stringResource(R.string.exercise_history_volume_inline, String.format(locale, "%.0f", totalVolume)),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            HorizontalDivider()

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

            sessionGroup.sets.forEachIndexed { index, set ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_set, index + 1),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = formatWeightShort(set.weight),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = set.reps.toString(),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }
}

private fun formatWeightShort(weight: Double): String {
    return if (weight % 1.0 == 0.0) {
        weight.toInt().toString()
    } else {
        String.format(Locale.getDefault(), "%.1f", weight)
    }
}
