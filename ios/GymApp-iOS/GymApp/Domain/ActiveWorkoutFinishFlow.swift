import Foundation

/// What a tap on the active workout's top-bar "Finish" does. Pure so the decision and the dialog
/// copy are unit-tested without the view.
enum ActiveWorkoutFinishDecision: Equatable {
    /// Every planned set is logged (or nothing is planned), or a commit retry is pending: finish now.
    case finishNow
    /// `count` planned sets are not logged: ask before dropping them.
    case confirmUnlogged(count: Int)

    static func decide(planned: Int, completed: Int, hasCommitIntent: Bool) -> ActiveWorkoutFinishDecision {
        let unlogged = max(planned - completed, 0)
        guard !hasCommitIntent, unlogged > 0 else { return .finishNow }
        return .confirmUnlogged(count: unlogged)
    }
}

/// Copy of the finish dialogs, ru/uk/en with correct plural forms. Android uses the same wording.
enum ActiveWorkoutFinishCopy {
    // MARK: Finish workout

    static func workoutTitle(languageCode: String) -> String {
        gymText("Finish workout?", "Завершити тренування?", "Завершить тренировку?", languageCode: languageCode)
    }

    static func workoutMessage(unlogged count: Int, languageCode: String) -> String {
        switch languageCode {
        case AppLanguage.russian.rawValue:
            switch gymPluralCategory(count, languageCode: languageCode) {
            case .one: return "Не записан \(count) подход — он не попадёт в историю."
            case .few: return "Не записано \(count) подхода — они не попадут в историю."
            case .many: return "Не записано \(count) подходов — они не попадут в историю."
            }
        case AppLanguage.ukrainian.rawValue:
            switch gymPluralCategory(count, languageCode: languageCode) {
            case .one: return "Не записано \(count) підхід — він не потрапить в історію."
            case .few: return "Не записано \(count) підходи — вони не потраплять в історію."
            case .many: return "Не записано \(count) підходів — вони не потраплять в історію."
            }
        default:
            return count == 1
                ? "\(count) set isn't logged — it won't be saved."
                : "\(count) sets aren't logged — they won't be saved."
        }
    }

    static func finishButton(languageCode: String) -> String {
        gymText("Finish", "Завершити", "Завершить", languageCode: languageCode)
    }

    static func markAllDoneButton(languageCode: String) -> String {
        gymText("Mark all as done", "Позначити всі як виконані", "Отметить все как выполненные", languageCode: languageCode)
    }

    static func cancelButton(languageCode: String) -> String {
        gymText("Cancel", "Скасувати", "Отмена", languageCode: languageCode)
    }

    // MARK: Finish exercise

    static func exerciseTitle(languageCode: String) -> String {
        gymText("Finish exercise?", "Завершити вправу?", "Завершить упражнение?", languageCode: languageCode)
    }

    static func exerciseMessage(unlogged count: Int, languageCode: String) -> String {
        switch languageCode {
        case AppLanguage.russian.rawValue:
            switch gymPluralCategory(count, languageCode: languageCode) {
            case .one: return "Не записан \(count) подход"
            case .few: return "Не записано \(count) подхода"
            case .many: return "Не записано \(count) подходов"
            }
        case AppLanguage.ukrainian.rawValue:
            switch gymPluralCategory(count, languageCode: languageCode) {
            case .one: return "Не записано \(count) підхід"
            case .few: return "Не записано \(count) підходи"
            case .many: return "Не записано \(count) підходів"
            }
        default:
            return count == 1 ? "\(count) set isn't logged" : "\(count) sets aren't logged"
        }
    }

    /// "Finish without them" (skips the unlogged sets); singular reads "without it".
    static func exerciseFinishWithoutButton(unlogged count: Int, languageCode: String) -> String {
        let one = count == 1
        return gymText(
            one ? "Finish without it" : "Finish without them",
            one ? "Завершити без нього" : "Завершити без них",
            one ? "Завершить без него" : "Завершить без них",
            languageCode: languageCode
        )
    }

    static func exerciseMarkDoneButton(languageCode: String) -> String {
        gymText("Mark as done", "Позначити як виконані", "Отметить как выполненные", languageCode: languageCode)
    }
}

/// Normalizes the typed text of a weight or reps field. Strips leading zeros of the integer part
/// ("006" -> "6", "0060" -> "60") and keeps "0", "0.5" and "0,5". The decimal separator the user
/// typed is preserved; non-numeric text is returned unchanged.
enum GymNumericInputNormalizer {
    static func normalize(_ text: String) -> String {
        let separatorIndex = text.firstIndex { $0 == "." || $0 == "," }
        let integerPart = separatorIndex.map { String(text[..<$0]) } ?? text
        let rest = separatorIndex.map { String(text[$0...]) } ?? ""
        guard !integerPart.isEmpty, integerPart.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return text }
        let stripped = integerPart.drop { $0 == "0" }
        // "00" -> "0", "000,5" -> "0,5"; digits other than zero are kept as typed.
        return (stripped.isEmpty ? "0" : String(stripped)) + rest
    }
}
