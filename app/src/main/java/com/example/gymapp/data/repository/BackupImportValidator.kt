package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import java.nio.ByteBuffer
import java.math.BigDecimal
import java.security.MessageDigest
import java.util.ArrayDeque
import org.json.JSONArray
import org.json.JSONObject

internal data class ValidatedBackupExercise(
    val name: String,
    val catalogKey: String?
) {
    val identityKey: String =
        BuiltInExerciseCatalog.resolvedKey(catalogKey = catalogKey, rawName = name)
            ?.let { "catalog:$it" }
            ?: "name:${name.normalizedExerciseName()}"
}

internal data class ValidatedBackupSet(
    val weight: Double,
    val reps: Int
)

internal data class ValidatedBackupBlock(
    val exercise: ValidatedBackupExercise,
    val sets: List<ValidatedBackupSet>
)

internal data class ValidatedBackupSession(
    val date: Long,
    val note: String?,
    val blocks: List<ValidatedBackupBlock>
)

internal data class ValidatedBackup(
    val exercises: List<ValidatedBackupExercise>,
    val sessions: List<ValidatedBackupSession>
)

internal object BackupImportValidator {
    fun validate(root: JSONObject, defaultTimestamp: Long = System.currentTimeMillis()): ValidatedBackup {
        requireSafeParsedJson(root)
        validateSchema(root)
        validateOptionalExportedAt(root)
        validateOwnerShape(root)

        val exerciseArray = root.optionalArray("exercises")
        val sessionArray = root.optionalArray("sessions")
        require(exerciseArray.length() <= WorkoutDataLimits.MAX_EXERCISES) {
            "Backup exceeds the exercise limit."
        }
        require(sessionArray.length() <= WorkoutDataLimits.MAX_SESSIONS) {
            "Backup exceeds the workout limit."
        }

        val allExerciseIdentities = linkedSetOf<String>()
        val exercises = List(exerciseArray.length()) { index ->
            val exercise = validateExercise(exerciseArray.requiredObject(index), "name")
            allExerciseIdentities += exercise.identityKey
            exercise
        }

        var totalSets = 0
        val sessions = List(sessionArray.length()) { sessionIndex ->
            val session = sessionArray.requiredObject(sessionIndex)
            val note = session.optionalBoundedString("note", WorkoutDataLimits.MAX_NOTE_LENGTH * 2)
                ?.also {
                    require(WorkoutDataLimits.isValidNote(it)) {
                        "Workout note exceeds the length limit."
                    }
                }
                ?.takeIf { it.isNotBlank() }
            val date = session.optionalTimestamp("date")
                ?: session.optionalTimestamp("startedAt")
                ?: defaultTimestamp
            require(WorkoutDataLimits.isValidTimestamp(date)) {
                "Workout timestamp is outside the supported range."
            }

            val nestedExercises = session.optionalArrayOrNull("exercises")
            val blocks = if (nestedExercises != null) {
                require(nestedExercises.length() <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                    "A workout exceeds the exercise limit."
                }
                List(nestedExercises.length()) { exerciseIndex ->
                    val exerciseJson = nestedExercises.requiredObject(exerciseIndex)
                    val exercise = validateExercise(exerciseJson, "name")
                    val sets = validateSets(exerciseJson.optionalArray("sets"))
                    totalSets += sets.size
                    require(totalSets <= WorkoutDataLimits.MAX_TOTAL_SETS) {
                        "Backup exceeds the total set limit."
                    }
                    ValidatedBackupBlock(exercise = exercise, sets = sets)
                }
            } else {
                validateLegacyExerciseNames(session)
                val flatSets = session.optionalArray("sets")
                require(flatSets.length() <= WorkoutDataLimits.MAX_TOTAL_SETS) {
                    "A legacy workout exceeds the set limit."
                }
                val grouped = linkedMapOf<String, Pair<ValidatedBackupExercise, MutableList<ValidatedBackupSet>>>()
                repeat(flatSets.length()) { setIndex ->
                    val setJson = flatSets.requiredObject(setIndex)
                    val exercise = validateExercise(setJson, "exerciseName", "name")
                    val set = validateSet(setJson)
                    val entry = grouped.getOrPut(exercise.identityKey) { exercise to mutableListOf() }
                    entry.second += set
                    require(entry.second.size <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                        "A workout exercise exceeds the set limit."
                    }
                    totalSets += 1
                    require(totalSets <= WorkoutDataLimits.MAX_TOTAL_SETS) {
                        "Backup exceeds the total set limit."
                    }
                }
                require(grouped.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                    "A legacy workout exceeds the exercise limit."
                }
                grouped.values.map { (exercise, sets) ->
                    ValidatedBackupBlock(exercise = exercise, sets = sets.toList())
                }
            }

            val setsPerExercise = linkedMapOf<String, Int>()
            blocks.forEach { block ->
                allExerciseIdentities += block.exercise.identityKey
                val count = setsPerExercise.getOrDefault(block.exercise.identityKey, 0) + block.sets.size
                require(count <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                    "A workout exercise exceeds the set limit."
                }
                setsPerExercise[block.exercise.identityKey] = count
            }
            require(setsPerExercise.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                "A workout exceeds the exercise limit."
            }
            require(allExerciseIdentities.size <= WorkoutDataLimits.MAX_EXERCISES) {
                "Backup exceeds the distinct exercise limit."
            }

            ValidatedBackupSession(date = date, note = note, blocks = blocks)
        }

        return ValidatedBackup(exercises = exercises, sessions = sessions)
    }

