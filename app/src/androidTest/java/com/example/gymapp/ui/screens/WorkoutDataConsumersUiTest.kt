package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.LocalizedText
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkoutDataConsumersUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun missionsAndRanksExposeRecoverableLoadFailure() {
        var missionRetries = 0
        val showRanks = mutableStateOf(false)
        val state = mutableStateOf(WorkoutListUiState(isLoading = true))
        composeRule.setContent {
            GymAppTheme {
                if (showRanks.value) {
                    RanksScreen(
                        uiState = state.value,
                        onRetryLoad = { missionRetries += 1 }
                    )
                } else {
                    MissionsScreen(
                        uiState = state.value,
                        onRetryLoad = { missionRetries += 1 }
                    )
                }
            }
        }

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workouts_loading)
        ).assertIsDisplayed()
        composeRule.runOnIdle { state.value = failedWorkoutState() }
        assertRetrySurfaceAndClick()
        composeRule.runOnIdle {
            showRanks.value = true
            state.value = WorkoutListUiState(isLoading = true)
        }
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workouts_loading)
        ).assertIsDisplayed()
        composeRule.runOnIdle { state.value = failedWorkoutState() }
        assertRetrySurfaceAndClick()
        composeRule.runOnIdle { assertEquals(2, missionRetries) }
    }

    @Test
    fun progressKeepsSectionControlsAvailableWhileOverviewCanRetry() {
        var retries = 0
        composeRule.setContent {
            GymAppTheme {
                ProgressHubScreen(
                    overviewState = failedWorkoutState(),
                    exerciseState = ExerciseProgressUiState(),
                    exerciseMediaOwnerKey = "synthetic-owner",
                    onSelectExercise = {},
                    onPreviousExerciseMonth = {},
                    onCurrentExerciseMonth = {},
                    onNextExerciseMonth = {},
                    onPreviousOverviewMonth = {},
                    onCurrentOverviewMonth = {},
                    onNextOverviewMonth = {},
                    onMuscleMapPeriodSelected = {},
                    onMuscleSelected = {},
                    onOpenRanks = {},
                    onRetryOverviewLoad = { retries += 1 }
                )
            }
        }

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.progress_section_overview)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.progress_section_exercises)
        ).assertIsDisplayed()
        assertRetrySurfaceAndClick()
        composeRule.runOnIdle { assertEquals(1, retries) }
    }

    private fun assertRetrySurfaceAndClick() {
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workouts_load_failed)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_retry)
        ).assertIsDisplayed().performClick()
    }

    private fun failedWorkoutState() = WorkoutListUiState(
        loadError = LocalizedText(R.string.workouts_load_failed)
    )
}
