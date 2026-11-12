package com.example.gymapp.ui.screens

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/history-exercise-search-v1.json, the same cases the iOS suite runs. */
class HistoryExerciseSearchGoldenTest {
    private data class Workout(val id: String, val exerciseNames: List<String>)

    @Test
    fun sharedGoldenCasesMatchIos() {
        val contract = contract()
        val workouts = contract.getJSONArray("workouts").let { rows ->
            List(rows.length()) { index ->
                val row = rows.getJSONObject(index)
                Workout(row.getString("id"), row.getJSONArray("exerciseNames").toStrings())
            }
        }
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 12)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val actual = filterWorkoutsByExerciseQuery(workouts, case.getString("query")) { it.exerciseNames }
                .map(Workout::id)
            val expected = case.getJSONArray("expectedWorkoutIds").toStrings()
            if (actual != expected) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals("History search mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun displayLimitMatchesFixture() {
        assertEquals(contract().getInt("displayLimit"), HISTORY_SEARCH_DISPLAY_LIMIT)
    }

    @Test
    fun blankQueryReturnsTheSameList() {
        val workouts = listOf(Workout("a", listOf("Bench Press")))
        assertSame(workouts, filterWorkoutsByExerciseQuery(workouts, "  ") { it.exerciseNames })
    }

    private fun JSONArray.toStrings(): List<String> = List(length()) { getString(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/history-exercise-search-v1.json")
        val file = if (direct.isFile) direct else File("../shared/history-exercise-search-v1.json")
        check(file.isFile) { "History exercise search contract was not found." }
        return JSONObject(file.readText())
    }
}
