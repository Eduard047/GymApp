package com.example.gymapp

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutRecommendationEngineTest {
    private val zoneId: ZoneId = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 6, 3)
    private val nowMillis = today.atStartOfDay(zoneId).toInstant().toEpochMilli()

    @Test
    fun upperLowerChoosesLowerAfterUpperSession() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = session(
                sessionId = 1,
                daysAgo = 1,
                exerciseId = 1,
                exerciseName = "Bench Press"
            ),
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Lower, plan.focus)
        assertTrue(plan.exerciseNames().any { it.contains("Leg Press") || it.contains("Squat") })
        assertFalse(plan.exerciseNames().contains("Bench Press"))
    }

    @Test
    fun upperLowerChoosesUpperAfterLowerSession() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = session(
                sessionId = 1,
                daysAgo = 1,
                exerciseId = 7,
                exerciseName = "Leg Press"
            ),
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Upper, plan.focus)
        assertTrue(plan.exerciseNames().any { it.contains("Row") || it.contains("Pull Up") })
        assertTrue(plan.exerciseNames().any { it.contains("Lateral Raise") || it.contains("Shoulder Press") })
    }

    @Test
    fun pushPullLegsCyclesFromLastDominantSession() {
        assertEquals(
            SmartWorkoutFocus.Pull,
            pplPlanAfter("Bench Press", exerciseId = 1).focus
        )
        assertEquals(
            SmartWorkoutFocus.Legs,
            pplPlanAfter("Cable Row", exerciseId = 4).focus
        )
        assertEquals(
            SmartWorkoutFocus.Push,
            pplPlanAfter("Leg Press", exerciseId = 7).focus
        )
    }

    @Test
    fun secondUpperSessionRotatesAwayFromRecentBenchTowardUncoveredMuscles() {
        val history = session(1, daysAgo = 1, exerciseId = 7, exerciseName = "Leg Press") +
            session(2, daysAgo = 3, exerciseId = 1, exerciseName = "Bench Press")

        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = history,
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        val names = plan.exerciseNames()
        assertEquals(SmartWorkoutFocus.Upper, plan.focus)
        assertFalse(names.contains("Bench Press"))
        assertTrue(names.any { it.contains("Lateral Raise") || it.contains("Shoulder Press") })
        assertTrue(names.any { it.contains("Row") || it.contains("Pull Up") })
    }

    @Test
    fun fullBodyIncludesUpperAndLowerPatterns() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(split = TrainingSplit.FullBody),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        val names = plan.exerciseNames()
        assertEquals(SmartWorkoutFocus.FullBody, plan.focus)
        assertTrue(names.any { it.contains("Press") || it.contains("Lateral Raise") })
        assertTrue(names.any { it.contains("Row") || it.contains("Pull Up") })
        assertTrue(names.any { it.contains("Leg") || it.contains("Romanian") || it.contains("Squat") })
    }

    private fun pplPlanAfter(exerciseName: String, exerciseId: Long) = WorkoutRecommendationEngine.buildWorkoutPlan(
        exercises = catalog(),
        history = session(
            sessionId = 1,
            daysAgo = 1,
            exerciseId = exerciseId,
            exerciseName = exerciseName
        ),
        trainingProfile = TrainingProfile(split = TrainingSplit.PushPullLegs),
        nowMillis = nowMillis,
        zoneId = zoneId
    )

    private fun catalog(): List<ExerciseEntity> = listOf(
        ExerciseEntity(id = 1, name = "Bench Press"),
        ExerciseEntity(id = 2, name = "Shoulder Press"),
        ExerciseEntity(id = 3, name = "Lateral Raise"),
        ExerciseEntity(id = 4, name = "Cable Row"),
        ExerciseEntity(id = 5, name = "Pull Up"),
        ExerciseEntity(id = 6, name = "Biceps Curl"),
        ExerciseEntity(id = 7, name = "Leg Press"),
        ExerciseEntity(id = 8, name = "Leg Extension"),
        ExerciseEntity(id = 9, name = "Leg Curl"),
        ExerciseEntity(id = 10, name = "Romanian Deadlift"),
        ExerciseEntity(id = 11, name = "Calf Raise"),
        ExerciseEntity(id = 12, name = "Weighted Crunch")
    )

    private fun session(
        sessionId: Long,
        daysAgo: Long,
        exerciseId: Long,
        exerciseName: String
    ): List<ExerciseHistoryEntry> {
        val date = today.minusDays(daysAgo).atStartOfDay(zoneId).toInstant().toEpochMilli()
        return List(3) { index ->
            ExerciseHistoryEntry(
                setId = sessionId * 100 + index,
                sessionId = sessionId,
                sessionDate = date,
                exerciseId = exerciseId,
                exerciseName = exerciseName,
                weight = 50.0,
                reps = 10,
                setOrderIndex = index
            )
        }
    }

    private fun com.example.gymapp.data.repository.SmartWorkoutPlan.exerciseNames(): List<String> {
        return exercises.map { it.exercise.name }
    }
}
