package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingProgramStore
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.util.UUID

class TrainingProgramUiTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    private val owner = "program-ui-" + UUID.randomUUID()
    private fun label(id: Int) = rule.activity.getString(id)
    private fun action(id: Int) = rule.onNodeWithText(label(id))
    private fun store() = TrainingProgramStore(rule.activity, owner)

    @After fun cleanup() { store().clear() }

    @Test fun largeTextProgramHasConfirmedFinishResumeAndNewCycle() {
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 1.5f)) {
                GymAppTheme { TrainingProgramCard(owner, emptyList(), TrainingProfile(workoutsPerWeek = 3), {}) }
            }
        }
        action(R.string.training_program_create).assertIsDisplayed().performClick()
        val original = store().load()!!.id
        action(R.string.training_program_prepare).performScrollTo().assertIsDisplayed()
        action(R.string.training_program_options).performScrollTo().performClick()
        action(R.string.training_program_finish).performScrollTo().performClick()
        assertEquals("active", store().load()!!.status)
        rule.onNode(hasText(label(R.string.training_program_finish)) and hasAnyAncestor(isDialog())).performClick()
        action(R.string.training_program_new).assertIsDisplayed()
        action(R.string.training_program_reopen).performScrollTo().performClick()
        assertEquals(original, store().load()!!.id)
        assertEquals("active", store().load()!!.status)
        action(R.string.training_program_options).performScrollTo().performClick()
        action(R.string.training_program_finish).performScrollTo().performClick()
        rule.onNode(hasText(label(R.string.training_program_finish)) and hasAnyAncestor(isDialog())).performClick()
        action(R.string.training_program_new).performClick()
        action(R.string.training_program_new_title).assertIsDisplayed()
        assertEquals(original, store().load()!!.id)
        rule.onNode(hasText(label(R.string.training_program_create)) and hasAnyAncestor(isDialog())).performClick()
        assertNotEquals(original, store().load()!!.id)
        assertEquals("active", store().load()!!.status)
        action(R.string.training_program_prepare).performScrollTo().assertIsDisplayed()
    }
}
