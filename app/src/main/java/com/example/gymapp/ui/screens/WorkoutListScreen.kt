package com.example.gymapp.ui.screens

/*
THESIS: Focus Lens puts today's workout in one fluid focal form and refuses the stacked-dashboard default.
OWN-WORLD: Airy canvas, aquatic contextual color, continuous curves, solid content rows, and one expressive Material control layer.
STORY: See the next useful action, understand its size and weekly rhythm, start it, then review recent work without changing modes.
FIRST VIEWPORT: A large asymmetric lens leads; core facts live inside it and the start action stays near thumb reach, followed by progressive analytics.
FORM: User-selected Focus Lens from Fluid Focus; seed af1a1dee. Android structure remains Material 3 with native back, insets, semantics, and motion.
*/

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.ui.draw.rotate
import com.example.gymapp.ui.components.GymAlertDialog
import com.example.gymapp.ui.components.GymAlertDialogButton
import com.example.gymapp.ui.components.GymAlertDialogButtonRole
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.ui.components.FitMetricValue
import com.example.gymapp.ui.components.TrainingSettingsSummaryRow
import com.example.gymapp.ui.components.TrainingSettingsSheet
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import com.example.gymapp.ui.viewmodel.tapAction
import com.example.gymapp.ui.viewmodel.TodayFriendTapAction
import com.example.gymapp.ui.viewmodel.TodayFriendEntryState
import com.example.gymapp.ui.viewmodel.TodayFriendChoice
import com.example.gymapp.ui.components.GymModalBottomSheet
import com.example.gymapp.ui.components.GymSearchField
import com.example.gymapp.ui.components.GymSheetCloseRow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.AccountCircle
import com.example.gymapp.ui.components.GymIcons
import com.example.gymapp.ui.components.Weightlifter
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import com.example.gymapp.ui.components.rememberReduceMotion
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import com.example.gymapp.R
import com.example.gymapp.ui.components.hairlineThickness
import com.example.gymapp.ui.components.groupedSeparatorColor
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.data.repository.FirstWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.WeeklyTrainingDecision
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.rememberGymTrackedSwipe
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.ActiveWorkoutDiscardDialog
import com.example.gymapp.ui.components.HeroTone
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.MuscleHeatmapCard
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.components.TutorialAnchorRegistry
import com.example.gymapp.ui.components.brandFillColor
import com.example.gymapp.ui.components.heroPrimaryButtonColors
import com.example.gymapp.ui.components.heroSecondaryBorder
import com.example.gymapp.ui.components.heroSecondaryOutlinedColors
import com.example.gymapp.ui.components.TutorialTarget
import com.example.gymapp.ui.components.tutorialAnchor
import com.example.gymapp.ui.theme.BrandFill
import com.example.gymapp.ui.theme.BrandFillNight
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.ActiveWorkoutFocus
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.MonthlyTrainingSummaryUiModel
import com.example.gymapp.ui.viewmodel.TrainingHistoryPeriod
import com.example.gymapp.ui.viewmodel.TrainingRecommendationUiModel
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import com.example.gymapp.ui.viewmodel.TodayPlanUiModel
import com.example.gymapp.ui.viewmodel.estimateWorkoutMinutes
import com.example.gymapp.ui.viewmodel.TodayHeroMetricsUiModel
import com.example.gymapp.ui.viewmodel.WeeklyTrainingSummaryUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.asString
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.format.TextStyle
import java.time.format.DateTimeFormatter
import java.util.Locale
import com.example.gymapp.util.formatVolumeTotal
import com.example.gymapp.ui.viewmodel.shouldShowRepeatLastWorkoutAction
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.formattedPluralStringResource
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import kotlinx.coroutines.FlowPreview
import com.example.gymapp.ui.theme.TintedButton
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import com.example.gymapp.ui.components.GroupedListDefaults
import com.example.gymapp.ui.components.GroupedRow
import com.example.gymapp.ui.components.GroupedSection

// Give the keyboard up to this long to open, and treat its height as final after it stops changing.
private const val HISTORY_SEARCH_IME_WAIT_MILLIS = 1_500L
private const val HISTORY_SEARCH_IME_SETTLE_MILLIS = 250L

