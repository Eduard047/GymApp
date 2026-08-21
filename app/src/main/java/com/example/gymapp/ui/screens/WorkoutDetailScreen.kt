package com.example.gymapp.ui.screens

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.garmin.GarminSetIntervalMetrics
import com.example.gymapp.garmin.GarminSetEvidenceMetrics
import com.example.gymapp.garmin.GarminSetHeartRateChartPoint
import com.example.gymapp.garmin.GarminWorkoutMetrics
import com.example.gymapp.garmin.hasSetIntervalDetails
import com.example.gymapp.garmin.parseGarminWorkoutPresentation
import com.example.gymapp.garmin.recoverySummary
import com.example.gymapp.garmin.rhythmSummary
import com.example.gymapp.garmin.setHeartRateChartPoints
import com.example.gymapp.garmin.setRecognitionSummary
import com.example.gymapp.garmin.totalHeartRateZoneSeconds
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.ExerciseMuscleMap
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.GymMetric
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricStrip
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.WorkoutComparisonCard
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.WorkoutDetailEvent
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

private const val SETS_TABLE_SET_WEIGHT = 0.95f
private const val SETS_TABLE_WEIGHT_WEIGHT = 1.1f
private const val SETS_TABLE_REPS_WEIGHT = 0.9f
private val SETS_TABLE_ACTIONS_WIDTH = 104.dp
private val GARMIN_ZONE_COLORS = listOf(
    Color(0xFF718096),
    Color(0xFF4EA8DE),
    Color(0xFF48BB78),
    Color(0xFFF6C453),
    Color(0xFFF28C45),
    Color(0xFFE45756)
)

internal data class WorkoutDetailControlVisibility(
    val showAddExercise: Boolean,
    val showAddSet: Boolean,
    val showSetActions: Boolean,
    val showDeleteWorkout: Boolean,
    val showRestTimer: Boolean,
    val showLogSetAndRest: Boolean
)

internal fun workoutDetailControlVisibility(
    isEditingWorkout: Boolean
): WorkoutDetailControlVisibility = WorkoutDetailControlVisibility(
    showAddExercise = isEditingWorkout,
    showAddSet = isEditingWorkout,
    showSetActions = isEditingWorkout,
    showDeleteWorkout = isEditingWorkout,
    showRestTimer = false,
    showLogSetAndRest = false
)

internal fun nextExpandedWorkoutExerciseId(
    currentExpandedExerciseId: Long?,
    selectedExerciseId: Long
): Long? = if (currentExpandedExerciseId == selectedExerciseId) {
    null
} else {
    selectedExerciseId
}

