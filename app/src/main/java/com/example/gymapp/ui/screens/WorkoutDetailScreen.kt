package com.example.gymapp.ui.screens

import android.content.Context
import android.content.Intent
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
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
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
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.garmin.GarminSetIntervalMetrics
import com.example.gymapp.garmin.GarminWorkoutMetrics
import com.example.gymapp.garmin.hasSetIntervalDetails
import com.example.gymapp.garmin.parseTrustedGarminWorkoutMetrics
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.ExerciseMuscleMap
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.WorkoutComparisonCard
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.WorkoutDetailEvent
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

private const val SETS_TABLE_SET_WEIGHT = 0.95f
private const val SETS_TABLE_WEIGHT_WEIGHT = 1.1f
private const val SETS_TABLE_REPS_WEIGHT = 0.9f
private const val DEFAULT_EXERCISE_REST_SECONDS = 90
private val SETS_TABLE_ACTIONS_WIDTH = 104.dp

internal fun shareWorkoutUrl(
    context: Context,
    url: String,
    chooserTitle: String
) {
    require(url.startsWith(SharedWorkoutLink.BASE_URL + "#workout="))
    require(url.length <= SharedWorkoutLink.BASE_URL.length + "#workout=".length +
        SharedWorkoutLink.MAX_ENCODED_LENGTH)
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
    }
    context.startActivity(Intent.createChooser(sendIntent, chooserTitle))
}

