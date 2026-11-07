package com.example.gymapp.util

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MemoryCueStorage : ExerciseCueStorage {
    val values = linkedMapOf<String, String>()
    override fun get(key: String) = values[key]
    override fun put(key: String, value: String): Boolean { values[key] = value; return true }
    override fun remove(key: String): Boolean { values.remove(key); return true }
    override fun count() = values.size
    override fun clear(): Boolean { values.clear(); return true }
}

class ExerciseCueStoreTest {
    private val files = mutableMapOf<String, MemoryCueStorage>()
    private val store = ExerciseCueStore { name -> files.getOrPut(name) { MemoryCueStorage() } }

    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        assertEquals(root.getInt("maxCodePoints"), EXERCISE_CUE_MAX_CODE_POINTS)
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() >= 12)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val expected = if (case.isNull("stored")) null else case.getString("stored")
            val actual = normalizeExerciseCue(case.getString("input"))
            if (actual != expected) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals(emptyList<String>(), mismatches)
    }

    @Test
    fun savesTrimmedSingleLineTextAndReadsItBack() {
        assertEquals("seat 4 narrow", store.setCue("db_a", "catalog:row", "  seat 4\nnarrow "))
        assertEquals("seat 4 narrow", store.cue("db_a", "catalog:row"))
    }

    @Test
    fun limitIsCountedInCodePoints() {
        val stored = store.setCue("db_a", "k", "a".repeat(79) + "😀😀")
        assertEquals(80, stored!!.codePointCount(0, stored.length))
        assertEquals("a".repeat(79) + "😀", stored)
    }

    @Test
    fun emptyTextRemovesTheCue() {
        store.setCue("db_a", "k", "seat 4")
        assertNull(store.setCue("db_a", "k", " \n "))
        assertNull(store.cue("db_a", "k"))
        assertTrue(files.values.all { it.values.isEmpty() })
    }

    @Test
    fun cuesDoNotLeakAcrossAccounts() {
        store.setCue("db_a", "k", "mine")
        assertNull(store.cue("db_b", "k"))
        store.setCue("db_b", "k", "other")
        assertEquals("mine", store.cue("db_a", "k"))
        assertEquals("other", store.cue("db_b", "k"))
        assertEquals(2, files.size)
        assertNotEquals(exerciseCueStorageName("db_a"), exerciseCueStorageName("db_b"))
        assertFalse(exerciseCueStorageName("db_a")!!.contains("db_a"))
    }

    @Test
    fun clearAccountWipesOnlyThatAccount() {
        store.setCue("db_a", "k1", "one")
        store.setCue("db_a", "k2", "two")
        store.setCue("db_b", "k1", "keep")
        assertTrue(store.clearAccount("db_a"))
        assertNull(store.cue("db_a", "k1"))
        assertNull(store.cue("db_a", "k2"))
        assertEquals("keep", store.cue("db_b", "k1"))
    }

    @Test
    fun rejectsUnusableAccountOrKey() {
        assertNull(store.setCue("", "k", "x"))
        assertNull(store.setCue("db_a", "   ", "x"))
        assertNull(store.setCue("db_a", "k\u0000", "x"))
        assertFalse(store.clearAccount(""))
        assertTrue(files.values.all { it.values.isEmpty() })
    }

    @Test
    fun refusesNewCueBeyondTheEntryCapButStillEditsExisting() {
        repeat(EXERCISE_CUE_MAX_ENTRIES) { store.setCue("db_a", "k$it", "x") }
        assertNull(store.setCue("db_a", "extra", "x"))
        assertEquals("changed", store.setCue("db_a", "k0", "changed"))
    }

    private fun contract(): JSONObject {
        val direct = File("shared/exercise-cue-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-cue-v1.json")
        return JSONObject(file.readText())
    }
}
