package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    private fun exercise(id: Long, name: String) = ExerciseEntity(id = id, name = name)

    private fun entry(exerciseId: Long, date: Long, weight: Double = 50.0, order: Int = 0) =
        ExerciseHistoryEntry(
            setId = exerciseId * 1_000 + date + order,
            sessionId = date,
            sessionDate = date,
            exerciseId = exerciseId,
            exerciseName = "e$exerciseId",
            weight = weight,
            reps = 8,
            setOrderIndex = order
        )

    @Test
    fun presetTargetMusclesMatchTheIphonePresets() {
        assertEquals(setOf("chest", "shoulders", "triceps"), WorkoutTemplatePreset.Push.targetMuscles)
        assertEquals(
            setOf("lats", "upperBack", "biceps", "forearms"),
            WorkoutTemplatePreset.Pull.targetMuscles
        )
        val lowerBody = setOf("quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack", "abs")
        assertEquals(lowerBody, WorkoutTemplatePreset.Legs.targetMuscles)
        assertEquals(lowerBody, WorkoutTemplatePreset.Lower.targetMuscles)
        assertEquals(
            WorkoutTemplatePreset.Push.targetMuscles + WorkoutTemplatePreset.Pull.targetMuscles,
            WorkoutTemplatePreset.Upper.targetMuscles
        )
        assertTrue(WorkoutTemplatePreset.Deload.targetMuscles.isEmpty())
        assertEquals(6, WorkoutTemplatePreset.Upper.maxExercises)
        assertEquals(5, WorkoutTemplatePreset.Push.maxExercises)
        assertEquals(
            listOf("Push", "Pull", "Legs", "Upper", "Lower", "Deload"),
            WorkoutTemplatePreset.entries.map { it.name }
        )
    }

    @Test
    fun deloadWeightIsNinetyPercentRoundedToHalfKilos() {
        assertEquals(74.5, deloadWeight(82.5), 0.0)
        assertEquals(90.0, deloadWeight(100.0), 0.0)
        assertEquals(18.0, deloadWeight(20.0), 0.0)
        assertEquals(0.0, deloadWeight(0.0), 0.0)
        assertEquals(45.0, deloadWeight(50.0), 0.0)
    }

    @Test
    fun deloadWeightRoundsExactHalvesAwayFromZeroLikeSwift() {
        // 12.5 * 0.9 * 2 = 22.5; Swift rounds the half up to 23 (11.5 kg), a half-even round would give 11.0.
        assertEquals(11.5, deloadWeight(12.5), 0.0)
    }

    @Test
    fun deloadAddsOneRepAndCapsAtTenThousand() {
        assertEquals(11, deloadReps(10))
        assertEquals(1, deloadReps(0))
        assertEquals(10_000, deloadReps(10_000))
        assertEquals(10_000, deloadReps(9_999))
    }

    @Test
    fun deloadKeepsATypedNoteAndLabelsAnEmptyOne() {
        assertEquals("Heavy legs", deloadNote("Heavy legs", "Deload"))
        assertEquals("Deload", deloadNote("", "Deload"))
        assertEquals("  ", deloadNote("  ", "Deload"))
    }

    @Test
    fun presetPicksBestMatchingExercisesAndDropsUnrelatedOnes() {
        val muscles = mapOf(
            1L to setOf("chest", "triceps", "shoulders"),
            2L to setOf("chest"),
            3L to setOf("quads", "glutes"),
            4L to setOf("biceps")
        )
        val exercises = listOf(
            exercise(1, "Bench"), exercise(2, "Fly"), exercise(3, "Squat"), exercise(4, "Curl")
        )

        val push = selectPresetExercises(
            preset = WorkoutTemplatePreset.Push,
            exercises = exercises,
            history = emptyList(),
            muscleIdsFor = { muscles.getValue(it.id) }
        )

        assertEquals(listOf(1L, 2L), push.map { it.id })
        assertTrue(
            selectPresetExercises(
                WorkoutTemplatePreset.Deload, exercises, emptyList(), muscleIdsFor = { muscles.getValue(it.id) }
            ).isEmpty()
        )
    }

    @Test
    fun presetOrdersByLongestUntrainedThenName() {
        val exercises = listOf(
            exercise(1, "Bravo"), exercise(2, "alpha"), exercise(3, "Charlie"), exercise(4, "Delta")
        )
        val history = listOf(entry(1, date = 500), entry(1, date = 900), entry(3, date = 100))

        val picked = selectPresetExercises(
            preset = WorkoutTemplatePreset.Pull,
            exercises = exercises,
            history = history,
            muscleIdsFor = { setOf("lats") }
        )

        // Never trained first (name order, case-insensitive), then oldest last session first.
        assertEquals(listOf(2L, 4L, 3L, 1L), picked.map { it.id })
    }

    @Test
    fun presetKeepsFiveExercisesAndUpperKeepsSix() {
        val exercises = List(8) { exercise(it + 1L, "E${it + 1}") }

        fun pick(preset: WorkoutTemplatePreset) = selectPresetExercises(
            preset, exercises, emptyList(), muscleIdsFor = { setOf("chest", "lats") }
        )

        assertEquals(5, pick(WorkoutTemplatePreset.Push).size)
        assertEquals(6, pick(WorkoutTemplatePreset.Upper).size)
    }

    @Test
    fun morePreferredMusclesBeatAnOlderSession() {
        val exercises = listOf(exercise(1, "Old single"), exercise(2, "Recent double"))
        val muscles = mapOf(1L to setOf("chest"), 2L to setOf("chest", "triceps"))
        val history = listOf(entry(1, date = 10), entry(2, date = 999))

        val picked = selectPresetExercises(
            WorkoutTemplatePreset.Push, exercises, history, muscleIdsFor = { muscles.getValue(it.id) }
        )

        assertEquals(listOf(2L, 1L), picked.map { it.id })
    }

    @Test
    fun lastLoggedWeightUsesTheLastSetOfTheNewestSession() {
        val history = listOf(
            entry(1, date = 100, weight = 40.0, order = 0),
            entry(1, date = 200, weight = 55.0, order = 0),
            entry(1, date = 200, weight = 60.0, order = 1),
            entry(2, date = 300, weight = 99.0)
        )

        assertEquals(60.0, lastLoggedWeight(history, 1)!!, 0.0)
        assertNull(lastLoggedWeight(history, 3))
    }
}
