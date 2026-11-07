import Foundation

/// Garmin watches only ever receive English/Latin text; every sync is tagged with this language.
let garminWatchLanguageTag = "en"

/// Pure view of the built-in exercise catalog that the Latin conversion needs.
protocol GarminBuiltInNames {
    /// The English catalog name when `raw` is a built-in exercise (catalog identity), else nil.
    func nameEn(for raw: String) -> String?

    /// True when `latin` is a string the catalog recognises (so a custom name must not equal it).
    func isReservedLatin(_ latin: String) -> Bool
}

/// Catalog identity is `BuiltInExerciseCatalog.resolvedKey` (exact names and reviewed legacy aliases);
/// Russian/Ukrainian display names are not identity, so a custom Russian name is transliterated.
struct CatalogGarminBuiltInNames: GarminBuiltInNames {
    func nameEn(for raw: String) -> String? {
        BuiltInExerciseCatalog.definition(
            forKey: BuiltInExerciseCatalog.resolvedKey(catalogKey: nil, name: raw)
        )?.englishName
    }

    func isReservedLatin(_ latin: String) -> Bool {
        BuiltInExerciseCatalog.canonicalKey(forName: latin) != nil
    }
}

struct GarminLatinEntry: Codable, Equatable, Hashable {
    let latin: String
    let raw: String
}

struct GarminLatinAssignment: Equatable {
    /// Trimmed raw name to the Latin name sent to the watch, for every requested name.
    let latinByRaw: [String: String]
    /// Table rows that must be appended, in assignment order.
    let newEntries: [GarminLatinEntry]

