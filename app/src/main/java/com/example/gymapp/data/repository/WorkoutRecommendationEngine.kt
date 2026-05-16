package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

data class RecommendedWorkoutSet(
    val weight: Double?,
    val reps: Int
)

enum class WorkoutRecommendationKind {
    NewExercise,
    ProgressiveOverload,
    HoldAndBuild,
    Deload,
    Comeback,
    PlateauBreak
}

enum class WorkoutRecommendationReason {
    NoHistory,
    LastSessionStrong,
    LastSessionUnstable,
    RecentBreak,
    VolumeTrendingUp,
    VolumeDropped,
    PlateauDetected,
    NearPersonalBest,
    ConservativeIncrease,
    AestheticGoal,
    CalorieDeficit,
    FourDayUpperLower
}

data class WorkoutRecommendation(
    val exerciseId: Long,
    val sets: List<RecommendedWorkoutSet>,
    val kind: WorkoutRecommendationKind,
    val confidence: Float,
    val estimatedVolume: Double,
    val daysSinceLastSession: Int?,
    val reasons: List<WorkoutRecommendationReason>
)

enum class SmartWorkoutFocus {
    Upper,
    Lower,
    Push,
    Pull,
    Legs,
    FullBody
}

data class SmartWorkoutExercise(
    val exercise: ExerciseEntity,
    val recommendation: WorkoutRecommendation
)

data class SmartWorkoutPlan(
    val focus: SmartWorkoutFocus,
    val exercises: List<SmartWorkoutExercise>
)

object WorkoutRecommendationEngine {
    private const val DefaultSetCount = 3
    private const val DefaultReps = 10
    private const val MaxHistorySets = 120
    private const val ComebackBreakDays = 10

