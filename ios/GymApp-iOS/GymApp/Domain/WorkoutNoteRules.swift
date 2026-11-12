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
        (try? validate(raw)) != nil
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
        var codePoints = 0
        for scalar in raw.unicodeScalars {
            codePoints += 1
            if codePoints > maxCodePoints { throw Failure.tooLong }
            if scalar.properties.generalCategory == .control,
               scalar != "\t", scalar != "\n", scalar != "\r" {
                throw Failure.controlCharacter
            }
        }
        if raw.utf8.count > maxUTF8Bytes { throw Failure.tooLong }
    }
}
