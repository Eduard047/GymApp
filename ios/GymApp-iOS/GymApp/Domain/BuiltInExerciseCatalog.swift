import Foundation

/// Portable exercise identity normalization shared with Android backup/cloud handling.
///
/// This deliberately is not a search normalizer: accents and character width remain
/// significant so untrusted labels cannot silently become a built-in or another custom
/// exercise. Only canonical Unicode composition and GymApp's established identity
/// compatibility rules are applied.
func normalizeExerciseIdentityName(_ value: String) -> String {
    var collapsed = ""
    var pendingSpace = false
    for scalar in value.unicodeScalars {
        // Swift's Unicode White_Space property covers Java's space characters and U+0085.
        // Java Character.isWhitespace additionally treats the four information separators
        // as whitespace, so include them explicitly for byte-for-byte Android parity.
        let isPortableWhitespace = scalar.properties.isWhitespace ||
            (0x001C ... 0x001F).contains(scalar.value)
        if isPortableWhitespace {
            if !collapsed.isEmpty {
                pendingSpace = true
            }
        } else {
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            collapsed.unicodeScalars.append(scalar)
        }
    }

    return collapsed
        .precomposedStringWithCanonicalMapping
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
        .replacingOccurrences(of: "ʼ", with: "'")
        .replacingOccurrences(of: "’", with: "'")
        .replacingOccurrences(of: "ё", with: "е")
}

public struct BuiltInExerciseDefinition: Hashable, Sendable {
    public let key: String
    public let englishName: String
    public let ukrainianName: String
    public let russianName: String
    public let muscleIDs: [String]
    public let legacyAliases: [String]
    /// Informal and alternate labels used by the exercise picker only.
    ///
    /// These values must never participate in persisted exercise identity resolution.
    public let searchAliases: [String]
    public let introducedInSeedVersion: Int

    public init(
        key: String,
        englishName: String,
        ukrainianName: String,
        russianName: String,
        muscleIDs: [String],
        legacyAliases: [String] = [],
        searchAliases: [String] = [],
        introducedInSeedVersion: Int = 1
    ) {
        self.key = key
        self.englishName = englishName
        self.ukrainianName = ukrainianName
        self.russianName = russianName
        self.muscleIDs = muscleIDs
        self.legacyAliases = legacyAliases
        self.searchAliases = searchAliases
        self.introducedInSeedVersion = introducedInSeedVersion
    }
}

/// Stable identities and localized labels for GymApp's built-in exercises.
///
/// Persisted workout data continues to use the original raw exercise name and UUID.
/// The catalog key is optional metadata used only to choose a display label, so old
/// snapshots and cross-platform schema-v2 backups remain valid.
public enum BuiltInExerciseCatalog {
    public static let seedVersion = 3

