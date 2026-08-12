package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class TrainingExperienceContractTest {
    @Test
    fun recommendedDirectStartPersistsClaimBeforeRoomAndAcceptsOnlyStarted() = runBlocking {
        val events = mutableListOf<String>()
        val started = RecommendedWorkoutStartCommitter.start(
            plan = launchPlan().copy(origin = SmartWorkoutLaunchOrigin.Recommended),
            claimAndPersist = {
                events += "claim"
                true
            },
            startActiveWorkout = { drafts ->
                events += "room"
                assertEquals(0.0, drafts.last().sets.last().weight, 0.0)
                StartActiveWorkoutResult.Started
            }
        )
        assertTrue(started)
        assertEquals(listOf("claim", "room"), events)

        assertFalse(
            RecommendedWorkoutStartCommitter.start(
                plan = launchPlan().copy(origin = SmartWorkoutLaunchOrigin.Recommended),
                claimAndPersist = { true },
                startActiveWorkout = { StartActiveWorkoutResult.AlreadyActive }
            )
        )
    }

    @Test
    fun rejectedRecommendedClaimNeverWritesActiveWorkout() = runBlocking {
        var roomWrites = 0
        val started = RecommendedWorkoutStartCommitter.start(
            plan = launchPlan().copy(origin = SmartWorkoutLaunchOrigin.Recommended),
            claimAndPersist = { false },
            startActiveWorkout = {
                roomWrites += 1
                StartActiveWorkoutResult.Started
            }
        )
        assertFalse(started)
        assertEquals(0, roomWrites)
    }

    @Test
    fun missingProfileDefaultsRemainCanonical() {
        assertEquals(
            TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 4,
                goal = TrainingGoal.AestheticFatLoss,
                calorieMode = CalorieMode.Deficit
            ),
            TrainingProfile()
        )
    }

    @Test
    fun activationMappingIsDeterministicAcrossEveryAllowedInput() {
        (2..6).forEach { days ->
            TrainingGoal.entries.forEach { goal ->
                val profile = trainingProfileForActivation(goal, days)
                assertEquals(days, profile.workoutsPerWeek)
                assertEquals(goal, profile.goal)
                assertEquals(
                    when {
                        days <= 3 -> TrainingSplit.FullBody
                        days == 4 -> TrainingSplit.UpperLower
                        else -> TrainingSplit.PushPullLegs
                    },
                    profile.split
                )
                assertEquals(
                    when (goal) {
                        TrainingGoal.AestheticFatLoss -> CalorieMode.Deficit
                        TrainingGoal.MuscleGain -> CalorieMode.Surplus
                        TrainingGoal.Strength,
                        TrainingGoal.Balanced -> CalorieMode.Maintenance
                    },
                    profile.calorieMode
                )
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            trainingProfileForActivation(TrainingGoal.Balanced, 1)
        }
        assertEquals(SmartWorkoutEffort.Standard, FirstWorkoutEffort.Standard.toSmartWorkoutEffort())
    }

    @Test
    fun feedbackWireValuesAreExactAndFailNeutral() {
        assertEquals(listOf("easy", "normal", "hard"), WorkoutFeedback.entries.map { it.wireValue })
        assertEquals(WorkoutFeedback.Easy, WorkoutFeedback.fromWireValue("easy"))
        assertEquals(null, WorkoutFeedback.fromWireValue("EASY"))
        assertEquals(null, WorkoutFeedback.fromWireValue("unknown"))
    }

    @Test
    fun launchPlanRoundTripsExactlyAndRejectsWrongAccountOrUnknownFields() {
        val plan = launchPlan()
        val encoded = SmartWorkoutLaunchPlanCodec.encode(plan)

        assertEquals(
            plan,
            SmartWorkoutLaunchPlanCodec.decode(
                encoded,
                ACCOUNT_BINDING,
                plan.trainingProfile,
                STATE_FINGERPRINT,
                nowMillis = NOW
            )
        )
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded,
                "b".repeat(64),
                plan.trainingProfile,
                STATE_FINGERPRINT,
                nowMillis = NOW
            )
        }

        val root = JSONObject(
            Base64.getUrlDecoder().decode(encoded).toString(Charsets.UTF_8)
        ).put("unknown", true)
        val mutated = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(root.toString().toByteArray(Charsets.UTF_8))
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                mutated,
                ACCOUNT_BINDING,
                plan.trainingProfile,
                STATE_FINGERPRINT,
                nowMillis = NOW
            )
        }
    }

    @Test
    fun directSmartStartMaterializesNullableLoadAsValidZero() {
        val drafts = materializeSmartWorkoutDrafts(launchPlan())

        assertEquals(0.0, drafts[0].sets.last().weight, 0.0)
        assertEquals(8, drafts[0].sets.last().reps)

        listOf(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            -0.01,
            WorkoutDataLimits.MAX_WEIGHT + 0.01
        ).forEach { invalidWeight ->
            assertThrows(IllegalArgumentException::class.java) {
                materializeSmartWorkoutDrafts(
                    launchPlan().copy(
                        exercises = launchPlan().exercises.mapIndexed { index, exercise ->
                            if (index == 0) {
                                exercise.copy(
                                    sets = exercise.sets.mapIndexed { setIndex, set ->
                                        if (setIndex == 0) set.copy(weight = invalidWeight) else set
                                    }
                                )
                            } else {
                                exercise
                            }
                        }
                    )
                )
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            materializeSmartWorkoutDrafts(
                launchPlan().copy(
                    exercises = launchPlan().exercises.mapIndexed { index, exercise ->
                        if (index == 0) {
                            exercise.copy(
                                sets = exercise.sets.mapIndexed { setIndex, set ->
                                    if (setIndex == 0) set.copy(reps = 0) else set
                                }
                            )
                        } else {
                            exercise
                        }
                    }
                )
            )
        }
    }

    @Test
    fun launchPlanEnforcesCanonicalExerciseAndSetCaps() {
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.encode(
                launchPlan().copy(
                    exercises = (1L..9L).map { id ->
                        SmartWorkoutLaunchExercise(id, sets(), false)
                    }
                )
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.encode(
                launchPlan().copy(
                    exercises = (1L..8L).map { id ->
                        SmartWorkoutLaunchExercise(
                            id,
                            if (id == 1L) sets() + SmartWorkoutLaunchSet(10.0, 8) else sets(),
                            false
                        )
                    }
                )
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.encode(
                launchPlan().copy(
                    exercises = listOf(
                        SmartWorkoutLaunchExercise(1, sets(), false),
                        SmartWorkoutLaunchExercise(1, sets(), false)
                    )
                )
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.encode(
                launchPlan().copy(
                    exercises = listOf(
                        SmartWorkoutLaunchExercise(1, sets().take(2), false)
                    )
                )
            )
        }
    }

    @Test
    fun launchDecoderRejectsMalformedAndNonCanonicalStaleTokens() {
        listOf("***", "abc=", "A".repeat(SmartWorkoutLaunchPlanCodec.MAX_ENCODED_LENGTH + 1))
            .forEach { malformed ->
                assertThrows(IllegalArgumentException::class.java) {
                    SmartWorkoutLaunchPlanCodec.decode(
                        malformed,
                        ACCOUNT_BINDING,
                        TrainingProfile(),
                        STATE_FINGERPRINT,
                        nowMillis = NOW
                    )
                }
            }

        val staleAccountToken = SmartWorkoutLaunchPlanCodec.encode(launchPlan())
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                staleAccountToken,
                "c".repeat(64),
                TrainingProfile(),
                STATE_FINGERPRINT,
                nowMillis = NOW
            )
        }

        val invalidPlan = launchPlan().copy(
            exercises = listOf(
                SmartWorkoutLaunchExercise(
                    1,
                    listOf(
                        SmartWorkoutLaunchSet(10.0, 0),
                        SmartWorkoutLaunchSet(10.0, 8),
                        SmartWorkoutLaunchSet(10.0, 8)
                    ),
                    false
                )
            )
        )
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.encode(invalidPlan)
        }
    }

    @Test
    fun launchDecoderRejectsExpiredFutureAndProfileChangedTokens() {
        val plan = launchPlan()
        val encoded = SmartWorkoutLaunchPlanCodec.encode(plan)

        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded,
                ACCOUNT_BINDING,
                plan.trainingProfile,
                STATE_FINGERPRINT,
                nowMillis = NOW + SmartWorkoutLaunchPlanCodec.MAX_LAUNCH_AGE_MILLIS + 1L
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded,
                ACCOUNT_BINDING,
                plan.trainingProfile,
                STATE_FINGERPRINT,
                nowMillis = NOW - SmartWorkoutLaunchPlanCodec.MAX_FUTURE_SKEW_MILLIS - 1L
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded,
                ACCOUNT_BINDING,
                plan.trainingProfile.copy(workoutsPerWeek = 5),
                STATE_FINGERPRINT,
                nowMillis = NOW
            )
        }
    }

    @Test
    fun launchFingerprintRejectsSameAccountCatalogAndHistoryChanges() {
        val profile = TrainingProfile()
        val catalog = listOf(
            ExerciseEntity(id = 11L, name = "Bench Press"),
            ExerciseEntity(id = 12L, name = "Barbell Row")
        )
        val history = listOf(
            ExerciseHistoryEntry(
                setId = 101L,
                sessionId = 10L,
                sessionDate = NOW - 86_400_000L,
                exerciseId = 11L,
                exerciseName = "Bench Press",
                weight = 40.0,
                reps = 10,
                setOrderIndex = 0
            )
        )
        fun fingerprint(
            exercises: List<ExerciseEntity> = catalog,
            entries: List<ExerciseHistoryEntry> = history
        ) = SmartWorkoutLaunchStateFingerprint.compute(
            profile = profile,
            exercises = exercises,
            history = entries,
            loadProfiles = emptyMap(),
            muscleMappings = emptyList()
        )

        val originalFingerprint = fingerprint()
        val encoded = SmartWorkoutLaunchPlanCodec.encode(
            launchPlan().copy(stateFingerprint = originalFingerprint)
        )
        assertEquals(
            originalFingerprint,
            SmartWorkoutLaunchPlanCodec.decode(
                encoded = encoded,
                expectedAccountBinding = ACCOUNT_BINDING,
                expectedTrainingProfile = profile,
                expectedStateFingerprint = originalFingerprint,
                nowMillis = NOW
            ).stateFingerprint
        )

        val catalogChanged = fingerprint(
            exercises = catalog.map { exercise ->
                if (exercise.id == 11L) exercise.copy(isFavorite = true) else exercise
            }
        )
        val historyChanged = fingerprint(
            entries = history + history.first().copy(
                setId = 102L,
                reps = 11,
                setOrderIndex = 1
            )
        )
        val catalogRemoved = fingerprint(exercises = emptyList())
        listOf(catalogChanged, historyChanged, catalogRemoved).forEach { staleFingerprint ->
            assertThrows(IllegalArgumentException::class.java) {
                SmartWorkoutLaunchPlanCodec.decode(
                    encoded = encoded,
                    expectedAccountBinding = ACCOUNT_BINDING,
                    expectedTrainingProfile = profile,
                    expectedStateFingerprint = staleFingerprint,
                    nowMillis = NOW
                )
            }
        }
    }

    @Test
    fun launchUseRegistryIsOneShotBoundedAndFailsClosedOnMalformedState() {
        val first = SmartWorkoutLaunchUseRegistry.consume(
            encoded = null,
            launchId = LAUNCH_ID,
            createdAtMillis = NOW,
            nowMillis = NOW
        )
        assertEquals(true, first != null)
        assertEquals(
            true,
            SmartWorkoutLaunchUseRegistry.isConsumed(first, LAUNCH_ID, NOW)
        )
        assertEquals(
            null,
            SmartWorkoutLaunchUseRegistry.consume(
                encoded = first,
                launchId = LAUNCH_ID,
                createdAtMillis = NOW,
                nowMillis = NOW
            )
        )
        assertEquals(
            true,
            SmartWorkoutLaunchUseRegistry.isConsumed("malformed", LAUNCH_ID, NOW)
        )
    }

    private fun launchPlan(): SmartWorkoutLaunchPlan = SmartWorkoutLaunchPlan(
        origin = SmartWorkoutLaunchOrigin.Activation,
        launchId = LAUNCH_ID,
        accountBinding = ACCOUNT_BINDING,
        createdAtMillis = NOW,
        stateFingerprint = STATE_FINGERPRINT,
        trainingProfile = TrainingProfile(),
        focus = SmartWorkoutFocus.Upper,
        variant = SmartWorkoutVariant.B,
        requestedEffort = SmartWorkoutEffort.Standard,
        appliedEffort = SmartWorkoutEffort.Standard,
        effortAdjustment = null,
        exercises = listOf(
            SmartWorkoutLaunchExercise(11, sets(), false),
            SmartWorkoutLaunchExercise(12, sets(), false)
        )
    )

    private fun sets(): List<SmartWorkoutLaunchSet> = listOf(
        SmartWorkoutLaunchSet(40.0, 10),
        SmartWorkoutLaunchSet(40.0, 10),
        SmartWorkoutLaunchSet(null, 8)
    )

    private companion object {
        const val ACCOUNT_BINDING =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        const val STATE_FINGERPRINT =
            "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        const val LAUNCH_ID = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        const val NOW = 1_786_473_600_000L
    }
}
