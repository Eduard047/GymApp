package com.example.gymapp.ui.screens

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FriendWorkoutPickerSheetTest {
    @Test
    fun pickerIsRecentFirstBoundedAndExcludesEmptySessions() {
        val valid = (1L..105L).map { id -> session(id = id, date = id) }
        val empty = session(id = 999L, date = 999L, exerciseCount = 0, setCount = 0)
        val invalidId = session(id = 0L, date = 1_000L)

        val result = friendWorkoutPickerSessions(valid + empty + invalidId)

        assertEquals(MAX_FRIEND_WORKOUT_PICKER_SESSIONS, result.size)
        assertEquals(105L, result.first().session.id)
        assertEquals(6L, result.last().session.id)
        assertFalse(result.any { it.session.id == empty.session.id })
        assertFalse(result.any { it.session.id == invalidId.session.id })
    }

    private fun session(
        id: Long,
        date: Long,
        exerciseCount: Int = 3,
        setCount: Int = 9
    ) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = id, date = date, note = "Synthetic $id"),
        exerciseCount = exerciseCount,
        setCount = setCount,
        totalVolume = 1_000.0
    )
}
