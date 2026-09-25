import Foundation

public struct VoiceWorkoutDraft: Codable, Equatable, Sendable {
    public var blocks: [VoiceWorkoutExerciseBlock]
    public var diagnostics: [VoiceWorkoutDiagnostic]

    public init(blocks: [VoiceWorkoutExerciseBlock] = [], diagnostics: [VoiceWorkoutDiagnostic] = []) {
        self.blocks = blocks
        self.diagnostics = diagnostics
    }

    public var isValid: Bool {
        !blocks.isEmpty && diagnostics.isEmpty && blocks.allSatisfy(\.isValid)
    }
}

public struct VoiceWorkoutExerciseBlock: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var spokenName: String
    public var catalogKey: String?
    public var exerciseID: UUID?
    public var sets: [VoiceWorkoutSet]
    public var matching: VoiceWorkoutMatchStatus

    public init(
        id: UUID = UUID(),
        spokenName: String,
        catalogKey: String? = nil,
        exerciseID: UUID? = nil,
        sets: [VoiceWorkoutSet],
        matching: VoiceWorkoutMatchStatus = .unresolved
    ) {
        self.id = id
        self.spokenName = spokenName
        self.catalogKey = catalogKey
        self.exerciseID = exerciseID
        self.sets = sets
        self.matching = matching
    }

    /// Live readiness shared by every client: an explicit exercise and 1...100 valid sets.
    public var isValid: Bool {
        exerciseID != nil && !sets.isEmpty &&
            sets.count <= VoiceWorkoutDraftParser.maximumSetsPerBlock &&
            sets.allSatisfy(\.isValid)
    }

    public var issue: VoiceWorkoutBlockIssue? {
        if exerciseID == nil { return .chooseExercise }
        return isValid ? nil : .fixSets
    }
}

public enum VoiceWorkoutBlockIssue: String, Codable, Sendable {
    case chooseExercise
    case fixSets
}

public struct VoiceWorkoutSet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var weight: Double?
    public var reps: Int?

    public init(id: UUID = UUID(), weight: Double? = nil, reps: Int? = nil) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }

    public var isValid: Bool {
        guard let weight, let reps else { return false }
        return VoiceWorkoutDraftParser.isValidWeight(weight) && VoiceWorkoutDraftParser.isValidReps(reps)
    }
}

public enum VoiceWorkoutMatchStatus: Codable, Equatable, Sendable {
    case resolved
    case unresolved
    case ambiguous([VoiceWorkoutCandidate])

    public var isResolved: Bool {
        if case .resolved = self { return true }
        return false
    }
}

public struct VoiceWorkoutCandidate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let catalogKey: String?

    public init(id: UUID, name: String, catalogKey: String?) {
        self.id = id
        self.name = name
        self.catalogKey = catalogKey
    }
}

public struct VoiceWorkoutDiagnostic: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case empty
        case transcriptTooLong
        case missingExercise
        case missingSets
        case invalidNumber
        case unknownExercise
        case ambiguousExercise
        case limitsExceeded
    }

    public let kind: Kind
    /// The block the transcript problem belongs to; nil for transcript-wide notices.
    public let blockID: UUID?

    public init(kind: Kind, blockID: UUID? = nil) {
        self.kind = kind
        self.blockID = blockID
    }
}

/// One exercise the parser may resolve to, with every localized label and search alias.
public struct VoiceWorkoutExerciseInput: Sendable {
    public let id: UUID
    public let name: String
    public let catalogKey: String?
    public let aliases: [String]

    public init(id: UUID, name: String, catalogKey: String?, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.catalogKey = catalogKey
        self.aliases = aliases
    }
}

/// Implements shared/voice-workout-v1.json. Android (VoiceWorkoutDraftParser.kt) and the
/// PWA (pwa/voice-workout.js) use the same tables and algorithm; the shared golden cases
/// run on every client.
public enum VoiceWorkoutDraftParser {
    public static let schemaVersion = 1
    public static let maximumTranscriptBytes = 8 * 1024
    public static let maximumBlocks = 100
    public static let maximumSetsPerBlock = 100
    public static let maximumWeight = 1_000_000.0
    public static let maximumReps = 10_000
    public static let containsMatchMinimumLength = 8
    public static let localeIdentifiers = ["en": "en-US", "uk": "uk-UA", "ru": "ru-RU"]

