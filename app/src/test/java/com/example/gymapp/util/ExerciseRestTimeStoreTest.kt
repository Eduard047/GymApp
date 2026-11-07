package com.example.gymapp.util

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MemoryRestStorage : ExerciseRestStorage {
    val values = linkedMapOf<String, String>()
    override fun get(key: String) = values[key]
    override fun put(key: String, value: String): Boolean { values[key] = value; return true }
    override fun remove(key: String): Boolean { values.remove(key); return true }
    override fun all(): Map<String, String> = values.toMap()
    override fun removeAll(keys: Collection<String>): Boolean { keys.forEach { values.remove(it) }; return true }
}

class ExerciseRestTimeStoreTest {
    private val storage = MemoryRestStorage()
    private val store = ExerciseRestTimeStore { storage }

    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        assertEquals(root.getInt("minSeconds"), EXERCISE_REST_MIN_SECONDS)
        assertEquals(root.getInt("maxSeconds"), EXERCISE_REST_MAX_SECONDS)
        assertEquals(root.getInt("stepSeconds"), EXERCISE_REST_STEP_SECONDS)
        assertEquals(root.getInt("maxEntries"), EXERCISE_REST_MAX_ENTRIES)
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() >= 10)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val stored = if (case.isNull("stored")) null else case.getInt("stored")
            val normalized = if (case.isNull("normalized")) null else case.getInt("normalized")
            val id = case.getString("id")
            if (normalizeExerciseRestSeconds(stored) != normalized) mismatches += "$id: normalized"
            val effective = effectiveExerciseRestSeconds(stored, case.getInt("defaultSeconds"))
            if (effective != case.getInt("effectiveSeconds")) mismatches += "$id: effective was $effective"
            assertTrue(id, isValidActiveWorkoutRestSeconds(effective))
        }
        assertEquals(emptyList<String>(), mismatches)
    }

    @Test
    fun sharedIdentityKeyCasesMatchIos() {
        val root = contract()
        val usable = root.getJSONArray("usableIdentityKeys")
        val unusable = root.getJSONArray("unusableIdentityKeys")
        for (index in 0 until usable.length()) {
            assertEquals(usable.getString(index), ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", usable.getString(index), 60))
        }
        for (index in 0 until unusable.length()) {
            val key = unusable.getString(index)
            assertEquals(key, ExerciseRestSaveResult.FAILED, store.setRestSeconds("db_a", key, 60))
            assertNull(key, store.restSeconds("db_a", key))
        }
        assertEquals(usable.length(), storage.values.size)
    }

    @Test
    fun savesClampedSecondsAndReadsThemBack() {
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "catalog:row", 90))
        assertEquals(90, store.restSeconds("db_a", "catalog:row"))
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "catalog:row", 100_000))
        assertEquals(EXERCISE_REST_MAX_SECONDS, store.restSeconds("db_a", "catalog:row"))
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "catalog:row", 3))
        assertEquals(EXERCISE_REST_MIN_SECONDS, store.restSeconds("db_a", "catalog:row"))
        assertEquals(mapOf("catalog:row" to EXERCISE_REST_MIN_SECONDS), store.restTimes("db_a"))
    }

    @Test
    fun aTamperedStoredValueIsClampedOrIgnoredOnRead() {
        val prefix = exerciseRestAccountHash("db_a")!! + "|"
        storage.values[prefix + "huge"] = "9999999"
        storage.values[prefix + "junk"] = "abc"
        storage.values[prefix + "zero"] = "0"
        assertEquals(EXERCISE_REST_MAX_SECONDS, store.restSeconds("db_a", "huge"))
        assertNull(store.restSeconds("db_a", "junk"))
        assertNull(store.restSeconds("db_a", "zero"))
        assertEquals(mapOf("huge" to EXERCISE_REST_MAX_SECONDS), store.restTimes("db_a"))
    }

    @Test
    fun nullOrNonPositiveRemovesTheCustomRest() {
        store.setRestSeconds("db_a", "k", 60)
        assertEquals(ExerciseRestSaveResult.REMOVED, store.setRestSeconds("db_a", "k", null))
        assertNull(store.restSeconds("db_a", "k"))
        assertTrue(storage.values.isEmpty())
        store.setRestSeconds("db_a", "k", 60)
        assertEquals(ExerciseRestSaveResult.REMOVED, store.setRestSeconds("db_a", "k", 0))
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun allAccountsShareOneFileWithHashedAccountPrefixedKeys() {
        store.setRestSeconds("db_a", "k", 60)
        store.setRestSeconds("db_b", "k", 120)
        val hashA = exerciseRestAccountHash("db_a")!!
        val hashB = exerciseRestAccountHash("db_b")!!
        assertNotEquals(hashA, hashB)
        assertEquals(32, hashA.length)
        assertFalse(hashA.contains("db_a"))
        assertNotEquals(exerciseCueAccountHash("db_a"), hashA)
        assertEquals(setOf("$hashA|k", "$hashB|k"), storage.values.keys)
        assertEquals("gym_exercise_rest_v1", EXERCISE_REST_PREFERENCES_NAME)
        assertNull(store.restSeconds("db_c", "k"))
        assertEquals(60, store.restSeconds("db_a", "k"))
        assertEquals(120, store.restSeconds("db_b", "k"))
    }

    @Test
    fun clearAccountRemovesOnlyThatAccountsKeys() {
        store.setRestSeconds("db_a", "k1", 60)
        store.setRestSeconds("db_a", "k2", 75)
        store.setRestSeconds("db_b", "k1", 90)
        assertTrue(store.clearAccount("db_a"))
        assertNull(store.restSeconds("db_a", "k1"))
        assertNull(store.restSeconds("db_a", "k2"))
        assertEquals(90, store.restSeconds("db_b", "k1"))
        assertEquals(1, storage.values.size)
    }

    @Test
    fun rejectsUnusableAccountOrKey() {
        assertEquals(ExerciseRestSaveResult.FAILED, store.setRestSeconds("", "k", 60))
        assertFalse(store.clearAccount(""))
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun refusesNewEntryBeyondTheCapButStillEditsExisting() {
        repeat(EXERCISE_REST_MAX_ENTRIES) {
            assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "k$it", 60))
        }
        assertEquals(ExerciseRestSaveResult.TOO_MANY, store.setRestSeconds("db_a", "extra", 60))
        assertNull(store.restSeconds("db_a", "extra"))
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "k0", 120))
        assertEquals(120, store.restSeconds("db_a", "k0"))
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_b", "k", 60))
        assertEquals(ExerciseRestSaveResult.REMOVED, store.setRestSeconds("db_a", "k1", null))
        assertEquals(ExerciseRestSaveResult.STORED, store.setRestSeconds("db_a", "extra", 60))
    }

    private fun contract(): JSONObject {
        val direct = File("shared/exercise-rest-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-rest-v1.json")
        return JSONObject(file.readText())
    }
}
