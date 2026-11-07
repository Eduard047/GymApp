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
    override fun all(): Map<String, String> = values.toMap()
    override fun removeAll(keys: Collection<String>): Boolean { keys.forEach { values.remove(it) }; return true }
}

class ExerciseCueStoreTest {
    private val storage = MemoryCueStorage()
    private val store = ExerciseCueStore { storage }

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
    fun sharedIdentityKeyCasesMatchIos() {
        val root = contract()
        val usable = root.getJSONArray("usableIdentityKeys")
        val unusable = root.getJSONArray("unusableIdentityKeys")
        assertTrue(usable.length() >= 3 && unusable.length() >= 4)
        for (index in 0 until usable.length()) {
            assertTrue(usable.getString(index), isUsableExerciseCueKey(usable.getString(index)))
        }
        for (index in 0 until unusable.length()) {
            val key = unusable.getString(index)
            assertFalse(key, isUsableExerciseCueKey(key))
            assertEquals(key, ExerciseCueSaveResult.FAILED, store.setCue("db_a", key, "x"))
        }
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun savesTrimmedSingleLineTextAndReadsItBack() {
        assertEquals(ExerciseCueSaveResult.STORED, store.setCue("db_a", "catalog:row", "  seat 4\nnarrow "))
        assertEquals("seat 4 narrow", store.cue("db_a", "catalog:row"))
        assertEquals(mapOf("catalog:row" to "seat 4 narrow"), store.cues("db_a"))
    }

    @Test
    fun limitIsCountedInCodePoints() {
        store.setCue("db_a", "k", "a".repeat(79) + "😀😀")
        val stored = store.cue("db_a", "k")!!
        assertEquals(80, stored.codePointCount(0, stored.length))
        assertEquals("a".repeat(79) + "😀", stored)
    }

    @Test
    fun emptyTextRemovesTheCue() {
        store.setCue("db_a", "k", "seat 4")
        assertEquals(ExerciseCueSaveResult.REMOVED, store.setCue("db_a", "k", " \n "))
        assertNull(store.cue("db_a", "k"))
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun allAccountsShareOneFileWithHashedAccountPrefixedKeys() {
        store.setCue("db_a", "k", "mine")
        store.setCue("db_b", "k", "other")
        val hashA = exerciseCueAccountHash("db_a")!!
        val hashB = exerciseCueAccountHash("db_b")!!
        assertNotEquals(hashA, hashB)
        assertEquals(32, hashA.length)
        assertFalse(hashA.contains("db_a"))
        assertEquals(setOf("$hashA|k", "$hashB|k"), storage.values.keys)
        assertEquals("gym_exercise_cues_v1", EXERCISE_CUE_PREFERENCES_NAME)
        assertNull(store.cue("db_c", "k"))
        assertEquals("mine", store.cue("db_a", "k"))
        assertEquals("other", store.cue("db_b", "k"))
    }

    @Test
    fun clearAccountRemovesOnlyThatAccountsKeys() {
        store.setCue("db_a", "k1", "one")
        store.setCue("db_a", "k2", "two")
        store.setCue("db_b", "k1", "keep")
        assertTrue(store.clearAccount("db_a"))
        assertNull(store.cue("db_a", "k1"))
        assertNull(store.cue("db_a", "k2"))
        assertEquals("keep", store.cue("db_b", "k1"))
        assertEquals(1, storage.values.size)
    }

    @Test
    fun rejectsUnusableAccountOrKey() {
        assertEquals(ExerciseCueSaveResult.FAILED, store.setCue("", "k", "x"))
        assertEquals(ExerciseCueSaveResult.FAILED, store.setCue("db_a", "   ", "x"))
        assertEquals(ExerciseCueSaveResult.FAILED, store.setCue("db_a", "k\u0000", "x"))
        assertFalse(store.clearAccount(""))
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun refusesNewCueBeyondTheEntryCapButStillEditsExisting() {
        repeat(EXERCISE_CUE_MAX_ENTRIES) {
            assertEquals(ExerciseCueSaveResult.STORED, store.setCue("db_a", "k$it", "x"))
        }
        assertEquals(ExerciseCueSaveResult.TOO_MANY, store.setCue("db_a", "extra", "x"))
        assertNull(store.cue("db_a", "extra"))
        assertEquals(ExerciseCueSaveResult.STORED, store.setCue("db_a", "k0", "changed"))
        assertEquals("changed", store.cue("db_a", "k0"))
    }

    @Test
    fun capCountsOnlyThatAccountsKeys() {
        repeat(EXERCISE_CUE_MAX_ENTRIES) { store.setCue("db_a", "k$it", "x") }
        assertEquals(ExerciseCueSaveResult.STORED, store.setCue("db_b", "k", "x"))
        assertEquals(ExerciseCueSaveResult.REMOVED, store.setCue("db_a", "k1", ""))
        assertEquals(ExerciseCueSaveResult.STORED, store.setCue("db_a", "extra", "x"))
    }

    private fun contract(): JSONObject {
        val direct = File("shared/exercise-cue-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-cue-v1.json")
        return JSONObject(file.readText())
    }
}