@OptIn(FlowPreview::class)
@Composable
fun WorkoutListScreen(
    uiState: WorkoutListUiState,
    onSessionClick: (Long) -> Unit,
    onPreviousMonth: () -> Unit,
    onCurrentMonth: () -> Unit,
    onNextMonth: () -> Unit,
    onPreviousWeek: () -> Unit,
    onCurrentWeek: () -> Unit,
    onNextWeek: () -> Unit,
    onHistoryPeriodSelected: (TrainingHistoryPeriod) -> Unit,
    onMuscleMapPeriodSelected: (MuscleMapPeriod) -> Unit,
    onMuscleSelected: (String) -> Unit,
    onAddWorkout: () -> Unit,
    onStartPlan: (String) -> Unit,
    onOpenPlan: (String) -> Unit,
    onRepeatLastWorkout: () -> Unit = {},
    onStartFirstWorkout: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onEditFirstWorkout: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onSkipFirstWorkout: () -> Unit,
    hasRetainedWorkoutDraft: Boolean = false,
    retainedDraftSummary: RetainedDraftSummary? = null,
    activeWorkoutFocus: ActiveWorkoutFocus? = null,
    onDiscardActiveWorkout: () -> Unit = {},
    onCancelRetainedPlan: () -> Unit = {},
    onRetryLoad: () -> Unit = {},
    tutorialAnchors: TutorialAnchorRegistry? = null,
    trainingProfile: TrainingProfile = TrainingProfile(),
    onTrainingProfileChange: (TrainingProfile) -> Unit = {},
    friendEntryState: TodayFriendEntryState = TodayFriendEntryState.Hidden,
    friendChoices: List<TodayFriendChoice> = emptyList(),
    onFriendEntryAction: (TodayFriendTapAction) -> Unit = {},
    onTrainWithFriend: (TodayFriendChoice) -> Unit = {},
    modifier: Modifier = Modifier
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showFriendPicker by rememberSaveable { mutableStateOf(false) }
    val onFriendTap: (Boolean) -> Unit = { forcedVisible ->
        when (val action = friendEntryState.tapAction(forcedVisible)) {
            TodayFriendTapAction.PickFriend -> showFriendPicker = true
            else -> onFriendEntryAction(action)
        }
    }
    val friendPill: @Composable (Boolean) -> Unit = { forcedVisible ->
        TrainWithFriendPill(
            state = friendEntryState,
            forcedVisible = forcedVisible,
            onClick = { onFriendTap(forcedVisible) }
        )
    }
    if (showFriendPicker) {
        TrainWithFriendPicker(
            friends = friendChoices,
            onPick = { friend ->
                showFriendPicker = false
                onTrainWithFriend(friend)
            },
            onDismiss = { showFriendPicker = false }
        )
    }
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    var showActiveWorkoutDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    var showRetainedPlanCancelConfirmation by rememberSaveable { mutableStateOf(false) }
    val historyWorkouts = when (uiState.historyPeriod) {
        TrainingHistoryPeriod.Week -> uiState.weeklyTrainingSummary.workouts
        TrainingHistoryPeriod.Month -> uiState.monthlyTrainingSummary.workouts
    }
    val listState = rememberLazyListState()
    val listScope = rememberCoroutineScope()
    // Bring the history search field to the top of the list when it gains focus, once the keyboard has
    // finished opening, so the field and the first results stay above the keyboard (the list itself
    // is resized by imePadding()). Snaps instead of animating when animations are turned off.
    var listTopInRoot by remember { mutableFloatStateOf(0f) }
    val imeInsets = WindowInsets.ime
    val imeDensity = LocalDensity.current
    val reduceMotion = rememberReduceMotion()
    val revealHistorySearch: (() -> Float?) -> Unit = { fieldTopInRoot ->
        listScope.launch {
            withTimeoutOrNull(HISTORY_SEARCH_IME_WAIT_MILLIS) {
                snapshotFlow { imeInsets.getBottom(imeDensity) }
                    .distinctUntilChanged()
                    .debounce(HISTORY_SEARCH_IME_SETTLE_MILLIS)
                    .first { it > 0 }
            } ?: return@launch
            val fieldTop = fieldTopInRoot() ?: return@launch
            val delta = fieldTop - listTopInRoot - with(imeDensity) { GymSpacing.Small.toPx() }
            if (kotlin.math.abs(delta) < 1f) return@launch
            if (reduceMotion) listState.scrollBy(delta) else listState.animateScrollBy(delta)
        }
    }
    val showsFirstWorkoutActivation =
        uiState.showFirstWorkoutActivation && activeWorkoutFocus == null
    val zoneId = remember { java.time.ZoneId.systemDefault() }
    val todaysCompletedWorkout = remember(uiState.pastWorkouts, uiState.hasCompletedWorkoutToday) {
        if (uiState.hasCompletedWorkoutToday) {
            todaysLatestWorkout(uiState.pastWorkouts, System.currentTimeMillis(), zoneId)
        } else {
            null
        }
    }

    if (uiState.isLoading) {
        Box(
            modifier = modifier.fillMaxSize().padding(horizontal = screenHorizontalPadding),
            contentAlignment = Alignment.Center
        ) {
            LoadingStatePanel(label = stringResource(R.string.workouts_loading))
        }
        return
    }
    uiState.loadError?.let { error ->
        Box(
            modifier = modifier.fillMaxSize().padding(horizontal = screenHorizontalPadding),
            contentAlignment = Alignment.Center
        ) {
            EmptyStatePanel(
                title = error.asString(),
                actionLabel = stringResource(R.string.action_retry),
                onAction = onRetryLoad
            )
        }
        return
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .imePadding()
            .onGloballyPositioned { listTopInRoot = it.positionInRoot().y },
        state = listState,
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.Small,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
    ) {
            item {
                ScreenHeader(title = stringResource(R.string.today_title))
            }
            if (showsFirstWorkoutActivation) {
                item {
                    FirstWorkoutActivationCard(
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                        onContinuePlan = onAddWorkout,
                        onCancelPlan = { showRetainedPlanCancelConfirmation = true },
                        onStart = onStartFirstWorkout,
                        onEdit = onEditFirstWorkout,
                        onCreateManually = onSkipFirstWorkout,
                        tutorialAnchors = tutorialAnchors,
                        trainingProfile = trainingProfile,
                        onTrainingProfileChange = onTrainingProfileChange,
                        friendPill = { friendPill(false) }
                    )
                }
                if (!hasRetainedWorkoutDraft) {
                    item {
                        Text(
                            text = stringResource(R.string.today_empty_state_hint),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
                        )
                    }
                }
            } else {
                item {
                    FocusLens(
                        todayPlan = uiState.todayPlan,
                        hasCompletedWorkoutToday = uiState.hasCompletedWorkoutToday,
                        todayHeroMetrics = uiState.todayHeroMetrics,
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                        retainedDraftSummary = retainedDraftSummary,
                        activeWorkoutFocus = activeWorkoutFocus,
                        onStartWorkout = onAddWorkout,
                        onStartPlan = onStartPlan,
                        onOpenPlan = onOpenPlan,
                        hasRepeatableWorkout = uiState.hasRepeatableWorkout,
                        onRepeatLastWorkout = onRepeatLastWorkout,
                        onDiscardWorkout = {
                            showActiveWorkoutDiscardConfirmation = true
                        },
                        onCancelRetainedPlan = {
                            showRetainedPlanCancelConfirmation = true
                        },
                        tutorialAnchors = tutorialAnchors,
                        friendEntryState = friendEntryState,
                        onFriendClick = { forced -> onFriendTap(forced) },
                        completedWorkout = todaysCompletedWorkout,
                        completedWorkoutExerciseNames = todaysCompletedWorkout
                            ?.let { uiState.sessionExerciseNames[it.session.id] }
                            .orEmpty(),
                        onOpenCompletedWorkout = onSessionClick
                    )
                }
            }

            if (uiState.hasAnyWorkout) {
                item {
                    TrainingHistoryPanel(
                        period = uiState.historyPeriod,
                        weeklySummary = uiState.weeklyTrainingSummary,
                        monthlySummary = uiState.monthlyTrainingSummary,
                        weekOffset = uiState.weekOffset,
                        monthOffset = uiState.monthOffset,
                        monthLabel = uiState.monthLabel,
                        onPeriodSelected = onHistoryPeriodSelected,
                        onPreviousWeek = onPreviousWeek,
                        onCurrentWeek = onCurrentWeek,
                        onNextWeek = onNextWeek,
                        onPreviousMonth = onPreviousMonth,
                        onCurrentMonth = onCurrentMonth,
                        onNextMonth = onNextMonth,
                        workouts = historyWorkouts,
                        pastWorkouts = uiState.pastWorkouts,
                        sessionExerciseNames = uiState.sessionExerciseNames,
                        recentWorkouts = uiState.pastWorkouts,
                        onSessionClick = onSessionClick,
                        onSearchFocused = revealHistorySearch
                    )
                }
            }
    }

    if (showActiveWorkoutDiscardConfirmation) {
        ActiveWorkoutDiscardDialog(
            onConfirm = {
                showActiveWorkoutDiscardConfirmation = false
                onDiscardActiveWorkout()
            },
            onDismiss = { showActiveWorkoutDiscardConfirmation = false }
        )
    }
    if (showRetainedPlanCancelConfirmation) {
        GymAlertDialog(
            onDismissRequest = { showRetainedPlanCancelConfirmation = false },
            title = stringResource(R.string.today_cancel_plan_title),
            text = { Text(stringResource(R.string.today_cancel_plan_message)) },
            confirmButton = {
                GymAlertDialogButton(
                    onClick = {
                        showRetainedPlanCancelConfirmation = false
                        onCancelRetainedPlan()
                    },
                    role = GymAlertDialogButtonRole.Destructive
                ) {
                    Text(stringResource(R.string.today_cancel_plan_confirm))
                }
            },
            dismissButton = {
                GymAlertDialogButton(
                    onClick = { showRetainedPlanCancelConfirmation = false },
                    role = GymAlertDialogButtonRole.Cancel
                ) {
                    Text(stringResource(R.string.today_cancel_plan_keep))
                }
            }
        )
    }
}

@Composable
private fun WorkoutSectionSwitcher(
    sessionCount: Int,
    workoutsSelected: Boolean,
    onOverviewClick: () -> Unit,
    onWorkoutListClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    GymSegmentedControl(
        items = listOf(
            GymSegmentItem(
                value = false,
                label = stringResource(R.string.workout_switch_overview_title)
            ),
            GymSegmentItem(
                value = true,
                label = formattedStringResource(R.string.workout_switch_list_title, sessionCount)
            )
        ),
        selected = workoutsSelected,
        onSelected = { selected ->
            if (selected) onWorkoutListClick() else onOverviewClick()
        },
        modifier = modifier
    )
}

/** Coach recommendations as grouped rows: title, reason underneath and the focus on the right. */
@Composable
internal fun RecommendationsCard(
    recommendations: List<TrainingRecommendationUiModel>,
    modifier: Modifier = Modifier
) {
    if (recommendations.isEmpty()) return
    GroupedSection(
        modifier = modifier,
        header = stringResource(R.string.recommendations_title)
    ) {
        recommendations.forEach { recommendation ->
            row {
                GroupedRow(
                    title = recommendation.title,
                    subtitle = recommendation.supporting,
                    value = recommendation.priorityLabel
                )
            }
        }
    }
}

@Composable
private fun WorkoutSectionHeader(
    sessionCount: Int,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = stringResource(R.string.workout_section_header_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = if (sessionCount == 0) {
                        stringResource(R.string.workout_section_header_empty)
                    } else {
                        stringResource(R.string.workout_section_header_hint)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            InfoPill(
                text = formattedPluralStringResource(R.plurals.progress_sessions_count, sessionCount, sessionCount)
            )
        }
    }
}

/** Size of the saved plan draft, shown on the Today card in place of the recommendation's size. */
data class RetainedDraftSummary(
    val exerciseCount: Int,
    val setCount: Int,
    val estimatedDurationMinutes: Int
)

/** Counts only cards with a chosen exercise; null when the draft holds no exercise yet. */
internal fun retainedDraftSummary(drafts: List<ExerciseInputState>): RetainedDraftSummary? {
    val selected = drafts.filter { it.exerciseId != null }
    if (selected.isEmpty()) return null
    val setCount = selected.sumOf { it.sets.size }
    return RetainedDraftSummary(
        exerciseCount = selected.size,
        setCount = setCount,
        estimatedDurationMinutes = estimateWorkoutMinutes(selected.size, setCount)
    )
}

/** Today's finished workout in one line: "<first exercise> · 35 min · 460 kg". */
internal fun completedWorkoutSummaryParts(
    session: WorkoutSessionSummary,
    exerciseNames: List<String>
): Triple<String?, Int, Double> {
    val name = exerciseNames.firstOrNull { it.isNotBlank() }
    val minutes = estimateWorkoutMinutes(
        exerciseCount = session.exerciseCount,
        setCount = session.setCount,
        measuredDurationSeconds = session.session.durationSeconds,
        note = session.session.note
    )
    return Triple(name, minutes, session.totalVolume)
}

