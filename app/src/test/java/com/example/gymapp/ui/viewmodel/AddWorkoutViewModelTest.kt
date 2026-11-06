package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AddWorkoutViewModelTest {
    private fun summary(id: Long, setCount: Int) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = id, date = 1_000_000L - id, note = null),
        exerciseCount = if (setCount > 0) 1 else 0,
        setCount = setCount,
        totalVolume = 0.0
    )

    private fun preview(id: Long, setCount: Int) = WorkoutTemplatePreviewUiModel(
        sessionId = id,
        date = id,
        exerciseCount = if (setCount > 0) 1 else 0,
        setCount = setCount,
        totalVolume = 0.0
    )

    @Test
    fun repeatIsDisabledWhenOnlyActivityOnlySessionsExist() {
        assertFalse(canRepeatFromTemplates(emptyList()))
        assertFalse(canRepeatFromTemplates(listOf(preview(1, 0), preview(2, 0))))
    }

    @Test
    fun repeatIsEnabledWhenAnySessionHasSets() {
        assertTrue(canRepeatFromTemplates(listOf(preview(1, 0), preview(2, 3))))
    }

    @Test
    fun pickerSkipsActivityOnlySessionsBeforeApplyingTheCap() {
        val sessions = List(10) { summary(it.toLong(), 0) } +
            List(70) { summary(100L + it, 2) }

        val picked = pickableWorkoutTemplateSessions(sessions)

        assertEquals(60, picked.size)
        assertTrue(picked.all { it.setCount > 0 })
        assertEquals(100L, picked.first().session.id)
    }

    @Test
    fun typedNoteSurvivesApplyingATemplate() {
        assertEquals("My note", mergedTemplateNote("My note", "Source note"))
        assertEquals("My note", mergedTemplateNote("My note", null))
    }

    @Test
    fun blankNoteIsFilledFromTheTemplate() {
        assertEquals("Source note", mergedTemplateNote("", "Source note"))
        assertEquals("Source note", mergedTemplateNote("   ", "Source note"))
        assertEquals("", mergedTemplateNote("", null))
    }
}