    private fun validateSchema(root: JSONObject) {
        if (!root.has("schemaVersion") || root.isNull("schemaVersion")) return
        val schema = root.requiredIntegralNumber("schemaVersion")
        require(schema == 2L) { "Unsupported backup schema version." }
    }

    private fun validateOptionalExportedAt(root: JSONObject) {
        if (!root.has("exportedAt") || root.isNull("exportedAt")) return
        require(WorkoutDataLimits.isValidTimestamp(root.requiredIntegralNumber("exportedAt"))) {
            "Backup export timestamp is outside the supported range."
        }
    }

    private fun validateOwnerShape(root: JSONObject) {
        if (!root.has("owner") || root.isNull("owner")) return
        val owner = root.opt("owner") as? JSONObject
            ?: throw IllegalArgumentException("Backup owner must be an object.")
        owner.optionalBoundedString("accountId", WorkoutDataLimits.MAX_ACCOUNT_IDENTIFIER_LENGTH)?.let {
            require(it.isNotBlank()) { "Backup owner account identifier must not be blank." }
        }
        owner.optionalBoundedString("userId", WorkoutDataLimits.MAX_ACCOUNT_IDENTIFIER_LENGTH)?.let {
            require(it.isNotBlank()) { "Backup owner user identifier must not be blank." }
        }
        owner.optionalBoundedString("email", WorkoutDataLimits.MAX_EMAIL_LENGTH)
        if (owner.has("remote") && !owner.isNull("remote")) {
            val remote = owner.opt("remote")
            require(remote is Boolean || remote == "supabase") {
                "Backup owner remote flag is unsupported."
            }
        }
    }

    private data class ParsedNode(val value: Any, val depth: Int)

