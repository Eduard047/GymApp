package com.example.gymapp.ui.screens

import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.espresso.Espresso.pressBack
import com.example.gymapp.MainActivity
import com.example.gymapp.R
import com.example.gymapp.data.repository.SmartWorkoutEffort
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class WorkoutPlanEditorUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun cleanInitialDraftClosesWithoutDiscardDialog() {
        var discardCount = 0
        setEditorContent(isDirty = false, onDiscard = { discardCount += 1 })

        pressBack()

        composeRule.runOnIdle { assertEquals(1, discardCount) }
        composeRule.onNodeWithText(discardTitle()).assertDoesNotExist()
    }

    @Test
    fun mutatedDraftRequiresKeepEditingOrExplicitDiscard() {
        var discardCount = 0
        setEditorContent(isDirty = true, onDiscard = { discardCount += 1 })

        pressBack()
        composeRule.onNodeWithText(discardTitle()).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_keep_editing)
        ).performClick()
        composeRule.runOnIdle { assertEquals(0, discardCount) }
        composeRule.onNodeWithText(discardTitle()).assertDoesNotExist()

        pressBack()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_discard_changes)
        ).performClick()
        composeRule.runOnIdle { assertEquals(1, discardCount) }
    }

    @Test
    fun clearPlanRequiresConfirmationAndKeepPlanDoesNotMutate() {
        var clearCount = 0
        setEditorContent(
            isDirty = false,
            drafts = listOf(ExerciseInputState(draftId = 1L)),
            onClear = { clearCount += 1 }
        )

        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(2)
        composeRule.onNodeWithText(clearAction()).performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_clear_title)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_clear_keep)
        ).performClick()
        composeRule.runOnIdle { assertEquals(0, clearCount) }

        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(2)
        composeRule.onNodeWithText(clearAction()).performClick()
        composeRule.onAllNodesWithText(clearAction()).onLast().performClick()
        composeRule.runOnIdle { assertEquals(1, clearCount) }
    }

    @Test
    fun emptyPlanOffersOneAddAndKeepsCoachAsTheOnlyBuildAction() {
        setEditorContent(isDirty = true, drafts = emptyList())

        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(3)
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.action_add_exercise)
        ).assertCountEquals(1)
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.action_generate_smart_workout)
        ).assertCountEquals(1)
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(4)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_start_workout)
        ).assertIsNotEnabled()
    }

    @Test
    fun editorStartsWithCompactCoachRowsAndNoDuplicatePlanHero() {
        setEditorContent(isDirty = false)

        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.title_workout_plan)
        ).assertCountEquals(0)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_profile_title)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_profile_split)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_profile_goal)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_profile_calories)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_profile_frequency)
        ).assertIsDisplayed()
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.smart_coach_title)
        ).assertCountEquals(1)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.smart_coach_effort_title)
        ).assertDoesNotExist()
    }

    private fun discardTitle(): String =
        composeRule.activity.getString(R.string.workout_plan_discard_title)

    private fun clearAction(): String =
        composeRule.activity.getString(R.string.workout_plan_clear_action)

    private fun setEditorContent(
        isDirty: Boolean,
        drafts: List<ExerciseInputState> = emptyList(),
        onDiscard: () -> Unit = {},
        onClear: () -> Unit = {}
    ) {
        composeRule.activity.runOnUiThread {
            composeRule.activity.setContent {
                GymAppTheme {
                    AddWorkoutScreen(
                    uiState = AddWorkoutUiState(
                        isDirty = isDirty,
                        smartWorkoutEffort = SmartWorkoutEffort.Auto,
                        exerciseDrafts = drafts
                    ),
                    exerciseMediaOwnerKey = "test-owner",
                    onWorkoutDateSelected = {},
                    onNoteChange = {},
                    onTrainingSplitSelected = {},
                    onWorkoutsPerWeekSelected = {},
                    onTrainingGoalSelected = {},
                    onCalorieModeSelected = {},
                    onSmartWorkoutEffortSelected = {},
                    onGenerateSmartWorkout = {},
                    onOpenSmartAlternatives = {},
                    onCloseSmartAlternatives = {},
                    onApplySmartAlternative = { _, _, _ -> },
                    onAddExerciseDraft = {},
                    onClearPlan = onClear,
                    onRemoveExerciseDraft = {},
                    onExerciseSelected = { _, _ -> },
                    onAddSet = {},
                    onAddSetFromPrevious = { _, _ -> },
                    onRemoveSet = { _, _ -> },
                    onSetWeightChanged = { _, _, _ -> },
                    onSetRepsChanged = { _, _, _ -> },
                    onApplyLastWeight = {},
                    onApplyWorkoutRecommendation = {},
                    onRepeatLastWorkout = {},
                    onOpenTemplatePicker = {},
                    onCloseTemplatePicker = {},
                    onCopyWorkoutTemplate = {},
                    onSyncPlanToWatch = {},
                    onShareWorkout = {},
                    onStartWorkout = {},
                    onDiscardPlan = onDiscard,
                    externalCloseRequestVersion = 0L,
                    onExternalCloseRequestHandled = {},
                    onDirtyStateChanged = {}
                    )
                }
            }
        }
        composeRule.waitForIdle()
    }
}
