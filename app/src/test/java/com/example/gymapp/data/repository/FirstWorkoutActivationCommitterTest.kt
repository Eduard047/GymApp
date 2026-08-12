package com.example.gymapp.data.repository

import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FirstWorkoutActivationCommitterTest {
    private val previousProfile = TrainingProfile()
    private val targetProfile = TrainingProfile(
        split = TrainingSplit.FullBody,
        workoutsPerWeek = 3,
        goal = TrainingGoal.Strength,
        calorieMode = CalorieMode.Maintenance
    )

    @Test
    fun directActivationClaimsAndPersistsBeforeRoomStart() = runBlocking {
        val writes = mutableListOf<String>()
        var storedProfile = previousProfile
        var dismissed = false
        val started = FirstWorkoutActivationDirectStarter.start(
            plan = activationPlan(),
            token = "exact-plan",
            previousProfile = previousProfile,
            previousDismissed = false,
            claimAndPersist = { writes += "claim"; true },
            persistProfile = { storedProfile = it; writes += "profile"; true },
            persistDismissed = { dismissed = it; writes += "dismissal"; true },
            restoreProfile = { storedProfile = it; true },
            restoreDismissed = { dismissed = it; true },
            startActiveWorkout = { drafts ->
                writes += "room"
                assertEquals(0.0, drafts.single().sets.last().weight, 0.0)
                StartActiveWorkoutResult.Started
            }
        )
        assertTrue(started)
        assertEquals(targetProfile, storedProfile)
        assertTrue(dismissed)
        assertEquals(listOf("claim", "profile", "dismissal", "room"), writes)
    }

    @Test
    fun directActivationAlreadyActiveRollsBackAndRejectedClaimDoesNothing() = runBlocking {
        var storedProfile = previousProfile
        var dismissed = false
        val failed = FirstWorkoutActivationDirectStarter.start(
            plan = activationPlan(),
            token = "exact-plan",
            previousProfile = previousProfile,
            previousDismissed = false,
            claimAndPersist = { true },
            persistProfile = { storedProfile = it; true },
            persistDismissed = { dismissed = it; true },
            restoreProfile = { storedProfile = it; true },
            restoreDismissed = { dismissed = it; true },
            startActiveWorkout = { StartActiveWorkoutResult.AlreadyActive }
        )
        assertFalse(failed)
        assertEquals(previousProfile, storedProfile)
        assertFalse(dismissed)

        val rejected = FirstWorkoutActivationDirectStarter.start(
            plan = activationPlan(),
            token = "fresh-plan",
            previousProfile = previousProfile,
            previousDismissed = false,
            claimAndPersist = { false },
            persistProfile = { error("profile must not change") },
            persistDismissed = { error("dismissal must not change") },
            restoreProfile = { error("nothing changed") },
            restoreDismissed = { error("nothing changed") },
            startActiveWorkout = { error("Room must not be called") }
        )
        assertFalse(rejected)
    }

    @Test
    fun emptyOrInvalidPlanNeverWritesProfileOrDismissal() {
        listOf<String?>(null, "", "malformed").forEach { candidate ->
            var profileWrites = 0
            var dismissalWrites = 0

            val result = FirstWorkoutActivationCommitter.commit(
                candidateToken = candidate,
                targetProfile = targetProfile,
                previousProfile = previousProfile,
                previousDismissed = false,
                isExactPlan = { it == "exact-plan" },
                persistProfile = { profileWrites += 1; true },
                persistDismissed = { dismissalWrites += 1; true }
            )

            assertNull(result)
            assertEquals(0, profileWrites)
            assertEquals(0, dismissalWrites)
        }
    }

    @Test
    fun successfulExactPlanPersistsDerivedProfileThenDismissal() {
        var storedProfile = previousProfile
        var dismissed = false
        val writes = mutableListOf<String>()

        val result = FirstWorkoutActivationCommitter.commit(
            candidateToken = "exact-plan",
            targetProfile = targetProfile,
            previousProfile = previousProfile,
            previousDismissed = false,
            isExactPlan = { it == "exact-plan" },
            persistProfile = {
                writes += "profile"
                storedProfile = it
                true
            },
            persistDismissed = {
                writes += "dismissal"
                dismissed = it
                true
            }
        )

        assertEquals("exact-plan", result)
        assertEquals(targetProfile, storedProfile)
        assertTrue(dismissed)
        assertEquals(listOf("profile", "dismissal"), writes)
    }

    @Test
    fun failedProfilePersistenceRestoresBothPriorValues() {
        var storedProfile = previousProfile
        var dismissed = false
        var failTargetWrite = true

        val result = FirstWorkoutActivationCommitter.commit(
            candidateToken = "exact-plan",
            targetProfile = targetProfile,
            previousProfile = previousProfile,
            previousDismissed = false,
            isExactPlan = { true },
            persistProfile = { profile ->
                // Model SharedPreferences' in-memory mutation even when commit() is false.
                storedProfile = profile
                if (profile == targetProfile && failTargetWrite) {
                    failTargetWrite = false
                    false
                } else {
                    true
                }
            },
            persistDismissed = { dismissed = it; true }
        )

        assertNull(result)
        assertEquals(previousProfile, storedProfile)
        assertFalse(dismissed)
    }

    @Test
    fun failedDismissalPersistenceRestoresBothPriorValues() {
        var storedProfile = previousProfile
        var dismissed = false
        var failDismissalWrite = true

        val result = FirstWorkoutActivationCommitter.commit(
            candidateToken = "exact-plan",
            targetProfile = targetProfile,
            previousProfile = previousProfile,
            previousDismissed = false,
            isExactPlan = { true },
            persistProfile = { storedProfile = it; true },
            persistDismissed = { value ->
                dismissed = value
                if (value && failDismissalWrite) {
                    failDismissalWrite = false
                    false
                } else {
                    true
                }
            }
        )

        assertNull(result)
        assertEquals(previousProfile, storedProfile)
        assertFalse(dismissed)
    }

    @Test
    fun failedEditorHandoffRestoresBothPriorValues() {
        var storedProfile = previousProfile
        var dismissed = false

        val result = FirstWorkoutActivationCommitter.commit(
            candidateToken = "exact-plan",
            targetProfile = targetProfile,
            previousProfile = previousProfile,
            previousDismissed = false,
            isExactPlan = { true },
            persistProfile = { storedProfile = it; true },
            persistDismissed = { dismissed = it; true },
            acknowledgeHandoff = { false }
        )

        assertNull(result)
        assertEquals(previousProfile, storedProfile)
        assertFalse(dismissed)
    }

    @Test
    fun failedNavigationCancelsPreparedTokenWithoutPersistence() {
        val token = "A".repeat(64)
        var storedProfile = previousProfile
        var dismissed = false
        var cancelled: String? = null

        val opened = handOffFirstWorkoutNavigation(
            token = token,
            open = { error("route failed") },
            cancel = { cancelled = it }
        )

        assertFalse(opened)
        assertEquals(token, cancelled)
        assertEquals(previousProfile, storedProfile)
        assertFalse(dismissed)
    }

    @Test
    fun pendingActivationRoundTripsAndMalformedStateFailsNeutral() {
        val pending = PendingFirstWorkoutActivation(
            token = "B".repeat(64),
            targetProfile = targetProfile,
            previousProfile = previousProfile,
            previousDismissed = false
        )

        assertEquals(
            pending,
            PendingFirstWorkoutActivationCodec.decode(
                PendingFirstWorkoutActivationCodec.encode(pending)
            )
        )
        assertNull(PendingFirstWorkoutActivationCodec.decode("{\"v\":1}"))
    }

    @Test
    fun skipRestoresDismissalWhenBlankEditorNavigationFails() {
        var dismissed = false

        val opened = handOffSkippedFirstWorkoutNavigation(
            previousDismissed = false,
            persistDismissed = { value -> dismissed = value; true },
            open = { error("route failed") }
        )

        assertFalse(opened)
        assertFalse(dismissed)
    }

    private fun activationPlan(): SmartWorkoutLaunchPlan = SmartWorkoutLaunchPlan(
        origin = SmartWorkoutLaunchOrigin.Activation,
        launchId = "0123456789abcdef0123456789abcdef",
        accountBinding = "a".repeat(64),
        createdAtMillis = 1_800_000_000_000L,
        stateFingerprint = "b".repeat(64),
        trainingProfile = targetProfile,
        focus = SmartWorkoutFocus.FullBody,
        variant = SmartWorkoutVariant.A,
        requestedEffort = SmartWorkoutEffort.Standard,
        appliedEffort = SmartWorkoutEffort.Standard,
        effortAdjustment = null,
        exercises = listOf(
            SmartWorkoutLaunchExercise(
                exerciseId = 1L,
                sets = listOf(
                    SmartWorkoutLaunchSet(20.0, 10),
                    SmartWorkoutLaunchSet(20.0, 10),
                    SmartWorkoutLaunchSet(null, 10)
                ),
                isHardSlot = false
            )
        )
    )
}
