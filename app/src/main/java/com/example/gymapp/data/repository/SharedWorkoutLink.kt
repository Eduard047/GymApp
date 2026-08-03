package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.WorkoutSessionDetails
import org.json.JSONArray
import org.json.JSONObject
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

internal object SharedWorkoutLink {
    const val BASE_URL = "https://gymapptracker.com/"
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
    private val controlCharacterPattern = Regex("[\\u0000-\\u001f\\u007f]")

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

    fun encode(exercises: List<SharedWorkoutExercise>): String {
        require(exercises.isNotEmpty() && exercises.size <= MAX_EXERCISES) {
            "Shared workout exercise count is invalid."
        }
        var totalSets = 0
        val compactExercises = JSONArray()
        exercises.forEach { exercise ->
            val name = exercise.name.trim()
            require(
                name.isNotEmpty() &&
                    name.codePointCount(0, name.length) <= MAX_NAME_CODE_POINTS &&
                    name.toByteArray(Charsets.UTF_8).size <= MAX_NAME_UTF8_BYTES &&
                    !controlCharacterPattern.containsMatchIn(name)
            ) { "Exercise name is outside the supported bounds." }

            val catalogKey = exercise.catalogKey.orEmpty()
            require(
                catalogKey.isEmpty() ||
                    (catalogKey.length <= MAX_CATALOG_KEY_CHARACTERS &&
                        catalogKeyPattern.matches(catalogKey))
            ) { "Exercise catalog key is invalid." }

            require(
                exercise.sets.isNotEmpty() &&
                    exercise.sets.size <= MAX_SETS_PER_EXERCISE
            ) { "Shared workout set count is invalid." }
            totalSets += exercise.sets.size
            require(totalSets <= MAX_TOTAL_SETS) { "Shared workout contains too many sets." }

            val compactSets = JSONArray()
            exercise.sets.forEach { set ->
                require(set.weight.isFinite() && set.weight in 0.0..MAX_WEIGHT) {
                    "Set weight is invalid."
                }
                require(set.reps in 1..MAX_REPS) { "Set repetitions are invalid." }
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
}
