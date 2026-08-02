package com.example.gymapp

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutVariant
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.data.repository.WorkoutRecommendationKind
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
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
                exerciseId = 8,
                exerciseName = "Leg Press"
            ),
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Upper, plan.focus)
        assertTrue(plan.exerciseNames().any { it.contains("Row") || it.contains("Pull Up") })
        assertTrue(plan.exerciseNames().any { it.contains("Press") || it.contains("Lateral Raise") || it.contains("Overhead") })
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
            pplPlanAfter("Leg Press", exerciseId = 8).focus
        )
    }

    @Test
    fun splitRotationSkipsUnrecognizedLatestSession() {
        val unknownLatest = session(
            sessionId = 2,
            daysAgo = 1,
            exerciseId = 99,
            exerciseName = "Custom mobility marker"
        )
        val upperHistory = session(1, daysAgo = 3, exerciseId = 1, exerciseName = "Bench Press")
        val pullHistory = session(1, daysAgo = 3, exerciseId = 4, exerciseName = "Cable Row")

        val upperLowerPlan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = upperHistory + unknownLatest,
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val pplPlan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = pullHistory + unknownLatest,
            trainingProfile = TrainingProfile(split = TrainingSplit.PushPullLegs),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Lower, upperLowerPlan.focus)
        assertEquals(SmartWorkoutFocus.Legs, pplPlan.focus)
    }

    @Test
    fun secondUpperSessionRotatesAwayFromRecentBenchTowardUncoveredMuscles() {
        val history = session(1, daysAgo = 1, exerciseId = 8, exerciseName = "Leg Press") +
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
    fun upperLowerAfterLightLowerAndHeavyUpperGeneratesHeavyLower() {
        val mondayLightLower = session(1, daysAgo = 2, exerciseId = 9, exerciseName = "Leg Extension") +
            session(1, daysAgo = 2, exerciseId = 10, exerciseName = "Leg Curl") +
            session(1, daysAgo = 2, exerciseId = 12, exerciseName = "Weighted Crunch")
        val tuesdayHeavyUpper = session(2, daysAgo = 1, exerciseId = 1, exerciseName = "Bench Press") +
            session(2, daysAgo = 1, exerciseId = 5, exerciseName = "Pull Up") +
            session(2, daysAgo = 1, exerciseId = 4, exerciseName = "Cable Row")

        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = mondayLightLower + tuesdayHeavyUpper,
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        val names = plan.exerciseNames()
        assertEquals(SmartWorkoutFocus.Lower, plan.focus)
        assertTrue(names.contains("Squat"))
        assertTrue(names.contains("Romanian Deadlift"))
        assertFalse(names.contains("Bench Press"))
    }

    @Test
    fun lowerWorkoutDoesNotFallbackToUpperOrUnknownExercises() {
        val history = session(1, daysAgo = 2, exerciseId = 9, exerciseName = "Leg Extension") +
            session(2, daysAgo = 1, exerciseId = 1, exerciseName = "Bench Press")

        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = history,
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        val names = plan.exerciseNames()
        assertEquals(SmartWorkoutFocus.Lower, plan.focus)
        assertFalse(names.contains("Overhead Dumbbell Extension"))
        assertFalse(names.contains("Crane Pulldown"))
        assertTrue(names.all { name ->
            name.contains("Squat") ||
                name.contains("Leg") ||
                name.contains("Romanian") ||
                name.contains("Calf") ||
                name.contains("Crunch")
        })
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

    @Test
    fun strengthFiveRepSetsBuildToSixInsteadOfTriggeringDeload() {
        val recommendation = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 1,
                weights = List(5) { 100.0 },
                reps = List(5) { 5 }
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.Strength,
                calorieMode = CalorieMode.Maintenance
            )
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, recommendation.kind)
        assertEquals(List(4) { 100.0 }, recommendation.sets.map { it.weight })
        assertEquals(List(4) { 6 }, recommendation.sets.map { it.reps })
    }

    @Test
    fun strengthProgressesOnlyAfterAllSetsReachTopOfRange() {
        val recommendation = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 3,
                weights = List(4) { 100.0 },
                reps = List(4) { 6 }
            ) + exerciseSession(
                sessionId = 2,
                daysAgo = 1,
                weights = List(4) { 100.0 },
                reps = List(4) { 6 }
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.Strength,
                calorieMode = CalorieMode.Maintenance
            )
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, recommendation.kind)
        assertEquals(List(4) { 105.0 }, recommendation.sets.map { it.weight })
        assertEquals(List(4) { 3 }, recommendation.sets.map { it.reps })
    }

    @Test
    fun muscleGainUsesDoubleProgressionAndPreservesPerSetLoads() {
        val profile = TrainingProfile(
            goal = TrainingGoal.MuscleGain,
            calorieMode = CalorieMode.Maintenance
        )
        val building = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 1,
                weights = listOf(40.0, 50.0, 60.0),
                reps = listOf(8, 8, 8)
            ),
            profile = profile
        )
        val progressing = recommendation(
            history = exerciseSession(
                sessionId = 2,
                daysAgo = 3,
                weights = listOf(40.0, 50.0, 60.0, 60.0),
                reps = listOf(10, 10, 10, 10)
            ) + exerciseSession(
                sessionId = 3,
                daysAgo = 1,
                weights = listOf(40.0, 50.0, 60.0, 60.0),
                reps = listOf(10, 10, 10, 10)
            ),
            profile = profile
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, building.kind)
        assertEquals(listOf(40.0, 50.0, 60.0, 60.0), building.sets.map { it.weight })
        assertEquals(List(4) { 9 }, building.sets.map { it.reps })
        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, progressing.kind)
        assertEquals(listOf(42.5, 52.5, 65.0, 65.0), progressing.sets.map { it.weight })
        assertEquals(List(4) { 6 }, progressing.sets.map { it.reps })
    }

    @Test
    fun cutDeficitReducesVolumeButStillAllowsEarnedProgression() {
        val recommendation = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 3,
                weights = listOf(50.0, 45.0, 40.0),
                reps = listOf(10, 10, 10)
            ) + exerciseSession(
                sessionId = 2,
                daysAgo = 1,
                weights = listOf(50.0, 45.0, 40.0),
                reps = listOf(10, 10, 10)
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.AestheticFatLoss,
                calorieMode = CalorieMode.Deficit,
                workoutsPerWeek = 4
            )
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, recommendation.kind)
        assertEquals(3, recommendation.sets.size)
        assertTrue(recommendation.sets.zip(listOf(50.0, 45.0, 40.0)).all { (set, previousWeight) ->
            (set.weight ?: 0.0) > previousWeight
        })
        assertEquals(List(3) { 6 }, recommendation.sets.map { it.reps })
    }

    @Test
    fun goalCaloriesAndFrequencyProduceDifferentSetBudgets() {
        val history = exerciseSession(
            sessionId = 1,
            daysAgo = 1,
            weights = List(3) { 50.0 },
            reps = List(3) { 8 }
        )
        fun setCount(calorieMode: CalorieMode, workoutsPerWeek: Int): Int {
            return recommendation(
                history = history,
                profile = TrainingProfile(
                    goal = TrainingGoal.MuscleGain,
                    calorieMode = calorieMode,
                    workoutsPerWeek = workoutsPerWeek
                )
            ).sets.size
        }

        assertEquals(4, setCount(CalorieMode.Maintenance, workoutsPerWeek = 4))
        assertEquals(4, setCount(CalorieMode.Surplus, workoutsPerWeek = 4))
        assertEquals(4, setCount(CalorieMode.Maintenance, workoutsPerWeek = 2))
        assertEquals(3, setCount(CalorieMode.Maintenance, workoutsPerWeek = 6))
    }

    @Test
    fun deloadRequiresTwoConsecutiveComparableRegressions() {
        val oldest = exerciseSession(1, daysAgo = 5, weights = List(3) { 100.0 }, reps = List(3) { 10 })
        val previous = exerciseSession(2, daysAgo = 3, weights = List(3) { 90.0 }, reps = List(3) { 8 })
        val latest = exerciseSession(3, daysAgo = 1, weights = List(3) { 80.0 }, reps = List(3) { 6 })
        val profile = TrainingProfile(goal = TrainingGoal.Balanced, calorieMode = CalorieMode.Maintenance)

        assertEquals(
            WorkoutRecommendationKind.HoldAndBuild,
            recommendation(history = previous + latest, profile = profile).kind
        )
        assertEquals(
            WorkoutRecommendationKind.Deload,
            recommendation(history = oldest + previous + latest, profile = profile).kind
        )
    }

    @Test
    fun plateauNeedsNoMeaningfulRepOrLoadProgress() {
        val flat = (1L..4L).flatMap { sessionId ->
            exerciseSession(
                sessionId = sessionId,
                daysAgo = 9 - sessionId * 2,
                weights = List(3) { 60.0 },
                reps = List(3) { 7 }
            )
        }
        val rising = (1L..4L).flatMap { sessionId ->
            exerciseSession(
                sessionId = sessionId,
                daysAgo = 9 - sessionId * 2,
                weights = List(3) { 60.0 },
                reps = List(3) { 4 + sessionId.toInt() }
            )
        }
        val profile = TrainingProfile(goal = TrainingGoal.Balanced, calorieMode = CalorieMode.Maintenance)

        assertEquals(WorkoutRecommendationKind.PlateauBreak, recommendation(flat, profile).kind)
        assertEquals(WorkoutRecommendationKind.HoldAndBuild, recommendation(rising, profile).kind)
    }

    @Test
    fun fullBodyHistoryRotatesDeterministicABCVariants() {
        val profile = TrainingProfile(
            split = TrainingSplit.FullBody,
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance
        )
        val firstSession = session(1, daysAgo = 3, exerciseId = 101, exerciseName = "Rotation marker alpha")
        val secondSession = session(2, daysAgo = 1, exerciseId = 102, exerciseName = "Rotation marker beta")
        val planA = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(), history = emptyList(), trainingProfile = profile,
            nowMillis = nowMillis, zoneId = zoneId
        )
        val planB = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(), history = firstSession, trainingProfile = profile,
            nowMillis = nowMillis, zoneId = zoneId
        )
        val planC = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(), history = firstSession + secondSession, trainingProfile = profile,
            nowMillis = nowMillis, zoneId = zoneId
        )

        assertEquals(SmartWorkoutVariant.A, planA.variant)
        assertEquals(SmartWorkoutVariant.B, planB.variant)
        assertEquals(SmartWorkoutVariant.C, planC.variant)
        assertTrue(planA.exerciseNames() != planB.exerciseNames())
        assertTrue(planB.exerciseNames() != planC.exerciseNames())
        assertTrue(planA.exerciseNames() != planC.exerciseNames())
    }

    @Test
    fun workoutFrequencyChangesFullBodyExerciseBudget() {
        fun plan(workoutsPerWeek: Int) = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = workoutsPerWeek,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(6, plan(workoutsPerWeek = 2).exercises.size)
        assertEquals(4, plan(workoutsPerWeek = 6).exercises.size)
    }

    @Test
    fun builtInAliasesShareIdentityForClassificationAndHistory() {
        val lowerPlan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = session(1, daysAgo = 1, exerciseId = 99, exerciseName = "Жим лежачи"),
            trainingProfile = TrainingProfile(split = TrainingSplit.UpperLower),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val aliasedHistoryRecommendation = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Bench Press",
            history = exerciseSession(
                sessionId = 2,
                daysAgo = 1,
                exerciseId = 99,
                exerciseName = "Жим лежачи",
                weights = List(3) { 50.0 },
                reps = List(3) { 10 }
            ),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val aliasCatalog = catalog() + ExerciseEntity(id = 16, name = "Жим лежачи")
        val aliasPlan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = aliasCatalog,
            history = emptyList(),
            trainingProfile = TrainingProfile(split = TrainingSplit.FullBody),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Lower, lowerPlan.focus)
        assertFalse(aliasedHistoryRecommendation.kind == WorkoutRecommendationKind.NewExercise)
        assertTrue(aliasPlan.exerciseNames().count { it == "Bench Press" || it == "Жим лежачи" } <= 1)
    }

    @Test
    fun coachRejectsInvalidHistoryAndCapsProgressionWeight() {
        val baseEntry = exerciseSession(
            sessionId = 1,
            daysAgo = 1,
            weights = listOf(50.0),
            reps = listOf(12)
        ).single()
        val invalidRecommendation = recommendation(
            history = listOf(
                baseEntry.copy(weight = Double.NaN),
                baseEntry.copy(
                    setId = 2,
                    sessionId = 2,
                    sessionDate = nowMillis + 2L * 24L * 60L * 60L * 1_000L
                )
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.MuscleGain,
                calorieMode = CalorieMode.Maintenance
            )
        )
        val cappedRecommendation = recommendation(
            history = exerciseSession(
                sessionId = 3,
                daysAgo = 1,
                weights = List(3) { WorkoutDataLimits.MAX_WEIGHT },
                reps = List(3) { 12 }
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.MuscleGain,
                calorieMode = CalorieMode.Maintenance
            )
        )

        assertEquals(WorkoutRecommendationKind.NewExercise, invalidRecommendation.kind)
        assertTrue(cappedRecommendation.sets.all { it.weight == WorkoutDataLimits.MAX_WEIGHT })
    }

    @Test
    fun coachBoundsCandidateCatalogBeforeScoring() {
        val oversizedCatalog = (1L..(WorkoutDataLimits.MAX_EXERCISES + 1L)).map { id ->
            ExerciseEntity(id = id, name = "Custom exercise $id")
        }
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = oversizedCatalog,
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 2,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(6, plan.exercises.size)
        assertTrue(plan.exercises.all { it.exercise.id <= WorkoutDataLimits.MAX_EXERCISES })
    }

    @Test
    fun everyProfileKeepsPrescriptionsWithinThreeToFourSetsAndTenReps() {
        TrainingGoal.entries.forEach { goal ->
            CalorieMode.entries.forEach { calorieMode ->
                (2..6).forEach { workoutsPerWeek ->
                    val profile = TrainingProfile(
                        split = when (workoutsPerWeek) {
                            2, 3 -> TrainingSplit.FullBody
                            4 -> TrainingSplit.UpperLower
                            else -> TrainingSplit.PushPullLegs
                        },
                        workoutsPerWeek = workoutsPerWeek,
                        goal = goal,
                        calorieMode = calorieMode
                    )
                    listOf("Bench Press", "Biceps Curl").forEachIndexed { index, exerciseName ->
                        val recommendation = WorkoutRecommendationEngine.buildForExercise(
                            exerciseId = index.toLong() + 1L,
                            exerciseName = exerciseName,
                            history = emptyList(),
                            trainingProfile = profile,
                            nowMillis = nowMillis,
                            zoneId = zoneId
                        )
                        assertTrue(recommendation.sets.size in 3..4)
                        assertTrue(recommendation.sets.all { it.reps in 3..10 })
                    }
                }
            }
        }
    }

    @Test
    fun smartPlanNeverTreatsWarmUpAsAWorkingExercise() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog() + ExerciseEntity(id = 99, name = "Warm Up"),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 3,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertFalse(plan.exerciseNames().contains("Warm Up"))
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
        ExerciseEntity(id = 7, name = "Squat"),
        ExerciseEntity(id = 8, name = "Leg Press"),
        ExerciseEntity(id = 9, name = "Leg Extension"),
        ExerciseEntity(id = 10, name = "Leg Curl"),
        ExerciseEntity(id = 11, name = "Romanian Deadlift"),
        ExerciseEntity(id = 12, name = "Calf Raise"),
        ExerciseEntity(id = 13, name = "Weighted Crunch"),
        ExerciseEntity(id = 14, name = "Overhead Dumbbell Extension"),
        ExerciseEntity(id = 15, name = "Crane Pulldown")
    )

    private fun recommendation(
        history: List<ExerciseHistoryEntry>,
        profile: TrainingProfile
    ) = WorkoutRecommendationEngine.buildForExercise(
        exerciseId = 1,
        history = history,
        trainingProfile = profile,
        nowMillis = nowMillis,
        zoneId = zoneId
    )

    private fun exerciseSession(
        sessionId: Long,
        daysAgo: Long,
        weights: List<Double>,
        reps: List<Int>,
        exerciseId: Long = 1,
        exerciseName: String = "Bench Press"
    ): List<ExerciseHistoryEntry> {
        require(weights.size == reps.size)
        val date = today.minusDays(daysAgo).atStartOfDay(zoneId).toInstant().toEpochMilli()
        return weights.indices.map { index ->
            ExerciseHistoryEntry(
                setId = sessionId * 100 + index,
                sessionId = sessionId,
                sessionDate = date,
                exerciseId = exerciseId,
                exerciseName = exerciseName,
                weight = weights[index],
                reps = reps[index],
                setOrderIndex = index
            )
        }
    }

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