    fun buildForExercise(
        exerciseId: Long,
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile = TrainingProfile(),
        nowMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): WorkoutRecommendation {
        val exerciseHistory = history
            .asSequence()
            .filter { it.exerciseId == exerciseId }
            .sortedWith(compareByDescending<ExerciseHistoryEntry> { it.sessionDate }.thenBy { it.setOrderIndex })
            .take(MaxHistorySets)
            .toList()

        if (exerciseHistory.isEmpty()) {
            return WorkoutRecommendation(
                exerciseId = exerciseId,
                sets = List(DefaultSetCount) { RecommendedWorkoutSet(weight = null, reps = DefaultReps) },
                kind = WorkoutRecommendationKind.NewExercise,
                confidence = 0.35f,
                estimatedVolume = 0.0,
                daysSinceLastSession = null,
                reasons = listOf(WorkoutRecommendationReason.NoHistory)
            )
        }

        val sessions = exerciseHistory
            .groupBy { it.sessionId }
            .values
            .map { entries -> ExerciseSessionSnapshot(entries.sortedBy { it.setOrderIndex }) }
            .sortedByDescending { it.date }

        val latest = sessions.first()
        val previous = sessions.getOrNull(1)
        val daysSinceLastSession = daysBetween(latest.date, nowMillis, zoneId)
        val recentSessions = sessions.take(5)
        val bestEstimatedMax = sessions.maxOf { it.estimatedMax }
        val recentMaxWeights = recentSessions.map { it.maxWeight }
        val plateauDetected = recentMaxWeights.size >= 4 &&
            recentMaxWeights.maxOrNull() != null &&
            recentMaxWeights.minOrNull() != null &&
            abs(recentMaxWeights.max() - recentMaxWeights.min()) <= 1.25
        val latestNearBest = latest.estimatedMax >= bestEstimatedMax * 0.97
        val previousVolume = previous?.volume ?: latest.volume
        val volumeRatio = if (previousVolume <= 0.0) 1.0 else latest.volume / previousVolume
        val latestStable = latest.minReps >= 8 && latest.sets.size >= 3
        val latestStrained = latest.minReps <= 5 || volumeRatio < 0.88
        val isFatLossDeficit = trainingProfile.goal == TrainingGoal.AestheticFatLoss &&
            trainingProfile.calorieMode == CalorieMode.Deficit

        val kind = when {
            daysSinceLastSession >= ComebackBreakDays -> WorkoutRecommendationKind.Comeback
            latestStrained || (isFatLossDeficit && volumeRatio < 0.96) -> WorkoutRecommendationKind.Deload
            plateauDetected -> WorkoutRecommendationKind.PlateauBreak
            latestStable && volumeRatio >= 0.95 && !isFatLossDeficit -> WorkoutRecommendationKind.ProgressiveOverload
            else -> WorkoutRecommendationKind.HoldAndBuild
        }

        val targetSetCount = when {
            trainingProfile.goal == TrainingGoal.Strength -> latest.sets.size.coerceIn(3, 5)
            isFatLossDeficit -> latest.sets.size.coerceIn(3, 4)
            else -> latest.sets.size.coerceIn(2, 5)
        }
        val targetWeight = when (kind) {
            WorkoutRecommendationKind.NewExercise -> null
            WorkoutRecommendationKind.ProgressiveOverload -> latest.maxWeight + chooseWeightStep(
                weight = latest.maxWeight,
                trainingProfile = trainingProfile
            )
            WorkoutRecommendationKind.HoldAndBuild -> latest.maxWeight
            WorkoutRecommendationKind.Deload -> latest.maxWeight * if (isFatLossDeficit) 0.9 else 0.92
            WorkoutRecommendationKind.Comeback -> latest.maxWeight * comebackMultiplier(daysSinceLastSession)
            WorkoutRecommendationKind.PlateauBreak -> latest.maxWeight
        }?.let(::roundToNearestHalf)

        val targetReps = when (kind) {
            WorkoutRecommendationKind.NewExercise -> DefaultReps
            WorkoutRecommendationKind.ProgressiveOverload -> latest.averageReps.roundToInt().coerceIn(6, goalMaxReps(trainingProfile))
            WorkoutRecommendationKind.HoldAndBuild -> (latest.averageReps.roundToInt() + 1).coerceIn(8, goalMaxReps(trainingProfile))
            WorkoutRecommendationKind.Deload -> (latest.averageReps.roundToInt() + 1).coerceIn(8, 12)
            WorkoutRecommendationKind.Comeback -> latest.averageReps.roundToInt().coerceIn(8, 12)
            WorkoutRecommendationKind.PlateauBreak -> if (latest.averageReps >= 9.0 && !isFatLossDeficit) 6 else 11
        }

        val sets = List(targetSetCount) { index ->
            val reps = when {
                kind == WorkoutRecommendationKind.PlateauBreak && targetReps <= 6 -> (targetReps - index / 2).coerceAtLeast(4)
                index >= 3 -> (targetReps - 1).coerceAtLeast(5)
                else -> targetReps
            }
            RecommendedWorkoutSet(weight = targetWeight, reps = reps)
        }

        val reasons = buildList {
            if (latestStable) add(WorkoutRecommendationReason.LastSessionStrong)
            if (latestStrained) add(WorkoutRecommendationReason.LastSessionUnstable)
            if (daysSinceLastSession >= ComebackBreakDays) add(WorkoutRecommendationReason.RecentBreak)
            if (volumeRatio >= 1.08) add(WorkoutRecommendationReason.VolumeTrendingUp)
            if (volumeRatio < 0.9) add(WorkoutRecommendationReason.VolumeDropped)
            if (plateauDetected) add(WorkoutRecommendationReason.PlateauDetected)
            if (latestNearBest) add(WorkoutRecommendationReason.NearPersonalBest)
            if (trainingProfile.goal == TrainingGoal.AestheticFatLoss) {
                add(WorkoutRecommendationReason.AestheticGoal)
            }
            if (trainingProfile.calorieMode == CalorieMode.Deficit) {
                add(WorkoutRecommendationReason.CalorieDeficit)
            }
            if (trainingProfile.workoutsPerWeek == 4 && trainingProfile.split.name == "UpperLower") {
                add(WorkoutRecommendationReason.FourDayUpperLower)
            }
            if (kind == WorkoutRecommendationKind.ProgressiveOverload) {
                add(WorkoutRecommendationReason.ConservativeIncrease)
            }
        }.distinct().ifEmpty {
            listOf(WorkoutRecommendationReason.ConservativeIncrease)
        }

        return WorkoutRecommendation(
            exerciseId = exerciseId,
            sets = sets,
            kind = kind,
            confidence = confidenceFor(sessions.size, latest.sets.size, daysSinceLastSession, trainingProfile),
            estimatedVolume = sets.sumOf { (it.weight ?: 0.0) * it.reps },
            daysSinceLastSession = daysSinceLastSession,
            reasons = reasons.take(3)
        )
    }

