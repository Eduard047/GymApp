package com.example.gymapp.auth

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/friend-code-v1.json, the same cases the iOS suite runs. */
class FriendCodeGoldenTest {
    @Test
    fun sharedNormalizeCasesMatchIos() {
        val cases = contract().getJSONArray("normalizeCases")
        assertTrue(cases.length() >= 40)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val expected = if (case.isNull("normalized")) null else case.getString("normalized")
            val actual = normalizeSocialFriendCode(case.getString("input"))
            if (actual != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was $actual"
            }
        }
        assertEquals("Friend code normalization mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun sharedDisplayCasesMatchIos() {
        val cases = contract().getJSONArray("displayCases")
        assertTrue(cases.length() >= 3)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            assertEquals(
                case.getString("id"),
                case.getString("display"),
                formatSocialFriendCode(case.getString("canonical"))
            )
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/friend-code-v1.json")
        val file = if (direct.isFile) direct else File("../shared/friend-code-v1.json")
        check(file.isFile) { "Friend code contract was not found." }
        return JSONObject(file.readText())
    }
}
