package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/machine-weights-v1.json, the same cases the iOS suite runs. */
class MachineWeightsTextGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 40)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val expected: List<Double>? = if (case.optBoolean("invalid", false)) {
                null
            } else {
                val weights = case.getJSONArray("weights")
                List(weights.length()) { weights.getDouble(it) }
            }
            val actual = MachineWeightsText.parse(case.getString("input"))
            if (actual != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was $actual"
            }
        }
        assertEquals("Machine weights mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun editorTextRoundTripsThroughTheParser() {
        val weights = listOf(0.0, 0.25, 2.5, 12.5, 100.0, 1_000_000.0, 0.1 + 0.2)
        val text = weights.joinToString("\n", transform = MachineWeightsText::format)
        assertEquals(listOf(0.0, 0.25, 0.3, 2.5, 12.5, 100.0, 1_000_000.0), MachineWeightsText.parse(text))
        assertEquals("0.3", MachineWeightsText.format(0.1 + 0.2))
        assertEquals("100", MachineWeightsText.format(100.0))
    }

    private fun contract(): JSONObject {
        val direct = File("shared/machine-weights-v1.json")
        val file = if (direct.isFile) direct else File("../shared/machine-weights-v1.json")
        check(file.isFile) { "Machine weights contract was not found." }
        return JSONObject(file.readText())
    }
}
