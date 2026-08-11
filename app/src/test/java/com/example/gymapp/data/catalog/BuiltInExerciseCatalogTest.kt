package com.example.gymapp.data.catalog

import com.example.gymapp.data.repository.normalizedExerciseName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BuiltInExerciseCatalogTest {
    @Test
    fun catalog_hasStableKeysAndBothDisplayLanguages() {
        val expected = listOf(
            Triple("bench_press", "Bench Press", "Жим штанги лежачи"),
            Triple("incline_dumbbell_press", "Incline Dumbbell Press", "Жим гантелей на похилій лаві"),
            Triple("pull_up", "Pull Up", "Підтягування"),
            Triple("assisted_dip", "Assisted Dip", "Віджимання на брусах у гравітроні"),
            Triple("lat_pulldown", "Lat Pulldown", "Тяга верхнього блока"),
            Triple("barbell_row", "Barbell Row", "Тяга штанги в нахилі"),
            Triple("squat", "Squat", "Присідання зі штангою"),
            Triple("leg_press", "Leg Press", "Жим ногами у тренажері"),
            Triple("romanian_deadlift", "Romanian Deadlift", "Румунська тяга"),
            Triple("deadlift", "Deadlift", "Станова тяга"),
            Triple("hip_abduction", "Hip Abduction", "Розведення ніг у тренажері"),
            Triple("shoulder_press", "Shoulder Press", "Жим над головою"),
            Triple("lateral_raise", "Lateral Raise", "Підйоми гантелей через сторони"),
            Triple("biceps_curl", "Biceps Curl", "Згинання рук на біцепс"),
            Triple("triceps_pushdown", "Triceps Pushdown", "Розгинання рук на блоці"),
            Triple("calf_raise", "Calf Raise", "Підйом на носки"),
            Triple("plank", "Plank", "Планка")
        )

        assertEquals(53, BuiltInExerciseCatalog.definitions.size)
        expected.forEach { (key, english, ukrainian) ->
            assertEquals(key, BuiltInExerciseCatalog.inferKey(english))
            assertEquals(key, BuiltInExerciseCatalog.inferKey(ukrainian))
            assertEquals(english, BuiltInExerciseCatalog.displayName(ukrainian, "en"))
            assertEquals(ukrainian, BuiltInExerciseCatalog.displayName(english, "uk"))
            assertEquals(english, BuiltInExerciseCatalog.canonicalNameForKey(key))
        }
    }

    @Test
    fun legacyAliases_areConservativeAndCaseInsensitive() {
        assertEquals("squat", BuiltInExerciseCatalog.inferKey("  BARBELL SQUAT "))
        assertEquals("squat", BuiltInExerciseCatalog.inferKey("Присід зі штангою"))
        assertEquals("bench_press", BuiltInExerciseCatalog.inferKey("жим лежачи"))
        assertEquals("lat_pulldown", BuiltInExerciseCatalog.inferKey("Фронтальна тяга"))
        assertEquals("shoulder_press", BuiltInExerciseCatalog.inferKey("Overhead Press"))
        assertEquals("hip_abduction", BuiltInExerciseCatalog.inferKey("разведение ног"))
        assertEquals("hip_abduction", BuiltInExerciseCatalog.inferKey("Разведение ног в тренажере"))
        assertEquals("assisted_dip", BuiltInExerciseCatalog.inferKey("підтягування з брусьями"))
        assertEquals("assisted_dip", BuiltInExerciseCatalog.inferKey("підтягування с брусьями"))
        assertEquals("assisted_dip", BuiltInExerciseCatalog.inferKey("підтягування с брусами"))
        assertEquals("dips", BuiltInExerciseCatalog.inferKey("брусья"))
        assertEquals("bench_press", BuiltInExerciseCatalog.inferKey("  BENCH\u00a0PRESS "))
        assertEquals("bench_press", BuiltInExerciseCatalog.inferKey("ЖИМ ЛЕЖАЧИ"))
        assertEquals("straight_arm_pulldown", BuiltInExerciseCatalog.inferKey("Журавель"))
        assertEquals(
            "Журавель — тяга прямими руками",
            BuiltInExerciseCatalog.displayName("Straight Arm Pulldown", "uk")
        )
        assertEquals(
            "Журавель — тяга прямыми руками",
            BuiltInExerciseCatalog.displayName("Straight Arm Pulldown", "ru")
        )
    }

    @Test
    fun everydaySearchAliases_areExposedButNeverBecomeExerciseIdentity() {
        val lateralRaise = BuiltInExerciseCatalog.definitionForKey("lateral_raise")
        assertTrue(
            BuiltInExerciseCatalog.searchAliasesForDefinition(lateralRaise)
                .contains("махи гантелями в стороны")
        )
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Lateral Raise").contains("lat raises"))
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Romanian Deadlift").contains("RDL"))
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Shoulder Press").contains("OHP"))
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Bulgarian Split Squat").contains("BSS"))
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Bulgarian Split Squat").contains("RFESS"))
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("Machine Chest Fly").contains("pec deck"))

        listOf(
            "махи гантелями в стороны",
            "бабочка",
            "pec deck",
            "OHP",
            "RDL",
            "BSS",
            "RFESS",
            "DB bench press",
            "BB row"
        ).forEach { searchOnlyAlias ->
            assertNull(searchOnlyAlias, BuiltInExerciseCatalog.inferKey(searchOnlyAlias))
        }
        assertTrue(BuiltInExerciseCatalog.searchAliasesForName("OHP").isEmpty())

        val allSearchAliases = BuiltInExerciseCatalog.definitions.flatMap { definition ->
            BuiltInExerciseCatalog.searchAliasesForDefinition(definition)
        }
        assertFalse(allSearchAliases.any { it.equals("DB", ignoreCase = true) })
        assertFalse(allSearchAliases.any { it.equals("BB", ignoreCase = true) })
        assertEquals(
            ExerciseSearchVocabulary.aliasesByKey.getValue("lateral_raise").toSet(),
            BuiltInExerciseCatalog.searchAliasesForDefinition(lateralRaise)
        )
    }

    @Test
    fun generatedVocabularyFacetsStayGroupedByMuscleAndEquipmentConcept() {
        val warmUp = BuiltInExerciseCatalog.definitionForKey("warm_up")!!
        val muscleConcepts = BuiltInExerciseCatalog
            .searchMuscleTermConceptsForDefinition(warmUp)
        assertTrue(muscleConcepts.any { concept -> concept.id == "shoulders" })
        assertTrue(muscleConcepts.any { concept -> concept.id == "hamstrings" })
        assertFalse(muscleConcepts.any { concept -> concept.terms.isEmpty() })

        val pulldown = BuiltInExerciseCatalog.definitionForKey("lat_pulldown")!!
        assertEquals(
            setOf("cable", "machine"),
            BuiltInExerciseCatalog.searchEquipmentTermConceptsForDefinition(pulldown)
                .map { concept -> concept.id }
                .toSet()
        )

    }

    @Test
    fun legacyVerticalPullAlias_keepsIdentityButIsExcludedFromUprightRowSearchNames() {
        val uprightRow = BuiltInExerciseCatalog.definitionForKey("upright_row")!!
        assertEquals("upright_row", BuiltInExerciseCatalog.inferKey("вертикальна тяга"))
        assertFalse(BuiltInExerciseCatalog.isIdentityNameSearchable(uprightRow, "вертикальна тяга"))
        assertTrue(BuiltInExerciseCatalog.isIdentityNameSearchable(uprightRow, "протяжка"))
    }

    @Test
    fun identityNormalizationIsNfcWhitespaceAwareButKeepsAccentsAndWidthStrict() {
        assertEquals("bíceps".normalizedExerciseName(), "bíceps".normalizedExerciseName())
        assertEquals("custom row".normalizedExerciseName(), "custom\u00a0row".normalizedExerciseName())
        assertEquals("custom row".normalizedExerciseName(), "\tcustom\u2007row\n".normalizedExerciseName())
        assertEquals("custom row".normalizedExerciseName(), "custom\u0085row".normalizedExerciseName())
        assertEquals("елка".normalizedExerciseName(), "ЁЛКА".normalizedExerciseName())
        assertEquals("rock'n'roll".normalizedExerciseName(), "Rock’NʼRoll".normalizedExerciseName())
        assertNotEquals("biceps".normalizedExerciseName(), "bíceps".normalizedExerciseName())
        assertNotEquals("biceps".normalizedExerciseName(), "Ｂiceps".normalizedExerciseName())
    }

    @Test
    fun unknownUserExercise_isNeverRenamed() {
        val custom = "My custom carry"
        assertNull(BuiltInExerciseCatalog.inferKey(custom))
        assertEquals(custom, BuiltInExerciseCatalog.displayName(custom, "en"))
        assertEquals(custom, BuiltInExerciseCatalog.displayName(custom, "uk"))
    }

    @Test
    fun recognizedRawName_winsOverConflictingOrMalformedBackupKey() {
        assertEquals(
            "squat",
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey = "bench_press",
                rawName = "Squat"
            )
        )
        assertEquals(
            "squat",
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey = "not-a-real-catalog-key",
                rawName = "Присідання зі штангою"
            )
        )
    }

    @Test
    fun validBackupKey_isFallbackOnlyWhenRawNameIsMissing() {
        assertNull(
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey = "bench_press",
                rawName = "Imported custom label"
            )
        )
        assertNull(
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey = "not-a-real-catalog-key",
                rawName = "Imported custom label"
            )
        )
        assertEquals(
            "bench_press",
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey = "bench_press",
                rawName = null
            )
        )
    }
}
