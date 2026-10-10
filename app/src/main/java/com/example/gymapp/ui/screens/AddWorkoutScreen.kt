package com.example.gymapp.ui.screens

import com.example.gymapp.ui.components.TrainingSettingsSummaryRow
import com.example.gymapp.ui.components.TrainingSettingsSheet
import android.app.DatePickerDialog
import android.content.Context
import androidx.activity.compose.BackHandler
import java.text.NumberFormat
import com.example.gymapp.ui.viewmodel.SetInputState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.SmartWorkoutAlternative
import com.example.gymapp.data.repository.SmartWorkoutAlternativeReason
import com.example.gymapp.data.repository.SmartWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.WorkoutRecommendation
import com.example.gymapp.data.repository.WorkoutRecommendationKind
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.components.ExerciseMuscleMap
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import com.example.gymapp.ui.viewmodel.SmartWorkoutPlanSummaryUiModel
import com.example.gymapp.ui.viewmodel.WorkoutTemplatePreviewUiModel
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import com.example.gymapp.util.asString
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** Lazy items (coach panel, exercises header) that precede the exercise cards in the plan editor. */
private const val PLAN_EDITOR_LEADING_ITEM_COUNT = 2

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddWorkoutScreen(
    uiState: AddWorkoutUiState,
    exerciseMediaOwnerKey: String,
    onWorkoutDateSelected: (Long) -> Unit,
    onNoteChange: (String) -> Unit,
    onTrainingSplitSelected: (TrainingSplit) -> Unit,
    onWorkoutsPerWeekSelected: (Int) -> Unit,
    onTrainingGoalSelected: (TrainingGoal) -> Unit,
    onCalorieModeSelected: (CalorieMode) -> Unit,
    onSmartWorkoutEffortSelected: (SmartWorkoutEffort) -> Unit,
    onGenerateSmartWorkout: () -> Unit,
    onOpenSmartAlternatives: (Long) -> Unit,
    onCloseSmartAlternatives: () -> Unit,
    onApplySmartAlternative: (Long, Long, Long) -> Unit,
    onAddExerciseDraft: () -> Unit,
    onClearPlan: () -> Unit,
    onRemoveExerciseDraft: (Long) -> Unit,
    onExerciseSelected: (Long, Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onRemoveSet: (Long, Int) -> Unit,
    onSetWeightChanged: (Long, Int, String) -> Unit,
    onSetRepsChanged: (Long, Int, String) -> Unit,
    onApplyLastWeightToSet: (Long, Int) -> Unit,
    onCopyPreviousSet: (Long, Int) -> Unit,
    onAddWeightToSet: (Long, Int) -> Unit,
    onDuplicateSet: (Long, Int) -> Unit,
    onApplyWorkoutRecommendation: (Long) -> Unit,
    onRepeatLastWorkout: () -> Unit,
    onOpenTemplatePicker: () -> Unit,
    onCloseTemplatePicker: () -> Unit,
    onCopyWorkoutTemplate: (Long) -> Unit,
    onSyncPlanToWatch: () -> Unit,
    onShareWorkout: () -> Unit,
    garminWatchIsLite: Boolean = false,
    liveInviteTargetName: String? = null,
    hasLiveInviteTarget: Boolean = !liveInviteTargetName.isNullOrBlank(),
    isLiveInviteAvailable: Boolean = true,
    isLiveInviteSending: Boolean = false,
    onSendLiveInvite: () -> Unit = {},
    onStartWorkout: () -> Unit,
    onNavigateToHistory: () -> Unit,
    onDiscardPlan: () -> Unit,
    externalCloseRequestVersion: Long,
    onExternalCloseRequestHandled: () -> Unit,
    onDirtyStateChanged: (Boolean) -> Unit,
    onInteractionLockChanged: (Boolean) -> Unit = {},
    onApplyVoiceWorkout: (List<com.example.gymapp.data.repository.WorkoutExerciseDraft>, Boolean) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    val selectedExerciseCount = uiState.exerciseDrafts.count { it.exerciseId != null }
    val primaryAction = workoutPlanPrimaryAction(hasLiveInviteTarget)
    val primaryActionInProgress = uiState.isSaving ||
        (primaryAction == WorkoutPlanPrimaryAction.SendLiveInvite && isLiveInviteSending)
    val editorInteractionsLocked = workoutPlanEditorInteractionsLocked(isLiveInviteSending)
    var secondaryOptionsExpanded by rememberSaveable { mutableStateOf(false) }
    var showTrainingSettings by rememberSaveable { mutableStateOf(false) }
    if (showTrainingSettings) {
        val profile = uiState.trainingProfile
        TrainingSettingsSheet(
            profile = profile,
            onProfileChange = { updated ->
                when {
                    updated.goal != profile.goal -> onTrainingGoalSelected(updated.goal)
                    updated.calorieMode != profile.calorieMode -> onCalorieModeSelected(updated.calorieMode)
                    updated.split != profile.split -> onTrainingSplitSelected(updated.split)
                    updated.workoutsPerWeek != profile.workoutsPerWeek ->
                        onWorkoutsPerWeekSelected(updated.workoutsPerWeek)
                }
            },
            onDismiss = { showTrainingSettings = false }
        )
    }
    val listState = rememberLazyListState()
    // New exercises are appended at the end, so bring the freshly added card into view.
    var revealAppendedDraft by remember { mutableStateOf(false) }
    var lastDraftCount by remember { mutableIntStateOf(uiState.exerciseDrafts.size) }
    val draftCount = uiState.exerciseDrafts.size
    LaunchedEffect(draftCount) {
        val shouldReveal = revealAppendedDraft && draftCount > lastDraftCount
        revealAppendedDraft = false
        lastDraftCount = draftCount
        if (shouldReveal) {
            listState.animateScrollToItem(PLAN_EDITOR_LEADING_ITEM_COUNT + draftCount - 1)
        }
    }
    val addExerciseDraftAndReveal: () -> Unit = {
        revealAppendedDraft = true
        onAddExerciseDraft()
    }
    var showDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    var showClearConfirmation by rememberSaveable { mutableStateOf(false) }
    var showVoiceWorkoutSheet by rememberSaveable { mutableStateOf(false) }
    val requestClose = onNavigateToHistory
    Box(modifier = modifier.fillMaxSize()) {
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .testTag("workout_plan_editor_list")
            .then(
                if (editorInteractionsLocked) {
                    Modifier.clearAndSetSemantics { disabled() }
                } else {
                    Modifier
                }
            ),
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.ScreenTop,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
    ) {
        item {
            SmartCoachPanel(
                trainingProfile = uiState.trainingProfile,
                onEditTrainingSettings = { showTrainingSettings = true },
                selectedEffort = uiState.smartWorkoutEffort,
                generatedPlan = uiState.generatedSmartPlan,
                generatedPlanNeedsRefresh = uiState.generatedSmartPlanNeedsRefresh,
                onEffortSelected = onSmartWorkoutEffortSelected,
                onGenerateSmartWorkout = onGenerateSmartWorkout
            )
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SectionTitle(
                    eyebrow = "",
                    title = stringResource(R.string.title_exercises),
                    modifier = Modifier.weight(1f)
                )
                val voiceLabel = stringResource(R.string.voice_workout_open)
                FilledIconButton(
                    onClick = { showVoiceWorkoutSheet = true },
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.primary
                    ),
                    modifier = Modifier
                        .size(44.dp)
                        .testTag("voice_workout_open")
                        .semantics { contentDescription = voiceLabel }
                ) {
                    Icon(imageVector = Icons.Default.Mic, contentDescription = null)
                }
                if (uiState.exerciseDrafts.isNotEmpty()) {
                    FilledIconButton(
                        onClick = addExerciseDraftAndReveal,
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = stringResource(R.string.action_add_exercise)
                        )
                    }
                    var planMenuExpanded by remember { mutableStateOf(false) }
                    Box {
                        FilledIconButton(
                            onClick = { planMenuExpanded = true },
                            colors = IconButtonDefaults.filledIconButtonColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                                contentColor = MaterialTheme.colorScheme.primary
                            ),
                            modifier = Modifier
                                .size(44.dp)
                                .testTag("workout_plan_exercises_menu")
                        ) {
                            Icon(
                                imageVector = Icons.Default.MoreHoriz,
                                contentDescription = stringResource(
                                    R.string.workout_plan_exercises_more_options
                                )
                            )
                        }
                        DropdownMenu(
                            expanded = planMenuExpanded,
                            onDismissRequest = { planMenuExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = stringResource(R.string.workout_plan_clear_action),
                                        color = MaterialTheme.colorScheme.error
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                },
                                onClick = {
                                    planMenuExpanded = false
                                    showClearConfirmation = true
                                },
                                modifier = Modifier.testTag("workout_plan_clear_action")
                            )
                        }
                    }
                }
            }
        }

        if (uiState.exerciseDrafts.isEmpty()) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = addExerciseDraftAndReveal,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Add, contentDescription = null)
                        Spacer(modifier = Modifier.size(8.dp))
                        Text(stringResource(R.string.action_add_exercise))
                    }
                }
            }
        }

        itemsIndexed(
            items = uiState.exerciseDrafts,
            key = { _, draft -> draft.draftId }
        ) { index, draft ->
            ExerciseDraftCard(
                index = index,
                draft = draft,
                exercises = uiState.exercises,
                frequentExerciseIds = uiState.frequentExerciseIds,
                exerciseWorkoutCounts = uiState.exerciseWorkoutCounts,
                exerciseMuscleIds = uiState.exerciseMuscleIds,
                lastWeight = draft.exerciseId?.let { uiState.lastWeights[it] },
                allowedWeights = draft.exerciseId
                    ?.let { uiState.exerciseLoadProfiles[it]?.allowedWeightsKg }
                    .orEmpty(),
                recommendation = draft.exerciseId?.let { uiState.workoutRecommendations[it] },
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onExerciseSelected = { selectedExerciseId ->
                    onExerciseSelected(draft.draftId, selectedExerciseId)
                },
                onAddSet = { onAddSet(draft.draftId) },
                onRemoveSet = { setIndex -> onRemoveSet(draft.draftId, setIndex) },
                onWeightChanged = { setIndex, value ->
                    onSetWeightChanged(draft.draftId, setIndex, value)
                },
                onRepsChanged = { setIndex, value ->
                    onSetRepsChanged(draft.draftId, setIndex, value)
                },
                onApplyLastWeightToSet = { setIndex -> onApplyLastWeightToSet(draft.draftId, setIndex) },
                onCopyPreviousSet = { setIndex -> onCopyPreviousSet(draft.draftId, setIndex) },
                onDuplicateSet = { setIndex -> onDuplicateSet(draft.draftId, setIndex) },
                onApplyWorkoutRecommendation = { onApplyWorkoutRecommendation(draft.draftId) },
                onOpenSmartAlternatives = { onOpenSmartAlternatives(draft.draftId) },
                onRemoveExerciseDraft = { onRemoveExerciseDraft(draft.draftId) }
            )
        }

        if (uiState.exerciseDrafts.isNotEmpty()) {
            item(key = "workout_plan_add_exercise_footer") {
                val addExerciseDescription = stringResource(R.string.action_add_exercise)
                WorkoutFooterButton(
                    label = stringResource(R.string.workout_detail_add_exercise_short),
                    accessibilityLabel = addExerciseDescription,
                    dashed = true,
                    enabled = true,
                    onClick = addExerciseDraftAndReveal,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("workout_plan_add_exercise_footer")
                )
            }
        }

        if (uiState.hasValidationError) {
            item {
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.error.copy(alpha = 0.20f),
                    highlighted = true
                ) {
                    Text(
                        text = stringResource(R.string.message_validation_error),
                        modifier = Modifier.padding(14.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }

        item {
            Button(
                onClick = when (primaryAction) {
                    WorkoutPlanPrimaryAction.StartSolo -> onStartWorkout
                    WorkoutPlanPrimaryAction.SendLiveInvite -> onSendLiveInvite
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("workout_plan_primary_action"),
                enabled = !primaryActionInProgress &&
                    !uiState.isTemplateLoading &&
                    !uiState.isSyncingPlanToWatch &&
                    uiState.exerciseDrafts.isNotEmpty() &&
                    (primaryAction != WorkoutPlanPrimaryAction.SendLiveInvite ||
                        isLiveInviteAvailable)
            ) {
                if (primaryActionInProgress) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp).size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text(
                    text = when (primaryAction) {
                        WorkoutPlanPrimaryAction.StartSolo ->
                            stringResource(R.string.action_start_workout)
                        WorkoutPlanPrimaryAction.SendLiveInvite ->
                            if (liveInviteTargetName.isNullOrBlank()) {
                                stringResource(R.string.workout_share_live_friend_title)
                            } else {
                                stringResource(
                                    R.string.workout_share_live_friend_action,
                                    liveInviteTargetName
                                )
                            }
                    }
                )
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics {
                            stateDescription = if (secondaryOptionsExpanded) {
                                context.getString(R.string.state_expanded)
                            } else {
                                context.getString(R.string.state_collapsed)
                            }
                        }
                        .clickable(role = Role.Button) {
                            secondaryOptionsExpanded = !secondaryOptionsExpanded
                        }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Tune,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(end = 12.dp)
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = stringResource(R.string.workout_plan_more_options),
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            text = stringResource(R.string.workout_plan_more_options_supporting),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Icon(
                        imageVector = if (secondaryOptionsExpanded) {
                            Icons.Default.ExpandLess
                        } else {
                            Icons.Default.ExpandMore
                        },
                        contentDescription = null
                    )
                }
            }
        }

        if (secondaryOptionsExpanded) {
        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.label_workout_date),
                        title = stringResource(R.string.label_note)
                    )
                    OutlinedButton(
                        onClick = {
                            showWorkoutDatePicker(
                                context = context,
                                currentTimestamp = uiState.workoutDate,
                                onSelectedEpochDay = onWorkoutDateSelected
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = GymControlShape
                    ) {
                        Icon(
                            imageVector = Icons.Default.CalendarMonth,
                            contentDescription = null
                        )
                        Spacer(modifier = Modifier.size(8.dp))
                        Text(DateTimeUtils.formatDate(uiState.workoutDate))
                    }
                    OutlinedTextField(
                        value = uiState.note,
                        onValueChange = onNoteChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.label_note)) },
                        placeholder = { Text(stringResource(R.string.hint_note)) },
                        minLines = 2,
                        maxLines = 4
                    )
                }
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = "",
                        title = stringResource(R.string.add_workout_choose_training_day)
                    )
                    OutlinedButton(
                        onClick = onRepeatLastWorkout,
                        enabled = uiState.canRepeatFromLast && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_repeat_last_workout),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onOpenTemplatePicker,
                        enabled = uiState.workoutTemplates.isNotEmpty() && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_copy_workout_day),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.title_add_workout),
                        title = stringResource(R.string.action_sync_plan_to_garmin),
                        supporting = stringResource(R.string.add_workout_plan_mode_hint)
                    )
                    if (garminWatchIsLite) {
                        Text(
                            text = stringResource(R.string.garmin_lite_free_only_notice),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    OutlinedButton(
                        onClick = onSyncPlanToWatch,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = selectedExerciseCount > 0 &&
                            !uiState.isSyncingPlanToWatch &&
                            !garminWatchIsLite
                    ) {
                        if (uiState.isSyncingPlanToWatch) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .padding(end = 8.dp)
                                    .size(18.dp),
                                strokeWidth = 2.dp
                            )
                        }
                        Text(
                            text = if (uiState.isSyncingPlanToWatch) {
                                stringResource(R.string.action_sync_plan_to_watch_in_progress)
                            } else {
                                stringResource(R.string.action_sync_plan_to_garmin)
                            }
                        )
                    }
                    when (uiState.didSyncPlanToWatch) {
                        true -> Text(
                            text = stringResource(R.string.message_plan_sync_success),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                        false -> Text(
                            text = uiState.watchPlanSyncError?.asString()
                                ?: stringResource(R.string.message_plan_sync_failed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                        null -> Unit
                    }
                }
            }
        }

        item {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = stringResource(R.string.add_workout_active_mode_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (workoutPlanAllowsGenericShare(hasLiveInviteTarget)) {
                    OutlinedButton(
                        onClick = onShareWorkout,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = selectedExerciseCount > 0 && !uiState.isSaving
                    ) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = null
                        )
                        Spacer(modifier = Modifier.size(8.dp))
                        Text(text = stringResource(R.string.action_share_workout))
                    }
                }
                if (uiState.isDirty ||
                    uiState.exerciseDrafts.isNotEmpty() ||
                    uiState.note.isNotBlank()
                ) {
                    TextButton(
                        onClick = { showDiscardConfirmation = true },
                        enabled = !uiState.isSaving && !uiState.isTemplateLoading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("workout_plan_discard_draft")
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.size(8.dp))
                        Text(
                            text = stringResource(R.string.workout_plan_discard_draft),
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
        }
    }
        if (editorInteractionsLocked) {
            val lockInteractionSource = remember { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .testTag("workout_plan_editor_locked")
                    .clickable(
                        interactionSource = lockInteractionSource,
                        indication = null,
                        onClick = {}
                    )
                    .semantics { disabled() }
            )
        }
    }

    BackHandler(enabled = editorInteractionsLocked) {}
    BackHandler(enabled = !editorInteractionsLocked, onBack = requestClose)
    LaunchedEffect(externalCloseRequestVersion, editorInteractionsLocked) {
        if (externalCloseRequestVersion > 0L && !editorInteractionsLocked) {
            requestClose()
            onExternalCloseRequestHandled()
        }
    }
    LaunchedEffect(uiState.isDirty) {
        onDirtyStateChanged(uiState.isDirty)
    }
    LaunchedEffect(editorInteractionsLocked) {
        onInteractionLockChanged(editorInteractionsLocked)
    }
    DisposableEffect(Unit) {
        onDispose {
            onDirtyStateChanged(false)
            onInteractionLockChanged(false)
        }
    }
    if (showDiscardConfirmation && !editorInteractionsLocked) {
        AlertDialog(
            onDismissRequest = { showDiscardConfirmation = false },
            title = { Text(stringResource(R.string.workout_plan_discard_title)) },
            text = { Text(stringResource(R.string.workout_plan_discard_message)) },
            confirmButton = {
                TextButton(onClick = onDiscardPlan) {
                    Text(stringResource(R.string.workout_plan_discard_changes))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardConfirmation = false }) {
                    Text(stringResource(R.string.workout_plan_keep_editing))
                }
            }
        )
    }
    if (showVoiceWorkoutSheet && !editorInteractionsLocked) {
        VoiceWorkoutDraftSheet(
            exercises = uiState.exercises,
            existingExerciseCount = uiState.exerciseDrafts.size,
            onApply = { drafts, replace ->
                onApplyVoiceWorkout(drafts, replace)
                showVoiceWorkoutSheet = false
            },
            onDismiss = { showVoiceWorkoutSheet = false }
        )
    }
    if (showClearConfirmation && !editorInteractionsLocked) {
        AlertDialog(
            onDismissRequest = { showClearConfirmation = false },
            title = { Text(stringResource(R.string.workout_plan_clear_title)) },
            text = { Text(stringResource(R.string.workout_plan_clear_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearConfirmation = false
                        onClearPlan()
                    }
                ) {
                    Text(
                        text = stringResource(R.string.workout_plan_clear_action),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirmation = false }) {
                    Text(stringResource(R.string.workout_plan_clear_keep))
                }
            }
        )
    }

    if (uiState.isTemplatePickerOpen && !editorInteractionsLocked) {
        ModalBottomSheet(
            onDismissRequest = onCloseTemplatePicker,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            WorkoutTemplatePickerContent(
                templates = uiState.workoutTemplates,
                onCopyWorkoutTemplate = onCopyWorkoutTemplate,
                onDismiss = onCloseTemplatePicker
            )
        }
    }

    uiState.smartAlternativePicker?.takeUnless { editorInteractionsLocked }?.let { picker ->
        ModalBottomSheet(
            onDismissRequest = onCloseSmartAlternatives,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            SmartWorkoutAlternativePickerContent(
                currentExerciseName = uiState.exercises
                    .firstOrNull { it.id == picker.expectedExerciseId }
                    ?.name,
                alternatives = picker.alternatives,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onSelect = { replacementExerciseId ->
                    onApplySmartAlternative(
                        picker.draftId,
                        picker.expectedExerciseId,
                        replacementExerciseId
                    )
                },
                onDismiss = onCloseSmartAlternatives
            )
        }
    }
}