    func latin(for raw: String) -> String? {
        latinByRaw[raw.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

/// Raw (possibly Cyrillic) exercise name to the ASCII name shown on the watch, and back.
/// The table below is mirrored by shared/garmin-latin-names-v1.json and tests/garmin-latin-names-contract.test.mjs.
enum GarminLatinNames {
    static let maxLength = 160
    static let fallbackName = "Exercise"

    // TABLE-BEGIN
    static let table: [String: String] = [
        "а": "a",
        "б": "b",
        "в": "v",
        "г": "g",
        "ґ": "g",
        "д": "d",
        "е": "e",
        "ё": "yo",
        "є": "ye",
        "ж": "zh",
        "з": "z",
        "и": "y",
        "і": "i",
        "ї": "yi",
        "й": "y",
        "к": "k",
        "л": "l",
        "м": "m",
        "н": "n",
        "о": "o",
        "п": "p",
        "р": "r",
        "с": "s",
        "т": "t",
        "у": "u",
        "ф": "f",
        "х": "kh",
        "ц": "ts",
        "ч": "ch",
        "ш": "sh",
        "щ": "shch",
        "ы": "y",
        "э": "e",
        "ю": "yu",
        "я": "ya"
    ]
    // TABLE-END

    // DROPPED-BEGIN
    static let dropped = "ъьʼ’'"
    // DROPPED-END

    static func isAscii(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { (0x20 ... 0x7E).contains($0.value) }
    }

    private static func isAsciiScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x20 ... 0x7E).contains(scalar.value)
    }

    /// Plain transliteration of a non-built-in name (no collision handling). Never empty.
    static func transliterate(_ raw: String) -> String {
        let normalized = raw.precomposedStringWithCanonicalMapping
        let droppedScalars = Set(dropped.unicodeScalars)
        var builder = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            if droppedScalars.contains(scalar) { continue }
            if let mapped = table[String(scalar).lowercased()] {
                if scalar.properties.isUppercase {
                    builder.append(contentsOf: (mapped.prefix(1).uppercased() + mapped.dropFirst()).unicodeScalars)
                } else {
                    builder.append(contentsOf: mapped.unicodeScalars)
                }
                continue
            }
            if isAsciiScalar(scalar) {
                builder.append(scalar)
                continue
            }
            // Accents: decompose this one character and keep only its ASCII base letters.
            for part in String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
            where isAsciiScalar(part) {
                builder.append(part)
            }
        }
        var result = collapseSpaces(String(builder))
        let allUppercase = normalized.unicodeScalars.contains { $0.properties.isUppercase } &&
            !normalized.unicodeScalars.contains { $0.properties.isLowercase }
        if allUppercase {
            result = result.split(separator: " ", omittingEmptySubsequences: false).map { word in
                let lowered = word.lowercased()
                return lowered.prefix(1).uppercased() + lowered.dropFirst()
            }.joined(separator: " ")
        }
        if result.count > maxLength {
            result = String(result.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? fallbackName : result
    }

    private static func collapseSpaces(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Latin name before collision handling: built-in English name, ASCII unchanged, or transliteration.
    static func baseName(
        _ raw: String,
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames()
    ) -> String {
        builtIns.nameEn(for: raw) ?? (isAscii(raw) ? raw : transliterate(raw))
    }

    /// Assigns a Latin name to every name in `names`. `existing` is the persisted append-only table:
    /// a raw name already in it keeps its Latin name; its Latin names stay reserved even when the raw
    /// exercise is gone. Transliterated names produce `newEntries`; so does an ASCII name that equals
    /// the Latin name of a live row (its exercise is still in `names`): it is sent under an alias row
    /// (raw = the ASCII name, latin = "Name 2") so the watch never sees two identical names and the
    /// import maps each back to its own exercise.
    static func assign(
        names: [String],
        existing: [GarminLatinEntry],
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames()
    ) -> GarminLatinAssignment {
        var seenNames = Set<String>()
        var trimmed: [String] = []
        for name in names {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, seenNames.insert(value).inserted { trimmed.append(value) }
        }
        let existingByRaw = Dictionary(existing.map { ($0.raw, $0.latin) }, uniquingKeysWith: { $1 })
        var reserved = Set<String>()
        for entry in existing { reserved.insert(entry.latin.lowercased()) }
        for name in trimmed where isAscii(name) { reserved.insert(name.lowercased()) }
        var liveLatin = Set<String>()
        for entry in existing where seenNames.contains(entry.raw) { liveLatin.insert(entry.latin.lowercased()) }

        var result: [String: String] = [:]
        var pending: [String] = []
        for raw in trimmed {
            if let builtIn = builtIns.nameEn(for: raw) {
                result[raw] = builtIn
            } else if let known = existingByRaw[raw] {
                result[raw] = known
            } else if isAscii(raw), !liveLatin.contains(raw.lowercased()) {
                result[raw] = raw
            } else {
                pending.append(raw)
            }
        }
        var added: [GarminLatinEntry] = []
        for raw in pending.sorted(by: codePointOrder) {
            let base = isAscii(raw) ? raw : transliterate(raw)
            var candidate = base
            var number = 2
            while reserved.contains(candidate.lowercased()) || builtIns.isReservedLatin(candidate) {
                let suffix = " \(number)"
                let head = String(base.prefix(maxLength - suffix.count)).trimmingCharacters(in: .whitespaces)
                candidate = head + suffix
                number += 1
            }
            reserved.insert(candidate.lowercased())
            result[raw] = candidate
            added.append(GarminLatinEntry(latin: candidate, raw: raw))
        }
        return GarminLatinAssignment(latinByRaw: result, newEntries: added)
    }

    /// The stored exercise name a watch-echoed `latin` name stands for, or nil to keep the caller's
    /// existing lookup unchanged (that is how old Cyrillic names still match exactly).
    /// Order: a table row (its exercise, or - when that exercise was renamed or deleted - the row's raw
    /// name so the original exercise is recreated, unless an exercise is literally named `latin`);
    /// the single current exercise the catalog resolves to the built-in named `latin`; the single
    /// non-built-in non-ASCII exercise whose plain transliteration equals `latin`.
    static func invert(
        _ latin: String,
        table entries: [GarminLatinEntry],
        currentNames: [String],
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames()
    ) -> String? {
        var seenNames = Set<String>()
        var current: [String] = []
        for name in currentNames {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if seenNames.insert(value).inserted { current.append(value) }
        }
        if let row = entries.first(where: { $0.latin == latin }) {
            return seenNames.contains(row.raw) || !seenNames.contains(latin) ? row.raw : nil
        }
        let builtInMatches = current.filter { builtIns.nameEn(for: $0) == latin }
        if builtInMatches.count == 1 { return builtInMatches[0] }
        let matches = current.filter {
            !isAscii($0) && builtIns.nameEn(for: $0) == nil && transliterate($0) == latin
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Raw name to the watch name for every plan set; nil when any name has no assignment or is not ASCII.
    /// `keepingAscii` is for names that were already converted (a stored delivery): an ASCII name is
    /// the watch name itself and must not be re-assigned (it could equal a table row's Latin name).
    static func watchPlan(
        _ plan: [NamedWorkoutSetDraft],
        assignment: GarminLatinAssignment,
        keepingAscii: Bool = false
    ) -> [NamedWorkoutSetDraft]? {
        var result: [NamedWorkoutSetDraft] = []
        result.reserveCapacity(plan.count)
        for set in plan {
            let latin = keepingAscii && isAscii(set.exerciseName)
                ? set.exerciseName
                : assignment.latin(for: set.exerciseName)
            guard let latin, isAscii(latin) else { return nil }
            result.append(NamedWorkoutSetDraft(exerciseName: latin, weight: set.weight, reps: set.reps))
        }
        return result
    }

    /// Raw catalog names to distinct watch names, in input order.
    static func watchCatalog(
        _ names: [String],
        assignment: GarminLatinAssignment,
        keepingAscii: Bool = false
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let mapped = keepingAscii && isAscii(name) ? name : assignment.latin(for: name)
            guard let latin = mapped, seen.insert(latin).inserted else { continue }
            result.append(latin)
        }
        return result
    }

    /// Payload builders refuse to send any name the watch could not render: ASCII only.
    static func areWatchNamesAscii(plan: [NamedWorkoutSetDraft], catalog: [String]) -> Bool {
        plan.allSatisfy { isAscii($0.exerciseName) } && catalog.allSatisfy { isAscii($0) }
    }

    /// Maps names echoed by the watch back to stored exercise names (see `invert`): a table row, the
    /// single exercise the catalog resolves to a built-in English name, the single unambiguous
    /// inversion, else the name unchanged so the existing exact lookup still matches old Cyrillic names.
    static func translateWatchNames(
        _ sets: [NamedWorkoutSetDraft],
        table entries: [GarminLatinEntry],
        currentNames: [String],
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames()
    ) -> [NamedWorkoutSetDraft] {
        var translatedByName: [String: String] = [:]
        return sets.map { set in
            let name = set.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let translated: String
            if let cached = translatedByName[name] {
                translated = cached
            } else {
                translated = invert(name, table: entries, currentNames: currentNames, builtIns: builtIns)
                    ?? set.exerciseName
                translatedByName[name] = translated
            }
            return translated == set.exerciseName
                ? set
                : NamedWorkoutSetDraft(exerciseName: translated, weight: set.weight, reps: set.reps)
        }
    }

    private static func codePointOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.unicodeScalars.map(\.value)
        let right = rhs.unicodeScalars.map(\.value)
        for (a, b) in zip(left, right) where a != b { return a < b }
        return left.count < right.count
    }
}
