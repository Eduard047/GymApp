import Foundation

/// One in-workout voice command, decoded from a single spoken utterance.
/// Implements `shared/voice-workout-command-v1.json`. Separate entry point
/// from plan dictation (`VoiceWorkoutDraftParser.parse`): one utterance maps
/// to one typed intent, never a block list.
public enum VoiceWorkoutCommand: Equatable, Sendable {
    case logSet(weightKg: Double?, reps: Int?)
    case repeatPrevious
    case skipRest
    case unknown(transcript: String, code: String?)
}

/// Reserved for forward-compatible tie-breaking (e.g. the set currently
/// being edited). Matching itself is locale-agnostic, exactly like
/// `VoiceWorkoutDraftParser.parse`.
public struct VoiceWorkoutCommandContext: Sendable {
    public init() {}
}

/// Android (`VoiceWorkoutCommandParser.kt`) and the PWA
/// (`pwa/voice-workout.js` → `parseVoiceWorkoutCommand`) implement the same
/// algorithm; `shared/voice-workout-command-v1.json`'s golden cases run on
/// every client. This parser reuses `VoiceWorkoutDraftParser`'s tokenizer,
/// number-word tables, and weight/rep/connector word sets rather than
/// redefining them, per the contract's `extends` note.
public enum VoiceWorkoutCommandParser {
    public static let maximumTranscriptBytes = VoiceWorkoutDraftParser.maximumTranscriptBytes
    public static let minWeightKg = 0.0
    public static let maxWeightKg = 1000.0
    public static let weightStepKg = 0.25
    public static let minReps = 1
    public static let maxReps = 200

    public static let fillerWords = [
        "ну", "эм", "окей", "ага",
        "емм", "гаразд",
        "um", "uh", "okay", "ok"
    ]
    public static let bodyweightPhrases = [
        "с собственным весом", "собственным весом", "своим весом",
        "власною вагою", "власним вагою", "з власною вагою",
        "bodyweight", "body weight", "own bodyweight"
    ]
    public static let repeatPhrases = [
        "повтори", "ещё раз так же", "то же самое", "повтор",
        "ще раз",
        "repeat", "same again"
    ]
    public static let skipPhrases = [
        "дальше", "пропусти отдых", "готов", "поехали",
        "далі", "пропусти відпочинок", "готовий",
        "next", "skip rest", "ready"
    ]
    public static let diagnosticCodes = [
        "empty", "transcriptTooLong",
        "ambiguousNumbers", "weightOutOfRange", "repsOutOfRange", "invalidWeightStep",
        "noMatch"
    ]

    private static let fillerSet = Set(fillerWords)

    private static func toPhraseWords(_ phrase: String) -> [String] {
        phrase.split(separator: " ").map { VoiceWorkoutDraftParser.normalizeWord(String($0)) }
    }

    // Longest phrase first so a longer bodyweight phrase wins over a
    // shorter one it contains (mirrors pwa/voice-workout.js findPhraseRun).
    private static let bodyweightPhraseWords = bodyweightPhrases
        .map(toPhraseWords)
        .enumerated()
        .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
        .map(\.element)
    private static let repeatPhraseWords = repeatPhrases.map(toPhraseWords)
    private static let skipPhraseWords = skipPhrases.map(toPhraseWords)

    /// Never throws/traps: any transcript resolves to a `VoiceWorkoutCommand`,
    /// falling back to `.unknown` on hostile or unrecognized input.
    public static func parse(
        _ transcript: String?,
        locale: String = "ru",
        context: VoiceWorkoutCommandContext = VoiceWorkoutCommandContext()
    ) -> VoiceWorkoutCommand {
        let raw = transcript ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(transcript: raw, code: "empty") }
        guard raw.utf8.count <= maximumTranscriptBytes else {
            return .unknown(transcript: VoiceWorkoutDraftParser.truncatedUTF8(raw), code: "transcriptTooLong")
        }

        var tokens = VoiceWorkoutDraftParser.tokenize(raw).filter { token in
            if case .separator = token { return false }
            return true
        }
        tokens = tokens.filter { token in
            guard case let .word(_, norm) = token else { return true }
            return !fillerSet.contains(norm)
        }

        let hasNumber = tokens.contains(where: \.isNumber)
        if !hasNumber {
            if wordSequenceMatchesAny(tokens, repeatPhraseWords) { return .repeatPrevious }
            if wordSequenceMatchesAny(tokens, skipPhraseWords) { return .skipRest }
            return .unknown(transcript: raw, code: "noMatch")
        }

        var isBodyweight = false
        if let run = findPhraseRun(tokens, bodyweightPhraseWords) {
            tokens.removeSubrange(run.start ..< (run.start + run.length))
            isBodyweight = true
        }

        let numberEntries = numberEntries(in: tokens)

        if isBodyweight {
            guard numberEntries.count == 1 else { return .unknown(transcript: raw, code: "ambiguousNumbers") }
            return finalize(raw, weightKg: 0, reps: numberEntries[0].value)
        }

