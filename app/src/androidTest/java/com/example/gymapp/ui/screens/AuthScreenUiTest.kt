package com.example.gymapp.ui.screens

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.example.gymapp.R
import com.example.gymapp.auth.AuthUiState
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.util.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import androidx.compose.ui.unit.dp

class AuthScreenUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun languageMenuExposesEnglishUkrainianAndRussian() {
        setAuthContent()

        composeRule.onNodeWithContentDescription(
            composeRule.activity.getString(R.string.cd_language)
        ).performClick()

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.language_name_english)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.language_name_ukrainian)
        ).assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.language_name_russian)
        ).assertIsDisplayed()
    }

    @Test
    fun offlineSheetCancelDoesNotCreateProfile() {
        var localContinuations = 0
        setAuthContent(onContinueLocal = { _, _ -> localContinuations += 1 })

        val continueOffline = composeRule.activity.getString(R.string.auth_continue_offline)
        val offlineProfile = composeRule.activity.getString(R.string.auth_offline_profile)
        val cancel = composeRule.activity.getString(R.string.action_cancel)
        composeRule.onNodeWithText(continueOffline).performClick()
        composeRule.onNodeWithText(offlineProfile).assertIsDisplayed()
        composeRule.onNodeWithText(cancel).performClick()

        composeRule.onNodeWithText(offlineProfile).assertDoesNotExist()
        assertEquals(0, localContinuations)
    }

    @Test
    fun legalPanelKeepsBothLocalizedActionsVisible() {
        setAuthContent()

        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.auth_legal_consequence)
        ).performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.auth_privacy_policy)
        ).assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        composeRule.onNodeWithText(
            composeRule.activity.getString(R.string.auth_support)
        ).assertIsDisplayed().assertHeightIsAtLeast(48.dp)
    }

    private fun setAuthContent(onContinueLocal: (String, Boolean) -> Unit = { _, _ -> }) {
        composeRule.setContent {
            GymAppTheme {
                AuthScreen(
                    uiState = AuthUiState(),
                    selectedLanguage = AppLanguage.EN,
                    onLanguageSelected = {},
                    onLogin = { _, _ -> },
                    onSignUp = { _, _, _ -> },
                    onResendConfirmation = {},
                    onDismissEmailConfirmation = {},
                    onPasswordReset = {},
                    savedLocalProfiles = emptyList(),
                    onContinueLocal = onContinueLocal
                )
            }
        }
    }
}
