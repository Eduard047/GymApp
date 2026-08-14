package com.example.gymapp.ui.components

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.platform.testTag
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymAppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalTestApi::class)
class FirstRunTutorialOverlayUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun activeTutorialHidesUnderlyingSemantics() {
        composeRule.setContent {
            GymAppTheme {
                Box(Modifier.fillMaxSize()) {
                    Button(
                        onClick = {},
                        modifier = Modifier
                            .testTag(UNDERLYING_TAG)
                            .semantics { hideFromAccessibility() }
                    ) {
                        Text("Underlying")
                    }
                    TutorialOverlayForTest()
                }
            }
        }

        composeRule.onNodeWithTag(UNDERLYING_TAG).assert(
            SemanticsMatcher.keyIsDefined(SemanticsProperties.HideFromAccessibility)
        )
        composeRule.onNodeWithTag(TUTORIAL_CARD_TAG).assertIsDisplayed()
    }

    @Test
    fun keyboardTraversalCannotEscapeTutorialCard() {
        composeRule.setContent {
            GymAppTheme {
                Box(Modifier.fillMaxSize()) {
                    Button(
                        onClick = {},
                        modifier = Modifier.testTag(OUTSIDE_FOCUS_TAG)
                    ) {
                        Text("Outside")
                    }
                    TutorialOverlayForTest()
                }
            }
        }

        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule
                .onAllNodes(
                    tutorialCardFocusMatcher(),
                    useUnmergedTree = true
                )
                .fetchSemanticsNodes()
                .size == 1
        }

        repeat(8) {
            composeRule.onNodeWithTag(TUTORIAL_CARD_TAG).performKeyInput {
                pressKey(Key.Tab)
            }
            composeRule.onNodeWithTag(OUTSIDE_FOCUS_TAG).assertIsNotFocused()
        }
        repeat(8) {
            composeRule.onNodeWithTag(TUTORIAL_CARD_TAG).performKeyInput {
                keyDown(Key.ShiftLeft)
                pressKey(Key.Tab)
                keyUp(Key.ShiftLeft)
            }
            composeRule.onNodeWithTag(OUTSIDE_FOCUS_TAG).assertIsNotFocused()
        }
        composeRule
            .onAllNodes(
                tutorialCardFocusMatcher(),
                useUnmergedTree = true
            )
            .assertCountEquals(1)
    }

    @Test
    fun completionSaveFailureKeepsLocalizedRetryActionAvailable() {
        var doneCount = 0
        composeRule.setContent {
            GymAppTheme {
                TutorialOverlayForTest(
                    stepIndex = FIRST_RUN_TUTORIAL_STEPS.lastIndex,
                    onDone = { doneCount += 1 }
                )
            }
        }

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.tutorial_completion_save_failed)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.tutorial_done)
        ).performClick()
        composeRule.runOnIdle { assertEquals(1, doneCount) }
    }

    @androidx.compose.runtime.Composable
    private fun TutorialOverlayForTest(
        stepIndex: Int = 0,
        onDone: () -> Unit = {}
    ) {
        FirstRunTutorialOverlay(
            stepIndex = stepIndex,
            registry = TutorialAnchorRegistry(),
            showCompletionSaveError = true,
            onBack = {},
            onNext = {},
            onSkip = {},
            onDone = onDone,
            modifier = Modifier.fillMaxSize()
        )
    }

    private fun tutorialCardFocusMatcher() =
        (hasTestTag(TUTORIAL_CARD_TAG) or hasAnyAncestor(hasTestTag(TUTORIAL_CARD_TAG))) and
            isFocused()

    private companion object {
        const val UNDERLYING_TAG = "tutorial_underlying_action"
        const val OUTSIDE_FOCUS_TAG = "tutorial_outside_focus_target"
        const val TUTORIAL_CARD_TAG = "first_run_tutorial_card"
    }
}
