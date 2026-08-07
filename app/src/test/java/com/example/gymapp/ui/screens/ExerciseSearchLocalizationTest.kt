package com.example.gymapp.ui.screens

import com.example.gymapp.data.entity.ExerciseEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExerciseSearchLocalizationTest {
    @Test
    fun russianBuiltInDisplayNameMatchesEnglishAndUkrainianStoredIdentity() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "жим штанги лежа"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Жим штанги лежачи", "жим штанги лежа"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Hammer Curl", "молоточные сгибания"))
    }

    @Test
    fun existingLanguagesAliasesAndCustomNamesRemainSearchable() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "bench"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "жим штанги лежачи"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Тяга верхнього блока до грудей", "фронтальна тяга"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Моё упражнение", "моё"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Моё упражнение", "мое"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Моё упражнение", "жим штанги"))
    }

    @Test
    fun reviewedLegacyAliasesSupportBoundedPartialSearchWithoutRestoringExcludedAliases() {
        val legacyPartialMatch = exerciseSearchMatch("Straight Arm Pulldown", "журав")

        assertTrue(legacyPartialMatch != null)
        assertEquals(ExerciseSearchMatchReasonKind.Alias, legacyPartialMatch!!.reason!!.kind)
        assertEquals("Журавель", legacyPartialMatch.reason!!.value)
        assertFalse(exerciseNameMatchesLocalizedQuery("Straight Arm Pulldown", "жу"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Upright Row", "вертикал"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Upright Row", "вертикальна тяга"))
    }

    @Test
    fun colloquialRussianUkrainianAndEnglishAliasesFindBuiltIns() {
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Lateral Raise",
                "махи в сторони с гантелями"
            )
        )
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Lateral Raise",
                "розведення гантелей в сторони"
            )
        )
        assertTrue(exerciseNameMatchesLocalizedQuery("Shoulder Press", "OHP"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Romanian Deadlift", "RDL"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Bulgarian Split Squat", "BSS"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Bulgarian Split Squat", "RFESS"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Machine Chest Fly", "pec deck"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Dumbbell Bench Press", "DB bench press"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Barbell Row", "BB row"))
    }

    @Test
    fun compactTransliteratedAndOneEditQueriesFindExpectedAliases() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Assisted Pull Up", "граветрон"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Machine Chest Fly", "pecdek"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Romanian Deadlift", "ruminka"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Lateral Raise", "mahi gantelyami"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Lateral Raise", "mahi s gantelyami"))
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Incline Bench Press",
                "zhim na verh grudi"
            )
        )
        assertTrue(exerciseNameMatchesLocalizedQuery("Lat Pulldown", "spina na bloke"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Squat", "sqaut"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Squat", "squt"))
        assertFalse(
            com.example.gymapp.data.catalog.BuiltInExerciseCatalog.definitions.any { definition ->
                exerciseNameMatchesLocalizedQuery(definition.nameEn, "дельфин")
            }
        )
    }

    @Test
    fun rankedSearchUsesRelevanceBeforeExistingFrequencyTieBreaks() {
        val exactCanonical = ExerciseEntity(id = 1, name = "Pec Deck")
        val exactAlias = ExerciseEntity(id = 2, name = "Machine Chest Fly")
        val partial = ExerciseEntity(id = 3, name = "Pec Deck Press")

        val ranked = filterAndSortExercises(
            exercises = listOf(partial, exactAlias, exactCanonical),
            exerciseWorkoutCounts = mapOf(partial.id to 100, exactAlias.id to 50),
            muscleIdsByExerciseName = emptyMap(),
            query = "pec deck",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.MostFrequent,
            favoritesOnly = false,
            languageTag = "en"
        )

        assertEquals(listOf(exactCanonical, exactAlias, partial), ranked)
        assertEquals(null, exerciseSearchMatch(exactCanonical.name, "pec deck")!!.reason)
        assertEquals(
            ExerciseSearchMatchReasonKind.Alias,
            exerciseSearchMatch(exactAlias.name, "pec deck")!!.reason!!.kind
        )
    }

    @Test
    fun semanticQueriesKeepConceptsTogetherAndRankSpecificAliasesFirst() {
        val rearDeltMatches = com.example.gymapp.data.catalog.BuiltInExerciseCatalog.definitions
            .filter { definition ->
                exerciseNameMatchesLocalizedQuery(definition.nameEn, "задняя дельта")
            }
            .map { definition -> definition.key }
        assertEquals(listOf("rear_delt_fly"), rearDeltMatches)

        assertTrue(exerciseNameMatchesLocalizedQuery("Incline Bench Press", "верх груди"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Incline Dumbbell Press", "верх груди"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Bench Press", "верх груди"))
        assertEquals(null, exerciseSearchMatch("Lat Pulldown", "верх груди"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Lat Pulldown", "spina blok"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Barbell Row", "spina blok"))
        assertFalse(
            com.example.gymapp.data.catalog.BuiltInExerciseCatalog.definitions.any { definition ->
                exerciseNameMatchesLocalizedQuery(definition.nameEn, "гантели штанга")
            }
        )

        val overheadExtension = ExerciseEntity(
            id = 1,
            name = "Overhead Dumbbell Triceps Extension"
        )
        val dumbbellBench = ExerciseEntity(id = 2, name = "Dumbbell Bench Press")
        val tricepsResults = filterAndSortExercises(
            exercises = listOf(dumbbellBench, overheadExtension),
            exerciseWorkoutCounts = mapOf(dumbbellBench.id to 100),
            muscleIdsByExerciseName = emptyMap(),
            query = "гантели трицепс",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.MostFrequent,
            favoritesOnly = false,
            languageTag = "ru"
        )
        assertEquals(overheadExtension, tricepsResults.first())
        assertEquals(
            ExerciseSearchMatchReasonKind.MuscleAndEquipment,
            exerciseSearchMatch("Lat Pulldown", "spina blok")!!.reason!!.kind
        )
    }

    @Test
    fun ambiguousEquipmentAbbreviationsDoNotFanOutByThemselves() {
        listOf("db", "bb", "DB DB", "BB BB", "дб").forEach { query ->
            assertFalse(
                com.example.gymapp.data.catalog.BuiltInExerciseCatalog.definitions.any { definition ->
                    exerciseNameMatchesLocalizedQuery(definition.nameEn, query)
                }
            )
        }
        assertTrue(exerciseNameMatchesLocalizedQuery("Dumbbell Bench Press", "DB bench press"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Barbell Row", "BB row"))
    }

    @Test
    fun searchIgnoresWordOrderConnectorsAndPunctuationAndHandlesInflections() {
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Lateral Raise",
                "гантелями по сторонам махи"
            )
        )
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Incline Dumbbell Press",
                "press with dumbbells on incline"
            )
        )
        assertTrue(exerciseNameMatchesLocalizedQuery("Machine Chest Fly", "PEC-DECK"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Weighted Side Bend", "нахили під гантелею"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Weighted Side Bend", "нахили або гантелею"))
    }

    @Test
    fun searchRejectsUnboundedOrConnectorOnlyQueries() {
        assertFalse(
            exerciseNameMatchesLocalizedQuery(
                "Romanian Deadlift",
                "R".repeat(EXERCISE_SEARCH_QUERY_MAX_CHARS + 1)
            )
        )
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Romanian Deadlift",
                List(EXERCISE_SEARCH_QUERY_MAX_TOKENS) { "RDL" }.joinToString(" ")
            )
        )
        assertFalse(
            exerciseNameMatchesLocalizedQuery(
                "Romanian Deadlift",
                List(EXERCISE_SEARCH_QUERY_MAX_TOKENS + 1) { "RDL" }.joinToString(" ")
            )
        )
        assertFalse(exerciseNameMatchesLocalizedQuery("Romanian Deadlift", "with and the"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Romanian Deadlift", "під або з"))
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "Romanian Deadlift",
                List(EXERCISE_SEARCH_QUERY_MAX_TOKENS) { "romanian" }.joinToString(" ")
            )
        )
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "x".repeat(49),
                "x".repeat(49)
            )
        )
        assertTrue(
            exerciseNameMatchesLocalizedQuery(
                "x".repeat(128),
                "x".repeat(EXERCISE_SEARCH_QUERY_MAX_CHARS)
            )
        )
        assertFalse(
            exerciseNameMatchesLocalizedQuery(
                "y".repeat(129),
                "y".repeat(129)
            )
        )
    }

    @Test
    fun verticalPulldownTermsDoNotMatchUprightRow() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Lat Pulldown", "вертикальная тяга"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Lat Pulldown", "вертикальна тяга"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Upright Row", "вертикальная тяга"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Upright Row", "вертикальна тяга"))
    }

    @Test
    fun sharedPickerFiltersFavoritesBodyAndSpecificMuscle() {
        val bench = ExerciseEntity(id = 1, name = "Bench Press", isFavorite = true)
        val squat = ExerciseEntity(id = 2, name = "Squat")
        val crunch = ExerciseEntity(id = 3, name = "Crunch", isFavorite = true)
        val mappings = mapOf(
            bench.name to setOf("chest", "triceps"),
            squat.name to setOf("quads", "glutes"),
            crunch.name to setOf("abs")
        )

        assertEquals(
            listOf(bench),
            filterAndSortExercises(
                exercises = listOf(bench, squat, crunch),
                exerciseWorkoutCounts = emptyMap(),
                muscleIdsByExerciseName = mappings,
                query = "",
                bodyFilter = ExerciseBodyFilter.Upper,
                muscleFilter = "chest",
                sortMode = ExerciseSortMode.Name,
                favoritesOnly = true,
                languageTag = "en"
            )
        )
    }

    @Test
    fun sharedPickerSortsByWorkoutFrequencyWithStableNameTieBreak() {
        val bench = ExerciseEntity(id = 1, name = "Bench Press")
        val squat = ExerciseEntity(id = 2, name = "Squat")
        val crunch = ExerciseEntity(id = 3, name = "Crunch")
        val exercises = listOf(squat, crunch, bench)

        val mostFrequent = filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = mapOf(bench.id to 4, squat.id to 1, crunch.id to 1),
            muscleIdsByExerciseName = emptyMap(),
            query = "",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.MostFrequent,
            favoritesOnly = false,
            languageTag = "en"
        )
        val leastFrequent = filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = mapOf(bench.id to 4, squat.id to 1, crunch.id to 1),
            muscleIdsByExerciseName = emptyMap(),
            query = "",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.LeastFrequent,
            favoritesOnly = false,
            languageTag = "en"
        )

        assertEquals(listOf(bench, crunch, squat), mostFrequent)
        assertEquals(listOf(crunch, squat, bench), leastFrequent)
    }
}
