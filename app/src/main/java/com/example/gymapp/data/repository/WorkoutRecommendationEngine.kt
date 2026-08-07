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
    LoadBoundaryReached,
    BodyweightProgressionNeeded,
    AestheticGoal,
    CalorieDeficit,
    FourDayUpperLower,
    RecoveryEffort,
    HardEffort
}

data class WorkoutRecommendation(
    val exerciseId: Long,
    val sets: List<RecommendedWorkoutSet>,
    val kind: WorkoutRecommendationKind,
    val confidence: Float,
    val estimatedVolume: Double,
    val daysSinceLastSession: Int?,
    val reasons: List<WorkoutRecommendationReason>,
    val targetRir: IntRange = 2..3
)

enum class SmartWorkoutEffort {
    Auto,
    Recovery,
    Standard,
    Hard
}

enum class SmartWorkoutEffortAdjustment {
    AutoRecovery,
    HardInsufficientHistory,
    HardRecentBreak,
    HardMusclesRecovering
}

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

enum class SmartWorkoutAlternativeReason {
    SameMovement,
    SameMuscles,
    SimilarRole,
    SameEquipment,
    Familiar,
    Favorite
}

data class SmartWorkoutAlternative(
    val exercise: ExerciseEntity,
    val recommendation: WorkoutRecommendation,
    val reasons: List<SmartWorkoutAlternativeReason>
)

