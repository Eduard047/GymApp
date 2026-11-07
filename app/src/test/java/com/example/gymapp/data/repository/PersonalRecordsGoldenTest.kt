package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/personal-records-v1.json, the same cases the iOS suite runs. */
class PersonalRecordsGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 10)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val expected = case.getJSONObject("expected")

            // Exercise keys map to ids in order of first appearance.
            val ids = mutableMapOf<String, Long>()
            fun idOf(key: String): Long = ids.getOrPut(key) { ids.size + 1L }

            val history = case.getJSONArray("history").objects().mapIndexed { i, item ->
                val exerciseId = idOf(item.getString("exercise"))
                ExerciseHistoryEntry(
                    setId = i.toLong() + 1,
                    sessionId = 1L,
                    sessionDate = 1_780_000_000_000L,
                    exerciseId = exerciseId,
                    exerciseName = item.getString("exercise"),
                    weight = item.getDouble("weight"),
                    reps = item.getInt("reps"),
                    setOrderIndex = i
                )
            }
            val baselines = LivePersonalRecords.baselines(history)

            val expectedBaselines = expected.getJSONObject("baselines")
            assertEquals("$id baseline exercises", expectedBaselines.length(), baselines.size)
            for (key in expectedBaselines.keys()) {
                val baseline = baselines[ids.getValue(key)]
                val want = expectedBaselines.getJSONObject(key)
                assertEquals("$id $key bestWeight", want.getDouble("bestWeight"), baseline!!.bestWeight, 1e-6)
                assertEquals(
                    "$id $key bestEstimatedOneRepMax",
                    want.getDouble("bestEstimatedOneRepMax"),
                    baseline.bestEstimatedOneRepMax,
                    1e-6
                )
            }

            // Every set is completed one minute after the previous one, in list order.
            val completed = mutableListOf<LiveCompletedSet>()
            val setIds = mutableListOf<Pair<String, List<String>>>()
            var clock = 1_000L
            case.getJSONArray("workout").objects().forEachIndexed { exerciseIndex, exercise ->
                val key = exercise.getString("exercise")
                val exerciseSetIds = mutableListOf<String>()
                exercise.getJSONArray("sets").objects().forEachIndexed { setIndex, set ->
                    val setId = "$exerciseIndex-$setIndex"
                    exerciseSetIds += setId
                    completed += LiveCompletedSet(
                        exerciseId = idOf(key),
                        setId = setId,
                        weight = set.getDouble("weight"),
                        reps = set.getInt("reps"),
                        completedAt = clock,
                        exerciseIndex = exerciseIndex,
                        setIndex = setIndex
                    )
                    clock += 60_000L
                }
                setIds += key to exerciseSetIds
            }
            val records = LivePersonalRecords.recordSetIds(completed, baselines)

            val expectedRecords = expected.getJSONArray("records").objects()
            assertEquals("$id exercise count", expectedRecords.size, setIds.size)
            expectedRecords.forEachIndexed { exerciseIndex, want ->
                assertEquals("$id exercise key", want.getString("exercise"), setIds[exerciseIndex].first)
                val flags = want.getJSONArray("sets")
                val actual = setIds[exerciseIndex].second.map { it in records }
                assertEquals(
                    "$id ${want.getString("exercise")} records",
                    List(flags.length()) { flags.getBoolean(it) },
                    actual
                )
            }
        }
    }

    private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/personal-records-v1.json")
        val file = if (direct.isFile) direct else File("../shared/personal-records-v1.json")
        check(file.isFile) { "Personal records contract was not found." }
        return JSONObject(file.readText())
    }
}