    public static let separatorPhrases = [
        "и потом", "а потом", "после этого", "потом", "затем", "далее", "дальше",
        "після цього", "потім", "далі",
        "and then", "after that", "then", "next"
    ]
    public static let setWords = [
        "подход", "подхода", "подходов", "подходы",
        "підхід", "підходи", "підходів", "підхода",
        "set", "sets"
    ]
    public static let repWords = [
        "повтор", "повтора", "повторов", "повторы", "повторение", "повторения", "повторений", "раз", "раза",
        "повтори", "повторів", "повторення", "повторень", "рази", "разів",
        "rep", "reps", "repetition", "repetitions", "times"
    ]
    public static let weightWords = [
        "кг", "кило", "килограмм", "килограмма", "килограммов", "килограм",
        "кілограм", "кілограми", "кілограмів", "кілограма", "кіло",
        "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"
    ]
    public static let weightPrefixWords = ["вес", "весом", "веса", "вага", "вагою", "ваги", "weight", "weighing"]
    public static let connectorWords = [
        "по", "на", "x", "х", "×", "с", "со", "з", "зі", "із", "и", "і", "й", "та", "а", "без", "каждый", "кожен",
        "for", "of", "by", "with", "at", "and", "each", "bodyweight"
    ]
    public static let numberUnits: [String: Int] = [
        "ноль": 0, "один": 1, "одна": 1, "одно": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
        "нуль": 0, "одне": 1, "дві": 2, "чотири": 4, "п'ять": 5, "шість": 6, "сім": 7, "вісім": 8, "дев'ять": 9,
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9
    ]
    public static let numberTeens: [String: Int] = [
        "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
        "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
        "одинадцять": 11, "дванадцять": 12, "тринадцять": 13, "чотирнадцять": 14, "п'ятнадцять": 15,
        "шістнадцять": 16, "сімнадцять": 17, "вісімнадцять": 18, "дев'ятнадцять": 19,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    public static let numberTens: [String: Int] = [
        "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
        "семьдесят": 70, "восемьдесят": 80, "девяносто": 90,
        "двадцять": 20, "тридцять": 30, "п'ятдесят": 50, "шістдесят": 60, "сімдесят": 70,
        "вісімдесят": 80, "дев'яносто": 90,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]
    public static let numberHundreds: [String: Int] = [
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500,
        "двісті": 200, "чотириста": 400, "п'ятсот": 500
    ]
    public static let hundredMultipliers = ["hundred"]
    public static let voiceAliasesByCatalogKey: [String: [String]] = [
        "bench_press": ["жим лежа", "жим лежачи", "жим штанги лежа", "жим штанги лежачи", "bench"],
        "squat": ["присед", "присед со штангой", "приседания", "приседания со штангой", "присідання", "присідання зі штангою", "присід", "barbell squat", "back squat", "squats"],
        "pull_up": ["подтягивания", "подтягивание", "підтягування", "pull ups", "pullups", "chin ups"],
        "push_up": ["отжимания", "отжимания от пола", "віджимання", "віджимання від підлоги", "push ups", "pushups"],
        "dips": ["брусья", "отжимания на брусьях", "бруси", "віджимання на брусах"],
        "deadlift": ["становая", "становая тяга", "станова", "станова тяга"],
        "romanian_deadlift": ["румынская тяга", "румунська тяга", "rdl"],
        "leg_press": ["жим ногами", "жим ногами в тренажере", "жим ногами у тренажері"],
        "lat_pulldown": ["тяга верхнего блока", "тяга верхнього блока", "вертикальная тяга"],
        "barbell_row": ["тяга штанги в наклоне", "тяга штанги в нахилі"],
        "shoulder_press": ["жим над головой", "армейский жим", "жим над головою", "армійський жим", "overhead press"],
        "biceps_curl": ["подъем на бицепс", "бицепс", "біцепс", "curls"],
        "lunge": ["выпады", "випади", "lunges"],
        "plank": ["планка"],
        "calf_raise": ["подъем на носки", "підйом на носки", "calf raises"],
        "lateral_raise": ["махи в стороны", "махи гантелями в стороны", "розведення в сторони", "lateral raises"]
    ]

    private static let setWordSet = Set(setWords)
    private static let repWordSet = Set(repWords)
    private static let weightWordSet = Set(weightWords)
    private static let weightPrefixSet = Set(weightPrefixWords)
    private static let connectorSet = Set(connectorWords)
    private static let separatorTokens = separatorPhrases
        .map { $0.split(separator: " ").map(String.init) }
        .enumerated()
        .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
        .map(\.element)

    // MARK: Public API

    /// Production adapter: every localized display name plus the shared search aliases.
    public static func parse(
        transcript: String,
        exercises: [Exercise],
        makeID: () -> UUID = { UUID() }
    ) -> VoiceWorkoutDraft {
        let inputs = exercises.map { exercise in
            var aliases = ["en", "uk", "ru"].map { gymExerciseName(exercise, languageCode: $0) }
            if let key = exercise.catalogKey {
                aliases += ExerciseSearchVocabulary.aliasesByKey[key] ?? []
            }
            return VoiceWorkoutExerciseInput(id: exercise.id, name: exercise.name, catalogKey: exercise.catalogKey, aliases: aliases)
        }
        return parse(transcript: transcript, candidates: inputs, makeID: makeID)
    }

    public static func parse(
        transcript: String,
        candidates exercises: [VoiceWorkoutExerciseInput],
        makeID: () -> UUID = { UUID() }
    ) -> VoiceWorkoutDraft {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return VoiceWorkoutDraft(diagnostics: [VoiceWorkoutDiagnostic(kind: .empty)])
        }
        guard transcript.utf8.count <= maximumTranscriptBytes else {
            return VoiceWorkoutDraft(diagnostics: [VoiceWorkoutDiagnostic(kind: .transcriptTooLong)])
        }
        let candidates = exercises.map { exercise in
            Candidate(input: exercise, aliases: candidateAliases(exercise))
        }

        var entries: [ParsedEntry] = []
        for tokens in segment(tokenize(transcript)) {
            let name = spokenName(tokens)
            let match = matchExercise(name, candidates: candidates)
            let values = parseValues(tokens)
            let resolved = match.status == .resolved ? match.candidates.first : nil
            if let resolved, let index = entries.firstIndex(where: { $0.block.exerciseID == resolved.input.id }) {
                entries[index].block.sets += values.sets.map { VoiceWorkoutSet(id: makeID(), weight: $0.weight, reps: $0.reps) }
                entries[index].invalid = entries[index].invalid || values.invalid
                continue
            }
            let matching: VoiceWorkoutMatchStatus
            switch match.status {
            case .resolved: matching = .resolved
            case .ambiguous:
                matching = .ambiguous(match.candidates.map {
                    VoiceWorkoutCandidate(id: $0.input.id, name: $0.input.name, catalogKey: $0.input.catalogKey)
                })
            case .unresolved: matching = .unresolved
            }
            let blockID = makeID()
            entries.append(ParsedEntry(
                hasName: !name.isEmpty,
                invalid: values.invalid,
                block: VoiceWorkoutExerciseBlock(
                    id: blockID,
                    spokenName: name,
                    catalogKey: resolved?.input.catalogKey,
                    exerciseID: resolved?.input.id,
                    sets: values.sets.map { VoiceWorkoutSet(id: makeID(), weight: $0.weight, reps: $0.reps) },
                    matching: matching
                )
            ))
        }

        var diagnostics: [VoiceWorkoutDiagnostic] = []
        let tooManyBlocks = entries.count > maximumBlocks
        if tooManyBlocks { entries = Array(entries.prefix(maximumBlocks)) }
        for index in entries.indices {
            let blockID = entries[index].block.id
            if !entries[index].hasName {
                diagnostics.append(VoiceWorkoutDiagnostic(kind: .missingExercise, blockID: blockID))
            } else if case .ambiguous = entries[index].block.matching {
                diagnostics.append(VoiceWorkoutDiagnostic(kind: .ambiguousExercise, blockID: blockID))
            } else if !entries[index].block.matching.isResolved {
                diagnostics.append(VoiceWorkoutDiagnostic(kind: .unknownExercise, blockID: blockID))
            }
            let truncated = entries[index].block.sets.count > maximumSetsPerBlock
            if truncated { entries[index].block.sets = Array(entries[index].block.sets.prefix(maximumSetsPerBlock)) }
            let sets = entries[index].block.sets
            let hasInvalid = entries[index].invalid || sets.contains { set in
                (set.weight.map { !isValidWeight($0) } ?? false) || (set.reps.map { !isValidReps($0) } ?? false)
            }
            if hasInvalid {
                diagnostics.append(VoiceWorkoutDiagnostic(kind: .invalidNumber, blockID: blockID))
            } else if sets.contains(where: { $0.weight == nil || $0.reps == nil }) {
                diagnostics.append(VoiceWorkoutDiagnostic(kind: .missingSets, blockID: blockID))
            }
            if truncated { diagnostics.append(VoiceWorkoutDiagnostic(kind: .limitsExceeded, blockID: blockID)) }
        }
        if tooManyBlocks { diagnostics.append(VoiceWorkoutDiagnostic(kind: .limitsExceeded)) }
        return VoiceWorkoutDraft(blocks: entries.map(\.block), diagnostics: diagnostics)
    }

