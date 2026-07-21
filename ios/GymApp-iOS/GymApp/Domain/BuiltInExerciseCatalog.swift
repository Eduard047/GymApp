import Foundation

public struct BuiltInExerciseDefinition: Hashable, Sendable {
    public let key: String
    public let englishName: String
    public let ukrainianName: String
    public let muscleIDs: [String]
    public let legacyAliases: [String]
    public let introducedInSeedVersion: Int

    public init(
        key: String,
        englishName: String,
        ukrainianName: String,
        muscleIDs: [String],
        legacyAliases: [String] = [],
        introducedInSeedVersion: Int = 1
    ) {
        self.key = key
        self.englishName = englishName
        self.ukrainianName = ukrainianName
        self.muscleIDs = muscleIDs
        self.legacyAliases = legacyAliases
        self.introducedInSeedVersion = introducedInSeedVersion
    }
}

/// Stable identities and localized labels for GymApp's built-in exercises.
///
/// Persisted workout data continues to use the original raw exercise name and UUID.
/// The catalog key is optional metadata used only to choose a display label, so old
/// snapshots and cross-platform schema-v2 backups remain valid.
public enum BuiltInExerciseCatalog {
    public static let seedVersion = 2

    public static let definitions: [BuiltInExerciseDefinition] = [
        definition("bench_press", "Bench Press", "Жим штанги лежачи", ["chest", "triceps", "shoulders"], aliases: ["жим лежачи"]),
        definition("dumbbell_bench_press", "Dumbbell Bench Press", "Жим гантелей лежачи", ["chest", "triceps", "shoulders"], aliases: ["гантелі лежачи"]),
        definition("incline_dumbbell_press", "Incline Dumbbell Press", "Жим гантелей на похилій лаві", ["chest", "shoulders", "triceps"]),
        definition("incline_bench_press", "Incline Bench Press", "Жим штанги на похилій лаві", ["chest", "shoulders", "triceps"]),
        definition("chest_fly_machine", "Machine Chest Fly", "Зведення рук у тренажері", ["chest", "shoulders"], aliases: ["метелик в середину"]),
        definition("push_up", "Push Up", "Віджимання від підлоги", ["chest", "triceps", "shoulders"], aliases: ["Push-Up"]),
        definition("dips", "Dips", "Віджимання на брусах", ["triceps", "chest", "shoulders"], aliases: ["брусья"]),
        definition("pull_up", "Pull Up", "Підтягування", ["lats", "biceps", "upperBack", "forearms"], aliases: ["Pull-Up"]),
        definition("assisted_pull_up", "Assisted Pull Up", "Підтягування у гравітроні", ["lats", "upperBack", "biceps", "forearms"], aliases: ["підтягування в гравітроні"]),
        definition("band_assisted_pull_up", "Band Assisted Pull Up", "Підтягування з еспандером", ["lats", "upperBack", "biceps", "forearms"], aliases: ["підтягування з резинкою"]),
        definition("lat_pulldown", "Lat Pulldown", "Тяга верхнього блока", ["lats", "upperBack", "biceps", "forearms"], aliases: ["Тяга верхнього блока до грудей", "Фронтальна тяга"]),
        definition("straight_arm_pulldown", "Straight Arm Pulldown", "Тяга прямих рук на верхньому блоці", ["lats", "upperBack"], aliases: ["Журавель", "Тяга верхніх блоків у тренажері"]),
        definition("barbell_row", "Barbell Row", "Тяга штанги в нахилі", ["upperBack", "lats", "biceps", "forearms"]),
        definition("seated_cable_row", "Seated Cable Row", "Горизонтальна тяга блока", ["upperBack", "lats", "biceps", "forearms"]),
        definition("plate_loaded_row", "Plate Loaded Row", "Горизонтальна тяга у важільному тренажері", ["upperBack", "lats", "biceps", "forearms"], aliases: ["горизонтальна важільна тяга"]),
        definition("face_pull", "Face Pull", "Тяга каната до обличчя", ["shoulders", "upperBack"]),
        definition("squat", "Squat", "Присідання зі штангою", ["quads", "glutes", "hamstrings", "adductors", "lowerBack"], aliases: ["Barbell Squat", "Присід зі штангою"]),
        definition("leg_press", "Leg Press", "Жим ногами у тренажері", ["quads", "glutes", "hamstrings"], aliases: ["Жим ногами"]),
        definition("bulgarian_split_squat", "Bulgarian Split Squat", "Болгарські випади", ["quads", "glutes", "hamstrings"]),
        definition("lunge", "Lunge", "Випади", ["quads", "glutes", "hamstrings"]),
        definition("romanian_deadlift", "Romanian Deadlift", "Румунська тяга", ["hamstrings", "glutes", "lowerBack"]),
        definition("deadlift", "Deadlift", "Станова тяга", ["hamstrings", "glutes", "lowerBack", "upperBack", "forearms"]),
        definition("hip_thrust", "Hip Thrust", "Ягодичний міст зі штангою", ["glutes", "hamstrings"]),
        definition("leg_extension", "Leg Extension", "Розгинання ніг у тренажері", ["quads"], aliases: ["розгинання ніг"]),
        definition("lying_leg_curl", "Lying Leg Curl", "Згинання ніг лежачи", ["hamstrings", "calves"], aliases: ["згибання ніг лежачи"]),
        definition("seated_leg_curl", "Seated Leg Curl", "Згинання ніг сидячи", ["hamstrings", "calves"], aliases: ["згибання ніг сидячі", "згибання ніг сидячи"]),
        definition("hip_adduction", "Hip Adduction", "Зведення ніг у тренажері", ["adductors"], aliases: ["зведення ніг"]),
        definition(
            "hip_abduction",
            "Hip Abduction",
            "Розведення ніг у тренажері",
            ["glutes"],
            aliases: ["розведення ніг", "разведение ног", "разведение ног в тренажере"],
            introducedInSeedVersion: 2
        ),
        definition("calf_raise", "Calf Raise", "Підйом на носки", ["calves"], aliases: ["Підйом на носки стоячи"]),
        definition("shoulder_press", "Shoulder Press", "Жим над головою", ["shoulders", "triceps"], aliases: ["Overhead Press", "Жим сидячи над головою", "Жим сидячи"]),
        definition("lateral_raise", "Lateral Raise", "Підйоми гантелей через сторони", ["shoulders"], aliases: ["Махи в сторони", "махи в сторони з гантелями"]),
        definition("machine_lateral_raise", "Machine Lateral Raise", "Підйоми рук через сторони у тренажері", ["shoulders"], aliases: ["махи в сторони в тренажері"]),
        definition("rear_delt_fly", "Rear Delt Fly", "Зворотні розведення у тренажері", ["shoulders", "upperBack"], aliases: ["метелик в сторони"]),
        definition("upright_row", "Upright Row", "Тяга штанги до підборіддя", ["shoulders", "upperBack", "biceps"], aliases: ["протяжка", "вертикальна тяга"]),
        definition("biceps_curl", "Biceps Curl", "Згинання рук на біцепс", ["biceps", "forearms"]),
        definition("barbell_curl", "Barbell Curl", "Згинання рук зі штангою", ["biceps", "forearms"], aliases: ["штанга на біцепс"]),
        definition("seated_dumbbell_curl", "Seated Dumbbell Curl", "Згинання рук з гантелями сидячи", ["biceps", "forearms"], aliases: ["біцепс з гантелями сидячи"]),
        definition("hammer_curl", "Hammer Curl", "Молоткові згинання рук", ["biceps", "forearms"]),
        definition("cable_curl", "Cable Curl", "Згинання рук на нижньому блоці", ["biceps", "forearms"], aliases: ["біцепс в кросовері"]),
        definition("preacher_curl", "Preacher Curl", "Згинання рук на лаві Скотта", ["biceps", "forearms"], aliases: ["тренажер скота(біцепс)"]),
        definition("triceps_pushdown", "Triceps Pushdown", "Розгинання рук на блоці", ["triceps"]),
        definition("v_bar_pushdown", "V-Bar Triceps Pushdown", "Розгинання рук на блоці з V-рукояттю", ["triceps"], aliases: ["трицепс трикутник"]),
        definition("overhead_dumbbell_triceps_extension", "Overhead Dumbbell Triceps Extension", "Розгинання гантелі над головою", ["triceps", "shoulders"], aliases: ["гантеля над головою"]),
        definition("french_press", "French Press", "Французький жим", ["triceps", "shoulders"]),
        definition("hyperextension", "Hyperextension", "Гіперекстензія", ["lowerBack", "glutes", "hamstrings"]),
        definition("side_hyperextension", "Side Hyperextension", "Бокові нахили на гіперекстензії", ["obliques", "abs", "lowerBack"], aliases: ["Нахили в сторони на гіперекстензії"]),
        definition("plank", "Plank", "Планка", ["abs", "obliques"]),
        definition("weighted_crunch", "Weighted Crunch", "Скручування з диском", ["abs", "obliques"], aliases: ["прес звичайний з диском"]),
        definition("hanging_leg_raise", "Hanging Leg Raise", "Підйом ніг у висі", ["abs"], aliases: ["прес(підйом ніг)"]),
        definition("plate_twist", "Plate Twist", "Повороти корпусу з диском", ["obliques", "abs"], aliases: ["прес з диском в сторони"]),
        definition("weighted_side_bend", "Weighted Side Bend", "Бокові нахили з обтяженням", ["obliques", "abs"], aliases: ["бокові нахили"]),
        definition("warm_up", "Warm Up", "Розминка", ["shoulders", "chest", "upperBack", "lats", "abs", "glutes", "quads", "hamstrings"])
    ]

    private static func definition(
        _ key: String,
        _ englishName: String,
        _ ukrainianName: String,
        _ muscleIDs: [String],
        aliases: [String] = [],
        introducedInSeedVersion: Int = 1
    ) -> BuiltInExerciseDefinition {
        BuiltInExerciseDefinition(
            key: key,
            englishName: englishName,
            ukrainianName: ukrainianName,
            muscleIDs: muscleIDs,
            legacyAliases: aliases,
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
                result[normalizedAlias(alias)] = definition.key
            }
        }
        return result
    }()

    public static func definition(forKey key: String?) -> BuiltInExerciseDefinition? {
        guard let key else { return nil }
        return definitionByKey[key.trimmingCharacters(in: .whitespacesAndNewlines)]
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
        return gymText(definition.englishName, definition.ukrainianName, languageCode: languageCode)
    }

    private static func normalizedAlias(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
