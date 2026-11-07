package com.example.gymapp.util

import java.io.File
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/weight-format-v1.json, the same cases the iOS suite runs. */
class WeightFormatGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        val cases = root.getJSONArray("cases")
        val languages = root.getJSONArray("languages")
        assertTrue(cases.length() >= 9)
        assertTrue(languages.length() == 3)
        val mismatches = mutableListOf<String>()

        fun check(label: String, expected: String, actual: String) {
            if (expected != actual) {
                mismatches += "$label: expected ${escaped(expected)} but was ${escaped(actual)}"
            }
        }

        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val value = case.getDouble("value")
            check("$id input", case.getString("input"), formatWeightInput(value))
            for (languageIndex in 0 until languages.length()) {
                val language = languages.getString(languageIndex)
                val locale = Locale.forLanguageTag(language)
                check("$id display $language", case.getJSONObject("display").getString(language), formatWeightDisplay(value, locale))
                check("$id volume $language", case.getJSONObject("volume").getString(language), formatVolumeTotal(value, locale))
            }
        }
        assertEquals("Weight format mismatches", emptyList<String>(), mismatches)
    }

    private fun escaped(text: String): String =
        "\"" + text.map { if (it.code in 32..126) it.toString() else "\\u%04x".format(it.code) }.joinToString("") + "\""

    private fun contract(): JSONObject {
        val direct = File("shared/weight-format-v1.json")
        val file = if (direct.isFile) direct else File("../shared/weight-format-v1.json")
        check(file.isFile) { "Weight format contract was not found." }
        return JSONObject(file.readText())
    }
}