    private fun requireSafeParsedJson(root: JSONObject) {
        val pending = ArrayDeque<ParsedNode>()
        pending.add(ParsedNode(root, 1))
        var estimatedBytes = 0L

        fun addBytes(bytes: Long) {
            estimatedBytes += bytes
            require(estimatedBytes <= WorkoutDataLimits.MAX_BACKUP_BYTES.toLong()) {
                "Backup exceeds the file size limit."
            }
        }

        while (pending.isNotEmpty()) {
            val (value, depth) = pending.removeLast()
            when (value) {
                is JSONObject -> {
                    require(depth <= WorkoutDataLimits.MAX_JSON_NESTING_DEPTH) {
                        "Backup exceeds the JSON nesting limit."
                    }
                    addBytes(2)
                    val keys = value.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val keyBytes = WorkoutDataLimits.utf8ByteLengthAtMost(
                            key,
                            WorkoutDataLimits.MAX_JSON_STRING_BYTES
                        ) ?: throw IllegalArgumentException("Backup exceeds the JSON string limit.")
                        addBytes(keyBytes.toLong() + 4L)
                        val child = value.opt(key)
                        if (child != null && child !== JSONObject.NULL) {
                            pending.add(ParsedNode(child, depth + 1))
                        } else {
                            addBytes(4)
                        }
                    }
                }
                is JSONArray -> {
                    require(depth <= WorkoutDataLimits.MAX_JSON_NESTING_DEPTH) {
                        "Backup exceeds the JSON nesting limit."
                    }
                    addBytes(2L + (value.length() - 1).coerceAtLeast(0).toLong())
                    repeat(value.length()) { index ->
                        val child = value.opt(index)
                        if (child != null && child !== JSONObject.NULL) {
                            pending.add(ParsedNode(child, depth + 1))
                        } else {
                            addBytes(4)
                        }
                    }
                }
                is String -> {
                    val stringBytes = WorkoutDataLimits.utf8ByteLengthAtMost(
                        value,
                        WorkoutDataLimits.MAX_JSON_STRING_BYTES
                    ) ?: throw IllegalArgumentException("Backup exceeds the JSON string limit.")
                    addBytes(stringBytes.toLong() + 2L)
                }
                is Number, is Boolean -> addBytes(value.toString().length.toLong())
                else -> throw IllegalArgumentException("Backup contains an unsupported JSON value.")
            }
        }
    }

    private fun validateLegacyExerciseNames(session: JSONObject) {
        val names = session.optionalArrayOrNull("exerciseNames") ?: return
        require(names.length() <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            "A legacy workout exceeds the exercise-name limit."
        }
        repeat(names.length()) { index ->
            val raw = names.opt(index)
            require(raw is String && raw.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
                "Legacy exercise names must be bounded non-empty strings."
            }
            require(WorkoutDataLimits.isValidExerciseName(raw.trim())) {
                "Legacy exercise names must be bounded non-empty strings."
            }
        }
    }

    private fun validateExercise(json: JSONObject, vararg nameFields: String): ValidatedBackupExercise {
        var rawName: String? = null
        nameFields.forEach { field ->
            if (json.has(field) && !json.isNull(field)) {
                val candidate = json.opt(field)
                require(candidate is String) { "Exercise name must be a string." }
                require(candidate.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
                    "Exercise name is outside the supported length."
                }
                if (rawName == null) {
                    val trimmed = candidate.trim()
                    if (trimmed.isNotBlank()) rawName = trimmed
                }
            }
        }
        val catalogKey = json.optionalBoundedString(
            "catalogKey",
            WorkoutDataLimits.MAX_CATALOG_KEY_LENGTH
        )?.trim()?.takeIf { it.isNotBlank() }
        val name = rawName
            ?: BuiltInExerciseCatalog.canonicalNameForKey(catalogKey.orEmpty())
            ?: throw IllegalArgumentException("Exercise name is required.")
        require(WorkoutDataLimits.isValidExerciseName(name)) {
            "Exercise name is outside the supported length."
        }
        return ValidatedBackupExercise(name = name, catalogKey = catalogKey)
    }

    private fun validateSets(array: JSONArray): List<ValidatedBackupSet> {
        require(array.length() <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
            "A workout exercise exceeds the set limit."
        }
        return List(array.length()) { index -> validateSet(array.requiredObject(index)) }
    }

    private fun validateSet(json: JSONObject): ValidatedBackupSet {
        val weight = json.requiredFiniteNumber("weight")
        val repsLong = json.requiredIntegralNumber("reps")
        require(repsLong in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
            "Set repetitions are outside the supported range."
        }
        val reps = repsLong.toInt()
        require(WorkoutDataLimits.isValidWeight(weight) && WorkoutDataLimits.isValidReps(reps)) {
            "Set values are outside the supported range."
        }
        return ValidatedBackupSet(weight = weight, reps = reps)
    }
}

