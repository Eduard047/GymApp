package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.example.gymapp.R
import com.example.gymapp.data.entity.*
import com.example.gymapp.data.repository.SetDeletionImpact
import com.example.gymapp.data.repository.SetDeletionSnapshot
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class FreeWorkoutUiTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Test fun removingLastManualSetExplainsThatWatchMetricsRemain() {
        val snapshot = SetDeletionSnapshot(
            setId = 401, workoutExerciseId = 301, workoutSessionId = 201,
            exerciseId = 101, exerciseName = "Bench Press", sessionDate = 1_788_685_200_000,
            weight = 55.0, reps = 12, orderIndex = 0, displayOrdinal = 1,
            setsInExerciseBlock = 1, exerciseBlocksInWorkout = 1,
            impact = SetDeletionImpact.WorkoutSession, removedWorkoutExercise = null,
            removedWorkoutSession = null, removedGarminProvenance = null,
            deletionStoreToken = "free-ui-test", retainsRecordedActivity = true
        )
        rule.setContent {
            GymAppTheme {
                SetDeleteConfirmationDialog(snapshot, false, null, {}, {})
            }
        }
        rule.onNodeWithText(rule.activity.getString(R.string.dialog_delete_set_impact_watch_activity))
            .assertIsDisplayed()
        rule.onNodeWithText(rule.activity.getString(R.string.dialog_delete_set_impact_workout))
            .assertDoesNotExist()
    }

    @Test fun freeWorkoutOpensCatalogAndKeepsMetricsWhenExerciseIsAdded() {
        val exercise = ExerciseEntity(101, "Free test exercise")
        val session = WorkoutSessionEntity(
            id = 201,
            date = 1_788_685_200_000,
            note = "Garmin · Duration 12:34 · Gym kcal 40 · Avg HR 130 · Max HR 165",
            durationSeconds = 754
        )
        val state = mutableStateOf(WorkoutDetailUiState(
            sessionDetails = WorkoutSessionDetails(session, emptyList()),
            hasGarminReceipt = true,
            availableExercisesToAdd = listOf(exercise)
        ))
        rule.setContent {
            GymAppTheme {
                WorkoutDetailScreen(
                    uiState = state.value,
                    exerciseMediaOwnerKey = "free-ui-test",
                    events = emptyFlow(),
                    onAddExerciseToWorkout = { id ->
                        assertEquals(exercise.id, id)
                        state.value = state.value.copy(
                            sessionDetails = WorkoutSessionDetails(session, listOf(
                                WorkoutExerciseWithDetails(
                                    WorkoutExerciseEntity(id = 301, sessionId = session.id,
                                        exerciseId = id, orderIndex = 0),
                                    exercise,
                                    listOf(SetEntryEntity(id = 401, workoutExerciseId = 301,
                                        weight = 55.0, reps = 12, orderIndex = 0))
                                )
                            )),
                            availableExercisesToAdd = emptyList()
                        )
                    },
                    onAddSet = {}, onDeleteSet = {}, onConfirmDeleteSet = {},
                    onDismissDeleteSet = {}, onDeleteSession = {}, onSessionDeleted = {},
                    onUpdateSet = { _, _, _ -> }
                )
            }
        }
        fun action(id: Int) = rule.onNodeWithText(rule.activity.getString(id))
        action(R.string.action_complete_free_workout).assertIsDisplayed().performClick()
        action(R.string.label_select_exercise).performScrollTo().performClick()
        rule.onNodeWithText(exercise.name).assertIsDisplayed().performClick()
        action(R.string.action_add_to_workout).performScrollTo().performClick()
        rule.onNodeWithText(exercise.name).performScrollTo().assertIsDisplayed()
        rule.runOnIdle {
            assertEquals(session, state.value.sessionDetails!!.session)
            assertEquals(55.0, state.value.sessionDetails!!.workoutExercises.single().sets.single().weight, 0.0)
            assertEquals(12, state.value.sessionDetails!!.workoutExercises.single().sets.single().reps)
        }
        rule.onNodeWithText("12:34").performScrollTo().assertIsDisplayed()
    }
}
