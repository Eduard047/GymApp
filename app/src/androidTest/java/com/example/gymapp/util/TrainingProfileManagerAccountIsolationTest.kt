package com.example.gymapp.util

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.auth.AccountSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TrainingProfileManagerAccountIsolationTest {
    @Test
    fun localProfileKeysSeparateFormerFilenameCollisions() {
        assertNotEquals(
            trainingProfileAccountKey(AccountSession.Local("a/b")),
            trainingProfileAccountKey(AccountSession.Local("a_b"))
        )
        assertNotEquals(
            trainingProfileAccountKey(AccountSession.Local("Іван")),
            trainingProfileAccountKey(AccountSession.Local("Олег"))
        )
        assertEquals(
            trainingProfileAccountKey(AccountSession.Local(" Alice ")),
            trainingProfileAccountKey(AccountSession.Local("alice"))
        )
    }

    @Test
    fun accountSwitchNeverReusesAnotherAccountsFitnessProfile() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clearPreferences(context)
        val manager = TrainingProfileManager(context)
        val accountA = AccountSession.Local("Alice")
        val accountB = AccountSession.Local("Bob")

        try {
            manager.switchAccount(accountA)
            manager.updateSplit(TrainingSplit.PushPullLegs)
            manager.updateWorkoutsPerWeek(6)
            manager.updateGoal(TrainingGoal.Strength)
            manager.updateCalorieMode(CalorieMode.Surplus)
            val profileA = manager.profile.value

            manager.switchAccount(accountB)
            assertEquals(TrainingProfile(), manager.profile.value)
            manager.updateSplit(TrainingSplit.FullBody)
            manager.updateGoal(TrainingGoal.MuscleGain)
            val profileB = manager.profile.value

            manager.switchAccount(null)
            assertEquals(TrainingProfile(), manager.profile.value)
            manager.updateGoal(TrainingGoal.Strength)
            assertEquals(TrainingProfile(), manager.profile.value)

            manager.switchAccount(AccountSession.Local(" alice "))
            assertEquals(profileA, manager.profile.value)
            manager.switchAccount(accountB)
            assertEquals(profileB, manager.profile.value)
            assertNotEquals(profileA, profileB)
        } finally {
            clearPreferences(context)
        }
    }

    @Test
    fun cloudProfileUsesStableUserIdentityNotTokensOrLoginGeneration() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clearPreferences(context)
        val firstLogin = cloudSession(
            userId = "11111111-1111-4111-8111-111111111111",
            accessToken = "first-token",
            sessionGeneration = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        )
        val sameUserNewLogin = cloudSession(
            userId = firstLogin.userId,
            accessToken = "second-token",
            sessionGeneration = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        )
        val otherUser = cloudSession(
            userId = "22222222-2222-4222-8222-222222222222",
            accessToken = "third-token",
            sessionGeneration = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        )
        val manager = TrainingProfileManager(context)

        try {
            assertEquals(
                trainingProfileAccountKey(firstLogin),
                trainingProfileAccountKey(sameUserNewLogin)
            )
            assertNotEquals(
                trainingProfileAccountKey(firstLogin),
                trainingProfileAccountKey(otherUser)
            )

            manager.switchAccount(firstLogin)
            manager.updateGoal(TrainingGoal.Strength)
            manager.switchAccount(sameUserNewLogin)
            assertEquals(TrainingGoal.Strength, manager.profile.value.goal)
            manager.switchAccount(otherUser)
            assertEquals(TrainingProfile(), manager.profile.value)

            val storedKeys = context.getSharedPreferences(SCOPED_PREFS, Context.MODE_PRIVATE).all.keys
            assertTrue(storedKeys.isNotEmpty())
            assertFalse(storedKeys.any { key ->
                key.contains(firstLogin.userId) ||
                    key.contains(firstLogin.accessToken) ||
                    key.contains(firstLogin.email)
            })
        } finally {
            clearPreferences(context)
        }
    }

    @Test
    fun legacyUnownedProfileIsDiscardedInsteadOfAssignedToNextLogin() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clearPreferences(context)
        context.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("goal", TrainingGoal.Strength.name)
            .putInt("workouts_per_week", 6)
            .commit()

        try {
            val manager = TrainingProfileManager(context)
            assertTrue(context.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE).all.isEmpty())
            manager.switchAccount(AccountSession.Local("Next user"))
            assertEquals(TrainingProfile(), manager.profile.value)
        } finally {
            clearPreferences(context)
        }
    }

    @Test
    fun corruptScopedValuesFailBackToCanonicalDefaultsWithoutChangingValidAccounts() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clearPreferences(context)
        val corruptAccount = AccountSession.Local("Corrupt")
        val validAccount = AccountSession.Local("Valid")
        val corruptKey = requireNotNull(trainingProfileAccountKey(corruptAccount))
        context.getSharedPreferences(SCOPED_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt("$corruptKey:split", 7)
            .putInt("$corruptKey:workouts_per_week", 999)
            .putString("$corruptKey:goal", "Unknown")
            .putBoolean("$corruptKey:calorie_mode", true)
            .commit()
        val manager = TrainingProfileManager(context)

        try {
            manager.switchAccount(corruptAccount)
            assertEquals(TrainingProfile(), manager.profile.value)
            manager.switchAccount(validAccount)
            assertTrue(
                manager.updateProfile(
                    TrainingProfile(
                        split = TrainingSplit.FullBody,
                        workoutsPerWeek = 3,
                        goal = TrainingGoal.Balanced,
                        calorieMode = CalorieMode.Maintenance
                    )
                )
            )
            manager.switchAccount(corruptAccount)
            assertEquals(TrainingProfile(), manager.profile.value)
            manager.switchAccount(validAccount)
            assertEquals(TrainingSplit.FullBody, manager.profile.value.split)
        } finally {
            clearPreferences(context)
        }
    }

    private fun cloudSession(
        userId: String,
        accessToken: String,
        sessionGeneration: String
    ): AccountSession.Cloud {
        return AccountSession.Cloud(
            userId = userId,
            email = "$userId@example.invalid",
            displayName = "User",
            accessToken = accessToken,
            refreshToken = "refresh-$accessToken",
            sessionGeneration = sessionGeneration
        )
    }

    private fun clearPreferences(context: Context) {
        context.deleteSharedPreferences(LEGACY_PREFS)
        context.deleteSharedPreferences(SCOPED_PREFS)
    }

    private companion object {
        const val LEGACY_PREFS = "gym_training_profile"
        const val SCOPED_PREFS = "gym_training_profiles"
    }
}
