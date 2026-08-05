package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.WorkoutSessionDetails
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.Base64

internal data class SharedWorkoutSet(
    val weight: Double,
    val reps: Int
)

internal data class SharedWorkoutExercise(
    val catalogKey: String?,
    val name: String,
    val sets: List<SharedWorkoutSet>
)

internal data class SharedWorkoutPlan(
    val exercises: List<SharedWorkoutExercise>
) {
    val exerciseCount: Int
        get() = exercises.size

    val setCount: Int
        get() = exercises.sumOf { it.sets.size }
}

internal sealed interface IncomingSharedWorkoutUrl {
    data object NotSharedWorkout : IncomingSharedWorkoutUrl
    data object InvalidSharedWorkout : IncomingSharedWorkoutUrl
    data class Valid(val plan: SharedWorkoutPlan) : IncomingSharedWorkoutUrl
}

internal object SharedWorkoutLink {
    const val SITE_ORIGIN = "https://gymapptracker.com"
    const val BASE_URL = "$SITE_ORIGIN/workout/"
    const val WEB_FALLBACK_BASE_URL = "$SITE_ORIGIN/"
    const val MAX_ENCODED_LENGTH = 12_000
    const val MAX_DECODED_BYTES = 9_000
    const val MAX_EXERCISES = 20
    const val MAX_SETS_PER_EXERCISE = 12
    const val MAX_TOTAL_SETS = 120
    const val MAX_NAME_CODE_POINTS = 120
    const val MAX_NAME_UTF8_BYTES = 480
    const val MAX_CATALOG_KEY_CHARACTERS = 64
    const val MAX_WEIGHT = 1_000_000.0
    const val MAX_REPS = 10_000

    private val catalogKeyPattern = Regex("^[a-z0-9_]{1,64}$")
    private val encodedPayloadPattern = Regex("^[A-Za-z0-9_-]{1,$MAX_ENCODED_LENGTH}$")

    fun fromSession(details: WorkoutSessionDetails): String {
        val exercises = details.workoutExercises
            .sortedBy { it.workoutExercise.orderIndex }
            .filter { it.sets.isNotEmpty() }
            .map { block ->
                SharedWorkoutExercise(
                    catalogKey = BuiltInExerciseCatalog.inferKey(block.exercise.name),
                    name = block.exercise.name,
                    sets = block.sets
                        .sortedBy { it.orderIndex }
                        .map { set -> SharedWorkoutSet(set.weight, set.reps) }
                )
            }
        return buildUrl(exercises)
    }

    fun buildUrl(exercises: List<SharedWorkoutExercise>): String =
        "$BASE_URL#workout=${encode(exercises)}"

    fun buildWebFallbackUrl(plan: SharedWorkoutPlan): String =
        "$WEB_FALLBACK_BASE_URL#workout=${encode(plan.exercises)}"

    fun parseIncomingUrl(
        rawUrl: String,
        customScheme: String
    ): IncomingSharedWorkoutUrl {
        val uri = runCatching { URI(rawUrl) }.getOrNull()
            ?: return IncomingSharedWorkoutUrl.NotSharedWorkout
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()
        val path = uri.path.orEmpty()
        val isHttpsRoute = scheme == "https" &&
            host == "gymapptracker.com" &&
            (path == "/workout/" || path == "/")
        val isCustomRoute = scheme == customScheme.lowercase() &&
            host == "workout" &&
            (path.isEmpty() || path == "/")
        if (!isHttpsRoute && !isCustomRoute) {
            return IncomingSharedWorkoutUrl.NotSharedWorkout
        }
        val hasSafeAuthorityAndQuery = if (isHttpsRoute) {
            uri.userInfo == null && (uri.port == -1 || uri.port == 443) && uri.rawQuery == null
        } else {
            uri.userInfo == null && uri.port == -1 && uri.rawQuery == null
        }
        if (!hasSafeAuthorityAndQuery) return IncomingSharedWorkoutUrl.InvalidSharedWorkout

        val fragment = uri.rawFragment.orEmpty()
        if (!fragment.startsWith("workout=") || fragment.indexOf('&') >= 0) {
            return IncomingSharedWorkoutUrl.InvalidSharedWorkout
        }
        val encoded = fragment.removePrefix("workout=")
        return runCatching { IncomingSharedWorkoutUrl.Valid(decode(encoded)) }
            .getOrElse { IncomingSharedWorkoutUrl.InvalidSharedWorkout }
    }

