package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject

internal enum class SmartWorkoutLaunchOrigin(val wireValue: String) {
    Activation("activation"),
    Recommended("recommended")
}

internal data class SmartWorkoutLaunchSet(
    val weight: Double?,
    val reps: Int
)

internal data class SmartWorkoutLaunchExercise(
    val exerciseId: Long,
    val sets: List<SmartWorkoutLaunchSet>,
    val isHardSlot: Boolean
)

internal data class SmartWorkoutLaunchPlan(
    val origin: SmartWorkoutLaunchOrigin,
    val launchId: String,
    val accountBinding: String,
    val createdAtMillis: Long,
    val stateFingerprint: String,
    val trainingProfile: TrainingProfile,
    val focus: SmartWorkoutFocus,
    val variant: SmartWorkoutVariant,
    val requestedEffort: SmartWorkoutEffort,
    val appliedEffort: SmartWorkoutEffort,
    val effortAdjustment: SmartWorkoutEffortAdjustment?,
    val exercises: List<SmartWorkoutLaunchExercise>
)

/**
 * Materializes the validated Smart Coach payload for the direct Start path.
 *
 * A missing load is the portable bodyweight/no-added-load value, not an incomplete set. Keep the
 * nullable wire field for backward compatibility, but never require a trip through the editor to
 * turn it into a persistable workout set.
 */
internal fun materializeSmartWorkoutDrafts(
    plan: SmartWorkoutLaunchPlan
): List<WorkoutExerciseDraft> {
    require(plan.exercises.size in 1..SMART_WORKOUT_MAX_EXERCISES)
    require(plan.exercises.map { it.exerciseId }.all { it > 0L })
    require(plan.exercises.map { it.exerciseId }.distinct().size == plan.exercises.size)
    var totalSets = 0
    return plan.exercises.map { exercise ->
        require(exercise.sets.size in
            SMART_WORKOUT_MIN_SETS_PER_EXERCISE..SMART_WORKOUT_MAX_SETS_PER_EXERCISE)
        totalSets += exercise.sets.size
        require(totalSets <= SMART_WORKOUT_MAX_TOTAL_SETS)
        WorkoutExerciseDraft(
            exerciseId = exercise.exerciseId,
            sets = exercise.sets.map { set ->
                val weight = set.weight ?: 0.0
                require(WorkoutDataLimits.isValidWeight(weight))
                require(WorkoutDataLimits.isValidReps(set.reps))
                WorkoutSetDraft(weight = weight, reps = set.reps)
            }
        )
    }
}

internal object SmartWorkoutLaunchPlanCodec {
    const val MAX_ENCODED_LENGTH = 12_000
    const val MAX_DECODED_BYTES = 9_000
    private val tokenPattern = Regex("^[A-Za-z0-9_-]{1,$MAX_ENCODED_LENGTH}$")
    private val bindingPattern = Regex("^[0-9a-f]{64}$")
    private val fingerprintPattern = Regex("^[0-9a-f]{64}$")
    private val launchIdPattern = Regex("^[0-9a-f]{32}$")

    internal fun isTokenShapeValid(encoded: String): Boolean = tokenPattern.matches(encoded)

    fun fromPlan(
        plan: SmartWorkoutPlan,
        profile: TrainingProfile,
        origin: SmartWorkoutLaunchOrigin,
        accountBinding: String,
        stateFingerprint: String,
        launchId: String = newLaunchId(),
        createdAtMillis: Long = System.currentTimeMillis()
    ): SmartWorkoutLaunchPlan = normalize(
        SmartWorkoutLaunchPlan(
            origin = origin,
            launchId = launchId,
            accountBinding = accountBinding,
            createdAtMillis = createdAtMillis,
            stateFingerprint = stateFingerprint,
            trainingProfile = profile,
            focus = plan.focus,
            variant = plan.variant,
            requestedEffort = plan.requestedEffort,
            appliedEffort = plan.appliedEffort,
            effortAdjustment = plan.effortAdjustment,
            exercises = plan.exercises.map { planned ->
                SmartWorkoutLaunchExercise(
                    exerciseId = planned.exercise.id,
                    sets = planned.recommendation.sets.map { set ->
                        SmartWorkoutLaunchSet(set.weight, set.reps)
                    },
                    isHardSlot = planned.recommendation.targetRir == 1..2
                )
            }
        )
    )

