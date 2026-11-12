package com.example.gymapp.ui.screens

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/remaining-workout-estimate-v1.json, the same cases the iOS suite runs. */
class RemainingWorkoutEstimateGoldenTest {
    private val root = contract()

    @Test
    fun constantsMatchSharedContract() {
        assertEquals(root.getInt("minutesPerExercise"), RemainingWorkoutEstimate.MINUTES_PER_EXERCISE)
        assertEquals(root.getInt("minutesPerSet"), RemainingWorkoutEstimate.MINUTES_PER_SET)
    }

    @Test
    fun everySharedCaseMatches() {
        val cases = root.getJSONArray("cases")
        assertTrue("contract lists the 10 cases", cases.length() >= 10)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val exercises = case.getJSONArray("exercises")
            val remaining = List(exercises.length()) { exercises.getJSONObject(it).getInt("remainingSets") }
            val expected = case.opt("expected")
                ?.takeIf { it != JSONObject.NULL }
                ?.let { it as JSONObject }
                ?.let { RemainingWorkoutEstimate.Result(it.getInt("setsLeft"), it.getInt("minutes")) }
            val actual = RemainingWorkoutEstimate.estimate(remaining)
            if (expected != actual) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals("remaining-workout-estimate mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/remaining-workout-estimate-v1.json")
        val file = if (direct.isFile) direct else File("../shared/remaining-workout-estimate-v1.json")
        check(file.isFile) { "Remaining workout estimate contract was not found." }
        return JSONObject(file.readText())
    }
}
