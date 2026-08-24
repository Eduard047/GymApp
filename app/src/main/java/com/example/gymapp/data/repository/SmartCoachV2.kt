package com.example.gymapp.data.repository

/** Normative, offline-only Smart Coach v2 inputs shared by Android, iOS and PWA. */
enum class SmartCoachReadinessV2(val wireValue: String) {
    Low("low"),
    Normal("normal"),
    High("high")
}

enum class SmartCoachEquipmentV2(val wireValue: String) {
    Barbell("barbell"),
    Dumbbell("dumbbell"),
    Cable("cable"),
    Machine("machine"),
    Bodyweight("bodyweight"),
    Assisted("assisted"),
    Band("band"),
    Other("other")
}

enum class SmartCoachExerciseFeedbackOutcomeV2(val wireValue: String) {
    OnTarget("onTarget"),
    TooEasy("tooEasy"),
    TooHard("tooHard"),
    EquipmentUnavailable("equipmentUnavailable"),
    TimeCut("timeCut")
}

enum class SmartCoachV2Reason(val wireValue: String) {
    ReadinessRecovery("readinessRecovery"),
    TimeCapped("timeCapped"),
    EquipmentUnavailable("equipmentUnavailable"),
    AvoidedMuscle("avoidedMuscle"),
    ExerciseFeedbackTooHard("exerciseFeedbackTooHard"),
    ExerciseFeedbackRepeatedEasy("exerciseFeedbackRepeatedEasy")
}

enum class SmartCoachExerciseRoleV2(val wireValue: String) {
    Primary("primary"),
    Secondary("secondary"),
    Isolation("isolation"),
    Core("core"),
    Warmup("warmup")
}

data class SmartCoachExerciseFeedbackSignalV2(
    val actualRir: Int? = null,
    val outcome: SmartCoachExerciseFeedbackOutcomeV2 =
        SmartCoachExerciseFeedbackOutcomeV2.OnTarget,
    val ageDays: Int
)

data class SmartCoachContextV2(
    val readiness: SmartCoachReadinessV2? = null,
    val availableMinutes: Int? = null,
    /** Null is unrestricted. A present set must contain 1..8 canonical equipment values. */
    val availableEquipment: Set<SmartCoachEquipmentV2>? = null,
    val musclesToAvoid: Set<String> = emptySet()
) {
    fun isValid(): Boolean =
        (availableMinutes == null || availableMinutes in MIN_AVAILABLE_MINUTES..MAX_AVAILABLE_MINUTES) &&
            (availableEquipment == null || availableEquipment.size in 1..MAX_EQUIPMENT_ITEMS) &&
            musclesToAvoid.size <= MAX_AVOIDED_MUSCLES &&
            musclesToAvoid.all(KNOWN_MUSCLE_IDS::contains)

    companion object {
        const val MIN_AVAILABLE_MINUTES = 30
        const val MAX_AVAILABLE_MINUTES = 120
        const val MAX_EQUIPMENT_ITEMS = 8
        const val MAX_AVOIDED_MUSCLES = 8
        val KNOWN_MUSCLE_IDS: Set<String> = setOf(
            "chest", "shoulders", "biceps", "triceps", "forearms", "abs", "obliques",
            "lats", "upperBack", "lowerBack", "glutes", "quads", "hamstrings",
            "adductors", "calves"
        )
    }
}

data class SmartCoachV2Scenario(
    val requestedEffort: SmartWorkoutEffort,
    val baseSetBudget: Int,
    val role: SmartCoachExerciseRoleV2,
    val equipment: SmartCoachEquipmentV2,
    val primaryMuscles: Set<String> = emptySet(),
    val context: SmartCoachContextV2 = SmartCoachContextV2(),
    /** Newest first. Invalid or stale values are ignored, never coerced. */
    val feedback: List<SmartCoachExerciseFeedbackSignalV2> = emptyList()
)

data class SmartCoachV2Adaptation(
    val eligible: Boolean,
    val appliedEffort: SmartWorkoutEffort,
    val setBudget: Int,
    val targetRir: IntRange,
    val restSeconds: Int,
    val loadAdjustmentSteps: Int,
    val confidenceDelta: Float,
    val freshForSeconds: Int,
    val reasons: List<SmartCoachV2Reason>
)

const val SMART_COACH_V2_CONTRACT_VERSION = 2
const val SMART_COACH_V2_FRESH_FOR_SECONDS = 6 * 60 * 60
const val SMART_COACH_V2_MAX_FEEDBACK_AGE_DAYS = 14
const val SMART_COACH_V2_MAX_FEEDBACK_PER_EXERCISE = 8

