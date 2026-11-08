package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/recent-exercises-v1.json, the same cases the iOS suite runs. */
class RecentExercisesGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val history = case.getJSONArray("history").let { rows ->
                List(rows.length()) { i -> rows.getJSONObject(i).toEntry(i.toLong()) }
            }
            val eligible = case.getJSONArray("eligibleExerciseIds").toLongs().toSet()
            val actual = recentExerciseIds(history, eligible, case.getString("query"))
            val expected = case.getJSONArray("expected").toLongs()
            if (actual != expected) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals("Recent exercise mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun pickerNarrowingKeepsOrderAndCap() {
        val recent = (1L..12L).toList()
        assertEquals((3L..10L).toList(), recent.limitedToPicker((3L..20L).toSet()))
        assertEquals(emptyList<Long>(), recent.limitedToPicker(emptySet()))
    }

    private fun JSONArray.toLongs(): List<Long> = List(length()) { getLong(it) }

    private fun JSONObject.toEntry(setId: Long) = ExerciseHistoryEntry(
        setId = setId,
        sessionId = getLong("sessionId"),
        sessionDate = getLong("date"),
        exerciseId = getLong("exerciseId"),
        exerciseName = "Exercise",
        weight = 0.0,
        reps = 1,
        setOrderIndex = 0,
        blockOrderIndex = getInt("blockOrderIndex")
    )

    private fun contract(): JSONObject {
        val direct = File("shared/recent-exercises-v1.json")
        val file = if (direct.isFile) direct else File("../shared/recent-exercises-v1.json")
        check(file.isFile) { "Recent exercises contract was not found." }
        return JSONObject(file.readText())
    }
}
