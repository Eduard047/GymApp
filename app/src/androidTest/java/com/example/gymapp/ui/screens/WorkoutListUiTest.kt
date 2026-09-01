package com.example.gymapp.ui.screens

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.activity.ComponentActivity
import com.example.gymapp.R
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.WeeklyTrainingDecision
import com.example.gymapp.data.repository.WeeklyTrainingRhythm
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.TodayPlanUiModel
import com.example.gymapp.ui.viewmodel.WeeklyTrainingDayUiModel
import com.example.gymapp.ui.viewmodel.WeeklyTrainingSummaryUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.LocalizedText
import java.time.LocalDate
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkoutListUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun completedTodayShowsWeeklyMetricsAndOnlyQuietCreateAnotherAction() {
        val weekStart = LocalDate.of(2026, 8, 10)
        val weeklySummary = WeeklyTrainingSummaryUiModel(
            days = (0L..6L).map { offset ->
                WeeklyTrainingDayUiModel(
                    date = weekStart.plusDays(offset),
                    isCompleted = offset in setOf(0L, 2L, 5L),
                    isToday = offset == 5L
                )
            },
            completedWorkoutCount = 3,
            completedTrainingDays = 3,
            targetTrainingDays = 4,
            estimatedMinutes = 48,
            totalVolume = 640.0
        )
        composeRule.setContent {
            GymAppTheme {
                WorkoutListScreen(
                        uiState = WorkoutListUiState(
                            todayPlan = TodayPlanUiModel(
                                focus = SmartWorkoutFocus.FullBody,
                                rhythm = WeeklyTrainingRhythm(
                                    completedTrainingDays = 3,
                                    targetTrainingDays = 4,
                                    decision = WeeklyTrainingDecision.Recovery
                                ),
                                exerciseCount = 4,
                                setCount = 12,
                                estimatedDurationMinutes = 40,
                                effortAdjustment = SmartWorkoutEffortAdjustment.AutoRecovery,
                                trainAnywayLaunchToken = "synthetic-recovery-token"
                            ),
                            hasCompletedWorkoutToday = true,
                            hasAnyWorkout = true,
                            weeklyTrainingSummary = weeklySummary
                        ),
                        onSessionClick = {},
                        onPreviousMonth = {},
                        onCurrentMonth = {},
                        onNextMonth = {},
                        onPreviousWeek = {},
                        onCurrentWeek = {},
                        onNextWeek = {},
                        onHistoryPeriodSelected = {},
                        onMuscleMapPeriodSelected = {},
                        onMuscleSelected = {},
                        onAddWorkout = {},
                        onStartPlan = {},
                        onOpenPlan = {},
                        onStartFirstWorkout = { _, _, _ -> },
                        onEditFirstWorkout = { _, _, _ -> },
                        onSkipFirstWorkout = {}
                )
            }
        }

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_workout_completed)
        ).assertIsDisplayed()

        val locale = composeRule.activity.resources.configuration.locales[0]
        listOf(
            R.string.weekly_training_workouts_label to
                formatTodayHeroCount(weeklySummary.completedWorkoutCount, locale),
            R.string.weekly_training_minutes_label to
                composeRule.activity.getString(
                    R.string.weekly_training_minutes_value,
                    weeklySummary.estimatedMinutes
                ),
            R.string.weekly_training_volume_label to
                formatTodayHeroVolume(weeklySummary.totalVolume, locale)
        ).forEach { (labelResource, value) ->
            val label = composeRule.activity.getString(labelResource)
            composeRule.onNodeWithContentDescription("$label, $value")
                .performScrollTo()
                .assertIsDisplayed()
        }

        val addAnother = composeRule.activity.getString(R.string.today_add_another_workout)
        composeRule.onNodeWithText(addAnother).performScrollTo().assertIsDisplayed()
        composeRule.onAllNodesWithText(addAnother).assertCountEquals(1)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_train_anyway)
        ).assertDoesNotExist()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_start_workout)
        ).assertDoesNotExist()
    }

    @Test
    fun completedTodayRetainedDraftOffersContinueAndConfirmedCancelOnly() {
        var cancelled = false
        setWorkoutListContent(
            uiState = WorkoutListUiState(
                todayPlan = TodayPlanUiModel(
                    focus = SmartWorkoutFocus.FullBody,
                    rhythm = WeeklyTrainingRhythm(
                        completedTrainingDays = 3,
                        targetTrainingDays = 4,
                        decision = WeeklyTrainingDecision.Recovery
                    ),
                    exerciseCount = 4,
                    setCount = 12,
                    estimatedDurationMinutes = 40,
                    effortAdjustment = SmartWorkoutEffortAdjustment.AutoRecovery,
                    trainAnywayLaunchToken = "synthetic-recovery-token"
                ),
                hasCompletedWorkoutToday = true
            ),
            hasRetainedWorkoutDraft = true,
            onCancelRetainedPlan = { cancelled = true }
        )

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_workout_completed)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_workout_completed_supporting)
        ).assertIsDisplayed()

        val continuePlan = composeRule.activity.getString(R.string.today_continue_plan)
        composeRule.onNodeWithText(continuePlan).performScrollTo().assertIsDisplayed()
        composeRule.onAllNodesWithText(continuePlan).assertCountEquals(1)
        val cancelPlan = composeRule.activity.getString(R.string.today_cancel_plan)
        composeRule.onNodeWithText(cancelPlan).performScrollTo().assertIsDisplayed().performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_cancel_plan_title)
        ).assertIsDisplayed()
        composeRule.onAllNodesWithText(cancelPlan).assertCountEquals(2)
        composeRule.onAllNodesWithText(cancelPlan)[1].performClick()
        composeRule.runOnIdle { assertTrue(cancelled) }
        listOf(
            R.string.today_add_another_workout,
            R.string.today_train_anyway,
            R.string.today_edit_plan,
            R.string.today_start_plan,
            R.string.activation_create_manually
        ).forEach { resource ->
            composeRule.onNodeWithText(
                composeRule.activity.getString(resource)
            ).assertDoesNotExist()
        }
    }

    @Test
    fun firstActivationWithRetainedDraftShowsContinueAndCancelPlan() {
        setWorkoutListContent(
            uiState = WorkoutListUiState(showFirstWorkoutActivation = true),
            hasRetainedWorkoutDraft = true
        )

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.title_workout_plan)
        ).assertIsDisplayed()
        val continuePlan = composeRule.activity.getString(R.string.today_continue_plan)
        composeRule.onNodeWithText(continuePlan).assertIsDisplayed()
        composeRule.onAllNodesWithText(continuePlan).assertCountEquals(1)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.today_cancel_plan)
        ).assertIsDisplayed()
        listOf(
            R.string.activation_goal,
            R.string.activation_days,
            R.string.activation_effort,
            R.string.activation_start_plan,
            R.string.activation_edit_plan,
            R.string.activation_create_manually
        ).forEach { resource ->
            composeRule.onNodeWithText(
                composeRule.activity.getString(resource)
            ).assertDoesNotExist()
        }
    }

    @Test
    fun loadingAndLoadFailureHaveExplicitRecoverableStates() {
        val uiState = mutableStateOf(WorkoutListUiState(isLoading = true))
        var retried = false
        composeRule.setContent {
            GymAppTheme {
                WorkoutListScreen(
                    uiState = uiState.value,
                    onSessionClick = {},
                    onPreviousMonth = {},
                    onCurrentMonth = {},
                    onNextMonth = {},
                    onPreviousWeek = {},
                    onCurrentWeek = {},
                    onNextWeek = {},
                    onHistoryPeriodSelected = {},
                    onMuscleMapPeriodSelected = {},
                    onMuscleSelected = {},
                    onAddWorkout = {},
                    onStartPlan = {},
                    onOpenPlan = {},
                    onStartFirstWorkout = { _, _, _ -> },
                    onEditFirstWorkout = { _, _, _ -> },
                    onSkipFirstWorkout = {},
                    hasRetainedWorkoutDraft = false,
                    onRetryLoad = { retried = true }
                )
            }
        }
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workouts_loading)
        ).assertIsDisplayed()

        composeRule.runOnIdle {
            uiState.value = WorkoutListUiState(
                loadError = LocalizedText(R.string.workouts_load_failed)
            )
        }
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workouts_load_failed)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_retry)
        ).performClick()
        composeRule.runOnIdle { assertTrue(retried) }
    }

    private fun setWorkoutListContent(
        uiState: WorkoutListUiState,
        hasRetainedWorkoutDraft: Boolean,
        onRetryLoad: () -> Unit = {},
        onCancelRetainedPlan: () -> Unit = {}
    ) {
        composeRule.setContent {
            GymAppTheme {
                WorkoutListScreen(
                        uiState = uiState,
                        onSessionClick = {},
                        onPreviousMonth = {},
                        onCurrentMonth = {},
                        onNextMonth = {},
                        onPreviousWeek = {},
                        onCurrentWeek = {},
                        onNextWeek = {},
                        onHistoryPeriodSelected = {},
                        onMuscleMapPeriodSelected = {},
                        onMuscleSelected = {},
                        onAddWorkout = {},
                        onStartPlan = {},
                        onOpenPlan = {},
                        onStartFirstWorkout = { _, _, _ -> },
                        onEditFirstWorkout = { _, _, _ -> },
                        onSkipFirstWorkout = {},
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                        onCancelRetainedPlan = onCancelRetainedPlan,
                        onRetryLoad = onRetryLoad
                )
            }
        }
    }
}