data class SmartWorkoutPlan(
    val focus: SmartWorkoutFocus,
    val exercises: List<SmartWorkoutExercise>,
    val variant: SmartWorkoutVariant = SmartWorkoutVariant.A,
    val requestedEffort: SmartWorkoutEffort = SmartWorkoutEffort.Auto,
    val appliedEffort: SmartWorkoutEffort = SmartWorkoutEffort.Standard,
    val effortAdjustment: SmartWorkoutEffortAdjustment? = null
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
        exerciseName: String? = null,
        loadProfile: ExerciseLoadProfile? = null,
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Standard,
        hardSetEligible: Boolean = true
    ): WorkoutRecommendation {
        val appliedEffort = effort.takeUnless { it == SmartWorkoutEffort.Auto }
            ?: SmartWorkoutEffort.Standard
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
            val targetSetCount = setBudget(
                trainingProfile = trainingProfile,
                analysis = programmingAnalysis,
                effort = appliedEffort,
                hardSetEligible = false
            )
            val startingWeight = when (programmingAnalysis?.loadMode) {
                ExerciseLoadMode.Bodyweight,
                ExerciseLoadMode.None -> 0.0
                ExerciseLoadMode.Standard,
                ExerciseLoadMode.Assistance,
                null -> null
            }
            val defaultReps = defaultTargetReps(trainingProfile, programmingAnalysis, repRange)
            val startingReps = if (
                appliedEffort == SmartWorkoutEffort.Recovery &&
                programmingAnalysis?.loadMode in setOf(ExerciseLoadMode.Bodyweight, ExerciseLoadMode.None)
            ) {
                (defaultReps - 1).coerceIn(repRange.minimum, repRange.maximum)
            } else {
                defaultReps
            }
            return WorkoutRecommendation(
                exerciseId = exerciseId,
                sets = List(targetSetCount) {
                    RecommendedWorkoutSet(
                        weight = startingWeight,
                        reps = startingReps
                    )
                },
                kind = WorkoutRecommendationKind.NewExercise,
                confidence = 0.35f,
                estimatedVolume = 0.0,
                daysSinceLastSession = null,
                reasons = buildList {
                    add(WorkoutRecommendationReason.NoHistory)
                    when (appliedEffort) {
                        SmartWorkoutEffort.Recovery -> add(WorkoutRecommendationReason.RecoveryEffort)
                        // A hard day still needs exercise-specific history before it can safely
                        // prescribe low-RIR work or an extra set for this movement.
                        SmartWorkoutEffort.Hard -> Unit
                        SmartWorkoutEffort.Auto,
                        SmartWorkoutEffort.Standard -> Unit
                    }
                },
                targetRir = targetRirFor(
                    effort = appliedEffort,
                    kind = WorkoutRecommendationKind.NewExercise,
                    hardIntensityEligible = false
                )
            )
        }

        val latest = sessions.first()
        val previous = sessions.getOrNull(1)
        val daysSinceLastSession = daysBetween(latest.date, nowMillis, zoneId)
        val repRange = goalRepRange(trainingProfile, programmingAnalysis)
        val requestedHardIntensity = appliedEffort == SmartWorkoutEffort.Hard &&
            hardSetEligible && sessions.size >= 2 && programmingAnalysis?.isCompound == true
        val programmedSetCount = setBudget(
            trainingProfile = trainingProfile,
            analysis = programmingAnalysis,
            effort = appliedEffort,
            hardSetEligible = requestedHardIntensity
        )
        val loadMode = programmingAnalysis?.loadMode ?: ExerciseLoadMode.Standard
        val effectiveLoadDirection = loadProfile?.direction ?: if (loadMode == ExerciseLoadMode.Assistance) {
            ExerciseLoadDirection.LowerIsHarder
        } else {
            ExerciseLoadDirection.HigherIsHarder
        }
        val usesExternalLoadMetrics = effectiveLoadDirection == ExerciseLoadDirection.HigherIsHarder &&
            loadMode != ExerciseLoadMode.Assistance
        val bestEstimatedMax = if (usesExternalLoadMetrics) {
            sessions.maxOf { it.estimatedMax }
        } else {
            0.0
        }
        val canAssessPlateau = effectiveLoadDirection == ExerciseLoadDirection.HigherIsHarder &&
            latest.maxWeight > 0.0
        val canAssessStandardRegression = effectiveLoadDirection == ExerciseLoadDirection.HigherIsHarder &&
            (latest.maxWeight > 0.0 || loadMode == ExerciseLoadMode.Bodyweight)
        val plateauDetected = canAssessPlateau && isTruePlateau(sessions.take(4))
        val repeatedRegression = sessions.size >= 3 && when (effectiveLoadDirection) {
            ExerciseLoadDirection.HigherIsHarder -> canAssessStandardRegression &&
                isComparableRegression(newer = sessions[0], older = sessions[1]) &&
                isComparableRegression(newer = sessions[1], older = sessions[2])
            ExerciseLoadDirection.LowerIsHarder ->
                isComparableAssistanceRegression(newer = sessions[0], older = sessions[1]) &&
                    isComparableAssistanceRegression(newer = sessions[1], older = sessions[2])
        }
        val latestNearBest = usesExternalLoadMetrics &&
            latest.estimatedMax >= bestEstimatedMax * 0.97
        val previousVolumePerSet = previous?.averageVolumePerSet ?: latest.averageVolumePerSet
        val volumeRatio = if (!usesExternalLoadMetrics || previousVolumePerSet <= 0.0) {
            1.0
        } else {
            latest.averageVolumePerSet / previousVolumePerSet
        }
        val latestStable = latest.sets.all { it.reps >= repRange.minimum }
        val latestStrained = latest.sets.any { it.reps < repRange.minimum } ||
            usesExternalLoadMetrics && volumeRatio < 0.9
        val completedRepCeiling = completedAtRepCeiling(
            session = latest,
            targetSetCount = programmedSetCount,
            repCeiling = repRange.maximum
        ) && completedAtRepCeiling(
            session = previous,
            targetSetCount = programmedSetCount,
            repCeiling = repRange.maximum
        ) && performanceDidNotDecline(
            latest = latest,
            previous = previous,
            targetSetCount = programmedSetCount,
            direction = effectiveLoadDirection
        )
        val needsHarderBodyweight = completedRepCeiling &&
            loadMode == ExerciseLoadMode.Bodyweight && latest.maxWeight <= 0.0
        val earnedProgression = completedRepCeiling && !needsHarderBodyweight
        val harderWeightAvailable = loadProfile == null || latest.sets
            .take(programmedSetCount)
            .any { set ->
                when (effectiveLoadDirection) {
                    ExerciseLoadDirection.HigherIsHarder ->
                        loadProfile.allowedWeightsKg.any { it > set.weight }
                    ExerciseLoadDirection.LowerIsHarder ->
                        loadProfile.allowedWeightsKg.any { it < set.weight }
                }
            }
        val earnedAtLoadBoundary = earnedProgression && !harderWeightAvailable
        val isFatLossDeficit = trainingProfile.goal == TrainingGoal.AestheticFatLoss &&
            trainingProfile.calorieMode == CalorieMode.Deficit

        val baseKind = when {
            daysSinceLastSession >= ComebackBreakDays -> WorkoutRecommendationKind.Comeback
            repeatedRegression -> WorkoutRecommendationKind.Deload
            earnedProgression && harderWeightAvailable -> WorkoutRecommendationKind.ProgressiveOverload
            plateauDetected -> WorkoutRecommendationKind.PlateauBreak
            else -> WorkoutRecommendationKind.HoldAndBuild
        }
        val kind = if (
            appliedEffort == SmartWorkoutEffort.Recovery &&
            baseKind != WorkoutRecommendationKind.Deload &&
            baseKind != WorkoutRecommendationKind.Comeback
        ) {
            WorkoutRecommendationKind.HoldAndBuild
        } else {
            baseKind
        }
        val effortOverriddenByRecovery = kind == WorkoutRecommendationKind.Deload ||
            kind == WorkoutRecommendationKind.Comeback
        val hardIntensityEligible = requestedHardIntensity && !effortOverriddenByRecovery
        val targetSetCount = if (effortOverriddenByRecovery) {
            3
        } else {
            programmedSetCount
        }

        val baselineSets = baselineSets(latest.sets, targetSetCount)
        val plateauUsesLowerRange = latest.averageReps >= (repRange.minimum + repRange.maximum) / 2.0
        val sets = baselineSets.map { baseline ->
            val weight = when {
                kind == WorkoutRecommendationKind.Deload -> easierWeight(
                    currentWeight = baseline.weight,
                    retainedIntensity = if (isFatLossDeficit) 0.9 else 0.92,
                    direction = effectiveLoadDirection,
                    loadMode = loadMode,
                    loadProfile = loadProfile
                )
                kind == WorkoutRecommendationKind.Comeback -> easierWeight(
                    currentWeight = baseline.weight,
                    retainedIntensity = comebackMultiplier(daysSinceLastSession),
                    direction = effectiveLoadDirection,
                    loadMode = loadMode,
                    loadProfile = loadProfile
                )
                appliedEffort == SmartWorkoutEffort.Recovery -> easierWeight(
                    currentWeight = baseline.weight,
                    retainedIntensity = 0.9,
                    direction = effectiveLoadDirection,
                    loadMode = loadMode,
                    loadProfile = loadProfile
                )
                kind == WorkoutRecommendationKind.ProgressiveOverload -> {
                    if (baseline.weight <= 0.0) {
                        baseline.weight
                    } else {
                        adjustedWeight(
                            currentWeight = baseline.weight,
                            harder = true,
                            direction = effectiveLoadDirection,
                            loadProfile = loadProfile
                        )
                    }
                }
                kind == WorkoutRecommendationKind.HoldAndBuild ||
                    kind == WorkoutRecommendationKind.PlateauBreak -> when {
                    loadProfile != null ->
                        nearestAllowedWeight(baseline.weight, loadProfile.allowedWeightsKg)
                    loadMode == ExerciseLoadMode.Standard ||
                        loadMode == ExerciseLoadMode.Assistance -> nearestFallbackGridWeight(
                            baseline.weight
                        )
                    else -> baseline.weight
                }
                else -> baseline.weight
            }
            val reps = when {
                kind == WorkoutRecommendationKind.Deload ||
                    kind == WorkoutRecommendationKind.Comeback ->
                    baseline.reps.coerceIn(repRange.minimum, repRange.maximum)
                appliedEffort == SmartWorkoutEffort.Recovery &&
                    (loadMode == ExerciseLoadMode.Bodyweight || loadMode == ExerciseLoadMode.None) ->
                    (baseline.reps - 1).coerceIn(repRange.minimum, repRange.maximum)
                appliedEffort == SmartWorkoutEffort.Recovery ->
                    baseline.reps.coerceIn(repRange.minimum, repRange.maximum)
                kind == WorkoutRecommendationKind.NewExercise ->
                    defaultTargetReps(trainingProfile, programmingAnalysis, repRange)
                kind == WorkoutRecommendationKind.ProgressiveOverload -> {
                    if (baseline.weight <= 0.0) repRange.maximum else repRange.minimum
                }
                kind == WorkoutRecommendationKind.HoldAndBuild ->
                    (baseline.reps + 1).coerceIn(repRange.minimum, repRange.maximum)
                else ->
                    if (plateauUsesLowerRange) repRange.minimum else repRange.maximum
            }
            RecommendedWorkoutSet(weight = weight, reps = reps)
        }

        val reasons = buildList {
            when (appliedEffort) {
                SmartWorkoutEffort.Recovery -> if (!effortOverriddenByRecovery) {
                    add(WorkoutRecommendationReason.RecoveryEffort)
                }
                SmartWorkoutEffort.Hard -> if (hardIntensityEligible) {
                    add(WorkoutRecommendationReason.HardEffort)
                }
                SmartWorkoutEffort.Auto,
                SmartWorkoutEffort.Standard -> Unit
            }
            if (earnedAtLoadBoundary) add(WorkoutRecommendationReason.LoadBoundaryReached)
            if (needsHarderBodyweight) add(WorkoutRecommendationReason.BodyweightProgressionNeeded)
            if (latestStable) add(WorkoutRecommendationReason.LastSessionStrong)
            if (latestStrained || repeatedRegression) add(WorkoutRecommendationReason.LastSessionUnstable)
            if (daysSinceLastSession >= ComebackBreakDays) add(WorkoutRecommendationReason.RecentBreak)
            if (usesExternalLoadMetrics && volumeRatio >= 1.08) {
                add(WorkoutRecommendationReason.VolumeTrendingUp)
            }
            if (usesExternalLoadMetrics && (volumeRatio < 0.9 || repeatedRegression)) {
                add(WorkoutRecommendationReason.VolumeDropped)
            }
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
            estimatedVolume = if (usesExternalLoadMetrics) {
                sets.sumOf { (it.weight ?: 0.0) * it.reps }
            } else {
                0.0
            },
            daysSinceLastSession = daysSinceLastSession,
            reasons = reasons.take(3),
            targetRir = targetRirFor(
                effort = appliedEffort,
                kind = kind,
                hardIntensityEligible = hardIntensityEligible
            )
        )
    }

    fun buildWorkoutPlan(
        exercises: List<ExerciseEntity>,
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile = TrainingProfile(),
        nowMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        loadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
        manualMuscleMappings: Map<String, List<MuscleContribution>> = emptyMap(),
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Auto
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
            return SmartWorkoutPlan(
                focus = SmartWorkoutFocus.FullBody,
                exercises = emptyList(),
                requestedEffort = effort,
                appliedEffort = if (effort == SmartWorkoutEffort.Auto) {
                    SmartWorkoutEffort.Standard
                } else {
                    effort
                }
            )
        }

        val safeHistory = history
            .asSequence()
            .take(WorkoutDataLimits.MAX_TOTAL_SETS)
            .filter { it.isUsableForRecommendation(nowMillis) }
            .toList()
        val focus = chooseWorkoutFocus(safeHistory, trainingProfile, nowMillis, zoneId)
        val variant = chooseWorkoutVariant(focus, safeHistory)
        val effortResolution = resolveEffort(
            requested = effort,
            focus = focus,
            history = safeHistory,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val targetExerciseCount = targetExerciseCount(trainingProfile, effortResolution.applied)
        val targetWorkingSetBudget = targetWorkingSetBudget(
            trainingProfile = trainingProfile,
            effort = effortResolution.applied,
            exerciseLimit = targetExerciseCount
        )
        val weeklyTargets = weeklyMuscleTargets(trainingProfile)
        val completedWeeklySets = completedWeeklyEffectiveSets(
            history = safeHistory,
            nowMillis = nowMillis,
            manualMuscleMappings = manualMuscleMappings
        )

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
                ?: 7
            val sessionCount = exerciseHistory.map { it.sessionId }.distinct().size
            val recentExercisePenalty = exerciseHistory
                .filter { it.sessionId in recentSessionIds }
                .map { it.sessionId }
                .distinct()
                .size * 8.0
            val sameWeekExercisePenalty = if (
                exerciseHistory.any { daysBetween(it.sessionDate, nowMillis, zoneId) <= 6 }
            ) {
                10.0
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
            val dueScore = daysSince.coerceAtMost(14).toDouble()
            val continuityScore = sessionCount.coerceAtMost(4) * 5.0
            val variantScore = variantPreferenceScore(analysis, focus, variant)
            val programmingScore = programmingPreferenceScore(
                analysis = analysis,
                trainingProfile = trainingProfile,
                sessionCount = sessionCount
            )
            val favoriteScore = if (exercise.isFavorite) FavoriteExerciseScore else 0.0

            ExerciseCandidate(
                exercise = exercise,
                analysis = analysis,
                score = focusScore + muscleMatchScore + dueScore + continuityScore +
                    variantScore + programmingScore + favoriteScore -
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
            targetWorkingSetBudget = targetWorkingSetBudget,
            history = safeHistory,
            nowMillis = nowMillis,
            zoneId = zoneId,
            trainingProfile = trainingProfile,
            effort = effortResolution.applied,
            manualMuscleMappings = manualMuscleMappings,
            weeklyTargets = weeklyTargets,
            completedWeeklySets = completedWeeklySets
        )
        var hardCompoundCount = 0
        return SmartWorkoutPlan(
            focus = focus,
            exercises = selected.map { candidate ->
                val candidateHistory = historyByIdentity[candidate.analysis.identityKey].orEmpty()
                val hasHardTrainingHistory = candidateHistory.asSequence()
                    .map { it.sessionId }
                    .distinct()
                    .take(2)
                    .count() >= 2
                val hardSetEligible = effortResolution.applied == SmartWorkoutEffort.Hard &&
                    candidate.analysis.isCompound && hasHardTrainingHistory &&
                    hardCompoundCount < MaxHardCompoundExercises
                if (hardSetEligible) hardCompoundCount += 1
                SmartWorkoutExercise(
                    exercise = candidate.exercise,
                    recommendation = buildForExercise(
                        exerciseId = candidate.exercise.id,
                        history = candidateHistory,
                        trainingProfile = trainingProfile,
                        nowMillis = nowMillis,
                        zoneId = zoneId,
                        exerciseName = candidate.exercise.name,
                        loadProfile = loadProfiles[candidate.exercise.id],
                        effort = effortResolution.applied,
                        hardSetEligible = hardSetEligible
                    )
                )
            },
            variant = variant,
            requestedEffort = effort,
            appliedEffort = effortResolution.applied,
            effortAdjustment = effortResolution.adjustment
        )
    }

    fun findAlternatives(
        currentExerciseId: Long,
        selectedExerciseIds: Set<Long>,
        exercises: List<ExerciseEntity>,
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile = TrainingProfile(),
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Standard,
        loadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
        manualMuscleMappings: Map<String, List<MuscleContribution>> = emptyMap(),
        hardSetEligible: Boolean = true,
        nowMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        limit: Int = MaxAlternativeCount
    ): List<SmartWorkoutAlternative> {
        val safeLimit = limit.coerceIn(1, MaxAlternativeCount)
        val safeExercises = exercises.asSequence()
            .take(WorkoutDataLimits.MAX_EXERCISES)
            .filter { exercise ->
                exercise.id > 0L && WorkoutDataLimits.isValidExerciseName(exercise.name) &&
                    BuiltInExerciseCatalog.inferKey(exercise.name) != "warm_up"
            }
            .distinctBy { it.id }
            .toList()
        val current = safeExercises.firstOrNull { it.id == currentExerciseId } ?: return emptyList()
        val currentAnalysis = analyzeExercise(current.name)
        val selectedIdentities = safeExercises.asSequence()
            .filter { it.id in selectedExerciseIds && it.id != currentExerciseId }
            .map { analyzeExercise(it.name).identityKey }
            .toSet()
        val safeHistory = history.asSequence()
            .take(WorkoutDataLimits.MAX_TOTAL_SETS)
            .filter { it.isUsableForRecommendation(nowMillis) }
            .toList()
        val currentMuscles = weightedMuscles(
            exerciseName = current.name,
            analysis = currentAnalysis,
            manualMuscleMappings = manualMuscleMappings
        )
        val currentEquipment = exerciseEquipment(current.name, currentAnalysis)

        return safeExercises.asSequence()
            .filterNot { it.id == currentExerciseId || it.id in selectedExerciseIds }
            .map { candidate ->
                val analysis = analyzeExercise(candidate.name)
                val candidateMuscles = weightedMuscles(
                    exerciseName = candidate.name,
                    analysis = analysis,
                    manualMuscleMappings = manualMuscleMappings
                )
                val muscleOverlap = weightedMuscleOverlap(currentMuscles, candidateMuscles)
                val sharedMovement = sharedMovementScore(currentAnalysis, analysis)
                val roleScore = roleCompatibilityScore(currentAnalysis, analysis)
                val trunkCompatible = currentAnalysis.trunkKind() == analysis.trunkKind() ||
                    currentAnalysis.trunkKind() == null && analysis.trunkKind() == null
                if (!trunkCompatible || sharedMovement <= 0.0 || muscleOverlap < MinimumAlternativeMuscleOverlap ||
                    roleScore < 0.0 || analysis.identityKey in selectedIdentities
                ) {
                    return@map null
                }
                val equipmentMatches = currentEquipment == exerciseEquipment(candidate.name, analysis)
                val sessionCount = safeHistory.asSequence()
                    .filter { entry -> analyzeExercise(entry.exerciseName).identityKey == analysis.identityKey }
                    .map { it.sessionId }
                    .distinct()
                    .take(4)
                    .count()
                val score = sharedMovement + muscleOverlap * 100.0 + roleScore +
                    (if (analysis.category == currentAnalysis.category) 10.0 else 0.0) +
                    (if (equipmentMatches) AlternativeEquipmentScore else 0.0) +
                    sessionCount * AlternativeFamiliarityScore +
                    (if (candidate.isFavorite) FavoriteExerciseScore else 0.0)
                AlternativeCandidate(
                    exercise = candidate,
                    analysis = analysis,
                    score = score,
                    reasons = buildList {
                        add(SmartWorkoutAlternativeReason.SameMovement)
                        add(SmartWorkoutAlternativeReason.SameMuscles)
                        if (roleScore > 0.0) add(SmartWorkoutAlternativeReason.SimilarRole)
                        if (equipmentMatches) add(SmartWorkoutAlternativeReason.SameEquipment)
                        if (sessionCount > 0) add(SmartWorkoutAlternativeReason.Familiar)
                        if (candidate.isFavorite) add(SmartWorkoutAlternativeReason.Favorite)
                    }
                )
            }
            .filterNotNull()
            .groupBy { it.analysis.identityKey }
            .values
            .map { equivalents -> equivalents.maxBy { it.score } }
            .sortedWith(
                compareByDescending<AlternativeCandidate> { it.score }
                    .thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            )
            .take(safeLimit)
            .map { candidate ->
                SmartWorkoutAlternative(
                    exercise = candidate.exercise,
                    recommendation = buildForExercise(
                        exerciseId = candidate.exercise.id,
                        history = safeHistory,
                        trainingProfile = trainingProfile,
                        nowMillis = nowMillis,
                        zoneId = zoneId,
                        exerciseName = candidate.exercise.name,
                        loadProfile = loadProfiles[candidate.exercise.id],
                        effort = effort,
                        hardSetEligible = hardSetEligible
                    ),
                    reasons = candidate.reasons
                )
            }
            .toList()
    }

    private fun easierWeight(
        currentWeight: Double,
        retainedIntensity: Double,
        direction: ExerciseLoadDirection,
        loadMode: ExerciseLoadMode,
        loadProfile: ExerciseLoadProfile?
    ): Double {
        if (currentWeight <= 0.0 || loadMode == ExerciseLoadMode.Bodyweight ||
            loadMode == ExerciseLoadMode.None
        ) {
            return currentWeight
        }
        val safeIntensity = retainedIntensity.coerceIn(0.5, 1.0)
        val targetWeight = when (direction) {
            ExerciseLoadDirection.HigherIsHarder -> currentWeight * safeIntensity
            ExerciseLoadDirection.LowerIsHarder -> currentWeight / safeIntensity
        }
        if (loadProfile != null) {
            val easierOptions = when (direction) {
                ExerciseLoadDirection.HigherIsHarder ->
                    loadProfile.allowedWeightsKg.filter { it < currentWeight }
                ExerciseLoadDirection.LowerIsHarder ->
                    loadProfile.allowedWeightsKg.filter { it > currentWeight }
            }
            if (easierOptions.isEmpty()) return currentWeight
            return when (direction) {
                ExerciseLoadDirection.HigherIsHarder ->
                    easierOptions.lastOrNull { it <= targetWeight } ?: easierOptions.first()
                ExerciseLoadDirection.LowerIsHarder ->
                    easierOptions.firstOrNull { it >= targetWeight } ?: easierOptions.last()
            }
        }
        return snapFallbackWeightToGrid(
            currentWeight = currentWeight,
            targetWeight = targetWeight,
            increaseWeight = direction == ExerciseLoadDirection.LowerIsHarder
        )
    }

    private fun adjustedWeight(
        currentWeight: Double,
        harder: Boolean,
        direction: ExerciseLoadDirection,
        loadProfile: ExerciseLoadProfile?
    ): Double {
        if (loadProfile != null) {
            val increaseWeight = when (direction) {
                ExerciseLoadDirection.HigherIsHarder -> harder
                ExerciseLoadDirection.LowerIsHarder -> !harder
            }
            return if (increaseWeight) {
                loadProfile.allowedWeightsKg.firstOrNull { it > currentWeight }
                    ?: loadProfile.allowedWeightsKg.last()
            } else {
                loadProfile.allowedWeightsKg.lastOrNull { it < currentWeight }
                    ?: loadProfile.allowedWeightsKg.first()
            }
        }
        val increaseWeight = when (direction) {
            ExerciseLoadDirection.HigherIsHarder -> harder
            ExerciseLoadDirection.LowerIsHarder -> !harder
        }
        return snapFallbackWeightToGrid(
            currentWeight = currentWeight,
            targetWeight = currentWeight,
            increaseWeight = increaseWeight
        )
    }

    private fun snapFallbackWeightToGrid(
        currentWeight: Double,
        targetWeight: Double,
        increaseWeight: Boolean
    ): Double {
        val gridKg = 2.5
        var snapped = if (increaseWeight) {
            kotlin.math.ceil(targetWeight / gridKg) * gridKg
        } else {
            kotlin.math.floor(targetWeight / gridKg) * gridKg
        }
        if (increaseWeight && snapped <= currentWeight) snapped += gridKg
        if (!increaseWeight && snapped >= currentWeight) snapped -= gridKg
        return snapped.coerceIn(0.0, WorkoutDataLimits.MAX_WEIGHT).let { bounded ->
            if (increaseWeight && bounded <= currentWeight ||
                !increaseWeight && bounded >= currentWeight
            ) currentWeight else bounded
        }
    }

    private fun nearestFallbackGridWeight(weight: Double): Double =
        (round(weight / 2.5) * 2.5).coerceIn(0.0, WorkoutDataLimits.MAX_WEIGHT)

    private fun nearestAllowedWeight(currentWeight: Double, allowedWeights: List<Double>): Double =
        allowedWeights.minWithOrNull(
            compareBy<Double> { kotlin.math.abs(it - currentWeight) }.thenBy { it }
        ) ?: currentWeight

    private fun targetRirFor(
        effort: SmartWorkoutEffort,
        kind: WorkoutRecommendationKind,
        hardIntensityEligible: Boolean
    ): IntRange {
        if (kind == WorkoutRecommendationKind.Deload || kind == WorkoutRecommendationKind.Comeback) {
            return 3..4
        }
        return when (effort) {
            SmartWorkoutEffort.Recovery -> 3..4
            SmartWorkoutEffort.Hard -> if (hardIntensityEligible) 1..2 else 2..3
            SmartWorkoutEffort.Auto,
            SmartWorkoutEffort.Standard -> 2..3
        }
    }

    private fun goalRepRange(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ): RepRange {
        // A missing/invalid exercise name has no evidence that it is a compound movement.
        // Match iOS/PWA and use the conservative isolation prescription.
        val role = analysis?.role ?: ExerciseRole.Isolation
        return when (trainingProfile.goal) {
            TrainingGoal.Strength -> when (role) {
                ExerciseRole.Primary -> RepRange(minimum = 4, maximum = 6)
                ExerciseRole.Secondary -> RepRange(minimum = 5, maximum = 8)
                ExerciseRole.Isolation,
                ExerciseRole.Core,
                ExerciseRole.Warmup -> RepRange(minimum = 8, maximum = 10)
            }
            TrainingGoal.MuscleGain -> when (role) {
                ExerciseRole.Primary -> RepRange(minimum = 6, maximum = 8)
                ExerciseRole.Secondary -> RepRange(minimum = 7, maximum = 10)
                ExerciseRole.Isolation,
                ExerciseRole.Core,
                ExerciseRole.Warmup -> RepRange(minimum = 8, maximum = 10)
            }
            TrainingGoal.AestheticFatLoss -> when (role) {
                ExerciseRole.Primary -> RepRange(minimum = 6, maximum = 8)
                ExerciseRole.Secondary -> RepRange(minimum = 7, maximum = 10)
                ExerciseRole.Isolation,
                ExerciseRole.Core,
                ExerciseRole.Warmup -> RepRange(minimum = 8, maximum = 10)
            }
            TrainingGoal.Balanced -> when (role) {
                ExerciseRole.Primary -> RepRange(minimum = 5, maximum = 8)
                ExerciseRole.Secondary -> RepRange(minimum = 6, maximum = 10)
                ExerciseRole.Isolation,
                ExerciseRole.Core,
                ExerciseRole.Warmup -> RepRange(minimum = 8, maximum = 10)
            }
        }
    }

    private fun defaultTargetReps(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        repRange: RepRange
    ): Int {
        val target = when (trainingProfile.goal) {
            TrainingGoal.Strength -> when (analysis?.role) {
                ExerciseRole.Primary -> 5
                ExerciseRole.Secondary -> 6
                else -> 8
            }
            TrainingGoal.MuscleGain -> when (analysis?.role) {
                ExerciseRole.Primary -> 8
                ExerciseRole.Secondary -> 9
                else -> 10
            }
            TrainingGoal.AestheticFatLoss -> when (analysis?.role) {
                ExerciseRole.Primary -> 8
                ExerciseRole.Secondary -> 9
                else -> 10
            }
            TrainingGoal.Balanced -> when (analysis?.role) {
                ExerciseRole.Primary -> 7
                ExerciseRole.Secondary -> 8
                else -> 10
            }
        }
        return target.coerceIn(repRange.minimum, repRange.maximum)
    }

    private fun setBudget(
        trainingProfile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Standard,
        hardSetEligible: Boolean = true
    ): Int {
        if (effort == SmartWorkoutEffort.Recovery) return 3
        if (effort == SmartWorkoutEffort.Hard) {
            return if (hardSetEligible && analysis?.isCompound == true) 4 else 3
        }
        val highFrequency = trainingProfile.workoutsPerWeek.coerceIn(2, 6) >= 5
        val recoveryLimited = trainingProfile.calorieMode == CalorieMode.Deficit
        return when (analysis?.role) {
            ExerciseRole.Primary -> if (!recoveryLimited && !highFrequency) 4 else 3
            ExerciseRole.Secondary -> 3
            ExerciseRole.Isolation,
            ExerciseRole.Core,
            ExerciseRole.Warmup,
            null -> 3
        }
    }

    internal fun weeklyMuscleTargets(trainingProfile: TrainingProfile): Map<String, Double> {
        val goalBase = when (trainingProfile.goal) {
            TrainingGoal.MuscleGain -> 10
            TrainingGoal.Strength,
            TrainingGoal.Balanced,
            TrainingGoal.AestheticFatLoss -> 8
        }
        val calorieAdjustment = when (trainingProfile.calorieMode) {
            CalorieMode.Deficit -> -1
            CalorieMode.Maintenance -> 0
            CalorieMode.Surplus -> 1
        }
        val base = (goalBase + calorieAdjustment).toDouble()
        return MUSCLE_DEFINITIONS.associate { definition ->
            val multiplier = when (definition.id) {
                in majorMuscles -> 1.0
                in secondaryMuscles -> 0.75
                else -> 0.5
            }
            definition.id to (base * multiplier).coerceIn(4.0, 12.0)
        }
    }

    internal fun completedWeeklyEffectiveSets(
        history: List<ExerciseHistoryEntry>,
        nowMillis: Long,
        manualMuscleMappings: Map<String, List<MuscleContribution>>
    ): Map<String, Double> {
        val windowStart = nowMillis - WEEKLY_VOLUME_WINDOW_MILLIS
        val result = MUSCLE_DEFINITIONS.associate { it.id to 0.0 }.toMutableMap()
        history.asSequence()
            .filter { it.sessionDate in windowStart..nowMillis }
            .forEach { entry ->
                safeMuscleContributions(entry.exerciseName, manualMuscleMappings).forEach { contribution ->
                    result[contribution.muscleId] =
                        (result[contribution.muscleId] ?: 0.0) + contribution.weight
                }
            }
        return result
    }

    private fun weeklyVolumeScore(
        candidate: ExerciseCandidate,
        projectedWeeklySets: Map<String, Double>,
        weeklyTargets: Map<String, Double>,
        plannedSets: Int,
        manualMuscleMappings: Map<String, List<MuscleContribution>>
    ): Double {
        val contributions = safeMuscleContributions(candidate.exercise.name, manualMuscleMappings)
        val coverageGain = contributions.sumOf { contribution ->
            val target = weeklyTargets[contribution.muscleId] ?: return@sumOf 0.0
            val remaining = (target - (projectedWeeklySets[contribution.muscleId] ?: 0.0))
                .coerceAtLeast(0.0)
            minOf(remaining, plannedSets * contribution.weight)
        }
        val saturatedPenalty = if (coverageGain <= 0.0) {
            12.0 * contributions.sumOf { it.weight }
        } else {
            0.0
        }
        return coverageGain * 18.0 - saturatedPenalty
    }

    private fun addProjectedWeeklySets(
        candidate: ExerciseCandidate,
        projectedWeeklySets: MutableMap<String, Double>,
        plannedSets: Int,
        manualMuscleMappings: Map<String, List<MuscleContribution>>
    ) {
        safeMuscleContributions(candidate.exercise.name, manualMuscleMappings).forEach { contribution ->
            projectedWeeklySets[contribution.muscleId] =
                (projectedWeeklySets[contribution.muscleId] ?: 0.0) + plannedSets * contribution.weight
        }
    }

    private fun safeMuscleContributions(
        exerciseName: String,
        manualMuscleMappings: Map<String, List<MuscleContribution>>
    ): List<MuscleContribution> {
        val knownMuscleIds = MUSCLE_DEFINITIONS.asSequence().map { it.id }.toSet()
        return muscleContributionsForExercise(exerciseName, manualMuscleMappings)
            .asSequence()
            .filter { it.muscleId in knownMuscleIds && it.weight.isFinite() && it.weight > 0.0 }
            .groupBy { it.muscleId }
            .map { (muscleId, contributions) ->
                MuscleContribution(
                    muscleId = muscleId,
                    weight = contributions.maxOf { it.weight }.coerceIn(0.0, 1.0)
                )
            }
            .sortedBy { it.muscleId }
    }

    private fun weightedMuscles(
        exerciseName: String,
        analysis: ExerciseAnalysis,
        manualMuscleMappings: Map<String, List<MuscleContribution>>
    ): Map<String, Double> {
        val contributions = safeMuscleContributions(exerciseName, manualMuscleMappings)
        return if (contributions.isNotEmpty()) {
            contributions.associate { it.muscleId to it.weight }
        } else {
            analysis.muscles.associateWith { 1.0 }
        }
    }

    private fun weightedMuscleOverlap(
        first: Map<String, Double>,
        second: Map<String, Double>
    ): Double {
        val ids = first.keys + second.keys
        if (ids.isEmpty()) return 0.0
        val intersection = ids.sumOf { id -> minOf(first[id] ?: 0.0, second[id] ?: 0.0) }
        val union = ids.sumOf { id -> maxOf(first[id] ?: 0.0, second[id] ?: 0.0) }
        return if (union > 0.0) intersection / union else 0.0
    }

    private fun sharedMovementScore(
        first: ExerciseAnalysis,
        second: ExerciseAnalysis
    ): Double {
        val firstMovements = first.patterns - MovementPattern.Accessory
        val secondMovements = second.patterns - MovementPattern.Accessory
        if (firstMovements.isEmpty() && secondMovements.isEmpty()) return 70.0
        val shared = firstMovements intersect secondMovements
        return when {
            shared.isEmpty() -> 0.0
            firstMovements == secondMovements -> 120.0
            else -> 100.0
        }
    }

    private fun roleCompatibilityScore(
        first: ExerciseAnalysis,
        second: ExerciseAnalysis
    ): Double {
        return when {
            first.role == second.role -> 30.0
            first.isCompound && second.isCompound -> 20.0
            else -> -1.0
        }
    }

    private fun exerciseEquipment(
        exerciseName: String,
        analysis: ExerciseAnalysis
    ): ExerciseEquipment {
        val key = analysis.identityKey.removePrefix("catalog:")
        return when (key) {
            "bench_press", "incline_bench_press", "barbell_row", "squat",
            "romanian_deadlift", "deadlift", "hip_thrust", "barbell_curl",
            "upright_row", "french_press" -> ExerciseEquipment.Barbell
            "dumbbell_bench_press", "incline_dumbbell_press", "lateral_raise",
            "seated_dumbbell_curl", "hammer_curl", "overhead_dumbbell_triceps_extension",
            "bulgarian_split_squat", "lunge", "weighted_side_bend" -> ExerciseEquipment.Dumbbell
            "lat_pulldown", "straight_arm_pulldown", "seated_cable_row", "face_pull",
            "cable_curl", "triceps_pushdown", "v_bar_pushdown" -> ExerciseEquipment.Cable
            "plate_loaded_row", "chest_fly_machine", "assisted_dip", "assisted_pull_up", "leg_press",
            "leg_extension", "lying_leg_curl", "seated_leg_curl", "hip_adduction",
            "hip_abduction", "machine_lateral_raise", "rear_delt_fly", "preacher_curl" ->
                ExerciseEquipment.Machine
            "band_assisted_pull_up" -> ExerciseEquipment.Band
            "push_up", "dips", "pull_up", "plank", "hanging_leg_raise" ->
                ExerciseEquipment.Bodyweight
            else -> {
                val normalized = exerciseName.normalizedExerciseName()
                when {
                    normalized.containsAny("гантел", "dumbbell") -> ExerciseEquipment.Dumbbell
                    normalized.containsAny("штанг", "barbell") -> ExerciseEquipment.Barbell
                    normalized.containsAny("блок", "кросовер", "cable", "pulldown") ->
                        ExerciseEquipment.Cable
                    normalized.containsAny("гравітрон", "гравитрон", "тренаж", "machine") ->
                        ExerciseEquipment.Machine
                    normalized.containsAny("резин", "еспандер", "band") -> ExerciseEquipment.Band
                    analysis.loadMode == ExerciseLoadMode.Bodyweight -> ExerciseEquipment.Bodyweight
                    else -> ExerciseEquipment.Other
                }
            }
        }
    }

    internal fun canonicalEquipmentForExercise(exerciseName: String): String =
        exerciseEquipment(exerciseName, analyzeExercise(exerciseName)).name

    internal fun recommendedRestSeconds(exerciseName: String): Int = when (
        analyzeExercise(exerciseName).role
    ) {
        ExerciseRole.Primary -> 180
        ExerciseRole.Secondary -> 120
        ExerciseRole.Isolation -> 75
        ExerciseRole.Core,
        ExerciseRole.Warmup -> 60
    }

    private fun targetExerciseCount(
        trainingProfile: TrainingProfile,
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Standard
    ): Int {
        val days = trainingProfile.workoutsPerWeek.coerceIn(2, 6)
        val base = when (days) {
            2 -> 10
            3 -> 9
            4 -> 8
            5 -> 7
            else -> 6
        }
        val goalAdjustment = when (trainingProfile.goal) {
            TrainingGoal.MuscleGain -> 1
            TrainingGoal.Strength,
            TrainingGoal.AestheticFatLoss -> -1
            TrainingGoal.Balanced -> 0
        }
        val calorieAdjustment = when (trainingProfile.calorieMode) {
            CalorieMode.Deficit -> -1
            CalorieMode.Maintenance -> 0
            CalorieMode.Surplus -> 1
        }
        val effortAdjustment = if (effort == SmartWorkoutEffort.Recovery) -2 else 0
        return (base + goalAdjustment + calorieAdjustment + effortAdjustment).coerceIn(5, 10)
    }

    private fun targetWorkingSetBudget(
        trainingProfile: TrainingProfile,
        effort: SmartWorkoutEffort,
        exerciseLimit: Int
    ): Int {
        val goalAdjustment = when (trainingProfile.goal) {
            TrainingGoal.MuscleGain -> 2
            TrainingGoal.Strength -> -2
            TrainingGoal.AestheticFatLoss -> -1
            TrainingGoal.Balanced -> 0
        }
        val calorieAdjustment = when (trainingProfile.calorieMode) {
            CalorieMode.Deficit -> -3
            CalorieMode.Maintenance -> 0
            CalorieMode.Surplus -> 3
        }
        val effortAdjustment = when (effort) {
            SmartWorkoutEffort.Recovery -> -3
            SmartWorkoutEffort.Hard -> 2
            SmartWorkoutEffort.Auto,
            SmartWorkoutEffort.Standard -> 0
        }
        return (exerciseLimit * 3 + goalAdjustment + calorieAdjustment + effortAdjustment)
            .coerceIn(MIN_SESSION_WORKING_SETS, exerciseLimit * 4)
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

    private fun completedAtRepCeiling(
        session: ExerciseSessionSnapshot?,
        targetSetCount: Int,
        repCeiling: Int
    ): Boolean {
        if (session == null || session.sets.size < targetSetCount) return false
        return session.sets.take(targetSetCount).all { it.reps >= repCeiling }
    }

    private fun performanceDidNotDecline(
        latest: ExerciseSessionSnapshot,
        previous: ExerciseSessionSnapshot?,
        targetSetCount: Int,
        direction: ExerciseLoadDirection
    ): Boolean {
        if (previous == null || latest.sets.size < targetSetCount || previous.sets.size < targetSetCount) {
            return false
        }
        val latestSets = latest.sets.take(targetSetCount)
        val previousSets = previous.sets.take(targetSetCount)
        val latestWeight = latestSets.map { it.weight }.average()
        val previousWeight = previousSets.map { it.weight }.average()
        val loadDidNotDecline = when (direction) {
            ExerciseLoadDirection.HigherIsHarder -> latestWeight >= previousWeight
            ExerciseLoadDirection.LowerIsHarder -> latestWeight <= previousWeight
        }
        return loadDidNotDecline &&
            latestSets.map { it.reps }.average() >= previousSets.map { it.reps }.average()
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

    private fun isComparableAssistanceRegression(
        newer: ExerciseSessionSnapshot,
        older: ExerciseSessionSnapshot
    ): Boolean {
        if (older.maxWeight <= 0.0) return false
        val assistanceIncreased = newer.averageWeight > older.averageWeight * 1.03
        val repsDidNotImprove = newer.averageReps <= older.averageReps * 1.02
        return assistanceIncreased && repsDidNotImprove
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

    private fun resolveEffort(
        requested: SmartWorkoutEffort,
        focus: SmartWorkoutFocus,
        history: List<ExerciseHistoryEntry>,
        nowMillis: Long,
        zoneId: ZoneId
    ): EffortResolution {
        val targetMuscles = targetMusclesForFocus(focus)
        val lastTrained = lastTrainedByMuscle(history)
        val recentlyTrainedFraction = if (targetMuscles.isEmpty()) {
            0.0
        } else {
            targetMuscles.count { muscle ->
                val timestamp = lastTrained[muscle] ?: return@count false
                daysBetween(timestamp, nowMillis, zoneId) <= 1
            }.toDouble() / targetMuscles.size.toDouble()
        }
        val distinctSessionCount = history.asSequence().map { it.sessionId }.distinct().take(2).count()
        val daysSinceAnySession = history.maxOfOrNull { it.sessionDate }
            ?.let { daysBetween(it, nowMillis, zoneId) }

        return when (requested) {
            SmartWorkoutEffort.Auto -> if (recentlyTrainedFraction >= RecoveryMuscleFraction) {
                EffortResolution(
                    applied = SmartWorkoutEffort.Recovery,
                    adjustment = SmartWorkoutEffortAdjustment.AutoRecovery
                )
            } else {
                EffortResolution(applied = SmartWorkoutEffort.Standard)
            }
            SmartWorkoutEffort.Recovery -> EffortResolution(applied = SmartWorkoutEffort.Recovery)
            SmartWorkoutEffort.Standard -> EffortResolution(applied = SmartWorkoutEffort.Standard)
            SmartWorkoutEffort.Hard -> when {
                distinctSessionCount < 2 -> EffortResolution(
                    applied = SmartWorkoutEffort.Standard,
                    adjustment = SmartWorkoutEffortAdjustment.HardInsufficientHistory
                )
                daysSinceAnySession != null && daysSinceAnySession >= ComebackBreakDays -> EffortResolution(
                    applied = SmartWorkoutEffort.Standard,
                    adjustment = SmartWorkoutEffortAdjustment.HardRecentBreak
                )
                recentlyTrainedFraction >= RecoveryMuscleFraction -> EffortResolution(
                    applied = SmartWorkoutEffort.Standard,
                    adjustment = SmartWorkoutEffortAdjustment.HardMusclesRecovering
                )
                else -> EffortResolution(applied = SmartWorkoutEffort.Hard)
            }
        }
    }

    private fun chooseWorkoutFocus(
        history: List<ExerciseHistoryEntry>,
        trainingProfile: TrainingProfile,
        nowMillis: Long,
        zoneId: ZoneId
    ): SmartWorkoutFocus {
        if (trainingProfile.workoutsPerWeek.coerceIn(2, 6) <= 2) {
            return SmartWorkoutFocus.FullBody
        }
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
        val normalized = name.normalizedExerciseName()
        val identityKey = definition?.let { "catalog:${it.key}" } ?: "custom:$normalized"
        if (definition != null) {
            val programming = builtInProgrammingByKey.getValue(definition.key)
            return ExerciseAnalysis(
                identityKey = identityKey,
                category = programming.category,
                muscles = definition.muscleIds,
                patterns = programming.patterns,
                role = programming.role,
                loadMode = programming.loadMode
            )
        }
        val muscles = linkedSetOf<String>()
        val patterns = linkedSetOf<MovementPattern>()

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

        val classificationMuscles = muscles
        val lowerCount = classificationMuscles.count { it in lowerMuscles }
        val pushCount = classificationMuscles.count { it in pushMuscles }
        val pullCount = classificationMuscles.count { it in pullMuscles }
        val category = when {
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
            patterns = patterns.ifEmpty { linkedSetOf(MovementPattern.Accessory) },
            role = if (patterns.any { it in compoundMovementPatterns }) {
                ExerciseRole.Secondary
            } else {
                ExerciseRole.Isolation
            },
            loadMode = ExerciseLoadMode.Standard
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
        targetWorkingSetBudget: Int,
        history: List<ExerciseHistoryEntry>,
        nowMillis: Long,
        zoneId: ZoneId,
        trainingProfile: TrainingProfile,
        effort: SmartWorkoutEffort,
        manualMuscleMappings: Map<String, List<MuscleContribution>>,
        weeklyTargets: Map<String, Double>,
        completedWeeklySets: Map<String, Double>
    ): List<ExerciseCandidate> {
        val selected = mutableListOf<ExerciseCandidate>()
        val coveredMuscles = mutableSetOf<String>()
        val lastTrainedByMuscle = lastTrainedByMuscle(history)
        val projectedWeeklySets = completedWeeklySets.toMutableMap()
        var plannedWorkingSets = 0
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
        fun volumeScore(candidate: ExerciseCandidate): Double = weeklyVolumeScore(
            candidate = candidate,
            projectedWeeklySets = projectedWeeklySets,
            weeklyTargets = weeklyTargets,
            plannedSets = setBudget(
                trainingProfile = trainingProfile,
                analysis = candidate.analysis,
                effort = effort,
                hardSetEligible = false
            ),
            manualMuscleMappings = manualMuscleMappings
        )
        fun plannedSets(candidate: ExerciseCandidate): Int = setBudget(
            trainingProfile = trainingProfile,
            analysis = candidate.analysis,
            effort = effort,
            hardSetEligible = false
        )
        fun hasUnfilledWeeklyTarget(candidate: ExerciseCandidate): Boolean {
            val contributions = safeMuscleContributions(candidate.exercise.name, manualMuscleMappings)
            if (contributions.isEmpty()) return true
            return contributions.any { contribution ->
                val target = weeklyTargets[contribution.muscleId] ?: return@any false
                (projectedWeeklySets[contribution.muscleId] ?: 0.0) < target
            }
        }
        fun fitsOptionalBudget(candidate: ExerciseCandidate): Boolean =
            plannedWorkingSets + plannedSets(candidate) <= targetWorkingSetBudget
        fun recordSelection(candidate: ExerciseCandidate) {
            val candidateSets = plannedSets(candidate)
            selected += candidate
            coveredMuscles += candidate.analysis.muscles
            plannedWorkingSets += candidateSets
            addProjectedWeeklySets(
                candidate = candidate,
                projectedWeeklySets = projectedWeeklySets,
                plannedSets = candidateSets,
                manualMuscleMappings = manualMuscleMappings
            )
            remaining.removeAll { it.exercise.id == candidate.exercise.id }
        }

        if (focus == SmartWorkoutFocus.Lower || focus == SmartWorkoutFocus.Legs) {
            selectRequiredPattern(
                remaining = remaining,
                patterns = preferredPatternsForVariant(focus, variant),
                volumeScore = ::volumeScore,
                onSelected = ::recordSelection
            )
            selectRequiredPattern(
                remaining = remaining,
                patterns = if (variant == SmartWorkoutVariant.A) {
                    setOf(MovementPattern.Hinge, MovementPattern.KneeFlexion)
                } else {
                    setOf(MovementPattern.Squat, MovementPattern.LegPress)
                },
                volumeScore = ::volumeScore,
                onSelected = ::recordSelection
            )
        }

        if (focus == SmartWorkoutFocus.Upper) {
            listOf(
                MovementPattern.HorizontalPress,
                MovementPattern.VerticalPress,
                MovementPattern.HorizontalPull,
                MovementPattern.VerticalPull
            ).forEach { requiredPattern ->
                selectRequiredPattern(
                    remaining = remaining,
                    patterns = setOf(requiredPattern),
                    volumeScore = ::volumeScore,
                    onSelected = ::recordSelection
                )
            }
        } else if (focus == SmartWorkoutFocus.Push) {
            listOf(MovementPattern.HorizontalPress, MovementPattern.VerticalPress).forEach { requiredPattern ->
                selectRequiredPattern(
                    remaining = remaining,
                    patterns = setOf(requiredPattern),
                    volumeScore = ::volumeScore,
                    onSelected = ::recordSelection
                )
            }
        } else if (focus == SmartWorkoutFocus.Pull) {
            listOf(MovementPattern.HorizontalPull, MovementPattern.VerticalPull).forEach { requiredPattern ->
                selectRequiredPattern(
                    remaining = remaining,
                    patterns = setOf(requiredPattern),
                    volumeScore = ::volumeScore,
                    onSelected = ::recordSelection
                )
            }
        }

        if (focus == SmartWorkoutFocus.FullBody) {
            val preferredPatterns = preferredPatternsForVariant(focus, variant)
            listOf(SmartWorkoutFocus.Push, SmartWorkoutFocus.Pull, SmartWorkoutFocus.Legs).forEach { requiredFocus ->
                val eligible = remaining
                    .filter { it.analysis.category == requiredFocus && it.analysis.isCompound }
                val preferred = eligible.filter { candidate ->
                    candidate.analysis.patterns.any { it in preferredPatterns }
                }
                val best = preferred.ifEmpty { eligible }
                    .sortedWith(
                        compareByDescending<ExerciseCandidate> { candidate ->
                            candidate.score + candidate.analysis.selectionRolePriority() + volumeScore(candidate)
                        }.thenBy { it.analysis.identityKey }
                            .thenBy { it.exercise.id }
                    )
                    .firstOrNull()
                    ?: return@forEach
                recordSelection(best)
            }
        }

        // Reserve one trunk slot, but choose it after the working movements. This keeps
        // compounds first and lets the trunk chooser avoid hyperextensions after a hinge.
        val hasTrunkCandidate = candidates.any { it.analysis.isTrunkExercise() }
        remaining.removeAll { it.analysis.isTrunkExercise() }
        val nonTrunkTarget = if (hasTrunkCandidate) {
            (targetExerciseCount - 1).coerceAtLeast(0)
        } else {
            targetExerciseCount
        }

        while (selected.size < nonTrunkTarget && remaining.isNotEmpty()) {
            val best = remaining
                .filter(::hasUnfilledWeeklyTarget)
                .filter(::fitsOptionalBudget)
                .sortedWith(
                compareByDescending<ExerciseCandidate> { candidate ->
                    balancedScore(
                        candidate = candidate,
                        selected = selected,
                        coveredMuscles = coveredMuscles,
                        targetMuscles = targetMuscles,
                        lastTrainedByMuscle = lastTrainedByMuscle,
                        nowMillis = nowMillis,
                        zoneId = zoneId
                    )
                        + volumeScore(candidate)
                }.thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
                ).firstOrNull() ?: break
            recordSelection(best)
        }

        if (selected.size < targetExerciseCount && hasTrunkCandidate) {
            selectTrunkExercise(
                candidates = candidates,
                selected = selected,
                history = history,
                variant = variant,
                nowMillis = nowMillis,
                volumeScore = ::volumeScore,
                onSelected = ::recordSelection
            )
        }

        return selected
            .take(targetExerciseCount)
            .sortedWith(
                compareBy<ExerciseCandidate> { it.analysis.planOrderPriority() }
                    .thenByDescending { it.score }
                    .thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            )
    }

    private fun selectRequiredPattern(
        remaining: MutableList<ExerciseCandidate>,
        patterns: Set<MovementPattern>,
        volumeScore: (ExerciseCandidate) -> Double,
        onSelected: (ExerciseCandidate) -> Unit
    ) {
        val best = remaining
            .filter { candidate ->
                !candidate.analysis.isTrunkExercise() &&
                    candidate.analysis.patterns.any { it in patterns }
            }
            .sortedWith(
                compareByDescending<ExerciseCandidate> { candidate ->
                    candidate.score + candidate.analysis.patterns.count { it in patterns } * 35.0 +
                        volumeScore(candidate) +
                        candidate.analysis.selectionRolePriority()
                }.thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            )
            .firstOrNull()
            ?: return

        onSelected(best)
    }

    private fun selectTrunkExercise(
        candidates: List<ExerciseCandidate>,
        selected: MutableList<ExerciseCandidate>,
        history: List<ExerciseHistoryEntry>,
        variant: SmartWorkoutVariant,
        nowMillis: Long,
        volumeScore: (ExerciseCandidate) -> Double,
        onSelected: (ExerciseCandidate) -> Unit
    ) {
        val lastPerformedByKind = history
            .mapNotNull { entry ->
                analyzeExercise(entry.exerciseName).trunkKind()?.let { kind -> kind to entry.sessionDate }
            }
            .groupBy(keySelector = { it.first }, valueTransform = { it.second })
            .mapValues { (_, dates) -> dates.max() }
        val coreLastPerformed = lastPerformedByKind[TrunkKind.Core] ?: Long.MIN_VALUE
        val hyperLastPerformed = lastPerformedByKind[TrunkKind.Hyperextension] ?: Long.MIN_VALUE
        val preferredKind = when {
            hyperLastPerformed < coreLastPerformed -> TrunkKind.Hyperextension
            coreLastPerformed < hyperLastPerformed -> TrunkKind.Core
            variant == SmartWorkoutVariant.B -> TrunkKind.Hyperextension
            else -> TrunkKind.Core
        }
        val selectedContainsHinge = selected.any { candidate ->
            MovementPattern.Hinge in candidate.analysis.patterns
        }
        val recentHyperSessionCount = history.asSequence()
            .filter { entry -> entry.sessionDate in (nowMillis - WEEKLY_VOLUME_WINDOW_MILLIS)..nowMillis }
            .filter { entry -> analyzeExercise(entry.exerciseName).trunkKind() == TrunkKind.Hyperextension }
            .map { it.sessionId }
            .distinct()
            .take(MaxWeeklyHyperextensions)
            .count()
        val best = candidates
            .asSequence()
            .filter { it.analysis.isTrunkExercise() }
            .filterNot { candidate -> selected.any { it.exercise.id == candidate.exercise.id } }
            .filterNot { candidate ->
                candidate.analysis.trunkKind() == TrunkKind.Hyperextension &&
                    (selectedContainsHinge || recentHyperSessionCount >= MaxWeeklyHyperextensions)
            }
            .sortedWith(
                compareByDescending<ExerciseCandidate> { it.analysis.trunkKind() == preferredKind }
                    .thenByDescending(volumeScore)
                    .thenByDescending { it.score }
                    .thenBy { it.analysis.identityKey }
                    .thenBy { it.exercise.id }
            )
            .firstOrNull()
            ?: return
        onSelected(best)
    }

    private fun balancedScore(
        candidate: ExerciseCandidate,
        selected: List<ExerciseCandidate>,
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
        val duplicateCompoundPatternPenalty = if (candidate.analysis.isCompound) {
            selected.sumOf { selectedCandidate ->
                candidate.analysis.patterns.count { pattern ->
                    pattern in compoundMovementPatterns && pattern in selectedCandidate.analysis.patterns
                } * 30.0
            }
        } else {
            0.0
        }
        val sameCategoryPenalty = selected.count {
            it.analysis.category == candidate.analysis.category
        } * 12.0

        return candidate.score + newTargetMuscles * 24.0 + targetOverlap * 4.0 - fatiguePenalty -
            tooMuchSameCategoryPenalty - duplicateCompoundPatternPenalty - sameCategoryPenalty
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
        val averageWeight: Double = sets.map { it.weight }.average()
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

    private data class AlternativeCandidate(
        val exercise: ExerciseEntity,
        val analysis: ExerciseAnalysis,
        val score: Double,
        val reasons: List<SmartWorkoutAlternativeReason>
    )

    private data class EffortResolution(
        val applied: SmartWorkoutEffort,
        val adjustment: SmartWorkoutEffortAdjustment? = null
    )

    private data class ExerciseAnalysis(
        val identityKey: String,
        val category: SmartWorkoutFocus,
        val muscles: Set<String>,
        val patterns: Set<MovementPattern>,
        val role: ExerciseRole,
        val loadMode: ExerciseLoadMode
    ) {
        val isCompound: Boolean
            get() = role == ExerciseRole.Primary || role == ExerciseRole.Secondary

        fun trunkKind(): TrunkKind? = when {
            identityKey == "catalog:hyperextension" ||
                identityKey == "catalog:side_hyperextension" -> TrunkKind.Hyperextension
            role == ExerciseRole.Core -> TrunkKind.Core
            else -> null
        }

        fun isTrunkExercise(): Boolean = trunkKind() != null

        fun selectionRolePriority(): Double = when (role) {
            ExerciseRole.Primary -> 28.0
            ExerciseRole.Secondary -> 14.0
            ExerciseRole.Isolation,
            ExerciseRole.Core,
            ExerciseRole.Warmup -> 0.0
        }

        fun planOrderPriority(): Int = when {
            isTrunkExercise() -> 4
            role == ExerciseRole.Primary -> 0
            role == ExerciseRole.Secondary -> 1
            role == ExerciseRole.Isolation -> 2
            else -> 3
        }
    }

    private enum class TrunkKind {
        Core,
        Hyperextension
    }

    private data class BuiltInProgramming(
        val category: SmartWorkoutFocus,
        val role: ExerciseRole,
        val loadMode: ExerciseLoadMode,
        val patterns: Set<MovementPattern>
    )

    private enum class ExerciseRole {
        Primary,
        Secondary,
        Isolation,
        Core,
        Warmup
    }

    private enum class ExerciseLoadMode {
        Standard,
        Bodyweight,
        Assistance,
        None
    }

    private enum class ExerciseEquipment {
        Barbell,
        Dumbbell,
        Cable,
        Machine,
        Bodyweight,
        Band,
        Other
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

    private fun programming(
        category: SmartWorkoutFocus,
        role: ExerciseRole,
        loadMode: ExerciseLoadMode = ExerciseLoadMode.Standard,
        vararg patterns: MovementPattern
    ) = BuiltInProgramming(category, role, loadMode, patterns.toSet())

    // Stable built-ins use reviewed programming metadata. Custom exercise names are handled by
    // the bounded heuristic fallback in analyzeExercise and cannot inject trusted role/load flags.
    private val builtInProgrammingByKey = mapOf(
        "bench_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.HorizontalPress)),
        "dumbbell_bench_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.HorizontalPress)),
        "incline_dumbbell_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.HorizontalPress)),
        "incline_bench_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.HorizontalPress)),
        "chest_fly_machine" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "push_up" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, ExerciseLoadMode.Bodyweight, MovementPattern.HorizontalPress),
        "dips" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, ExerciseLoadMode.Bodyweight, MovementPattern.HorizontalPress),
        "assisted_dip" to programming(SmartWorkoutFocus.Push, ExerciseRole.Secondary, ExerciseLoadMode.Assistance, MovementPattern.HorizontalPress),
        "pull_up" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, ExerciseLoadMode.Bodyweight, MovementPattern.VerticalPull),
        "assisted_pull_up" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, ExerciseLoadMode.Assistance, MovementPattern.VerticalPull),
        "band_assisted_pull_up" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, ExerciseLoadMode.Bodyweight, MovementPattern.VerticalPull),
        "lat_pulldown" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.VerticalPull)),
        "straight_arm_pulldown" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "barbell_row" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.HorizontalPull)),
        "seated_cable_row" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.HorizontalPull)),
        "plate_loaded_row" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.HorizontalPull)),
        "face_pull" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "squat" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.Squat)),
        "leg_press" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.LegPress)),
        "bulgarian_split_squat" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.Squat)),
        "lunge" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.Squat)),
        "romanian_deadlift" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.Hinge)),
        "deadlift" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.Hinge)),
        "hip_thrust" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Secondary, patterns = arrayOf(MovementPattern.Hinge)),
        "leg_extension" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.KneeExtension)),
        "lying_leg_curl" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.KneeFlexion)),
        "seated_leg_curl" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.KneeFlexion)),
        "hip_adduction" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "hip_abduction" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "calf_raise" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Calf)),
        "shoulder_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Primary, patterns = arrayOf(MovementPattern.VerticalPress)),
        "lateral_raise" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "machine_lateral_raise" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "rear_delt_fly" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "upright_row" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "biceps_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "barbell_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "seated_dumbbell_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "hammer_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "cable_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "preacher_curl" to programming(SmartWorkoutFocus.Pull, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "triceps_pushdown" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "v_bar_pushdown" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "overhead_dumbbell_triceps_extension" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "french_press" to programming(SmartWorkoutFocus.Push, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Accessory)),
        "hyperextension" to programming(SmartWorkoutFocus.Legs, ExerciseRole.Isolation, patterns = arrayOf(MovementPattern.Hinge)),
        "side_hyperextension" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, patterns = arrayOf(MovementPattern.Core)),
        "plank" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, ExerciseLoadMode.Bodyweight, MovementPattern.Core),
        "weighted_crunch" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, patterns = arrayOf(MovementPattern.Core)),
        "hanging_leg_raise" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, ExerciseLoadMode.Bodyweight, MovementPattern.Core),
        "plate_twist" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, patterns = arrayOf(MovementPattern.Core)),
        "weighted_side_bend" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Core, patterns = arrayOf(MovementPattern.Core)),
        "warm_up" to programming(SmartWorkoutFocus.FullBody, ExerciseRole.Warmup, ExerciseLoadMode.None, MovementPattern.Accessory)
    )

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
    private val majorMuscles = setOf(
        "chest", "shoulders", "lats", "upperBack", "quads", "hamstrings", "glutes"
    )
    private val secondaryMuscles = setOf("biceps", "triceps", "calves", "abs")
    private const val FavoriteExerciseScore = 5.0
    private const val AlternativeEquipmentScore = 8.0
    private const val AlternativeFamiliarityScore = 3.0
    private const val MinimumAlternativeMuscleOverlap = 0.35
    private const val MaxAlternativeCount = 6
    private const val MaxHardCompoundExercises = 2
    private const val MaxWeeklyHyperextensions = 2
    private const val RecoveryMuscleFraction = 0.5
    private const val MIN_SESSION_WORKING_SETS = 12
    private const val WEEKLY_VOLUME_WINDOW_MILLIS = 7L * 24L * 60L * 60L * 1_000L
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
