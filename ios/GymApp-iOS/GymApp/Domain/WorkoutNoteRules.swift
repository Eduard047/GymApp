import Foundation

/// The rule for editing the workout note during an active workout, shared with Android through
/// `shared/workout-note-v1.json`. The raw input is validated first (code points, UTF-8 bytes,
/// control characters), then trimmed; an empty result means no note.
enum WorkoutNoteRules {
    static let maxCodePoints = 4_000
    static let maxUTF8Bytes = 16_000

    enum Failure: Error, Equatable {
        case tooLong
        case controlCharacter
    }

    /// True when `raw` passes the raw-input checks, before any trimming.
    static func isValid(_ raw: String) -> Bool {
        failure(raw) == nil
    }

    /// Why `raw` is refused, or nil when it is valid. Length (code points, UTF-8 bytes) is judged
    /// before control characters, so an input that is both too long and unsafe reports `.tooLong`.
    /// Mirrors `WorkoutDataLimits.noteFailure` on Android (shared/workout-note-v1.json).
    static func failure(_ raw: String) -> Failure? {
        if raw.unicodeScalars.count > maxCodePoints || raw.utf8.count > maxUTF8Bytes {
            return .tooLong
        }
        let unsafe = raw.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control
                && scalar != "\t" && scalar != "\n" && scalar != "\r"
        }
        return unsafe ? .controlCharacter : nil
    }

    /// Cuts `raw` to at most `maxCodePoints` Unicode code points (never graphemes).
    static func limited(_ raw: String) -> String {
        guard raw.unicodeScalars.count > maxCodePoints else { return raw }
        return String(String.UnicodeScalarView(raw.unicodeScalars.prefix(maxCodePoints)))
    }

    /// Returns the value to store: trimmed text, or nil for nothing / whitespace only.
    /// Throws when the raw input is too long or holds a control character other than tab, LF, CR.
    static func normalized(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        try validate(raw)
        let trimmed = raw.gymTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validate(_ raw: String) throws {
        if let failure = failure(raw) { throw failure }
    }
}