    public static func isValidWeight(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumWeight
    }

    public static func isValidReps(_ value: Int) -> Bool {
        (1 ... maximumReps).contains(value)
    }

    /// Cuts on character boundaries so the result never exceeds the byte budget.
    public static func truncatedUTF8(_ value: String, maxBytes: Int = maximumTranscriptBytes) -> String {
        var bytes = 0
        var result = ""
        for character in value {
            let size = String(character).utf8.count
            if bytes + size > maxBytes { break }
            bytes += size
            result.append(character)
        }
        return result
    }

    public static func formatWeight(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    /// nil = empty field; .nan = text that is not a number.
    public static func parseWeightInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(trimmed) else { return .nan }
        return value
    }

    // MARK: Normalization

    static func normalizeWord(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "`", with: "'")
    }

    static func normalizeName(_ value: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in normalizeWord(value.precomposedStringWithCanonicalMapping) {
            if character.isLetter || isDigit(character) || character == "'" {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    private static func isDigit(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’" || character == "ʼ" || character == "`"
    }

    // MARK: Tokens

    private enum Token {
        case word(raw: String, norm: String)
        case number(Double)
        case separator

        var norm: String? {
            if case let .word(_, norm) = self { return norm }
            return nil
        }

        var isNumber: Bool {
            if case .number = self { return true }
            return false
        }
    }

    private static func tokenize(_ transcript: String) -> [Token] {
        let characters = Array(transcript.precomposedStringWithCanonicalMapping)
        var tokens: [Token] = []
        var index = 0
        func at(_ position: Int) -> Character? {
            position >= 0 && position < characters.count ? characters[position] : nil
        }
        while index < characters.count {
            let character = characters[index]
            let previous = at(index - 1)
            let next = at(index + 1)
            if isDigit(character) || (character == "-" && next.map(isDigit) == true && previous.map(isDigit) != true) {
                var text = String(character)
                index += 1
                while let current = at(index), isDigit(current) { text.append(current); index += 1 }
                if let separator = at(index), separator == "." || separator == ",", at(index + 1).map(isDigit) == true {
                    text.append(".")
                    index += 1
                    while let current = at(index), isDigit(current) { text.append(current); index += 1 }
                }
                tokens.append(.number(Double(text) ?? .nan))
                continue
            }
            if character == "×" {
                tokens.append(.word(raw: "×", norm: "×"))
                index += 1
                continue
            }
            if character.isLetter {
                var raw = String(character)
                index += 1
                while let current = at(index), current.isLetter || isApostrophe(current) { raw.append(current); index += 1 }
                while let last = raw.last, isApostrophe(last) { raw.removeLast() }
                tokens.append(.word(raw: raw, norm: normalizeWord(raw)))
                continue
            }
            if [";", "\n", "\r", "\r\n", ".", "!", "?"].contains(character) {
                tokens.append(.separator)
            }
            index += 1
        }
        return combineNumberWords(tokens)
    }

    private enum NumberClass { case hundreds, tens, teens, units, multiplier }

    private static func numberWordClass(_ norm: String) -> (NumberClass, Int)? {
        if let value = numberHundreds[norm] { return (.hundreds, value) }
        if let value = numberTens[norm] { return (.tens, value) }
        if let value = numberTeens[norm] { return (.teens, value) }
        if let value = numberUnits[norm] { return (.units, value) }
        if hundredMultipliers.contains(norm) { return (.multiplier, 100) }
        return nil
    }

    private static func combineNumberWords(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var total: Int?
        var allowed: Set<NumberClass> = []
        func flush() {
            if let total { result.append(.number(Double(total))) }
            total = nil
            allowed = []
        }
        func nextAllowed(_ kind: NumberClass, total: Int) -> Set<NumberClass> {
            switch kind {
            case .hundreds, .multiplier: [.tens, .teens, .units]
            case .tens: [.units]
            case .units: total < 10 ? [.multiplier] : []
            case .teens: []
            }
        }
        for token in tokens {
            guard let norm = token.norm, let (kind, value) = numberWordClass(norm) else {
                flush()
                result.append(token)
                continue
            }
            if let current = total, allowed.contains(kind) {
                let updated = kind == .multiplier ? current * 100 : current + value
                total = updated
                allowed = nextAllowed(kind, total: updated)
                continue
            }
            flush()
            if kind == .multiplier {
                result.append(token)
                continue
            }
            total = value
            allowed = nextAllowed(kind, total: value)
        }
        flush()
        return result
    }

    private static func isMetadataWord(_ norm: String) -> Bool {
        connectorSet.contains(norm) || setWordSet.contains(norm) || repWordSet.contains(norm) ||
            weightWordSet.contains(norm) || weightPrefixSet.contains(norm)
    }

    private static func separatorLength(_ tokens: [Token], at index: Int) -> Int {
        for phrase in separatorTokens {
            var matches = true
            for offset in phrase.indices {
                let position = index + offset
                guard position < tokens.count, tokens[position].norm == phrase[offset] else {
                    matches = false
                    break
                }
            }
            if matches { return phrase.count }
        }
        return 0
    }

    private static func segment(_ tokens: [Token]) -> [[Token]] {
        var segments: [[Token]] = []
        var current: [Token] = []
        var seenNumber = false
        func close() {
            if current.contains(where: { token in
                token.isNumber || (token.norm.map { !isMetadataWord($0) } ?? false)
            }) {
                segments.append(current)
            }
            current = []
            seenNumber = false
        }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if case .separator = token {
                close()
                index += 1
                continue
            }
            let separator = separatorLength(tokens, at: index)
            if separator > 0 {
                close()
                index += separator
                continue
            }
            if let norm = token.norm, seenNumber, !isMetadataWord(norm) { close() }
            if token.isNumber { seenNumber = true }
            current.append(token)
            index += 1
        }
        close()
        return segments
    }

    private static func spokenName(_ tokens: [Token]) -> String {
        let prefix = tokens.prefix { !$0.isNumber }
        var words: [(raw: String, norm: String)] = prefix.compactMap { token in
            if case let .word(raw, norm) = token { return (raw, norm) }
            return nil
        }
        while let first = words.first, isMetadataWord(first.norm) { words.removeFirst() }
        while let last = words.last, isMetadataWord(last.norm) { words.removeLast() }
        return words.map(\.raw).joined(separator: " ")
    }

    // MARK: Matching

    private struct Candidate {
        let input: VoiceWorkoutExerciseInput
        let aliases: Set<String>
    }

    private enum MatchStatus { case resolved, ambiguous, unresolved }

    private static func candidateAliases(_ exercise: VoiceWorkoutExerciseInput) -> Set<String> {
        var aliases = [exercise.name] + exercise.aliases
        if let key = exercise.catalogKey { aliases += voiceAliasesByCatalogKey[key] ?? [] }
        return Set(aliases.map(normalizeName).filter { !$0.isEmpty })
    }

    private static func matchExercise(_ name: String, candidates: [Candidate]) -> (status: MatchStatus, candidates: [Candidate]) {
        let normalized = normalizeName(name)
        guard !normalized.isEmpty else { return (.unresolved, []) }
        let padded = " \(normalized) "
        var exact: [Candidate] = []
        var contained: [(Candidate, Int)] = []
        var bestScore = 0
        for candidate in candidates {
            if candidate.aliases.contains(normalized) {
                exact.append(candidate)
                continue
            }
            let score = candidate.aliases
                .filter { $0.count >= containsMatchMinimumLength && padded.contains(" \($0) ") }
                .map(\.count)
                .max() ?? 0
            if score > 0 {
                contained.append((candidate, score))
                bestScore = max(bestScore, score)
            }
        }
        let chosen = exact.isEmpty ? contained.filter { $0.1 == bestScore }.map(\.0) : exact
        var seen = Set<UUID>()
        let unique = chosen.filter { seen.insert($0.input.id).inserted }
        switch unique.count {
        case 1: return (.resolved, unique)
        case 0: return (.unresolved, [])
        default: return (.ambiguous, unique)
        }
    }

    // MARK: Values

    private struct ParsedEntry {
        var hasName: Bool
        var invalid: Bool
        var block: VoiceWorkoutExerciseBlock
    }

    private struct RawSet {
        var weight: Double?
        var reps: Int?
    }

    private enum ValueTag { case set, rep, weight }

    private static func repsValue(_ raw: Double?, invalid: inout Bool) -> Int? {
        guard let raw else { return nil }
        guard raw.isFinite, raw.rounded() == raw, let value = Int(exactly: raw) else {
            invalid = true
            return nil
        }
        return value
    }

    private static func parseValues(_ tokens: [Token]) -> (sets: [RawSet], invalid: Bool) {
        var invalid = false
        var numbers: [(value: Double, tag: ValueTag?)] = []
        for index in tokens.indices {
            guard case let .number(value) = tokens[index] else { continue }
            var tag: ValueTag?
            if index + 1 < tokens.count, let next = tokens[index + 1].norm {
                if setWordSet.contains(next) { tag = .set }
                else if repWordSet.contains(next) { tag = .rep }
                else if weightWordSet.contains(next) { tag = .weight }
            }
            if tag == nil, index > 0, let previous = tokens[index - 1].norm, weightPrefixSet.contains(previous) {
                tag = .weight
            }
            numbers.append((value, tag))
        }
        guard !numbers.isEmpty else { return ([RawSet()], invalid) }

        if let setEntry = numbers.first(where: { $0.tag == .set }) {
            var reps = numbers.first(where: { $0.tag == .rep })?.value
            var weight = numbers.first(where: { $0.tag == .weight })?.value
            for entry in numbers where entry.tag == nil {
                if reps == nil { reps = entry.value }
                else if weight == nil { weight = entry.value }
            }
            let repsInteger = repsValue(reps, invalid: &invalid)
            if reps == nil && weight == nil { return ([RawSet()], invalid) }
            if weight == nil && repsInteger != nil { weight = 0 }
            let count = setEntry.value
            guard count.isFinite, count.rounded() == count, count >= 1 else {
                invalid = true
                return ([RawSet(weight: weight, reps: repsInteger)], invalid)
            }
            let bounded = Int(min(count, Double(maximumSetsPerBlock + 1)))
            return (Array(repeating: RawSet(weight: weight, reps: repsInteger), count: bounded), invalid)
        }

        var sets: [RawSet] = []
        var weight: Double?
        var reps: Int?
        var hasReps = false
        func push() {
            if weight != nil || hasReps { sets.append(RawSet(weight: weight, reps: reps)) }
            weight = nil
            reps = nil
            hasReps = false
        }
        for entry in numbers {
            switch entry.tag {
            case .rep:
                if hasReps { push() }
                reps = repsValue(entry.value, invalid: &invalid)
                hasReps = true
            case .weight:
                if weight != nil { push() }
                weight = entry.value
            default:
                if weight == nil && !hasReps {
                    weight = entry.value
                } else if weight != nil && !hasReps {
                    reps = repsValue(entry.value, invalid: &invalid)
                    hasReps = true
                } else if weight == nil {
                    weight = entry.value
                } else {
                    push()
                    weight = entry.value
                }
            }
            if weight != nil && hasReps { push() }
        }
        push()
        return (sets, invalid)
    }
}
