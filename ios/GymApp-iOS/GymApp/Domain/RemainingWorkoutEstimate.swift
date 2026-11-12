import Foundation

/// "N sets left · ~M min" for the active workout.
///
/// Shared contract: `shared/remaining-workout-estimate-v1.json` (Android runs the same cases).
///
/// Rule: `setsLeft` is the number of sets not yet recorded. `minutes` reuses the coefficients of
/// the plan-duration estimate (`TodayFocusPlanMetrics.estimatedMinutes`: 3 min per exercise plus
/// 2 min per set) applied to what is left: `3 * exercisesWithSetsLeft + 2 * setsLeft`, never less
/// than 1. That estimate is a flat model with no per-exercise rest, so none is added here. Its
/// 10-minute floor and 90-minute cap are plan-sanity bounds and are deliberately not applied: one
/// remaining set must not read "~10 min". No sets left means no estimate. A running rest timer is
/// ignored.
enum RemainingWorkoutEstimate {
    static let minutesPerExercise = 3
    static let minutesPerSet = 2

    struct Result: Equatable, Sendable {
        let setsLeft: Int
        let minutes: Int
    }

    /// - Parameter remainingSetsPerExercise: unrecorded set count of each exercise, in any order.
    ///   Negative values count as 0.
    static func estimate(remainingSetsPerExercise: [Int]) -> Result? {
        let counts = remainingSetsPerExercise.map { max(0, $0) }
        let setsLeft = counts.reduce(0, +)
        guard setsLeft > 0 else { return nil }
        let exercisesLeft = counts.lazy.filter { $0 > 0 }.count
        let minutes = max(1, minutesPerExercise * exercisesLeft + minutesPerSet * setsLeft)
        return Result(setsLeft: setsLeft, minutes: minutes)
    }

    static func estimate(draft: ActiveWorkoutDraft) -> Result? {
        estimate(
            remainingSetsPerExercise: draft.exercises.map { exercise in
                exercise.sets.lazy.filter { !$0.isCompleted }.count
            }
        )
    }

    /// "5 sets left · ~12 min", "Залишилось 5 підходів · ~12 хв", "Осталось 5 подходов · ~12 мин".
    static func text(_ result: Result, languageCode: String) -> String {
        let phrase = setsLeftPhrase(result.setsLeft, languageCode: languageCode)
        let minutes = result.minutes
        let time = gymText(
            "~\(minutes)\u{00A0}min",
            "~\(minutes)\u{00A0}хв",
            "~\(minutes)\u{00A0}мин",
            languageCode: languageCode
        )
        return "\(phrase) · \(time)"
    }

    /// "5 sets left, about 12 minutes", read naturally by VoiceOver.
    static func accessibilityText(_ result: Result, languageCode: String) -> String {
        let phrase = setsLeftPhrase(result.setsLeft, languageCode: languageCode)
        let minutes = result.minutes
        let unit = gymPlural(
            minutes,
            en: (one: "minute", many: "minutes"),
            uk: (one: "хвилина", few: "хвилини", many: "хвилин"),
            ru: (one: "минута", few: "минуты", many: "минут"),
            languageCode: languageCode
        )
        return gymText(
            "\(phrase), about \(minutes) \(unit)",
            "\(phrase), приблизно \(minutes) \(unit)",
            "\(phrase), примерно \(minutes) \(unit)",
            languageCode: languageCode
        )
    }

    /// Verb agrees with the count: "1 set left" / "Залишився 1 підхід" / "Осталось 5 подходов".
    private static func setsLeftPhrase(_ count: Int, languageCode: String) -> String {
        let counted = gymCount(
            count,
            englishOne: "set", englishMany: "sets",
            ukrainianOne: "підхід", ukrainianFew: "підходи", ukrainianMany: "підходів",
            languageCode: languageCode
        ).gymBindingFirstSpace
        let category = gymPluralCategory(count, languageCode: languageCode)
        return gymText(
            "\(counted) left",
            "\(category == .one ? "Залишився" : "Залишилось") \(counted)",
            "\(category == .one ? "Остался" : "Осталось") \(counted)",
            languageCode: languageCode
        )
    }
}