internal enum class WorkoutPlanPrimaryAction {
    StartSolo,
    SendLiveInvite
}

internal fun workoutPlanAllowsGenericShare(hasLiveInviteTarget: Boolean): Boolean =
    !hasLiveInviteTarget

internal fun workoutPlanEditorInteractionsLocked(isLiveInviteSending: Boolean): Boolean =
    isLiveInviteSending

internal fun workoutPlanPrimaryAction(hasLiveInviteTarget: Boolean): WorkoutPlanPrimaryAction =
    if (hasLiveInviteTarget) {
        WorkoutPlanPrimaryAction.SendLiveInvite
    } else {
        WorkoutPlanPrimaryAction.StartSolo
    }

private fun showWorkoutDatePicker(
    context: Context,
    currentTimestamp: Long,
    onSelectedEpochDay: (Long) -> Unit
) {
    val zoneId = ZoneId.systemDefault()
    val currentDate = Instant.ofEpochMilli(currentTimestamp).atZone(zoneId).toLocalDate()
    DatePickerDialog(
        context,
        { _, year, zeroBasedMonth, dayOfMonth ->
            runCatching { LocalDate.of(year, zeroBasedMonth + 1, dayOfMonth) }
                .getOrNull()
                ?.let { selectedDate -> onSelectedEpochDay(selectedDate.toEpochDay()) }
        },
        currentDate.year,
        currentDate.monthValue - 1,
        currentDate.dayOfMonth
    ).apply {
        datePicker.maxDate = System.currentTimeMillis()
    }.show()
}