        guard !numberEntries.isEmpty else { return .unknown(transcript: raw, code: "noMatch") }

        if numberEntries.count == 1 {
            let only = numberEntries[0]
            if only.tag == .weight { return finalize(raw, weightKg: only.value, reps: nil) }
            if only.tag == .rep { return finalize(raw, weightKg: nil, reps: only.value) }
            return .unknown(transcript: raw, code: "ambiguousNumbers")
        }

        if numberEntries.count == 2 {
            let first = numberEntries[0]
            let second = numberEntries[1]
            let taggedWeight = numberEntries.filter { $0.tag == .weight }
            let taggedRep = numberEntries.filter { $0.tag == .rep }
            let untagged = numberEntries.filter { $0.tag == nil }
            if taggedWeight.count == 1, taggedRep.count == 1 {
                return finalize(raw, weightKg: taggedWeight[0].value, reps: taggedRep[0].value)
            }
            if taggedWeight.count == 1, untagged.count == 1 {
                return finalize(raw, weightKg: taggedWeight[0].value, reps: untagged[0].value)
            }
            if taggedRep.count == 1, untagged.count == 1 {
                return finalize(raw, weightKg: untagged[0].value, reps: taggedRep[0].value)
            }
            if untagged.count == 2, first.index < second.index, first.index + 1 <= second.index {
                let between = tokens[(first.index + 1) ..< second.index]
                let hasConnector = between.contains { token in
                    guard case let .word(_, norm) = token else { return false }
                    return VoiceWorkoutDraftParser.connectorSet.contains(norm)
                }
                if hasConnector { return finalize(raw, weightKg: first.value, reps: second.value) }
            }
            return .unknown(transcript: raw, code: "ambiguousNumbers")
        }

        return .unknown(transcript: raw, code: "ambiguousNumbers")
    }

    // MARK: Number tagging

    private enum ValueTag { case weight, rep }

    private struct NumberEntry {
        let value: Double
        let tag: ValueTag?
        let index: Int
    }

    private static func numberEntries(in tokens: [VoiceWorkoutDraftParser.Token]) -> [NumberEntry] {
        var entries: [NumberEntry] = []
        for index in tokens.indices {
            guard case let .number(value) = tokens[index] else { continue }
            var tag: ValueTag?
            if index + 1 < tokens.count, case let .word(_, norm) = tokens[index + 1] {
                if VoiceWorkoutDraftParser.weightWordSet.contains(norm) { tag = .weight }
                else if VoiceWorkoutDraftParser.repWordSet.contains(norm) { tag = .rep }
            }
            entries.append(NumberEntry(value: value, tag: tag, index: index))
        }
        return entries
    }

    // MARK: Phrase matching

    private static func wordSequenceMatches(_ tokens: [VoiceWorkoutDraftParser.Token], _ phraseWords: [String]) -> Bool {
        guard tokens.count == phraseWords.count else { return false }
        for index in tokens.indices {
            guard case let .word(_, norm) = tokens[index], norm == phraseWords[index] else { return false }
        }
        return true
    }

    private static func wordSequenceMatchesAny(
        _ tokens: [VoiceWorkoutDraftParser.Token],
        _ phraseWordsList: [[String]]
    ) -> Bool {
        phraseWordsList.contains { wordSequenceMatches(tokens, $0) }
    }

    /// First contiguous run of word tokens equal to one of `phraseWordsList`.
    private static func findPhraseRun(
        _ tokens: [VoiceWorkoutDraftParser.Token],
        _ phraseWordsList: [[String]]
    ) -> (start: Int, length: Int)? {
        for phraseWords in phraseWordsList {
            guard !phraseWords.isEmpty else { continue }
            var start = 0
            while start + phraseWords.count <= tokens.count {
                var matches = true
                for offset in phraseWords.indices {
                    guard case let .word(_, norm) = tokens[start + offset], norm == phraseWords[offset] else {
                        matches = false
                        break
                    }
                }
                if matches { return (start, phraseWords.count) }
                start += 1
            }
        }
        return nil
    }

    // MARK: Finalization

    private static func finalize(_ raw: String, weightKg: Double?, reps: Double?) -> VoiceWorkoutCommand {
        if let weightKg {
            guard weightKg.isFinite, weightKg >= minWeightKg, weightKg <= maxWeightKg else {
                return .unknown(transcript: raw, code: "weightOutOfRange")
            }
            let scaled = weightKg / weightStepKg
            guard abs(scaled - scaled.rounded()) <= 1e-6 else {
                return .unknown(transcript: raw, code: "invalidWeightStep")
            }
        }
        var repsInt: Int?
        if let reps {
            guard reps.isFinite, reps.rounded() == reps, let intValue = Int(exactly: reps),
                  intValue >= minReps, intValue <= maxReps else {
                return .unknown(transcript: raw, code: "repsOutOfRange")
            }
            repsInt = intValue
        }
        return .logSet(weightKg: weightKg, reps: repsInt)
    }
}
