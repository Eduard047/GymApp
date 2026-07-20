package com.example.gymapp.data.catalog

import com.example.gymapp.util.RussianText
import java.util.Locale

data class BuiltInExerciseDefinition(
    val key: String,
    val nameEn: String,
    val nameUk: String,
    val legacyAliases: Set<String> = emptySet()
)

/**
 * Stable identities and localized display names for the exercises shipped by GymApp.
 *
 * Exercise rows and workout history intentionally keep their original raw names. This catalog is
 * only an identity/display layer, so enabling it does not rename existing data or split history.
 */
object BuiltInExerciseCatalog {
    val definitions: List<BuiltInExerciseDefinition> = listOf(
        BuiltInExerciseDefinition(
            key = "bench_press",
            nameEn = "Bench Press",
            nameUk = "Жим штанги лежачи",
            legacyAliases = setOf("жим лежачи")
        ),
        BuiltInExerciseDefinition(
            key = "incline_dumbbell_press",
            nameEn = "Incline Dumbbell Press",
            nameUk = "Жим гантелей на похилій лаві"
        ),
        BuiltInExerciseDefinition(
            key = "pull_up",
            nameEn = "Pull Up",
            nameUk = "Підтягування",
            legacyAliases = setOf("Pull-Up")
        ),
        BuiltInExerciseDefinition(
            key = "lat_pulldown",
            nameEn = "Lat Pulldown",
            nameUk = "Тяга верхнього блока",
            legacyAliases = setOf("Тяга верхнього блока до грудей", "Фронтальна тяга")
        ),
        BuiltInExerciseDefinition(
            key = "barbell_row",
            nameEn = "Barbell Row",
            nameUk = "Тяга штанги в нахилі"
        ),
        BuiltInExerciseDefinition(
            key = "squat",
            nameEn = "Squat",
            nameUk = "Присідання зі штангою",
            legacyAliases = setOf("Barbell Squat", "Присід зі штангою")
        ),
        BuiltInExerciseDefinition(
            key = "leg_press",
            nameEn = "Leg Press",
            nameUk = "Жим ногами у тренажері",
            legacyAliases = setOf("Жим ногами")
        ),
        BuiltInExerciseDefinition(
            key = "romanian_deadlift",
            nameEn = "Romanian Deadlift",
            nameUk = "Румунська тяга"
        ),
        BuiltInExerciseDefinition(
            key = "deadlift",
            nameEn = "Deadlift",
            nameUk = "Станова тяга"
        ),
        BuiltInExerciseDefinition(
            key = "shoulder_press",
            nameEn = "Shoulder Press",
            nameUk = "Жим над головою",
            legacyAliases = setOf("Overhead Press", "Жим сидячи над головою", "Жим сидячи")
        ),
        BuiltInExerciseDefinition(
            key = "lateral_raise",
            nameEn = "Lateral Raise",
            nameUk = "Підйоми гантелей через сторони",
            legacyAliases = setOf("Махи в сторони")
        ),
        BuiltInExerciseDefinition(
            key = "biceps_curl",
            nameEn = "Biceps Curl",
            nameUk = "Згинання рук на біцепс"
        ),
        BuiltInExerciseDefinition(
            key = "triceps_pushdown",
            nameEn = "Triceps Pushdown",
            nameUk = "Розгинання рук на блоці"
        ),
        BuiltInExerciseDefinition(
            key = "calf_raise",
            nameEn = "Calf Raise",
            nameUk = "Підйом на носки",
            legacyAliases = setOf("Підйом на носки стоячи")
        ),
        BuiltInExerciseDefinition(
            key = "plank",
            nameEn = "Plank",
            nameUk = "Планка"
        )
    )

    private val definitionsByKey = definitions.associateBy { it.key }
    private val definitionsByName = buildMap {
        definitions.forEach { definition ->
            sequenceOf(definition.nameEn, definition.nameUk)
                .plus(definition.legacyAliases.asSequence())
                .forEach { alias ->
                    val normalized = normalizeName(alias)
                    require(put(normalized, definition) == null) {
                        "Duplicate built-in exercise alias: $alias"
                    }
                }
        }
    }

    fun definitionForKey(key: String?): BuiltInExerciseDefinition? {
        return key
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.let(definitionsByKey::get)
    }

    fun definitionForName(rawName: String?): BuiltInExerciseDefinition? {
        val normalized = rawName?.let(::normalizeName).orEmpty()
        return definitionsByName[normalized]
    }

    fun inferKey(rawName: String?): String? = definitionForName(rawName)?.key

    /**
     * Resolves optional backup metadata without allowing it to override a recognized raw name.
     *
     * Backups are user-controlled input. A stale or hostile `catalogKey` must therefore never
     * turn a known exercise name into a different exercise and attach its sets to the wrong
     * history row. The supplied key is used only to recover a missing raw name. A present but
     * unknown raw name keeps its own identity even if untrusted metadata names a built-in exercise.
     */
    fun resolvedKey(catalogKey: String?, rawName: String?): String? {
        val cleanRawName = rawName?.trim().orEmpty()
        return if (cleanRawName.isNotEmpty()) {
            inferKey(cleanRawName)
        } else {
            definitionForKey(catalogKey)?.key
        }
    }

    fun canonicalNameForKey(key: String?): String? = definitionForKey(key)?.nameEn

    fun displayName(rawName: String, languageTag: String?): String {
        val definition = definitionForName(rawName) ?: return rawName
        return when {
            languageTag.equals("uk", ignoreCase = true) -> definition.nameUk
            languageTag.equals("ru", ignoreCase = true) -> RussianText.translate(definition.nameEn)
            else -> definition.nameEn
        }
    }

    private fun normalizeName(value: String): String {
        return value
            .lowercase(Locale.ROOT)
            .replace('ʼ', '\'')
            .replace('’', '\'')
            .replace(Regex("\\s+"), " ")
            .trim()
    }
}