internal fun selectedWorkoutExerciseQuickAddId(
    selectedExerciseId: Long?,
    availableExerciseIds: Set<Long>
): Long? = selectedExerciseId?.takeIf { it in availableExerciseIds }

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
internal fun WorkoutDetailScreen(
    uiState: WorkoutDetailUiState,
    exerciseMediaOwnerKey: String,
    events: Flow<WorkoutDetailEvent>,
    onAddExerciseToWorkout: (Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onDeleteSet: (SetEntryEntity) -> Unit,
    onConfirmDeleteSet: () -> Unit,
    onDismissDeleteSet: () -> Unit,
    onDeleteSession: () -> Unit,
    onSessionDeleted: () -> Unit,
    onUpdateSet: (SetEntryEntity, String, String) -> Unit,
    onShareWorkout: ((SharedWorkoutPlan) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var editingSet by remember { mutableStateOf<SetEntryEntity?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }
    var confirmDeleteSession by remember { mutableStateOf(false) }
    var editingWorkoutSessionId by rememberSaveable { mutableStateOf<Long?>(null) }
    var expandedExerciseId by rememberSaveable { mutableStateOf<Long?>(null) }
    var areWatchMetricsExpanded by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(events, context) {
        events.collect { event ->
            when (event) {
                WorkoutDetailEvent.AddSetFailed -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_add_set_failed),
                        duration = SnackbarDuration.Short
                    )
                }

                WorkoutDetailEvent.AddExerciseFailed -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_add_exercise_failed),
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
            val isEditingWorkout = editingWorkoutSessionId == details.session.id
            val controls = workoutDetailControlVisibility(isEditingWorkout)
            val listState = rememberLazyListState()
            val toggleEditMode = {
                editingWorkoutSessionId = if (isEditingWorkout) {
                    editingSet = null
                    confirmDeleteSession = false
                    onDismissDeleteSet()
                    null
                } else {
                    details.session.id
                }
            }
            val shareWorkout: () -> Unit = {
                runCatching {
                    val plan = SharedWorkoutLink.planFromSession(details)
                    if (onShareWorkout != null) {
                        onShareWorkout(plan)
                    } else {
                        shareWorkoutUrl(
                            context = context,
                            url = SharedWorkoutLink.buildUrl(plan.exercises),
                            chooserTitle = context.getString(R.string.action_share_workout)
                        )
                    }
                }.onFailure {
                    coroutineScope.launch {
                        snackbarHostState.showSnackbar(
                            message = context.getString(R.string.message_share_workout_failed),
                            duration = SnackbarDuration.Short
                        )
                    }
                }
            }
            val garminPresentation = remember(details.session.note, uiState.hasGarminReceipt) {
                parseGarminWorkoutPresentation(
                    note = details.session.note.orEmpty(),
                    hasGarminReceipt = uiState.hasGarminReceipt
                )
            }
            val garminMetrics = garminPresentation?.metrics
            val isGarminWorkout = garminMetrics != null
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = GymSpacing.ScreenHorizontal,
                    top = GymSpacing.ScreenTop,
                    end = GymSpacing.ScreenHorizontal,
                    bottom = 112.dp
                ),
                verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
            ) {
                item {
                    if (garminMetrics != null) {
                        GarminWorkoutHeaderCard(
                            date = DateTimeUtils.formatLongDate(details.session.date),
                            metrics = garminMetrics,
                            hasVerifiedGarminOrigin =
                                garminPresentation?.hasVerifiedGarminOrigin == true,
                            exerciseCount = details.workoutExercises.size,
                            setCount = details.workoutExercises.sumOf { it.sets.size },
                            onShare = shareWorkout,
                            isEditing = isEditingWorkout,
                            showDelete = controls.showDeleteWorkout,
                            onToggleEdit = toggleEditMode,
                            onDelete = { confirmDeleteSession = true }
                        )
                    } else {
                        WorkoutHeaderCard(
                            date = DateTimeUtils.formatLongDate(details.session.date),
                            note = details.session.note,
                            exerciseCount = details.workoutExercises.size,
                            setCount = details.workoutExercises.sumOf { it.sets.size },
                            volume = details.workoutExercises.sumOf { exercise ->
                                exercise.sets.sumOf { set -> set.weight * set.reps }
                            },
                            durationSeconds = details.session.durationSeconds,
                            onShare = shareWorkout,
                            isEditing = isEditingWorkout,
                            showDelete = controls.showDeleteWorkout,
                            onToggleEdit = toggleEditMode,
                            onDelete = { confirmDeleteSession = true }
                        )
                    }
                }

                if (garminMetrics != null) {
                    item {
                        WatchMetricsDisclosureCard(
                            expanded = areWatchMetricsExpanded,
                            onToggle = { areWatchMetricsExpanded = !areWatchMetricsExpanded }
                        )
                    }
                    if (areWatchMetricsExpanded) {
                        item {
                            GarminWorkoutMetricsCard(metrics = garminMetrics)
                        }
                        if (
                            garminMetrics.setIntervals.isNotEmpty() ||
                            garminMetrics.setEvidence.isNotEmpty()
                        ) {
                            item {
                                GarminWatchInsightsCard(metrics = garminMetrics)
                            }
                        }
                        if (garminMetrics.hasSetIntervalDetails()) {
                            item {
                                GarminSetIntervalsCard(metrics = garminMetrics)
                            }
                        }
                    }
                }

                uiState.workoutComparison?.let { comparison ->
                    item {
                        WorkoutComparisonCard(comparison = comparison)
                    }
                }

                if (controls.showAddExercise) {
                    item {
                        WorkoutExerciseQuickAddCard(
                            availableExercises = uiState.availableExercisesToAdd,
                            frequentExerciseIds = uiState.frequentExerciseIds,
                            exerciseWorkoutCounts = uiState.exerciseWorkoutCounts,
                            exerciseMuscleIds = uiState.exerciseMuscleIds,
                            exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                            onAddExerciseToWorkout = onAddExerciseToWorkout
                        )
                    }
                }

                items(
                    items = details.workoutExercises,
                    key = { it.workoutExercise.id }
                ) { exerciseDetails ->
                    val workoutExerciseId = exerciseDetails.workoutExercise.id
                    val displayExerciseName = localizedExerciseName(exerciseDetails.exercise.name)
                    val isExpanded = expandedExerciseId == workoutExerciseId
                    val muscleIntensities = remember(exerciseDetails.exercise.name) {
                        defaultContributionsForExercise(exerciseDetails.exercise.name)
                            .associate { contribution ->
                                contribution.muscleId to contribution.weight.toFloat()
                            }
                    }
                    val setCount = exerciseDetails.sets.size
                    val repCount = exerciseDetails.sets.sumOf { it.reps }
                    val setCountLabel = pluralStringResource(
                        R.plurals.saved_workout_set_count,
                        setCount,
                        setCount
                    )
                    val repsLabel = pluralStringResource(
                        R.plurals.saved_workout_rep_count,
                        repCount,
                        repCount
                    )
                    val volumeLabel = stringResource(
                        R.string.stats_volume,
                        exerciseDetails.sets.sumOf { it.weight * it.reps }
                    )
                    val setSummary = remember(setCountLabel, repsLabel, volumeLabel) {
                        "$setCountLabel · $repsLabel · $volumeLabel"
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
                                IconButton(
                                    onClick = {
                                        expandedExerciseId = nextExpandedWorkoutExerciseId(
                                            currentExpandedExerciseId = expandedExerciseId,
                                            selectedExerciseId = workoutExerciseId
                                        )
                                    }
                                ) {
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

                            if (uiState.personalRecordFlags[workoutExerciseId] == true) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    InfoPill(
                                        text = stringResource(R.string.label_personal_record),
                                        accent = MaterialTheme.colorScheme.tertiary
                                    )
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
                                    if (controls.showSetActions) {
                                        Box(modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH))
                                    }
                                }

                                exerciseDetails.sets.forEachIndexed { setIndex, setEntry ->
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(GymControlShape)
                                            .background(
                                                MaterialTheme.colorScheme.surfaceVariant.copy(
                                                    alpha = 0.42f
                                                )
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
                                            text = String.format(
                                                Locale.getDefault(),
                                                "%.1f",
                                                setEntry.weight
                                            ),
                                            modifier = Modifier.weight(SETS_TABLE_WEIGHT_WEIGHT),
                                            maxLines = 1
                                        )
                                        Text(
                                            text = setEntry.reps.toString(),
                                            modifier = Modifier.weight(SETS_TABLE_REPS_WEIGHT),
                                            maxLines = 1
                                        )
                                        if (controls.showSetActions) {
                                            Box(modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH)) {
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
                                                            contentDescription = stringResource(
                                                                R.string.cd_edit
                                                            )
                                                        )
                                                    }
                                                    IconButton(
                                                        onClick = { onDeleteSet(setEntry) }
                                                    ) {
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
                                }

                                if (exerciseDetails.sets.isEmpty()) {
                                    Text(
                                        text = stringResource(R.string.empty_progress),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }

                                if (controls.showAddSet) {
                                    OutlinedButton(
                                        onClick = { onAddSet(workoutExerciseId) },
                                        enabled = workoutExerciseId !in uiState.setAdditionsInFlight,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Text(text = stringResource(R.string.action_add_set))
                                    }
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

    val currentSessionId = uiState.sessionDetails?.session?.id
    val isEditingWorkout = currentSessionId != null && editingWorkoutSessionId == currentSessionId

    if (editingSet != null && isEditingWorkout) {
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

    if (isEditingWorkout) {
        uiState.pendingSetDeletion?.let { snapshot ->
            SetDeleteConfirmationDialog(
                snapshot = snapshot,
                isDeleting = uiState.isSetDeletionInProgress,
                error = uiState.setDeletionError,
                onDismiss = onDismissDeleteSet,
                onConfirm = onConfirmDeleteSet
            )
        }
    }

    if (confirmDeleteSession && isEditingWorkout) {
        val details = uiState.sessionDetails
        AlertDialog(
            onDismissRequest = { confirmDeleteSession = false },
            title = { Text(text = stringResource(R.string.dialog_delete_workout_title)) },
            text = {
                Text(
                    text = stringResource(
                        R.string.dialog_delete_workout_message,
                        details?.session?.date?.let(DateTimeUtils::formatLongDate).orEmpty()
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
    durationSeconds: Long?,
    onShare: () -> Unit,
    isEditing: Boolean,
    showDelete: Boolean,
    onToggleEdit: () -> Unit,
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
                if (showDelete) {
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
            }
            Text(
                text = note
                    ?.takeIf { it.isNotBlank() }
                    ?.let { stringResource(R.string.details_note, it) }
                    ?: stringResource(R.string.details_no_note),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.84f)
            )
            MetricStrip(
                metrics = buildList {
                    add(
                    GymMetric(
                        stringResource(R.string.post_workout_metric_exercises),
                        exerciseCount.toString()
                    ))
                    add(
                    GymMetric(
                        stringResource(R.string.post_workout_metric_sets),
                        setCount.toString()
                    ))
                    add(
                    GymMetric(
                        stringResource(R.string.post_workout_metric_volume),
                        formatCompactWeight(volume),
                        emphasized = true
                    ))
                    durationSeconds?.let { duration ->
                        add(
                            GymMetric(
                                stringResource(R.string.post_workout_metric_duration),
                                formatWorkoutDuration(duration)
                            )
                        )
                    }
                },
                onHero = true
            )
            WorkoutEditModeButton(
                isEditing = isEditing,
                onToggleEdit = onToggleEdit
            )
        }
    }
}

@Composable
private fun formatWorkoutDuration(totalSeconds: Long): String {
    val minutes = (totalSeconds.coerceAtLeast(0L) / 60L).coerceAtLeast(1L)
    val hours = minutes / 60L
    val remainingMinutes = minutes % 60L
    return if (hours == 0L) {
        stringResource(R.string.duration_minutes_compact, minutes)
    } else if (remainingMinutes == 0L) {
        stringResource(R.string.duration_hours_compact, hours)
    } else {
        stringResource(R.string.duration_hours_minutes_compact, hours, remainingMinutes)
    }
}

@Composable
private fun GarminWorkoutHeaderCard(
    date: String,
    metrics: GarminWorkoutMetrics,
    hasVerifiedGarminOrigin: Boolean,
    exerciseCount: Int,
    setCount: Int,
    onShare: () -> Unit,
    isEditing: Boolean,
    showDelete: Boolean,
    onToggleEdit: () -> Unit,
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
                        text = stringResource(
                            if (hasVerifiedGarminOrigin) {
                                R.string.garmin_workout_title
                            } else {
                                R.string.garmin_workout_format_title
                            }
                        ),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = stringResource(
                            if (hasVerifiedGarminOrigin) {
                                R.string.garmin_workout_synced_from
                            } else {
                                R.string.garmin_workout_note_derived_from
                            },
                            date
                        ),
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
                if (showDelete) {
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
                    value = pluralStringResource(
                        R.plurals.saved_workout_set_count,
                        setCount,
                        setCount
                    ),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
            Text(
                text = pluralStringResource(
                    R.plurals.saved_workout_exercise_count,
                    exerciseCount,
                    exerciseCount
                ) +
                    " · " + stringResource(
                        if (hasVerifiedGarminOrigin) {
                            R.string.garmin_synced_sets_hint
                        } else {
                            R.string.garmin_note_derived_sets_hint
                        }
                    ),
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
            WorkoutEditModeButton(
                isEditing = isEditing,
                onToggleEdit = onToggleEdit
            )
        }
    }
}

@Composable
private fun WorkoutEditModeButton(
    isEditing: Boolean,
    onToggleEdit: () -> Unit
) {
    FilledTonalButton(
        onClick = onToggleEdit,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = Color.White.copy(alpha = 0.16f),
            contentColor = Color.White
        )
    ) {
        Icon(
            imageVector = if (isEditing) Icons.Default.Close else Icons.Default.Edit,
            contentDescription = null
        )
        Text(
            text = stringResource(
                if (isEditing) {
                    R.string.action_finish_editing_workout
                } else {
                    R.string.action_edit_workout
                }
            ),
            modifier = Modifier.padding(start = 8.dp)
        )
    }
}

@Composable
private fun WatchMetricsDisclosureCard(
    expanded: Boolean,
    onToggle: () -> Unit
) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = stringResource(R.string.garmin_watch_metrics_section_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = stringResource(R.string.garmin_watch_metrics_section_supporting),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onToggle) {
                Icon(
                    imageVector = if (expanded) {
                        Icons.Default.ExpandLess
                    } else {
                        Icons.Default.ExpandMore
                    },
                    contentDescription = stringResource(
                        if (expanded) {
                            R.string.cd_collapse_watch_metrics
                        } else {
                            R.string.cd_expand_watch_metrics
                        }
                    )
                )
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
            if (metrics.gymCalories != null || metrics.garminCalories != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    metrics.gymCalories?.let { gymCalories ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_metric_gym_kcal),
                            value = gymCalories.toString(),
                            helper = stringResource(R.string.garmin_metric_our_formula),
                            modifier = Modifier.weight(1f)
                        )
                    }
                    metrics.garminCalories?.let { garminCalories ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_metric_garmin_kcal),
                            value = garminCalories.toString(),
                            helper = stringResource(R.string.garmin_metric_system),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
            if (metrics.averageHeartRate != null || metrics.maximumHeartRate != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    metrics.averageHeartRate?.let { averageHeartRate ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_metric_avg_hr),
                            value = stringResource(
                                R.string.garmin_metric_bpm_value,
                                averageHeartRate
                            ),
                            helper = metrics.durationSeconds?.let(::formatGarminDuration)
                                ?.let { stringResource(R.string.garmin_metric_duration_value, it) }
                                ?: stringResource(R.string.garmin_metric_heart_rate),
                            modifier = Modifier.weight(1f)
                        )
                    }
                    metrics.maximumHeartRate?.let { maximumHeartRate ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_metric_max_hr),
                            value = stringResource(
                                R.string.garmin_metric_bpm_value,
                                maximumHeartRate
                            ),
                            helper = stringResource(R.string.garmin_metric_heart_rate),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
            metrics.endingHeartRateZone?.let { endingZone ->
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_ending_zone),
                    value = "Z$endingZone",
                    helper = stringResource(R.string.garmin_metric_ending_zone_helper),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (metrics.averageHeartRate != null || metrics.maximumHeartRate != null) {
                GarminHeartRateVisual(metrics = metrics)
            }
            if (metrics.gymCalories != null && metrics.garminCalories != null) {
                GarminMetricCell(
                    label = stringResource(R.string.garmin_metric_kcal_gap),
                    value = metrics.calorieGapLabel(),
                    helper = stringResource(R.string.garmin_metric_gym_vs_garmin),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (metrics.gymCalories != null || metrics.garminCalories != null) {
                Text(
                    text = stringResource(R.string.garmin_kcal_explainer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun GarminWatchInsightsCard(metrics: GarminWorkoutMetrics) {
    val rhythm = remember(metrics.setIntervals) { metrics.rhythmSummary() }
    val zoneSeconds = remember(metrics.setIntervals) { metrics.totalHeartRateZoneSeconds() }
    val recognition = remember(metrics.setEvidence, metrics.setIntervals) {
        metrics.setRecognitionSummary()
    }
    val recovery = remember(metrics.setEvidence, metrics.setIntervals) {
        metrics.recoverySummary()
    }
    val heartRatePoints = remember(metrics.setEvidence, metrics.setIntervals) {
        metrics.setHeartRateChartPoints()
    }

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = stringResource(R.string.garmin_watch_insights_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.garmin_watch_insights_supporting),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (heartRatePoints.isNotEmpty()) {
                GarminSetHeartRateOverview(points = heartRatePoints)
            }
            rhythm?.let {
                GarminWorkoutRhythmVisual(metrics = metrics, rhythm = it)
            }
            if (zoneSeconds.isNotEmpty()) {
                GarminZoneDistribution(zoneSeconds = zoneSeconds)
            }
            if (recognition != null || recovery != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    recognition?.let { summary ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_detection_confidence),
                            value = stringResource(
                                R.string.garmin_detection_confidence_value,
                                summary.averageConfidence
                            ),
                            helper = stringResource(
                                R.string.garmin_sets_with_evidence,
                                summary.measuredSetCount
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }
                    recovery?.let { summary ->
                        GarminMetricCell(
                            label = stringResource(R.string.garmin_recovery_hr_drop),
                            value = stringResource(
                                R.string.garmin_recovery_hr_drop_value,
                                summary.medianHeartRateDrop
                            ),
                            helper = stringResource(
                                R.string.garmin_recovery_median_sets,
                                summary.measuredSetCount
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
            recognition?.lowConfidenceSetNumbers
                ?.takeIf { it.isNotEmpty() }
                ?.let { lowConfidenceSets ->
                    Text(
                        text = stringResource(
                            R.string.garmin_review_low_confidence_sets,
                            lowConfidenceSets.joinToString { "S$it" }
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            if (recognition != null) {
                Text(
                    text = stringResource(R.string.garmin_detection_confidence_explainer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun GarminSetHeartRateOverview(points: List<GarminSetHeartRateChartPoint>) {
    val readings = points.flatMap(GarminSetHeartRateChartPoint::readings)
    if (readings.isEmpty()) return

    val firstSetNumber = points.minOf(GarminSetHeartRateChartPoint::setNumber)
    val lastSetNumber = points.maxOf(GarminSetHeartRateChartPoint::setNumber)
    val minimumReading = readings.minOrNull() ?: return
    val maximumReading = readings.maxOrNull() ?: return
    var chartMinimum = (minimumReading - 10).coerceAtLeast(1)
    var chartMaximum = (maximumReading + 10).coerceAtMost(240)
    if (chartMaximum - chartMinimum < 20) {
        chartMinimum = (chartMaximum - 20).coerceAtLeast(1)
        chartMaximum = (chartMinimum + 20).coerceAtMost(240)
        chartMinimum = (chartMaximum - 20).coerceAtLeast(1)
    }

    val startColor = MaterialTheme.colorScheme.primary
    val peakColor = MaterialTheme.colorScheme.tertiary
    val endColor = MaterialTheme.colorScheme.secondary
    val rangeColor = MaterialTheme.colorScheme.outline
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)
    val accessibilityDescription = stringResource(
        R.string.garmin_set_hr_overview_accessibility,
        points.size,
        minimumReading,
        maximumReading
    )

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.garmin_set_hr_overview_title),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = stringResource(
                    R.string.garmin_set_hr_overview_range,
                    minimumReading,
                    maximumReading
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(142.dp)
                .clip(GymCompactShape)
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f))
                .padding(horizontal = 12.dp, vertical = 12.dp)
                .semantics { contentDescription = accessibilityDescription }
        ) {
            val left = 8f
            val right = size.width - 8f
            val top = 8f
            val bottom = size.height - 8f
            val chartHeight = (bottom - top).coerceAtLeast(1f)
            val chartWidth = (right - left).coerceAtLeast(1f)

            fun xFor(setNumber: Int): Float = if (firstSetNumber == lastSetNumber) {
                left + chartWidth / 2f
            } else {
                left + (
                    (setNumber - firstSetNumber).toFloat() /
                        (lastSetNumber - firstSetNumber).toFloat()
                ) * chartWidth
            }

            fun yFor(value: Int): Float {
                val normalized = (
                    (value - chartMinimum).toFloat() /
                        (chartMaximum - chartMinimum).toFloat()
                ).coerceIn(0f, 1f)
                return bottom - normalized * chartHeight
            }

            listOf(0f, 0.5f, 1f).forEach { fraction ->
                val y = top + chartHeight * fraction
                drawLine(
                    color = gridColor,
                    start = Offset(left, y),
                    end = Offset(right, y),
                    strokeWidth = 2f,
                    cap = StrokeCap.Round
                )
            }

            points.forEach { point ->
                val x = xFor(point.setNumber)
                val setReadings = point.readings
                val setMinimum = setReadings.minOrNull()
                val setMaximum = setReadings.maxOrNull()
                if (setReadings.size > 1 && setMinimum != null && setMaximum != null) {
                    drawLine(
                        color = rangeColor,
                        start = Offset(x, yFor(setMinimum)),
                        end = Offset(x, yFor(setMaximum)),
                        strokeWidth = 5f,
                        cap = StrokeCap.Round
                    )
                }
                point.startHeartRate?.let { value ->
                    drawCircle(
                        color = startColor,
                        radius = 6f,
                        center = Offset(x - 5f, yFor(value))
                    )
                }
                point.peakHeartRate?.let { value ->
                    drawCircle(
                        color = peakColor,
                        radius = 7f,
                        center = Offset(x, yFor(value))
                    )
                }
                point.endHeartRate?.let { value ->
                    drawCircle(
                        color = endColor,
                        radius = 6f,
                        center = Offset(x + 5f, yFor(value))
                    )
                }
            }
        }
        if (firstSetNumber == lastSetNumber) {
            Text(
                text = "S$firstSetNumber",
                modifier = Modifier.align(Alignment.CenterHorizontally),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "S$firstSetNumber",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "S$lastSetNumber",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            GarminHeartRateLegendItem(
                label = stringResource(R.string.garmin_set_hr_start),
                color = startColor,
                modifier = Modifier.weight(1f)
            )
            GarminHeartRateLegendItem(
                label = stringResource(R.string.garmin_set_hr_peak),
                color = peakColor,
                modifier = Modifier.weight(1f)
            )
            GarminHeartRateLegendItem(
                label = stringResource(R.string.garmin_set_hr_end),
                color = endColor,
                modifier = Modifier.weight(1f)
            )
        }
        Text(
            text = stringResource(R.string.garmin_set_hr_overview_supporting),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun GarminHeartRateLegendItem(
    label: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun GarminWorkoutRhythmVisual(
    metrics: GarminWorkoutMetrics,
    rhythm: com.example.gymapp.garmin.GarminWorkoutRhythmSummary
) {
    val intervals = metrics.setIntervals
    val finalEnd = intervals.lastOrNull()?.endOffsetSeconds ?: return
    val scaleSeconds = maxOf(metrics.durationSeconds ?: finalEnd, finalEnd).coerceAtLeast(1L)
    val activeColor = MaterialTheme.colorScheme.primary
    val trackColor = MaterialTheme.colorScheme.surfaceVariant
    val timelineDescription = stringResource(
        R.string.garmin_timeline_accessibility,
        intervals.size,
        formatGarminDuration(rhythm.activeSetSeconds),
        formatGarminDuration(rhythm.betweenSetSeconds)
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.garmin_workout_rhythm_title),
            style = MaterialTheme.typography.labelLarge
        )
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(34.dp)
                .semantics { contentDescription = timelineDescription }
        ) {
            val cornerRadius = CornerRadius(size.height / 2f, size.height / 2f)
            drawRoundRect(
                color = trackColor,
                size = size,
                cornerRadius = cornerRadius
            )
            intervals.forEach { interval ->
                val left = (interval.startOffsetSeconds.toFloat() / scaleSeconds) * size.width
                val right = (interval.endOffsetSeconds.toFloat() / scaleSeconds) * size.width
                val width = (right - left).coerceAtLeast(3f)
                drawRoundRect(
                    color = activeColor,
                    topLeft = Offset(left.coerceAtMost(size.width - 1f), 0f),
                    size = Size(width.coerceAtMost(size.width - left), size.height),
                    cornerRadius = cornerRadius
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = stringResource(
                    R.string.garmin_active_set_time,
                    formatGarminDuration(rhythm.activeSetSeconds)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary
            )
            Text(
                text = stringResource(
                    R.string.garmin_between_set_time,
                    formatGarminDuration(rhythm.betweenSetSeconds)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = stringResource(R.string.garmin_workout_rhythm_helper),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun GarminZoneDistribution(zoneSeconds: List<Long>) {
    val totalSeconds = zoneSeconds.sum().takeIf { it > 0L } ?: return
    val zoneSummary = zoneSeconds.mapIndexedNotNull { zone, seconds ->
        seconds.takeIf { it > 0L }?.let {
            val label = if (zone == 0) {
                stringResource(R.string.garmin_zone_no_reading)
            } else {
                stringResource(R.string.garmin_zone_label, zone)
            }
            "$label ${formatGarminDuration(seconds)}"
        }
    }.joinToString()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.garmin_zone_distribution_title),
            style = MaterialTheme.typography.labelLarge
        )
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(18.dp)
                .clip(GymCompactShape)
                .semantics { contentDescription = zoneSummary }
        ) {
            var x = 0f
            zoneSeconds.forEachIndexed { zone, seconds ->
                if (seconds <= 0L) return@forEachIndexed
                val width = size.width * (seconds.toFloat() / totalSeconds.toFloat())
                drawRect(
                    color = GARMIN_ZONE_COLORS[zone],
                    topLeft = Offset(x, 0f),
                    size = Size(width, size.height)
                )
                x += width
            }
        }
        zoneSeconds.forEachIndexed { zone, seconds ->
            if (seconds <= 0L) return@forEachIndexed
            val percent = ((seconds * 100L) / totalSeconds).toInt()
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(9.dp)
                        .clip(CircleShape)
                        .background(GARMIN_ZONE_COLORS[zone])
                )
                Text(
                    text = if (zone == 0) {
                        stringResource(R.string.garmin_zone_no_reading)
                    } else {
                        stringResource(R.string.garmin_zone_label, zone)
                    },
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodySmall
                )
                Text(
                    text = stringResource(
                        R.string.garmin_zone_time_value,
                        formatGarminDuration(seconds),
                        percent
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
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
            val intervalsBySet = metrics.setIntervals.associateBy { it.setNumber }
            val evidenceBySet = metrics.setEvidence.associateBy { it.setNumber }
            (intervalsBySet.keys + evidenceBySet.keys)
                .sorted()
                .forEach { setNumber ->
                    val interval = intervalsBySet[setNumber]
                    if (interval != null) {
                        GarminSetIntervalRow(interval = interval)
                    } else {
                        evidenceBySet[setNumber]?.let { evidence ->
                            GarminSetEvidenceRow(evidence = evidence)
                        }
                    }
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
private fun GarminSetEvidenceRow(evidence: GarminSetEvidenceMetrics) {
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
                text = stringResource(R.string.garmin_watch_set_label, evidence.setNumber),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            evidence.activeSeconds?.let { activeSeconds ->
                Text(
                    text = stringResource(
                        R.string.garmin_set_interval_active,
                        formatGarminDuration(activeSeconds)
                    ),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
        GarminSetEvidenceBody(
            restBeforeSeconds = evidence.restBeforeSeconds,
            startHeartRate = evidence.startHeartRate,
            peakHeartRate = evidence.peakHeartRate,
            endHeartRate = evidence.endHeartRate,
            recoveryHeartRateDrop = evidence.recoveryHeartRateDrop,
            detectionConfidence = evidence.detectionConfidence
        )
    }
}

@Composable
private fun GarminSetIntervalRow(interval: GarminSetIntervalMetrics) {
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
        GarminSetEvidenceBody(
            restBeforeSeconds = interval.restBeforeSeconds,
            startHeartRate = interval.startHeartRate,
            peakHeartRate = interval.peakHeartRate,
            endHeartRate = interval.endHeartRate,
            recoveryHeartRateDrop = interval.recoveryHeartRateDrop,
            detectionConfidence = interval.detectionConfidence
        )
        Text(
            text = interval.garminCalories?.let { garminCalories ->
                stringResource(
                    R.string.garmin_set_interval_calories,
                    formatGarminIntervalCalories(interval.gymCalories),
                    garminCalories.toString()
                )
            } ?: stringResource(
                R.string.garmin_set_interval_gym_calories,
                formatGarminIntervalCalories(interval.gymCalories)
            ),
            style = MaterialTheme.typography.bodyMedium
        )
        if (interval.heartRateZoneSeconds.any { it > 0 }) {
            GarminSetZoneBar(interval = interval)
        } else {
            Text(
                text = stringResource(R.string.garmin_set_interval_no_zones),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun GarminSetEvidenceBody(
    restBeforeSeconds: Long?,
    startHeartRate: Int?,
    peakHeartRate: Int?,
    endHeartRate: Int?,
    recoveryHeartRateDrop: Int?,
    detectionConfidence: Int?
) {
    if (detectionConfidence != null || recoveryHeartRateDrop != null) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            detectionConfidence?.let { confidence ->
                InfoPill(
                    text = stringResource(R.string.garmin_set_confidence_value, confidence),
                    modifier = Modifier.weight(1f),
                    accent = when {
                        confidence >= 70 -> MaterialTheme.colorScheme.primary
                        confidence >= 40 -> MaterialTheme.colorScheme.tertiary
                        else -> MaterialTheme.colorScheme.error
                    }
                )
            }
            recoveryHeartRateDrop?.let { drop ->
                InfoPill(
                    text = stringResource(R.string.garmin_set_recovery_value, drop),
                    modifier = Modifier.weight(1f),
                    accent = MaterialTheme.colorScheme.secondary
                )
            }
        }
    }
    restBeforeSeconds?.let { seconds ->
        Text(
            text = stringResource(
                R.string.garmin_set_rest_before,
                formatGarminDuration(seconds)
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    if (startHeartRate != null || peakHeartRate != null || endHeartRate != null) {
        GarminSetHeartRateMarkers(
            startHeartRate = startHeartRate,
            peakHeartRate = peakHeartRate,
            endHeartRate = endHeartRate
        )
    }
}

@Composable
private fun GarminSetHeartRateMarkers(
    startHeartRate: Int?,
    peakHeartRate: Int?,
    endHeartRate: Int?
) {
    val readings = listOf(
        stringResource(R.string.garmin_set_hr_start) to startHeartRate,
        stringResource(R.string.garmin_set_hr_peak) to peakHeartRate,
        stringResource(R.string.garmin_set_hr_end) to endHeartRate
    )
    val availableReadings = readings.mapIndexedNotNull { index, (label, value) ->
        value?.let { Triple(index, label, it) }
    }
    if (availableReadings.isEmpty()) return
    val chartDescription = availableReadings.joinToString { (_, label, value) -> "$label $value" }
    val lineColor = MaterialTheme.colorScheme.primary
    val pointColor = MaterialTheme.colorScheme.tertiary
    val trackColor = MaterialTheme.colorScheme.outlineVariant
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(
            text = stringResource(R.string.garmin_set_hr_markers_title),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(GymCompactShape)
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.45f))
                .padding(horizontal = 10.dp, vertical = 7.dp)
                .semantics { contentDescription = chartDescription }
        ) {
            fun pointFor(index: Int, value: Int): Offset {
                val x = when (index) {
                    0 -> 6f
                    1 -> size.width / 2f
                    else -> size.width - 6f
                }
                val normalized = ((value - 40f) / 200f).coerceIn(0f, 1f)
                val y = size.height - 6f - (normalized * (size.height - 12f))
                return Offset(x, y)
            }
            drawLine(
                color = trackColor,
                start = Offset(6f, size.height / 2f),
                end = Offset(size.width - 6f, size.height / 2f),
                strokeWidth = 2f,
                cap = StrokeCap.Round
            )
            val points = availableReadings.map { (index, _, value) -> pointFor(index, value) }
            points.zipWithNext().forEach { (start, end) ->
                drawLine(
                    color = lineColor,
                    start = start,
                    end = end,
                    strokeWidth = 5f,
                    cap = StrokeCap.Round
                )
            }
            points.forEach { point ->
                drawCircle(color = pointColor, radius = 6f, center = point)
            }
        }
        Text(
            text = availableReadings.joinToString(separator = " · ") { (_, label, value) ->
                "$label $value"
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun GarminSetZoneBar(interval: GarminSetIntervalMetrics) {
    val totalSeconds = interval.heartRateZoneSeconds.sum().takeIf { it > 0 } ?: return
    val summary = interval.heartRateZoneSeconds
        .mapIndexedNotNull { zone, seconds ->
            seconds.takeIf { it > 0 }?.let {
                val label = if (zone == 0) {
                    stringResource(R.string.garmin_zone_no_reading)
                } else {
                    stringResource(R.string.garmin_zone_label, zone)
                }
                "$label ${formatGarminDuration(seconds.toLong())}"
            }
        }
        .joinToString()
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(11.dp)
                .clip(GymCompactShape)
                .semantics { contentDescription = summary }
        ) {
            var x = 0f
            interval.heartRateZoneSeconds.forEachIndexed { zone, seconds ->
                if (seconds <= 0) return@forEachIndexed
                val width = size.width * (seconds.toFloat() / totalSeconds.toFloat())
                drawRect(
                    color = GARMIN_ZONE_COLORS[zone],
                    topLeft = Offset(x, 0f),
                    size = Size(width, size.height)
                )
                x += width
            }
        }
        Text(
            text = if (summary.isBlank()) {
                stringResource(R.string.garmin_set_interval_no_zones)
            } else {
                summary
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
    frequentExerciseIds: List<Long>,
    exerciseWorkoutCounts: Map<Long, Int>,
    exerciseMuscleIds: Map<String, Set<String>>,
    exerciseMediaOwnerKey: String,
    onAddExerciseToWorkout: (Long) -> Unit
) {
    var selectedExerciseId by remember(availableExercises) {
        mutableStateOf<Long?>(null)
    }
    val availableExerciseIds = remember(availableExercises) {
        availableExercises.mapTo(linkedSetOf()) { it.id }
    }
    val addableExerciseId = selectedWorkoutExerciseQuickAddId(
        selectedExerciseId = selectedExerciseId,
        availableExerciseIds = availableExerciseIds
    )

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
                ExerciseCatalogSelector(
                    selectedExerciseId = addableExerciseId,
                    exercises = availableExercises,
                    frequentExerciseIds = frequentExerciseIds,
                    exerciseWorkoutCounts = exerciseWorkoutCounts,
                    exerciseMuscleIds = exerciseMuscleIds,
                    exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                    onExerciseSelected = { selectedExerciseId = it },
                    modifier = Modifier.fillMaxWidth()
                )

                Button(
                    onClick = {
                        val selectedId = addableExerciseId ?: return@Button
                        onAddExerciseToWorkout(selectedId)
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = addableExerciseId != null
                ) {
                    Text(text = stringResource(R.string.action_add_to_workout))
                }
            }
        }
    }
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