/**
 * Small pure policy layer used by the real plan engines and common golden vectors.
 * History-based focus/progression remains in [WorkoutRecommendationEngine].
 */
fun resolveSmartCoachV2(scenario: SmartCoachV2Scenario): SmartCoachV2Adaptation {
    require(scenario.baseSetBudget in 12..24)
    require(scenario.primaryMuscles.all(SmartCoachContextV2.KNOWN_MUSCLE_IDS::contains))
    require(scenario.context.isValid())

    val reasons = mutableListOf<SmartCoachV2Reason>()
    val appliedEffort = when {
        scenario.context.readiness == SmartCoachReadinessV2.Low -> {
            reasons += SmartCoachV2Reason.ReadinessRecovery
            SmartWorkoutEffort.Recovery
        }
        scenario.requestedEffort == SmartWorkoutEffort.Auto -> SmartWorkoutEffort.Standard
        else -> scenario.requestedEffort
    }
    val timeCap = scenario.context.availableMinutes?.let { minutes ->
        (minutes / 3).coerceIn(12, 24)
    }
    val setBudget = minOf(scenario.baseSetBudget, timeCap ?: scenario.baseSetBudget)
    if (setBudget < scenario.baseSetBudget) reasons += SmartCoachV2Reason.TimeCapped

    var eligible = true
    scenario.context.availableEquipment?.let { available ->
        if (scenario.equipment !in available) {
            eligible = false
            reasons += SmartCoachV2Reason.EquipmentUnavailable
        }
    }
    if (scenario.primaryMuscles.any(scenario.context.musclesToAvoid::contains)) {
        eligible = false
        reasons += SmartCoachV2Reason.AvoidedMuscle
    }

    val usableFeedback = scenario.feedback
        .asSequence()
        .take(SMART_COACH_V2_MAX_FEEDBACK_PER_EXERCISE)
        .filter { signal ->
            signal.ageDays in 0..SMART_COACH_V2_MAX_FEEDBACK_AGE_DAYS &&
                (signal.actualRir == null || signal.actualRir in 0..5) &&
                signal.outcome !in setOf(
                    SmartCoachExerciseFeedbackOutcomeV2.EquipmentUnavailable,
                    SmartCoachExerciseFeedbackOutcomeV2.TimeCut
                )
        }
        .toList()
    val latest = usableFeedback.firstOrNull()
    val latestIsHard = latest?.outcome == SmartCoachExerciseFeedbackOutcomeV2.TooHard ||
        latest?.actualRir?.let { it <= 1 } == true
    val firstTwoAreEasy = usableFeedback.take(2).size == 2 &&
        usableFeedback.take(2).all { signal ->
            signal.outcome == SmartCoachExerciseFeedbackOutcomeV2.TooEasy ||
                signal.actualRir?.let { it >= 4 } == true
        }
    val loadAdjustmentSteps = when {
        latestIsHard -> {
            reasons += SmartCoachV2Reason.ExerciseFeedbackTooHard
            -1
        }
        firstTwoAreEasy -> {
            reasons += SmartCoachV2Reason.ExerciseFeedbackRepeatedEasy
            1
        }
        else -> 0
    }
    val targetRir = when {
        latestIsHard || appliedEffort == SmartWorkoutEffort.Recovery -> 3..4
        appliedEffort == SmartWorkoutEffort.Hard &&
            scenario.role in setOf(
                SmartCoachExerciseRoleV2.Primary,
                SmartCoachExerciseRoleV2.Secondary
            ) -> 1..2
        else -> 2..3
    }
    val restSeconds = when (scenario.role) {
        SmartCoachExerciseRoleV2.Primary -> 180
        SmartCoachExerciseRoleV2.Secondary -> 120
        SmartCoachExerciseRoleV2.Isolation -> 75
        SmartCoachExerciseRoleV2.Core,
        SmartCoachExerciseRoleV2.Warmup -> 60
    }
    return SmartCoachV2Adaptation(
        eligible = eligible,
        appliedEffort = appliedEffort,
        setBudget = setBudget,
        targetRir = targetRir,
        restSeconds = restSeconds,
        loadAdjustmentSteps = loadAdjustmentSteps,
        confidenceDelta = if (loadAdjustmentSteps == 0) 0f else 0.05f,
        freshForSeconds = SMART_COACH_V2_FRESH_FOR_SECONDS,
        reasons = reasons.take(4)
    )
}