    fun encode(plan: SmartWorkoutLaunchPlan): String {
        val safe = normalize(plan)
        val profile = JSONArray()
            .put(safe.trainingProfile.split.name)
            .put(safe.trainingProfile.workoutsPerWeek)
            .put(safe.trainingProfile.goal.name)
            .put(safe.trainingProfile.calorieMode.name)
        val exercises = JSONArray()
        safe.exercises.forEach { exercise ->
            val sets = JSONArray()
            exercise.sets.forEach { set ->
                sets.put(JSONArray().put(set.weight ?: JSONObject.NULL).put(set.reps))
            }
            exercises.put(
                JSONArray()
                    .put(exercise.exerciseId)
                    .put(sets)
                    .put(exercise.isHardSlot)
            )
        }
        val raw = JSONObject()
            .put("v", 1)
            .put("m", safe.origin.wireValue)
            .put("i", safe.launchId)
            .put("b", safe.accountBinding)
            .put("t", safe.createdAtMillis)
            .put("s", safe.stateFingerprint)
            .put("p", profile)
            .put("f", safe.focus.name)
            .put("q", safe.variant.name)
            .put("r", safe.requestedEffort.name)
            .put("a", safe.appliedEffort.name)
            .put("j", safe.effortAdjustment?.name.orEmpty())
            .put("e", exercises)
            .toString()
        val bytes = raw.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_DECODED_BYTES) { "Smart workout launch is too large." }
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes).also { encoded ->
            require(encoded.length <= MAX_ENCODED_LENGTH) { "Smart workout launch is too large." }
        }
    }

    fun decode(
        encoded: String,
        expectedAccountBinding: String,
        expectedTrainingProfile: TrainingProfile,
        expectedStateFingerprint: String,
        nowMillis: Long = System.currentTimeMillis()
    ): SmartWorkoutLaunchPlan {
        require(bindingPattern.matches(expectedAccountBinding)) { "Account binding is invalid." }
        require(fingerprintPattern.matches(expectedStateFingerprint)) {
            "Launch state fingerprint is invalid."
        }
        require(WorkoutDataLimits.isValidTimestamp(nowMillis)) { "Current time is invalid." }
        require(tokenPattern.matches(encoded)) { "Smart workout launch encoding is invalid." }
        val bytes = runCatching { Base64.getUrlDecoder().decode(encoded) }
            .getOrElse { throw IllegalArgumentException("Smart workout launch encoding is invalid.") }
        require(bytes.size <= MAX_DECODED_BYTES)
        require(Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) == encoded)
        val raw = bytes.toString(Charsets.UTF_8)
        require(raw.toByteArray(Charsets.UTF_8).contentEquals(bytes))
        WorkoutDataLimits.requireSafeJsonEnvelope(raw, MAX_DECODED_BYTES)
        val root = runCatching { JSONObject(raw) }
            .getOrElse { throw IllegalArgumentException("Smart workout launch JSON is invalid.") }
        require(
            root.keys().asSequence().toSet() == setOf(
                "v", "m", "i", "b", "t", "s", "p", "f", "q", "r", "a", "j", "e"
            ) &&
                (root.opt("v") as? Number)?.toDouble() == 1.0
        )
        val binding = root.opt("b") as? String ?: error("Account binding is invalid.")
        require(binding == expectedAccountBinding)
        val stateFingerprint = root.opt("s") as? String
            ?: error("Launch state fingerprint is invalid.")
        require(stateFingerprint == expectedStateFingerprint) {
            "Workout catalog or history has changed."
        }
        val createdAtMillis = exactLong(root.opt("t"))
        require(WorkoutDataLimits.isValidTimestamp(createdAtMillis)) {
            "Launch timestamp is invalid."
        }
        require(createdAtMillis <= nowMillis + MAX_FUTURE_SKEW_MILLIS) {
            "Smart workout launch is from the future."
        }
        require(createdAtMillis >= nowMillis - MAX_LAUNCH_AGE_MILLIS) {
            "Smart workout launch has expired."
        }
        val originWire = root.opt("m") as? String ?: error("Launch origin is invalid.")
        val origin = SmartWorkoutLaunchOrigin.entries.firstOrNull { it.wireValue == originWire }
            ?: error("Launch origin is invalid.")
        val launchId = root.opt("i") as? String ?: error("Launch ID is invalid.")
        val rawProfile = root.optJSONArray("p") ?: error("Training profile is invalid.")
        require(rawProfile.length() == 4)
        val profile = TrainingProfile(
            split = enumValue(rawProfile.opt(0)),
            workoutsPerWeek = exactInt(rawProfile.opt(1)),
            goal = enumValue(rawProfile.opt(2)),
            calorieMode = enumValue(rawProfile.opt(3))
        )
        require(profile == expectedTrainingProfile) { "Training profile has changed." }
        val rawExercises = root.optJSONArray("e") ?: error("Launch exercises are invalid.")
        val exercises = List(rawExercises.length()) { index ->
            val rawExercise = rawExercises.optJSONArray(index) ?: error("Launch exercise is invalid.")
            require(rawExercise.length() == 3)
            val exerciseId = exactLong(rawExercise.opt(0))
            val rawSets = rawExercise.optJSONArray(1) ?: error("Launch sets are invalid.")
            val hardSlot = rawExercise.opt(2) as? Boolean ?: error("Launch effort is invalid.")
            SmartWorkoutLaunchExercise(
                exerciseId = exerciseId,
                sets = List(rawSets.length()) { setIndex ->
                    val rawSet = rawSets.optJSONArray(setIndex) ?: error("Launch set is invalid.")
                    require(rawSet.length() == 2)
                    val rawWeight = rawSet.opt(0)
                    SmartWorkoutLaunchSet(
                        weight = if (rawWeight == null || rawWeight == JSONObject.NULL) {
                            null
                        } else {
                            (rawWeight as? Number)?.toDouble() ?: error("Launch weight is invalid.")
                        },
                        reps = exactInt(rawSet.opt(1))
                    )
                },
                isHardSlot = hardSlot
            )
        }
        return normalize(
            SmartWorkoutLaunchPlan(
                origin = origin,
                launchId = launchId,
                accountBinding = binding,
                createdAtMillis = createdAtMillis,
                stateFingerprint = stateFingerprint,
                trainingProfile = profile,
                focus = enumValue(root.opt("f")),
                variant = enumValue(root.opt("q")),
                requestedEffort = enumValue(root.opt("r")),
                appliedEffort = enumValue(root.opt("a")),
                effortAdjustment = (root.opt("j") as? String)
                    ?.takeIf(String::isNotEmpty)
                    ?.let { value -> enumValue<SmartWorkoutEffortAdjustment>(value) },
                exercises = exercises
            )
        )
    }

    private fun normalize(plan: SmartWorkoutLaunchPlan): SmartWorkoutLaunchPlan {
        require(bindingPattern.matches(plan.accountBinding))
        require(launchIdPattern.matches(plan.launchId))
        require(fingerprintPattern.matches(plan.stateFingerprint))
        require(WorkoutDataLimits.isValidTimestamp(plan.createdAtMillis))
        require(plan.trainingProfile.workoutsPerWeek in 2..6)
        require(plan.exercises.size in 1..SMART_WORKOUT_MAX_EXERCISES)
        require(plan.exercises.map { it.exerciseId }.all { it > 0L })
        require(plan.exercises.map { it.exerciseId }.distinct().size == plan.exercises.size)
        var totalSets = 0
        plan.exercises.forEach { exercise ->
            require(exercise.sets.size in
                SMART_WORKOUT_MIN_SETS_PER_EXERCISE..SMART_WORKOUT_MAX_SETS_PER_EXERCISE)
            totalSets += exercise.sets.size
            require(totalSets <= SMART_WORKOUT_MAX_TOTAL_SETS)
            exercise.sets.forEach { set ->
                require(set.weight == null || WorkoutDataLimits.isValidWeight(set.weight))
                require(WorkoutDataLimits.isValidReps(set.reps))
            }
        }
        require(plan.appliedEffort != SmartWorkoutEffort.Auto)
        require(plan.exercises.count { it.isHardSlot } <= 2)
        require(plan.appliedEffort == SmartWorkoutEffort.Hard || plan.exercises.none { it.isHardSlot })
        return plan.copy(exercises = plan.exercises.map { it.copy(sets = it.sets.toList()) })
    }

    private inline fun <reified T : Enum<T>> enumValue(raw: Any?): T {
        val value = raw as? String ?: error("Enum value is invalid.")
        return enumValues<T>().firstOrNull { it.name == value } ?: error("Enum value is invalid.")
    }

    private fun exactInt(raw: Any?): Int {
        val number = raw as? Number ?: error("Integer is invalid.")
        val value = number.toDouble()
        require(value.isFinite() && value % 1.0 == 0.0 && value in Int.MIN_VALUE.toDouble()..Int.MAX_VALUE.toDouble())
        return value.toInt()
    }

    private fun exactLong(raw: Any?): Long {
        val number = raw as? Number ?: error("Integer is invalid.")
        val value = number.toString().toLongOrNull() ?: error("Integer is invalid.")
        return value
    }

    internal const val MAX_LAUNCH_AGE_MILLIS = 5 * 60 * 1_000L
    internal const val MAX_FUTURE_SKEW_MILLIS = 60 * 1_000L

    private fun newLaunchId(): String {
        val bytes = ByteArray(16)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { byte -> "%02x".format(byte) }
    }

    private val secureRandom = SecureRandom()
}

