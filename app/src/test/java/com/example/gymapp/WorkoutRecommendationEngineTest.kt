package com.example.gymapp

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutVariant
import com.example.gymapp.data.repository.SmartWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.ExerciseLoadDirection
import com.example.gymapp.data.repository.ExerciseLoadProfile
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.data.repository.WorkoutRecommendationKind
import com.example.gymapp.data.repository.WorkoutRecommendationReason
import com.example.gymapp.ui.viewmodel.SmartWorkoutPlanSummaryUiModel
import com.example.gymapp.ui.viewmodel.smartWorkoutRecommendationPolicy
import com.example.gymapp.ui.viewmodel.smartWorkoutPlanNeedsRefresh
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
    fun secondUpperSessionKeepsPressAndPullBalanced() {
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
        assertTrue(names.any { it.contains("Press") || it.contains("Lateral Raise") })
        assertTrue(names.any { it.contains("Row") || it.contains("Pull Up") || it.contains("Pulldown") })
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
                name.contains("Crunch") ||
                name.contains("Deadlift") ||
                name.contains("Hip") ||
                name.contains("Lunge") ||
                name.contains("Bulgarian") ||
                name.contains("Hyperextension")
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
        assertEquals(List(4) { 102.5 }, recommendation.sets.map { it.weight })
        assertEquals(List(4) { 4 }, recommendation.sets.map { it.reps })
    }

    @Test
    fun partialTargetSetSessionsDoNotEarnProgression() {
        val recommendation = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 3,
                weights = List(3) { 100.0 },
                reps = List(3) { 6 }
            ) + exerciseSession(
                sessionId = 2,
                daysAgo = 1,
                weights = List(3) { 100.0 },
                reps = List(3) { 6 }
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.Strength,
                calorieMode = CalorieMode.Maintenance,
                workoutsPerWeek = 4
            )
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, recommendation.kind)
        assertEquals(List(4) { 100.0 }, recommendation.sets.map { it.weight })
    }

    @Test
    fun repRegressionAtSameWeightDoesNotEarnProgression() {
        val recommendation = recommendation(
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 3,
                weights = List(4) { 100.0 },
                reps = List(4) { 10 }
            ) + exerciseSession(
                sessionId = 2,
                daysAgo = 1,
                weights = List(4) { 100.0 },
                reps = List(4) { 8 }
            ),
            profile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance,
                workoutsPerWeek = 4
            )
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, recommendation.kind)
        assertEquals(List(4) { 100.0 }, recommendation.sets.map { it.weight })
    }

    @Test
    fun assistanceProgressionReducesHelpAndComebackIncreasesIt() {
        val profile = TrainingProfile(
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance,
            workoutsPerWeek = 4
        )
        val successfulHistory = exerciseSession(
            sessionId = 1,
            daysAgo = 3,
            weights = List(3) { 50.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "Assisted Pull Up"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 1,
            weights = List(3) { 50.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "Assisted Pull Up"
        )
        val progression = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Pull Up",
            history = successfulHistory,
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val comeback = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Pull Up",
            history = exerciseSession(
                sessionId = 3,
                daysAgo = 20,
                weights = List(3) { 50.0 },
                reps = List(3) { 8 },
                exerciseId = 2,
                exerciseName = "Assisted Pull Up"
            ),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, progression.kind)
        assertEquals(List(3) { 47.5 }, progression.sets.map { it.weight })
        assertEquals(WorkoutRecommendationKind.Comeback, comeback.kind)
        assertEquals(List(3) { 57.5 }, comeback.sets.map { it.weight })
    }

    @Test
    fun machineProfileUsesIrregularActualStackAndNeverInventsIntermediateWeight() {
        val history = exerciseSession(
            sessionId = 1,
            daysAgo = 3,
            weights = List(3) { 69.0 },
            reps = List(3) { 10 },
            exerciseName = "Lat Pulldown"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 1,
            weights = List(3) { 69.0 },
            reps = List(3) { 10 },
            exerciseName = "Lat Pulldown"
        )

        val recommendation = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Lat Pulldown",
            history = history,
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = ExerciseLoadProfile(
                ExerciseLoadDirection.HigherIsHarder,
                listOf(69.0, 73.0, 77.0)
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, recommendation.kind)
        assertEquals(List(3) { 73.0 }, recommendation.sets.map { it.weight })
    }

    @Test
    fun fallbackProgressionSnapsOffGridHistoryToDirectionalTwoPointFiveGrid() {
        val history = exerciseSession(
            sessionId = 1,
            daysAgo = 3,
            weights = List(3) { 48.5 },
            reps = List(3) { 10 },
            exerciseName = "Lat Pulldown"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 1,
            weights = List(3) { 48.5 },
            reps = List(3) { 10 },
            exerciseName = "Lat Pulldown"
        )

        val recommendation = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Lat Pulldown",
            history = history,
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Deficit
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(List(3) { 50.0 }, recommendation.sets.map { it.weight })
        assertFalse(recommendation.sets.any { it.weight == 51.0 })
    }

    @Test
    fun lowerIsHarderProfileUnderstandsFiftyToFortyFiveAndComebackReversesToFifty() {
        val loadProfile = ExerciseLoadProfile(
            ExerciseLoadDirection.LowerIsHarder,
            listOf(40.0, 45.0, 50.0, 55.0)
        )
        val successfulHistory = exerciseSession(
            sessionId = 1,
            daysAgo = 3,
            weights = List(3) { 50.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "Assisted Dip"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 1,
            weights = List(3) { 45.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "підтягування с брусьями"
        )
        val progression = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Dip",
            history = successfulHistory,
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = loadProfile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val comeback = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Dip",
            history = exerciseSession(
                sessionId = 3,
                daysAgo = 20,
                weights = List(3) { 45.0 },
                reps = List(3) { 8 },
                exerciseId = 2,
                exerciseName = "підтягування з брусьями"
            ),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = loadProfile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, progression.kind)
        assertEquals(List(3) { 40.0 }, progression.sets.map { it.weight })
        assertEquals(WorkoutRecommendationKind.Comeback, comeback.kind)
        assertEquals(List(3) { 50.0 }, comeback.sets.map { it.weight })
    }

    @Test
    fun assistanceExerciseRespectsExplicitHigherIsHarderMachineDirection() {
        val history = exerciseSession(
            sessionId = 1,
            daysAgo = 3,
            weights = List(3) { 50.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "Assisted Dip"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 1,
            weights = List(3) { 50.0 },
            reps = List(3) { 10 },
            exerciseId = 2,
            exerciseName = "Assisted Dip"
        )

        val recommendation = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Dip",
            history = history,
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = ExerciseLoadProfile(
                ExerciseLoadDirection.HigherIsHarder,
                listOf(45.0, 50.0, 55.0)
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, recommendation.kind)
        assertEquals(List(3) { 55.0 }, recommendation.sets.map { it.weight })
        assertEquals(0.0, recommendation.estimatedVolume, 0.0001)
    }

    @Test
    fun explicitProfileSnapsHoldAndBoundaryToActualAvailableWeight() {
        val profile = ExerciseLoadProfile(
            ExerciseLoadDirection.HigherIsHarder,
            listOf(50.0, 55.0)
        )
        val hold = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Lat Pulldown",
            history = exerciseSession(
                sessionId = 1,
                daysAgo = 1,
                weights = List(3) { 51.0 },
                reps = List(3) { 6 },
                exerciseName = "Lat Pulldown"
            ),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val boundary = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Lat Pulldown",
            history = exerciseSession(
                sessionId = 2,
                daysAgo = 3,
                weights = List(3) { 60.0 },
                reps = List(3) { 10 },
                exerciseName = "Lat Pulldown"
            ) + exerciseSession(
                sessionId = 3,
                daysAgo = 1,
                weights = List(3) { 60.0 },
                reps = List(3) { 10 },
                exerciseName = "Lat Pulldown"
            ),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            loadProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(List(3) { 50.0 }, hold.sets.map { it.weight })
        assertEquals(List(3) { 55.0 }, boundary.sets.map { it.weight })
        assertEquals(WorkoutRecommendationKind.HoldAndBuild, boundary.kind)
        assertTrue(boundary.reasons.contains(com.example.gymapp.data.repository.WorkoutRecommendationReason.LoadBoundaryReached))
    }

    @Test
    fun assistanceHistoryDoesNotUseOrdinaryLoadRegressionOrPlateauSignals() {
        val profile = TrainingProfile(
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance,
            workoutsPerWeek = 4
        )
        fun assistanceSession(sessionId: Long, daysAgo: Long, weight: Double, reps: Int) = exerciseSession(
            sessionId = sessionId,
            daysAgo = daysAgo,
            weights = List(3) { weight },
            reps = List(3) { reps },
            exerciseId = 2,
            exerciseName = "Assisted Pull Up"
        )
        val apparentLoadRegression = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Pull Up",
            history = assistanceSession(1, 5, 70.0, 10) +
                assistanceSession(2, 3, 60.0, 8) +
                assistanceSession(3, 1, 50.0, 6),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val flat = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Pull Up",
            history = (1L..4L).flatMap { sessionId ->
                assistanceSession(sessionId + 10, 9 - sessionId * 2, 50.0, 7)
            },
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val repeatedAssistanceRegression = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Assisted Pull Up",
            history = assistanceSession(30, 5, 40.0, 8) +
                assistanceSession(31, 3, 45.0, 8) +
                assistanceSession(32, 1, 50.0, 8),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, apparentLoadRegression.kind)
        assertEquals(WorkoutRecommendationKind.HoldAndBuild, flat.kind)
        assertEquals(WorkoutRecommendationKind.Deload, repeatedAssistanceRegression.kind)
        assertEquals(List(3) { 55.0 }, repeatedAssistanceRegression.sets.map { it.weight })
    }

    @Test
    fun zeroLoadBodyweightDoesNotFakeProgressionButRepeatedRepRegressionDeloads() {
        val profile = TrainingProfile(
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance,
            workoutsPerWeek = 4
        )
        fun bodyweightSession(sessionId: Long, daysAgo: Long, reps: Int) = exerciseSession(
            sessionId = sessionId,
            daysAgo = daysAgo,
            weights = List(3) { 0.0 },
            reps = List(3) { reps },
            exerciseId = 3,
            exerciseName = "Push Up"
        )
        val completedCeiling = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 3,
            exerciseName = "Push Up",
            history = bodyweightSession(1, 3, 10) + bodyweightSession(2, 1, 10),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val regressed = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 3,
            exerciseName = "Push Up",
            history = bodyweightSession(3, 5, 10) +
                bodyweightSession(4, 3, 8) +
                bodyweightSession(5, 1, 6),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.HoldAndBuild, completedCeiling.kind)
        assertTrue(completedCeiling.sets.all { it.weight == 0.0 && it.reps == 10 })
        assertEquals(WorkoutRecommendationKind.Deload, regressed.kind)
        assertTrue(regressed.sets.all { it.weight == 0.0 })
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
                reps = listOf(6, 6, 6)
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
        assertEquals(List(4) { 7 }, building.sets.map { it.reps })
        assertEquals(WorkoutRecommendationKind.ProgressiveOverload, progressing.kind)
        assertEquals(listOf(42.5, 52.5, 62.5, 62.5), progressing.sets.map { it.weight })
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
        assertEquals(3, setCount(CalorieMode.Surplus, workoutsPerWeek = 6))

        val secondarySurplus = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Incline Dumbbell Press",
            history = emptyList(),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.MuscleGain,
                calorieMode = CalorieMode.Surplus,
                workoutsPerWeek = 2
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        assertEquals(3, secondarySurplus.sets.size)
    }

    @Test
    fun newExerciseRepTargetsMatchTheSharedIosAndPwaPolicy() {
        fun target(goal: TrainingGoal, exerciseId: Long, exerciseName: String): Int =
            WorkoutRecommendationEngine.buildForExercise(
                exerciseId = exerciseId,
                exerciseName = exerciseName,
                history = emptyList(),
                trainingProfile = TrainingProfile(goal = goal),
                nowMillis = nowMillis,
                zoneId = zoneId
            ).sets.first().reps

        val exercises = listOf(
            1L to "Bench Press",
            2L to "Incline Dumbbell Press",
            3L to "Lateral Raise"
        )
        assertEquals(listOf(5, 6, 8), exercises.map { target(TrainingGoal.Strength, it.first, it.second) })
        assertEquals(listOf(8, 9, 10), exercises.map { target(TrainingGoal.MuscleGain, it.first, it.second) })
        assertEquals(
            listOf(8, 9, 10),
            exercises.map { target(TrainingGoal.AestheticFatLoss, it.first, it.second) }
        )
        assertEquals(listOf(7, 8, 10), exercises.map { target(TrainingGoal.Balanced, it.first, it.second) })
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

        val plateau = recommendation(flat, profile)
        assertEquals(WorkoutRecommendationKind.PlateauBreak, plateau.kind)
        assertEquals(1, plateau.sets.map { it.reps }.distinct().size)
        assertEquals(WorkoutRecommendationKind.HoldAndBuild, recommendation(rising, profile).kind)
    }

    @Test
    fun reviewedBuiltInsUseExactRolesInsteadOfNameHeuristics() {
        val profile = TrainingProfile(
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance,
            workoutsPerWeek = 4
        )
        fun fresh(name: String, id: Long) = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = id,
            exerciseName = name,
            history = emptyList(),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(4, fresh("Bench Press", 1).sets.size)
        listOf("Lateral Raise", "Rear Delt Fly", "Hyperextension").forEachIndexed { index, name ->
            val recommendation = fresh(name, index.toLong() + 2)
            assertEquals(name, 3, recommendation.sets.size)
            assertEquals(name, List(3) { 10 }, recommendation.sets.map { it.reps })
        }
        assertEquals(53, BuiltInExerciseCatalog.definitions.size)
        BuiltInExerciseCatalog.definitions.forEachIndexed { index, definition ->
            fresh(definition.nameEn, index.toLong() + 100)
        }
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

        val twoDays = plan(workoutsPerWeek = 2)
        val sixDays = plan(workoutsPerWeek = 6)
        assertTrue(twoDays.exercises.size > sixDays.exercises.size)
        assertTrue(twoDays.exercises.sumOf { it.recommendation.sets.size } >
            sixDays.exercises.sumOf { it.recommendation.sets.size })
        assertTrue(sixDays.exercises.all { it.recommendation.sets.size in 3..4 })
    }

    @Test
    fun goalAndDeficitDoNotCollapseNormalExerciseCountMatrix() {
        fun count(days: Int, split: TrainingSplit): Int = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = split,
                workoutsPerWeek = days,
                goal = TrainingGoal.Strength,
                calorieMode = CalorieMode.Deficit
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        ).exercises.size

        val fullBodyCounts = (2..6).map { days -> count(days, TrainingSplit.FullBody) }
        assertTrue(fullBodyCounts.zipWithNext().all { (lowerFrequency, higherFrequency) ->
            lowerFrequency >= higherFrequency
        })
        assertTrue(fullBodyCounts.all { it in 4..8 })
        assertTrue(count(4, TrainingSplit.UpperLower) >= 5)
        assertTrue(count(6, TrainingSplit.PushPullLegs) >= 3)
    }

    @Test
    fun everyPlanReservesOneTrunkSlotAndRotatesCoreWithHyperextension() {
        val trunkCatalog = catalog() + ExerciseEntity(id = 16, name = "Hyperextension")
        val trunkNames = setOf("Weighted Crunch", "Hyperextension")
        val fullBody = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = trunkCatalog,
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 5
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val rotated = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = trunkCatalog,
            history = session(1, daysAgo = 1, exerciseId = 13, exerciseName = "Weighted Crunch"),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 5
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val lower = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = trunkCatalog,
            history = session(2, daysAgo = 1, exerciseId = 1, exerciseName = "Bench Press"),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 4
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val upperAfterCore = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = trunkCatalog,
            history = session(3, daysAgo = 1, exerciseId = 13, exerciseName = "Weighted Crunch"),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 4
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val pushAfterCore = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = trunkCatalog,
            history = session(4, daysAgo = 1, exerciseId = 13, exerciseName = "Weighted Crunch"),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.PushPullLegs,
                workoutsPerWeek = 6
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(1, fullBody.exerciseNames().count { it in trunkNames })
        assertEquals(1, rotated.exerciseNames().count { it in trunkNames })
        assertFalse(rotated.exerciseNames().contains("Hyperextension"))
        assertEquals("Weighted Crunch", rotated.exerciseNames().last())
        assertEquals(SmartWorkoutFocus.Lower, lower.focus)
        assertEquals(1, lower.exerciseNames().count { it in trunkNames })
        assertEquals(SmartWorkoutFocus.Upper, upperAfterCore.focus)
        assertEquals(1, upperAfterCore.exerciseNames().count { it in trunkNames })
        assertTrue(upperAfterCore.exerciseNames().contains("Hyperextension"))
        assertEquals(SmartWorkoutFocus.Push, pushAfterCore.focus)
        assertEquals(1, pushAfterCore.exerciseNames().count { it in trunkNames })
        assertTrue(pushAfterCore.exerciseNames().contains("Hyperextension"))
        assertTrue(fullBody.exercises.sumOf { it.recommendation.sets.size } <= 28)
        assertTrue(lower.exercises.sumOf { it.recommendation.sets.size } <= 32)
        assertTrue(upperAfterCore.exercises.sumOf { it.recommendation.sets.size } <= 32)
        assertTrue(pushAfterCore.exercises.sumOf { it.recommendation.sets.size } in 12..18)
    }

    @Test
    fun sparseCatalogKeepsExactlyOneTrunkInsteadOfPaddingWithAnotherVariant() {
        val sparseCatalog = listOf(
            ExerciseEntity(id = 1, name = "Bench Press"),
            ExerciseEntity(id = 2, name = "Cable Row"),
            ExerciseEntity(id = 3, name = "Squat"),
            ExerciseEntity(id = 4, name = "Weighted Crunch"),
            ExerciseEntity(id = 5, name = "Hyperextension")
        )

        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = sparseCatalog,
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 2
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(4, plan.exercises.size)
        assertEquals(plan.exercises.size, plan.exercises.map { it.exercise.id }.distinct().size)
        assertEquals(
            1,
            plan.exerciseNames().count { it == "Weighted Crunch" || it == "Hyperextension" }
        )
    }

    @Test
    fun twoDayPushPullLegsUsesCompoundFullBodyPlan() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.PushPullLegs,
                workoutsPerWeek = 2,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val names = plan.exerciseNames()

        assertEquals(SmartWorkoutFocus.FullBody, plan.focus)
        assertTrue(names.any { it == "Bench Press" || it == "Shoulder Press" })
        assertTrue(names.any {
            it == "Cable Row" || it == "Barbell Row" || it == "Pull Up" ||
                it == "Lat Pulldown" || it == "Crane Pulldown"
        })
        assertTrue(names.any { it == "Squat" || it == "Leg Press" || it == "Romanian Deadlift" })
    }

    @Test
    fun upperPlanAlwaysContainsPressAndPullWithoutExcessVolume() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 4,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val names = plan.exerciseNames()

        assertEquals(SmartWorkoutFocus.Upper, plan.focus)
        assertEquals(8, names.size)
        assertTrue(names.any { it == "Bench Press" || it == "Shoulder Press" })
        assertTrue(names.any { it == "Cable Row" || it == "Pull Up" || it == "Crane Pulldown" })
        assertTrue(plan.exercises.sumOf { it.recommendation.sets.size } <= 24)
        assertTrue(names.contains("Weighted Crunch"))
    }

    @Test
    fun highFrequencyMuscleGainUpperPlanKeepsEightExercisesWithinSessionCap() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 6,
                goal = TrainingGoal.MuscleGain,
                calorieMode = CalorieMode.Surplus
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Upper, plan.focus)
        assertEquals(8, plan.exercises.size)
        assertEquals(24, plan.exercises.sumOf { it.recommendation.sets.size })
        assertTrue(plan.exerciseNames().any { it == "Bench Press" || it == "Shoulder Press" })
        assertTrue(plan.exerciseNames().any { it == "Cable Row" || it == "Pull Up" })
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

        assertEquals(8, plan.exercises.size)
        assertTrue(plan.exercises.all { it.exercise.id <= WorkoutDataLimits.MAX_EXERCISES })
    }

    @Test
    fun everyProfileKeepsPrescriptionsWithinThreeToFourSetsAndTenReps() {
        TrainingGoal.entries.forEach { goal ->
            CalorieMode.entries.forEach { calorieMode ->
                (2..6).forEach { workoutsPerWeek ->
                    TrainingSplit.entries.forEach { split ->
                        val profile = TrainingProfile(
                            split = split,
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
    }

    @Test
    fun missingExerciseAnalysisUsesTheCrossPlatformIsolationRepRange() {
        val expectedReps = mapOf(
            TrainingGoal.Strength to 8,
            TrainingGoal.MuscleGain to 10,
            TrainingGoal.AestheticFatLoss to 10,
            TrainingGoal.Balanced to 10
        )

        expectedReps.forEach { (goal, reps) ->
            val recommendation = WorkoutRecommendationEngine.buildForExercise(
                exerciseId = 1L,
                exerciseName = null,
                history = emptyList(),
                trainingProfile = TrainingProfile(goal = goal),
                nowMillis = nowMillis,
                zoneId = zoneId
            )

            assertTrue(recommendation.sets.isNotEmpty())
            assertEquals(
                goal.name,
                List(recommendation.sets.size) { reps },
                recommendation.sets.map { it.reps }
            )
        }
    }

    @Test
    fun builtInCatalogFillsEveryProfileBudgetWithExactlyOneTrunkExercise() {
        val exercises = BuiltInExerciseCatalog.definitions.mapIndexed { index, definition ->
            ExerciseEntity(id = index.toLong() + 1L, name = definition.nameEn)
        }
        val trunkNames = setOf(
            "Hyperextension",
            "Side Hyperextension",
            "Plank",
            "Weighted Crunch",
            "Hanging Leg Raise",
            "Plate Twist",
            "Weighted Side Bend"
        )

        TrainingGoal.entries.forEach { goal ->
            CalorieMode.entries.forEach { calorieMode ->
                (2..6).forEach { workoutsPerWeek ->
                    TrainingSplit.entries.forEach { split ->
                        val context = "$goal/$calorieMode/$workoutsPerWeek/$split"
                        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
                            exercises = exercises,
                            history = emptyList(),
                            trainingProfile = TrainingProfile(
                                split = split,
                                workoutsPerWeek = workoutsPerWeek,
                                goal = goal,
                                calorieMode = calorieMode
                            ),
                            nowMillis = nowMillis,
                            zoneId = zoneId
                        )
                        assertTrue(context, plan.exercises.size in 4..8)
                        assertEquals(
                            "$context trunk",
                            1,
                            plan.exerciseNames().count { it in trunkNames }
                        )
                        assertEquals(plan.exercises.size, plan.exercises.map { it.exercise.id }.distinct().size)
                        assertTrue(plan.exercises.all { it.recommendation.sets.size in 3..4 })
                        assertTrue(plan.exercises.sumOf { it.recommendation.sets.size } <= 24)
                        assertTrue(plan.exercises.all { exercise ->
                            exercise.recommendation.sets.all { it.reps in 3..10 }
                        })
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

    @Test
    fun weeklyTargetsFollowGoalAndCalorieProfileWithinSafeBounds() {
        val muscleGainSurplus = WorkoutRecommendationEngine.weeklyMuscleTargets(
            TrainingProfile(goal = TrainingGoal.MuscleGain, calorieMode = CalorieMode.Surplus)
        )
        val deficit = WorkoutRecommendationEngine.weeklyMuscleTargets(
            TrainingProfile(goal = TrainingGoal.Strength, calorieMode = CalorieMode.Deficit)
        )

        assertEquals(15, muscleGainSurplus.size)
        assertEquals(11.0, muscleGainSurplus.getValue("chest"), 0.0001)
        assertEquals(8.25, muscleGainSurplus.getValue("biceps"), 0.0001)
        assertEquals(5.5, muscleGainSurplus.getValue("forearms"), 0.0001)
        assertEquals(15, deficit.size)
        assertEquals(7.0, deficit.getValue("quads"), 0.0001)
        assertEquals(5.25, deficit.getValue("abs"), 0.0001)
        assertEquals(4.0, deficit.getValue("lowerBack"), 0.0001)
    }

    @Test
    fun weeklyEffectiveSetsUseExactSevenDayWindowAndFractionalKnownMappings() {
        val window = 7L * 24L * 60L * 60L * 1_000L
        fun entry(id: Long, timestamp: Long) = ExerciseHistoryEntry(
            setId = id,
            sessionId = id,
            sessionDate = timestamp,
            exerciseId = 99,
            exerciseName = "Weekly marker",
            weight = 1.0,
            reps = 1,
            setOrderIndex = 0
        )
        val mappings = mapOf(
            "weekly marker" to listOf(
                MuscleContribution("chest", 0.5),
                MuscleContribution("unknown", 1.0),
                MuscleContribution("biceps", Double.NaN)
            )
        )

        val completed = WorkoutRecommendationEngine.completedWeeklyEffectiveSets(
            history = listOf(
                entry(1, nowMillis - window),
                entry(2, nowMillis),
                entry(3, nowMillis - window - 1),
                entry(4, nowMillis + 1)
            ),
            nowMillis = nowMillis,
            manualMuscleMappings = mappings
        )

        assertEquals(1.0, completed.getValue("chest"), 0.0001)
        assertEquals(0.0, completed.getValue("biceps"), 0.0001)
        assertFalse(completed.containsKey("unknown"))
    }

    @Test
    fun saturatedManualMuscleMappingLosesToNeglectedAccessoriesWithoutChangingRoles() {
        val requiredCatalog = listOf(
            ExerciseEntity(id = 1, name = "Bench Press"),
            ExerciseEntity(id = 2, name = "Barbell Row"),
            ExerciseEntity(id = 3, name = "Squat"),
            ExerciseEntity(id = 4, name = "Plank"),
            ExerciseEntity(id = 5, name = "Alpha accessory"),
            ExerciseEntity(id = 6, name = "Beta accessory"),
            ExerciseEntity(id = 7, name = "Gamma accessory")
        )
        val mappings = mapOf(
            "weekly marker" to listOf(MuscleContribution("chest", 1.0)),
            "alpha accessory" to listOf(MuscleContribution("chest", 1.0)),
            "beta accessory" to listOf(MuscleContribution("biceps", 1.0)),
            "gamma accessory" to listOf(MuscleContribution("calves", 1.0))
        )
        val chestHistory = List(8) { index ->
            ExerciseHistoryEntry(
                setId = index.toLong() + 1,
                sessionId = 100 + index.toLong(),
                sessionDate = nowMillis - 60_000L,
                exerciseId = 99,
                exerciseName = "Weekly marker",
                weight = 1.0,
                reps = 1,
                setOrderIndex = 0
            )
        }
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = requiredCatalog,
            history = chestHistory,
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 6,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId,
            manualMuscleMappings = mappings
        )

        assertEquals(6, plan.exercises.size)
        assertFalse(plan.exerciseNames().contains("Alpha accessory"))
        assertTrue(plan.exerciseNames().contains("Beta accessory"))
        assertTrue(plan.exerciseNames().contains("Gamma accessory"))
        assertEquals(1, plan.exercises.count { it.exercise.name == "Plank" })
    }

    @Test
    fun projectedWeeklySetsPreventFillerSlotsFromOverConcentratingOneMuscle() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = listOf(
                ExerciseEntity(id = 1, name = "Bench Press"),
                ExerciseEntity(id = 2, name = "Barbell Row"),
                ExerciseEntity(id = 3, name = "Squat"),
                ExerciseEntity(id = 4, name = "Plank"),
                ExerciseEntity(id = 5, name = "Alpha biceps accessory"),
                ExerciseEntity(id = 6, name = "Beta biceps accessory"),
                ExerciseEntity(id = 7, name = "Zeta calves accessory")
            ),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 6,
                goal = TrainingGoal.Strength,
                calorieMode = CalorieMode.Deficit
            ),
            nowMillis = nowMillis,
            zoneId = zoneId,
            manualMuscleMappings = mapOf(
                "alpha biceps accessory" to listOf(MuscleContribution("biceps", 1.0)),
                "beta biceps accessory" to listOf(MuscleContribution("biceps", 1.0)),
                "zeta calves accessory" to listOf(MuscleContribution("calves", 1.0))
            )
        )

        val names = plan.exerciseNames()
        assertEquals(1, names.count { it.contains("accessory") })
        assertTrue(names.any { it.contains("biceps accessory") || it == "Zeta calves accessory" })
        assertTrue(plan.exercises.all { exercise ->
            exercise.recommendation.sets.size in 3..4 &&
                exercise.recommendation.sets.all { it.reps <= 10 }
        })
    }

    @Test
    fun autoUsesRecoveryOnlyWhenAtLeastHalfOfTargetMusclesWereJustTrained() {
        val recentFullBodyHistory = session(1, 1, 1, "Bench Press") +
            session(2, 1, 4, "Cable Row") +
            session(3, 1, 7, "Squat") +
            session(4, 1, 13, "Weighted Crunch")
        val profile = TrainingProfile(
            split = TrainingSplit.FullBody,
            workoutsPerWeek = 4,
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance
        )

        val recovery = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = recentFullBodyHistory,
            trainingProfile = profile,
            effort = SmartWorkoutEffort.Auto,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val standard = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = profile,
            effort = SmartWorkoutEffort.Auto,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutEffort.Auto, recovery.requestedEffort)
        assertEquals(SmartWorkoutEffort.Recovery, recovery.appliedEffort)
        assertEquals(SmartWorkoutEffortAdjustment.AutoRecovery, recovery.effortAdjustment)
        assertEquals(6, recovery.exercises.size)
        assertTrue(recovery.exercises.all { it.recommendation.sets.size == 3 })
        assertEquals(SmartWorkoutEffort.Standard, standard.appliedEffort)
        assertFalse(standard.appliedEffort == SmartWorkoutEffort.Hard)
    }

    @Test
    fun splitPlansReserveBothMovementPlanesBeforeAccessoryFillers() {
        val upper = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.UpperLower,
                workoutsPerWeek = 4
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val push = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.PushPullLegs,
                workoutsPerWeek = 4
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val pull = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = session(1, 2, 1, "Bench Press"),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.PushPullLegs,
                workoutsPerWeek = 4
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutFocus.Upper, upper.focus)
        assertTrue(upper.exerciseNames().any { it == "Bench Press" || it == "Dumbbell Bench Press" })
        assertTrue(upper.exerciseNames().contains("Shoulder Press"))
        assertTrue(upper.exerciseNames().any { it == "Cable Row" || it == "Barbell Row" })
        assertTrue(upper.exerciseNames().any { it == "Pull Up" || it == "Lat Pulldown" || it == "Crane Pulldown" })

        assertEquals(SmartWorkoutFocus.Push, push.focus)
        assertTrue(push.exerciseNames().any { it == "Bench Press" || it == "Dumbbell Bench Press" })
        assertTrue(push.exerciseNames().contains("Shoulder Press"))

        assertEquals(SmartWorkoutFocus.Pull, pull.focus)
        assertTrue(pull.exerciseNames().any { it == "Cable Row" || it == "Barbell Row" })
        assertTrue(pull.exerciseNames().any { it == "Pull Up" || it == "Lat Pulldown" || it == "Crane Pulldown" })
    }

    @Test
    fun hardEffortUsesLowRirOnlyForPreparedEligibleCompounds() {
        val benchHistory = exerciseSession(
            sessionId = 1,
            daysAgo = 4,
            weights = List(4) { 80.0 },
            reps = List(4) { 8 },
            exerciseName = "Bench Press"
        ) + exerciseSession(
            sessionId = 2,
            daysAgo = 2,
            weights = List(4) { 80.0 },
            reps = List(4) { 8 },
            exerciseName = "Bench Press"
        )
        val curlHistory = exerciseSession(
            sessionId = 3,
            daysAgo = 4,
            weights = List(3) { 20.0 },
            reps = List(3) { 9 },
            exerciseId = 6,
            exerciseName = "Biceps Curl"
        ) + exerciseSession(
            sessionId = 4,
            daysAgo = 2,
            weights = List(3) { 20.0 },
            reps = List(3) { 9 },
            exerciseId = 6,
            exerciseName = "Biceps Curl"
        )

        val compound = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Bench Press",
            history = benchHistory,
            effort = SmartWorkoutEffort.Hard,
            hardSetEligible = true,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val accessory = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 6,
            exerciseName = "Biceps Curl",
            history = curlHistory,
            effort = SmartWorkoutEffort.Hard,
            hardSetEligible = false,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(4, compound.sets.size)
        assertEquals(1..2, compound.targetRir)
        assertEquals(3, accessory.sets.size)
        assertEquals(2..3, accessory.targetRir)
    }

    @Test
    fun newCompoundDoesNotConsumeOneOfTwoPreparedHardSlots() {
        val exercises = listOf(
            ExerciseEntity(id = 1, name = "Bench Press", isFavorite = true),
            ExerciseEntity(id = 2, name = "Dumbbell Bench Press"),
            ExerciseEntity(id = 3, name = "Cable Row"),
            ExerciseEntity(id = 4, name = "Bulgarian Split Squat"),
            ExerciseEntity(id = 5, name = "Weighted Crunch")
        )
        val history = exerciseSession(11, 2, List(3) { 30.0 }, List(3) { 8 }, 2, "Dumbbell Bench Press") +
            exerciseSession(12, 4, List(3) { 30.0 }, List(3) { 8 }, 2, "Dumbbell Bench Press") +
            exerciseSession(13, 3, List(3) { 20.0 }, List(3) { 8 }, 4, "Bulgarian Split Squat") +
            exerciseSession(14, 5, List(3) { 20.0 }, List(3) { 8 }, 4, "Bulgarian Split Squat")

        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = exercises,
            history = history,
            trainingProfile = TrainingProfile(split = TrainingSplit.FullBody, workoutsPerWeek = 6),
            effort = SmartWorkoutEffort.Hard,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val newCompound = plan.exercises.single { it.exercise.id == 1L }.recommendation
        val hardPrepared = plan.exercises.filter { it.recommendation.targetRir == 1..2 }
        val newCompoundIndex = plan.exercises.indexOfFirst { it.exercise.id == 1L }
        val lastHardIndex = plan.exercises.indexOfLast { it.recommendation.targetRir == 1..2 }

        assertEquals(SmartWorkoutEffort.Hard, plan.appliedEffort)
        assertTrue(plan.exerciseNames().toString(), newCompoundIndex in 0 until lastHardIndex)
        assertEquals(3, newCompound.sets.size)
        assertEquals(2..3, newCompound.targetRir)
        assertEquals(2, hardPrepared.size)
        assertTrue(hardPrepared.all { it.recommendation.sets.size == 4 })
    }

    @Test
    fun hardRequestDowngradesWhenGlobalHistoryIsInsufficient() {
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = session(1, 2, 1, "Bench Press"),
            trainingProfile = TrainingProfile(split = TrainingSplit.FullBody),
            effort = SmartWorkoutEffort.Hard,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(SmartWorkoutEffort.Hard, plan.requestedEffort)
        assertEquals(SmartWorkoutEffort.Standard, plan.appliedEffort)
        assertEquals(SmartWorkoutEffortAdjustment.HardInsufficientHistory, plan.effortAdjustment)
        assertTrue(plan.exercises.none { it.recommendation.targetRir == 1..2 })
    }

    @Test
    fun recoveryUsesActualStackAndBodyweightKeepsZeroLoad() {
        val machine = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 21,
            exerciseName = "Lat Pulldown",
            history = exerciseSession(1, 2, List(3) { 77.0 }, List(3) { 8 }, 21, "Lat Pulldown"),
            effort = SmartWorkoutEffort.Recovery,
            loadProfile = ExerciseLoadProfile(
                ExerciseLoadDirection.HigherIsHarder,
                listOf(69.0, 73.0, 77.0)
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val assisted = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 30,
            exerciseName = "Assisted Pull Up",
            history = exerciseSession(2, 2, List(3) { 50.0 }, List(3) { 8 }, 30, "Assisted Pull Up"),
            effort = SmartWorkoutEffort.Recovery,
            loadProfile = ExerciseLoadProfile(
                ExerciseLoadDirection.LowerIsHarder,
                listOf(50.0, 55.0, 60.0)
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val bodyweight = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 31,
            exerciseName = "Push Up",
            history = exerciseSession(3, 2, List(3) { 0.0 }, List(3) { 8 }, 31, "Push Up"),
            effort = SmartWorkoutEffort.Recovery,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val freshBodyweight = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 32,
            exerciseName = "Pull Up",
            history = emptyList(),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(List(3) { 69.0 }, machine.sets.map { it.weight })
        assertEquals(List(3) { 60.0 }, assisted.sets.map { it.weight })
        assertEquals(List(3) { 0.0 }, bodyweight.sets.map { it.weight })
        assertEquals(List(3) { 7 }, bodyweight.sets.map { it.reps })
        assertEquals(3..4, bodyweight.targetRir)
        assertTrue(freshBodyweight.sets.all { it.weight == 0.0 })
    }

    @Test
    fun longComebackUsesMeaningfulPercentageInsteadOfOneGridStep() {
        val comeback = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Bench Press",
            history = exerciseSession(1, 45, List(4) { 200.0 }, List(4) { 6 }),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.Comeback, comeback.kind)
        assertEquals(List(3) { 162.5 }, comeback.sets.map { it.weight })
        assertEquals(3..4, comeback.targetRir)
    }

    @Test
    fun comebackOverridesRequestedHardSetsAndRir() {
        val history = exerciseSession(1, 24, List(4) { 100.0 }, List(4) { 6 }) +
            exerciseSession(2, 20, List(4) { 100.0 }, List(4) { 6 })
        val comeback = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Bench Press",
            history = history,
            effort = SmartWorkoutEffort.Hard,
            hardSetEligible = true,
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(WorkoutRecommendationKind.Comeback, comeback.kind)
        assertEquals(3, comeback.sets.size)
        assertEquals(3..4, comeback.targetRir)
        assertFalse(
            comeback.reasons.contains(
                com.example.gymapp.data.repository.WorkoutRecommendationReason.HardEffort
            )
        )

        val bodyweightRecovery = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 31,
            exerciseName = "Push Up",
            history = exerciseSession(3, 20, List(3) { 0.0 }, List(3) { 8 }, 31, "Push Up"),
            effort = SmartWorkoutEffort.Recovery,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        assertEquals(WorkoutRecommendationKind.Comeback, bodyweightRecovery.kind)
        assertEquals(List(3) { 8 }, bodyweightRecovery.sets.map { it.reps })
    }

    @Test
    fun alternativesMatchMovementExcludeSelectedAndUseReplacementHistory() {
        val exercises = listOf(
            ExerciseEntity(id = 1, name = "Bench Press"),
            ExerciseEntity(id = 2, name = "Dumbbell Bench Press"),
            ExerciseEntity(id = 3, name = "Incline Bench Press"),
            ExerciseEntity(id = 4, name = "Cable Row"),
            ExerciseEntity(id = 5, name = "Biceps Curl")
        )
        val history = exerciseSession(1, 4, List(3) { 100.0 }, List(3) { 8 }, 1, "Bench Press") +
            exerciseSession(2, 2, List(3) { 100.0 }, List(3) { 8 }, 1, "Bench Press") +
            exerciseSession(3, 2, List(3) { 30.0 }, List(3) { 8 }, 3, "Incline Bench Press")

        val alternatives = WorkoutRecommendationEngine.findAlternatives(
            currentExerciseId = 1,
            selectedExerciseIds = setOf(1, 2, 4),
            exercises = exercises,
            history = history,
            nowMillis = nowMillis,
            zoneId = zoneId,
            limit = 20
        )
        val incline = alternatives.single { it.exercise.id == 3L }

        assertTrue(alternatives.size <= 6)
        assertFalse(alternatives.any { it.exercise.id in setOf(1L, 2L, 4L, 5L) })
        assertTrue(incline.recommendation.sets.all { it.weight == 30.0 })

        val staleRecomputed = WorkoutRecommendationEngine.findAlternatives(
            currentExerciseId = 1,
            selectedExerciseIds = setOf(1, 2, 3, 4),
            exercises = exercises,
            history = history,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        assertFalse(staleRecomputed.any { it.exercise.id == 3L })
    }

    @Test
    fun recommendationPolicyKeepsManualDraftStandardAndHardAllowlistExact() {
        val beforeGeneration = smartWorkoutRecommendationPolicy(
            selectedEffort = SmartWorkoutEffort.Hard,
            currentProfile = TrainingProfile(),
            generatedPlan = null
        )
        val generatedPlan = SmartWorkoutPlanSummaryUiModel(
            focus = SmartWorkoutFocus.FullBody,
            variant = SmartWorkoutVariant.A,
            requestedEffort = SmartWorkoutEffort.Hard,
            appliedEffort = SmartWorkoutEffort.Hard,
            effortAdjustment = null,
            hardExerciseIds = setOf(1L, 2L),
            trainingProfileSnapshot = TrainingProfile()
        )
        val generatedPolicy = smartWorkoutRecommendationPolicy(
            selectedEffort = SmartWorkoutEffort.Hard,
            currentProfile = TrainingProfile(),
            generatedPlan = generatedPlan
        )
        val stalePolicy = smartWorkoutRecommendationPolicy(
            selectedEffort = SmartWorkoutEffort.Standard,
            currentProfile = TrainingProfile(),
            generatedPlan = generatedPlan
        )
        val changedProfilePolicy = smartWorkoutRecommendationPolicy(
            selectedEffort = SmartWorkoutEffort.Hard,
            currentProfile = TrainingProfile(goal = TrainingGoal.Strength),
            generatedPlan = generatedPlan
        )

        assertEquals(SmartWorkoutEffort.Standard, beforeGeneration.effort)
        assertTrue(beforeGeneration.hardExerciseIds.isEmpty())
        assertEquals(SmartWorkoutEffort.Hard, generatedPolicy.effort)
        assertEquals(setOf(1L, 2L), generatedPolicy.hardExerciseIds)
        assertEquals(SmartWorkoutEffort.Standard, stalePolicy.effort)
        assertTrue(stalePolicy.hardExerciseIds.isEmpty())
        assertEquals(SmartWorkoutEffort.Standard, changedProfilePolicy.effort)
        assertTrue(changedProfilePolicy.hardExerciseIds.isEmpty())
        assertFalse(
            smartWorkoutPlanNeedsRefresh(
                selectedEffort = SmartWorkoutEffort.Hard,
                currentProfile = TrainingProfile(),
                generatedPlan = generatedPlan
            )
        )
        assertTrue(
            smartWorkoutPlanNeedsRefresh(
                selectedEffort = SmartWorkoutEffort.Standard,
                currentProfile = TrainingProfile(),
                generatedPlan = generatedPlan
            )
        )

        val names = mapOf(
            1L to "Bench Press",
            2L to "Barbell Row",
            3L to "Squat",
            4L to "Deadlift"
        )
        val recommendations = names.map { (exerciseId, exerciseName) ->
            val history = exerciseSession(
                sessionId = exerciseId * 10,
                daysAgo = 4,
                weights = List(3) { 60.0 },
                reps = List(3) { 6 },
                exerciseId = exerciseId,
                exerciseName = exerciseName
            ) + exerciseSession(
                sessionId = exerciseId * 10 + 1,
                daysAgo = 2,
                weights = List(3) { 60.0 },
                reps = List(3) { 6 },
                exerciseId = exerciseId,
                exerciseName = exerciseName
            )
            WorkoutRecommendationEngine.buildForExercise(
                exerciseId = exerciseId,
                exerciseName = exerciseName,
                history = history,
                effort = generatedPolicy.effort,
                hardSetEligible = exerciseId in generatedPolicy.hardExerciseIds,
                nowMillis = nowMillis,
                zoneId = zoneId
            )
        }

        assertEquals(2, recommendations.count { it.targetRir == 1..2 && it.sets.size == 4 })
        assertEquals(2, recommendations.count { it.targetRir == 2..3 && it.sets.size == 3 })
    }

    @Test
    fun everyProfileInputMateriallyChangesTheGeneratedSession() {
        fun plan(profile: TrainingProfile) = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog(),
            history = emptyList(),
            trainingProfile = profile,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        fun workingSets(profile: TrainingProfile): Int =
            plan(profile).exercises.sumOf { it.recommendation.sets.size }

        val base = TrainingProfile(
            split = TrainingSplit.FullBody,
            workoutsPerWeek = 4,
            goal = TrainingGoal.Balanced,
            calorieMode = CalorieMode.Maintenance
        )
        val strengthPlan = plan(base.copy(goal = TrainingGoal.Strength))
        val balancedPlan = plan(base)
        val muscleGainPlan = plan(base.copy(goal = TrainingGoal.MuscleGain))
        val strengthSets = strengthPlan.exercises.sumOf { it.recommendation.sets.size }
        val balancedSets = balancedPlan.exercises.sumOf { it.recommendation.sets.size }
        val muscleGainSets = muscleGainPlan.exercises.sumOf { it.recommendation.sets.size }
        assertTrue(strengthSets < balancedSets)
        assertTrue(balancedSets <= muscleGainSets)
        assertTrue(balancedPlan.exercises != muscleGainPlan.exercises)

        val deficitPlan = plan(base.copy(calorieMode = CalorieMode.Deficit))
        val surplusPlan = plan(base.copy(calorieMode = CalorieMode.Surplus))
        val deficitSets = deficitPlan.exercises.sumOf { it.recommendation.sets.size }
        val surplusSets = surplusPlan.exercises.sumOf { it.recommendation.sets.size }
        assertTrue(deficitSets < balancedSets)
        assertTrue(balancedSets <= surplusSets)
        assertTrue(balancedPlan.exercises != surplusPlan.exercises)

        assertTrue(
            workingSets(base.copy(workoutsPerWeek = 2)) >
                workingSets(base.copy(workoutsPerWeek = 6))
        )
        val upperLower = plan(base.copy(split = TrainingSplit.UpperLower))
        val pushPullLegs = plan(base.copy(split = TrainingSplit.PushPullLegs))
        assertTrue(upperLower.focus != pushPullLegs.focus)
        assertTrue(upperLower.exerciseNames() != pushPullLegs.exerciseNames())
    }

    @Test
    fun saturatedWeeklyTargetsKeepRequiredMovementsAndTrunkButStopFillers() {
        val allMuscles = listOf(
            "chest", "shoulders", "triceps", "lats", "upperBack", "biceps", "forearms",
            "quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack", "abs", "obliques"
        )
        val history = List(12) { index ->
            ExerciseHistoryEntry(
                setId = index.toLong() + 1,
                sessionId = index.toLong() + 100,
                sessionDate = nowMillis - 60_000L,
                exerciseId = 99,
                exerciseName = "Saturation marker",
                weight = 1.0,
                reps = 1,
                setOrderIndex = 0
            )
        }
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = listOf(
                ExerciseEntity(1, "Bench Press"),
                ExerciseEntity(2, "Barbell Row"),
                ExerciseEntity(3, "Squat"),
                ExerciseEntity(4, "Plank"),
                ExerciseEntity(5, "Biceps Curl"),
                ExerciseEntity(6, "Calf Raise")
            ),
            history = history,
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 4,
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            manualMuscleMappings = mapOf(
                "saturation marker" to allMuscles.map { MuscleContribution(it, 1.0) }
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(setOf("Bench Press", "Barbell Row", "Squat", "Plank"), plan.exerciseNames().toSet())
        assertTrue(plan.exercises.all { it.recommendation.sets.size in 3..4 })
    }

    @Test
    fun recoveryBodyweightAndCanonicalEquipmentUseActionableProgrammingMetadata() {
        val recovery = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1,
            exerciseName = "Pull Up",
            history = emptyList(),
            effort = SmartWorkoutEffort.Recovery,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val progressed = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 2,
            exerciseName = "Push Up",
            history = exerciseSession(1, 3, List(3) { 0.0 }, List(3) { 10 }, 2, "Push Up") +
                exerciseSession(2, 1, List(3) { 0.0 }, List(3) { 10 }, 2, "Push Up"),
            trainingProfile = TrainingProfile(
                goal = TrainingGoal.Balanced,
                calorieMode = CalorieMode.Maintenance
            ),
            nowMillis = nowMillis,
            zoneId = zoneId
        )

        assertEquals(List(3) { 8 }, recovery.sets.map { it.reps })
        assertTrue(
            progressed.reasons.toString(),
            progressed.reasons.contains(WorkoutRecommendationReason.BodyweightProgressionNeeded)
        )
        assertEquals("Machine", WorkoutRecommendationEngine.canonicalEquipmentForExercise("Plate Loaded Row"))
        assertEquals("Dumbbell", WorkoutRecommendationEngine.canonicalEquipmentForExercise("Bulgarian Split Squat"))
        assertEquals(180, WorkoutRecommendationEngine.recommendedRestSeconds("Bench Press"))
        assertEquals(120, WorkoutRecommendationEngine.recommendedRestSeconds("Pull Up"))
        assertEquals(75, WorkoutRecommendationEngine.recommendedRestSeconds("Biceps Curl"))
        assertEquals(60, WorkoutRecommendationEngine.recommendedRestSeconds("Plank"))
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
        ExerciseEntity(id = 15, name = "Crane Pulldown"),
        ExerciseEntity(id = 17, name = "Dumbbell Bench Press"),
        ExerciseEntity(id = 18, name = "Chest Fly Machine"),
        ExerciseEntity(id = 19, name = "Dips"),
        ExerciseEntity(id = 20, name = "Barbell Row"),
        ExerciseEntity(id = 21, name = "Lat Pulldown"),
        ExerciseEntity(id = 22, name = "Hammer Curl"),
        ExerciseEntity(id = 23, name = "Deadlift"),
        ExerciseEntity(id = 24, name = "Hip Thrust"),
        ExerciseEntity(id = 25, name = "Bulgarian Split Squat"),
        ExerciseEntity(id = 26, name = "Lunge"),
        ExerciseEntity(id = 27, name = "Seated Leg Curl"),
        ExerciseEntity(id = 28, name = "Hip Adduction"),
        ExerciseEntity(id = 29, name = "Hip Abduction")
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
