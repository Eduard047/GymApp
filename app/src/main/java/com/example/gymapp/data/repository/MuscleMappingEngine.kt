package com.example.gymapp.data.repository

import com.example.gymapp.data.catalog.normalizeExerciseIdentityName
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity

data class MuscleDefinition(
    val id: String,
    val titleEn: String,
    val titleUk: String
)

data class MuscleContribution(
    val muscleId: String,
    val weight: Double
)

private const val BODYWEIGHT_LOAD_PROXY = 72.0
private const val SET_COMPLETION_LOAD = 35.0

val MUSCLE_DEFINITIONS = listOf(
    MuscleDefinition("chest", "Chest", "Груди"),
    MuscleDefinition("shoulders", "Shoulders", "Плечі"),
    MuscleDefinition("biceps", "Biceps", "Біцепс"),
    MuscleDefinition("triceps", "Triceps", "Трицепс"),
    MuscleDefinition("forearms", "Forearms", "Передпліччя"),
    MuscleDefinition("abs", "Abs", "Прес"),
    MuscleDefinition("obliques", "Obliques", "Косі мʼязи"),
    MuscleDefinition("lats", "Lats", "Широчайші"),
    MuscleDefinition("upperBack", "Upper back", "Верх спини"),
    MuscleDefinition("lowerBack", "Lower back", "Поперек"),
    MuscleDefinition("glutes", "Glutes", "Сідниці"),
    MuscleDefinition("quads", "Quads", "Квадрицепси"),
    MuscleDefinition("hamstrings", "Hamstrings", "Біцепс стегна"),
    MuscleDefinition("adductors", "Adductors", "Привідні"),
    MuscleDefinition("calves", "Calves", "Ікри")
)

