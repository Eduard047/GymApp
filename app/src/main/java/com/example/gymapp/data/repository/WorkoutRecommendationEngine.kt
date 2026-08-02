package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.Instant
import java.time.ZoneId
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

enum class SmartWorkoutVariant {
    A,
    B,
    C
}

data class SmartWorkoutExercise(
    val exercise: ExerciseEntity,
    val recommendation: WorkoutRecommendation
)

data class SmartWorkoutPlan(
    val focus: SmartWorkoutFocus,
    val exercises: List<SmartWorkoutExercise>,
    val variant: SmartWorkoutVariant = SmartWorkoutVariant.A
)

object WorkoutRecommendationEngine {
    private const val MaxHistorySessions = 24
    private const val ComebackBreakDays = 10

    fun buildForExercise(
        exerciseId: Long,
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile = TrainingProfile(),
        nowMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        exerciseName: String? = null
    ): WorkoutRecommendation {
        val programmingAnalysis = exerciseName
            ?.takeIf { it.isNotBlank() }
            ?.let(::analyzeExercise)
            ?: history.firstOrNull { entry ->
                entry.exerciseId == exerciseId && WorkoutDataLimits.isValidExerciseName(entry.exerciseName)
            }?.let { analyzeExercise(it.exerciseName) }
        val targetIdentityKey = programmingAnalysis?.identityKey
        val sessions = history
            .asSequence()
            .take(WorkoutDataLimits.MAX_TOTAL_SETS)
            .filter { entry ->
                entry.isUsableForRecommendation(nowMillis) && (
                    entry.exerciseId == exerciseId ||
                        targetIdentityKey != null && analyzeExercise(entry.exerciseName).identityKey == targetIdentityKey
                    )
            }
            .groupBy { it.sessionId }
            .map { (sessionId, entries) ->
                ExerciseSessionSnapshot(
                    sessionId = sessionId,
                    sets = entries
                        .sortedWith(
                            compareBy<ExerciseHistoryEntry> { it.setOrderIndex }
                                .thenBy { it.setId }
                        )
                        .take(WorkoutDataLimits.MAX_SETS_PER_EXERCISE)
                )
            }
            .sortedWith(
                compareByDescending<ExerciseSessionSnapshot> { it.date }
                    .thenByDescending { it.sessionId }
            )
            .take(MaxHistorySessions)

        if (sessions.isEmpty()) {
            val repRange = goalRepRange(trainingProfile, programmingAnalysis)
            val targetSetCount = setBudget(trainingProfile, programmingAnalysis)
            return WorkoutRecommendation(
                exerciseId = exerciseId,
                sets = List(targetSetCount) {
                    RecommendedWorkoutSet(
                        weight = null,
                        reps = defaultTargetReps(trainingProfile, programmingAnalysis, repRange)
                    )
                },
                kind = WorkoutRecommendationKind.NewExercise,
                confidence = 0.35f,
                estimatedVolume = 0.0,
                daysSinceLastSession = null,
                reasons = listOf(WorkoutRecommendationReason.NoHistory)
            )
        }

        val latest = sessions.first()
        val previous = sessions.getOrNull(1)
        val daysSinceLastSession = daysBetween(latest.date, nowMillis, zoneId)
        val repRange = goalRepRange(trainingProfile, programmingAnalysis)
        val bestEstimatedMax = sessions.maxOf { it.estimatedMax }
        val plateauDetected = isTruePlateau(sessions.take(4))
        val repeatedRegression = sessions.size >= 3 &&
            isComparableRegression(newer = sessions[0], older = sessions[1]) &&
            isComparableRegression(newer = sessions[1], older = sessions[2])
        val latestNearBest = latest.estimatedMax >= bestEstimatedMax * 0.97
        val previousVolumePerSet = previous?.averageVolumePerSet ?: latest.averageVolumePerSet
        val volumeRatio = if (previousVolumePerSet <= 0.0) {
            1.0
        } else {
            latest.averageVolumePerSet / previousVolumePerSet
        }
        val latestStable = latest.sets.all { it.reps >= repRange.minimum }
        val latestStrained = latest.sets.any { it.reps < repRange.minimum } || volumeRatio < 0.9
        val earnedProgression = latest.sets.all { it.reps >= repRange.maximum } &&
            previous?.sets?.all { it.reps >= repRange.maximum } == true
        val isFatLossDeficit = trainingProfile.goal == TrainingGoal.AestheticFatLoss &&
            trainingProfile.calorieMode == CalorieMode.Deficit

        val kind = when {
            daysSinceLastSession >= ComebackBreakDays -> WorkoutRecommendationKind.Comeback
            repeatedRegression -> WorkoutRecommendationKind.Deload
            earnedProgression -> WorkoutRecommendationKind.ProgressiveOverload
            plateauDetected -> WorkoutRecommendationKind.PlateauBreak
            else -> WorkoutRecommendationKind.HoldAndBuild
        }

        val targetSetCount = setBudget(trainingProfile, programmingAnalysis)
        val baselineSets = baselineSets(latest.sets, targetSetCount)
        val plateauUsesLowerRange = latest.averageReps >= (repRange.minimum + repRange.maximum) / 2.0
        val sets = baselineSets.mapIndexed { index, baseline ->
            val weight = when (kind) {
                WorkoutRecommendationKind.NewExercise -> null
                WorkoutRecommendationKind.ProgressiveOverload -> {
                    if (baseline.weight <= 0.0) {
                        baseline.weight
                    } else {
                        boundedRoundedWeight(
                            baseline.weight + chooseWeightStep(
                                weight = baseline.weight,
                                trainingProfile = trainingProfile
                            )
                        )
                    }
                }
                WorkoutRecommendationKind.HoldAndBuild,
                WorkoutRecommendationKind.PlateauBreak -> baseline.weight
                WorkoutRecommendationKind.Deload -> boundedRoundedWeight(
                    baseline.weight * if (isFatLossDeficit) 0.9 else 0.92
                )
                WorkoutRecommendationKind.Comeback -> boundedRoundedWeight(
                    baseline.weight * comebackMultiplier(daysSinceLastSession)
                )
            }
            val reps = when (kind) {
                WorkoutRecommendationKind.NewExercise ->
                    defaultTargetReps(trainingProfile, programmingAnalysis, repRange)
                WorkoutRecommendationKind.ProgressiveOverload -> {
                    if (baseline.weight <= 0.0) repRange.maximum else repRange.minimum
                }
                WorkoutRecommendationKind.HoldAndBuild ->
                    (baseline.reps + 1).coerceIn(repRange.minimum, repRange.maximum)
                WorkoutRecommendationKind.Deload,
                WorkoutRecommendationKind.Comeback ->
                    baseline.reps.coerceIn(repRange.minimum, repRange.maximum)
                WorkoutRecommendationKind.PlateauBreak -> {
                    if (plateauUsesLowerRange) {
                        (repRange.minimum + index % 2).coerceAtMost(repRange.maximum)
                    } else {
                        (repRange.maximum - index % 2).coerceAtLeast(repRange.minimum)
                    }
                }
            }
            RecommendedWorkoutSet(weight = weight, reps = reps)
        }

        val reasons = buildList {
            if (latestStable) add(WorkoutRecommendationReason.LastSessionStrong)
            if (latestStrained || repeatedRegression) add(WorkoutRecommendationReason.LastSessionUnstable)
            if (daysSinceLastSession >= ComebackBreakDays) add(WorkoutRecommendationReason.RecentBreak)
            if (volumeRatio >= 1.08) add(WorkoutRecommendationReason.VolumeTrendingUp)
            if (volumeRatio < 0.9 || repeatedRegression) add(WorkoutRecommendationReason.VolumeDropped)
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
        val safeExercises = exercises
            .asSequence()
            .take(WorkoutDataLimits.MAX_EXERCISES)
            .filter { exercise ->
                exercise.id > 0L &&
                    WorkoutDataLimits.isValidExerciseName(exercise.name) &&
                    BuiltInExerciseCatalog.inferKey(exercise.name) != "warm_up"
            }
            .toList()
            .distinctBy { it.id }
        if (safeExercises.isEmpty()) {
            return SmartWorkoutPlan(focus = SmartWorkoutFocus.FullBody, exercises = emptyList())
        }

        val safeHistory = history
            .asSequence()
            .take(WorkoutDataLimits.MAX_TOTAL_SETS)
            .filter { it.isUsableForRecommendation(nowMillis) }
            .toList()
        val focus = chooseWorkoutFocus(safeHistory, trainingProfile, nowMillis, zoneId)
        val variant = chooseWorkoutVariant(focus, safeHistory)
        val targetExerciseCount = targetExerciseCount(focus, trainingProfile)

        val analysesByExerciseId = safeExercises.associate { exercise ->
            exercise.id to analyzeExercise(exercise.name)
        }
        val historyByIdentity = safeHistory.groupBy { entry ->
            analysesByExerciseId[entry.exerciseId]?.identityKey
                ?: analyzeExercise(entry.exerciseName).identityKey
        }
        val recentSessionIds = recentSessionIds(safeHistory, limit = 3)
        val targetMuscles = targetMusclesForFocus(focus)
        val candidates = safeExercises.map { exercise ->
            val analysis = analysesByExerciseId.getValue(exercise.id)
            val exerciseHistory = historyByIdentity[analysis.identityKey].orEmpty()
            val daysSince = exerciseHistory
                .maxOfOrNull { it.sessionDate }
                ?.let { daysBetween(it, nowMillis, zoneId) }
                ?: 90
            val sessionCount = exerciseHistory.map { it.sessionId }.distinct().size
            val recentExercisePenalty = exerciseHistory
                .filter { it.sessionId in recentSessionIds }
                .map { it.sessionId }
                .distinct()
                .size * 16.0
            val sameWeekExercisePenalty = if (
                exerciseHistory.any { daysBetween(it.sessionDate, nowMillis, zoneId) <= 6 }
            ) {
                55.0
            } else {
                0.0
            }
            val focusScore = when {
                focus == SmartWorkoutFocus.FullBody -> 44.0
                isExerciseEligibleForFocus(analysis, focus) -> 86.0
                analysis.category == SmartWorkoutFocus.FullBody -> 32.0
                else -> -60.0
            }
            val muscleMatchScore = analysis.muscles.count { it in targetMuscles } * 9.0
            val noveltyScore = if (sessionCount == 0) 12.0 else 0.0
            val dueScore = daysSince.coerceAtMost(28) * 1.25
            val confidenceScore = sessionCount.coerceAtMost(4) * 2.0
            val variantScore = variantPreferenceScore(analysis, focus, variant)
            val programmingScore = programmingPreferenceScore(
                analysis = analysis,
                trainingProfile = trainingProfile,
                sessionCount = sessionCount
            )

            ExerciseCandidate(
                exercise = exercise,
                analysis = analysis,
                score = focusScore + muscleMatchScore + noveltyScore + dueScore + confidenceScore +
                    variantScore + programmingScore -
                    recentExercisePenalty - sameWeekExercisePenalty
            )
        }
            .groupBy { it.analysis.identityKey }
            .values
            .map { equivalentCandidates ->
                equivalentCandidates.sortedWith(
                    compareByDescending<ExerciseCandidate> { it.score }
                        .thenBy { it.exercise.name.lowercase() }
                        .thenBy { it.exercise.id }
                ).first()
            }

        val selected = selectBalancedExercises(
            candidates = candidates,
            focus = focus,
            variant = variant,
            targetMuscles = targetMuscles,
            targetExerciseCount = targetExerciseCount,
            history = safeHistory,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        return SmartWorkoutPlan(
            focus = focus,
            exercises = selected.map { candidate ->
                SmartWorkoutExercise(
                    exercise = candidate.exercise,
                    recommendation = buildForExercise(
                        exerciseId = candidate.exercise.id,
                        history = historyByIdentity[candidate.analysis.identityKey].orEmpty(),
                        trainingProfile = trainingProfile,
                        nowMillis = nowMillis,
                        zoneId = zoneId,
                        exerciseName = candidate.exercise.name
                    )
                )
            },
            variant = variant
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

    private fun goalRepRange(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ): RepRange {
        val isCompound = analysis?.isCompound == true
        return when (trainingProfile.goal) {
            TrainingGoal.Strength -> if (isCompound) {
                RepRange(minimum = 3, maximum = 6)
            } else {
                RepRange(minimum = 6, maximum = 10)
            }
            TrainingGoal.MuscleGain,
            TrainingGoal.AestheticFatLoss -> if (isCompound) {
                RepRange(minimum = 6, maximum = 10)
            } else {
                RepRange(minimum = 8, maximum = 10)
            }
            TrainingGoal.Balanced -> if (isCompound) {
                RepRange(minimum = 5, maximum = 8)
            } else {
                RepRange(minimum = 8, maximum = 10)
            }
        }
    }

    private fun defaultTargetReps(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        repRange: RepRange
    ): Int {
        val target = when (trainingProfile.goal) {
            TrainingGoal.Strength -> if (analysis?.isCompound == true) 5 else 8
            TrainingGoal.MuscleGain,
            TrainingGoal.AestheticFatLoss -> if (analysis?.isCompound == true) 8 else 10
            TrainingGoal.Balanced -> if (analysis?.isCompound == true) 8 else 10
        }
        return target.coerceIn(repRange.minimum, repRange.maximum)
    }

    private fun setBudget(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ): Int {
        val highFrequency = trainingProfile.workoutsPerWeek.coerceIn(2, 6) >= 5
        val recoveryLimited = trainingProfile.calorieMode == CalorieMode.Deficit
        return if (analysis?.isCompound == true && !highFrequency && !recoveryLimited) 4 else 3
    }

    private fun targetExerciseCount(
        focus: SmartWorkoutFocus,
        trainingProfile: TrainingProfile
    ): Int {
        val days = trainingProfile.workoutsPerWeek.coerceIn(2, 6)
        var target = when {
            focus == SmartWorkoutFocus.FullBody && days == 2 -> 6
            focus == SmartWorkoutFocus.FullBody && days == 3 -> 5
            focus == SmartWorkoutFocus.FullBody -> 4
            days <= 3 -> 6
            else -> 5
        }
        if (trainingProfile.goal == TrainingGoal.Strength) target -= 1
        if (
            trainingProfile.goal == TrainingGoal.MuscleGain &&
            trainingProfile.calorieMode == CalorieMode.Surplus
        ) {
            target += 1
        }
        return target.coerceIn(4, 6)
    }

    private fun programmingPreferenceScore(
        analysis: ExerciseAnalysis,
        trainingProfile: TrainingProfile,
        sessionCount: Int
    ): Double {
        var score = when (trainingProfile.goal) {
            TrainingGoal.Strength -> if (analysis.isCompound) 24.0 else -8.0
            TrainingGoal.MuscleGain -> if (analysis.isCompound) 14.0 else 6.0
            TrainingGoal.AestheticFatLoss -> if (analysis.isCompound) 8.0 else 2.0
            TrainingGoal.Balanced -> if (analysis.isCompound) 10.0 else 4.0
        }
        if (trainingProfile.calorieMode == CalorieMode.Deficit) {
            score += if (sessionCount > 0) 10.0 else -6.0
        } else if (trainingProfile.calorieMode == CalorieMode.Surplus && analysis.isCompound) {
            score += 4.0
        }
        return score
    }

    private fun baselineSets(
        latestSets: List<ExerciseHistoryEntry>,
        targetSetCount: Int
    ): List<ExerciseHistoryEntry> {
        return List(targetSetCount) { index ->
            latestSets.getOrElse(index) { latestSets.last() }
        }
    }

    private fun boundedRoundedWeight(value: Double): Double {
        return roundToNearestHalf(value.coerceIn(0.0, WorkoutDataLimits.MAX_WEIGHT))
    }

    private fun isComparableRegression(
        newer: ExerciseSessionSnapshot,
        older: ExerciseSessionSnapshot
    ): Boolean {
        if (older.maxWeight <= 0.0 && newer.maxWeight <= 0.0) {
            return newer.averageReps < older.averageReps * 0.9
        }
        if (older.estimatedMax <= 0.0 || older.averageVolumePerSet <= 0.0) return false
        return newer.estimatedMax < older.estimatedMax * 0.97 &&
            newer.averageVolumePerSet < older.averageVolumePerSet * 0.92
    }

    private fun isTruePlateau(recentSessions: List<ExerciseSessionSnapshot>): Boolean {
        if (recentSessions.size < 4) return false
        val latest = recentSessions.first()
        val oldest = recentSessions.last()
        val estimatedMaxImproved = when {
            oldest.estimatedMax <= 0.0 -> latest.estimatedMax > 0.0
            else -> latest.estimatedMax > oldest.estimatedMax * 1.015
        }
        val averageRepsImproved = latest.averageReps > oldest.averageReps + 0.25
        val volumePerSetImproved = when {
            oldest.averageVolumePerSet <= 0.0 -> latest.averageVolumePerSet > 0.0
            else -> latest.averageVolumePerSet > oldest.averageVolumePerSet * 1.02
        }
        val maxWeights = recentSessions.map { it.maxWeight }
        val stableLoad = (maxWeights.maxOrNull() ?: 0.0) - (maxWeights.minOrNull() ?: 0.0) <=
            max(1.25, oldest.maxWeight * 0.02)
        return stableLoad && !estimatedMaxImproved && !averageRepsImproved && !volumePerSetImproved
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
        trainingProfile: TrainingProfile,
        nowMillis: Long,
        zoneId: ZoneId
    ): SmartWorkoutFocus {
        if (history.isEmpty()) {
            return when (trainingProfile.split) {
                TrainingSplit.UpperLower -> SmartWorkoutFocus.Upper
                TrainingSplit.FullBody -> SmartWorkoutFocus.FullBody
                TrainingSplit.PushPullLegs -> SmartWorkoutFocus.Push
                TrainingSplit.Custom -> SmartWorkoutFocus.FullBody
            }
        }

        val sessions = history.sessionGroupsByDate()
        if (sessions.isEmpty()) return SmartWorkoutFocus.Upper

        return when (trainingProfile.split) {
            TrainingSplit.UpperLower -> {
                val latestRecognizedFocus = sessions
                    .asSequence()
                    .map { dominantFocus(it.entries) }
                    .firstOrNull { it.isUpperDay() || it.isLowerDay() }
                if (latestRecognizedFocus != null) {
                    return if (latestRecognizedFocus.isLowerDay()) {
                        SmartWorkoutFocus.Upper
                    } else {
                        SmartWorkoutFocus.Lower
                    }
                }
                val thisWeekSessions = sessions.filter { session ->
                    daysBetween(session.date, nowMillis, zoneId) <= 6
                }
                val upperCount = thisWeekSessions.count { dominantFocus(it.entries).isUpperDay() }
                val lowerCount = thisWeekSessions.count { dominantFocus(it.entries).isLowerDay() }
                if (lowerCount < upperCount) SmartWorkoutFocus.Lower else SmartWorkoutFocus.Upper
            }
            TrainingSplit.PushPullLegs -> {
                val latestRecognizedFocus = sessions
                    .asSequence()
                    .map { dominantFocus(it.entries) }
                    .firstOrNull {
                        it == SmartWorkoutFocus.Push ||
                            it == SmartWorkoutFocus.Pull ||
                            it.isLowerDay()
                    }
                when (latestRecognizedFocus) {
                    SmartWorkoutFocus.Push -> SmartWorkoutFocus.Pull
                    SmartWorkoutFocus.Pull -> SmartWorkoutFocus.Legs
                    SmartWorkoutFocus.Legs,
                    SmartWorkoutFocus.Lower -> SmartWorkoutFocus.Push
                    SmartWorkoutFocus.Upper,
                    SmartWorkoutFocus.FullBody,
                    null -> chooseMostNeglectedFocus(history)
                }
            }
            TrainingSplit.FullBody -> SmartWorkoutFocus.FullBody
            TrainingSplit.Custom -> chooseMostNeglectedFocus(history)
        }
    }

    private fun chooseWorkoutVariant(
        focus: SmartWorkoutFocus,
        history: List<ExerciseHistoryEntry>
    ): SmartWorkoutVariant {
        val completedSlotCount = history.sessionGroupsByDate().count { session ->
            if (focus == SmartWorkoutFocus.FullBody) {
                true
            } else {
                val completedFocus = dominantFocus(session.entries)
                when (focus) {
                    SmartWorkoutFocus.Upper -> completedFocus.isUpperDay()
                    SmartWorkoutFocus.Lower,
                    SmartWorkoutFocus.Legs -> completedFocus.isLowerDay()
                    SmartWorkoutFocus.Push -> completedFocus == SmartWorkoutFocus.Push
                    SmartWorkoutFocus.Pull -> completedFocus == SmartWorkoutFocus.Pull
                    SmartWorkoutFocus.FullBody -> true
                }
            }
        }
        val slotCount = if (focus == SmartWorkoutFocus.FullBody) 3 else 2
        return when (completedSlotCount % slotCount) {
            1 -> SmartWorkoutVariant.B
            2 -> SmartWorkoutVariant.C
            else -> SmartWorkoutVariant.A
        }
    }

    private fun variantPreferenceScore(
        analysis: ExerciseAnalysis,
        focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant
    ): Double {
        val slotCount = if (focus == SmartWorkoutFocus.FullBody) 3 else 2
        val variantIndex = variant.index.coerceAtMost(slotCount - 1)
        val bucketScore = if (stableBucket(analysis.identityKey, slotCount) == variantIndex) 10.0 else 0.0
        val preferredPatterns = preferredPatternsForVariant(focus, variant)
        val patternScore = if (analysis.patterns.any { it in preferredPatterns }) 18.0 else 0.0
        return bucketScore + patternScore
    }

    private fun preferredPatternsForVariant(
        focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant
    ): Set<MovementPattern> {
        return when (focus) {
            SmartWorkoutFocus.Upper -> when (variant) {
                SmartWorkoutVariant.A -> setOf(MovementPattern.HorizontalPress, MovementPattern.HorizontalPull)
                SmartWorkoutVariant.B,
                SmartWorkoutVariant.C -> setOf(MovementPattern.VerticalPress, MovementPattern.VerticalPull)
            }
            SmartWorkoutFocus.Push -> when (variant) {
                SmartWorkoutVariant.A -> setOf(MovementPattern.HorizontalPress)
                SmartWorkoutVariant.B,
                SmartWorkoutVariant.C -> setOf(MovementPattern.VerticalPress)
            }
            SmartWorkoutFocus.Pull -> when (variant) {
                SmartWorkoutVariant.A -> setOf(MovementPattern.HorizontalPull)
                SmartWorkoutVariant.B,
                SmartWorkoutVariant.C -> setOf(MovementPattern.VerticalPull)
            }
            SmartWorkoutFocus.Lower,
            SmartWorkoutFocus.Legs -> when (variant) {
                SmartWorkoutVariant.A -> setOf(MovementPattern.Squat, MovementPattern.LegPress)
                SmartWorkoutVariant.B,
                SmartWorkoutVariant.C -> setOf(MovementPattern.Hinge, MovementPattern.KneeFlexion)
            }
            SmartWorkoutFocus.FullBody -> when (variant) {
                SmartWorkoutVariant.A -> setOf(
                    MovementPattern.HorizontalPress,
                    MovementPattern.HorizontalPull,
                    MovementPattern.Squat
                )
                SmartWorkoutVariant.B -> setOf(
                    MovementPattern.VerticalPress,
                    MovementPattern.VerticalPull,
                    MovementPattern.Hinge
                )
                SmartWorkoutVariant.C -> setOf(
                    MovementPattern.LegPress,
                    MovementPattern.KneeExtension,
                    MovementPattern.Calf,
                    MovementPattern.Core
                )
            }
        }
    }

    private fun stableBucket(value: String, bucketCount: Int): Int {
        val hash = value.fold(0) { result, character -> result * 31 + character.code }
        return Math.floorMod(hash, bucketCount)
    }

    private fun analyzeExercise(name: String): ExerciseAnalysis {
        val definition = BuiltInExerciseCatalog.definitionForName(name)
        val normalized = (definition?.nameEn ?: name).normalizedExerciseName()
        val identityKey = definition?.let { "catalog:${it.key}" } ?: "custom:$normalized"
        val muscles = linkedSetOf<String>()
        val patterns = linkedSetOf<MovementPattern>()
        definition?.muscleIds?.let(muscles::addAll)

        fun add(vararg ids: String) {
            muscles += ids
        }
        fun pattern(vararg values: MovementPattern) {
            patterns += values
        }

        if (normalized.containsAny("жим ног", "leg press")) {
            add("quads", "glutes", "hamstrings")
            pattern(MovementPattern.LegPress)
        }
        if (normalized.containsAny("прис", "присед", "squat", "випад", "выпад", "lunge")) {
            add("quads", "glutes", "hamstrings")
            pattern(MovementPattern.Squat)
        }
        if (normalized.containsAny("румун", "румын", "станов", "становая", "deadlift")) {
            add("hamstrings", "glutes", "lowerBack", "upperBack")
            pattern(MovementPattern.Hinge)
        }
        if (normalized.containsAny("згинання ніг", "згибання ніг", "сгибание ног", "leg curl")) {
            add("hamstrings")
            pattern(MovementPattern.KneeFlexion)
        }
        if (normalized.containsAny("розгинання ніг", "разгибание ног", "leg extension")) {
            add("quads")
            pattern(MovementPattern.KneeExtension)
        }
        if (normalized.containsAny("сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик")) {
            add("glutes", "hamstrings")
            pattern(MovementPattern.Hinge)
        }
        if (normalized.containsAny("икр", "ікр", "calf", "носок", "носки")) {
            add("calves")
            pattern(MovementPattern.Calf)
        }
        if (normalized.containsAny("зведення ніг", "сведение ног", "adductor")) add("adductors")
        if (normalized.containsAny("розведення ніг", "разведение ног", "hip abduction", "abductor")) add("glutes")

        if (normalized.containsAny("жим", "press", "bench", "віджим", "отжим", "push up", "dips", "брусь") &&
            !normalized.containsAny("ног", "leg press")
        ) {
            add("chest", "triceps", "shoulders")
            if (normalized.containsAny("сидя", "сидячи", "над голов", "overhead", "shoulder")) {
                pattern(MovementPattern.VerticalPress)
            } else {
                pattern(MovementPattern.HorizontalPress)
            }
        }
        if (normalized.containsAny("груд", "груди", "chest", "метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies")) add("chest", "shoulders")
        if (normalized.containsAny("плеч", "дельт", "махи", "розведення", "разведение", "lateral raise", "rear delt", "shoulder", "overhead", "над голов")) {
            add("shoulders")
            pattern(MovementPattern.VerticalPress)
        }
        if (normalized.containsAny("трицепс", "tricep", "француз", "розгинання рук", "разгибание рук", "pushdown", "гантеля над голов", "гантель над голов")) add("triceps")

        if (normalized.containsAny("підтяг", "подтяг", "pull up", "pullup", "pulldown", "верхній блок", "верхний блок", "журавель")) {
            add("lats", "upperBack", "biceps")
            pattern(MovementPattern.VerticalPull)
        }
        if (normalized.containsAny("face pull", "тяга каната до обличчя", "тяга каната к лицу")) {
            add("shoulders", "upperBack")
            pattern(MovementPattern.HorizontalPull)
        }
        if (normalized.containsAny("тяга", "row") && !normalized.containsAny("румун", "румын", "станов", "становая", "deadlift", "підборід", "подбород")) {
            add("lats", "upperBack", "biceps")
            pattern(MovementPattern.HorizontalPull)
        }
        if (normalized.containsAny("спин", "спина", "back")) add("lats", "upperBack")
        if (normalized.containsAny("біцепс", "бицепс", "bicep", "curl", "згинання рук", "сгибание рук")) add("biceps", "forearms")
        if (normalized.containsAny("передпліч", "предплеч", "forearm")) add("forearms")

        if (normalized.containsAny("прес", "abs", "crunch", "скруч", "планка", "plank", "leg raise")) {
            add("abs")
            pattern(MovementPattern.Core)
        }
        if (normalized.containsAny("нахил", "наклон", "сторони", "стороны", "oblique", "rotation", "twist")) add("obliques")
        if (normalized.containsAny("гіперекстензі", "гиперэкстенз", "hyperextension")) {
            add("lowerBack", "glutes", "hamstrings")
            pattern(MovementPattern.Hinge)
        }

        val classificationMuscles = definition?.muscleIds ?: muscles
        val lowerCount = classificationMuscles.count { it in lowerMuscles }
        val pushCount = classificationMuscles.count { it in pushMuscles }
        val pullCount = classificationMuscles.count { it in pullMuscles }
        val category = when {
            definition?.key == "warm_up" -> SmartWorkoutFocus.FullBody
            patterns.any { it in lowerMovementPatterns } || lowerCount > max(pushCount, pullCount) ->
                SmartWorkoutFocus.Legs
            patterns.any { it == MovementPattern.HorizontalPull || it == MovementPattern.VerticalPull } &&
                patterns.none { it == MovementPattern.HorizontalPress || it == MovementPattern.VerticalPress } ->
                SmartWorkoutFocus.Pull
            patterns.any { it == MovementPattern.HorizontalPress || it == MovementPattern.VerticalPress } ->
                SmartWorkoutFocus.Push
            pullCount > pushCount -> SmartWorkoutFocus.Pull
            pushCount > pullCount -> SmartWorkoutFocus.Push
            classificationMuscles.any { it in coreMuscles } -> SmartWorkoutFocus.FullBody
            else -> SmartWorkoutFocus.FullBody
        }

        return ExerciseAnalysis(
            identityKey = identityKey,
            category = category,
            muscles = muscles,
            patterns = patterns.ifEmpty { linkedSetOf(MovementPattern.Accessory) }
        )
    }

    private fun isExerciseEligibleForFocus(analysis: ExerciseAnalysis, workoutFocus: SmartWorkoutFocus): Boolean {
        return when (workoutFocus) {
            SmartWorkoutFocus.Upper -> analysis.category in upperFocuses
            SmartWorkoutFocus.Lower,
            SmartWorkoutFocus.Legs -> analysis.category in lowerFocuses || analysis.muscles.any { it in coreMuscles }
            SmartWorkoutFocus.Push -> analysis.category == SmartWorkoutFocus.Push
            SmartWorkoutFocus.Pull -> analysis.category == SmartWorkoutFocus.Pull
            SmartWorkoutFocus.FullBody -> true
        }
    }

    private fun selectBalancedExercises(
        candidates: List<ExerciseCandidate>,
        focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant,
        targetMuscles: Set<String>,
        targetExerciseCount: Int,
        history: List<ExerciseHistoryEntry>,
        nowMillis: Long,
        zoneId: ZoneId
    ): List<ExerciseCandidate> {
        val selected = mutableListOf<ExerciseCandidate>()
        val coveredMuscles = mutableSetOf<String>()
        val lastTrainedByMuscle = lastTrainedByMuscle(history)
        val remaining = candidates
            .filter { candidate -> isExerciseEligibleForFocus(candidate.analysis, focus) }
            .ifEmpty {
                if (focus == SmartWorkoutFocus.Lower || focus == SmartWorkoutFocus.Legs) {
                    emptyList()
                } else {
                    candidates
                }
            }
            .toMutableList()

        if (focus != SmartWorkoutFocus.FullBody) {
            selectRequiredPattern(
                remaining = remaining,
                selected = selected,
                coveredMuscles = coveredMuscles,
                patterns = preferredPatternsForVariant(focus, variant)
            )
        }

        if (focus == SmartWorkoutFocus.Lower || focus == SmartWorkoutFocus.Legs) {
            if (selected.none { candidate ->
                    candidate.analysis.patterns.any { it == MovementPattern.Squat || it == MovementPattern.LegPress }
                }
            ) {
                selectRequiredPattern(
                    remaining = remaining,
                    selected = selected,
                    coveredMuscles = coveredMuscles,
                    patterns = setOf(MovementPattern.Squat, MovementPattern.LegPress)
                )
            }
            if (shouldPrioritizeHeavyLower(history) &&
                selected.none { candidate -> MovementPattern.Hinge in candidate.analysis.patterns }
            ) {
                selectRequiredPattern(
                    remaining = remaining,
                    selected = selected,
                    coveredMuscles = coveredMuscles,
                    patterns = setOf(MovementPattern.Hinge)
                )
            }
        }

        if (focus == SmartWorkoutFocus.FullBody) {
            listOf(SmartWorkoutFocus.Push, SmartWorkoutFocus.Pull, SmartWorkoutFocus.Legs).forEach { requiredFocus ->
                val best = remaining
                    .filter { it.analysis.category == requiredFocus }
                    .sortedWith(exerciseCandidateOrder())
                    .firstOrNull()
                    ?: return@forEach
                selected += best
                coveredMuscles += best.analysis.muscles
                remaining.removeAll { it.exercise.id == best.exercise.id }
            }
        }

        while (selected.size < targetExerciseCount && remaining.isNotEmpty()) {
            val best = remaining.sortedWith(
                compareByDescending<ExerciseCandidate> { candidate ->
                    balancedScore(
                        candidate = candidate,
                        coveredMuscles = coveredMuscles,
                        targetMuscles = targetMuscles,
                        lastTrainedByMuscle = lastTrainedByMuscle,
                        nowMillis = nowMillis,
                        zoneId = zoneId
                    )
                }.thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            ).firstOrNull() ?: break
            selected += best
            coveredMuscles += best.analysis.muscles
            remaining.removeAll { it.exercise.id == best.exercise.id }
        }

        if (selected.size < targetExerciseCount) {
            selected += candidates
                .filter { candidate -> isExerciseEligibleForFocus(candidate.analysis, focus) }
                .filterNot { candidate -> selected.any { it.exercise.id == candidate.exercise.id } }
                .sortedWith(exerciseCandidateOrder())
                .take(targetExerciseCount - selected.size)
        }

        return selected.take(targetExerciseCount)
    }

    private fun selectRequiredPattern(
        remaining: MutableList<ExerciseCandidate>,
        selected: MutableList<ExerciseCandidate>,
        coveredMuscles: MutableSet<String>,
        patterns: Set<MovementPattern>
    ) {
        val best = remaining
            .filter { candidate -> candidate.analysis.patterns.any { it in patterns } }
            .sortedWith(
                compareByDescending<ExerciseCandidate> { candidate ->
                    candidate.score + candidate.analysis.patterns.count { it in patterns } * 35.0
                }.thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            )
            .firstOrNull()
            ?: return

        selected += best
        coveredMuscles += best.analysis.muscles
        remaining.removeAll { it.exercise.id == best.exercise.id }
    }

    private fun exerciseCandidateOrder(): Comparator<ExerciseCandidate> {
        return compareByDescending<ExerciseCandidate> { it.score }
            .thenBy { it.analysis.identityKey }
            .thenBy { it.exercise.id }
    }

    private fun shouldPrioritizeHeavyLower(history: List<ExerciseHistoryEntry>): Boolean {
        val latestLowerSession = history
            .sessionGroupsByDate()
            .firstOrNull { dominantFocus(it.entries).isLowerDay() }
            ?: return true
        val patterns = latestLowerSession.entries
            .flatMap { analyzeExercise(it.exerciseName).patterns }
            .toSet()
        return MovementPattern.Squat !in patterns &&
            MovementPattern.LegPress !in patterns &&
            MovementPattern.Hinge !in patterns
    }

    private fun balancedScore(
        candidate: ExerciseCandidate,
        coveredMuscles: Set<String>,
        targetMuscles: Set<String>,
        lastTrainedByMuscle: Map<String, Long>,
        nowMillis: Long,
        zoneId: ZoneId
    ): Double {
        val newTargetMuscles = candidate.analysis.muscles.count { it in targetMuscles && it !in coveredMuscles }
        val targetOverlap = candidate.analysis.muscles.count { it in targetMuscles }
        val fatiguePenalty = candidate.analysis.muscles.sumOf { muscle ->
            val lastTrained = lastTrainedByMuscle[muscle] ?: return@sumOf 0.0
            when (daysBetween(lastTrained, nowMillis, zoneId)) {
                0 -> 28.0
                1 -> 18.0
                2 -> 8.0
                else -> 0.0
            }
        }
        val tooMuchSameCategoryPenalty = if (
            coveredMuscles.isNotEmpty() &&
            candidate.analysis.muscles.all { it in coveredMuscles }
        ) {
            10.0
        } else {
            0.0
        }

        return candidate.score + newTargetMuscles * 24.0 + targetOverlap * 4.0 - fatiguePenalty - tooMuchSameCategoryPenalty
    }

    private fun dominantFocus(entries: List<ExerciseHistoryEntry>): SmartWorkoutFocus {
        val counts = entries
            .groupingBy { analyzeExercise(it.exerciseName).category }
            .eachCount()
        val lowerCount = (counts[SmartWorkoutFocus.Legs] ?: 0) + (counts[SmartWorkoutFocus.Lower] ?: 0)
        val upperCount = (counts[SmartWorkoutFocus.Push] ?: 0) + (counts[SmartWorkoutFocus.Pull] ?: 0) + (counts[SmartWorkoutFocus.Upper] ?: 0)

        return when {
            lowerCount > upperCount -> SmartWorkoutFocus.Lower
            upperCount > lowerCount -> {
                val pushCount = counts[SmartWorkoutFocus.Push] ?: 0
                val pullCount = counts[SmartWorkoutFocus.Pull] ?: 0
                if (pushCount >= pullCount) SmartWorkoutFocus.Push else SmartWorkoutFocus.Pull
            }
            else -> SmartWorkoutFocus.FullBody
        }
    }

    private fun recentSessionIds(history: List<ExerciseHistoryEntry>, limit: Int): Set<Long> {
        return history
            .sessionGroupsByDate()
            .take(limit)
            .map { it.id }
            .toSet()
    }

    private fun lastTrainedByMuscle(history: List<ExerciseHistoryEntry>): Map<String, Long> {
        val result = mutableMapOf<String, Long>()
        history.forEach { entry ->
            analyzeExercise(entry.exerciseName).muscles.forEach { muscle ->
                result[muscle] = max(result[muscle] ?: 0L, entry.sessionDate)
            }
        }
        return result
    }

    private fun targetMusclesForFocus(focus: SmartWorkoutFocus): Set<String> {
        return when (focus) {
            SmartWorkoutFocus.Upper -> pushMuscles + pullMuscles
            SmartWorkoutFocus.Lower,
            SmartWorkoutFocus.Legs -> lowerMuscles + coreMuscles
            SmartWorkoutFocus.Push -> pushMuscles
            SmartWorkoutFocus.Pull -> pullMuscles
            SmartWorkoutFocus.FullBody -> pushMuscles + pullMuscles + lowerMuscles + coreMuscles
        }
    }

    private fun chooseMostNeglectedFocus(history: List<ExerciseHistoryEntry>): SmartWorkoutFocus {
        val lastByFocus = history
            .groupBy { analyzeExercise(it.exerciseName).category }
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

    private data class ExerciseSessionSnapshot(
        val sessionId: Long,
        val sets: List<ExerciseHistoryEntry>
    ) {
        val date: Long = sets.first().sessionDate
        val maxWeight: Double = sets.maxOf { it.weight }
        val averageReps: Double = sets.map { it.reps }.average()
        val volume: Double = sets.sumOf { it.weight * it.reps }
        val averageVolumePerSet: Double = volume / sets.size
        val estimatedMax: Double = sets.maxOf { it.weight * (1.0 + it.reps / 30.0) }
    }

    private data class RepRange(
        val minimum: Int,
        val maximum: Int
    )

    private data class ExerciseCandidate(
        val exercise: ExerciseEntity,
        val analysis: ExerciseAnalysis,
        val score: Double
    )

    private data class ExerciseAnalysis(
        val identityKey: String,
        val category: SmartWorkoutFocus,
        val muscles: Set<String>,
        val patterns: Set<MovementPattern>
    ) {
        val isCompound: Boolean
            get() = patterns.any { it in compoundMovementPatterns }
    }

    private enum class MovementPattern {
        Squat,
        LegPress,
        Hinge,
        KneeFlexion,
        KneeExtension,
        Calf,
        HorizontalPress,
        VerticalPress,
        HorizontalPull,
        VerticalPull,
        Core,
        Accessory
    }

    private val lowerMovementPatterns = setOf(
        MovementPattern.Squat,
        MovementPattern.LegPress,
        MovementPattern.Hinge,
        MovementPattern.KneeFlexion,
        MovementPattern.KneeExtension,
        MovementPattern.Calf
    )
    private val compoundMovementPatterns = setOf(
        MovementPattern.Squat,
        MovementPattern.LegPress,
        MovementPattern.Hinge,
        MovementPattern.HorizontalPress,
        MovementPattern.VerticalPress,
        MovementPattern.HorizontalPull,
        MovementPattern.VerticalPull
    )
    private val upperFocuses = setOf(SmartWorkoutFocus.Upper, SmartWorkoutFocus.Push, SmartWorkoutFocus.Pull)
    private val lowerFocuses = setOf(SmartWorkoutFocus.Lower, SmartWorkoutFocus.Legs)
    private val pushMuscles = setOf("chest", "shoulders", "triceps")
    private val pullMuscles = setOf("lats", "upperBack", "biceps", "forearms")
    private val lowerMuscles = setOf("quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack")
    private val coreMuscles = setOf("abs", "obliques")
}

private fun String.containsAny(vararg tokens: String): Boolean {
    return tokens.any { token -> contains(token) }
}

private data class SessionGroup(
    val id: Long,
    val date: Long,
    val entries: List<ExerciseHistoryEntry>
)

private fun List<ExerciseHistoryEntry>.sessionGroupsByDate(): List<SessionGroup> {
    return groupBy { it.sessionId }
        .map { (sessionId, entries) ->
            SessionGroup(
                id = sessionId,
                date = entries.maxOf { it.sessionDate },
                entries = entries
            )
        }
        .sortedWith(compareByDescending<SessionGroup> { it.date }.thenByDescending { it.id })
}

private val SmartWorkoutVariant.index: Int
    get() = when (this) {
        SmartWorkoutVariant.A -> 0
        SmartWorkoutVariant.B -> 1
        SmartWorkoutVariant.C -> 2
    }

private fun ExerciseHistoryEntry.isUsableForRecommendation(nowMillis: Long): Boolean {
    val latestAllowedTimestamp = if (nowMillis > Long.MAX_VALUE - RecommendationFutureClockSkewMillis) {
        Long.MAX_VALUE
    } else {
        nowMillis + RecommendationFutureClockSkewMillis
    }
    return sessionId > 0L &&
        exerciseId > 0L &&
        setOrderIndex in 0 until WorkoutDataLimits.MAX_SETS_PER_EXERCISE &&
        WorkoutDataLimits.isValidTimestamp(sessionDate) &&
        sessionDate <= latestAllowedTimestamp &&
        WorkoutDataLimits.isValidWeight(weight) &&
        WorkoutDataLimits.isValidReps(reps) &&
        WorkoutDataLimits.isValidExerciseName(exerciseName)
}

private const val RecommendationFutureClockSkewMillis = 24L * 60L * 60L * 1_000L

private fun SmartWorkoutFocus.isUpperDay(): Boolean {
    return this == SmartWorkoutFocus.Upper || this == SmartWorkoutFocus.Push || this == SmartWorkoutFocus.Pull
}

private fun SmartWorkoutFocus.isLowerDay(): Boolean {
    return this == SmartWorkoutFocus.Lower || this == SmartWorkoutFocus.Legs
}