/** The newest saved workout that falls on the current local day, if any. */
internal fun todaysLatestWorkout(
    pastWorkouts: List<WorkoutSessionSummary>,
    nowMillis: Long,
    zoneId: java.time.ZoneId
): WorkoutSessionSummary? {
    val today = java.time.Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
    return pastWorkouts
        .filter {
            runCatching {
                java.time.Instant.ofEpochMilli(it.session.date).atZone(zoneId).toLocalDate() == today
            }.getOrDefault(false)
        }
        .maxByOrNull { it.session.date }
}

/** Accent leading glyph of an action row: 22dp icon centred in the 30dp icon column. */
@Composable
private fun ActionRowIcon(imageVector: androidx.compose.ui.graphics.vector.ImageVector, tint: Color) {
    Box(Modifier.size(GroupedListDefaults.IconTile), contentAlignment = Alignment.Center) {
        Icon(imageVector = imageVector, contentDescription = null, modifier = Modifier.size(22.dp), tint = tint)
    }
}

@Composable
private fun FocusLens(
    todayPlan: TodayPlanUiModel?,
    hasCompletedWorkoutToday: Boolean,
    todayHeroMetrics: TodayHeroMetricsUiModel,
    hasRetainedWorkoutDraft: Boolean,
    retainedDraftSummary: RetainedDraftSummary?,
    activeWorkoutFocus: ActiveWorkoutFocus?,
    onStartWorkout: () -> Unit,
    onStartPlan: (String) -> Unit,
    onOpenPlan: (String) -> Unit,
    hasRepeatableWorkout: Boolean,
    onRepeatLastWorkout: () -> Unit,
    onDiscardWorkout: () -> Unit,
    onCancelRetainedPlan: () -> Unit,
    tutorialAnchors: TutorialAnchorRegistry?,
    friendEntryState: TodayFriendEntryState,
    onFriendClick: (Boolean) -> Unit,
    completedWorkout: WorkoutSessionSummary?,
    completedWorkoutExerciseNames: List<String>,
    onOpenCompletedWorkout: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var showPlanDetails by rememberSaveable { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    val expandedState = stringResource(R.string.state_expanded)
    val collapsedState = stringResource(R.string.state_collapsed)
    val hasActiveWorkout = activeWorkoutFocus != null
    val shouldContinueRetainedPlan = shouldShowRetainedWorkoutDraftAction(
        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
        hasActiveWorkout = hasActiveWorkout
    )
    val hasCompletedToday = hasCompletedWorkoutToday && !hasActiveWorkout
    val lensShape = remember { RoundedCornerShape(28.dp) }
    val isRestOrRecovery = todayPlan != null && todayPlan.rhythm.decision in setOf(
        WeeklyTrainingDecision.Rest,
        WeeklyTrainingDecision.Recovery
    )
    val showRepeat = shouldShowRepeatLastWorkoutAction(
        hasRepeatableWorkout = hasRepeatableWorkout,
        hasActiveWorkout = hasActiveWorkout,
        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft
    )
    val completedIsPrimary = hasCompletedToday && !shouldContinueRetainedPlan
    // After a workout the primary is "Repeat last"; without anything to repeat it is "Add another".
    val repeatIsPrimary = completedIsPrimary && showRepeat
    val accent = MaterialTheme.colorScheme.primary

    val focusModifier = if (tutorialAnchors == null) {
        modifier
    } else {
        modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayFocus)
    }
    fun Modifier.primaryTutorialAnchor(): Modifier = if (tutorialAnchors == null) {
        this
    } else {
        tutorialAnchor(tutorialAnchors, TutorialTarget.TodayPrimaryAction)
    }

    Column(
        modifier = focusModifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(lensShape)
                .background(HeroTone.surface)
                .padding(if (hasCompletedToday) 18.dp else 22.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Header: title + one supporting line. Tapping it opens the plan details; a running
            // workout adds a "..." menu holding the destructive action.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .then(
                            if (hasCompletedToday || hasActiveWorkout) {
                                Modifier
                            } else {
                                Modifier
                                    .clickable(role = Role.Button) { showPlanDetails = !showPlanDetails }
                                    .semantics {
                                        stateDescription =
                                            if (showPlanDetails) expandedState else collapsedState
                                    }
                            }
                        ),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = when {
                            activeWorkoutFocus != null -> activeWorkoutFocus.exerciseName
                                ?.let { localizedExerciseName(it) }
                                ?: stringResource(R.string.today_focus_next_exercise)
                            hasCompletedToday -> stringResource(R.string.today_workout_completed)
                            todayPlan?.rhythm?.decision == WeeklyTrainingDecision.Rest ->
                                stringResource(R.string.today_rest)
                            todayPlan?.rhythm?.decision == WeeklyTrainingDecision.Recovery ->
                                stringResource(R.string.smart_effort_recovery)
                            todayPlan != null -> stringResource(todayPlan.focus.labelResource())
                            shouldContinueRetainedPlan -> stringResource(R.string.title_workout_plan)
                            else -> stringResource(R.string.action_start_workout)
                        },
                        style = if (hasCompletedToday || hasActiveWorkout) {
                            MaterialTheme.typography.headlineMedium
                        } else {
                            MaterialTheme.typography.headlineLarge
                        },
                        color = HeroTone.title,
                        fontWeight = FontWeight.Bold
                    )
                    if (activeWorkoutFocus != null) {
                        Text(
                            text = formattedStringResource(
                                R.string.today_focus_set_progress,
                                activeWorkoutFocus.currentSetNumber,
                                activeWorkoutFocus.completedSets,
                                activeWorkoutFocus.totalSets
                            ),
                            style = MaterialTheme.typography.bodyLarge,
                            color = HeroTone.supporting
                        )
                    } else if (hasCompletedToday) {
                        // The saved workout is the summary row below; no filler sentence.
                    } else if (isRestOrRecovery && todayPlan != null) {
                        Text(
                            text = if (todayPlan.rhythm.decision == WeeklyTrainingDecision.Rest) {
                                formattedStringResource(
                                    R.string.today_recovery_reason_target,
                                    todayPlan.rhythm.completedTrainingDays,
                                    todayPlan.rhythm.targetTrainingDays
                                )
                            } else {
                                stringResource(todayPlan.effortAdjustment.recoveryReasonResource())
                            },
                            style = MaterialTheme.typography.bodyLarge,
                            color = HeroTone.supporting
                        )
                        todayPlan.rhythm.nextRecommendedDayMillis?.let { nextDay ->
                            val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
                            Text(
                                text = formattedStringResource(
                                    R.string.today_next_recommended_day,
                                    DateTimeUtils.formatLongDate(nextDay, locale)
                                ),
                                style = MaterialTheme.typography.titleMedium,
                                color = HeroTone.title,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    } else if (todayPlan != null) {
                        // With a saved plan the card shows that plan's current size, not the recommendation's.
                        val summary = retainedDraftSummary.takeIf { shouldContinueRetainedPlan }
                        val shownExerciseCount = summary?.exerciseCount ?: todayPlan.exerciseCount
                        val shownSetCount = summary?.setCount ?: todayPlan.setCount
                        val shownMinutes = summary?.estimatedDurationMinutes ?: todayPlan.estimatedDurationMinutes
                        if (!shouldContinueRetainedPlan || summary != null) {
                            Text(
                                text = formattedStringResource(
                                    R.string.today_plan_summary,
                                    formattedPluralStringResource(
                                        R.plurals.saved_workout_exercise_count,
                                        shownExerciseCount,
                                        shownExerciseCount
                                    ),
                                    formattedPluralStringResource(
                                        R.plurals.saved_workout_set_count,
                                        shownSetCount,
                                        shownSetCount
                                    ),
                                    shownMinutes
                                ),
                                style = MaterialTheme.typography.bodyLarge,
                                color = HeroTone.supporting
                            )
                        }
                    }
                }
                if (hasActiveWorkout) {
                    Box {
                        IconButton(onClick = { showMenu = true }, modifier = Modifier.size(44.dp)) {
                            Icon(
                                imageVector = Icons.Default.MoreHoriz,
                                contentDescription = stringResource(R.string.active_workout_more_options),
                                tint = HeroTone.actionLabel
                            )
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        stringResource(R.string.active_workout_discard_action),
                                        color = MaterialTheme.colorScheme.error
                                    )
                                },
                                onClick = {
                                    showMenu = false
                                    onDiscardWorkout()
                                }
                            )
                        }
                    }
                }
                if (!hasCompletedToday && !hasActiveWorkout) {
                    Icon(
                        imageVector = if (showPlanDetails) Icons.Default.ExpandLess
                        else Icons.Default.ExpandMore,
                        contentDescription = stringResource(R.string.focus_lens_details),
                        tint = HeroTone.supporting,
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .clickable(role = Role.Button) { showPlanDetails = !showPlanDetails }
                            .padding(6.dp)
                    )
                }
            }

            if (hasActiveWorkout) {
                // Running workout, as on iPhone: "Plan details" is its own disclosure row inside the
                // card, with a small grey chevron that turns down while the details are open.
                val chevronTurn by animateFloatAsState(
                    targetValue = if (showPlanDetails) 90f else 0f,
                    animationSpec = spring(dampingRatio = 1f, stiffness = 440f),
                    label = "planDetailsChevron"
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clickable(role = Role.Button) { showPlanDetails = !showPlanDetails }
                        .semantics {
                            stateDescription = if (showPlanDetails) expandedState else collapsedState
                        },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(R.string.focus_lens_details),
                        style = MaterialTheme.typography.bodyLarge,
                        color = HeroTone.title,
                        modifier = Modifier.weight(1f)
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = HeroTone.supporting,
                        modifier = Modifier
                            .size(20.dp)
                            .rotate(chevronTurn)
                    )
                }
            }

            if (!hasCompletedToday && showPlanDetails) {
                TodayHeroMetricsRow(metrics = todayHeroMetrics)
                if (!hasActiveWorkout) {
                    TextButton(
                        onClick = onStartWorkout,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    ) {
                        Text(
                            stringResource(R.string.activation_build_manually),
                            color = HeroTone.actionLabel
                        )
                    }
                }
            }

            // The one primary action.
            val launchToken = todayPlan?.recommendedLaunchToken
            val anywayToken = todayPlan?.trainAnywayLaunchToken ?: todayPlan?.recommendedLaunchToken
            val primaryLabel: String
            val primaryClick: () -> Unit
            when {
                hasActiveWorkout -> {
                    primaryLabel = stringResource(R.string.action_continue_workout)
                    primaryClick = onStartWorkout
                }
                shouldContinueRetainedPlan -> {
                    primaryLabel = stringResource(R.string.today_continue_plan)
                    primaryClick = onStartWorkout
                }
                repeatIsPrimary -> {
                    primaryLabel = stringResource(R.string.repeat_last_workout_action)
                    primaryClick = onRepeatLastWorkout
                }
                hasCompletedToday -> {
                    primaryLabel = stringResource(R.string.today_add_another_workout)
                    primaryClick = onStartWorkout
                }
                isRestOrRecovery -> {
                    primaryLabel = stringResource(R.string.today_train_anyway)
                    primaryClick = { if (anywayToken != null) onStartPlan(anywayToken) else onStartWorkout() }
                }
                else -> {
                    primaryLabel = stringResource(
                        if (launchToken == null) R.string.action_start_workout else R.string.today_start_plan
                    )
                    primaryClick = { if (launchToken != null) onStartPlan(launchToken) else onStartWorkout() }
                }
            }
            Button(
                onClick = primaryClick,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .primaryTutorialAnchor(),
                shape = RoundedCornerShape(50),
                colors = heroPrimaryButtonColors()
            ) {
                if (hasActiveWorkout) {
                    Icon(
                        imageVector = Icons.Default.PlayArrow,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(
                    text = primaryLabel,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontWeight = FontWeight.Bold
                )
            }

            // Running workout, as on iPhone: "With a friend" sits inside the card under the action.
            if (hasActiveWorkout) {
                TrainWithFriendRow(
                    state = friendEntryState,
                    forcedVisible = true,
                    inHero = true,
                    onClick = { onFriendClick(true) }
                )
            }
        }

        // Secondary actions: rows in one grouped section, accent text, chevron where it navigates.
        val editToken = when {
            hasActiveWorkout || shouldContinueRetainedPlan || hasCompletedToday -> null
            isRestOrRecovery -> anywayTokenOf(todayPlan)
            else -> todayPlan?.recommendedLaunchToken
        }
        val friendVisible = friendEntryState != TodayFriendEntryState.Hidden && !hasActiveWorkout
        val showSummaryRow = hasCompletedToday && completedWorkout != null
        val showAddAnotherRow = hasCompletedToday && !shouldContinueRetainedPlan && repeatIsPrimary
        val showRepeatRow = showRepeat && !hasCompletedToday
        val addAnotherLabel = stringResource(R.string.today_add_another_workout)
        val repeatLabel = stringResource(R.string.repeat_last_workout_action)
        val editLabel = stringResource(R.string.today_edit_plan)
        val cancelPlanLabel = stringResource(R.string.today_cancel_plan)
        val errorColor = MaterialTheme.colorScheme.error
        if (showSummaryRow || showAddAnotherRow || showRepeatRow || editToken != null ||
            shouldContinueRetainedPlan || friendVisible
        ) {
            GroupedSection(separatorInset = 58.dp) {
                if (showSummaryRow && completedWorkout != null) {
                    row {
                        val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
                        val (name, minutes, volume) =
                            completedWorkoutSummaryParts(completedWorkout, completedWorkoutExerciseNames)
                        val title = formattedStringResource(
                            R.string.today_completed_summary,
                            name?.let { localizedExerciseName(it) }
                                ?: stringResource(R.string.today_workout_completed),
                            workoutDurationText(minutes * 60L, locale).replace(' ', '\u00A0'),
                            formattedStringResource(
                                R.string.today_history_volume_kg,
                                formatTodayHeroVolume(volume, locale)
                            ).replace(' ', '\u00A0')
                        )
                        GroupedRow(
                            title = title,
                            icon = { ActionRowIcon(Icons.Default.FitnessCenter, MaterialTheme.colorScheme.onSurfaceVariant) },
                            chevron = true,
                            onClick = { onOpenCompletedWorkout(completedWorkout.session.id) }
                        )
                    }
                }
                if (showAddAnotherRow) {
                    row(
                        title = addAnotherLabel,
                        icon = { ActionRowIcon(Icons.Default.Add, accent) },
                        titleColor = accent,
                        onClick = onStartWorkout
                    )
                }
                if (showRepeatRow) {
                    row(
                        title = repeatLabel,
                        icon = { ActionRowIcon(Icons.Default.Refresh, accent) },
                        titleColor = accent,
                        onClick = onRepeatLastWorkout
                    )
                }
                if (editToken != null) {
                    row(
                        title = editLabel,
                        icon = { ActionRowIcon(Icons.Default.Edit, accent) },
                        titleColor = accent,
                        chevron = true,
                        onClick = { onOpenPlan(editToken) }
                    )
                }
                if (shouldContinueRetainedPlan) {
                    row(
                        title = cancelPlanLabel,
                        icon = { ActionRowIcon(Icons.Default.Close, errorColor) },
                        titleColor = errorColor,
                        onClick = onCancelRetainedPlan
                    )
                }
                if (friendVisible) {
                    row {
                        TrainWithFriendRow(
                            state = friendEntryState,
                            forcedVisible = hasActiveWorkout,
                            onClick = { onFriendClick(hasActiveWorkout) }
                        )
                    }
                }
            }
        }
    }
}

