package com.example.gymapp.wear.sync

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import org.json.JSONArray
import org.json.JSONObject

data class SyncedSetPayload(
    val id: Long,
    val sessionId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int
)

data class SyncedSessionPayload(
    val id: Long,
    val startedAt: Long,
    val note: String?,
    val sets: List<SyncedSetPayload>
)

object WatchSyncJson {
    fun buildCreateWorkoutPayload(
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>
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

        return JSONObject()
            .put("startedAt", startedAt)
            .put("note", note)
            .put("sets", setsJson)
            .toString()
    }

    fun buildUpdateSetPayload(setId: Long, weight: Double, reps: Int): String {
        return JSONObject()
            .put("setId", setId)
            .put("weight", weight)
            .put("reps", reps)
            .toString()
    }

    fun buildDeleteSetPayload(setId: Long): String {
        return JSONObject()
            .put("setId", setId)
            .toString()
    }

    fun parseWorkoutPlanPayload(raw: String): List<WearWorkoutSetDraft> {
        return runCatching {
            val root = JSONObject(raw)
            val setsArray = root.optJSONArray("sets") ?: JSONArray()
            buildList {
                for (index in 0 until setsArray.length()) {
                    val item = setsArray.optJSONObject(index) ?: continue
                    val exerciseName = item.optString("exerciseName", "").trim()
                    val weight = item.optDouble("weight", Double.NaN)
                    val reps = item.optInt("reps", -1)
                    if (
                        exerciseName.isBlank() ||
                        !weight.isFinite() ||
                        weight < 0.0 ||
                        reps <= 0
                    ) {
                        continue
                    }

                    add(
                        WearWorkoutSetDraft(
                            exerciseName = exerciseName,
                            weight = weight,
                            reps = reps
                        )
                    )
                }
            }
        }.getOrElse { emptyList() }
    }

    fun parseExerciseCatalogFromWorkoutPlan(raw: String): List<String> {
        return runCatching {
            val root = JSONObject(raw)
            val catalog = root.optJSONArray("exerciseCatalog") ?: JSONArray()
            val unique = linkedSetOf<String>()
            for (index in 0 until catalog.length()) {
                val item = catalog.optString(index, "").trim()
                if (item.isNotBlank()) {
                    unique += item
                }
            }
            unique.toList()
        }.getOrElse { emptyList() }
    }

    fun parseExerciseCatalogFromFullSync(raw: String): List<String> {
        return runCatching {
            val root = JSONObject(raw)
            val catalog = root.optJSONArray("exerciseCatalog") ?: JSONArray()
            val unique = linkedSetOf<String>()
            for (index in 0 until catalog.length()) {
                val item = catalog.optString(index, "").trim()
                if (item.isNotBlank()) {
                    unique += item
                }
            }
            unique.toList()
        }.getOrElse { emptyList() }
    }

    fun parseFullSyncPayload(raw: String): List<SyncedSessionPayload> {
        return runCatching {
            val root = JSONObject(raw)
            val sessions = root.optJSONArray("sessions") ?: JSONArray()
            buildList {
                for (sessionIndex in 0 until sessions.length()) {
                    val session = sessions.optJSONObject(sessionIndex) ?: continue
                    val sessionId = session.optLong("id", -1L)
                    if (sessionId <= 0) continue

                    val setsArray = session.optJSONArray("sets") ?: JSONArray()
                    val sets = buildList {
                        for (setIndex in 0 until setsArray.length()) {
                            val set = setsArray.optJSONObject(setIndex) ?: continue
                            val setId = set.optLong("id", -1L)
                            val payloadSessionId = set.optLong("sessionId", sessionId)
                            val exerciseName = set.optString("exerciseName", "").trim()
                            val weight = set.optDouble("weight", Double.NaN)
                            val reps = set.optInt("reps", -1)
                            val orderIndex = set.optInt("orderIndex", setIndex)
                            if (
                                setId <= 0 ||
                                payloadSessionId <= 0 ||
                                exerciseName.isBlank() ||
                                !weight.isFinite() ||
                                weight < 0.0 ||
                                reps <= 0
                            ) {
                                continue
                            }
                            add(
                                SyncedSetPayload(
                                    id = setId,
                                    sessionId = payloadSessionId,
                                    exerciseName = exerciseName,
                                    weight = weight,
                                    reps = reps,
                                    orderIndex = orderIndex
                                )
                            )
                        }
                    }

                    add(
                        SyncedSessionPayload(
                            id = sessionId,
                            startedAt = session.optLong("startedAt", System.currentTimeMillis()),
                            note = session.optString("note", "").ifBlank { null },
                            sets = sets.sortedBy { it.orderIndex }
                        )
                    )
                }
            }
        }.getOrElse { emptyList() }
    }
}
