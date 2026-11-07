package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/best-set-v1.json, the same cases the iOS suite runs. */
class BestSetSelectionTest {
    @Test
    fun sharedCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val sets = case.getJSONArray("sets")
            val candidates = (0 until sets.length()).map { setIndex ->
                val set = sets.getJSONObject(setIndex)
                BestSetCandidate(
                    weight = set.getDouble("weight"),
                    reps = set.getInt("reps"),
                    isPersonalRecord = set.getBoolean("isPR")
                )
            }
            val expected = if (case.isNull("expectedBestIndex")) null else case.getInt("expectedBestIndex")
            val actual = BestSetSelection.bestIndex(candidates)
            if (actual != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was $actual"
            }
        }
        assertEquals("Best set mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/best-set-v1.json")
        val file = if (direct.isFile) direct else File("../shared/best-set-v1.json")
        check(file.isFile) { "Best set contract was not found." }
        return JSONObject(file.readText())
    }
}
