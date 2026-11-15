package com.example.gymapp.ui.viewmodel

import java.io.File
import java.time.ZoneId
import javax.xml.parsers.DocumentBuilderFactory
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Runs shared/today-presentation-v1.json against the Android resources and helpers: weekday labels, the
 * stat plural labels under the Today history numbers, and when the week comparison line is shown.
 */
class TodayLabelsGoldenTest {
    private val languages = mapOf("en" to "values", "ru" to "values-ru", "uk" to "values-uk")

    @Test
    fun weekdayLabelsMatchTheSharedContract() {
        val expected = contract().getJSONObject("weekdays")
        for ((language, folder) in languages) {
            val items = stringArray(folder, "weekday_short_labels")
            assertEquals(language, expected.getJSONArray(language).toList(), items)
        }
    }

    @Test
    fun statPluralLabelsMatchTheSharedContract() {
        val labels = contract().getJSONObject("statLabels")
        val resourceNames = mapOf("workouts" to "today_stat_workouts_label", "minutes" to "today_stat_minutes_label")
        for ((kind, resource) in resourceNames) {
            val cases = labels.getJSONArray(kind)
            assertTrue(cases.length() >= 6)
            for ((language, folder) in languages) {
                val forms = plurals(folder, resource)
                for (index in 0 until cases.length()) {
                    val case = cases.getJSONObject(index)
                    val count = case.getInt("count")
                    val form = pluralCategory(language, count)
                    assertEquals(
                        "$kind/$language/$count",
                        case.getString(language),
                        forms[form] ?: forms.getValue("other")
                    )
                }
            }
        }
    }

    @Test
    fun comparisonVisibilityMatchesTheSharedContract() {
        val cases = contract().getJSONArray("weekComparison")
        assertTrue(cases.length() >= 5)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            assertEquals(
                case.getString("id"),
                case.getBoolean("visible"),
                // A percentage exists whenever the compared week has volume; the counts decide.
                shouldShowWeekComparison(
                    currentWorkouts = case.getInt("currentWorkouts"),
                    previousWorkouts = case.getInt("comparisonWorkouts"),
                    percent = 0
                )
            )
        }
    }

    @Test
    fun theWeeklySummaryHidesTheComparisonAgainstAnEmptyWeek() {
        val zone = ZoneId.of("UTC")
        fun at(day: String): Long = java.time.LocalDateTime.parse("${day}T10:00:00").atZone(zone).toInstant().toEpochMilli()
        // Wednesday 2026-11-11; the previous week held one workout, this week none yet.
        val now = at("2026-11-11")
        val previousOnly = listOf(WeekVolumeSample(at("2026-11-03"), 1000.0))
        val empty = weekVolumeComparison(previousOnly, now, zone)
        assertEquals(-100, empty.percent)
        assertNull(empty.visiblePercent)
        val both = weekVolumeComparison(previousOnly + WeekVolumeSample(at("2026-11-09"), 1500.0), now, zone)
        assertEquals(50, both.visiblePercent)
    }

    private fun pluralCategory(language: String, count: Int): String = when (language) {
        "ru", "uk" -> when {
            count % 10 == 1 && count % 100 != 11 -> "one"
            count % 10 in 2..4 && count % 100 !in 12..14 -> "few"
            else -> "many"
        }
        else -> if (count == 1) "one" else "other"
    }

    private fun contract(): JSONObject {
        val direct = File("shared/today-presentation-v1.json")
        val file = if (direct.isFile) direct else File("../shared/today-presentation-v1.json")
        check(file.isFile) { "Today presentation contract was not found." }
        return JSONObject(file.readText())
    }

    private fun resources(folder: String): org.w3c.dom.Document {
        val direct = File("src/main/res/$folder/strings.xml")
        val file = if (direct.isFile) direct else File("app/src/main/res/$folder/strings.xml")
        check(file.isFile) { "$folder/strings.xml was not found." }
        return DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
    }

    private fun stringArray(folder: String, name: String): List<String> {
        val nodes = resources(folder).getElementsByTagName("string-array")
        for (i in 0 until nodes.length) {
            val element = nodes.item(i) as Element
            if (element.getAttribute("name") == name) {
                val items = element.getElementsByTagName("item")
                return (0 until items.length).map { items.item(it).textContent }
            }
        }
        error("$name missing in $folder")
    }

    private fun plurals(folder: String, name: String): Map<String, String> {
        val nodes = resources(folder).getElementsByTagName("plurals")
        for (i in 0 until nodes.length) {
            val element = nodes.item(i) as Element
            if (element.getAttribute("name") == name) {
                val items = element.getElementsByTagName("item")
                return (0 until items.length).associate {
                    (items.item(it) as Element).getAttribute("quantity") to items.item(it).textContent
                }
            }
        }
        error("$name missing in $folder")
    }

    private fun JSONArray.toList(): List<String> = (0 until length()).map { getString(it) }
}