/** Bounded, process-restorable one-shot registry for accepted launch IDs. */
internal object SmartWorkoutLaunchUseRegistry {
    private const val MAX_ENTRIES = 128
    private const val MAX_BYTES = 16 * 1_024
    private val launchIdPattern = Regex("^[0-9a-f]{32}$")

    fun isConsumed(
        encoded: String?,
        launchId: String,
        nowMillis: Long
    ): Boolean {
        require(launchIdPattern.matches(launchId))
        return read(encoded, nowMillis)?.any { it.first == launchId } ?: true
    }

    fun consume(
        encoded: String?,
        launchId: String,
        createdAtMillis: Long,
        nowMillis: Long
    ): String? {
        require(launchIdPattern.matches(launchId))
        require(WorkoutDataLimits.isValidTimestamp(createdAtMillis))
        val entries = read(encoded, nowMillis) ?: return null
        if (entries.any { it.first == launchId } || entries.size >= MAX_ENTRIES) return null
        val updated = entries + (launchId to createdAtMillis)
        val array = JSONArray()
        updated.forEach { (id, createdAt) ->
            array.put(JSONArray().put(id).put(createdAt))
        }
        return JSONObject().put("v", 1).put("u", array).toString().takeIf {
            it.toByteArray(Charsets.UTF_8).size <= MAX_BYTES
        }
    }

