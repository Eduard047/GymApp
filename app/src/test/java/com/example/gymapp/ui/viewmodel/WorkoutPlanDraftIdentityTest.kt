package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Locks in that a persisted workout plan draft can never restore two blocks that share an id.
 * The parser is file-private, so it is reached by reflection to keep production visibility as is.
 */
class WorkoutPlanDraftIdentityTest {
    private fun parse(payload: String): Any? {
        val method = Class.forName("com.example.gymapp.ui.viewmodel.AddWorkoutViewModelKt")
            .getDeclaredMethod("parsePersistedWorkoutPlanDraft", String::class.java)
        method.isAccessible = true
        return method.invoke(null, payload)
    }

    @Suppress("UNCHECKED_CAST")
    private fun Any.restoredDrafts(): List<ExerciseInputState> {
        val getter = javaClass.getDeclaredMethod("getExerciseDrafts")
        getter.isAccessible = true
        return getter.invoke(this) as List<ExerciseInputState>
    }

    private fun exercise(draftId: Long) =
        """{"draftId":$draftId,"exerciseId":null,"sets":[{"weight":"60","reps":"8"}]}"""

    private fun payload(vararg exercises: String) =
        """{"schemaVersion":1,"workoutDate":1750000000000,"note":"",""" +
            """"smartWorkoutEffort":"Auto","isDirty":true,"exercises":[${exercises.joinToString(",")}]}"""

    @Test
    fun validDraftWithDistinctBlockIdsIsRestoredInOrder() {
        val restored = parse(payload(exercise(1), exercise(2), exercise(5)))
        assertNotNull(restored)
        assertEquals(listOf(1L, 2L, 5L), restored!!.restoredDrafts().map { it.draftId })
    }

    @Test
    fun draftWithTwoBlocksSharingAnIdIsRejected() {
        assertNull(parse(payload(exercise(3), exercise(3))))
        assertNull(parse(payload(exercise(1), exercise(2), exercise(1))))
    }

    @Test
    fun draftWithNonPositiveBlockIdIsRejected() {
        assertNull(parse(payload(exercise(0))))
        assertNull(parse(payload(exercise(1), exercise(-4))))
    }

    @Test
    fun restoredIdsAreUniqueSoTheNextFreshIdAboveTheMaxCannotCollide() {
        val restored = checkNotNull(parse(payload(exercise(2), exercise(9), exercise(4))))
        val ids = restored.restoredDrafts().map { it.draftId }
        // The view model resumes numbering at max + 1 after a restore.
        val nextDraftId = (ids.maxOrNull() ?: 0L) + 1L
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(10L, nextDraftId)
        assertEquals(false, nextDraftId in ids)
    }

    private fun Any.restoredDateExplicit(): Boolean {
        val getter = javaClass.getDeclaredMethod("getWorkoutDateExplicit")
        getter.isAccessible = true
        return getter.invoke(this) as Boolean
    }

    @Test
    fun draftSavedBeforeTheExplicitDateFlagRestoresAsDefaultDated() {
        assertEquals(false, checkNotNull(parse(payload(exercise(1)))).restoredDateExplicit())
    }

    @Test
    fun draftWithExplicitDateFlagRoundTrips() {
        val explicit = payload(exercise(1)).replace(
            "\"workoutDate\":1750000000000,", "\"workoutDate\":1750000000000,\"workoutDateExplicit\":true,"
        )
        assertEquals(true, checkNotNull(parse(explicit)).restoredDateExplicit())
        assertNull(parse(explicit.replace("\"workoutDateExplicit\":true,", "\"workoutDateExplicit\":true,\"extra\":1,")))
    }
}
