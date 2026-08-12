package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutRecommendationFeedbackTest {
    private val zone = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 8, 12)
    private val now = today.atStartOfDay(zone).toInstant().toEpochMilli()
    private val profile = TrainingProfile(
        split = TrainingSplit.FullBody,
        workoutsPerWeek = 6,
        goal = TrainingGoal.Balanced,
        calorieMode = CalorieMode.Maintenance
    )

    @Test
    fun latestHardFeedbackMakesOnlyAutoARecoveryPlan() {
        val history = session(7, 3, 1, "Bench Press", reps = 8)
        val feedback = feedback(history, WorkoutFeedback.Hard)

        val auto = plan(history, SmartWorkoutEffort.Auto, feedback)
        val explicit = plan(history, SmartWorkoutEffort.Standard, feedback)

        assertEquals(SmartWorkoutEffort.Recovery, auto.appliedEffort)
        assertEquals(SmartWorkoutEffortAdjustment.FeedbackHardRecovery, auto.effortAdjustment)
        assertEquals(SmartWorkoutEffort.Standard, explicit.appliedEffort)
        assertEquals(null, explicit.effortAdjustment)
    }

    @Test
    fun hardFeedbackReasonWinsWhenMusclesAlsoNeedRecovery() {
        val history = session(7, 1, 1, "Bench Press", reps = 8)

        val auto = plan(history, SmartWorkoutEffort.Auto, feedback(history, WorkoutFeedback.Hard))

        assertEquals(SmartWorkoutEffort.Recovery, auto.appliedEffort)
        assertEquals(SmartWorkoutEffortAdjustment.FeedbackHardRecovery, auto.effortAdjustment)
    }

    @Test
    fun futureDatedLatestFeedbackIsNeutral() {
        val futureDate = now + 3_600_000L
        val futureHistory = List(3) { index ->
            ExerciseHistoryEntry(
                setId = 900L + index,
                sessionId = 9L,
                sessionDate = futureDate,
                exerciseId = 1L,
                exerciseName = "Bench Press",
                weight = 50.0,
                reps = 8,
                setOrderIndex = index
            )
        }

        val result = plan(
            futureHistory,
            SmartWorkoutEffort.Auto,
            SmartCoachFeedback(9L, futureDate, WorkoutFeedback.Hard)
        )

        assertNotEquals(SmartWorkoutEffortAdjustment.FeedbackHardRecovery, result.effortAdjustment)
    }

    @Test
    fun futureSessionDoesNotSuppressLatestCompletedFeedback() {
        val completed = session(7, 3, 1, "Bench Press", reps = 8)
        val futureDate = now + 3_600_000L
        val future = List(3) { index ->
            completed.first().copy(
                setId = 900L + index,
                sessionId = 9L,
                sessionDate = futureDate,
                setOrderIndex = index
            )
        }

        val result = plan(
            completed + future,
            SmartWorkoutEffort.Auto,
            feedback(completed, WorkoutFeedback.Hard)
        )

        assertEquals(SmartWorkoutEffortAdjustment.FeedbackHardRecovery, result.effortAdjustment)
    }

    @Test
    fun easyAddsAtMostOneSetWithoutChangingExistingPrescription() {
        val history = session(7, 3, 1, "Bench Press", reps = 8)
        val baseline = plan(history, SmartWorkoutEffort.Auto, null)
        val adjusted = plan(history, SmartWorkoutEffort.Auto, feedback(history, WorkoutFeedback.Easy))

        assertEquals(SmartWorkoutEffort.Standard, adjusted.appliedEffort)
        assertEquals(SmartWorkoutEffortAdjustment.FeedbackEasyExtraSet, adjusted.effortAdjustment)
        assertEquals(
            baseline.exercises.sumOf { it.recommendation.sets.size } + 1,
            adjusted.exercises.sumOf { it.recommendation.sets.size }
        )
        assertTrue(adjusted.exercises.sumOf { it.recommendation.sets.size } <= 24)
        assertTrue(adjusted.exercises.all { it.recommendation.sets.size <= 4 })
        baseline.exercises.zip(adjusted.exercises).forEach { (before, after) ->
            assertEquals(before.exercise.id, after.exercise.id)
            assertEquals(before.recommendation.targetRir, after.recommendation.targetRir)
            assertEquals(before.recommendation.sets, after.recommendation.sets.take(before.recommendation.sets.size))
        }
    }

    @Test
    fun normalStaleAndNonLatestFeedbackAreNeutral() {
        val latest = session(9, 3, 1, "Bench Press", reps = 8)
        val older = session(8, 5, 2, "Barbell Row", reps = 8)
        val history = older + latest
        val baseline = plan(history, SmartWorkoutEffort.Auto, null)

        assertEquals(
            baseline,
            plan(history, SmartWorkoutEffort.Auto, feedback(latest, WorkoutFeedback.Normal))
        )
        assertEquals(
            baseline,
            plan(
                history,
                SmartWorkoutEffort.Auto,
                SmartCoachFeedback(8, older.first().sessionDate, WorkoutFeedback.Hard)
            )
        )

        val staleHistory = session(10, 8, 1, "Bench Press", reps = 8)
        val stale = plan(
            staleHistory,
            SmartWorkoutEffort.Auto,
            feedback(staleHistory, WorkoutFeedback.Hard)
        )
        assertNotEquals(SmartWorkoutEffortAdjustment.FeedbackHardRecovery, stale.effortAdjustment)
    }

    @Test
    fun easyNeverBypassesDeloadAndPlanCapsRemainCanonical() {
        val regressed = session(1, 5, 1, "Push Up", reps = 10) +
            session(2, 3, 1, "Push Up", reps = 8) +
            session(3, 1, 1, "Push Up", reps = 6)
        val limitedCatalog = listOf(
            ExerciseEntity(1, "Push Up"),
            ExerciseEntity(2, "Barbell Row"),
            ExerciseEntity(3, "Squat"),
            ExerciseEntity(4, "Lateral Raise"),
            ExerciseEntity(5, "Plank")
        )
        val baseline = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = limitedCatalog,
            history = regressed,
            trainingProfile = profile,
            nowMillis = now,
            zoneId = zone,
            effort = SmartWorkoutEffort.Auto
        )
        val easy = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = limitedCatalog,
            history = regressed,
            trainingProfile = profile,
            nowMillis = now,
            zoneId = zone,
            effort = SmartWorkoutEffort.Auto,
            latestFeedback = feedback(regressed.takeLast(3), WorkoutFeedback.Easy)
        )

        assertTrue(baseline.exercises.any { it.recommendation.kind == WorkoutRecommendationKind.Deload })
        assertEquals(baseline, easy)

        val capped = plan(emptyList(), SmartWorkoutEffort.Auto, null)
        assertTrue(capped.exercises.size <= 8)
        assertTrue(capped.exercises.sumOf { it.recommendation.sets.size } <= 24)
        assertTrue(capped.exercises.all { it.recommendation.sets.size in 3..4 })
    }

    private fun plan(
        history: List<ExerciseHistoryEntry>,
        effort: SmartWorkoutEffort,
        feedback: SmartCoachFeedback?
    ): SmartWorkoutPlan = WorkoutRecommendationEngine.buildWorkoutPlan(
        exercises = catalog(),
        history = history,
        trainingProfile = profile,
        nowMillis = now,
        zoneId = zone,
        effort = effort,
        latestFeedback = feedback
    )

    private fun feedback(
        session: List<ExerciseHistoryEntry>,
        value: WorkoutFeedback
    ): SmartCoachFeedback = SmartCoachFeedback(
        sessionId = session.first().sessionId,
        sessionDateMillis = session.first().sessionDate,
        feedback = value
    )

    private fun session(
        id: Long,
        daysAgo: Long,
        exerciseId: Long,
        name: String,
        reps: Int
    ): List<ExerciseHistoryEntry> {
        val date = today.minusDays(daysAgo).atStartOfDay(zone).toInstant().toEpochMilli()
        return List(3) { index ->
            ExerciseHistoryEntry(
                setId = id * 100 + index,
                sessionId = id,
                sessionDate = date,
                exerciseId = exerciseId,
                exerciseName = name,
                weight = 50.0,
                reps = reps,
                setOrderIndex = index
            )
        }
    }

    private fun catalog(): List<ExerciseEntity> = listOf(
        ExerciseEntity(1, "Bench Press"),
        ExerciseEntity(2, "Barbell Row"),
        ExerciseEntity(3, "Squat"),
        ExerciseEntity(4, "Lateral Raise"),
        ExerciseEntity(5, "Biceps Curl"),
        ExerciseEntity(6, "Leg Curl"),
        ExerciseEntity(7, "Calf Raise"),
        ExerciseEntity(8, "Plank")
    )
}
