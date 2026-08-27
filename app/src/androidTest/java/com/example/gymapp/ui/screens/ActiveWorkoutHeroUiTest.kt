package com.example.gymapp.ui.screens

import android.text.format.DateFormat
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.ActiveWorkoutUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutExerciseUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutSetUiState
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ActiveWorkoutHeroUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun heroShowsBalancedElapsedCompletedAndStartedMetricsWithProgressSemantics() {
        val startedAt = Instant.parse("2026-08-24T14:05:00Z").toEpochMilli()
        val locale = composeRule.activity.resources.configuration.locales[0]
        composeRule.setContent {
            GymAppTheme {
                ActiveWorkoutScreen(
                    uiState = ActiveWorkoutUiState(
                        isLoading = false,
                        startedAt = startedAt,
                        completedSetCount = 2,
                        totalSetCount = 4,
                        workoutElapsedSeconds = 123
                    ),
                    exerciseMediaOwnerKey = "hero-test",
                    onSetWeightChanged = { _, _ -> },
                    onSetRepsChanged = { _, _ -> },
                    onSaveExercise = {},
                    onAddSet = {},
                    onRecordSet = {},
                    onRecordAllPendingSets = {},
                    onUndoLatestSet = {},
                    onAdjustRestTimer = {},
                    onStopRestTimer = {},
                    onFinishWorkout = {},
                    onDiscardWorkout = {},
                    onDismissMessage = {}
                )
            }
        }

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_elapsed_label).uppercase(locale)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(formatActiveWorkoutTime(123, locale)).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_completed_label).uppercase(locale)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_completed_value, 2, 4)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(
                R.string.active_workout_started_at,
                formatActiveWorkoutStartedAt(
                    timestamp = startedAt,
                    locale = locale,
                    is24Hour = DateFormat.is24HourFormat(composeRule.activity)
                )
            )
        ).assertIsDisplayed()

        val elapsedWidth = composeRule.onNodeWithTag(ACTIVE_WORKOUT_ELAPSED_METRIC_TAG)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot
            .width
        val completedWidth = composeRule.onNodeWithTag(ACTIVE_WORKOUT_COMPLETED_METRIC_TAG)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot
            .width
        assertEquals(elapsedWidth, completedWidth, 1f)

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_progress_accessibility)
        ).assertIsDisplayed().assert(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo(current = 2f, range = 0f..4f, steps = 3)
            )
        )
    }

    @Test
    fun currentValidSetCanBeRecordedFromTheWorkoutFlow() {
        var recordedSetId: String? = null
        setActiveWorkoutContent(
            uiState = ActiveWorkoutUiState(
                isLoading = false,
                exercises = listOf(
                    ActiveWorkoutExerciseUiState(
                        id = "exercise-1",
                        exerciseId = null,
                        exerciseName = "Bench Press",
                        orderIndex = 0,
                        restDurationSeconds = 90,
                        sets = listOf(
                            ActiveWorkoutSetUiState(
                                id = "set-1",
                                orderIndex = 0,
                                weightInput = "60",
                                repsInput = "8",
                                isCompleted = false,
                                completedAt = null
                            )
                        )
                    )
                ),
                totalSetCount = 1
            ),
            onRecordSet = { recordedSetId = it }
        )

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_set_current)
        ).performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_log_set_and_rest, 90)
        ).performScrollTo().assertIsEnabled().performClick()

        composeRule.runOnIdle { assertEquals("set-1", recordedSetId) }
    }

    @Test
    fun latestCompletedSetExposesRestControlsAndUndo() {
        var adjustedBy: Int? = null
        var stopped = false
        var undoneSetId: String? = null
        setActiveWorkoutContent(
            uiState = ActiveWorkoutUiState(
                isLoading = false,
                exercises = listOf(
                    ActiveWorkoutExerciseUiState(
                        id = "exercise-1",
                        exerciseId = null,
                        exerciseName = "Bench Press",
                        orderIndex = 0,
                        restDurationSeconds = 90,
                        sets = listOf(
                            ActiveWorkoutSetUiState(
                                id = "set-1",
                                orderIndex = 0,
                                weightInput = "60",
                                repsInput = "8",
                                isCompleted = true,
                                completedAt = 1L
                            ),
                            ActiveWorkoutSetUiState(
                                id = "set-2",
                                orderIndex = 1,
                                weightInput = "60",
                                repsInput = "8",
                                isCompleted = false,
                                completedAt = null
                            )
                        )
                    )
                ),
                completedSetCount = 1,
                totalSetCount = 2,
                latestCompletedSetId = "set-1",
                restSecondsRemaining = 30
            ),
            onUndoLatestSet = { undoneSetId = it },
            onAdjustRestTimer = { adjustedBy = it },
            onStopRestTimer = { stopped = true }
        )

        composeRule.onNodeWithText("+15").performScrollTo().performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_rest_stop)
        ).performScrollTo().performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_undo_action)
        ).performScrollTo().performClick()

        composeRule.runOnIdle {
            assertEquals(15, adjustedBy)
            assertEquals(true, stopped)
            assertEquals("set-1", undoneSetId)
        }
    }

    @Test
    fun restControlsAreDisabledWhileAWorkoutMutationIsInFlight() {
        setActiveWorkoutContent(
            uiState = ActiveWorkoutUiState(
                isLoading = false,
                exercises = listOf(
                    ActiveWorkoutExerciseUiState(
                        id = "exercise-1",
                        exerciseId = null,
                        exerciseName = "Bench Press",
                        orderIndex = 0,
                        restDurationSeconds = 90,
                        sets = listOf(
                            ActiveWorkoutSetUiState(
                                id = "set-1",
                                orderIndex = 0,
                                weightInput = "60",
                                repsInput = "8",
                                isCompleted = true,
                                completedAt = 1L
                            )
                        )
                    )
                ),
                completedSetCount = 1,
                totalSetCount = 1,
                latestCompletedSetId = "set-1",
                restSecondsRemaining = 30,
                setRecordingsInFlight = setOf("set-2")
            )
        )

        composeRule.onNodeWithText("+15").performScrollTo().assertIsNotEnabled()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_rest_stop)
        ).performScrollTo().assertIsNotEnabled()
    }

    private fun setActiveWorkoutContent(
        uiState: ActiveWorkoutUiState,
        onRecordSet: (String) -> Unit = {},
        onUndoLatestSet: (String) -> Unit = {},
        onAdjustRestTimer: (Int) -> Unit = {},
        onStopRestTimer: () -> Unit = {}
    ) {
        composeRule.setContent {
            GymAppTheme {
                ActiveWorkoutScreen(
                    uiState = uiState,
                    exerciseMediaOwnerKey = "active-workout-test",
                    onSetWeightChanged = { _, _ -> },
                    onSetRepsChanged = { _, _ -> },
                    onSaveExercise = {},
                    onAddSet = {},
                    onRecordSet = onRecordSet,
                    onRecordAllPendingSets = {},
                    onUndoLatestSet = onUndoLatestSet,
                    onAdjustRestTimer = onAdjustRestTimer,
                    onStopRestTimer = onStopRestTimer,
                    onFinishWorkout = {},
                    onDiscardWorkout = {},
                    onDismissMessage = {}
                )
            }
        }
    }
}