private val EXACT_MUSCLE_MAP = mapOf(
    "нахили в сторони на гіперекстензії" to muscles("obliques" to 0.9, "abs" to 0.35, "lowerBack" to 0.25),
    "бокові нахили на гіперекстензії" to muscles("obliques" to 0.9, "abs" to 0.35, "lowerBack" to 0.25),
    "присід зі штангою" to muscles("quads" to 1.0, "glutes" to 0.7, "hamstrings" to 0.45, "lowerBack" to 0.25, "abs" to 0.2),
    "присідання зі штангою" to muscles("quads" to 1.0, "glutes" to 0.7, "hamstrings" to 0.45, "lowerBack" to 0.25, "abs" to 0.2),
    "бокові нахили" to muscles("obliques" to 0.9, "abs" to 0.3),
    "бокові нахили з обтяженням" to muscles("obliques" to 0.9, "abs" to 0.3),
    "брусья" to muscles("triceps" to 0.85, "chest" to 0.75, "shoulders" to 0.35),
    "віджимання на брусах" to muscles("triceps" to 0.85, "chest" to 0.75, "shoulders" to 0.35),
    "біцепс з гантелями сидячи" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "згинання рук з гантелями сидячи" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "гантеля над головою" to muscles("triceps" to 1.0, "shoulders" to 0.3),
    "розгинання гантелі над головою" to muscles("triceps" to 1.0, "shoulders" to 0.3),
    "гантелі лежачи" to muscles("chest" to 0.9, "triceps" to 0.55, "shoulders" to 0.45),
    "жим гантелей лежачи" to muscles("chest" to 0.9, "triceps" to 0.55, "shoulders" to 0.45),
    "горизонтальна важільна тяга" to muscles("upperBack" to 1.0, "lats" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "горизонтальна тяга у важільному тренажері" to muscles("upperBack" to 1.0, "lats" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "гіперекстензія" to muscles("lowerBack" to 1.0, "glutes" to 0.55, "hamstrings" to 0.45),
    "жим лежачи" to muscles("chest" to 1.0, "triceps" to 0.6, "shoulders" to 0.5),
    "жим штанги лежачи" to muscles("chest" to 1.0, "triceps" to 0.6, "shoulders" to 0.5),
    "жим ногами" to muscles("quads" to 1.0, "glutes" to 0.55, "hamstrings" to 0.35, "calves" to 0.15),
    "жим ногами у тренажері" to muscles("quads" to 1.0, "glutes" to 0.55, "hamstrings" to 0.35, "calves" to 0.15),
    "жим сидячи" to muscles("shoulders" to 1.0, "triceps" to 0.55, "chest" to 0.2),
    "жим сидячи над головою" to muscles("shoulders" to 1.0, "triceps" to 0.55, "chest" to 0.2),
    "журавель" to muscles("lats" to 1.0, "upperBack" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "тяга верхніх блоків у тренажері" to muscles("lats" to 1.0, "upperBack" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "тяга верхних блоков в тренажере" to muscles("lats" to 1.0, "upperBack" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "зведення ніг" to muscles("adductors" to 1.0, "quads" to 0.25),
    "зведення ніг у тренажері" to muscles("adductors" to 1.0, "quads" to 0.25),
    "розведення ніг" to muscles("glutes" to 1.0),
    "розведення ніг у тренажері" to muscles("glutes" to 1.0),
    "разведение ног" to muscles("glutes" to 1.0),
    "разведение ног в тренажере" to muscles("glutes" to 1.0),
    "згибання ніг" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "згинання ніг у тренажері" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "сгибание ног" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "сгибание ног в тренажере" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "сгибание ног лежа" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "сгибание ног сидя" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "махи в сторони" to muscles("shoulders" to 1.0),
    "підйоми гантелей через сторони" to muscles("shoulders" to 1.0),
    "метелик в середину" to muscles("chest" to 1.0, "shoulders" to 0.25),
    "зведення рук у тренажері" to muscles("chest" to 1.0, "shoulders" to 0.25),
    "метелик в сторони" to muscles("shoulders" to 0.75, "upperBack" to 0.65),
    "зворотні розведення у тренажері" to muscles("shoulders" to 0.75, "upperBack" to 0.65),
    "прес з диском в сторони" to muscles("obliques" to 0.85, "abs" to 0.45),
    "повороти корпусу з диском" to muscles("obliques" to 0.85, "abs" to 0.45),
    "прес звичайний з диском" to muscles("abs" to 1.0, "obliques" to 0.25),
    "скручування з диском" to muscles("abs" to 1.0, "obliques" to 0.25),
    "прес(підйом ніг)" to muscles("abs" to 1.0),
    "підйом ніг у висі" to muscles("abs" to 1.0),
    "протяжка" to muscles("shoulders" to 0.85, "upperBack" to 0.55, "biceps" to 0.25),
    "тяга штанги до підборіддя" to muscles("shoulders" to 0.85, "upperBack" to 0.55, "biceps" to 0.25),
    "підйом на носки" to muscles("calves" to 1.0),
    "підйом на носки стоячи" to muscles("calves" to 1.0),
    "підтягування в гравітроні" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "підтягування у гравітроні" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "підтягування з резинкою" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "підтягування з еспандером" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "розгинання ніг" to muscles("quads" to 1.0),
    "розгинання ніг у тренажері" to muscles("quads" to 1.0),
    "румунська тяга" to muscles("hamstrings" to 1.0, "glutes" to 0.85, "lowerBack" to 0.65, "upperBack" to 0.2),
    "станова тяга" to muscles("lowerBack" to 0.9, "glutes" to 0.85, "hamstrings" to 0.8, "upperBack" to 0.45, "quads" to 0.35, "forearms" to 0.3),
    "тренажер скота(біцепс)" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "згинання рук на лаві скотта" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "трицепс трикутник" to muscles("triceps" to 1.0),
    "розгинання рук на блоці з v-рукояттю" to muscles("triceps" to 1.0),
    "французький жим" to muscles("triceps" to 1.0, "shoulders" to 0.15),
    "фронтальна тяга" to muscles("lats" to 1.0, "upperBack" to 0.7, "biceps" to 0.5, "forearms" to 0.25),
    "тяга верхнього блока до грудей" to muscles("lats" to 1.0, "upperBack" to 0.7, "biceps" to 0.5, "forearms" to 0.25),
    "штанга на біцепс" to muscles("biceps" to 1.0, "forearms" to 0.35),
    "згинання рук зі штангою" to muscles("biceps" to 1.0, "forearms" to 0.35)
)

fun ExerciseHistoryEntry.estimatedLoad(): Double {
    val repsValue = reps.coerceAtLeast(0)
    val trackedLoad = weight.coerceAtLeast(0.0) * repsValue
    val exerciseLoad = if (trackedLoad > 0.0) {
        trackedLoad
    } else {
        BODYWEIGHT_LOAD_PROXY * repsValue
    }
    return exerciseLoad + SET_COMPLETION_LOAD
}

fun List<ExerciseMuscleMappingEntity>.toManualContributionMap(): Map<String, List<MuscleContribution>> {
    return groupBy { it.exerciseNameKey }
        .mapValues { (_, mappings) ->
            mappings
                .filter { mapping -> MUSCLE_DEFINITIONS.any { it.id == mapping.muscleId } }
                .map { mapping ->
                    MuscleContribution(
                        muscleId = mapping.muscleId,
                        weight = mapping.weight.coerceIn(0.0, 1.0)
                    )
                }
        }
}

fun defaultContributionsForExercise(exerciseName: String): List<MuscleContribution> {
    return muscleContributionsForExercise(exerciseName, manualMappings = emptyMap())
}

fun muscleContributionsForExercise(
    exerciseName: String,
    manualMappings: Map<String, List<MuscleContribution>> = emptyMap()
): List<MuscleContribution> {
    val normalizedName = exerciseName.normalizedExerciseName()
    manualMappings[normalizedName]?.takeIf { it.isNotEmpty() }?.let { return it }
    EXACT_MUSCLE_MAP[normalizedName]?.let { return it }
    val isLegCurl = normalizedName.isLegCurlName()

    val inferred = linkedMapOf<String, Double>()
    fun add(muscleId: String, weight: Double) {
        inferred[muscleId] = (inferred[muscleId] ?: 0.0).coerceAtLeast(weight.coerceIn(0.0, 1.0))
    }

    if (isLegCurl) {
        add("hamstrings", 1.0)
        add("calves", 0.2)
    }
    if (!isLegCurl && normalizedName.containsAny("біцепс", "бицепс", "bicep", "curl", "сгибание рук", "згинання рук")) {
        add("biceps", 1.0)
        add("forearms", 0.25)
    }
    if (normalizedName.containsAny("трицепс", "tricep", "француз", "розгинання рук", "разгибание рук", "pushdown")) {
        add("triceps", 1.0)
    }
    if (normalizedName.containsAny("жим ног", "жим ногами", "leg press")) {
        add("quads", 1.0)
        add("glutes", 0.55)
        add("hamstrings", 0.35)
    }
    if (normalizedName.containsAny("жим", "press", "bench") && !normalizedName.containsAny("ног", "leg press")) {
        add("chest", 0.85)
        add("triceps", 0.55)
        add("shoulders", 0.45)
    }
    if (normalizedName.containsAny("плеч", "дельт", "махи", "розведення", "разведение", "підйом гантелей", "подъем гантелей", "shoulder", "lateral raise", "rear delt", "face pull", "overhead press", "press overhead")) {
        add("shoulders", 1.0)
    }
    if (normalizedName.containsAny("підтяг", "подтяг", "pull up", "pullup", "pulldown", "тяга верхнього блока", "тяга верхнего блока", "верхній блок", "верхний блок")) {
        add("lats", 1.0)
        add("upperBack", 0.65)
        add("biceps", 0.55)
        add("forearms", 0.3)
    }
    if (normalizedName.containsAny("тяга", "deadlift", "row") && normalizedName.containsAny("румун", "станов", "становая", "deadlift")) {
        add("hamstrings", 0.9)
        add("glutes", 0.85)
        add("lowerBack", 0.75)
        add("upperBack", 0.3)
        add("forearms", 0.25)
    }
    if (normalizedName.containsAny("тяга", "row") && !normalizedName.containsAny("румун", "станов", "становая", "deadlift", "підборід", "подбород")) {
        add("lats", 0.9)
        add("upperBack", 0.85)
        add("biceps", 0.45)
        add("forearms", 0.25)
    }
    if (normalizedName.containsAny("прис", "присед", "squat", "випади", "выпады", "lunge")) {
        add("quads", 1.0)
        add("glutes", 0.7)
        add("hamstrings", 0.45)
        add("lowerBack", 0.25)
    }
    if (normalizedName.containsAny("розгинання ніг", "разгибание ног", "leg extension")) {
        add("quads", 1.0)
    }
    if (isLegCurl) {
        add("hamstrings", 1.0)
        add("calves", 0.2)
    }
    if (normalizedName.containsAny("підйом на носки", "підйоми на носки", "подъем на носки", "икры", "calf")) {
        add("calves", 1.0)
    }
    if (normalizedName.containsAny("прес", "скруч", "планка", "crunch", "sit up", "leg raise", "plank")) {
        add("abs", 1.0)
    }
    if (normalizedName.containsAny("нахил", "наклон", "сторони", "стороны", "поворот корпус", "rotation", "side bend", "russian twist")) {
        add("obliques", 0.85)
    }
    if (normalizedName.containsAny("гіперекстензі", "гиперэкстенз", "hyperextension")) {
        add("lowerBack", 1.0)
        add("glutes", 0.55)
        add("hamstrings", 0.45)
    }
    if (normalizedName.containsAny("сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик")) {
        add("glutes", 1.0)
        add("hamstrings", 0.35)
    }
    if (normalizedName.containsAny("зведення ніг", "сведение ног", "adductor")) {
        add("adductors", 1.0)
    }
    if (normalizedName.containsAny("розведення ніг", "разведение ног", "hip abduction", "abductor")) {
        add("glutes", 1.0)
    }
    if (normalizedName.containsAny("метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies")) {
        add("chest", 1.0)
        add("shoulders", 0.25)
    }

    return inferred.map { (muscleId, weight) ->
        MuscleContribution(muscleId = muscleId, weight = weight)
    }
}

private fun muscles(vararg values: Pair<String, Double>): List<MuscleContribution> {
    return values
        .filter { (muscleId, _) -> MUSCLE_DEFINITIONS.any { it.id == muscleId } }
        .map { (muscleId, weight) ->
            MuscleContribution(
                muscleId = muscleId,
                weight = weight.coerceIn(0.0, 1.0)
            )
        }
}

fun String.normalizedExerciseName(): String {
    return normalizeExerciseIdentityName(this)
}

private fun String.containsAny(vararg tokens: String): Boolean {
    return tokens.any { token -> contains(token) }
}

private fun String.isLegCurlName(): Boolean {
    return containsAny(
        "згинання ніг",
        "згибання ніг",
        "сгибание ног",
        "сгибания ног",
        "leg curl",
        "lying leg curl",
        "seated leg curl"
    )
}
