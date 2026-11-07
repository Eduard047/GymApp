package com.example.gymapp.ui.viewmodel

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/training-minutes-v1.json, the same cases the iOS suite runs. */
class TrainingMinutesGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 20)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val actual = estimateWorkoutMinutes(
                exerciseCount = case.getInt("exerciseCount"),
                setCount = case.getInt("setCount"),
                measuredDurationSeconds = if (case.isNull("durationSeconds")) null else case.getLong("durationSeconds"),
                note = if (case.isNull("note")) null else case.getString("note")
            )
            if (actual != case.getInt("expectedMinutes")) {
                mismatches += "${case.getString("id")}: expected ${case.getInt("expectedMinutes")} but was $actual"
            }
        }
        assertEquals("Training minutes mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/training-minutes-v1.json")
        val file = if (direct.isFile) direct else File("../shared/training-minutes-v1.json")
        check(file.isFile) { "Training minutes contract was not found." }
        return JSONObject(file.readText())
    }
}
