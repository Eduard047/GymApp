package com.example.gymapp.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.ExerciseMuscleMap
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.WorkoutDetailEvent
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import java.util.Locale

private const val SETS_TABLE_SET_WEIGHT = 0.95f
private const val SETS_TABLE_WEIGHT_WEIGHT = 1.1f
private const val SETS_TABLE_REPS_WEIGHT = 0.9f
private val SETS_TABLE_ACTIONS_WIDTH = 104.dp

@Composable
fun WorkoutDetailScreen(
    uiState: WorkoutDetailUiState,
    events: Flow<WorkoutDetailEvent>,
    onAddExerciseToWorkout: (Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onDeleteSet: (SetEntryEntity) -> Unit,
    onDeleteSession: () -> Unit,
    onSessionDeleted: () -> Unit,
    onUpdateSet: (SetEntryEntity, String, String) -> Unit,
    onUndoDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var editingSet by remember { mutableStateOf<SetEntryEntity?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }
    var confirmDeleteSession by remember { mutableStateOf(false) }

    val exerciseTimerTargets = remember { mutableStateMapOf<Long, Long>() }
    var exerciseTimerNowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(exerciseTimerTargets.keys.toList(), exerciseTimerTargets.values.toList()) {
        if (exerciseTimerTargets.isEmpty()) return@LaunchedEffect

        while (exerciseTimerTargets.isNotEmpty()) {
            val now = System.currentTimeMillis()
            exerciseTimerNowMillis = now
            val expiredIds = exerciseTimerTargets
                .filterValues { it <= now }
                .keys
                .toList()
            expiredIds.forEach { exerciseTimerTargets.remove(it) }
            if (exerciseTimerTargets.isEmpty()) break
            delay(500)
        }
    }

    fun startExerciseTimer(workoutExerciseId: Long, seconds: Int) {
        if (seconds <= 0) return
        exerciseTimerNowMillis = System.currentTimeMillis()
        exerciseTimerTargets[workoutExerciseId] = exerciseTimerNowMillis + seconds * 1_000L
    }

    fun stopExerciseTimer(workoutExerciseId: Long) {
        exerciseTimerTargets.remove(workoutExerciseId)
    }

    fun remainingExerciseTimerSeconds(workoutExerciseId: Long): Int {
        val target = exerciseTimerTargets[workoutExerciseId] ?: return 0
        val remainingMillis = (target - exerciseTimerNowMillis).coerceAtLeast(0L)
        return ((remainingMillis + 999L) / 1_000L).toInt()
    }

    LaunchedEffect(events, context) {
        events.collect { event ->
            when (event) {
                WorkoutDetailEvent.SetDeleted -> {
                    val result = snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_set_deleted),
                        actionLabel = context.getString(R.string.action_undo),
                        duration = SnackbarDuration.Short
                    )
                    if (result == SnackbarResult.ActionPerformed) {
                        onUndoDelete()
                    }
                }

                WorkoutDetailEvent.SessionDeleted -> {
                    onSessionDeleted()
                }

                WorkoutDetailEvent.InvalidInput -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_invalid_set_input),
                        duration = SnackbarDuration.Short
                    )
                }
            }
        }
    }

    Box(
        modifier = modifier.fillMaxSize()
    ) {
        val details = uiState.sessionDetails
        if (details == null) {
            AppPanel(
                modifier = Modifier
                    .padding(14.dp)
                    .fillMaxWidth(),
                highlighted = true
            ) {
                Text(
                    text = stringResource(R.string.empty_detail),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(20.dp)
                )
            }
        } else {
            val garminMetrics = remember(details.session.note) {
                parseGarminWorkoutMetrics(details.session.note.orEmpty())
            }
            val isGarminWorkout = garminMetrics != null
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 14.dp,
                    top = 12.dp,
                    end = 14.dp,
                    bottom = 32.dp
                ),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                item {
                    if (garminMetrics != null) {
                        GarminWorkoutHeaderCard(
                            date = DateTimeUtils.formatDate(details.session.date),
                            metrics = garminMetrics,
                            exerciseCount = details.workoutExercises.size,
                            setCount = details.workoutExercises.sumOf { it.sets.size },
                            onDelete = { confirmDeleteSession = true }
                        )
                    } else {
                        WorkoutHeaderCard(
                            date = DateTimeUtils.formatDate(details.session.date),
                            note = details.session.note,
                            exerciseCount = details.workoutExercises.size,
                            setCount = details.workoutExercises.sumOf { it.sets.size },
                            volume = details.workoutExercises.sumOf { exercise ->
                                exercise.sets.sumOf { set -> set.weight * set.reps }
                            },
                            onDelete = { confirmDeleteSession = true }
                        )
                    }
                }

                if (garminMetrics != null) {
                    item {
                        GarminWorkoutMetricsCard(metrics = garminMetrics)
                    }
                }

                item {
                    WorkoutExerciseQuickAddCard(
                        availableExercises = uiState.availableExercisesToAdd,
                        onAddExerciseToWorkout = onAddExerciseToWorkout
                    )
                }

                items(
                    items = details.workoutExercises,
                    key = { it.workoutExercise.id }
                ) { exerciseDetails ->
                    val workoutExerciseId = exerciseDetails.workoutExercise.id
                    val localRestSecondsRemaining = remainingExerciseTimerSeconds(workoutExerciseId)
                    var isExpanded by rememberSaveable(workoutExerciseId, isGarminWorkout) {
                        mutableStateOf(!isGarminWorkout)
                    }
                    val muscleIntensities = remember(exerciseDetails.exercise.name) {
                        defaultContributionsForExercise(exerciseDetails.exercise.name)
                            .associate { contribution ->
                                contribution.muscleId to contribution.weight.toFloat()
                            }
                    }
                    val setCountLabel = stringResource(
                        R.string.exercise_set_count_compact,
                        exerciseDetails.sets.size
                    )
                    val setSummary = remember(exerciseDetails.sets, setCountLabel) {
                        val detailsText = exerciseDetails.sets.joinToString(separator = " · ") { set ->
                            "${formatCompactWeight(set.weight)} kg × ${set.reps}"
                        }
                        if (detailsText.isBlank()) setCountLabel else "$setCountLabel · $detailsText"
                    }

                    AppPanel(
                        modifier = Modifier.fillMaxWidth(),
                        highlighted = true
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = localizedExerciseName(exerciseDetails.exercise.name),
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                IconButton(onClick = { isExpanded = !isExpanded }) {
                                    Icon(
                                        imageVector = if (isExpanded) {
                                            Icons.Default.ExpandLess
                                        } else {
                                            Icons.Default.ExpandMore
                                        },
                                        contentDescription = stringResource(
                                            if (isExpanded) {
                                                R.string.cd_collapse_exercise
                                            } else {
                                                R.string.cd_expand_exercise
                                            }
                                        )
                                    )
                                }
                            }

                            if (
                                localRestSecondsRemaining > 0 ||
                                uiState.personalRecordFlags[workoutExerciseId] == true
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    if (localRestSecondsRemaining > 0) {
                                        InfoPill(
                                            text = stringResource(
                                                R.string.label_exercise_rest_remaining,
                                                formatTimerLabel(localRestSecondsRemaining)
                                            )
                                        )
                                    }
                                    if (uiState.personalRecordFlags[workoutExerciseId] == true) {
                                        InfoPill(
                                            text = stringResource(R.string.label_personal_record),
                                            accent = MaterialTheme.colorScheme.tertiary
                                        )
                                    }
                                }
                            }

                            if (!isExpanded) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    Text(
                                        text = setSummary,
                                        modifier = Modifier.weight(1f),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    if (muscleIntensities.isNotEmpty()) {
                                        ExerciseMuscleMap(
                                            muscleIntensities = muscleIntensities,
                                            modifier = Modifier.size(width = 96.dp, height = 72.dp)
                                        )
                                    }
                                }
                            }

                            if (isExpanded) {
                            if (!isGarminWorkout && muscleIntensities.isNotEmpty()) {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(
                                        text = stringResource(R.string.exercise_muscles_title),
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    ExerciseMuscleMap(
                                        muscleIntensities = muscleIntensities,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(132.dp)
                                    )
                                }
                            }

                            if (!isGarminWorkout) {
                                ExerciseRestTimerRow(
                                    restSecondsRemaining = localRestSecondsRemaining,
                                    onStart60 = { startExerciseTimer(workoutExerciseId, 60) },
                                    onStart90 = { startExerciseTimer(workoutExerciseId, 90) },
                                    onStart180 = { startExerciseTimer(workoutExerciseId, 180) },
                                    onStop = { stopExerciseTimer(workoutExerciseId) }
                                )
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.label_set_short),
                                    modifier = Modifier.weight(SETS_TABLE_SET_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_weight_kg),
                                    modifier = Modifier.weight(SETS_TABLE_WEIGHT_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_reps),
                                    modifier = Modifier.weight(SETS_TABLE_REPS_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Box(
                                    modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH)
                                )
                            }

                            exerciseDetails.sets.forEachIndexed { setIndex, setEntry ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(GymControlShape)
                                        .background(
                                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f)
                                        )
                                        .padding(vertical = 3.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        text = stringResource(R.string.label_set, setIndex + 1),
                                        modifier = Modifier.weight(SETS_TABLE_SET_WEIGHT),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = String.format(Locale.getDefault(), "%.1f", setEntry.weight),
                                        modifier = Modifier.weight(SETS_TABLE_WEIGHT_WEIGHT),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = setEntry.reps.toString(),
                                        modifier = Modifier.weight(SETS_TABLE_REPS_WEIGHT),
                                        maxLines = 1
                                    )
                                    Box(
                                        modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH)
                                    ) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.spacedBy(
                                                8.dp,
                                                Alignment.End
                                            ),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            IconButton(
                                                onClick = {
                                                    editingSet = setEntry
                                                    editWeight = if (setEntry.weight == 0.0) {
                                                        ""
                                                    } else {
                                                        String.format(
                                                            Locale.getDefault(),
                                                            "%.1f",
                                                            setEntry.weight
                                                        )
                                                    }
                                                    editReps = setEntry.reps.toString()
                                                }
                                            ) {
                                                Icon(
                                                    imageVector = Icons.Default.Edit,
                                                    contentDescription = stringResource(R.string.cd_edit)
                                                )
                                            }
                                            IconButton(onClick = { onDeleteSet(setEntry) }) {
                                                Icon(
                                                    imageVector = Icons.Default.Delete,
                                                    contentDescription = stringResource(R.string.cd_delete),
                                                    tint = MaterialTheme.colorScheme.error
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            if (exerciseDetails.sets.isEmpty()) {
                                Text(
                                    text = stringResource(R.string.empty_progress),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }

                            OutlinedButton(
                                onClick = {
                                    onAddSet(workoutExerciseId)
                                    startExerciseTimer(workoutExerciseId, 90)
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = stringResource(R.string.action_add_set),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
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

    if (editingSet != null) {
        AlertDialog(
            onDismissRequest = { editingSet = null },
            title = { Text(text = stringResource(R.string.dialog_edit_set_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editWeight,
                        onValueChange = { editWeight = it },
                        label = { Text(stringResource(R.string.label_weight_kg)) },
                        placeholder = { Text(stringResource(R.string.hint_optional)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editReps,
                        onValueChange = { editReps = it },
                        label = { Text(stringResource(R.string.label_reps)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                OutlinedButton(
                    onClick = {
                        val setEntry = editingSet
                        if (setEntry != null) {
                            onUpdateSet(setEntry, editWeight, editReps)
                        }
                        editingSet = null
                    }
                ) {
                    Text(text = stringResource(R.string.action_save))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { editingSet = null }) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            }
        )
    }

    if (confirmDeleteSession) {
        val details = uiState.sessionDetails
        AlertDialog(
            onDismissRequest = { confirmDeleteSession = false },
            title = { Text(text = stringResource(R.string.dialog_delete_workout_title)) },
            text = {
                Text(
                    text = stringResource(
                        R.string.dialog_delete_workout_message,
                        details?.session?.date?.let(DateTimeUtils::formatDate).orEmpty()
                    )
                )
            },
            confirmButton = {
                OutlinedButton(
                    onClick = {
                        confirmDeleteSession = false
                        onDeleteSession()
                    }
                ) {
                    Text(text = stringResource(R.string.action_delete))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { confirmDeleteSession = false }) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun WorkoutHeaderCard(
    date: String,
    note: String?,
    exerciseCount: Int,
    setCount: Int,
    volume: Double,
    onDelete: () -> Unit
) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = date,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.cd_delete)
                    )
                }
            }
            Text(
                text = note
                    ?.takeIf { it.isNotBlank() }
                    ?.let { stringResource(R.string.details_note, it) }
                    ?: stringResource(R.string.details_no_note),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.84f)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_exercises),
                    value = exerciseCount.toString(),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_sets),
                    value = setCount.toString(),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_volume),
                    value = formatCompactWeight(volume),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
        }
    }
}

@Composable
private fun GarminWorkoutHeaderCard(
    date: String,
    metrics: GarminWorkoutMetrics,
    exerciseCount: Int,
    setCount: Int,
    onDelete: () -> Unit
) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.garmin_workout_title),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = stringResource(R.string.garmin_workout_synced_from, date),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.78f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.cd_delete)
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.garmin_metric_duration),
                    value = metrics.duration ?: "—",
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.garmin_metric_logged),
                    value = stringResource(R.string.garmin_metric_sets_value, setCount),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
            Text(
                text = stringResource(R.string.garmin_metric_exercises_value, exerciseCount) +
                    " · " + stringResource(R.string.garmin_synced_sets_hint),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.78f)
            )
        }
    }
}

