package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/warmup-ramp-v1.json, the same cases the iOS suite runs. */
class WarmupRampGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        assertEquals(root.getDouble("minimumAboveBarKg"), PlateCalculator.WARMUP_MIN_ABOVE_BAR, 0.0)
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() >= 8)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val actual = PlateCalculator.warmup(
                workingWeight = case.getDouble("workingWeight"),
                bar = case.getDouble("bar"),
                plates = doubles(case.getJSONArray("plates"))
            ).map { Triple(it.weight, it.reps, it.load.platesPerSide) }
            val steps = case.getJSONArray("steps")
            val expected = (0 until steps.length()).map { stepIndex ->
                val step = steps.getJSONObject(stepIndex)
                Triple(step.getDouble("weight"), step.getInt("reps"), doubles(step.getJSONArray("platesPerSide")))
            }
            if (actual != expected) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals("Warm-up ramp mismatches", emptyList<String>(), mismatches)
    }

    private fun doubles(array: JSONArray): List<Double> = (0 until array.length()).map { array.getDouble(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/warmup-ramp-v1.json")
        val file = if (direct.isFile) direct else File("../shared/warmup-ramp-v1.json")
        check(file.isFile) { "Warm-up ramp contract was not found." }
        return JSONObject(file.readText())
    }
}
