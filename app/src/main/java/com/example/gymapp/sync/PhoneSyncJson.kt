package com.example.gymapp.sync

import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import org.json.JSONArray
import org.json.JSONObject

data class CreateWorkoutCommand(
    val startedAt: Long,
    val note: String?,
    val sets: List<NamedWorkoutSetDraft>
)

data class UpdateSetCommand(
    val setId: Long,
    val weight: Double,
    val reps: Int
)

data class DeleteSetCommand(
    val setId: Long
)

object PhoneSyncJson {
    fun encodeWorkoutPlanPayload(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>
    ): String {
        val setsJson = JSONArray()
        sets.forEach { set ->
            setsJson.put(
                JSONObject()
                    .put("exerciseName", set.exerciseName)
                    .put("weight", set.weight)
                    .put("reps", set.reps)
            )
        }

        val exercisesJson = JSONArray()
        exerciseCatalog.forEach { exerciseName ->
            val trimmed = exerciseName.trim()
            if (trimmed.isNotBlank()) {
                exercisesJson.put(trimmed)
            }
        }

        return JSONObject()
            .put("generatedAt", System.currentTimeMillis())
            .put("sets", setsJson)
            .put("exerciseCatalog", exercisesJson)
            .toString()
    }

    fun parseCreateWorkoutCommand(raw: String): CreateWorkoutCommand? {
        return runCatching {
            val root = JSONObject(raw)
            val setsArray = root.optJSONArray("sets") ?: JSONArray()
            val sets = mutableListOf<NamedWorkoutSetDraft>()
            for (index in 0 until setsArray.length()) {
                val item = setsArray.optJSONObject(index) ?: continue
                val exerciseName = item.optString("exerciseName", "").trim()
                val weight = item.optDouble("weight", Double.NaN)
                val reps = item.optInt("reps", -1)
                if (exerciseName.isBlank() || !weight.isFinite() || weight < 0.0 || reps <= 0) {
                    continue
                }
                sets += NamedWorkoutSetDraft(
                    exerciseName = exerciseName,
                    weight = weight,
                    reps = reps
                )
            }

            CreateWorkoutCommand(
                startedAt = root.optLong("startedAt", System.currentTimeMillis()),
                note = root.optString("note", "").ifBlank { null },
                sets = sets
            )
        }.getOrNull()
    }

    fun parseUpdateSetCommand(raw: String): UpdateSetCommand? {
        return runCatching {
            val root = JSONObject(raw)
            val setId = root.optLong("setId", -1L)
            val weight = root.optDouble("weight", Double.NaN)
            val reps = root.optInt("reps", -1)
            if (setId <= 0 || !weight.isFinite() || weight < 0.0 || reps <= 0) {
                null
            } else {
                UpdateSetCommand(setId = setId, weight = weight, reps = reps)
            }
        }.getOrNull()
    }

    fun parseDeleteSetCommand(raw: String): DeleteSetCommand? {
        return runCatching {
            val root = JSONObject(raw)
            val setId = root.optLong("setId", -1L)
            if (setId <= 0) null else DeleteSetCommand(setId = setId)
        }.getOrNull()
    }

    fun encodeFullSyncPayload(
        detailsList: List<WorkoutSessionDetails>,
        exerciseCatalog: List<String>
    ): String {
        val sessions = JSONArray()
        detailsList.forEach { details ->
            val setsJson = JSONArray()
            var order = 0
            details.workoutExercises.forEach { exerciseDetails ->
                exerciseDetails.sets.forEach { set ->
                    setsJson.put(
                        JSONObject()
                            .put("id", set.id)
                            .put("sessionId", details.session.id)
                            .put("exerciseName", exerciseDetails.exercise.name)
                            .put("weight", set.weight)
                            .put("reps", set.reps)
                            .put("orderIndex", order++)
                    )
                }
            }

            sessions.put(
                JSONObject()
                    .put("id", details.session.id)
                    .put("startedAt", details.session.date)
                    .put("note", details.session.note)
                    .put("sets", setsJson)
            )
        }

        val exercisesJson = JSONArray()
        exerciseCatalog.forEach { exerciseName ->
            val trimmed = exerciseName.trim()
            if (trimmed.isNotBlank()) {
                exercisesJson.put(trimmed)
            }
        }

        return JSONObject()
            .put("sessions", sessions)
            .put("exerciseCatalog", exercisesJson)
            .toString()
    }
}
