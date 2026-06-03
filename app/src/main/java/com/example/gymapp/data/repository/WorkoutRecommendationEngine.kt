package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
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

        val focus = chooseWorkoutFocus(history, trainingProfile, nowMillis, zoneId)
        val targetExerciseCount = when (focus) {
            SmartWorkoutFocus.Upper -> 5
            SmartWorkoutFocus.Lower -> 5
            SmartWorkoutFocus.Push -> 5
            SmartWorkoutFocus.Pull -> 5
            SmartWorkoutFocus.Legs -> 5
            SmartWorkoutFocus.FullBody -> 6
        }

        val historyByExerciseId = history.groupBy { it.exerciseId }
        val recentSessionIds = recentSessionIds(history, limit = 3)
        val targetMuscles = targetMusclesForFocus(focus)
        val candidates = exercises.map { exercise ->
            val exerciseHistory = historyByExerciseId[exercise.id].orEmpty()
            val analysis = analyzeExercise(exercise.name)
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

            ExerciseCandidate(
                exercise = exercise,
                analysis = analysis,
                score = focusScore + muscleMatchScore + noveltyScore + dueScore + confidenceScore -
                    recentExercisePenalty - sameWeekExercisePenalty
            )
        }

        val selected = selectBalancedExercises(
            candidates = candidates,
            focus = focus,
            targetMuscles = targetMuscles,
            targetExerciseCount = targetExerciseCount,
            history = history,
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
        val latestSession = sessions.firstOrNull()?.entries
            ?: return SmartWorkoutFocus.Upper
        val latestFocus = dominantFocus(latestSession)

        return when (trainingProfile.split) {
            TrainingSplit.UpperLower -> {
                val thisWeekSessions = sessions.filter { session ->
                    daysBetween(session.date, nowMillis, zoneId) <= 6
                }
                val latestWeekFocus = thisWeekSessions.firstOrNull()?.entries?.let(::dominantFocus) ?: latestFocus
                when {
                    latestWeekFocus.isLowerDay() -> SmartWorkoutFocus.Upper
                    latestWeekFocus.isUpperDay() -> SmartWorkoutFocus.Lower
                    else -> {
                        val upperCount = thisWeekSessions.count { dominantFocus(it.entries).isUpperDay() }
                        val lowerCount = thisWeekSessions.count { dominantFocus(it.entries).isLowerDay() }
                        if (lowerCount < upperCount) SmartWorkoutFocus.Lower else SmartWorkoutFocus.Upper
                    }
                }
            }
            TrainingSplit.PushPullLegs -> {
                when (latestFocus) {
                    SmartWorkoutFocus.Push -> SmartWorkoutFocus.Pull
                    SmartWorkoutFocus.Pull -> SmartWorkoutFocus.Legs
                    SmartWorkoutFocus.Legs,
                    SmartWorkoutFocus.Lower -> SmartWorkoutFocus.Push
                    SmartWorkoutFocus.Upper,
                    SmartWorkoutFocus.FullBody -> chooseMostNeglectedFocus(history)
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

    private fun analyzeExercise(name: String): ExerciseAnalysis {
        val normalized = name.normalizedExerciseName()
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

        val category = when {
            muscles.any { it in lowerMuscles } -> SmartWorkoutFocus.Legs
            muscles.any { it in pullMuscles } && muscles.none { it in pushMuscles } -> SmartWorkoutFocus.Pull
            muscles.any { it in pushMuscles } -> SmartWorkoutFocus.Push
            muscles.any { it in coreMuscles } -> SmartWorkoutFocus.FullBody
            else -> SmartWorkoutFocus.FullBody
        }

        return ExerciseAnalysis(
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

        if (focus == SmartWorkoutFocus.Lower || focus == SmartWorkoutFocus.Legs) {
            selectRequiredPattern(
                remaining = remaining,
                selected = selected,
                coveredMuscles = coveredMuscles,
                patterns = setOf(MovementPattern.Squat, MovementPattern.LegPress)
            )
            if (shouldPrioritizeHeavyLower(history)) {
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
                    .maxByOrNull { it.score }
                    ?: return@forEach
                selected += best
                coveredMuscles += best.analysis.muscles
                remaining.removeAll { it.exercise.id == best.exercise.id }
            }
        }

        while (selected.size < targetExerciseCount && remaining.isNotEmpty()) {
            val best = remaining.maxWithOrNull(
                compareBy<ExerciseCandidate> { candidate ->
                    balancedScore(
                        candidate = candidate,
                        coveredMuscles = coveredMuscles,
                        targetMuscles = targetMuscles,
                        lastTrainedByMuscle = lastTrainedByMuscle,
                        nowMillis = nowMillis,
                        zoneId = zoneId
                    )
                }.thenByDescending { it.exercise.name.lowercase() }
            ) ?: break
            selected += best
            coveredMuscles += best.analysis.muscles
            remaining.removeAll { it.exercise.id == best.exercise.id }
        }

        if (selected.size < targetExerciseCount) {
            selected += candidates
                .filter { candidate -> isExerciseEligibleForFocus(candidate.analysis, focus) }
                .filterNot { candidate -> selected.any { it.exercise.id == candidate.exercise.id } }
                .sortedWith(compareByDescending<ExerciseCandidate> { it.score }.thenBy { it.exercise.name.lowercase() })
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
            .maxByOrNull { candidate -> candidate.score + candidate.analysis.patterns.count { it in patterns } * 35.0 }
            ?: return

        selected += best
        coveredMuscles += best.analysis.muscles
        remaining.removeAll { it.exercise.id == best.exercise.id }
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
            .groupBy { it.sessionId }
            .values
            .sortedByDescending { entries -> entries.maxOf { it.sessionDate } }
            .take(limit)
            .map { entries -> entries.first().sessionId }
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
        val analysis: ExerciseAnalysis,
        val score: Double
    )

    private data class ExerciseAnalysis(
        val category: SmartWorkoutFocus,
        val muscles: Set<String>,
        val patterns: Set<MovementPattern>
    )

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

    private val upperFocuses = setOf(SmartWorkoutFocus.Upper, SmartWorkoutFocus.Push, SmartWorkoutFocus.Pull)
    private val lowerFocuses = setOf(SmartWorkoutFocus.Lower, SmartWorkoutFocus.Legs)
    private val pushMuscles = setOf("chest", "shoulders", "triceps")
    private val pullMuscles = setOf("lats", "upperBack", "biceps", "forearms")
    private val lowerMuscles = setOf("quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack")
    private val coreMuscles = setOf("abs", "obliques")
}

private fun String.normalizedExerciseName(): String {
    return lowercase(Locale.ROOT)
        .replace('ʼ', '\'')
        .replace('’', '\'')
        .replace(Regex("\\s+"), " ")
        .trim()
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
        .sortedByDescending { it.date }
}

private fun SmartWorkoutFocus.isUpperDay(): Boolean {
    return this == SmartWorkoutFocus.Upper || this == SmartWorkoutFocus.Push || this == SmartWorkoutFocus.Pull
}

private fun SmartWorkoutFocus.isLowerDay(): Boolean {
    return this == SmartWorkoutFocus.Lower || this == SmartWorkoutFocus.Legs
}
