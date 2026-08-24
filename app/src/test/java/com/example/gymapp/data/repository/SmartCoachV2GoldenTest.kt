package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartCoachV2GoldenTest {
    @Test
    fun sharedGoldenVectorsExecuteAndroidPolicyEngine() {
        val root = JSONObject(sharedFixture().readText())
        assertEquals(SMART_COACH_V2_CONTRACT_VERSION, root.getInt("contractVersion"))

        val vectors = root.getJSONArray("vectors")
        repeat(vectors.length()) { index ->
            val vector = vectors.getJSONObject(index)
            val input = vector.getJSONObject("input")
            val expected = vector.getJSONObject("expected")
            val name = vector.getString("name")
            val adaptation = resolveSmartCoachV2(input.toScenario())

            assertEquals(name, expected.getBoolean("eligible"), adaptation.eligible)
            assertEquals(name, expected.getString("appliedEffort"), adaptation.appliedEffort.wireValue())
            assertEquals(name, expected.getInt("setBudget"), adaptation.setBudget)
            assertEquals(name, expected.getJSONArray("targetRir").getInt(0), adaptation.targetRir.first)
            assertEquals(name, expected.getJSONArray("targetRir").getInt(1), adaptation.targetRir.last)
            assertEquals(name, expected.getInt("restSeconds"), adaptation.restSeconds)
            assertEquals(name, expected.getInt("loadAdjustmentSteps"), adaptation.loadAdjustmentSteps)
            assertEquals(name, expected.getInt("confidenceDeltaMilli"), (adaptation.confidenceDelta * 1_000).toInt())
            assertEquals(name, expected.getInt("freshForSeconds"), adaptation.freshForSeconds)
            assertEquals(
                name,
                expected.getJSONArray("reasons").strings(),
                adaptation.reasons.map(SmartCoachV2Reason::wireValue)
            )
        }
    }

    @Test
    fun androidPlanEngineAppliesV2ContextFeedbackAndCoreRest() {
        val exercises = BuiltInExerciseCatalog.definitions.mapIndexed { index, definition ->
            ExerciseEntity(id = index + 1L, name = definition.nameEn)
        }
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = exercises,
            history = emptyList(),
            trainingProfile = TrainingProfile(
                split = TrainingSplit.FullBody,
                workoutsPerWeek = 2,
                goal = TrainingGoal.MuscleGain,
                calorieMode = CalorieMode.Surplus
            ),
            context = SmartCoachContextV2(
                readiness = SmartCoachReadinessV2.Low,
                availableMinutes = 45
            )
        )

        assertEquals(SMART_COACH_V2_CONTRACT_VERSION, plan.contractVersion)
        assertEquals(SMART_COACH_V2_FRESH_FOR_SECONDS, plan.freshForSeconds)
        assertEquals(SmartWorkoutEffort.Recovery, plan.appliedEffort)
        assertEquals(15, plan.setBudget)
        assertTrue(plan.exercises.sumOf { it.recommendation.sets.size } <= requireNotNull(plan.setBudget))
        assertTrue(SmartCoachV2Reason.ReadinessRecovery in plan.adaptationReasons)
        assertTrue(SmartCoachV2Reason.TimeCapped in plan.adaptationReasons)
        assertNotNull(plan.estimatedMinutes)

        val baseline = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 10_001L,
            history = emptyList(),
            exerciseName = "Bench Press"
        )
        val protected = WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 10_001L,
            history = emptyList(),
            exerciseName = "Bench Press",
            exerciseFeedback = listOf(
                SmartCoachExerciseFeedbackSignalV2(
                    actualRir = 1,
                    outcome = SmartCoachExerciseFeedbackOutcomeV2.TooHard,
                    ageDays = 1
                )
            )
        )
        assertEquals(baseline.sets.map { (it.reps - 1).coerceAtLeast(1) }, protected.sets.map { it.reps })
        assertEquals(3..4, protected.targetRir)
        assertTrue(WorkoutRecommendationReason.ExerciseFeedbackTooHard in protected.reasons)

        val core = SmartWorkoutExercise(
            exercise = ExerciseEntity(id = 10_002L, name = "Weighted Crunch"),
            recommendation = WorkoutRecommendationEngine.buildForExercise(
                exerciseId = 10_002L,
                history = emptyList(),
                exerciseName = "Weighted Crunch"
            )
        )
        assertEquals(60, core.recommendedRestSeconds)
    }

    private fun JSONObject.toScenario(): SmartCoachV2Scenario = SmartCoachV2Scenario(
        requestedEffort = SmartWorkoutEffort.values().single {
            it.wireValue() == getString("requestedEffort")
        },
        baseSetBudget = getInt("baseSetBudget"),
        role = SmartCoachExerciseRoleV2.values().single { it.wireValue == getString("role") },
        equipment = SmartCoachEquipmentV2.values().single { it.wireValue == getString("equipment") },
        primaryMuscles = optJSONArray("primaryMuscles")?.strings()?.toSet().orEmpty(),
        context = SmartCoachContextV2(
            readiness = optStringOrNull("readiness")?.let { wire ->
                SmartCoachReadinessV2.values().single { it.wireValue == wire }
            },
            availableMinutes = if (has("availableMinutes")) getInt("availableMinutes") else null,
            availableEquipment = optJSONArray("availableEquipment")?.strings()?.map { wire ->
                SmartCoachEquipmentV2.values().single { it.wireValue == wire }
            }?.toSet(),
            musclesToAvoid = optJSONArray("musclesToAvoid")?.strings()?.toSet().orEmpty()
        ),
        feedback = optJSONArray("feedback")?.objects()?.map { feedback ->
            SmartCoachExerciseFeedbackSignalV2(
                actualRir = if (feedback.has("actualRir")) feedback.getInt("actualRir") else null,
                outcome = SmartCoachExerciseFeedbackOutcomeV2.values().single {
                    it.wireValue == feedback.getString("outcome")
                },
                ageDays = feedback.getInt("ageDays")
            )
        }.orEmpty()
    )

    private fun SmartWorkoutEffort.wireValue(): String = name.replaceFirstChar(Char::lowercase)

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null

    private fun JSONArray.strings(): List<String> =
        List(length()) { index -> getString(index) }

    private fun JSONArray.objects(): List<JSONObject> =
        List(length()) { index -> getJSONObject(index) }

    private fun sharedFixture(): File {
        val direct = File("shared/smart-coach-v2-golden.json")
        if (direct.isFile) return direct
        return File("../shared/smart-coach-v2-golden.json").also {
            check(it.isFile) { "Shared Smart Coach v2 golden fixture was not found." }
        }
    }
}