@Composable
private fun SmartCoachPanel(
    trainingProfile: TrainingProfile,
    onEditTrainingSettings: () -> Unit,
    selectedEffort: SmartWorkoutEffort,
    generatedPlan: SmartWorkoutPlanSummaryUiModel?,
    generatedPlanNeedsRefresh: Boolean,
    onEffortSelected: (SmartWorkoutEffort) -> Unit,
    onGenerateSmartWorkout: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = "",
                title = stringResource(R.string.smart_coach_title)
            )
            // The coach settings summary sits at the top of this card; the full editor is shared.
            TrainingSettingsSummaryRow(profile = trainingProfile, onEdit = onEditTrainingSettings)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SmartWorkoutEffort.entries.chunked(2).forEach { rowEfforts ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowEfforts.forEach { effort ->
                            FilterChip(
                                selected = selectedEffort == effort,
                                onClick = { onEffortSelected(effort) },
                                label = { Text(effort.smartCoachLabel()) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
            generatedPlan?.let { plan ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (generatedPlanNeedsRefresh) {
                        Text(
                            text = stringResource(R.string.smart_coach_plan_needs_refresh),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.TrackChanges,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = stringResource(
                                R.string.smart_coach_focus_rir,
                                plan.focus.smartCoachLabel(),
                                plan.rirSummary
                            ),
                            style = MaterialTheme.typography.titleSmall
                        )
                    }
                    if (plan.requestedEffort != plan.appliedEffort) {
                        Text(
                            text = stringResource(
                                R.string.smart_coach_effort_override,
                                plan.requestedEffort.smartCoachLabel(),
                                plan.appliedEffort.smartCoachLabel()
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    plan.effortAdjustment?.let { adjustment ->
                        Text(
                            text = adjustment.smartCoachLabel(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            Button(
                onClick = onGenerateSmartWorkout,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(imageVector = Icons.Default.AutoAwesome, contentDescription = null)
                Text(
                    text = stringResource(R.string.action_generate_smart_workout),
                    modifier = Modifier.padding(start = 8.dp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun SmartWorkoutEffort.smartCoachLabel(): String = when (this) {
    SmartWorkoutEffort.Auto -> stringResource(R.string.smart_effort_auto)
    SmartWorkoutEffort.Recovery -> stringResource(R.string.smart_effort_recovery)
    SmartWorkoutEffort.Standard -> stringResource(R.string.smart_effort_standard)
    SmartWorkoutEffort.Hard -> stringResource(R.string.smart_effort_hard)
}

@Composable
private fun SmartWorkoutEffortAdjustment.smartCoachLabel(): String = when (this) {
    SmartWorkoutEffortAdjustment.AutoRecovery ->
        stringResource(R.string.smart_effort_adjustment_auto_recovery)
    SmartWorkoutEffortAdjustment.FeedbackHardRecovery ->
        stringResource(R.string.smart_effort_adjustment_feedback_hard)
    SmartWorkoutEffortAdjustment.FeedbackEasyExtraSet ->
        stringResource(R.string.smart_effort_adjustment_feedback_easy)
    SmartWorkoutEffortAdjustment.ReadinessLowRecovery ->
        stringResource(R.string.smart_effort_adjustment_readiness_low)
    SmartWorkoutEffortAdjustment.HardInsufficientHistory ->
        stringResource(R.string.smart_effort_adjustment_history)
    SmartWorkoutEffortAdjustment.HardRecentBreak ->
        stringResource(R.string.smart_effort_adjustment_break)
    SmartWorkoutEffortAdjustment.HardMusclesRecovering ->
        stringResource(R.string.smart_effort_adjustment_recovery)
}

@Composable
private fun SmartWorkoutFocus.smartCoachLabel(): String = when (this) {
    SmartWorkoutFocus.Upper -> stringResource(R.string.smart_focus_upper)
    SmartWorkoutFocus.Lower -> stringResource(R.string.smart_focus_lower)
    SmartWorkoutFocus.Push -> stringResource(R.string.smart_focus_push)
    SmartWorkoutFocus.Pull -> stringResource(R.string.smart_focus_pull)
    SmartWorkoutFocus.Legs -> stringResource(R.string.smart_focus_legs)
    SmartWorkoutFocus.FullBody -> stringResource(R.string.smart_focus_full_body)
}

@Composable
private fun WorkoutTemplatePickerContent(
    templates: List<WorkoutTemplatePreviewUiModel>,
    onCopyWorkoutTemplate: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(R.string.template_picker_title),
                style = MaterialTheme.typography.headlineSmall
            )
        }

        if (templates.isEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.template_picker_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            items(
                items = templates,
                key = { it.sessionId }
            ) { template ->
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    highlighted = true
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = DateTimeUtils.formatDate(template.date),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            text = stringResource(
                                R.string.template_picker_summary,
                                pluralStringResource(
                                    R.plurals.saved_workout_exercise_count,
                                    template.exerciseCount,
                                    template.exerciseCount
                                ),
                                pluralStringResource(
                                    R.plurals.saved_workout_set_count,
                                    template.setCount,
                                    template.setCount
                                ),
                                String.format(Locale.getDefault(), "%.0f", template.totalVolume)
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Button(
                            onClick = { onCopyWorkoutTemplate(template.sessionId) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.action_copy_workout_day))
                        }
                    }
                }
            }
        }

        item {
            HorizontalDivider()
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    }
}

/**
 * One exercise of the plan, built from the same card pieces as the active and saved workout screens
 * ([WorkoutExerciseCardShell], header, [SetEditorCapsules], dashed [WorkoutFooterButton]) so all
 * three read alike. The plan's cards are highlighted and never collapse; the header menu holds
 * "Replace with similar" and the immediate (draft-only) "Delete".
 */
@Composable
private fun ExerciseDraftCard(
    index: Int,
    draft: ExerciseInputState,
    exercises: List<ExerciseEntity>,
    frequentExerciseIds: List<Long>,
    exerciseWorkoutCounts: Map<Long, Int>,
    exerciseMuscleIds: Map<String, Set<String>>,
    lastWeight: Double?,
    allowedWeights: List<Double>,
    recommendation: WorkoutRecommendation?,
    exerciseMediaOwnerKey: String,
    onExerciseSelected: (Long) -> Unit,
    onAddSet: () -> Unit,
    onRemoveSet: (Int) -> Unit,
    onWeightChanged: (Int, String) -> Unit,
    onRepsChanged: (Int, String) -> Unit,
    onApplyLastWeightToSet: (Int) -> Unit,
    onCopyPreviousSet: (Int) -> Unit,
    onDuplicateSet: (Int) -> Unit,
    onApplyWorkoutRecommendation: () -> Unit,
    onOpenSmartAlternatives: () -> Unit,
    onRemoveExerciseDraft: () -> Unit
) {
    val selectedExercise = exercises.firstOrNull { it.id == draft.exerciseId }
    val exerciseName = selectedExercise?.let { localizedExerciseName(it.name) }
        ?: stringResource(R.string.exercise_block_title, index + 1)
    val locale = Locale.forLanguageTag(currentAppLanguageTag())
    val addSetDescription = stringResource(R.string.action_add_planned_set)

    WorkoutExerciseCardShell(highlighted = true) {
        WorkoutExerciseCardHeader(
            title = exerciseName,
            onToggleExpanded = null,
            media = selectedExercise?.let { exercise ->
                {
                    WorkoutExerciseMedia(
                        exerciseId = exercise.id,
                        exerciseName = exercise.name,
                        ownerKey = exerciseMediaOwnerKey
                    )
                }
            },
            menu = {
                WorkoutExerciseMenu(
                    enabled = true,
                    onRemove = onRemoveExerciseDraft,
                    modifier = Modifier.testTag("workout_plan_exercise_menu"),
                    removeLabel = stringResource(R.string.action_delete),
                    buttonDescription = stringResource(R.string.cd_exercise_actions, exerciseName),
                    extraItems = { closeMenu ->
                        if (selectedExercise != null) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.editor_replace_with_similar)) },
                                leadingIcon = {
                                    Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                                },
                                onClick = {
                                    closeMenu()
                                    onOpenSmartAlternatives()
                                }
                            )
                        }
                    }
                )
            }
        ) {
            if (lastWeight != null) {
                val formattedLastWeight = remember(lastWeight, locale) {
                    NumberFormat.getNumberInstance(locale).apply {
                        minimumFractionDigits = 0
                        maximumFractionDigits = 2
                    }.format(lastWeight)
                }
                Text(
                    text = stringResource(R.string.editor_last_logged, formattedLastWeight),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        if (draft.exerciseId == null) {
            val selectExerciseLabel = stringResource(R.string.label_select_exercise)
            ExerciseCatalogSelector(
                selectedExerciseId = draft.exerciseId,
                exercises = exercises,
                frequentExerciseIds = frequentExerciseIds,
                exerciseWorkoutCounts = exerciseWorkoutCounts,
                exerciseMuscleIds = exerciseMuscleIds,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onExerciseSelected = onExerciseSelected,
                modifier = Modifier.fillMaxWidth(),
                trigger = { openPicker ->
                    WorkoutFooterButton(
                        label = selectExerciseLabel,
                        accessibilityLabel = selectExerciseLabel,
                        dashed = true,
                        enabled = true,
                        onClick = openPicker,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            )
        }

        if (recommendation != null) {
            SmartRecommendationPanel(
                recommendation = recommendation,
                onApplyWorkoutRecommendation = onApplyWorkoutRecommendation
            )
        }

        if (draft.sets.isNotEmpty()) {
            Column(modifier = Modifier.fillMaxWidth()) {
                draft.sets.forEachIndexed { setIndex, set ->
                    if (setIndex > 0) {
                        HorizontalDivider(
                            thickness = 1.dp,
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)
                        )
                    }
                    WorkoutSetDraftRow(
                        position = setIndex,
                        isFirst = setIndex == 0,
                        isLast = setIndex == draft.sets.lastIndex,
                        set = set,
                        exerciseName = exerciseName,
                        lastWeight = lastWeight,
                        allowedWeights = allowedWeights,
                        onWeightChanged = { onWeightChanged(setIndex, it) },
                        onRepsChanged = { onRepsChanged(setIndex, it) },
                        onApplyLastWeight = { onApplyLastWeightToSet(setIndex) },
                        onCopyPrevious = { onCopyPreviousSet(setIndex) },
                        onDuplicate = { onDuplicateSet(setIndex) },
                        onDelete = { onRemoveSet(setIndex) }
                    )
                }
            }
        }

        WorkoutFooterButton(
            label = stringResource(R.string.editor_add_set_short),
            accessibilityLabel = addSetDescription,
            dashed = true,
            enabled = true,
            onClick = onAddSet,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

/**
 * One planned set: the number badge, the shared `− 12 kg +` / `− 4 +` capsules with the trash
 * button (the editor is always open; the weight value is tappable for keyboard entry), and a row of
 * compact tonal quick-fill pills (Last, Prev., Copy) aligned under the capsules.
 */
@Composable
private fun WorkoutSetDraftRow(
    position: Int,
    isFirst: Boolean,
    isLast: Boolean,
    set: SetInputState,
    exerciseName: String,
    lastWeight: Double?,
    allowedWeights: List<Double>,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onApplyLastWeight: () -> Unit,
    onCopyPrevious: () -> Unit,
    onDuplicate: () -> Unit,
    onDelete: () -> Unit
) {
    val number = position + 1
    Column(
        modifier = Modifier
            .fillMaxWidth()
            // The card's 12dp rhythm already separates the first and last set from their neighbours.
            .padding(
                top = if (isFirst) 0.dp else PlainSetRowPadding,
                bottom = if (isLast) 0.dp else PlainSetRowPadding
            ),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SetNumberBadge(number)
            SetEditorCapsules(
                modifier = Modifier.weight(1f),
                number = number,
                weightInput = set.weight,
                repsInput = set.reps,
                allowedWeights = allowedWeights,
                enabled = true,
                onWeightChanged = onWeightChanged,
                onRepsChanged = onRepsChanged,
                deleteDescription = stringResource(R.string.cd_delete_set_named, number, exerciseName),
                onDelete = onDelete
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(start = SetNumberBadgeSize + 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val lastWeightLabel = stringResource(R.string.cd_chip_last_weight)
            val previousLabel = stringResource(R.string.cd_chip_previous)
            val copyLabel = stringResource(R.string.cd_chip_copy_set)
            SetQuickChip(
                text = stringResource(R.string.editor_chip_last_weight),
                description = lastWeightLabel,
                enabled = lastWeight != null,
                onClick = onApplyLastWeight
            )
            SetQuickChip(
                text = stringResource(R.string.editor_chip_previous),
                description = previousLabel,
                enabled = position > 0,
                onClick = onCopyPrevious
            )
            SetQuickChip(
                text = stringResource(R.string.editor_chip_copy),
                description = copyLabel,
                enabled = true,
                onClick = onDuplicate
            )
        }
    }
}

/** Compact tonal pill (36dp, fully rounded like the capsules, primary text on primary 12%) inside a 44dp tap target. */
@Composable
private fun SetQuickChip(
    text: String,
    description: String?,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val primary = MaterialTheme.colorScheme.primary
    Box(
        modifier = Modifier
            .heightIn(min = 44.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) {
                if (description != null) contentDescription = description
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .height(36.dp)
                .background(primary.copy(alpha = if (enabled) 0.12f else 0.06f), CircleShape)
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelLarge,
                color = if (enabled) primary else primary.copy(alpha = 0.38f),
                maxLines = 1,
                modifier = Modifier.clearAndSetSemantics {}
            )
        }
    }
}

@Composable
private fun SmartRecommendationPanel(
    recommendation: WorkoutRecommendation,
    onApplyWorkoutRecommendation: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 40.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = stringResource(
                R.string.smart_coach_status_compact,
                recommendation.kind.smartCoachLabel(),
                recommendation.targetRir.first,
                recommendation.targetRir.last
            ),
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.labelLarge,
            // Informational for every kind (Deload and Comeback are advice, not errors).
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        TextButton(
            onClick = onApplyWorkoutRecommendation,
            modifier = Modifier.height(40.dp),
            contentPadding = PaddingValues(horizontal = 8.dp)
        ) {
            Text(stringResource(R.string.action_apply_smart_plan))
        }
    }
}

@Composable
private fun WorkoutRecommendationKind.smartCoachLabel(): String {
    return when (this) {
        WorkoutRecommendationKind.NewExercise -> stringResource(R.string.smart_kind_new_exercise)
        WorkoutRecommendationKind.ProgressiveOverload -> stringResource(R.string.smart_kind_progressive_overload)
        WorkoutRecommendationKind.HoldAndBuild -> stringResource(R.string.smart_kind_hold_and_build)
        WorkoutRecommendationKind.Deload -> stringResource(R.string.smart_kind_deload)
        WorkoutRecommendationKind.Comeback -> stringResource(R.string.smart_kind_comeback)
        WorkoutRecommendationKind.PlateauBreak -> stringResource(R.string.smart_kind_plateau_break)
    }
}

@Composable
private fun SmartWorkoutAlternativePickerContent(
    currentExerciseName: String?,
    alternatives: List<SmartWorkoutAlternative>,
    exerciseMediaOwnerKey: String,
    onSelect: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(R.string.smart_alternatives_title),
                style = MaterialTheme.typography.headlineSmall
            )
            currentExerciseName?.let { name ->
                Text(
                    text = stringResource(
                        R.string.smart_alternatives_for,
                        localizedExerciseName(name)
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        items(
            items = alternatives,
            key = { it.exercise.id }
        ) { alternative ->
            SmartWorkoutAlternativeCard(
                alternative = alternative,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onSelect = { onSelect(alternative.exercise.id) }
            )
        }

        if (alternatives.isEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.smart_alternatives_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    }
}

@Composable
private fun SmartWorkoutAlternativeCard(
    alternative: SmartWorkoutAlternative,
    exerciseMediaOwnerKey: String,
    onSelect: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ExerciseMediaPreview(
                    exerciseId = alternative.exercise.id,
                    exerciseName = alternative.exercise.name,
                    ownerKey = exerciseMediaOwnerKey,
                    width = 76.dp,
                    height = 64.dp,
                    editable = false
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = localizedExerciseName(alternative.exercise.name),
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = stringResource(
                            R.string.smart_alternative_prescription,
                            alternative.recommendation.sets.size,
                            alternative.recommendation.sets.firstOrNull()?.reps ?: 0,
                            alternative.recommendation.targetRir.first,
                            alternative.recommendation.targetRir.last
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            val reasonLabels = mutableListOf<String>()
            alternative.reasons.take(3).forEach { reason ->
                reasonLabels += reason.smartCoachLabel()
            }
            Text(
                text = reasonLabels.joinToString(separator = " · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(onClick = onSelect, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.smart_alternative_select))
            }
        }
    }
}

@Composable
private fun SmartWorkoutAlternativeReason.smartCoachLabel(): String = when (this) {
    SmartWorkoutAlternativeReason.SameMovement -> stringResource(R.string.smart_alternative_same_movement)
    SmartWorkoutAlternativeReason.SameMuscles -> stringResource(R.string.smart_alternative_same_muscles)
    SmartWorkoutAlternativeReason.SimilarRole -> stringResource(R.string.smart_alternative_similar_role)
    SmartWorkoutAlternativeReason.SameEquipment -> stringResource(R.string.smart_alternative_same_equipment)
    SmartWorkoutAlternativeReason.Familiar -> stringResource(R.string.smart_alternative_familiar)
    SmartWorkoutAlternativeReason.Favorite -> stringResource(R.string.smart_alternative_favorite)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExerciseSelector(
    selectedExerciseId: Long?,
    exercises: List<ExerciseEntity>,
    frequentExerciseIds: List<Long>,
    exerciseWorkoutCounts: Map<Long, Int>,
    exerciseMuscleIds: Map<String, Set<String>>,
    onExerciseSelected: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var frequentOnly by rememberSaveable { mutableStateOf(false) }
    var bodyFilter by rememberSaveable { mutableStateOf(ExerciseBodyFilter.All) }
    var muscleFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by rememberSaveable { mutableStateOf(ExerciseSortMode.Name) }
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    val languageTag = currentAppLanguageTag()
    val selectedLabel = exercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.let { BuiltInExerciseCatalog.displayName(it.name, languageTag) }
        ?: stringResource(R.string.label_select_exercise)
    val visibleExercises = remember(
        exercises,
        frequentExerciseIds,
        exerciseWorkoutCounts,
        exerciseMuscleIds,
        query,
        frequentOnly,
        bodyFilter,
        muscleFilter,
        sortMode,
        favoritesOnly,
        languageTag
    ) {
        filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = exerciseWorkoutCounts,
            muscleIdsByExerciseName = exerciseMuscleIds,
            query = query,
            bodyFilter = bodyFilter,
            muscleFilter = muscleFilter,
            sortMode = sortMode,
            favoritesOnly = favoritesOnly,
            languageTag = languageTag
        ).filter { exercise -> !frequentOnly || exercise.id in frequentExerciseIds }
    }

    OutlinedButton(
        onClick = { expanded = true },
        modifier = modifier.fillMaxWidth()
    ) {
        Icon(imageVector = Icons.Default.Search, contentDescription = null)
        Text(
            text = selectedLabel,
            modifier = Modifier.padding(start = 8.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }

    if (expanded) {
        ModalBottomSheet(
            onDismissRequest = { expanded = false },
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_select_exercise),
                    style = MaterialTheme.typography.headlineSmall
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = !frequentOnly,
                        onClick = { frequentOnly = false },
                        label = { Text(stringResource(R.string.exercise_picker_all)) }
                    )
                    FilterChip(
                        selected = frequentOnly,
                        onClick = {
                            frequentOnly = true
                            sortMode = ExerciseSortMode.MostFrequent
                        },
                        label = { Text(stringResource(R.string.exercise_picker_frequent)) },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Star,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    )
                }
                ExerciseSearchAndFilters(
                    query = query,
                    onQueryChange = { query = it },
                    bodyFilter = bodyFilter,
                    onBodyFilterChange = { bodyFilter = it },
                    muscleFilter = muscleFilter,
                    onMuscleFilterChange = { muscleFilter = it },
                    sortMode = sortMode,
                    onSortModeChange = { sortMode = it },
                    favoritesOnly = favoritesOnly,
                    onFavoritesOnlyChange = { favoritesOnly = it },
                    resultCount = visibleExercises.size
                )
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f, fill = false)
                        .heightIn(max = 480.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (visibleExercises.isEmpty()) {
                        item {
                            Text(
                                text = if (frequentOnly && frequentExerciseIds.isEmpty()) {
                                    stringResource(R.string.exercise_picker_frequent_empty)
                                } else {
                                    stringResource(R.string.exercise_search_no_results)
                                },
                                modifier = Modifier.padding(vertical = 20.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(visibleExercises, key = { it.id }) { exercise ->
                            OutlinedButton(
                                onClick = {
                                    onExerciseSelected(exercise.id)
                                    expanded = false
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = BuiltInExerciseCatalog.displayName(
                                        exercise.name,
                                        languageTag
                                    ),
                                    modifier = Modifier.weight(1f),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                                if (exercise.id == selectedExerciseId) {
                                    Spacer(modifier = Modifier.size(8.dp))
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