private fun anywayTokenOf(plan: TodayPlanUiModel?): String? =
    plan?.trainAnywayLaunchToken ?: plan?.recommendedLaunchToken

internal fun shouldShowRetainedWorkoutDraftAction(
    hasRetainedWorkoutDraft: Boolean,
    hasActiveWorkout: Boolean
): Boolean = hasRetainedWorkoutDraft && !hasActiveWorkout

@Composable
private fun TrainingHistoryPanel(
    period: TrainingHistoryPeriod,
    weeklySummary: WeeklyTrainingSummaryUiModel,
    monthlySummary: MonthlyTrainingSummaryUiModel,
    weekOffset: Int,
    monthOffset: Int,
    monthLabel: String,
    onPeriodSelected: (TrainingHistoryPeriod) -> Unit,
    onPreviousWeek: () -> Unit,
    onCurrentWeek: () -> Unit,
    onNextWeek: () -> Unit,
    onPreviousMonth: () -> Unit,
    onCurrentMonth: () -> Unit,
    onNextMonth: () -> Unit,
    workouts: List<WorkoutSessionSummary>,
    pastWorkouts: List<WorkoutSessionSummary>,
    sessionExerciseNames: Map<Long, List<String>>,
    recentWorkouts: List<WorkoutSessionSummary>,
    onSessionClick: (Long) -> Unit,
    onSearchFocused: (fieldTopInRoot: () -> Float?) -> Unit,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    // One entry point to the full history: collapsed Today shows this week, the three latest
    // workouts and an "All history" row; expanding it reveals period switch, navigation, month view,
    // search and the whole list. Collapsing returns to the current week.
    var expanded by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(expanded) {
        if (!expanded) {
            if (period == TrainingHistoryPeriod.Month) onPeriodSelected(TrainingHistoryPeriod.Week)
            if (weekOffset != 0) onCurrentWeek()
            if (monthOffset != 0) onCurrentMonth()
        }
    }
    var searchFieldCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var searchFieldFocused by remember { mutableStateOf(false) }
    // Survives rotation / process recreation of the screen, never persisted across app restarts.
    var searchQuery by rememberSaveable { mutableStateOf("") }
    val isSearching = searchQuery.isNotBlank()
    // Search runs on every past workout (before the week/month grouping); the period header and its
    // totals above stay computed from the unfiltered period data.
    val searchResults = remember(isSearching, searchQuery, pastWorkouts, sessionExerciseNames) {
        if (isSearching) {
            filterWorkoutsByExerciseQuery(pastWorkouts, searchQuery) { workout ->
                sessionExerciseNames[workout.session.id].orEmpty()
            }.take(HISTORY_SEARCH_DISPLAY_LIMIT)
        } else {
            emptyList()
        }
    }
    val visibleWorkouts = if (isSearching) searchResults else workouts
    // On focus, and again when the first characters bring in results (the list could not scroll
    // that far while it was still short): keep the field at the top with the results under it.
    LaunchedEffect(searchFieldFocused, isSearching) {
        if (searchFieldFocused) {
            onSearchFocused {
                searchFieldCoordinates?.takeIf { it.isAttached }?.positionInRoot()?.y
            }
        }
    }
    val focusManager = LocalFocusManager.current
    val rangeFormatter = remember(locale) {
        // English reads month-day ("Oct 5"), matching formatShortDate, iOS and the PWA.
        val pattern = if (locale.language.equals("en", ignoreCase = true)) "MMM d" else "d MMM"
        DateTimeFormatter.ofPattern(pattern, locale)
    }
    val weekRange = remember(weeklySummary.days, rangeFormatter) {
        val first = weeklySummary.days.firstOrNull()?.date
        val last = weeklySummary.days.lastOrNull()?.date
        if (first == null || last == null) "" else {
            "${first.format(rangeFormatter)} – ${last.format(rangeFormatter)}"
        }
    }
    val completedWorkoutCountValue = when (period) {
        TrainingHistoryPeriod.Week -> weeklySummary.completedWorkoutCount
        TrainingHistoryPeriod.Month -> monthlySummary.completedWorkoutCount
    }
    val estimatedMinutes = when (period) {
        TrainingHistoryPeriod.Week -> weeklySummary.estimatedMinutes
        TrainingHistoryPeriod.Month -> monthlySummary.estimatedMinutes
    }
    val totalVolume = when (period) {
        TrainingHistoryPeriod.Week -> weeklySummary.totalVolume
        TrainingHistoryPeriod.Month -> monthlySummary.totalVolume
    }
    val volume = remember(totalVolume, locale) {
        formatTodayHeroVolume(totalVolume, locale)
    }
    val completedWorkoutCount = remember(completedWorkoutCountValue, locale) {
        formatTodayHeroCount(completedWorkoutCountValue, locale)
    }
    // Week and month navigation follow the finger (rubber-banded at the current period); the chevrons stay.
    val isWeekPeriod = period == TrainingHistoryPeriod.Week
    val swipe = rememberGymTrackedSwipe(
        canPrevious = true,
        canNext = if (isWeekPeriod) weekOffset < 0 else monthOffset < 0,
        onPrevious = if (isWeekPeriod) onPreviousWeek else onPreviousMonth,
        onNext = if (isWeekPeriod) onNextWeek else onNextMonth,
        key = period
    )
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .then(swipe.gesture)
    ) {
        Column(
            modifier = Modifier
                .graphicsLayer { translationX = swipe.offset }
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            val weeklyGoalSpoken = formattedStringResource(
                R.string.today_weekly_goal_spoken,
                weeklySummary.completedTrainingDays,
                weeklySummary.targetTrainingDays
            )
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = stringResource(R.string.training_history_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                // The weekly goal is plain subtitle text, not a chip.
                val isWeek = period == TrainingHistoryPeriod.Week
                Text(
                    text = if (isWeek) {
                        formattedStringResource(
                            R.string.today_weekly_goal,
                            weeklySummary.completedTrainingDays,
                            weeklySummary.targetTrainingDays
                        )
                    } else {
                        formattedPluralStringResource(
                            R.plurals.training_history_active_days,
                            monthlySummary.completedTrainingDays,
                            monthlySummary.completedTrainingDays
                        )
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = if (isWeek) {
                        Modifier.clearAndSetSemantics { contentDescription = weeklyGoalSpoken }
                    } else {
                        Modifier
                    }
                )
            }
            if (expanded) {
                GymSegmentedControl(
                    items = listOf(
                        GymSegmentItem(
                            TrainingHistoryPeriod.Week,
                            stringResource(R.string.training_history_week)
                        ),
                        GymSegmentItem(
                            TrainingHistoryPeriod.Month,
                            stringResource(R.string.training_history_month)
                        )
                    ),
                    selected = period,
                    onSelected = onPeriodSelected
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    IconButton(
                        onClick = if (period == TrainingHistoryPeriod.Week) {
                            onPreviousWeek
                        } else {
                            onPreviousMonth
                        },
                        modifier = Modifier.size(48.dp)
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.NavigateBefore,
                            contentDescription = stringResource(
                                if (period == TrainingHistoryPeriod.Week) {
                                    R.string.cd_previous_week
                                } else {
                                    R.string.cd_prev_month
                                }
                            )
                        )
                    }
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .clickable(
                                enabled = if (period == TrainingHistoryPeriod.Week) {
                                    weekOffset != 0
                                } else {
                                    monthOffset != 0
                                },
                                onClick = if (period == TrainingHistoryPeriod.Week) {
                                    onCurrentWeek
                                } else {
                                    onCurrentMonth
                                }
                            )
                            .padding(horizontal = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            text = if (period == TrainingHistoryPeriod.Week) weekRange else monthLabel,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                            maxLines = 1
                        )
                        Text(
                            text = stringResource(
                                if (period == TrainingHistoryPeriod.Week && weekOffset == 0) {
                                    R.string.weekly_training_summary_title
                                } else if (period == TrainingHistoryPeriod.Month && monthOffset == 0) {
                                    R.string.action_current_month
                                } else if (period == TrainingHistoryPeriod.Week) {
                                    R.string.action_return_to_current_week
                                } else {
                                    R.string.action_return_to_current_month
                                }
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            maxLines = 2
                        )
                    }
                    IconButton(
                        onClick = if (period == TrainingHistoryPeriod.Week) {
                            onNextWeek
                        } else {
                            onNextMonth
                        },
                        enabled = if (period == TrainingHistoryPeriod.Week) {
                            weekOffset != 0
                        } else {
                            monthOffset != 0
                        },
                        modifier = Modifier.size(48.dp)
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                            contentDescription = stringResource(
                                if (period == TrainingHistoryPeriod.Week) {
                                    R.string.cd_next_week
                                } else {
                                    R.string.cd_next_month
                                }
                            )
                        )
                    }
                }
            }
            if (period == TrainingHistoryPeriod.Week) {
                TrainingHistoryWeekStrip(summary = weeklySummary, locale = locale)
            } else {
                TrainingHistoryMonthGrid(summary = monthlySummary, locale = locale)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    WeeklyTrainingMetric(
                        value = completedWorkoutCount,
                        label = pluralStringResource(
                            R.plurals.today_stat_workouts_label,
                            completedWorkoutCountValue.coerceAtLeast(0)
                        ),
                        modifier = Modifier.weight(1f)
                    )
                    WeeklyTrainingMetric(
                        value = formattedStringResource(
                            R.string.weekly_training_minutes_value,
                            estimatedMinutes
                        ),
                        label = pluralStringResource(
                            R.plurals.today_stat_minutes_label,
                            estimatedMinutes.coerceAtLeast(0)
                        ),
                        modifier = Modifier.weight(1f)
                    )
                    WeeklyTrainingMetric(
                        value = formattedStringResource(R.string.today_history_volume_kg, volume),
                        label = stringResource(R.string.today_stat_volume_label),
                        modifier = Modifier.weight(1f)
                    )
                }
                val volumeDeltaPercent = weeklySummary.volumeDeltaPercent
                if (isWeekPeriod && volumeDeltaPercent != null) {
                    Text(
                        text = formatWeekVolumeDelta(volumeDeltaPercent, locale) + " " +
                            stringResource(
                                if (weekOffset == 0) {
                                    R.string.training_week_delta_same_days
                                } else {
                                    R.string.training_week_delta_previous_week
                                }
                            ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            val toggleRow: @Composable (String, Boolean) -> Unit = { label, isOpen ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clickable(role = Role.Button) {
                            if (isOpen) searchQuery = ""
                            expanded = !isOpen
                        },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f)
                    )
                    if (!isOpen) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            if (expanded) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(MaterialTheme.colorScheme.outlineVariant)
                )
                GymSearchField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it.take(EXERCISE_SEARCH_QUERY_MAX_CHARS) },
                    placeholder = stringResource(R.string.history_search_placeholder),
                    clearDescription = stringResource(R.string.exercise_search_clear),
                    modifier = Modifier
                        .fillMaxWidth()
                        .onGloballyPositioned { searchFieldCoordinates = it }
                        .onFocusChanged { state -> searchFieldFocused = state.hasFocus },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() })
                )
                if (visibleWorkouts.isEmpty()) {
                    Text(
                        text = stringResource(
                            if (isSearching) {
                                R.string.history_search_empty
                            } else if (period == TrainingHistoryPeriod.Week) {
                                R.string.training_history_empty_week
                            } else {
                                R.string.training_history_empty_month
                            }
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    visibleWorkouts.forEachIndexed { index, session ->
                        if (index > 0) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(1.dp)
                                    .background(MaterialTheme.colorScheme.outlineVariant)
                            )
                        }
                        TrainingHistoryRow(
                            session = session,
                            onClick = { onSessionClick(session.session.id) }
                        )
                    }
                }
                toggleRow(stringResource(R.string.today_history_collapse), true)
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(hairlineThickness())
                        .background(groupedSeparatorColor())
                )
                recentWorkouts.take(3).forEachIndexed { index, session ->
                    if (index > 0) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(hairlineThickness())
                                .background(groupedSeparatorColor())
                        )
                    }
                    TrainingHistoryRow(
                        session = session,
                        onClick = { onSessionClick(session.session.id) }
                    )
                }
                toggleRow(stringResource(R.string.today_all_history), false)
            }
        }
    }
}