@Composable
fun WorkoutDetailScreen(
    uiState: WorkoutDetailUiState,
    exerciseMediaOwnerKey: String,
    events: Flow<WorkoutDetailEvent>,
    onAddExerciseToWorkout: (Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onStartExerciseRestTimer: (Long, Int) -> Unit,
    onStopExerciseRestTimer: (Long) -> Unit,
    onDeleteSet: (SetEntryEntity) -> Unit,
    onConfirmDeleteSet: () -> Unit,
    onDismissDeleteSet: () -> Unit,
    onDeleteSession: () -> Unit,
    onSessionDeleted: () -> Unit,
    onUpdateSet: (SetEntryEntity, String, String) -> Unit,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var editingSet by remember { mutableStateOf<SetEntryEntity?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }
    var confirmDeleteSession by remember { mutableStateOf(false) }

    var exerciseTimerNowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(uiState.exerciseRestDeadlineMillis) {
        while (true) {
            val now = System.currentTimeMillis()
            exerciseTimerNowMillis = now
            if (uiState.exerciseRestDeadlineMillis.values.none { deadline -> deadline > now }) break
            delay(500)
        }
    }

    fun remainingExerciseTimerSeconds(workoutExerciseId: Long): Int {
        val target = uiState.exerciseRestDeadlineMillis[workoutExerciseId] ?: return 0
        val remainingMillis = (target - exerciseTimerNowMillis).coerceAtLeast(0L)
        return ((remainingMillis + 999L) / 1_000L).toInt()
    }

    LaunchedEffect(events, context) {
        events.collect { event ->
            when (event) {
                WorkoutDetailEvent.AddSetFailed -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_add_set_failed),
                        duration = SnackbarDuration.Short
                    )
                }

                WorkoutDetailEvent.RestTimerFailed -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_rest_timer_save_failed),
                        duration = SnackbarDuration.Short
                    )
                }

                WorkoutDetailEvent.SetDeleted -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_set_deleted),
                        duration = SnackbarDuration.Short
                    )
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

                WorkoutDetailEvent.DeleteTargetChanged -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_delete_target_changed),
                        duration = SnackbarDuration.Short
                    )
                }

                WorkoutDetailEvent.DeleteFailed -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_delete_failed),
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
            val shareWorkout: () -> Unit = {
                runCatching {
                    val url = SharedWorkoutLink.fromSession(details)
                    shareWorkoutUrl(
                        context = context,
                        url = url,
                        chooserTitle = context.getString(R.string.action_share_workout)
                    )
                }.onFailure {
                    coroutineScope.launch {
                        snackbarHostState.showSnackbar(
                            message = context.getString(R.string.message_share_workout_failed),
                            duration = SnackbarDuration.Short
                        )
                    }
                }
            }
            val garminMetrics = remember(details.session.note, uiState.hasGarminReceipt) {
                parseTrustedGarminWorkoutMetrics(
                    note = details.session.note.orEmpty(),
                    hasGarminReceipt = uiState.hasGarminReceipt
                )
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
                            onShare = shareWorkout,
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
                            onShare = shareWorkout,
                            onDelete = { confirmDeleteSession = true }
                        )
                    }
                }

                if (garminMetrics != null) {
                    item {
                        GarminWorkoutMetricsCard(metrics = garminMetrics)
                    }
                    if (garminMetrics.hasSetIntervalDetails()) {
                        item {
                            GarminSetIntervalsCard(metrics = garminMetrics)
                        }
                    }
                }

                uiState.workoutComparison?.let { comparison ->
                    item {
                        WorkoutComparisonCard(comparison = comparison)
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
                    val displayExerciseName = localizedExerciseName(exerciseDetails.exercise.name)
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
                                ExerciseMediaPreview(
                                    exerciseId = exerciseDetails.exercise.id,
                                    exerciseName = exerciseDetails.exercise.name,
                                    ownerKey = exerciseMediaOwnerKey,
                                    width = 72.dp,
                                    height = 60.dp
                                )
                                Text(
                                    text = displayExerciseName,
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
                                    onStart60 = {
                                        onStartExerciseRestTimer(workoutExerciseId, 60)
                                    },
                                    onStart90 = {
                                        onStartExerciseRestTimer(workoutExerciseId, 90)
                                    },
                                    onStart180 = {
                                        onStartExerciseRestTimer(workoutExerciseId, 180)
                                    },
                                    onStop = { onStopExerciseRestTimer(workoutExerciseId) }
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
                                                    contentDescription = stringResource(
                                                        R.string.cd_delete_set_named,
                                                        setIndex + 1,
                                                        displayExerciseName
                                                    ),
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
                                onClick = { onAddSet(workoutExerciseId) },
                                enabled = workoutExerciseId !in uiState.setAdditionsInFlight,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = stringResource(
                                        R.string.action_log_set_and_rest,
                                        DEFAULT_EXERCISE_REST_SECONDS
                                    ),
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

    uiState.pendingSetDeletion?.let { snapshot ->
        SetDeleteConfirmationDialog(
            snapshot = snapshot,
            isDeleting = uiState.isSetDeletionInProgress,
            error = uiState.setDeletionError,
            onDismiss = onDismissDeleteSet,
            onConfirm = onConfirmDeleteSet
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
    onShare: () -> Unit,
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
                IconButton(onClick = onShare) {
                    Icon(
                        imageVector = Icons.Default.Share,
                        contentDescription = stringResource(R.string.action_share_workout)
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(
                            R.string.cd_delete_workout_on,
                            date
                        )
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
    onShare: () -> Unit,
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
                IconButton(onClick = onShare) {
                    Icon(
                        imageVector = Icons.Default.Share,
                        contentDescription = stringResource(R.string.action_share_workout)
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(
                            R.string.cd_delete_workout_on,
                            date
                        )
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.garmin_metric_duration),
                    value = metrics.durationSeconds?.let(::formatGarminDuration) ?: "—",
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
            val completedSetCount = metrics.completedSetCount
            completedSetCount?.let { completed ->
                metrics.plannedSetCount
                    ?.takeIf { planned -> planned > completed }
                    ?.let { plannedSetCount ->
                        Text(
                            text = stringResource(
                                R.string.garmin_partial_sets_status,
                                completed,
                                plannedSetCount
                            ),
                            style = MaterialTheme.typography.labelLarge,
                            color = Color.White
                        )
                    }
            }
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
                    value = metrics.averageHeartRate?.let {
                        stringResource(R.string.garmin_metric_bpm_value, it)
                    } ?: "—",
                    helper = metrics.durationSeconds?.let(::formatGarminDuration)
                        ?.let { stringResource(R.string.garmin_metric_duration_value, it) }
                        ?: stringResource(R.string.garmin_metric_heart_rate),
                    modifier = Modifier.weight(1f)
                )
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_max_hr),
                    value = metrics.maximumHeartRate?.let {
                        stringResource(R.string.garmin_metric_bpm_value, it)
                    } ?: "—",
                    helper = stringResource(R.string.garmin_metric_heart_rate),
                    modifier = Modifier.weight(1f)
                )
            }
            metrics.endingHeartRateZone?.let { endingZone ->
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_ending_zone),
                    value = "Z$endingZone",
                    helper = stringResource(R.string.garmin_metric_ending_zone_helper),
                    modifier = Modifier.fillMaxWidth()
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
                    helper = metrics.averageHeartRate?.let {
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
private fun GarminSetIntervalsCard(metrics: GarminWorkoutMetrics) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.garmin_set_intervals_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.garmin_set_intervals_supporting),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            metrics.setIntervals.forEach { interval ->
                GarminSetIntervalRow(interval = interval)
            }
            if (metrics.omittedSetIntervalCount > 0) {
                Text(
                    text = stringResource(
                        R.string.garmin_set_intervals_omitted,
                        metrics.omittedSetIntervalCount
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun GarminSetIntervalRow(interval: GarminSetIntervalMetrics) {
    val nonZeroZones = interval.heartRateZoneSeconds
        .mapIndexedNotNull { zone, seconds ->
            seconds.takeIf { it > 0 }?.let { "Z$zone $it" }
        }
        .joinToString(separator = " · ")
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(GymCompactShape)
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                GymCompactShape
            )
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f),
                shape = GymCompactShape
            )
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.garmin_watch_set_label, interval.setNumber),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(
                    R.string.garmin_set_interval_active,
                    formatGarminDuration(interval.activeSeconds)
                ),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
        Text(
            text = stringResource(
                R.string.garmin_set_interval_calories,
                formatGarminIntervalCalories(interval.gymCalories),
                interval.garminCalories?.toString() ?: "—"
            ),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = if (nonZeroZones.isEmpty()) {
                stringResource(R.string.garmin_set_interval_no_zones)
            } else {
                stringResource(R.string.garmin_set_interval_zones, nonZeroZones)
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun GarminHeartRateVisual(metrics: GarminWorkoutMetrics) {
    val average = metrics.averageHeartRate
    val maximum = metrics.maximumHeartRate
    val trackColor = MaterialTheme.colorScheme.outlineVariant
    val rangeColor = MaterialTheme.colorScheme.primary
    val averageColor = MaterialTheme.colorScheme.secondary
    val maximumColor = MaterialTheme.colorScheme.tertiary
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
            metrics.endingHeartRateZone?.let { endingZone ->
                Text(
                    text = stringResource(R.string.garmin_metric_ending_zone) + " Z$endingZone",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(GymCompactShape)
                .background(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f),
                    shape = GymCompactShape
                )
                .padding(horizontal = 10.dp, vertical = 12.dp)
        ) {
            val startX = 8f
            val endX = size.width - 8f
            val centerY = size.height / 2f
            fun xFor(value: Int): Float {
                val normalized = ((value - 40f) / 200f).coerceIn(0f, 1f)
                return startX + normalized * (endX - startX)
            }
            drawLine(
                color = trackColor,
                start = Offset(startX, centerY),
                end = Offset(endX, centerY),
                strokeWidth = 6f,
                cap = StrokeCap.Round
            )
            if (average != null && maximum != null) {
                drawLine(
                    color = rangeColor,
                    start = Offset(xFor(average), centerY),
                    end = Offset(xFor(maximum), centerY),
                    strokeWidth = 8f,
                    cap = StrokeCap.Round
                )
            }
            average?.let { value ->
                drawCircle(averageColor, radius = 8f, center = Offset(xFor(value), centerY))
            }
            maximum?.let { value ->
                drawCircle(maximumColor, radius = 8f, center = Offset(xFor(value), centerY))
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = average?.let { stringResource(R.string.garmin_metric_avg_short, it) } ?: "—",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = maximum?.let { stringResource(R.string.garmin_metric_max_short, it) } ?: "—",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = stringResource(R.string.garmin_hr_chart_helper),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
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

private fun formatGarminIntervalCalories(calories: Double): String {
    if (!calories.isFinite()) return "—"
    return NumberFormat.getNumberInstance(Locale.getDefault()).apply {
        isGroupingUsed = false
        minimumFractionDigits = 0
        maximumFractionDigits = 2
    }.format(calories)
}

private fun GarminWorkoutMetrics.intensityLabelRes(): Int? {
    val avg = averageHeartRate ?: return null
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

private fun formatGarminDuration(totalSeconds: Long): String {
    val safeSeconds = totalSeconds.coerceAtLeast(0L)
    val hours = safeSeconds / 3_600L
    val minutes = (safeSeconds % 3_600L) / 60L
    val seconds = safeSeconds % 60L
    return if (hours > 0L) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.ROOT, "%d:%02d", minutes, seconds)
    }
}
