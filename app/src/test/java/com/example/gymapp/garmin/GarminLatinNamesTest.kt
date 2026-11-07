package com.example.gymapp.garmin

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/garmin-latin-names-v1.json; iOS must pass the same cases. */
class GarminLatinNamesTest {
    private val fixture = fixture()

    // Fake catalog built from the fixture so the cases do not depend on the real catalog data.
    private val builtIns = object : GarminBuiltInNames {
        private val byName = HashMap<String, String>()
        private val reserved = HashSet<String>()

        init {
            val items = fixture.getJSONArray("builtIns")
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val nameEn = item.getString("nameEn")
                reserved += nameEn.lowercase()
                val names = item.getJSONArray("names")
                for (j in 0 until names.length()) {
                    byName[names.getString(j).lowercase()] = nameEn
                    reserved += names.getString(j).lowercase()
                }
            }
        }

        override fun nameEnFor(raw: String): String? = byName[raw.lowercase()]
        override fun isReservedLatin(latin: String): Boolean = latin.lowercase() in reserved
    }

    @Test
    fun kotlinTableMatchesTheSharedFixture() {
        val table = fixture.getJSONObject("transliteration")
        assertEquals(table.length(), GarminLatinNames.TABLE.size)
        table.keys().forEach { key ->
            assertEquals(key, table.getString(key), GarminLatinNames.TABLE[key.single()])
        }
        val dropped = fixture.getJSONArray("droppedCharacters")
        assertEquals(dropped.length(), GarminLatinNames.DROPPED.length)
        for (i in 0 until dropped.length()) {
            assertTrue(dropped.getString(i) in GarminLatinNames.DROPPED)
        }
        assertEquals(fixture.getInt("maxNameLength"), GarminLatinNames.MAX_LENGTH)
        assertEquals(fixture.getString("fallbackName"), GarminLatinNames.FALLBACK_NAME)
        assertEquals(fixture.getString("watchLanguage"), GARMIN_WATCH_LANGUAGE_TAG)
    }

    @Test
    fun assignCasesMatchTheFixture() {
        val cases = fixture.getJSONArray("assignCases")
        assertTrue(cases.length() >= 10)
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val id = case.getString("id")
            val assignment = GarminLatinNames.assign(
                names = case.getJSONArray("names").strings(),
                existing = case.getJSONArray("existing").entries(),
                builtIns = builtIns
            )
            val expected = case.getJSONObject("expected")
            assertEquals(id, expected.length(), assignment.latinByRaw.size)
            expected.keys().forEach { raw -> assertEquals("$id $raw", expected.getString(raw), assignment.latinByRaw[raw]) }
            assertEquals(id, case.getJSONArray("newEntries").entries(), assignment.newEntries)
            assignment.latinByRaw.values.forEach { assertTrue("$id ascii", GarminLatinNames.isAscii(it)) }
        }
    }

    @Test
    fun invertCasesMatchTheFixture() {
        val cases = fixture.getJSONArray("invertCases")
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val actual = GarminLatinNames.invert(
                latin = case.getString("latin"),
                table = case.getJSONArray("table").entries(),
                currentNames = case.getJSONArray("currentNames").strings(),
                builtIns = builtIns
            )
            val expected = if (case.isNull("expected")) null else case.getString("expected")
            assertEquals(case.getString("id"), expected, actual)
        }
    }

    @Test
    fun realCatalogMapsBuiltInUkrainianAndAliasNamesToEnglish() {
        val assignment = GarminLatinNames.assign(listOf("Станова тяга", "Push-Up", "Присед"), emptyList())
        assertEquals("Deadlift", assignment.latinFor("Станова тяга"))
        assertEquals("Push Up", assignment.latinFor("Push-Up"))
        assertEquals("Prysed", assignment.latinFor("Присед"))
        assertEquals(listOf(GarminLatinEntry("Prysed", "Присед")), assignment.newEntries)
    }

    @Test
    fun longNamesAreCutAndSuffixesStillFit() {
        val raw = "ж".repeat(200)
        val other = "ж".repeat(199) + "з"
        val assignment = GarminLatinNames.assign(listOf(raw, other), emptyList(), builtIns)
        val first = assignment.latinFor(raw)!!
        assertEquals(160, first.length)
        assertTrue(first.all { it == 'z' || it == 'h' })
        // "ж"*199+"з" is a different raw but its cut Latin form is identical -> suffix, still <= 160.
        val second = assignment.latinFor(other)!!
        assertTrue(second.length <= 160)
        assertTrue(second.endsWith(" 2"))
    }

    @Test
    fun roundTripCustomCyrillicNameBecomesLatinAndInvertsToTheSameExercise() {
        val exercises = listOf("Присед", "Жим лёжа", "Станова тяга", "My Row")
        val assignment = GarminLatinNames.assign(exercises, emptyList())
        val table = assignment.newEntries
        for (raw in exercises) {
            val latin = assignment.latinFor(raw)!!
            assertTrue(GarminLatinNames.isAscii(latin))
            // What the import does: table hit, else unambiguous inversion; built-in/ASCII keep their name
            // and are matched by the existing lookup (catalog key / exact name).
            val restored = GarminLatinNames.invert(latin, table, exercises) ?: latin
            if (raw == "Станова тяга") assertEquals("Deadlift", restored) else assertEquals(raw, restored)
        }
        // Without the table (other platform) the unambiguous inversion still finds the exercise.
        assertEquals(
            "Жим лёжа",
            GarminLatinNames.invert(assignment.latinFor("Жим лёжа")!!, emptyList(), exercises)
        )
        // An old queued workout with the Cyrillic name is left to the exact lookup.
        assertNull(GarminLatinNames.invert("Присед", table, exercises))
    }

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun JSONArray.entries(): List<GarminLatinEntry> = List(length()) {
        val item = getJSONObject(it)
        GarminLatinEntry(latin = item.getString("latin"), raw = item.getString("raw"))
    }

    private fun fixture(): JSONObject {
        val direct = File("shared/garmin-latin-names-v1.json")
        val file = if (direct.isFile) direct else File("../shared/garmin-latin-names-v1.json")
        check(file.isFile) { "Garmin Latin names fixture was not found." }
        return JSONObject(file.readText(Charsets.UTF_8))
    }
}
