package com.example.gymapp.data.catalog

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/exercise-identity-v1.json, the same cases the iOS suite runs. */
class ExerciseIdentityGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 20)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val input = case.getString("input")
            val expectedKey = if (case.isNull("catalogKey")) null else case.getString("catalogKey")

            assertEquals("$id normalized", case.getString("normalized"), normalizeExerciseIdentityName(input))
            assertEquals("$id inferKey", expectedKey, BuiltInExerciseCatalog.inferKey(input))
            if (case.getString("normalized").isNotEmpty()) {
                // The raw name is authoritative; untrusted catalogKey metadata never overrides it.
                assertEquals("$id resolvedKey", expectedKey, BuiltInExerciseCatalog.resolvedKey("bench_press", input))
                assertEquals("$id resolvedKey no metadata", expectedKey, BuiltInExerciseCatalog.resolvedKey(null, input))
            } else {
                // Whitespace-only raw names fall back to the supplied catalog key.
                assertEquals("$id resolvedKey falls back to catalogKey", "bench_press", BuiltInExerciseCatalog.resolvedKey("bench_press", input))
                assertEquals("$id resolvedKey null", null, BuiltInExerciseCatalog.resolvedKey(null, input))
            }
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/exercise-identity-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-identity-v1.json")
        check(file.isFile) { "Exercise identity contract was not found." }
        return JSONObject(file.readText())
    }
}