@Composable
private fun GarminWorkoutMetricsCard(metrics: GarminWorkoutMetrics) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.garmin_metrics_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_gym_kcal),
                    value = metrics.gymCalories?.toString() ?: "—",
                    helper = stringResource(R.string.garmin_metric_our_formula),
                    modifier = Modifier.weight(1f)
                )
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_garmin_kcal),
                    value = metrics.garminCalories?.toString() ?: "—",
                    helper = stringResource(R.string.garmin_metric_system),
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_avg_hr),
                    value = metrics.avgHeartRate?.let { stringResource(R.string.garmin_metric_bpm_value, it) } ?: "—",
                    helper = metrics.duration?.let { stringResource(R.string.garmin_metric_duration_value, it) }
                        ?: stringResource(R.string.garmin_metric_heart_rate),
                    modifier = Modifier.weight(1f)
                )
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_max_hr),
                    value = metrics.maxHeartRate?.let { stringResource(R.string.garmin_metric_bpm_value, it) } ?: "—",
                    helper = metrics.heartRateZone ?: stringResource(R.string.garmin_metric_peak),
                    modifier = Modifier.weight(1f)
                )
            }
            GarminHeartRateVisual(metrics = metrics)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_hr_intensity),
                    value = metrics.intensityLabelRes()?.let { stringResource(it) } ?: "—",
                    helper = metrics.avgHeartRate?.let {
                        stringResource(R.string.garmin_metric_from_avg_hr)
                    } ?: stringResource(R.string.garmin_metric_heart_rate),
                    modifier = Modifier.weight(1f)
                )
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_kcal_gap),
                    value = metrics.calorieGapLabel(),
                    helper = stringResource(R.string.garmin_metric_gym_vs_garmin),
                    modifier = Modifier.weight(1f)
                )
            }
            Text(
                text = stringResource(R.string.garmin_kcal_explainer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun GarminHeartRateVisual(metrics: GarminWorkoutMetrics) {
    val avg = metrics.avgHeartRate
    val max = metrics.maxHeartRate
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.garmin_hr_chart_title),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = metrics.heartRateZone ?: stringResource(R.string.garmin_metric_peak),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold
            )
        }
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(96.dp)
                .clip(GymCompactShape)
                .background(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f),
                    shape = GymCompactShape
                )
                .padding(horizontal = 10.dp, vertical = 12.dp)
        ) {
            val zoneColors = listOf(
                Color(0xFF4EA3FF),
                Color(0xFF3DDC84),
                Color(0xFFFFD23F),
                Color(0xFFFF8A34),
                Color(0xFFFF4D5E)
            )
            val segmentWidth = size.width / zoneColors.size
            zoneColors.forEachIndexed { index, color ->
                drawLine(
                    color = color,
                    start = Offset(index * segmentWidth + 4f, size.height - 8f),
                    end = Offset((index + 1) * segmentWidth - 4f, size.height - 8f),
                    strokeWidth = 10f,
                    cap = StrokeCap.Round
                )
            }

            if (avg != null || max != null) {
                val low = 80f
                val high = 190f
                fun yFor(value: Int): Float {
                    val normalized = ((value - low) / (high - low)).coerceIn(0f, 1f)
                    return size.height - 22f - normalized * (size.height - 34f)
                }
                val avgValue = avg ?: max ?: 110
                val maxValue = max ?: avgValue
                val path = Path().apply {
                    moveTo(8f, yFor((avgValue * 0.92f).toInt()))
                    cubicTo(
                        size.width * 0.28f,
                        yFor(avgValue),
                        size.width * 0.58f,
                        yFor(((avgValue + maxValue) / 2f).toInt()),
                        size.width - 8f,
                        yFor(maxValue)
                    )
                }
                drawPath(
                    path = path,
                    color = Color(0xFFE84A5F),
                    style = Stroke(width = 6f, cap = StrokeCap.Round)
                )
                drawCircle(Color.White, radius = 6f, center = Offset(size.width - 8f, yFor(maxValue)))
                drawCircle(Color(0xFFE84A5F), radius = 4f, center = Offset(size.width - 8f, yFor(maxValue)))
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = avg?.let { stringResource(R.string.garmin_metric_avg_short, it) } ?: "—",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = max?.let { stringResource(R.string.garmin_metric_max_short, it) } ?: "—",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun GarminMetricCell(
    label: String,
    value: String,
    helper: String,
    modifier: Modifier = Modifier
) {
    val outline = MaterialTheme.colorScheme.outlineVariant
    Column(
        modifier = modifier
            .clip(GymCompactShape)
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                GymCompactShape
            )
            .border(
                width = 1.dp,
                color = outline.copy(alpha = outline.alpha * 0.55f),
                shape = GymCompactShape
            )
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Text(
            text = label.uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = helper,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun WorkoutExerciseQuickAddCard(
    availableExercises: List<ExerciseEntity>,
    onAddExerciseToWorkout: (Long) -> Unit
) {
    var expanded by remember(availableExercises) { mutableStateOf(false) }
    var selectedExerciseId by remember(availableExercises) {
        mutableStateOf(availableExercises.firstOrNull()?.id)
    }
    val selectedExerciseName = availableExercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.let { localizedExerciseName(it.name) }
        ?: stringResource(R.string.label_select_exercise)

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = stringResource(R.string.title_add_exercise_to_workout_section),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }

            if (availableExercises.isEmpty()) {
                Text(
                    text = stringResource(R.string.label_all_exercises_added),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Box(modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = { expanded = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = selectedExerciseName,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    DropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        availableExercises.forEach { exercise ->
                            DropdownMenuItem(
                                text = { Text(localizedExerciseName(exercise.name)) },
                                onClick = {
                                    selectedExerciseId = exercise.id
                                    expanded = false
                                }
                            )
                        }
                    }
                }

                FilledTonalButton(
                    onClick = {
                        val selectedId = selectedExerciseId ?: return@FilledTonalButton
                        onAddExerciseToWorkout(selectedId)
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.action_add_to_workout))
                }
            }
        }
    }
}

@Composable
private fun ExerciseRestTimerRow(
    restSecondsRemaining: Int,
    onStart60: () -> Unit,
    onStart90: () -> Unit,
    onStart180: () -> Unit,
    onStop: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = stringResource(R.string.label_rest_timer_exercise),
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = if (restSecondsRemaining > 0) {
                    formatTimerLabel(restSecondsRemaining)
                } else {
                    stringResource(R.string.label_timer_ready)
                },
                style = MaterialTheme.typography.labelLarge,
                color = if (restSecondsRemaining > 0) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_60),
                onClick = onStart60,
                modifier = Modifier.weight(1f)
            )
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_90),
                onClick = onStart90,
                modifier = Modifier.weight(1f)
            )
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_180),
                onClick = onStart180,
                modifier = Modifier.weight(1f)
            )
        }
        OutlinedButton(
            onClick = onStop,
            modifier = Modifier.fillMaxWidth(),
            enabled = restSecondsRemaining > 0
        ) {
            Text(text = stringResource(R.string.action_timer_stop))
        }
    }
}

