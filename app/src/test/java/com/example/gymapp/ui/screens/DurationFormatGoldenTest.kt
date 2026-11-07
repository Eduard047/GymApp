package com.example.gymapp.ui.screens

import com.example.gymapp.util.DateTimeUtils
import java.io.File
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/duration-format-v1.json, the same cases the iOS suite runs. */
class DurationFormatGoldenTest {
    private val root = contract()
    private val languages = root.getJSONArray("languages").let { array -> List(array.length()) { array.getString(it) } }

    @Test
    fun compactDurationMatchesSharedCases() = checkLocalized("compactDuration") { seconds, locale ->
        DateTimeUtils.formatCompactDuration(seconds, locale)
    }

    @Test
    fun workoutDurationMatchesSharedCases() = checkLocalized("workoutDuration") { seconds, locale ->
        workoutDurationText(seconds, locale)
    }

    @Test
    fun elapsedTimerMatchesSharedCases() = checkPlain("elapsedTimer", "android") { seconds ->
        // The elapsed timer takes a locale; Latin digits must come out for every app language.
        val texts = languages.map { formatActiveWorkoutTime(seconds, Locale.forLanguageTag(it)) }
        assertEquals("elapsed $seconds differs by language", 1, texts.toSet().size)
        texts.first()
    }

    @Test
    fun restCountdownMatchesSharedCases() = checkPlain("restCountdown", "android") { seconds ->
        formatRestTime(seconds.toInt())
    }

    @Test
    fun garminDurationMatchesSharedCases() = checkPlain("garminDuration", "android") { seconds ->
        formatGarminDuration(seconds)
    }

    private fun cases(name: String) = root.getJSONObject("formatters").getJSONObject(name).getJSONArray("cases").also {
        assertTrue("$name needs the full second set", it.length() >= 11)
    }

    private fun checkLocalized(name: String, format: (Long, Locale) -> String) {
        assertEquals(3, languages.size)
        val cases = cases(name)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val seconds = case.getLong("seconds")
            for (language in languages) {
                val expected = case.getJSONObject("expected").getString(language)
                val actual = format(seconds, Locale.forLanguageTag(language))
                if (expected != actual) mismatches += "$name $seconds $language: expected \"$expected\" but was \"$actual\""
            }
        }
        assertEquals("$name mismatches", emptyList<String>(), mismatches)
    }

    private fun checkPlain(name: String, platform: String, format: (Long) -> String) {
        val cases = cases(name)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val seconds = case.getLong("seconds")
            val expected = if (case.has("expected")) case.getString("expected") else case.getString(platform)
            val actual = format(seconds)
            if (expected != actual) mismatches += "$name $seconds: expected \"$expected\" but was \"$actual\""
        }
        assertEquals("$name mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/duration-format-v1.json")
        val file = if (direct.isFile) direct else File("../shared/duration-format-v1.json")
        check(file.isFile) { "Duration format contract was not found." }
        return JSONObject(file.readText())
    }
}