    fun buildWorkoutPlan(
        exercises: List<ExerciseEntity>,
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile = TrainingProfile(),
        nowMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): SmartWorkoutPlan {
        if (exercises.isEmpty()) {
            return SmartWorkoutPlan(focus = SmartWorkoutFocus.FullBody, exercises = emptyList())
        }

        val focus = chooseWorkoutFocus(history, trainingProfile)
        val targetExerciseCount = when (focus) {
            SmartWorkoutFocus.Upper -> 5
            SmartWorkoutFocus.Lower -> 5
            SmartWorkoutFocus.Push -> 5
            SmartWorkoutFocus.Pull -> 5
            SmartWorkoutFocus.Legs -> 5
            SmartWorkoutFocus.FullBody -> 6
        }

        val historyByExerciseId = history.groupBy { it.exerciseId }
        val candidates = exercises
            .map { exercise ->
                val exerciseHistory = historyByExerciseId[exercise.id].orEmpty()
                val bodyGroup = classifyExercise(exercise.name)
                val daysSince = exerciseHistory
                    .maxOfOrNull { it.sessionDate }
                    ?.let { daysBetween(it, nowMillis, zoneId) }
                    ?: 90
                val sessionCount = exerciseHistory.map { it.sessionId }.distinct().size
                val focusScore = when {
                    focus == SmartWorkoutFocus.FullBody -> 24
                    isCandidateForFocus(bodyGroup, focus) && bodyGroup != SmartWorkoutFocus.FullBody -> 80
                    bodyGroup == SmartWorkoutFocus.FullBody -> 34
                    else -> -35
                }
                val noveltyScore = if (sessionCount == 0) 18 else 0
                val dueScore = daysSince.coerceAtMost(45) * 1.6
                val confidenceScore = sessionCount.coerceAtMost(6) * 3.0

                ExerciseCandidate(
                    exercise = exercise,
                    bodyGroup = bodyGroup,
                    score = focusScore + noveltyScore + dueScore + confidenceScore
                )
            }
            .sortedWith(
                compareByDescending<ExerciseCandidate> { it.score }
                    .thenBy { it.exercise.name.lowercase() }
            )

        val primary = candidates
            .filter { candidate ->
                isCandidateForFocus(candidate.bodyGroup, focus)
            }
            .take(targetExerciseCount)
        val fallback = if (primary.size >= targetExerciseCount) {
            emptyList()
        } else {
            candidates
                .filterNot { candidate -> primary.any { it.exercise.id == candidate.exercise.id } }
                .take(targetExerciseCount - primary.size)
        }

        val selected = (primary + fallback).take(targetExerciseCount)
        return SmartWorkoutPlan(
            focus = focus,
            exercises = selected.map { candidate ->
                SmartWorkoutExercise(
                    exercise = candidate.exercise,
                    recommendation = buildForExercise(
                        exerciseId = candidate.exercise.id,
                        history = history,
                        trainingProfile = trainingProfile,
                        nowMillis = nowMillis,
                        zoneId = zoneId
                    )
                )
            }
        )
    }

    private fun chooseWeightStep(weight: Double, trainingProfile: TrainingProfile): Double {
        val baseStep = when {
            weight < 20.0 -> 1.0
            weight < 60.0 -> 2.5
            weight < 120.0 -> 5.0
            else -> 7.5
        }
        return if (
            trainingProfile.goal == TrainingGoal.AestheticFatLoss ||
            trainingProfile.calorieMode == CalorieMode.Deficit
        ) {
            baseStep * 0.5
        } else {
            baseStep
        }
    }

