package com.example.gymapp.ui.screens

import androidx.activity.compose.setContent
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import com.example.gymapp.MainActivity
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.ActiveWorkoutUiState
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ActiveWorkoutHeroUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun heroShowsBalancedElapsedCompletedAndStartedMetricsWithProgressSemantics() {
        val startedAt = Instant.parse("2026-08-24T14:05:00Z").toEpochMilli()
        val locale = composeRule.activity.resources.configuration.locales[0]
        composeRule.activity.setContent {
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
                    onRecordAllPendingSets = {},
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
                formatActiveWorkoutStartedAt(startedAt, locale)
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
}
