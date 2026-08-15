package com.example.gymapp.ui.screens

import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.gymapp.MainActivity
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
import java.time.LocalDate
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkoutListUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

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
        composeRule.activity.runOnUiThread {
            composeRule.activity.setContent {
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
                            weeklyTrainingSummary = weeklySummary
                        ),
                        onSessionClick = {},
                        onPreviousMonth = {},
                        onCurrentMonth = {},
                        onNextMonth = {},
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
    fun completedTodayKeepsItsCopyButRetainedDraftReplacesAllActions() {
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
            hasRetainedWorkoutDraft = true
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
    fun firstActivationWithRetainedDraftShowsOnlyContinuePlan() {
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

    private fun setWorkoutListContent(
        uiState: WorkoutListUiState,
        hasRetainedWorkoutDraft: Boolean
    ) {
        composeRule.activity.runOnUiThread {
            composeRule.activity.setContent {
                GymAppTheme {
                    WorkoutListScreen(
                        uiState = uiState,
                        onSessionClick = {},
                        onPreviousMonth = {},
                        onCurrentMonth = {},
                        onNextMonth = {},
                        onMuscleMapPeriodSelected = {},
                        onMuscleSelected = {},
                        onAddWorkout = {},
                        onStartPlan = {},
                        onOpenPlan = {},
                        onStartFirstWorkout = { _, _, _ -> },
                        onEditFirstWorkout = { _, _, _ -> },
                        onSkipFirstWorkout = {},
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft
                    )
                }
            }
        }
    }
}
