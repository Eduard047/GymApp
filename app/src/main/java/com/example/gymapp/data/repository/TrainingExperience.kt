package com.example.gymapp.data.repository

import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import org.json.JSONArray
import org.json.JSONObject

enum class FirstWorkoutEffort {
    Recovery,
    Standard,
    Hard
}

enum class WorkoutFeedback(val wireValue: String) {
    Easy("easy"),
    Normal("normal"),
    Hard("hard");

    companion object {
        fun fromWireValue(value: String): WorkoutFeedback? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

data class WorkoutFeedbackRecord(
    val sessionId: Long,
    val feedback: WorkoutFeedback,
    val sessionStartedAtMillis: Long
)

data class SmartCoachFeedback(
    val sessionId: Long,
    val sessionDateMillis: Long,
    val feedback: WorkoutFeedback
)

internal fun trainingProfileForActivation(
    goal: TrainingGoal,
    workoutsPerWeek: Int
): TrainingProfile {
    require(workoutsPerWeek in 2..6) { "Training frequency is outside the supported bounds." }
    return TrainingProfile(
        split = when {
            workoutsPerWeek <= 3 -> TrainingSplit.FullBody
            workoutsPerWeek == 4 -> TrainingSplit.UpperLower
            else -> TrainingSplit.PushPullLegs
        },
        workoutsPerWeek = workoutsPerWeek,
        goal = goal,
        calorieMode = when (goal) {
            TrainingGoal.AestheticFatLoss -> CalorieMode.Deficit
            TrainingGoal.MuscleGain -> CalorieMode.Surplus
            TrainingGoal.Strength,
            TrainingGoal.Balanced -> CalorieMode.Maintenance
        }
    )
}

internal fun FirstWorkoutEffort.toSmartWorkoutEffort(): SmartWorkoutEffort = when (this) {
    FirstWorkoutEffort.Recovery -> SmartWorkoutEffort.Recovery
    FirstWorkoutEffort.Standard -> SmartWorkoutEffort.Standard
    FirstWorkoutEffort.Hard -> SmartWorkoutEffort.Hard
}

/**
 * Applies the two account-local activation writes only after the launch payload has
 * been validated as the exact non-empty plan that will be opened. Failed commits
 * are restored because SharedPreferences may update its in-memory snapshot even
 * when its synchronous disk commit reports false.
 */
internal object FirstWorkoutActivationCommitter {
    fun commit(
        candidateToken: String?,
        targetProfile: TrainingProfile,
        previousProfile: TrainingProfile,
        previousDismissed: Boolean,
        isExactPlan: (String) -> Boolean,
        persistProfile: (TrainingProfile) -> Boolean,
        persistDismissed: (Boolean) -> Boolean,
        acknowledgeHandoff: (String) -> Boolean = { true },
        restoreProfile: (TrainingProfile) -> Boolean = persistProfile,
        restoreDismissed: (Boolean) -> Boolean = persistDismissed
    ): String? {
        val token = candidateToken
            ?.takeIf { it.isNotEmpty() && it.length <= SmartWorkoutLaunchPlanCodec.MAX_ENCODED_LENGTH }
            ?: return null
        if (!runCatching { isExactPlan(token) }.getOrDefault(false)) return null

        fun restorePreviousState() {
            // Both restores are attempted even if one fails so neither state is
            // intentionally left at the uncommitted activation selection.
            restoreProfile(previousProfile)
            restoreDismissed(previousDismissed)
        }

        if (!persistProfile(targetProfile)) {
            restorePreviousState()
            return null
        }
        if (!persistDismissed(true)) {
            restorePreviousState()
            return null
        }
        if (!runCatching { acknowledgeHandoff(token) }.getOrDefault(false)) {
            restorePreviousState()
            return null
        }
        return token
    }
}

/**
 * Claims a validated recommended launch before any Room mutation. The claim is intentionally not
 * rolled back when Room rejects or fails: the caller must refresh Today and issue a fresh bounded
 * token, so a crash or replay can never start the same launch twice.
 */
internal object RecommendedWorkoutStartCommitter {
    suspend fun start(
        plan: SmartWorkoutLaunchPlan,
        claimAndPersist: () -> Boolean,
        startActiveWorkout: suspend (List<WorkoutExerciseDraft>) -> StartActiveWorkoutResult
    ): Boolean {
        val drafts = runCatching { materializeSmartWorkoutDrafts(plan) }.getOrNull()
            ?: return false
        if (!runCatching(claimAndPersist).getOrDefault(false)) return false
        return startActiveWorkout(drafts) == StartActiveWorkoutResult.Started
    }
}

internal object FirstWorkoutActivationDirectStarter {
    suspend fun start(
        plan: SmartWorkoutLaunchPlan,
        token: String,
        previousProfile: TrainingProfile,
        previousDismissed: Boolean,
        claimAndPersist: () -> Boolean,
        persistProfile: (TrainingProfile) -> Boolean,
        persistDismissed: (Boolean) -> Boolean,
        restoreProfile: (TrainingProfile) -> Boolean,
        restoreDismissed: (Boolean) -> Boolean,
        startActiveWorkout: suspend (List<WorkoutExerciseDraft>) -> StartActiveWorkoutResult
    ): Boolean {
        if (plan.origin != SmartWorkoutLaunchOrigin.Activation || token.isEmpty()) return false
        val drafts = runCatching { materializeSmartWorkoutDrafts(plan) }.getOrNull()
            ?: return false
        if (!runCatching(claimAndPersist).getOrDefault(false)) return false

        fun restorePreviousState() {
            restoreProfile(previousProfile)
            restoreDismissed(previousDismissed)
        }

        if (!persistProfile(plan.trainingProfile)) {
            restorePreviousState()
            return false
        }
        if (!persistDismissed(true)) {
            restorePreviousState()
            return false
        }
        val result = try {
            startActiveWorkout(drafts)
        } catch (cancellation: kotlinx.coroutines.CancellationException) {
            restorePreviousState()
            throw cancellation
        } catch (_: Throwable) {
            restorePreviousState()
            return false
        }
        if (result != StartActiveWorkoutResult.Started) {
            restorePreviousState()
            return false
        }
        return true
    }
}

internal data class PendingFirstWorkoutActivation(
    val token: String,
    val targetProfile: TrainingProfile,
    val previousProfile: TrainingProfile,
    val previousDismissed: Boolean
)

/** A single SavedStateHandle value keeps activation preparation process-restorable and atomic. */
internal object PendingFirstWorkoutActivationCodec {
    private const val MAX_BYTES = SmartWorkoutLaunchPlanCodec.MAX_ENCODED_LENGTH + 1_024

    fun encode(value: PendingFirstWorkoutActivation): String {
        require(SmartWorkoutLaunchPlanCodec.isTokenShapeValid(value.token))
        val raw = JSONObject()
            .put("v", 1)
            .put("t", value.token)
            .put("n", profileArray(value.targetProfile))
            .put("o", profileArray(value.previousProfile))
            .put("d", value.previousDismissed)
            .toString()
        require(raw.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
        return raw
    }

    fun decode(raw: String?): PendingFirstWorkoutActivation? {
        val candidate = raw ?: return null
        if (candidate.toByteArray(Charsets.UTF_8).size > MAX_BYTES) return null
        return runCatching {
            WorkoutDataLimits.requireSafeJsonEnvelope(candidate, MAX_BYTES)
            val root = JSONObject(candidate)
            require(root.keys().asSequence().toSet() == setOf("v", "t", "n", "o", "d"))
            require((root.opt("v") as? Number)?.toDouble() == 1.0)
            val token = root.opt("t") as? String ?: error("Pending launch token is invalid.")
            require(SmartWorkoutLaunchPlanCodec.isTokenShapeValid(token))
            PendingFirstWorkoutActivation(
                token = token,
                targetProfile = parseProfile(root.optJSONArray("n")),
                previousProfile = parseProfile(root.optJSONArray("o")),
                previousDismissed = root.opt("d") as? Boolean
                    ?: error("Pending dismissal state is invalid.")
            )
        }.getOrNull()
    }

    private fun profileArray(profile: TrainingProfile): JSONArray {
        require(profile.workoutsPerWeek in 2..6)
        return JSONArray()
            .put(profile.split.name)
            .put(profile.workoutsPerWeek)
            .put(profile.goal.name)
            .put(profile.calorieMode.name)
    }

    private fun parseProfile(raw: JSONArray?): TrainingProfile {
        val profile = raw ?: error("Pending profile is invalid.")
        require(profile.length() == 4)
        val workoutsPerWeek = (profile.opt(1) as? Number)?.toDouble()
            ?.takeIf { it.isFinite() && it % 1.0 == 0.0 }
            ?.toInt()
            ?: error("Pending frequency is invalid.")
        require(workoutsPerWeek in 2..6)
        return TrainingProfile(
            split = enumValue(profile.opt(0)),
            workoutsPerWeek = workoutsPerWeek,
            goal = enumValue(profile.opt(2)),
            calorieMode = enumValue(profile.opt(3))
        )
    }

    private inline fun <reified T : Enum<T>> enumValue(raw: Any?): T {
        val value = raw as? String ?: error("Pending enum is invalid.")
        return enumValues<T>().firstOrNull { it.name == value }
            ?: error("Pending enum is invalid.")
    }
}

/**
 * Navigation acknowledgement deliberately happens before activation persistence.
 * A thrown route handoff cancels only the prepared token; profile and dismissal
 * are still untouched at that point.
 */
internal fun handOffFirstWorkoutNavigation(
    token: String?,
    open: (String) -> Unit,
    cancel: (String) -> Unit
): Boolean {
    val candidate = token?.takeIf(SmartWorkoutLaunchPlanCodec::isTokenShapeValid)
        ?: return false
    return runCatching {
        open(candidate)
        true
    }.getOrElse {
        cancel(candidate)
        false
    }
}

internal fun handOffSkippedFirstWorkoutNavigation(
    previousDismissed: Boolean,
    persistDismissed: (Boolean) -> Boolean,
    open: () -> Unit
): Boolean {
    if (!persistDismissed(true)) return false
    return runCatching {
        open()
        true
    }.getOrElse {
        persistDismissed(previousDismissed)
        false
    }
}

enum class WeeklyTrainingDecision {
    Train,
    Recovery,
    Rest
}

data class WeeklyTrainingRhythm(
    val completedTrainingDays: Int,
    val targetTrainingDays: Int,
    val decision: WeeklyTrainingDecision
)

internal object WeeklyTrainingRhythmCalculator {
    fun calculate(
        sessionTimestamps: List<Long>,
        targetTrainingDays: Int,
        recoveryRecommended: Boolean,
        nowMillis: Long,
        zoneId: ZoneId
    ): WeeklyTrainingRhythm {
        require(targetTrainingDays in 2..6) { "Weekly target is outside the supported bounds." }
        val today = localDate(nowMillis, zoneId)
        val weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val completedDays = sessionTimestamps.asSequence()
            .take(WorkoutDataLimits.MAX_SESSIONS)
            .mapNotNull { timestamp ->
                if (!WorkoutDataLimits.isValidTimestamp(timestamp) || timestamp > nowMillis) {
                    return@mapNotNull null
                }
                runCatching { localDate(timestamp, zoneId) }.getOrNull()
            }
            .filter { date -> date in weekStart..today }
            .distinct()
            .count()

        return WeeklyTrainingRhythm(
            completedTrainingDays = completedDays,
            targetTrainingDays = targetTrainingDays,
            decision = when {
                completedDays >= targetTrainingDays -> WeeklyTrainingDecision.Rest
                recoveryRecommended -> WeeklyTrainingDecision.Recovery
                else -> WeeklyTrainingDecision.Train
            }
        )
    }

    private fun localDate(timestamp: Long, zoneId: ZoneId): LocalDate =
        Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
}