    private fun read(encoded: String?, nowMillis: Long): List<Pair<String, Long>>? {
        require(WorkoutDataLimits.isValidTimestamp(nowMillis))
        if (encoded == null) return emptyList()
        if (encoded.toByteArray(Charsets.UTF_8).size > MAX_BYTES) return null
        return runCatching {
            WorkoutDataLimits.requireSafeJsonEnvelope(encoded, MAX_BYTES)
            val root = JSONObject(encoded)
            require(root.keys().asSequence().toSet() == setOf("v", "u"))
            require((root.opt("v") as? Number)?.toDouble() == 1.0)
            val array = root.getJSONArray("u")
            require(array.length() <= MAX_ENTRIES)
            val oldestAccepted = nowMillis - SmartWorkoutLaunchPlanCodec.MAX_LAUNCH_AGE_MILLIS
            buildList {
                repeat(array.length()) { index ->
                    val item = array.optJSONArray(index) ?: error("Consumed launch is invalid.")
                    require(item.length() == 2)
                    val id = item.opt(0) as? String ?: error("Consumed launch ID is invalid.")
                    val createdAt = (item.opt(1) as? Number)?.toString()?.toLongOrNull()
                        ?: error("Consumed launch timestamp is invalid.")
                    require(launchIdPattern.matches(id))
                    require(WorkoutDataLimits.isValidTimestamp(createdAt))
                    if (createdAt >= oldestAccepted &&
                        createdAt <= nowMillis + SmartWorkoutLaunchPlanCodec.MAX_FUTURE_SKEW_MILLIS
                    ) {
                        add(id to createdAt)
                    }
                }
            }.also { entries ->
                require(entries.map { it.first }.distinct().size == entries.size)
            }
        }.getOrNull()
    }
}

/**
 * Binds an exact editable launch to the bounded account-local inputs that can
 * change Smart Coach materialization. The digest is order-sensitive where the
 * recommendation engine is order-sensitive and canonicalized for keyed sidecars.
 */
internal object SmartWorkoutLaunchStateFingerprint {
    private const val DOMAIN = "GymAppSmartWorkoutLaunchStateV1"
    private const val MAX_MUSCLE_MAPPINGS =
        WorkoutDataLimits.MAX_EXERCISES * 15

