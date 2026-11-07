package com.example.gymapp

import com.example.gymapp.data.repository.defaultContributionsForExercise
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/muscle-contributions-v1.json, the same cases the iOS suite runs. */
class MuscleContributionsGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 100)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val name = case.getString("name")
            val expectedJson = case.getJSONObject("contributions")
            val expected = expectedJson.keys().asSequence().associateWith { expectedJson.getDouble(it) }
            val actualList = defaultContributionsForExercise(name)
            val actual = actualList.associate { it.muscleId to it.weight }
            assertEquals("$name muscle ids", expected.keys, actual.keys)
            assertEquals("$name has duplicate muscle ids", actualList.size, actual.size)
            for ((muscle, weight) in expected) {
                assertEquals("$name $muscle", weight, actual.getValue(muscle), 1e-9)
            }
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/muscle-contributions-v1.json")
        val file = if (direct.isFile) direct else File("../shared/muscle-contributions-v1.json")
        check(file.isFile) { "Muscle contributions contract was not found." }
        return JSONObject(file.readText())
    }
}
