import Foundation

public struct BuiltInExerciseDefinition: Hashable, Sendable {
    public let key: String
    public let englishName: String
    public let ukrainianName: String
    public let legacyAliases: [String]

    public init(
        key: String,
        englishName: String,
        ukrainianName: String,
        legacyAliases: [String] = []
    ) {
        self.key = key
        self.englishName = englishName
        self.ukrainianName = ukrainianName
        self.legacyAliases = legacyAliases
    }
}

/// Stable identities and localized labels for GymApp's built-in exercises.
///
/// Persisted workout data continues to use the original raw exercise name and UUID.
/// The catalog key is optional metadata used only to choose a display label, so old
/// snapshots and cross-platform schema-v2 backups remain valid.
public enum BuiltInExerciseCatalog {
    public static let definitions: [BuiltInExerciseDefinition] = [
        .init(
            key: "bench_press",
            englishName: "Bench Press",
            ukrainianName: "Жим штанги лежачи",
            legacyAliases: ["жим лежачи"]
        ),
        .init(
            key: "incline_dumbbell_press",
            englishName: "Incline Dumbbell Press",
            ukrainianName: "Жим гантелей на похилій лаві"
        ),
        .init(
            key: "pull_up",
            englishName: "Pull Up",
            ukrainianName: "Підтягування",
            legacyAliases: ["Pull-Up"]
        ),
        .init(
            key: "lat_pulldown",
            englishName: "Lat Pulldown",
            ukrainianName: "Тяга верхнього блока",
            legacyAliases: ["Тяга верхнього блока до грудей", "Фронтальна тяга"]
        ),
        .init(
            key: "barbell_row",
            englishName: "Barbell Row",
            ukrainianName: "Тяга штанги в нахилі"
        ),
        .init(
            key: "squat",
            englishName: "Squat",
            ukrainianName: "Присідання зі штангою",
            legacyAliases: ["Barbell Squat", "Присід зі штангою"]
        ),
        .init(
            key: "leg_press",
            englishName: "Leg Press",
            ukrainianName: "Жим ногами у тренажері",
            legacyAliases: ["Жим ногами"]
        ),
        .init(
            key: "romanian_deadlift",
            englishName: "Romanian Deadlift",
            ukrainianName: "Румунська тяга"
        ),
        .init(
            key: "deadlift",
            englishName: "Deadlift",
            ukrainianName: "Станова тяга"
        ),
        .init(
            key: "shoulder_press",
            englishName: "Shoulder Press",
            ukrainianName: "Жим над головою",
            legacyAliases: ["Overhead Press", "Жим сидячи над головою", "Жим сидячи"]
        ),
        .init(
            key: "lateral_raise",
            englishName: "Lateral Raise",
            ukrainianName: "Підйоми гантелей через сторони",
            legacyAliases: ["Махи в сторони"]
        ),
        .init(
            key: "biceps_curl",
            englishName: "Biceps Curl",
            ukrainianName: "Згинання рук на біцепс"
        ),
        .init(
            key: "triceps_pushdown",
            englishName: "Triceps Pushdown",
            ukrainianName: "Розгинання рук на блоці"
        ),
        .init(
            key: "calf_raise",
            englishName: "Calf Raise",
            ukrainianName: "Підйом на носки",
            legacyAliases: ["Підйом на носки стоячи"]
        ),
        .init(
            key: "plank",
            englishName: "Plank",
            ukrainianName: "Планка"
        )
    ]

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
        // Backup JSON is user-controlled input. A recognized raw name is authoritative so a
        // stale or hostile catalogKey cannot redirect its sets into another exercise's history.
        canonicalKey(forName: name) ?? definition(forKey: catalogKey)?.key
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
        return languageCode == "uk" ? definition.ukrainianName : definition.englishName
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
