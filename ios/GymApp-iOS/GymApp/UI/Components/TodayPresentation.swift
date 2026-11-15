import Foundation

/// Pure presentation rules of the Today tab. Contract: shared/today-presentation-v1.json
/// (Android runs the same cases).
enum TodayPresentation {
    /// Two-letter weekday labels for the history strip, Monday first: ru/uk lowercase, en
    /// capitalized ("Mo Tu ...").
    static func weekdayLabels(languageCode: String) -> [String] {
        switch languageCode {
        case AppLanguage.russian.rawValue:
            ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
        case AppLanguage.ukrainian.rawValue:
            ["пн", "вт", "ср", "чт", "пт", "сб", "нд"]
        default:
            ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        }
    }

    /// `index` 0 = Monday ... 6 = Sunday; out-of-range values wrap.
    static func weekdayLabel(mondayIndex index: Int, languageCode: String) -> String {
        let labels = weekdayLabels(languageCode: languageCode)
        return labels[((index % 7) + 7) % 7]
    }

    /// The week-over-week comparison is shown only when both weeks have a workout: a drop to
    /// "-100%" on an empty week (or a jump from nothing) says nothing.
    static func showsWeekComparison(currentWorkouts: Int, comparisonWorkouts: Int) -> Bool {
        currentWorkouts >= 1 && comparisonWorkouts >= 1
    }

    enum StatNoun {
        case workout
        case minute
    }

    /// Lowercase unit label that agrees with the number it sits under: "1 тренировка",
    /// "2 тренировки", "5 тренировок", "1 минута", "2 минуты", "5 минут".
    static func statLabel(_ noun: StatNoun, count: Int, languageCode: String) -> String {
        switch noun {
        case .workout:
            gymPlural(
                count,
                en: ("workout", "workouts"),
                uk: ("тренування", "тренування", "тренувань"),
                ru: ("тренировка", "тренировки", "тренировок"),
                languageCode: languageCode
            )
        case .minute:
            gymPlural(
                count,
                en: ("minute", "minutes"),
                uk: ("хвилина", "хвилини", "хвилин"),
                ru: ("минута", "минуты", "минут"),
                languageCode: languageCode
            )
        }
    }
}
