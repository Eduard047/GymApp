package com.example.gymapp.data.catalog

import com.example.gymapp.util.RussianText
import java.util.Locale

data class BuiltInExerciseDefinition(
    val key: String,
    val nameEn: String,
    val nameUk: String,
    val muscleIds: Set<String>,
    val legacyAliases: Set<String> = emptySet(),
    val introducedInSeedVersion: Int = 1
)

/**
 * Stable identities and localized display names for the exercises shipped by GymApp.
 *
 * Exercise rows and workout history intentionally keep their original raw names. This catalog is
 * only an identity/display layer, so enabling it does not rename existing data or split history.
 */
object BuiltInExerciseCatalog {
    const val SEED_VERSION: Int = 3

    val definitions: List<BuiltInExerciseDefinition> = listOf(
        definition("bench_press", "Bench Press", "Жим штанги лежачи", "chest", "triceps", "shoulders", aliases = setOf("жим лежачи")),
        definition("dumbbell_bench_press", "Dumbbell Bench Press", "Жим гантелей лежачи", "chest", "triceps", "shoulders", aliases = setOf("гантелі лежачи")),
        definition("incline_dumbbell_press", "Incline Dumbbell Press", "Жим гантелей на похилій лаві", "chest", "shoulders", "triceps"),
        definition("incline_bench_press", "Incline Bench Press", "Жим штанги на похилій лаві", "chest", "shoulders", "triceps"),
        definition("chest_fly_machine", "Machine Chest Fly", "Зведення рук у тренажері", "chest", "shoulders", aliases = setOf("метелик в середину")),
        definition("push_up", "Push Up", "Віджимання від підлоги", "chest", "triceps", "shoulders", aliases = setOf("Push-Up")),
        definition("dips", "Dips", "Віджимання на брусах", "triceps", "chest", "shoulders", aliases = setOf("брусья")),
        definition(
            "assisted_dip",
            "Assisted Dip",
            "Віджимання на брусах у гравітроні",
            "triceps",
            "chest",
            "shoulders",
            aliases = setOf(
                "підтягування з брусьями",
                "підтягування з брусами",
                "підтягування с брусьями",
                "підтягування с брусами",
                "подтягивания с брусьями",
                "подтягивание с брусьями"
            ),
            introducedInSeedVersion = 3
        ),
        definition("pull_up", "Pull Up", "Підтягування", "lats", "biceps", "upperBack", "forearms", aliases = setOf("Pull-Up")),
        definition("assisted_pull_up", "Assisted Pull Up", "Підтягування у гравітроні", "lats", "upperBack", "biceps", "forearms", aliases = setOf("підтягування в гравітроні")),
        definition("band_assisted_pull_up", "Band Assisted Pull Up", "Підтягування з еспандером", "lats", "upperBack", "biceps", "forearms", aliases = setOf("підтягування з резинкою")),
        definition("lat_pulldown", "Lat Pulldown", "Тяга верхнього блока", "lats", "upperBack", "biceps", "forearms", aliases = setOf("Тяга верхнього блока до грудей", "Фронтальна тяга")),
        definition("straight_arm_pulldown", "Straight Arm Pulldown", "Тяга прямих рук на верхньому блоці", "lats", "upperBack", aliases = setOf("Журавель", "Тяга верхніх блоків у тренажері")),
        definition("barbell_row", "Barbell Row", "Тяга штанги в нахилі", "upperBack", "lats", "biceps", "forearms"),
        definition("seated_cable_row", "Seated Cable Row", "Горизонтальна тяга блока", "upperBack", "lats", "biceps", "forearms"),
        definition("plate_loaded_row", "Plate Loaded Row", "Горизонтальна тяга у важільному тренажері", "upperBack", "lats", "biceps", "forearms", aliases = setOf("горизонтальна важільна тяга")),
        definition("face_pull", "Face Pull", "Тяга каната до обличчя", "shoulders", "upperBack"),
        definition("squat", "Squat", "Присідання зі штангою", "quads", "glutes", "hamstrings", "adductors", "lowerBack", aliases = setOf("Barbell Squat", "Присід зі штангою")),
        definition("leg_press", "Leg Press", "Жим ногами у тренажері", "quads", "glutes", "hamstrings", aliases = setOf("Жим ногами")),
        definition("bulgarian_split_squat", "Bulgarian Split Squat", "Болгарські випади", "quads", "glutes", "hamstrings"),
        definition("lunge", "Lunge", "Випади", "quads", "glutes", "hamstrings"),
        definition("romanian_deadlift", "Romanian Deadlift", "Румунська тяга", "hamstrings", "glutes", "lowerBack"),
        definition("deadlift", "Deadlift", "Станова тяга", "hamstrings", "glutes", "lowerBack", "upperBack", "forearms"),
        definition("hip_thrust", "Hip Thrust", "Ягодичний міст зі штангою", "glutes", "hamstrings"),
        definition("leg_extension", "Leg Extension", "Розгинання ніг у тренажері", "quads", aliases = setOf("розгинання ніг")),
        definition("lying_leg_curl", "Lying Leg Curl", "Згинання ніг лежачи", "hamstrings", "calves", aliases = setOf("згибання ніг лежачи")),
        definition("seated_leg_curl", "Seated Leg Curl", "Згинання ніг сидячи", "hamstrings", "calves", aliases = setOf("згибання ніг сидячі", "згибання ніг сидячи")),
        definition("hip_adduction", "Hip Adduction", "Зведення ніг у тренажері", "adductors", aliases = setOf("зведення ніг")),
        definition(
            "hip_abduction",
            "Hip Abduction",
            "Розведення ніг у тренажері",
            "glutes",
            aliases = setOf("розведення ніг", "разведение ног", "разведение ног в тренажере"),
            introducedInSeedVersion = 2
        ),
        definition("calf_raise", "Calf Raise", "Підйом на носки", "calves", aliases = setOf("Підйом на носки стоячи")),
        definition("shoulder_press", "Shoulder Press", "Жим над головою", "shoulders", "triceps", aliases = setOf("Overhead Press", "Жим сидячи над головою", "Жим сидячи")),
        definition("lateral_raise", "Lateral Raise", "Підйоми гантелей через сторони", "shoulders", aliases = setOf("Махи в сторони", "махи в сторони з гантелями")),
        definition("machine_lateral_raise", "Machine Lateral Raise", "Підйоми рук через сторони у тренажері", "shoulders", aliases = setOf("махи в сторони в тренажері")),
        definition("rear_delt_fly", "Rear Delt Fly", "Зворотні розведення у тренажері", "shoulders", "upperBack", aliases = setOf("метелик в сторони")),
        definition("upright_row", "Upright Row", "Тяга штанги до підборіддя", "shoulders", "upperBack", "biceps", aliases = setOf("протяжка", "вертикальна тяга")),
        definition("biceps_curl", "Biceps Curl", "Згинання рук на біцепс", "biceps", "forearms"),
        definition("barbell_curl", "Barbell Curl", "Згинання рук зі штангою", "biceps", "forearms", aliases = setOf("штанга на біцепс")),
        definition("seated_dumbbell_curl", "Seated Dumbbell Curl", "Згинання рук з гантелями сидячи", "biceps", "forearms", aliases = setOf("біцепс з гантелями сидячи")),
        definition("hammer_curl", "Hammer Curl", "Молоткові згинання рук", "biceps", "forearms"),
        definition("cable_curl", "Cable Curl", "Згинання рук на нижньому блоці", "biceps", "forearms", aliases = setOf("біцепс в кросовері")),
        definition("preacher_curl", "Preacher Curl", "Згинання рук на лаві Скотта", "biceps", "forearms", aliases = setOf("тренажер скота(біцепс)")),
        definition("triceps_pushdown", "Triceps Pushdown", "Розгинання рук на блоці", "triceps"),
        definition("v_bar_pushdown", "V-Bar Triceps Pushdown", "Розгинання рук на блоці з V-рукояттю", "triceps", aliases = setOf("трицепс трикутник")),
        definition("overhead_dumbbell_triceps_extension", "Overhead Dumbbell Triceps Extension", "Розгинання гантелі над головою", "triceps", "shoulders", aliases = setOf("гантеля над головою")),
        definition("french_press", "French Press", "Французький жим", "triceps", "shoulders"),
        definition("hyperextension", "Hyperextension", "Гіперекстензія", "lowerBack", "glutes", "hamstrings"),
        definition("side_hyperextension", "Side Hyperextension", "Бокові нахили на гіперекстензії", "obliques", "abs", "lowerBack", aliases = setOf("Нахили в сторони на гіперекстензії")),
        definition("plank", "Plank", "Планка", "abs", "obliques"),
        definition("weighted_crunch", "Weighted Crunch", "Скручування з диском", "abs", "obliques", aliases = setOf("прес звичайний з диском")),
        definition("hanging_leg_raise", "Hanging Leg Raise", "Підйом ніг у висі", "abs", aliases = setOf("прес(підйом ніг)")),
        definition("plate_twist", "Plate Twist", "Повороти корпусу з диском", "obliques", "abs", aliases = setOf("прес з диском в сторони")),
        definition("weighted_side_bend", "Weighted Side Bend", "Бокові нахили з обтяженням", "obliques", "abs", aliases = setOf("бокові нахили")),
        definition("warm_up", "Warm Up", "Розминка", "shoulders", "chest", "upperBack", "lats", "abs", "glutes", "quads", "hamstrings")
    )

    private fun definition(
        key: String,
        nameEn: String,
        nameUk: String,
        vararg muscleIds: String,
        aliases: Set<String> = emptySet(),
        introducedInSeedVersion: Int = 1
    ) = BuiltInExerciseDefinition(
        key = key,
        nameEn = nameEn,
        nameUk = nameUk,
        muscleIds = muscleIds.toSet(),
        legacyAliases = aliases,
        introducedInSeedVersion = introducedInSeedVersion
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