    fun compute(
        profile: TrainingProfile,
        exercises: List<ExerciseEntity>,
        history: List<ExerciseHistoryEntry>,
        loadProfiles: Map<Long, ExerciseLoadProfile>,
        muscleMappings: List<ExerciseMuscleMappingEntity>
    ): String {
        require(profile.workoutsPerWeek in 2..6)
        require(exercises.size <= WorkoutDataLimits.MAX_EXERCISES)
        require(history.size <= WorkoutDataLimits.MAX_TOTAL_SETS)
        require(loadProfiles.size <= WorkoutDataLimits.MAX_EXERCISES)
        require(muscleMappings.size <= MAX_MUSCLE_MAPPINGS)

        val writer = DigestWriter(MessageDigest.getInstance("SHA-256"))
        writer.string(DOMAIN)
        writer.string(profile.split.name)
        writer.int(profile.workoutsPerWeek)
        writer.string(profile.goal.name)
        writer.string(profile.calorieMode.name)

        writer.int(exercises.size)
        exercises.forEach { exercise ->
            require(exercise.id > 0L && WorkoutDataLimits.isValidExerciseName(exercise.name))
            writer.long(exercise.id)
            writer.string(exercise.name, WorkoutDataLimits.MAX_EXERCISE_NAME_BYTES)
            writer.boolean(exercise.isFavorite)
        }

        val sortedHistory = history.sortedWith(
            compareBy<ExerciseHistoryEntry> { it.sessionDate }
                .thenBy { it.sessionId }
                .thenBy { it.exerciseId }
                .thenBy { it.setOrderIndex }
                .thenBy { it.setId }
                .thenBy { it.exerciseName }
                .thenBy { it.weight }
                .thenBy { it.reps }
        )
        writer.int(sortedHistory.size)
        sortedHistory.forEach { entry ->
            require(entry.setId > 0L && entry.sessionId > 0L && entry.exerciseId > 0L)
            require(WorkoutDataLimits.isValidTimestamp(entry.sessionDate))
            require(WorkoutDataLimits.isValidExerciseName(entry.exerciseName))
            require(WorkoutDataLimits.isValidWeight(entry.weight))
            require(WorkoutDataLimits.isValidReps(entry.reps))
            require(entry.setOrderIndex in 0 until WorkoutDataLimits.MAX_SETS_PER_EXERCISE)
            writer.long(entry.setId)
            writer.long(entry.sessionId)
            writer.long(entry.sessionDate)
            writer.long(entry.exerciseId)
            writer.string(entry.exerciseName, WorkoutDataLimits.MAX_EXERCISE_NAME_BYTES)
            writer.long(entry.weight.toBits())
            writer.int(entry.reps)
            writer.int(entry.setOrderIndex)
        }

        val sortedLoadProfiles = loadProfiles.entries.sortedBy { it.key }
        writer.int(sortedLoadProfiles.size)
        sortedLoadProfiles.forEach { (exerciseId, loadProfile) ->
            require(exerciseId > 0L)
            writer.long(exerciseId)
            writer.string(loadProfile.direction.wireValue)
            writer.int(loadProfile.allowedWeightsKg.size)
            loadProfile.allowedWeightsKg.forEach { weight ->
                require(WorkoutDataLimits.isValidWeight(weight))
                writer.long(weight.toBits())
            }
        }

        val sortedMappings = muscleMappings.sortedWith(
            compareBy<ExerciseMuscleMappingEntity> { it.exerciseNameKey }
                .thenBy { it.muscleId }
                .thenBy { it.exerciseName }
                .thenBy { it.updatedAt }
        )
        writer.int(sortedMappings.size)
        sortedMappings.forEach { mapping ->
            require(mapping.exerciseNameKey.isNotBlank())
            require(mapping.exerciseNameKey.toByteArray(Charsets.UTF_8).size <=
                WorkoutDataLimits.MAX_EXERCISE_NAME_BYTES)
            require(WorkoutDataLimits.isValidExerciseName(mapping.exerciseName))
            require(mapping.muscleId.isNotBlank() && mapping.muscleId.length <= 64)
            require(mapping.weight.isFinite())
            writer.string(mapping.exerciseNameKey, WorkoutDataLimits.MAX_EXERCISE_NAME_BYTES)
            writer.string(mapping.exerciseName, WorkoutDataLimits.MAX_EXERCISE_NAME_BYTES)
            writer.string(mapping.muscleId, 64)
            writer.long(mapping.weight.toBits())
            writer.long(mapping.updatedAt)
        }

        return writer.finish()
    }

    private class DigestWriter(private val digest: MessageDigest) {
        fun boolean(value: Boolean) = int(if (value) 1 else 0)

        fun int(value: Int) {
            digest.update((value ushr 24).toByte())
            digest.update((value ushr 16).toByte())
            digest.update((value ushr 8).toByte())
            digest.update(value.toByte())
        }

        fun long(value: Long) {
            digest.update((value ushr 56).toByte())
            digest.update((value ushr 48).toByte())
            digest.update((value ushr 40).toByte())
            digest.update((value ushr 32).toByte())
            digest.update((value ushr 24).toByte())
            digest.update((value ushr 16).toByte())
            digest.update((value ushr 8).toByte())
            digest.update(value.toByte())
        }

        fun string(value: String, maximumBytes: Int = 256) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            require(bytes.size <= maximumBytes)
            int(bytes.size)
            digest.update(bytes)
        }

        fun finish(): String = digest.digest().joinToString("") { byte ->
            "%02x".format(byte)
        }
    }
}