@Composable
private fun TimerPresetButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier,
        shape = GymControlShape,
        contentPadding = ButtonDefaults.ButtonWithIconContentPadding
    ) {
        Text(
            text = label,
            maxLines = 1,
            fontWeight = FontWeight.SemiBold
        )
    }
}

private fun formatTimerLabel(totalSeconds: Int): String {
    return String.format(
        Locale.getDefault(),
        "%02d:%02d",
        totalSeconds / 60,
        totalSeconds % 60
    )
}

private fun formatCompactWeight(weight: Double): String {
    if (!weight.isFinite()) return "—"
    return if (weight % 1.0 == 0.0) {
        String.format(Locale.getDefault(), "%.0f", weight)
    } else {
        String.format(Locale.getDefault(), "%.1f", weight)
    }
}

private data class GarminWorkoutMetrics(
    val duration: String?,
    val gymCalories: Int?,
    val garminCalories: Int?,
    val avgHeartRate: Int?,
    val maxHeartRate: Int?,
    val heartRateZone: String?
)

private fun GarminWorkoutMetrics.intensityLabelRes(): Int? {
    val avg = avgHeartRate ?: return null
    return when {
        avg >= 155 -> R.string.garmin_intensity_high
        avg >= 135 -> R.string.garmin_intensity_solid
        avg >= 115 -> R.string.garmin_intensity_moderate
        else -> R.string.garmin_intensity_easy
    }
}