    private fun goalMaxReps(trainingProfile: TrainingProfile): Int {
        return when (trainingProfile.goal) {
            TrainingGoal.Strength -> 8
            TrainingGoal.AestheticFatLoss -> 14
            TrainingGoal.MuscleGain -> 12
            TrainingGoal.Balanced -> 12
        }
    }

    private fun comebackMultiplier(daysSinceLastSession: Int): Double {
        return when {
            daysSinceLastSession >= 45 -> 0.82
            daysSinceLastSession >= 30 -> 0.86
            else -> 0.9
        }
    }

    private fun confidenceFor(
        sessionCount: Int,
        lastSetCount: Int,
        daysSinceLastSession: Int,
        trainingProfile: TrainingProfile
    ): Float {
        val historyScore = min(sessionCount, 6) * 0.09f
        val setScore = min(lastSetCount, 4) * 0.05f
        val profileScore = if (trainingProfile.workoutsPerWeek > 0) 0.06f else 0f
        val recencyPenalty = when {
            daysSinceLastSession >= 30 -> 0.18f
            daysSinceLastSession >= 14 -> 0.08f
            else -> 0f
        }
        return (0.35f + historyScore + setScore + profileScore - recencyPenalty).coerceIn(0.25f, 0.94f)
    }

    private fun daysBetween(fromMillis: Long, toMillis: Long, zoneId: ZoneId): Int {
        val from = Instant.ofEpochMilli(fromMillis).atZone(zoneId).toLocalDate()
        val to = Instant.ofEpochMilli(toMillis).atZone(zoneId).toLocalDate()
        return max(0, (to.toEpochDay() - from.toEpochDay()).toInt())
    }

    private fun chooseWorkoutFocus(
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile
    ): SmartWorkoutFocus {
        if (history.isEmpty()) {
            return when (trainingProfile.split) {
                TrainingSplit.UpperLower -> SmartWorkoutFocus.Upper
                TrainingSplit.FullBody -> SmartWorkoutFocus.FullBody
                TrainingSplit.PushPullLegs -> SmartWorkoutFocus.Push
                TrainingSplit.Custom -> SmartWorkoutFocus.FullBody
            }
        }

        val latestSessionId = history.maxByOrNull { it.sessionDate }?.sessionId ?: return SmartWorkoutFocus.Upper
        val latestSession = history.filter { it.sessionId == latestSessionId }

        return when (trainingProfile.split) {
            TrainingSplit.UpperLower -> {
                val lowerCount = latestSession.count { classifyExercise(it.exerciseName) in lowerFocuses }
                val upperCount = latestSession.count { classifyExercise(it.exerciseName) in upperFocuses }
                if (lowerCount > upperCount) SmartWorkoutFocus.Upper else SmartWorkoutFocus.Lower
            }
            TrainingSplit.PushPullLegs -> {
                val pushCount = latestSession.count { classifyExercise(it.exerciseName) == SmartWorkoutFocus.Push }
                val pullCount = latestSession.count { classifyExercise(it.exerciseName) == SmartWorkoutFocus.Pull }
                val legsCount = latestSession.count { classifyExercise(it.exerciseName) in lowerFocuses }
                when {
                    legsCount >= pushCount && legsCount >= pullCount -> SmartWorkoutFocus.Push
                    pushCount >= pullCount -> SmartWorkoutFocus.Pull
                    else -> SmartWorkoutFocus.Legs
                }
            }
            TrainingSplit.FullBody -> SmartWorkoutFocus.FullBody
            TrainingSplit.Custom -> chooseMostNeglectedFocus(history)
        }
    }

