package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/rest-duration-v1.json, the same cases the iOS suite runs. */
class RestDurationGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val actual = WorkoutRecommendationEngine.recommendedRestSeconds(case.getString("name"))
            if (actual != case.getInt("restSeconds")) {
                mismatches += "${case.getString("id")}: expected ${case.getInt("restSeconds")} but was $actual"
            }
        }
        assertEquals("Rest duration mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/rest-duration-v1.json")
        val file = if (direct.isFile) direct else File("../shared/rest-duration-v1.json")
        check(file.isFile) { "Rest duration contract was not found." }
        return JSONObject(file.readText())
    }
}
