package com.example.gymapp.ui.screens

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NextSetFocusTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() > 0)
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val id = case.getString("id")
            val sets = case.getJSONArray("sets").let { array ->
                (0 until array.length()).map { index ->
                    val triple = array.getJSONArray(index)
                    NextSetFocusSet(triple.getInt(0), triple.getInt(1), triple.getBoolean(2))
                }
            }
            val recorded = case.getJSONArray("recorded").let { NextSetPosition(it.getInt(0), it.getInt(1)) }
            val expected = if (case.isNull("next")) {
                null
            } else {
                case.getJSONArray("next").let { NextSetPosition(it.getInt(0), it.getInt(1)) }
            }
            assertEquals(id, expected, NextSetFocus.next(sets, recorded))
        }
    }

    @Test
    fun recordedSetIsNeverItsOwnTargetEvenWhenMarkedPending() {
        val sets = listOf(NextSetFocusSet(0, 0, false))
        assertNull(NextSetFocus.next(sets, NextSetPosition(0, 0)))
    }

    @Test
    fun scrollDeltaIsZeroWhenRowIsFullyVisible() {
        assertEquals(0f, NextSetFocus.scrollDelta(100f, 200f, 0f, 800f), 0f)
        assertEquals(0f, NextSetFocus.scrollDelta(0f, 800f, 0f, 800f), 0f)
    }

    @Test
    fun scrollDeltaMovesPartlyHiddenRowIntoView() {
        // Cut off at the bottom: content moves up by the hidden part.
        assertEquals(60f, NextSetFocus.scrollDelta(700f, 860f, 0f, 800f), 0f)
        // Cut off at the top: content moves down.
        assertEquals(-40f, NextSetFocus.scrollDelta(-40f, 100f, 0f, 800f), 0f)
        // Fully below the viewport.
        assertEquals(400f, NextSetFocus.scrollDelta(1000f, 1200f, 0f, 800f), 0f)
    }

    @Test
    fun scrollDeltaAlignsTopOfRowTallerThanViewport() {
        assertEquals(50f, NextSetFocus.scrollDelta(50f, 1000f, 0f, 800f), 0f)
    }

    @Test
    fun failedRecordForAwaitingSetClearsPendingFocus() {
        assertTrue(NextSetFocus.recordFailureClearsAwaiting("a", "a", true, false))
    }

    @Test
    fun otherSetsStaleMessagesAndRestTimerFailuresKeepPendingFocus() {
        assertFalse(NextSetFocus.recordFailureClearsAwaiting("a", "b", true, false))
        assertFalse(NextSetFocus.recordFailureClearsAwaiting("a", "a", false, false))
        assertFalse(NextSetFocus.recordFailureClearsAwaiting("a", "a", true, true))
        assertFalse(NextSetFocus.recordFailureClearsAwaiting(null, null, true, false))
    }

    private fun contract(): JSONObject {
        val direct = File("shared/next-set-focus-v1.json")
        val file = if (direct.isFile) direct else File("../shared/next-set-focus-v1.json")
        return JSONObject(file.readText())
    }
}