    public static let definitions: [BuiltInExerciseDefinition] = [
        definition("bench_press", "Bench Press", "Жим штанги лежачи", "Жим штанги лежа", ["chest", "triceps", "shoulders"], aliases: ["жим лежачи"]),
        definition("dumbbell_bench_press", "Dumbbell Bench Press", "Жим гантелей лежачи", "Жим гантелей лежа", ["chest", "triceps", "shoulders"], aliases: ["гантелі лежачи"]),
        definition("incline_dumbbell_press", "Incline Dumbbell Press", "Жим гантелей на похилій лаві", "Жим гантелей на наклонной скамье", ["chest", "shoulders", "triceps"]),
        definition("incline_bench_press", "Incline Bench Press", "Жим штанги на похилій лаві", "Жим штанги на наклонной скамье", ["chest", "shoulders", "triceps"]),
        definition("chest_fly_machine", "Machine Chest Fly", "Зведення рук у тренажері", "Сведение рук в тренажёре", ["chest", "shoulders"], aliases: ["метелик в середину"]),
        definition("push_up", "Push Up", "Віджимання від підлоги", "Отжимания от пола", ["chest", "triceps", "shoulders"], aliases: ["Push-Up"]),
        definition("dips", "Dips", "Віджимання на брусах", "Отжимания на брусьях", ["triceps", "chest", "shoulders"], aliases: ["брусья"]),
        definition(
            "assisted_dip",
            "Assisted Dip",
            "Віджимання на брусах у гравітроні",
            "Отжимания на брусьях в гравитроне",
            ["triceps", "chest", "shoulders"],
            aliases: [
                "підтягування з брусьями",
                "підтягування з брусами",
                "підтягування с брусьями",
                "підтягування с брусами",
                "подтягивания с брусьями",
                "подтягивание с брусьями"
            ],
            introducedInSeedVersion: 3
        ),
        definition("pull_up", "Pull Up", "Підтягування", "Подтягивание", ["lats", "biceps", "upperBack", "forearms"], aliases: ["Pull-Up"]),
        definition("assisted_pull_up", "Assisted Pull Up", "Підтягування у гравітроні", "Подтягивание в гравитроне", ["lats", "upperBack", "biceps", "forearms"], aliases: ["підтягування в гравітроні"]),
        definition("band_assisted_pull_up", "Band Assisted Pull Up", "Підтягування з еспандером", "Подтягивание с эспандером", ["lats", "upperBack", "biceps", "forearms"], aliases: ["підтягування з резинкою"]),
        definition("lat_pulldown", "Lat Pulldown", "Тяга верхнього блока", "Тяга верхнего блока", ["lats", "upperBack", "biceps", "forearms"], aliases: ["Тяга верхнього блока до грудей", "Фронтальна тяга"]),
        definition("straight_arm_pulldown", "Straight Arm Pulldown", "Тяга прямих рук на верхньому блоці", "Журавель — тяга прямыми руками", ["lats", "upperBack"], aliases: ["Журавель", "Тяга верхніх блоків у тренажері"]),
        definition("barbell_row", "Barbell Row", "Тяга штанги в нахилі", "Тяга штанги в наклоне", ["upperBack", "lats", "biceps", "forearms"]),
        definition("seated_cable_row", "Seated Cable Row", "Горизонтальна тяга блока", "Горизонтальная тяга блока", ["upperBack", "lats", "biceps", "forearms"]),
        definition("plate_loaded_row", "Plate Loaded Row", "Горизонтальна тяга у важільному тренажері", "Горизонтальная тяга в рычажном тренажере", ["upperBack", "lats", "biceps", "forearms"], aliases: ["горизонтальна важільна тяга"]),
        definition("face_pull", "Face Pull", "Тяга каната до обличчя", "Тяга каната к лицу", ["shoulders", "upperBack"]),
        definition("squat", "Squat", "Присідання зі штангою", "Приседания со штангой", ["quads", "glutes", "hamstrings", "adductors", "lowerBack"], aliases: ["Barbell Squat", "Присід зі штангою"]),
        definition("leg_press", "Leg Press", "Жим ногами у тренажері", "Жим ногами в тренажере", ["quads", "glutes", "hamstrings"], aliases: ["Жим ногами"]),
        definition("bulgarian_split_squat", "Bulgarian Split Squat", "Болгарські випади", "Болгарские выпады", ["quads", "glutes", "hamstrings"]),
        definition("lunge", "Lunge", "Випади", "Выпады", ["quads", "glutes", "hamstrings"]),
        definition("romanian_deadlift", "Romanian Deadlift", "Румунська тяга", "Румынская тяга", ["hamstrings", "glutes", "lowerBack"]),
        definition("deadlift", "Deadlift", "Станова тяга", "Становая тяга", ["hamstrings", "glutes", "lowerBack", "upperBack", "forearms"]),
        definition("hip_thrust", "Hip Thrust", "Ягодичний міст зі штангою", "Ягодичный мост со штангой", ["glutes", "hamstrings"]),
        definition("leg_extension", "Leg Extension", "Розгинання ніг у тренажері", "Разгибание ног в тренажере", ["quads"], aliases: ["розгинання ніг"]),
        definition("lying_leg_curl", "Lying Leg Curl", "Згинання ніг лежачи", "Сгибание ног лежа", ["hamstrings", "calves"], aliases: ["згибання ніг лежачи"]),
        definition("seated_leg_curl", "Seated Leg Curl", "Згинання ніг сидячи", "Сгибание ног сидя", ["hamstrings", "calves"], aliases: ["згибання ніг сидячі", "згибання ніг сидячи"]),
        definition("hip_adduction", "Hip Adduction", "Зведення ніг у тренажері", "Сведение ног в тренажере", ["adductors"], aliases: ["зведення ніг"]),
        definition(
            "hip_abduction",
            "Hip Abduction",
            "Розведення ніг у тренажері",
            "Разведение ног в тренажере",
            ["glutes"],
            aliases: ["розведення ніг", "разведение ног", "разведение ног в тренажере"],
            introducedInSeedVersion: 2
        ),
        definition("calf_raise", "Calf Raise", "Підйом на носки", "Подъем на носки", ["calves"], aliases: ["Підйом на носки стоячи"]),
        definition("shoulder_press", "Shoulder Press", "Жим над головою", "Жим над головой", ["shoulders", "triceps"], aliases: ["Overhead Press", "Жим сидячи над головою", "Жим сидячи"]),
        definition("lateral_raise", "Lateral Raise", "Підйоми гантелей через сторони", "Подъемы гантелей через стороны", ["shoulders"], aliases: ["Махи в сторони", "махи в сторони з гантелями"]),
        definition("machine_lateral_raise", "Machine Lateral Raise", "Підйоми рук через сторони у тренажері", "Подъемы рук через стороны в тренажере", ["shoulders"], aliases: ["махи в сторони в тренажері"]),
        definition("rear_delt_fly", "Rear Delt Fly", "Зворотні розведення у тренажері", "Обратные разведения в тренажере", ["shoulders", "upperBack"], aliases: ["метелик в сторони"]),
        definition("upright_row", "Upright Row", "Тяга штанги до підборіддя", "Тяга штанги к подбородку", ["shoulders", "upperBack", "biceps"], aliases: ["протяжка", "вертикальна тяга"]),
        definition("biceps_curl", "Biceps Curl", "Згинання рук на біцепс", "Сгибание рук на бицепс", ["biceps", "forearms"]),
        definition("barbell_curl", "Barbell Curl", "Згинання рук зі штангою", "Сгибание рук со штангой", ["biceps", "forearms"], aliases: ["штанга на біцепс"]),
        definition("seated_dumbbell_curl", "Seated Dumbbell Curl", "Згинання рук з гантелями сидячи", "Сгибание рук с гантелями сидя", ["biceps", "forearms"], aliases: ["біцепс з гантелями сидячи"]),
        definition("hammer_curl", "Hammer Curl", "Молоткові згинання рук", "Молоточные сгибания рук", ["biceps", "forearms"]),
        definition("cable_curl", "Cable Curl", "Згинання рук на нижньому блоці", "Сгибание рук на нижнем блоке", ["biceps", "forearms"], aliases: ["біцепс в кросовері"]),
        definition("preacher_curl", "Preacher Curl", "Згинання рук на лаві Скотта", "Сгибание рук на скамье Скотта", ["biceps", "forearms"], aliases: ["тренажер скота(біцепс)"]),
        definition("triceps_pushdown", "Triceps Pushdown", "Розгинання рук на блоці", "Разгибание рук на блоке", ["triceps"]),
        definition("v_bar_pushdown", "V-Bar Triceps Pushdown", "Розгинання рук на блоці з V-рукояттю", "Разгибание рук на блоке с V-рукояткой", ["triceps"], aliases: ["трицепс трикутник"]),
        definition("overhead_dumbbell_triceps_extension", "Overhead Dumbbell Triceps Extension", "Розгинання гантелі над головою", "Разгибание гантели над головой", ["triceps", "shoulders"], aliases: ["гантеля над головою"]),
        definition("french_press", "French Press", "Французький жим", "Французский жим", ["triceps", "shoulders"]),
        definition("hyperextension", "Hyperextension", "Гіперекстензія", "Гиперекстензия", ["lowerBack", "glutes", "hamstrings"]),
        definition("side_hyperextension", "Side Hyperextension", "Бокові нахили на гіперекстензії", "Боковая гиперэкстензия", ["obliques", "abs", "lowerBack"], aliases: ["Нахили в сторони на гіперекстензії"]),
        definition("plank", "Plank", "Планка", "Планка", ["abs", "obliques"]),
        definition("weighted_crunch", "Weighted Crunch", "Скручування з диском", "Скручивание с диском", ["abs", "obliques"], aliases: ["прес звичайний з диском"]),
        definition("hanging_leg_raise", "Hanging Leg Raise", "Підйом ніг у висі", "Подъем ног в висе", ["abs"], aliases: ["прес(підйом ніг)"]),
        definition("plate_twist", "Plate Twist", "Повороти корпусу з диском", "Повороты корпуса с диском", ["obliques", "abs"], aliases: ["прес з диском в сторони"]),
        definition("weighted_side_bend", "Weighted Side Bend", "Бокові нахили з обтяженням", "Боковые наклоны с отягощением", ["obliques", "abs"], aliases: ["бокові нахили"]),
        definition("warm_up", "Warm Up", "Розминка", "Разминка", ["shoulders", "chest", "upperBack", "lats", "abs", "glutes", "quads", "hamstrings"])
    ]

