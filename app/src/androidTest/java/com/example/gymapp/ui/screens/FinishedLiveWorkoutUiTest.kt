package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.example.gymapp.R
import com.example.gymapp.auth.*
import com.example.gymapp.ui.theme.GymAppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class FinishedLiveWorkoutUiTest {
    @get:Rule val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test fun finishedRoomHasTwoReadOnlyTabsAndRefreshDoesNotCreateEditors() {
        var refreshes = 0
        var closes = 0
        val timestamp = "2026-08-10T10:00:00Z"
        val self = LiveParticipant(true, LiveProfile("p_${"1".repeat(32)}", "Preview Self"),
            "owner", "finished", 3, timestamp, timestamp, null,
            LiveProgress(3, listOf(LiveCompletedSet("s_01_01", 82.5, 7, timestamp)), null, timestamp))
        val peer = LiveParticipant(false, LiveProfile("p_${"2".repeat(32)}", "Preview Friend"),
            "participant", "joined", 2, timestamp, null, null, LiveProgress(1, emptyList(), null, null))
        val snapshot = LiveWorkoutSnapshot(
            LiveRoomSnapshot("lr_${"a".repeat(32)}", "active", 5, null, timestamp, timestamp,
                timestamp, "2026-08-11T10:00:00Z", null, LiveWorkoutSummary(1, 2, listOf("Bench Press"))),
            LiveCanonicalPlan(listOf(LiveCanonicalExercise("e_01", "Bench Press", "bench_press",
                listOf(LiveCanonicalSet("s_01_01", 80.0, 8), LiveCanonicalSet("s_01_02", 80.0, 8))))),
            listOf(self, peer)
        )
        composeRule.setContent {
            GymAppTheme {
                FinishedLiveWorkoutDialog(snapshot, onRefresh = { refreshes++ }, onDismiss = { closes++ })
            }
        }
        composeRule.onNodeWithText("Preview Self").assertIsDisplayed()
        composeRule.onNodeWithText(composeRule.activity.getString(R.string.live_workout_member_finished)).assertIsDisplayed()
        composeRule.onNodeWithText(composeRule.activity.getString(R.string.live_workout_peer_set_completed, "82.5", 7)).assertIsDisplayed()
        composeRule.onNodeWithText("Preview Friend").assertIsDisplayed().performClick()
        composeRule.onAllNodes(hasSetTextAction()).assertCountEquals(0)
        composeRule.onNodeWithText("Preview Self").performClick()
        composeRule.onNodeWithText(composeRule.activity.getString(R.string.action_refresh)).performClick()
        composeRule.runOnIdle { assertEquals(1, refreshes) }
        composeRule.onAllNodes(hasSetTextAction()).assertCountEquals(0)
        composeRule.onNodeWithText(composeRule.activity.getString(R.string.action_close)).performClick()
        composeRule.runOnIdle { assertEquals(1, closes) }
    }
}