    fun encode(exercises: List<SharedWorkoutExercise>): String {
        val plan = normalize(exercises)
        val compactExercises = JSONArray()
        plan.exercises.forEach { exercise ->
            val name = exercise.name
            val catalogKey = exercise.catalogKey.orEmpty()

            val compactSets = JSONArray()
            exercise.sets.forEach { set ->
                compactSets.put(JSONArray().put(set.weight).put(set.reps))
            }
            compactExercises.put(
                JSONArray()
                    .put(catalogKey)
                    .put(name)
                    .put(compactSets)
            )
        }

        val json = JSONObject()
            .put("v", 1)
            .put("e", compactExercises)
            .toString()
        val bytes = json.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_DECODED_BYTES) { "Shared workout is too large." }
        val encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        require(encoded.length <= MAX_ENCODED_LENGTH) { "Shared workout is too large." }
        return encoded
    }

    fun decode(encoded: String): SharedWorkoutPlan {
        require(encodedPayloadPattern.matches(encoded)) {
            "Shared workout encoding is invalid."
        }
        val bytes = runCatching { Base64.getUrlDecoder().decode(encoded) }
            .getOrElse { throw IllegalArgumentException("Shared workout encoding is invalid.") }
        require(bytes.size <= MAX_DECODED_BYTES) { "Shared workout is too large." }
        require(
            Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) == encoded
        ) { "Shared workout encoding is not canonical." }
        val rawJson = bytes.toString(Charsets.UTF_8)
        require(rawJson.toByteArray(Charsets.UTF_8).contentEquals(bytes)) {
            "Shared workout JSON is not valid UTF-8."
        }
        WorkoutDataLimits.requireSafeJsonEnvelope(rawJson, MAX_DECODED_BYTES)
        val root = runCatching { JSONObject(rawJson) }
            .getOrElse { throw IllegalArgumentException("Shared workout JSON is invalid.") }
        val rawVersion = root.opt("v") as? Number
        require(
            root.keys().asSequence().toSet() == setOf("v", "e") &&
                rawVersion?.toDouble() == 1.0
        ) {
            "Shared workout version is unsupported."
        }
        val rawExercises = root.optJSONArray("e")
            ?: throw IllegalArgumentException("Shared workout exercise count is invalid.")
        require(rawExercises.length() in 1..MAX_EXERCISES) {
            "Shared workout exercise count is invalid."
        }
        val exercises = List(rawExercises.length()) { exerciseIndex ->
            val rawExercise = rawExercises.optJSONArray(exerciseIndex)
                ?: throw IllegalArgumentException("Shared workout exercise is invalid.")
            require(rawExercise.length() == 3) { "Shared workout exercise is invalid." }
            val rawCatalogKey = rawExercise.opt(0)
            val rawName = rawExercise.opt(1)
            val rawSets = rawExercise.optJSONArray(2)
            require(rawCatalogKey is String && rawName is String && rawSets != null) {
                "Shared workout exercise is invalid."
            }
            SharedWorkoutExercise(
                catalogKey = rawCatalogKey.ifEmpty { null },
                name = rawName,
                sets = List(rawSets.length()) { setIndex ->
                    val rawSet = rawSets.optJSONArray(setIndex)
                        ?: throw IllegalArgumentException("Shared workout set is invalid.")
                    require(rawSet.length() == 2) { "Shared workout set is invalid." }
                    val weight = rawSet.opt(0) as? Number
                        ?: throw IllegalArgumentException("Set weight is invalid.")
                    val repetitions = rawSet.opt(1) as? Number
                        ?: throw IllegalArgumentException("Set repetitions are invalid.")
                    val weightValue = weight.toDouble()
                    val repetitionsValue = repetitions.toDouble()
                    require(repetitionsValue.isFinite() && repetitionsValue % 1.0 == 0.0) {
                        "Set repetitions are invalid."
                    }
                    SharedWorkoutSet(
                        weight = weightValue,
                        reps = repetitionsValue.toInt()
                    )
                }
            )
        }
        return normalize(exercises)
    }

    fun normalize(exercises: List<SharedWorkoutExercise>): SharedWorkoutPlan {
        require(exercises.isNotEmpty() && exercises.size <= MAX_EXERCISES) {
            "Shared workout exercise count is invalid."
        }
        var totalSets = 0
        val identities = linkedSetOf<String>()
        val normalized = exercises.map { exercise ->
            val name = exercise.name.trim()
            require(
                name.isNotEmpty() &&
                    name.codePointCount(0, name.length) <= MAX_NAME_CODE_POINTS &&
                    name.toByteArray(Charsets.UTF_8).size <= MAX_NAME_UTF8_BYTES &&
                    !name.containsUnsafeSharedWorkoutNameScalar()
            ) { "Exercise name is outside the supported bounds." }
            val catalogKey = exercise.catalogKey.orEmpty()
            require(
                catalogKey.isEmpty() ||
                    (catalogKey.length <= MAX_CATALOG_KEY_CHARACTERS &&
                        catalogKeyPattern.matches(catalogKey))
            ) { "Exercise catalog key is invalid." }
            require(exercise.sets.size in 1..MAX_SETS_PER_EXERCISE) {
                "Shared workout set count is invalid."
            }
            totalSets += exercise.sets.size
            require(totalSets <= MAX_TOTAL_SETS) { "Shared workout contains too many sets." }
            val inferredCatalogKey = BuiltInExerciseCatalog.inferKey(name)
            val identity = inferredCatalogKey?.let { "catalog:$it" }
                ?: "name:${name.normalizedExerciseName()}"
            require(identities.add(identity)) { "Shared workout contains duplicate exercises." }
            SharedWorkoutExercise(
                // Preserve the portable key for cross-language receivers, but never use an
                // attacker-supplied key to decide this device's exercise identity. Resolution
                // on import deliberately prefers the validated raw name.
                catalogKey = inferredCatalogKey ?: catalogKey.ifEmpty { null },
                name = name,
                sets = exercise.sets.map { set ->
                    require(set.weight.isFinite() && set.weight in 0.0..MAX_WEIGHT) {
                        "Set weight is invalid."
                    }
                    require(set.reps in 1..MAX_REPS) { "Set repetitions are invalid." }
                    set.copy()
                }
            )
        }
        return SharedWorkoutPlan(normalized)
    }

    private fun String.containsUnsafeSharedWorkoutNameScalar(): Boolean {
        var index = 0
        while (index < length) {
            val codePoint = Character.codePointAt(this, index)
            when (Character.getType(codePoint)) {
                Character.CONTROL.toInt(),
                Character.FORMAT.toInt(),
                Character.LINE_SEPARATOR.toInt(),
                Character.PARAGRAPH_SEPARATOR.toInt() -> return true
            }
            index += Character.charCount(codePoint)
        }
        return false
    }

    fun resolvedCatalogKeyForImport(exercise: SharedWorkoutExercise): String? {
        BuiltInExerciseCatalog.inferKey(exercise.name)?.let { return it }
        val definition = BuiltInExerciseCatalog.definitionForKey(exercise.catalogKey) ?: return null
        val normalizedName = exercise.name.normalizedExerciseName()
        val reviewedNames = sequenceOf(
            definition.nameEn,
            definition.nameUk,
            BuiltInExerciseCatalog.displayName(definition.nameEn, "ru")
        ) + definition.legacyAliases.asSequence()
        return definition.key.takeIf { key ->
            key.isNotEmpty() && reviewedNames.any { candidate ->
                candidate.normalizedExerciseName() == normalizedName
            }
        }
    }
}