private fun GarminWorkoutMetrics.calorieGapLabel(): String {
    val gym = gymCalories ?: return "—"
    val garmin = garminCalories ?: return "—"
    val gap = gym - garmin
    return when {
        gap > 0 -> "+$gap"
        else -> gap.toString()
    }
}

private fun parseGarminWorkoutMetrics(note: String): GarminWorkoutMetrics? {
    // Keep parsing legacy "Garmin Fenix 8" notes while using a device-neutral marker for new watches.
    if (!Regex("""^Garmin(?: Fenix 8)?(?: ·|$)""", RegexOption.IGNORE_CASE).containsMatchIn(note)) return null

    val duration = Regex("""(?:Duration|Тривалість|Длительность)\s+([0-9]+:[0-9]{2}(?::[0-9]{2})?)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)
    val gymCalories = Regex("""Gym\s+(?:kcal|ккал)\s+([0-9]+)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    val garminCalories = Regex("""Garmin\s+(?:kcal|ккал)\s+([0-9]+)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    val avgHeartRate = Regex("""(?:Avg HR|Сер пульс|Средний пульс)\s+([0-9]+)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    val maxHeartRate = Regex("""(?:Max HR|Макс пульс|Макс\. пульс)\s+([0-9]+)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    val zone = Regex("""(?:HR zone|Зона пульсу|Зона пульса)\s+(Z[0-9]+)""")
        .find(note)
        ?.groupValues
        ?.getOrNull(1)

    return GarminWorkoutMetrics(
        duration = duration,
        gymCalories = gymCalories,
        garminCalories = garminCalories,
        avgHeartRate = avgHeartRate,
        maxHeartRate = maxHeartRate,
        heartRateZone = zone
    )
}