    private static func definition(
        _ key: String,
        _ englishName: String,
        _ ukrainianName: String,
        _ russianName: String,
        _ muscleIDs: [String],
        aliases: [String] = [],
        introducedInSeedVersion: Int = 1
    ) -> BuiltInExerciseDefinition {
        BuiltInExerciseDefinition(
            key: key,
            englishName: englishName,
            ukrainianName: ukrainianName,
            russianName: russianName,
            muscleIDs: muscleIDs,
            legacyAliases: aliases,
            searchAliases: ExerciseSearchVocabulary.aliasesByKey[key] ?? [],
            introducedInSeedVersion: introducedInSeedVersion
        )
    }

    private static let definitionByKey = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.key, $0) }
    )

    private static let keyByAlias: [String: String] = {
        var result: [String: String] = [:]
        for definition in definitions {
            let aliases = [definition.englishName, definition.ukrainianName] + definition.legacyAliases
            for alias in aliases {
                let normalized = normalizedAlias(alias)
                precondition(
                    result[normalized] == nil,
                    "Duplicate built-in exercise alias: \(alias)"
                )
                result[normalized] = definition.key
            }
        }
        return result
    }()

    public static func definition(forKey key: String?) -> BuiltInExerciseDefinition? {
        guard let key else { return nil }
        let normalizedKey = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        return definitionByKey[normalizedKey]
    }

    /// Recognizes only exact, case-insensitive catalog names and reviewed legacy aliases.
    /// User-created names that merely contain the same words remain custom exercises.
    public static func canonicalKey(forName name: String) -> String? {
        keyByAlias[normalizedAlias(name)]
    }

    public static func resolvedKey(catalogKey: String?, name: String) -> String? {
        // Backup JSON is user-controlled input. Any non-empty raw name is authoritative:
        // recognized names resolve through reviewed aliases, while unknown names remain custom.
        // A catalogKey is only recovery metadata for legacy records whose raw name is missing.
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty
            ? definition(forKey: catalogKey)?.key
            : canonicalKey(forName: cleanName)
    }

    public static func displayName(
        catalogKey: String?,
        rawName: String,
        languageCode: String
    ) -> String {
        guard let definition = definition(
            forKey: resolvedKey(catalogKey: catalogKey, name: rawName)
        ) else {
            return rawName
        }
        if definition.key == "straight_arm_pulldown" {
            return gymText(
                definition.englishName,
                "Журавель — тяга прямими руками",
                "Журавель — тяга прямыми руками",
                languageCode: languageCode
            )
        }
        return gymText(
            definition.englishName,
            definition.ukrainianName,
            definition.russianName,
            languageCode: languageCode
        )
    }

    private static func normalizedAlias(_ value: String) -> String {
        normalizeExerciseIdentityName(value)
    }
}
