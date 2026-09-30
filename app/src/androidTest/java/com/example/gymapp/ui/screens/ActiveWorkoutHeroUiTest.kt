package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
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
    fun heroShowsElapsedClockRingCountAndOneCombinedAccessibilityElement() {
        val locale = composeRule.activity.resources.configuration.locales[0]
        setActiveWorkoutContent(
            uiState = ActiveWorkoutUiState(
                isLoading = false,
                startedAt = Instant.parse("2026-08-24T14:05:00Z").toEpochMilli(),
                completedSetCount = 2,
                totalSetCount = 4,
                workoutElapsedSeconds = 123
            )
        )

        val clock = formatActiveWorkoutTime(123, locale)
        composeRule.onNodeWithTag(ACTIVE_WORKOUT_ELAPSED_METRIC_TAG, useUnmergedTree = true)
            .assertIsDisplayed()
            .assertTextEquals(clock)
        composeRule.onNodeWithText("2/4", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_status_in_progress),
            useUnmergedTree = true
        ).assertIsDisplayed()

        val setsDone = composeRule.activity.resources.getQuantityString(
            R.plurals.active_workout_hero_sets_done,
            4,
            2,
            4
        )
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_hero_summary, clock, setsDone)
        ).assertIsDisplayed()
    }

    @Test
    fun heroNamesTheCurrentExerciseAndReadsItInTheCombinedDescription() {
        val locale = composeRule.activity.resources.configuration.locales[0]
        setActiveWorkoutContent(
            uiState = ActiveWorkoutUiState(
                isLoading = false,
                exercises = listOf(
                    ActiveWorkoutExerciseUiState(
                        id = "exercise-1",
                        exerciseId = null,
                        exerciseName = "XYZ-42",
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
                completedSetCount = 0,
                totalSetCount = 1,
                workoutElapsedSeconds = 65
            )
        )

        val clock = formatActiveWorkoutTime(65, locale)
        val setsDone = composeRule.activity.resources.getQuantityString(
            R.plurals.active_workout_hero_sets_done,
            1,
            0,
            1
        )
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(
                R.string.active_workout_hero_summary_now,
                clock,
                setsDone,
                "XYZ-42"
            )
        ).assertIsDisplayed()
    }

    @Test
    fun overflowMenuRaisesDiscardRequestFromTheToolbar() {
        val toolbarState = ActiveWorkoutToolbarState().apply {
            showsOverflow = true
            canDiscard = true
        }
        composeRule.setContent {
            GymAppTheme { ActiveWorkoutOverflowMenu(toolbarState) }
        }

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_more_options)
        ).performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_discard_short)
        ).performClick()

        composeRule.runOnIdle { assertEquals(true, toolbarState.discardRequested) }
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

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.action_log_set_and_rest, "1:30")
        ).performScrollTo().assertIsDisplayed().assertIsEnabled().performClick()

        composeRule.runOnIdle { assertEquals("set-1", recordedSetId) }
    }

    @Test
    fun latestCompletedSetShowsCompactRestControlsWithoutAStandingUndoButton() {
        var adjustedBy: Int? = null
        var stopped = false
        setActiveWorkoutContent(
            uiState = completedThenPendingState(restSecondsRemaining = 30),
            onAdjustRestTimer = { adjustedBy = it },
            onStopRestTimer = { stopped = true }
        )

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_add)
        ).performScrollTo().performClick()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_subtract)
        ).performScrollTo().performClick()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_stop)
        ).performScrollTo().performClick()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_timer_cd)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_undo_action)
        ).assertDoesNotExist()

        composeRule.runOnIdle {
            assertEquals(-15, adjustedBy)
            assertEquals(true, stopped)
        }
    }

    @Test
    fun restControlsAreHiddenOnceTheRestTimerEnds() {
        setActiveWorkoutContent(uiState = completedThenPendingState(restSecondsRemaining = 0))

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_stop)
        ).assertDoesNotExist()
    }

    @Test
    fun longPressOnLatestCompletedRowOffersUndoForThatSet() {
        var undoneSetId: String? = null
        setActiveWorkoutContent(
            uiState = completedThenPendingState(restSecondsRemaining = 0),
            onUndoLatestSet = { undoneSetId = it }
        )

        composeRule.onNodeWithTag(activeWorkoutCompletedSetTag("set-1")).performScrollTo()
            .performTouchInput { longClick(Offset(8f, 8f)) }
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_undo_action)
        ).performClick()

        composeRule.runOnIdle { assertEquals("set-1", undoneSetId) }
    }

    @Test
    fun screenEntryCollapsesAnExerciseWithoutTheLatestSetAndKeepsTheLatestOneOpen() {
        setActiveWorkoutContent(uiState = twoCompletedSetsState())
        composeRule.onNodeWithTag(activeWorkoutCompletedSetTag("set-2")).assertExists()
    }

    @Test
    fun fullyRecordedExerciseWithoutTheLatestSetStartsCollapsedAndCanBeExpanded() {
        setActiveWorkoutContent(uiState = twoCompletedSetsState().copy(latestCompletedSetId = null))

        composeRule.onNodeWithTag(activeWorkoutCompletedSetTag("set-2")).assertDoesNotExist()
        composeRule.onNodeWithContentDescription("Bench Press").performClick()
        composeRule.onNodeWithTag(activeWorkoutCompletedSetTag("set-2")).assertExists()
    }

    @Test
    fun latestCompletedRowExposesUndoAsAnAccessibilityActionOnly() {
        var undoneSetId: String? = null
        setActiveWorkoutContent(
            uiState = twoCompletedSetsState(),
            onUndoLatestSet = { undoneSetId = it }
        )
        val undoLabel = composeRule.activity.getString(R.string.active_workout_undo_action)
        fun rowDescription(number: Int) = composeRule.activity.getString(
            R.string.active_workout_set_recorded_cd,
            number,
            composeRule.activity.getString(R.string.active_workout_set_summary, "60", "8")
        )

        val earlier = composeRule.onNodeWithContentDescription(rowDescription(1)).fetchSemanticsNode()
        assertEquals(false, SemanticsActions.CustomActions in earlier.config)

        val latest = composeRule.onNodeWithContentDescription(rowDescription(2)).fetchSemanticsNode()
        val undo = latest.config[SemanticsActions.CustomActions].single { it.label == undoLabel }
        composeRule.runOnUiThread { undo.action() }

        composeRule.runOnIdle { assertEquals("set-2", undoneSetId) }
    }

    @Test
    fun restControlsAndUndoAreDisabledWhileAWorkoutMutationIsInFlight() {
        setActiveWorkoutContent(
            uiState = completedThenPendingState(restSecondsRemaining = 30)
                .copy(setRecordingsInFlight = setOf("set-2"))
        )

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_add)
        ).performScrollTo().assertIsNotEnabled()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_rest_stop)
        ).performScrollTo().assertIsNotEnabled()
        val description = composeRule.activity.getString(
            R.string.active_workout_set_recorded_cd,
            1,
            composeRule.activity.getString(R.string.active_workout_set_summary, "60", "8")
        )
        val row = composeRule.onNodeWithContentDescription(description).fetchSemanticsNode()
        assertEquals(false, SemanticsActions.CustomActions in row.config)
    }

    @Test
    fun loggingASetShowsOneConfirmationBannerThatAnnouncesTheRest() {
        setActiveWorkoutContent(uiState = singlePendingSetState())

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.action_log_set_and_rest, "1:30")
        ).performScrollTo().performClick()

        val summary = composeRule.activity.getString(R.string.active_workout_set_summary, "60", "8")
        val message = composeRule.activity.getString(R.string.active_workout_recorded_banner, summary)
        val announcement = composeRule.activity.getString(
            R.string.active_workout_recorded_announcement,
            message,
            "1:30"
        )
        composeRule.onNodeWithTag(ACTIVE_WORKOUT_RECORDED_BANNER_TAG).assertIsDisplayed()
        composeRule.onNodeWithText(message).assertIsDisplayed()
        composeRule.onNodeWithContentDescription(announcement).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.voice_command_undo)
        ).assertIsDisplayed()

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.action_dismiss)
        ).performClick()
        composeRule.onNodeWithTag(ACTIVE_WORKOUT_RECORDED_BANNER_TAG).assertDoesNotExist()
    }

    @Test
    fun finishWithUnrecordedSetsAsksBeforeLoggingOrSkipping() {
        var saved = 0
        var skipped = 0
        setActiveWorkoutContent(
            uiState = singlePendingSetState(canSkipRemaining = true),
            onSaveExercise = { saved++ },
            onSkipRemainingSets = { skipped++ }
        )

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_add_set)
        ).assertIsDisplayed()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_save_exercise)
        ).performScrollTo().performClick()

        composeRule.onNodeWithText(
            composeRule.activity.resources.getQuantityString(
                R.plurals.active_workout_finish_sets_left,
                1,
                1
            )
        ).assertIsDisplayed()
        assertEquals(0, saved)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_finish_skip_them)
        ).performClick()
        assertEquals(1, skipped)
        assertEquals(0, saved)
    }

    @Test
    fun finishDialogLogsAsPlannedAndHidesSkipWhenNoSkipCandidateExists() {
        var saved = 0
        setActiveWorkoutContent(
            uiState = singlePendingSetState(canSkipRemaining = false),
            onSaveExercise = { saved++ }
        )

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.active_workout_save_exercise)
        ).performScrollTo().performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_finish_skip_them)
        ).assertDoesNotExist()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.active_workout_finish_log_as_planned)
        ).performClick()
        assertEquals(1, saved)
    }

    private fun singlePendingSetState(canSkipRemaining: Boolean = false) = ActiveWorkoutUiState(
        isLoading = false,
        exercises = listOf(
            ActiveWorkoutExerciseUiState(
                id = "exercise-1",
                exerciseId = null,
                exerciseName = "Bench Press",
                orderIndex = 0,
                restDurationSeconds = 90,
                canSkipRemaining = canSkipRemaining,
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
    )

    /** set-1 is the latest completed set; set-2 is the current one. */
    private fun completedThenPendingState(restSecondsRemaining: Int) = ActiveWorkoutUiState(
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
        restSecondsRemaining = restSecondsRemaining
    )

    /** set-1 and set-2 are both completed; only set-2 is the latest. */
    private fun twoCompletedSetsState() = ActiveWorkoutUiState(
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
                        isCompleted = true,
                        completedAt = 2L
                    )
                )
            )
        ),
        completedSetCount = 2,
        totalSetCount = 2,
        latestCompletedSetId = "set-2"
    )

    private fun setActiveWorkoutContent(
        uiState: ActiveWorkoutUiState,
        onRecordSet: (String) -> Unit = {},
        onUndoLatestSet: (String) -> Unit = {},
        onAdjustRestTimer: (Int) -> Unit = {},
        onStopRestTimer: () -> Unit = {},
        onSaveExercise: (String) -> Unit = {},
        onSkipRemainingSets: (String) -> Unit = {}
    ) {
        composeRule.setContent {
            GymAppTheme {
                ActiveWorkoutScreen(
                    uiState = uiState,
                    exerciseMediaOwnerKey = "active-workout-test",
                    onSetWeightChanged = { _, _ -> },
                    onSetRepsChanged = { _, _ -> },
                    onSaveExercise = onSaveExercise,
                    onAddSet = {},
                    onSkipRemainingSets = onSkipRemainingSets,
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
