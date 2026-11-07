package com.example.gymapp.data.repository

import com.example.gymapp.util.MAX_ACTIVE_WORKOUT_REST_SECONDS
import com.example.gymapp.util.MIN_ACTIVE_WORKOUT_REST_SECONDS
import com.example.gymapp.util.activeWorkoutAdjustedRestSeconds
import com.example.gymapp.util.isValidActiveWorkoutRestSeconds
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

    @Test
    fun sharedRestLimitsMatchIos() {
        val limits = contract().getJSONObject("restLimits")
        assertEquals(limits.getInt("minSeconds"), MIN_ACTIVE_WORKOUT_REST_SECONDS)
        assertEquals(limits.getInt("maxSeconds"), MAX_ACTIVE_WORKOUT_REST_SECONDS)
        val valid = limits.getJSONArray("validCases")
        assertTrue(valid.length() >= 6)
        for (index in 0 until valid.length()) {
            val case = valid.getJSONObject(index)
            assertEquals(
                case.getString("id"),
                case.getBoolean("valid"),
                isValidActiveWorkoutRestSeconds(case.getInt("seconds"))
            )
        }
        val adjust = limits.getJSONArray("adjustCases")
        assertTrue(adjust.length() >= 11)
        for (index in 0 until adjust.length()) {
            val case = adjust.getJSONObject(index)
            assertEquals(
                case.getString("id"),
                case.getInt("expectedSeconds"),
                activeWorkoutAdjustedRestSeconds(
                    case.getInt("remainingSeconds"),
                    case.getInt("deltaSeconds")
                )
            )
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/rest-duration-v1.json")
        val file = if (direct.isFile) direct else File("../shared/rest-duration-v1.json")
        check(file.isFile) { "Rest duration contract was not found." }
        return JSONObject(file.readText())
    }
}
