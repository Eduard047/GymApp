import Foundation

/// The editable weight text in the app language's decimal separator (ru/uk comma, en dot), the same
/// number format as `gymWeightText` but without digit grouping. Typing accepts both '.' and ',' regardless of the phone's region.
/// Parsing mirrors Android's `parseWeightInputOrNull`.
struct GymWeightFieldFormat: ParseableFormatStyle {
    var languageCode: String

    /// Android `MAX_WEIGHT_INPUT_LENGTH`.
    private static let maximumInputLength = 64

    /// Trims, treats ',' as '.', and returns nil for blank, over-long, non-numeric, non-finite,
    /// negative, or above-maximum-weight text.
    nonisolated static func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, normalized.count <= maximumInputLength,
              let number = Double(normalized),
              number.isFinite, number >= 0, number <= ActiveWorkoutStore.maximumWeight else {
            return nil
        }
        return number
    }

    /// Never groups digits: "1,000" would read back as 1 and "1 000" would not parse at all, so a
    /// weight of 1000 kg or more must round-trip through the field as plain digits.
    func format(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0 ... 2))
                .grouping(.never)
                .locale(gymAppLocale(languageCode: languageCode))
        )
    }

    var parseStrategy: Strategy { Strategy() }

    struct Strategy: ParseStrategy {
        func parse(_ value: String) throws -> Double {
            guard let number = GymWeightFieldFormat.parse(value) else {
                throw CocoaError(.formatting)
            }
            return number
        }
    }
}
