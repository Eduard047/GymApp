package com.example.gymapp.data.repository

import com.example.gymapp.util.TrainingProgram
import com.example.gymapp.util.TrainingProgramCodec
import com.example.gymapp.util.TrainingProgramSlot
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TrainingProgramCodecTest {
    private fun program(): TrainingProgram {
        val now = System.currentTimeMillis() - 1000
        return TrainingProgram(1, now, 2, "Strength", "active",
            (0 until 8).map { TrainingProgramSlot(it + 1L, now + it * 86_400_000L) })
    }

    @Test fun roundTripKeepsFutureDatesAndExactOwner() {
        val value = program()
        val raw = requireNotNull(TrainingProgramCodec.encode(value, "owner-a"))
        assertEquals(value, TrainingProgramCodec.decode(raw, "owner-a"))
        assertNull(TrainingProgramCodec.decode(raw, "owner-b"))
    }

    @Test fun rejectsMalformedTypesDuplicatesAndOversizedRecords() {
        val raw = requireNotNull(TrainingProgramCodec.encode(program(), "owner-a"))
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("days", "2") },
            { it.put("id", 1.5) },
            { it.put("extra", true) },
            { it.getJSONArray("slots").getJSONObject(1).put("id", 1) },
            { it.getJSONArray("slots").getJSONObject(0).put("date", Long.MAX_VALUE) },
            { it.getJSONArray("slots").getJSONObject(0).put("sessionId", 4)
              it.getJSONArray("slots").getJSONObject(1).put("sessionId", 4) }
        )
        mutations.forEach { mutate ->
            val value = JSONObject(raw); mutate(value)
            assertNull(TrainingProgramCodec.decode(value.toString(), "owner-a"))
        }
        assertNull(TrainingProgramCodec.decode(" ".repeat(32769), "owner-a"))
        assertNotNull(TrainingProgramCodec.decode(raw, "owner-a"))
    }
}
