package com.example.gymapp

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.legacyNameGuessContributions
import com.example.gymapp.data.repository.muscleContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.planAutoSeededMuscleMappingRepairs
import com.example.gymapp.data.repository.toManualContributionMap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MuscleMappingCatalogTest {
    private fun muscles(name: String): Set<String> =
        muscleContributionsForExercise(name).map { it.muscleId }.toSet()

    private fun stored(name: String, vararg rows: Pair<String, Double>) = rows.map { (muscle, weight) ->
        ExerciseMuscleMappingEntity(
            exerciseNameKey = name.normalizedExerciseName(),
            exerciseName = name,
            muscleId = muscle,
            weight = weight,
            updatedAt = 1L
        )
    }

    @Test
    fun everyBuiltInExerciseHasMusclesMatchingItsCatalogDefinition() {
        val known = MUSCLE_DEFINITIONS.map { it.id }.toSet()
        BuiltInExerciseCatalog.definitions.forEach { definition ->
            listOf(definition.nameEn, definition.nameUk).forEach { name ->
                val ids = muscles(name)
                assertTrue("$name must have muscles", ids.isNotEmpty())
                assertEquals("$name must follow the catalog", definition.muscleIds.filter { it in known }.toSet(), ids)
                // Appears under every muscle group filter its definition lists.
                definition.muscleIds.forEach { assertTrue("$name missing $it", it in ids) }
            }
        }
    }

    @Test
    fun spotChecksMatchExpectedGroups() {
        assertTrue("chest" in muscles("Push Up"))
        assertTrue("chest" in muscles("Dips") && "triceps" in muscles("Dips"))
        assertTrue("adductors" in muscles("Hip Adduction"))
        assertTrue("shoulders" in muscles("Upright Row"))
        assertFalse("chest" in muscles("Shoulder Press"))
        assertFalse("chest" in muscles("French Press"))
        assertTrue("upperBack" in muscles("Face Pull"))
        assertTrue("adductors" in muscles("Squat"))
    }

    @Test
    fun catalogPrimaryMuscleOutweighsSecondary() {
        val weights = defaultContributionsForExercise("Squat").associate { it.muscleId to it.weight }
        assertEquals(1.0, weights.getValue("quads"), 1e-9)
        assertTrue(weights.getValue("glutes") < 1.0)
    }

    @Test
    fun customExerciseFallsBackToNameGuessing() {
        assertTrue("biceps" in muscles("My Special Curl"))
    }

    @Test
    fun emptyManualMappingFallsBackToDefault() {
        val manual = listOf(
            ExerciseMuscleMappingEntity("push up", "Push Up", "unknownMuscle", 1.0, 1L)
        ).toManualContributionMap()
        assertFalse(manual.containsKey("push up"))
        assertTrue("chest" in muscleContributionsForExercise("Push Up", manual).map { it.muscleId })
        val explicitEmpty = mapOf("push up" to emptyList<com.example.gymapp.data.repository.MuscleContribution>())
        assertTrue("chest" in muscleContributionsForExercise("Push Up", explicitEmpty).map { it.muscleId })
    }

    @Test
    fun repairReplacesOnlyUntouchedAutoSeededMappings() {
        // Old auto-seed for "Squat" (name guess) misses adductors.
        val oldGuess = legacyNameGuessContributions("Squat")
        val untouched = stored("Squat", *oldGuess.map { it.muscleId to it.weight }.toTypedArray())
        val repairs = planAutoSeededMuscleMappingRepairs(listOf("Squat"), untouched)
        assertEquals(1, repairs.size)
        assertTrue("adductors" in repairs.single().contributions.map { it.muscleId })

        // Applying the repair is idempotent.
        val repaired = stored("Squat", *repairs.single().contributions.map { it.muscleId to it.weight }.toTypedArray())
        assertTrue(planAutoSeededMuscleMappingRepairs(listOf("Squat"), repaired).isEmpty())

        // User customization (differs from the old guess) is untouched.
        val custom = stored("Squat", "quads" to 1.0, "calves" to 0.4)
        assertTrue(planAutoSeededMuscleMappingRepairs(listOf("Squat"), custom).isEmpty())

        // User-saved mappings (all weights 1.0) are never treated as auto-seeded.
        val saved = stored("Squat", "quads" to 1.0, "glutes" to 1.0)
        assertTrue(planAutoSeededMuscleMappingRepairs(listOf("Squat"), saved).isEmpty())

        // Custom (non-catalog) exercises are never repaired.
        val customName = "My Special Curl"
        val customGuess = legacyNameGuessContributions(customName)
        val customStored = stored(customName, *customGuess.map { it.muscleId to it.weight }.toTypedArray())
        assertTrue(planAutoSeededMuscleMappingRepairs(listOf(customName), customStored).isEmpty())
    }
}
