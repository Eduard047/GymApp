package com.example.gymapp.ui.screens

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/exercise-search-v1.json, the same cases the iOS suite runs. */
class ExerciseSearchGoldenTest {
    @Test
    fun sharedTransliterationMatchesIos() {
        val cases = contract().getJSONArray("transliteration")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val actual = transliterateExerciseSearchToken(case.getString("input"))
            if (actual != case.getString("expected")) {
                mismatches += "${case.getString("id")}: expected ${case.getString("expected")} but was $actual"
            }
        }
        assertEquals("Transliteration mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun sharedTokenCasesMatchIos() {
        val cases = contract().getJSONArray("tokenCases")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val expectedArray = case.getJSONArray("tokens")
            val expected = List(expectedArray.length()) { expectedArray.getString(it) }
            val actual = exerciseSearchTokens(
                case.getString("query"),
                keepConnectorsWhenOnlyConnectors = true
            )
            if (actual != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was $actual"
            }
        }
        assertEquals("Search token mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/exercise-search-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-search-v1.json")
        check(file.isFile) { "Exercise search contract was not found." }
        return JSONObject(file.readText())
    }
}
