package com.example.gymapp.auth

import com.example.gymapp.ui.screens.sanitizeSignUpDisplayNameDraft
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/display-name-v1.json, the same cases the iOS suite and the node mirror test run. */
class SignUpDisplayNameGoldenTest {
    @Test
    fun sharedNameCasesMatchIosAndServerRules() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 40)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val actual = checkSignUpDisplayName(case.getString("input"))
            if (case.isNull("normalized")) {
                val expected = when (case.getString("reason")) {
                    "length" -> SignUpDisplayNameRejection.LENGTH
                    "characters" -> SignUpDisplayNameRejection.CHARACTERS
                    else -> SignUpDisplayNameRejection.SERVER_RULES
                }
                if (actual != SignUpDisplayNameCheck.Rejected(expected)) {
                    mismatches += "$id: expected rejected($expected) but was $actual"
                }
            } else if (actual != SignUpDisplayNameCheck.Valid(case.getString("normalized"))) {
                mismatches += "$id: expected ${case.getString("normalized")} but was $actual"
            }
        }
        assertEquals("Sign-up display name mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun sharedDraftCasesMatchIos() {
        val cases = contract().getJSONArray("draftCases")
        assertTrue(cases.length() >= 5)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            assertEquals(
                case.getString("id"),
                case.getString("draft"),
                sanitizeSignUpDisplayNameDraft(case.getString("input"))
            )
        }
    }

    @Test
    fun rejectionMessagesAreTheLocalizedContractStrings() {
        assertEquals(
            "Name can't contain links or long numbers and needs a letter or digit.",
            SignUpDisplayNameRejection.SERVER_RULES.message()
        )
    }

    private fun contract(): JSONObject {
        val direct = File("shared/display-name-v1.json")
        val file = if (direct.isFile) direct else File("../shared/display-name-v1.json")
        check(file.isFile) { "Display name contract was not found." }
        return JSONObject(file.readText())
    }
}
