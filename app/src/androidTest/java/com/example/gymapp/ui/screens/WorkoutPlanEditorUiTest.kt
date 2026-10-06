package com.example.gymapp.ui.screens

import androidx.compose.runtime.key
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.espresso.Espresso.pressBack
import androidx.activity.ComponentActivity
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
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun cleanInitialDraftNavigatesToHistoryWithoutDiscarding() {
        var navigateCount = 0
        var discardCount = 0
        setEditorContent(
            isDirty = false,
            onNavigateToHistory = { navigateCount += 1 },
            onDiscard = { discardCount += 1 }
        )

        pressBack()

        composeRule.runOnIdle {
            assertEquals(1, navigateCount)
            assertEquals(0, discardCount)
        }
        composeRule.onNodeWithText(discardTitle()).assertDoesNotExist()
    }

    @Test
    fun mutatedDraftSurvivesBackAndOnlyExplicitDiscardResetsIt() {
        var navigateCount = 0
        var discardCount = 0
        setEditorContent(
            isDirty = true,
            onNavigateToHistory = { navigateCount += 1 },
            onDiscard = { discardCount += 1 }
        )

        pressBack()
        composeRule.runOnIdle {
            assertEquals(1, navigateCount)
            assertEquals(0, discardCount)
        }
        composeRule.onNodeWithText(discardTitle()).assertDoesNotExist()

        openDiscardAction(hasDrafts = false)
        composeRule.onNodeWithText(discardTitle()).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_keep_editing)
        ).performClick()
        composeRule.runOnIdle { assertEquals(0, discardCount) }
        composeRule.onNodeWithText(discardTitle()).assertDoesNotExist()

        composeRule.onNodeWithTag("workout_plan_discard_draft").performClick()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_discard_changes)
        ).performClick()
        composeRule.runOnIdle { assertEquals(1, discardCount) }
    }

    @Test
    fun hydratedCleanDraftStillConfirmsEveryExplicitDiscard() {
        var discardCount = 0
        setEditorContent(
            isDirty = false,
            drafts = listOf(ExerciseInputState(draftId = 1L)),
            onDiscard = { discardCount += 1 }
        )

        openDiscardAction(hasDrafts = true)

        composeRule.onNodeWithText(discardTitle()).assertIsDisplayed()
        composeRule.runOnIdle { assertEquals(0, discardCount) }
    }

    @Test
    fun clearPlanRequiresConfirmationAndKeepPlanDoesNotMutate() {
        var clearCount = 0
        setEditorContent(
            isDirty = false,
            drafts = listOf(ExerciseInputState(draftId = 1L)),
            onClear = { clearCount += 1 }
        )

        openClearPlanMenu()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_clear_title)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_clear_keep)
        ).performClick()
        composeRule.runOnIdle { assertEquals(0, clearCount) }

        openClearPlanMenu()
        composeRule.onAllNodesWithText(clearAction()).onLast().performClick()
        composeRule.runOnIdle { assertEquals(1, clearCount) }
    }

    @Test
    fun emptyPlanOffersOneAddAndKeepsCoachAsTheOnlyBuildAction() {
        setEditorContent(isDirty = true, drafts = emptyList())

        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(2)
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.action_add_exercise)
        ).assertCountEquals(1)
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.action_generate_smart_workout)
        ).assertCountEquals(1)
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(3)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.action_start_workout)
        ).assertIsNotEnabled()
    }

    @Test
    fun draftCardUsesSharedSetEditorWithDashedFootersAndOneMenu() {
        var addCount = 0
        setEditorContent(
            isDirty = true,
            drafts = listOf(ExerciseInputState(draftId = 1L)),
            onAddExercise = { addCount += 1 }
        )

        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(2)
        // Header menu, the selector trigger and the "+ Set" footer sit on the card.
        composeRule.onNodeWithTag("workout_plan_exercise_menu").assertIsDisplayed()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.label_select_exercise)
        ).assertIsDisplayed()
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.action_add_planned_set)
        ).assertIsDisplayed()
        // The set uses the shared capsules: a named trash button, with no "+2.5" chip.
        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(
                R.string.cd_delete_set_named,
                1,
                composeRule.activity.getString(R.string.exercise_block_title, 1)
            )
        ).assertIsDisplayed()
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.editor_chip_plus_step)
        ).assertCountEquals(0)
        // "+ Add exercise" closes the exercise list and reuses the header "+" flow.
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(3)
        composeRule.onNodeWithTag("workout_plan_add_exercise_footer").performClick()
        composeRule.runOnIdle { assertEquals(1, addCount) }
    }

    @Test
    fun editorStartsWithCompactCoachRowsAndNoDuplicatePlanHero() {
        setEditorContent(isDirty = false)

        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.title_workout_plan)
        ).assertCountEquals(0)
        // Coach settings are one summary line inside the Smart coach card, not a separate card.
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.training_profile_title)
        ).assertCountEquals(0)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.training_settings_edit)
        ).assertIsDisplayed()
        composeRule.onAllNodesWithText(
            composeRule.activity.getString(R.string.smart_coach_title)
        ).assertCountEquals(1)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.smart_coach_effort_title)
        ).assertDoesNotExist()
    }

    @Test
    fun directLiveSendBlocksEditorMutationsAndBackUntilSettlement() {
        var navigateCount = 0
        var addCount = 0
        var interactionLocked = false
        setEditorContent(
            isDirty = true,
            drafts = listOf(ExerciseInputState(draftId = 1L)),
            isLiveInviteSending = true,
            onNavigateToHistory = { navigateCount += 1 },
            onAddExercise = { addCount += 1 },
            onInteractionLockChanged = { interactionLocked = it }
        )

        composeRule.onNodeWithTag("workout_plan_editor_locked")
            .assertIsDisplayed()
            .assertIsNotEnabled()
        pressBack()

        composeRule.runOnIdle {
            assertEquals(0, navigateCount)
            assertEquals(0, addCount)
            assertEquals(true, interactionLocked)
        }
    }

    private fun discardTitle(): String =
        composeRule.activity.getString(R.string.workout_plan_discard_title)

    private fun clearAction(): String =
        composeRule.activity.getString(R.string.workout_plan_clear_action)

    private fun openClearPlanMenu() {
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(1)
        composeRule.onNodeWithTag("workout_plan_exercises_menu").performClick()
        composeRule.onNodeWithText(clearAction()).performClick()
    }

    /** With drafts the list also holds the trailing "+ Add exercise" item, which shifts later rows by one. */
    private fun openDiscardAction(hasDrafts: Boolean) {
        val shift = if (hasDrafts) 1 else 0
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(4 + shift)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.workout_plan_more_options)
        ).performClick()
        composeRule.onNodeWithTag("workout_plan_editor_list").performScrollToIndex(8 + shift)
        composeRule.onNodeWithTag("workout_plan_discard_draft").performClick()
    }

    private fun setEditorContent(
        isDirty: Boolean,
        drafts: List<ExerciseInputState> = emptyList(),
        isLiveInviteSending: Boolean = false,
        onNavigateToHistory: () -> Unit = {},
        onDiscard: () -> Unit = {},
        onClear: () -> Unit = {},
        onAddExercise: () -> Unit = {},
        onInteractionLockChanged: (Boolean) -> Unit = {}
    ) {
        val contentKey = System.nanoTime()
        composeRule.setContent {
            key(contentKey) {
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
                    onAddExerciseDraft = onAddExercise,
                    onClearPlan = onClear,
                    onRemoveExerciseDraft = {},
                    onExerciseSelected = { _, _ -> },
                    onAddSet = {},
                    onRemoveSet = { _, _ -> },
                    onSetWeightChanged = { _, _, _ -> },
                    onSetRepsChanged = { _, _, _ -> },
                    onApplyLastWeightToSet = { _, _ -> },
                    onCopyPreviousSet = { _, _ -> },
                    onAddWeightToSet = { _, _ -> },
                    onDuplicateSet = { _, _ -> },
                    onApplyWorkoutRecommendation = {},
                    onRepeatLastWorkout = {},
                    onOpenTemplatePicker = {},
                    onCloseTemplatePicker = {},
                    onCopyWorkoutTemplate = {},
                    onSyncPlanToWatch = {},
                    onShareWorkout = {},
                    liveInviteTargetName = if (isLiveInviteSending) "Training Friend" else null,
                    hasLiveInviteTarget = isLiveInviteSending,
                    isLiveInviteSending = isLiveInviteSending,
                    onStartWorkout = {},
                    onNavigateToHistory = onNavigateToHistory,
                    onDiscardPlan = onDiscard,
                    externalCloseRequestVersion = 0L,
                    onExternalCloseRequestHandled = {},
                    onDirtyStateChanged = {},
                    onInteractionLockChanged = onInteractionLockChanged
                    )
                }
            }
        }
        composeRule.waitForIdle()
    }
}