    private fun classifyExercise(name: String): SmartWorkoutFocus {
        val normalized = name.lowercase()
            .replace('ʼ', '\'')
            .replace('’', '\'')
            .replace(Regex("\\s+"), " ")
            .trim()

        val legsTokens = listOf(
            "нога", "ноги", "прис", "squat", "leg", "квад", "стег", "ікр", "икр",
            "calf", "румун", "станов", "deadlift", "згибання ніг", "розгинання ніг",
            "жим ногами", "сідниц", "ягод", "glute"
        )
        val pushTokens = listOf(
            "жим", "груд", "chest", "плеч", "shoulder", "tricep", "трицеп",
            "метелик", "брусь", "dips", "press"
        )
        val pullTokens = listOf(
            "спин", "тяга", "row", "pull", "підтяг", "подтяг", "біцеп", "бицеп",
            "curl", "штанга на біцепс", "гантелі сидячи"
        )
        val coreTokens = listOf("прес", "abs", "crunch", "нахил", "oblique", "гіперекстензі", "hyperextension")

        return when {
            legsTokens.any { normalized.contains(it) } -> SmartWorkoutFocus.Legs
            pullTokens.any { normalized.contains(it) } -> SmartWorkoutFocus.Pull
            pushTokens.any { normalized.contains(it) } -> SmartWorkoutFocus.Push
            coreTokens.any { normalized.contains(it) } -> SmartWorkoutFocus.FullBody
            else -> SmartWorkoutFocus.FullBody
        }
    }

    private fun isCandidateForFocus(candidateFocus: SmartWorkoutFocus, workoutFocus: SmartWorkoutFocus): Boolean {
        return when (workoutFocus) {
            SmartWorkoutFocus.Upper -> candidateFocus in upperFocuses || candidateFocus == SmartWorkoutFocus.FullBody
            SmartWorkoutFocus.Lower -> candidateFocus in lowerFocuses || candidateFocus == SmartWorkoutFocus.FullBody
            SmartWorkoutFocus.Push -> candidateFocus == SmartWorkoutFocus.Push || candidateFocus == SmartWorkoutFocus.FullBody
            SmartWorkoutFocus.Pull -> candidateFocus == SmartWorkoutFocus.Pull || candidateFocus == SmartWorkoutFocus.FullBody
            SmartWorkoutFocus.Legs -> candidateFocus in lowerFocuses || candidateFocus == SmartWorkoutFocus.FullBody
            SmartWorkoutFocus.FullBody -> true
        }
    }

    private fun chooseMostNeglectedFocus(history: List<ExerciseHistoryEntry>): SmartWorkoutFocus {
        val lastByFocus = history
            .groupBy { classifyExercise(it.exerciseName) }
            .mapValues { (_, entries) -> entries.maxOfOrNull { it.sessionDate } ?: 0L }
        val focusOrder = listOf(
            SmartWorkoutFocus.Push,
            SmartWorkoutFocus.Pull,
            SmartWorkoutFocus.Legs,
            SmartWorkoutFocus.FullBody
        )
        return focusOrder.minByOrNull { focus -> lastByFocus[focus] ?: 0L } ?: SmartWorkoutFocus.FullBody
    }

    private fun roundToNearestHalf(value: Double): Double {
        return round(value * 2.0) / 2.0
    }

    private fun Double.roundToInt(): Int = round(this).toInt()

    private data class ExerciseSessionSnapshot(
        val sets: List<ExerciseHistoryEntry>
    ) {
        val date: Long = sets.first().sessionDate
        val maxWeight: Double = sets.maxOf { it.weight }
        val minReps: Int = sets.minOf { it.reps }
        val averageReps: Double = sets.map { it.reps }.average()
        val volume: Double = sets.sumOf { it.weight * it.reps }
        val estimatedMax: Double = sets.maxOf { it.weight * (1.0 + it.reps / 30.0) }
    }

    private data class ExerciseCandidate(
        val exercise: ExerciseEntity,
        val bodyGroup: SmartWorkoutFocus,
        val score: Double
    )

    private val upperFocuses = setOf(SmartWorkoutFocus.Upper, SmartWorkoutFocus.Push, SmartWorkoutFocus.Pull)
    private val lowerFocuses = setOf(SmartWorkoutFocus.Lower, SmartWorkoutFocus.Legs)
}
