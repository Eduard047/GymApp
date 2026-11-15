package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/workout-note-v1.json, the same cases the iOS suite runs. */
class WorkoutNoteGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val contract = contract()
        assertEquals(WorkoutDataLimits.MAX_NOTE_LENGTH, contract.getInt("maxCodePoints"))
        assertEquals(WorkoutDataLimits.MAX_NOTE_BYTES, contract.getInt("maxUtf8Bytes"))
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 18)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val name = case.getString("name")
            val input = text(case.get("input"))
            val valid = case.getBoolean("valid")
            val actualFailure = WorkoutDataLimits.noteFailure(input)
            val actualValid = actualFailure == null
            if (actualValid != valid) {
                mismatches += "$name: expected valid=$valid but was $actualValid"
                continue
            }
            if (!valid) {
                val expectedFailure = when (case.getString("failure")) {
                    "tooLong" -> WorkoutDataLimits.NoteFailure.TOO_LONG
                    "controlCharacter" -> WorkoutDataLimits.NoteFailure.CONTROL_CHARACTER
                    else -> error("Unknown failure in case $name")
                }
                if (actualFailure != expectedFailure) {
                    mismatches += "$name: expected failure=$expectedFailure but was $actualFailure"
                }
            }
            if (valid) {
                val expected = if (case.isNull("stored")) null else text(case.get("stored"))
                val actual = normalizedWorkoutNote(input)
                if (actual != expected) mismatches += "$name: stored mismatch"
            }
        }
        assertEquals("Workout note mismatches", emptyList<String>(), mismatches)
    }

    private fun text(value: Any): String =
        if (value is JSONObject) value.getString("repeat").repeat(value.getInt("count")) else value as String

    private fun contract(): JSONObject {
        val direct = File("shared/workout-note-v1.json")
        val file = if (direct.isFile) direct else File("../shared/workout-note-v1.json")
        check(file.isFile) { "Workout note contract was not found." }
        return JSONObject(file.readText())
    }
}