@Composable
private fun TrainingHistoryWeekStrip(
    summary: WeeklyTrainingSummaryUiModel,
    locale: Locale,
    modifier: Modifier = Modifier
) {
    val weekdayLabels = stringArrayResource(R.array.weekday_short_labels)
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        summary.days.forEach { day ->
            val weekday = day.date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
            val status = stringResource(
                if (day.isCompleted) {
                    R.string.weekly_training_day_completed
                } else {
                    R.string.weekly_training_day_not_completed
                }
            )
            val todayStatus = if (day.isToday) {
                stringResource(R.string.weekly_training_day_today)
            } else {
                ""
            }
            val description = listOf(
                "$weekday ${day.date.dayOfMonth}",
                status,
                todayStatus
            ).filter { it.isNotBlank() }.joinToString(", ")
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clearAndSetSemantics { contentDescription = description },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = weekdayLabels.getOrElse(day.date.dayOfWeek.value - 1) { "" },
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (day.isToday) FontWeight.Bold else FontWeight.Normal,
                    color = if (day.isToday) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
                Box(
                    modifier = Modifier.size(22.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(
                                if (day.isCompleted) {
                                    MaterialTheme.colorScheme.secondary
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant
                                }
                            )
                            // An empty day keeps a 3:1 outline so the dot reads on the white panel.
                            .then(
                                if (day.isCompleted) {
                                    Modifier
                                } else {
                                    Modifier.border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)
                                }
                            )
                    )
                    if (day.isToday) {
                        Box(
                            modifier = Modifier
                                .size(18.dp)
                                .border(
                                    width = 1.dp,
                                    color = MaterialTheme.colorScheme.primary,
                                    shape = CircleShape
                                )
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TrainingHistoryMonthGrid(
    summary: MonthlyTrainingSummaryUiModel,
    locale: Locale,
    modifier: Modifier = Modifier
) {
    val weekdayLabels = stringArrayResource(R.array.weekday_short_labels)
    val leadingEmpty = summary.days.firstOrNull()?.date?.dayOfWeek?.value?.minus(1) ?: 0
    val unpaddedCells = List(leadingEmpty) { null } + summary.days.map { it }
    val trailingEmpty = (7 - unpaddedCells.size % 7) % 7
    val cells = unpaddedCells + List(trailingEmpty) { null }
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            (1..7).forEach { dayNumber ->
                Text(
                    text = weekdayLabels.getOrElse(dayNumber - 1) { "" },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        cells.chunked(7).forEach { week ->
            Row(modifier = Modifier.fillMaxWidth()) {
                week.forEach { day ->
                    if (day == null) {
                        Spacer(modifier = Modifier.weight(1f).height(34.dp))
                    } else {
                        val weekday = day.date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
                        val status = stringResource(
                            if (day.isCompleted) {
                                R.string.weekly_training_day_completed
                            } else {
                                R.string.weekly_training_day_not_completed
                            }
                        )
                        val description = "$weekday ${day.date.dayOfMonth}, $status"
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(34.dp)
                                .clearAndSetSemantics { contentDescription = description },
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(30.dp)
                                    .clip(CircleShape)
                                    .background(
                                        if (day.isCompleted) {
                                            MaterialTheme.colorScheme.secondaryContainer
                                        } else {
                                            Color.Transparent
                                        }
                                    )
                                    .then(
                                        if (day.isToday) {
                                            Modifier.border(
                                                1.dp,
                                                MaterialTheme.colorScheme.primary,
                                                CircleShape
                                            )
                                        } else {
                                            Modifier
                                        }
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = day.date.dayOfMonth.toString(),
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = if (day.isCompleted) {
                                        FontWeight.Bold
                                    } else {
                                        FontWeight.Normal
                                    },
                                    color = if (day.isCompleted) {
                                        MaterialTheme.colorScheme.onSecondaryContainer
                                    } else {
                                        MaterialTheme.colorScheme.onSurface
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TrainingHistoryRow(
    session: WorkoutSessionSummary,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val isActivityOnly = session.exerciseCount == 0 &&
        session.setCount == 0 &&
        session.session.durationSeconds?.let { it > 0L } == true
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = DateTimeUtils.formatShortDate(session.session.date, locale),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = if (isActivityOnly) {
                    stringResource(R.string.garmin_free_workout_title)
                } else {
                    listOf(
                        formattedPluralStringResource(
                            R.plurals.saved_workout_exercise_count,
                            session.exerciseCount,
                            session.exerciseCount
                        ),
                        formattedPluralStringResource(
                            R.plurals.saved_workout_set_count,
                            session.setCount,
                            session.setCount
                        )
                    ).joinToString(" · ")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        val trailingText = if (isActivityOnly) {
            formatWorkoutDuration(checkNotNull(session.session.durationSeconds))
        } else {
            formattedStringResource(
                R.string.today_history_volume_kg,
                formatTodayHeroVolume(session.totalVolume, locale)
            )
        }
        val trailingSpoken = if (isActivityOnly) {
            trailingText
        } else {
            formattedStringResource(
                R.string.today_history_volume_kg,
                formatTodayHeroVolumeSpoken(session.totalVolume, locale)
            )
        }
        Text(
            text = trailingText,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = Modifier.semantics { contentDescription = trailingSpoken }
        )
        Icon(
            imageVector = Icons.AutoMirrored.Filled.NavigateNext,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun WeeklyTrainingMetric(
    value: String,
    label: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .widthIn(min = 0.dp)
            .clearAndSetSemantics { contentDescription = "$label, $value" },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        FitMetricValue(text = value)
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun TodayHeroMetricsRow(
    metrics: TodayHeroMetricsUiModel,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val volume = remember(metrics.totalVolume, locale) {
        formatTodayHeroVolume(metrics.totalVolume, locale)
    }
    val totalWorkouts = remember(metrics.totalWorkouts, locale) {
        formatTodayHeroCount(metrics.totalWorkouts, locale)
    }
    val totalWorkoutsAccessibilityValue = remember(metrics.totalWorkouts, locale) {
        NumberFormat.getIntegerInstance(locale).format(metrics.totalWorkouts.coerceAtLeast(0))
    }
    val volumeAccessibilityValue = remember(metrics.totalVolume, locale) {
        formatVolumeTotal(
            metrics.totalVolume.takeIf { it.isFinite() && it >= 0.0 }
                ?.coerceAtMost(1_000_000_000_000_000.0) ?: 0.0,
            locale
        )
    }
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        TodayHeroMetric(
            value = totalWorkouts,
            label = stringResource(R.string.focus_lens_total_workouts),
            accessibilityValue = totalWorkoutsAccessibilityValue,
            modifier = Modifier.weight(1f)
        )
        TodayHeroMetric(
            value = formattedStringResource(
                R.string.focus_lens_week_streak_value,
                metrics.weeklyStreakWeeks
            ),
            label = stringResource(R.string.focus_lens_week_streak),
            accessibilityValue = formattedStringResource(
                R.string.focus_lens_week_streak_value,
                metrics.weeklyStreakWeeks
            ),
            modifier = Modifier.weight(1f)
        )
        TodayHeroMetric(
            value = formattedStringResource(R.string.today_history_volume_kg, volume),
            label = stringResource(R.string.focus_lens_total_volume),
            accessibilityValue = formattedStringResource(R.string.today_history_volume_kg, volumeAccessibilityValue),
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun TodayHeroMetric(
    value: String,
    label: String,
    accessibilityValue: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .widthIn(min = 0.dp)
            .clearAndSetSemantics { contentDescription = "$label, $accessibilityValue" },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        FitMetricValue(text = value, color = HeroTone.title)
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = HeroTone.supporting,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

internal fun formatTodayHeroCount(value: Int, locale: Locale): String {
    val safeValue = value.coerceAtLeast(0).toDouble()
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        android.icu.text.CompactDecimalFormat.getInstance(
            locale,
            android.icu.text.CompactDecimalFormat.CompactStyle.SHORT
        ).apply { maximumFractionDigits = 1 }.format(safeValue)
    } else {
        NumberFormat.getIntegerInstance(locale).format(safeValue)
    }
}

/** "+12%" / "−8%" (true minus sign) / "0%"; the sign is part of the text, the number follows the locale. */
internal fun formatWeekVolumeDelta(percent: Int, locale: Locale): String {
    val sign = when {
        percent > 0 -> "+"
        percent < 0 -> "\u2212"
        else -> ""
    }
    return sign + NumberFormat.getIntegerInstance(locale).format(Math.abs(percent.toLong())) + "%"
}

internal fun formatTodayHeroVolume(value: Double, locale: Locale): String {
    val safeValue = value
        .takeIf { it.isFinite() && it >= 0.0 }
        ?.coerceAtMost(1_000_000_000_000_000.0)
        ?: 0.0
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        android.icu.text.CompactDecimalFormat.getInstance(
            locale,
            android.icu.text.CompactDecimalFormat.CompactStyle.SHORT
        ).apply { maximumFractionDigits = 1 }.format(safeValue)
    } else {
        NumberFormat.getNumberInstance(locale).apply {
            maximumFractionDigits = 1
            isGroupingUsed = true
        }.format(safeValue)
    }
}

/** Full, grouped number for screen readers (the visible label is compact, e.g. "12K"). */
internal fun formatTodayHeroVolumeSpoken(value: Double, locale: Locale): String {
    val safeValue = value
        .takeIf { it.isFinite() && it >= 0.0 }
        ?.coerceAtMost(1_000_000_000_000_000.0)
        ?: 0.0
    return formatVolumeTotal(safeValue, locale)
}

@Composable
private fun FirstWorkoutActivationCard(
    hasRetainedWorkoutDraft: Boolean,
    onContinuePlan: () -> Unit,
    onCancelPlan: () -> Unit,
    onStart: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onEdit: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onCreateManually: () -> Unit,
    tutorialAnchors: TutorialAnchorRegistry?,
    trainingProfile: TrainingProfile = TrainingProfile(),
    onTrainingProfileChange: (TrainingProfile) -> Unit = {},
    friendPill: @Composable () -> Unit = {},
    modifier: Modifier = Modifier
) {
    // Goal and weekly target come from the stored training settings, edited in one place.
    val goal = trainingProfile.goal
    val days = trainingProfile.workoutsPerWeek
    var showTrainingSettings by rememberSaveable { mutableStateOf(false) }
    if (showTrainingSettings) {
        TrainingSettingsSheet(
            profile = trainingProfile,
            onProfileChange = onTrainingProfileChange,
            onDismiss = { showTrainingSettings = false }
        )
    }
    var effort by rememberSaveable { mutableStateOf(FirstWorkoutEffort.Standard) }
    var showRecommendationOptions by rememberSaveable { mutableStateOf(false) }
    val darkTheme = isSystemInDarkTheme()
    val adjustLabel = stringResource(R.string.activation_adjust_recommendation)
    val adjustOpenState = stringResource(R.string.activation_adjust_open)
    val adjustClosedState = stringResource(R.string.activation_adjust_closed)
    val focusModifier = if (tutorialAnchors == null) {
        modifier
    } else {
        modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayFocus)
    }
    val primaryModifier = if (tutorialAnchors == null) {
        Modifier
    } else {
        Modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayPrimaryAction)
    }
    Column(
        modifier = focusModifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(HeroTone.surface)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        if (hasRetainedWorkoutDraft) {
            Text(
                text = stringResource(R.string.title_workout_plan),
                style = MaterialTheme.typography.headlineLarge,
                color = HeroTone.title,
                fontWeight = FontWeight.Bold
            )
            Button(
                onClick = onContinuePlan,
                modifier = primaryModifier.fillMaxWidth().heightIn(min = 54.dp),
                colors = heroPrimaryButtonColors()
            ) {
                Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    stringResource(R.string.today_continue_plan),
                    fontWeight = FontWeight.Bold
                )
            }
            TintedButton(
                onClick = onCancelPlan,
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                colors = heroSecondaryOutlinedColors(),
                border = heroSecondaryBorder()
            ) {
                Text(stringResource(R.string.today_cancel_plan))
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Text(
                        text = stringResource(R.string.activation_first_plan_title),
                        style = MaterialTheme.typography.headlineLarge,
                        color = HeroTone.title,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f)
                    )
                    IconButton(
                        onClick = { showRecommendationOptions = !showRecommendationOptions },
                        modifier = Modifier
                            .size(44.dp)
                            .semantics {
                                contentDescription = adjustLabel
                                selected = showRecommendationOptions
                                stateDescription = if (showRecommendationOptions) {
                                    adjustOpenState
                                } else {
                                    adjustClosedState
                                }
                            },
                        colors = IconButtonDefaults.iconButtonColors(
                            containerColor = if (showRecommendationOptions) {
                                if (darkTheme) BrandFillNight else BrandFill
                            } else {
                                HeroTone.tile
                            },
                            contentColor = if (showRecommendationOptions) {
                                Color.White
                            } else {
                                HeroTone.actionLabel
                            }
                        )
                    ) {
                        Icon(imageVector = Icons.Default.Tune, contentDescription = null)
                    }
                }
                Text(
                    text = stringResource(R.string.activation_first_plan_supporting),
                    style = MaterialTheme.typography.bodyLarge,
                    color = HeroTone.supporting
                )
                if (showRecommendationOptions) {
                    Column(
                        modifier = Modifier.padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        TrainingSettingsSummaryRow(
                            profile = trainingProfile,
                            onEdit = { showTrainingSettings = true },
                            textColor = HeroTone.supporting,
                            linkColor = HeroTone.actionLabel
                        )
                        // Short one-word labels keep the three efforts in one equal-width row.
                        ActivationChoiceRow(
                            label = stringResource(R.string.activation_effort),
                            options = listOf(
                                FirstWorkoutEffort.Recovery to
                                    stringResource(R.string.activation_effort_light),
                                FirstWorkoutEffort.Standard to
                                    stringResource(R.string.activation_effort_normal),
                                FirstWorkoutEffort.Hard to
                                    stringResource(R.string.activation_effort_hard)
                            ),
                            selected = effort,
                            onSelected = { effort = it }
                        )
                        TextButton(
                            onClick = { onEdit(goal, days, effort) },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Edit,
                                contentDescription = null,
                                tint = HeroTone.actionLabel
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                stringResource(R.string.activation_edit_plan),
                                color = HeroTone.actionLabel
                            )
                        }
                    }
                }
            }
            Button(
                onClick = { onStart(goal, days, effort) },
                modifier = primaryModifier.fillMaxWidth().heightIn(min = 54.dp),
                colors = heroPrimaryButtonColors()
            ) {
                Text(
                    stringResource(R.string.activation_start_plan),
                    fontWeight = FontWeight.Bold
                )
            }
            TextButton(
                onClick = onCreateManually,
                modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)
            ) {
                Text(
                    stringResource(R.string.activation_build_manually),
                    color = HeroTone.actionLabel,
                    fontWeight = FontWeight.Medium
                )
            }
        }
        friendPill()
    }
}

/** The "С другом" pill in the Today hero, variant B as on iOS. */
@Composable
private fun TrainWithFriendPill(
    state: TodayFriendEntryState,
    forcedVisible: Boolean,
    onClick: () -> Unit
) {
    if (state == TodayFriendEntryState.Hidden) return
    val inviteCount = (state as? TodayFriendEntryState.PendingInvite)?.count
    val title = stringResource(
        if (inviteCount != null) R.string.today_friend_pill_invite else R.string.today_friend_pill
    )
    val hint = stringResource(
        when {
            forcedVisible && inviteCount == null -> R.string.today_friend_hint_blocked
            state == TodayFriendEntryState.NeedsCloudAccount -> R.string.today_friend_hint_account
            state == TodayFriendEntryState.NeedsFriends -> R.string.today_friend_hint_friends
            inviteCount != null -> R.string.today_friend_hint_invite
            else -> R.string.today_friend_hint_pick
        }
    )
    TintedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .semantics { contentDescription = "$title. $hint" },
        shape = RoundedCornerShape(50),
        // Tonal pill with a blue label; the invite state adds a solid blue count badge.
        colors = heroSecondaryOutlinedColors(),
        border = heroSecondaryBorder()
    ) {
        Icon(imageVector = Icons.Default.Group, contentDescription = null)
        Spacer(modifier = Modifier.width(8.dp))
        Text(title, fontWeight = FontWeight.Bold, maxLines = 1)
        if (inviteCount != null) {
            Spacer(modifier = Modifier.width(8.dp))
            Surface(shape = RoundedCornerShape(50), color = brandFillColor(), contentColor = Color.White) {
                Text(
                    text = inviteCount.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
    }
}

/** The "С другом" action as a row of the Today grouped section (accent text, chevron, invite count). */
@Composable
private fun TrainWithFriendRow(
    state: TodayFriendEntryState,
    forcedVisible: Boolean,
    inHero: Boolean = false,
    onClick: () -> Unit
) {
    if (state == TodayFriendEntryState.Hidden) return
    val inviteCount = (state as? TodayFriendEntryState.PendingInvite)?.count
    val title = stringResource(
        if (inviteCount != null) R.string.today_friend_pill_invite else R.string.today_friend_pill
    )
    val hint = stringResource(
        when {
            forcedVisible && inviteCount == null -> R.string.today_friend_hint_blocked
            state == TodayFriendEntryState.NeedsCloudAccount -> R.string.today_friend_hint_account
            state == TodayFriendEntryState.NeedsFriends -> R.string.today_friend_hint_friends
            inviteCount != null -> R.string.today_friend_hint_invite
            else -> R.string.today_friend_hint_pick
        }
    )
    if (inHero) {
        // Inside the hero card the row aligns with the card's own content edge, so it is drawn here
        // instead of as an inset grouped row.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics { contentDescription = "$title. $hint" },
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Group,
                contentDescription = null,
                tint = HeroTone.actionLabel,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = HeroTone.actionLabel,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            if (inviteCount != null) {
                Surface(shape = RoundedCornerShape(50), color = brandFillColor(), contentColor = Color.White) {
                    Text(
                        text = inviteCount.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = HeroTone.supporting,
                modifier = Modifier.size(20.dp)
            )
        }
        return
    }
    val accent = MaterialTheme.colorScheme.primary
    GroupedRow(
        title = title,
        modifier = Modifier.semantics { contentDescription = "$title. $hint" },
        value = inviteCount?.toString(),
        icon = { ActionRowIcon(Icons.Default.Group, accent) },
        chevron = true,
        titleColor = accent,
        onClick = onClick
    )
}

/** Friend list for "С другом"; picking one opens the live workout editor with that friend. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TrainWithFriendPicker(
    friends: List<TodayFriendChoice>,
    onPick: (TodayFriendChoice) -> Unit,
    onDismiss: () -> Unit
) {
    GymModalBottomSheet(onDismissRequest = onDismiss) {
        GymSheetCloseRow(onClose = onDismiss, modifier = Modifier.padding(horizontal = 12.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = stringResource(R.string.today_friend_picker_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            if (friends.isEmpty()) {
                Text(
                    text = stringResource(R.string.today_friend_picker_empty),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            val startHint = stringResource(R.string.today_friend_picker_row_hint)
            friends.forEach { friend ->
                TextButton(
                    onClick = { onPick(friend) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 52.dp)
                        .semantics { contentDescription = "${friend.displayName}. $startHint" }
                ) {
                    Icon(
                        imageVector = Icons.Default.AccountCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = friend.displayName,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f),
                        maxLines = 1
                    )
                    Icon(
                        imageVector = Icons.Default.FitnessCenter,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun <T> ActivationChoiceRow(
    label: String,
    options: List<Pair<T, String>>,
    selected: T,
    onSelected: (T) -> Unit,
    columns: Int = options.size
) {
    require(columns > 0)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = HeroTone.supporting
        )
        if (columns == 2) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                options.chunked(columns).forEach { optionRow ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        optionRow.forEach { (value, optionLabel) ->
                            val isSelected = value == selected
                            Surface(
                                onClick = { onSelected(value) },
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                                color = if (isSelected) brandFillColor() else HeroTone.tile,
                                contentColor = if (isSelected) Color.White else HeroTone.actionLabel,
                                shape = RoundedCornerShape(50)
                            ) {
                                Box(
                                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = optionLabel,
                                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                                        maxLines = 2,
                                        style = MaterialTheme.typography.labelMedium,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                        repeat(columns - optionRow.size) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(options.size) { index ->
                    val (value, optionLabel) = options[index]
                    FilterChip(
                        selected = value == selected,
                        onClick = { onSelected(value) },
                        colors = FilterChipDefaults.filterChipColors(
                            containerColor = HeroTone.tile,
                            labelColor = HeroTone.actionLabel,
                            selectedContainerColor = brandFillColor(),
                            selectedLabelColor = Color.White
                        ),
                        border = FilterChipDefaults.filterChipBorder(
                            enabled = true,
                            selected = value == selected,
                            borderColor = HeroTone.outline,
                            selectedBorderColor = Color.Transparent
                        ),
                        label = {
                            Text(
                                text = optionLabel,
                                maxLines = 1,
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    )
                }
            }
        }
    }
}

private fun SmartWorkoutFocus.labelResource(): Int = when (this) {
    SmartWorkoutFocus.Upper -> R.string.smart_focus_upper
    SmartWorkoutFocus.Lower -> R.string.smart_focus_lower
    SmartWorkoutFocus.Push -> R.string.smart_focus_push
    SmartWorkoutFocus.Pull -> R.string.smart_focus_pull
    SmartWorkoutFocus.Legs -> R.string.smart_focus_legs
    SmartWorkoutFocus.FullBody -> R.string.smart_focus_full_body
}

private fun SmartWorkoutEffortAdjustment?.recoveryReasonResource(): Int = when (this) {
    SmartWorkoutEffortAdjustment.AutoRecovery -> R.string.smart_effort_adjustment_auto_recovery
    SmartWorkoutEffortAdjustment.FeedbackHardRecovery ->
        R.string.smart_effort_adjustment_feedback_hard
    SmartWorkoutEffortAdjustment.ReadinessLowRecovery ->
        R.string.smart_effort_adjustment_readiness_low
    else -> R.string.smart_reason_recovery_effort
}

@Composable
private fun FocusLensMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            color = HeroTone.title,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = HeroTone.supporting
        )
    }
}

@Composable
private fun DashboardCard(
    stats: DashboardStats,
    modifier: Modifier = Modifier
) {
    HeroPanel(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = stringResource(R.string.dashboard_title),
                style = MaterialTheme.typography.titleLarge,
                color = HeroTone.title
            )
            Text(
                text = stringResource(R.string.dashboard_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = HeroTone.supporting
            )

            Row(
                modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.kpi_workouts),
                    value = stats.workoutCount.toString(),
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.kpi_streak),
                    value = formattedStringResource(
                        R.string.kpi_streak_weekly_value,
                        stats.weeklyStreakWeeks
                    ),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.kpi_total_volume),
                    value = formattedStringResource(R.string.kpi_volume_value, stats.totalVolume),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.kpi_avg_intensity),
                    value = formattedStringResource(R.string.kpi_avg_intensity_value, stats.averageIntensity),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
        }
    }
}