internal fun canonicalWorkoutPayloadMatches(left: JSONObject, right: JSONObject): Boolean =
    runCatching {
        BackupImportValidator.validate(left) == BackupImportValidator.validate(right)
    }.getOrDefault(false)

internal fun canonicalWorkoutPayloadDigest(root: JSONObject): String? = runCatching {
    canonicalWorkoutPayloadDigest(BackupImportValidator.validate(root))
}.getOrNull()

internal fun canonicalWorkoutPayloadDigest(backup: ValidatedBackup): String {
    val digest = MessageDigest.getInstance("SHA-256")

    fun updateLong(value: Long) {
        digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(value).array())
    }

    fun updateInt(value: Int) = updateLong(value.toLong())

    fun updateString(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        updateInt(bytes.size)
        digest.update(bytes)
    }

    fun updateOptionalString(value: String?) {
        digest.update(if (value == null) 0.toByte() else 1.toByte())
        value?.let(::updateString)
    }

    fun updateDouble(value: Double) {
        val canonical = if (value == 0.0) 0.0 else value
        updateLong(java.lang.Double.doubleToLongBits(canonical))
    }

    updateString("gymapp-canonical-workout-payload/v1")
    updateInt(backup.exercises.size)
    backup.exercises.forEach { exercise ->
        updateString(exercise.name)
        updateOptionalString(exercise.catalogKey)
    }
    updateInt(backup.sessions.size)
    backup.sessions.forEach { session ->
        updateLong(session.date)
        updateOptionalString(session.note)
        updateInt(session.blocks.size)
        session.blocks.forEach { block ->
            updateString(block.exercise.name)
            updateOptionalString(block.exercise.catalogKey)
            updateInt(block.sets.size)
            block.sets.forEach { set ->
                updateDouble(set.weight)
                updateInt(set.reps)
            }
        }
    }
    return digest.digest().joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}

private fun JSONObject.optionalArray(key: String): JSONArray {
    if (!has(key) || isNull(key)) return JSONArray()
    return opt(key) as? JSONArray
        ?: throw IllegalArgumentException("Backup field '$key' must be an array.")
}

private fun JSONObject.optionalArrayOrNull(key: String): JSONArray? {
    if (!has(key) || isNull(key)) return null
    return opt(key) as? JSONArray
        ?: throw IllegalArgumentException("Backup field '$key' must be an array.")
}

private fun JSONArray.requiredObject(index: Int): JSONObject =
    opt(index) as? JSONObject
        ?: throw IllegalArgumentException("Backup array entries must be objects.")

private fun JSONObject.optionalBoundedString(key: String, maximumLength: Int): String? {
    if (!has(key) || isNull(key)) return null
    val value = opt(key)
    require(value is String) { "Backup field '$key' must be a string." }
    require(value.length <= maximumLength) { "Backup field '$key' exceeds the length limit." }
    return value
}

private fun JSONObject.requiredFiniteNumber(key: String): Double {
    val value = opt(key)
    require(value is Number) { "Backup field '$key' must be numeric." }
    val number = value.toDouble()
    require(number.isFinite()) { "Backup field '$key' must be finite." }
    return number
}

private fun JSONObject.requiredIntegralNumber(key: String): Long {
    val value = opt(key)
    require(value is Number) { "Backup field '$key' must be an integer." }
    return when (value) {
        is Byte, is Short, is Int, is Long -> value.toLong()
        else -> runCatching { BigDecimal(value.toString()).longValueExact() }
            .getOrElse { throw IllegalArgumentException("Backup field '$key' must be an integer.") }
    }
}

private fun JSONObject.optionalTimestamp(key: String): Long? {
    if (!has(key) || isNull(key)) return null
    return requiredIntegralNumber(key)
}
