package com.example.gymapp.ui.viewmodel

import com.example.gymapp.util.formatSessionVolume
import java.io.File
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/active-volume-v1.json, the same cases the iOS suite runs. */
class ActiveWorkoutVolumeGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        val cases = root.getJSONArray("cases")
        val languages = root.getJSONArray("languages")
        assertTrue(cases.length() >= 8)
        assertEquals(3, languages.length())
        val mismatches = mutableListOf<String>()

        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val setsJson = case.getJSONArray("sets")
            val sets = (0 until setsJson.length()).map { setIndex ->
                val set = setsJson.getJSONObject(setIndex)
                val completed = set.getBoolean("completed")
                ActiveWorkoutSetUiState(
                    id = "$id-$setIndex",
                    orderIndex = setIndex,
                    weightInput = "",
                    repsInput = "",
                    isCompleted = completed,
                    completedAt = if (completed) 1L else null,
                    loggedWeight = set.getDouble("weight"),
                    loggedReps = set.getInt("reps")
                )
            }
            val volume = activeWorkoutCompletedVolume(sets)
            if (Math.abs(volume - case.getDouble("volume")) > 1e-9) {
                mismatches += "$id volume: expected ${case.getDouble("volume")} but was $volume"
            }
            if ((volume >= 0.5) != case.getBoolean("visible")) {
                mismatches += "$id visible: expected ${case.getBoolean("visible")} for $volume"
            }
            for (languageIndex in 0 until languages.length()) {
                val language = languages.getString(languageIndex)
                val expected = case.getJSONObject("text").getString(language)
                val actual = formatSessionVolume(volume, Locale.forLanguageTag(language))
                if (expected != actual) {
                    mismatches += "$id text $language: expected ${escaped(expected)} but was ${escaped(actual)}"
                }
            }
        }
        assertEquals("Active volume mismatches", emptyList<String>(), mismatches)
    }

    private fun escaped(text: String): String =
        "\"" + text.map { if (it.code in 32..126) it.toString() else "\\u%04x".format(it.code) }.joinToString("") + "\""

    private fun contract(): JSONObject {
        val direct = File("shared/active-volume-v1.json")
        val file = if (direct.isFile) direct else File("../shared/active-volume-v1.json")
        check(file.isFile) { "Active volume contract was not found." }
        return JSONObject(file.readText())
    }
}
