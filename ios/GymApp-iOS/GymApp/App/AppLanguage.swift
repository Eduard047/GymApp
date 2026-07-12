import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case ukrainian = "uk"

    var id: String { rawValue }
    var title: String { self == .english ? "EN" : "UK" }
    var locale: Locale { Locale(identifier: rawValue) }
}

private let gymAppLanguageDefaultsKey = "app-language"

func gymCurrentLanguageCode() -> String {
    UserDefaults.standard.string(forKey: gymAppLanguageDefaultsKey) ?? AppLanguage.english.rawValue
}

func gymText(_ english: String, _ ukrainian: String, languageCode: String) -> String {
    languageCode == AppLanguage.ukrainian.rawValue ? ukrainian : english
}

func gymExerciseName(
    _ exercise: Exercise,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    BuiltInExerciseCatalog.displayName(
        catalogKey: exercise.catalogKey,
        rawName: exercise.name,
        languageCode: languageCode
    )
}

func gymExerciseName(
    _ rawName: String,
    catalogKey: String? = nil,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    BuiltInExerciseCatalog.displayName(
        catalogKey: catalogKey,
        rawName: rawName,
        languageCode: languageCode
    )
}

/// Resolves an English source string through the app's String Catalog while
/// respecting GymApp's in-app language setting rather than the device language.
/// Missing catalog entries safely fall back to the supplied English text.
func gymLocalized(
    _ english: String,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    guard languageCode == AppLanguage.ukrainian.rawValue,
          let path = Bundle.main.path(forResource: AppLanguage.ukrainian.rawValue, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return english
    }
    let localized = bundle.localizedString(forKey: english, value: english, table: "Localizable")
    guard localized == english else { return localized }
    return gymUkrainianDynamicFallback(english, bundle: bundle)
}

private func gymUkrainianDynamicFallback(_ english: String, bundle: Bundle) -> String {
    func exact(_ key: String) -> String {
        let localized = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard localized == key else { return localized }
        let prefix = "Unsupported local schema "
        let suffix = "."
        if key.hasPrefix(prefix), key.hasSuffix(suffix) {
            let start = key.index(key.startIndex, offsetBy: prefix.count)
            let end = key.index(key.endIndex, offsetBy: -suffix.count)
            return "Непідтримувана версія локальної схеми \(key[start ..< end])."
        }
        return key
    }

    func value(between prefix: String, and suffix: String) -> String? {
        guard english.hasPrefix(prefix), english.hasSuffix(suffix) else { return nil }
        let start = english.index(english.startIndex, offsetBy: prefix.count)
        let end = english.index(english.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return nil }
        return String(english[start ..< end])
    }

    let prefixedMessages: [(String, String)] = [
        ("The local workout store is invalid: ", "Локальне сховище тренувань пошкоджене: "),
        ("The workout is invalid: ", "Тренування некоректне: "),
        ("The backup is invalid: ", "Резервна копія некоректна: "),
        ("Workout data could not be saved: ", "Не вдалося зберегти дані тренувань: ")
    ]
    for (prefix, translatedPrefix) in prefixedMessages where english.hasPrefix(prefix) {
        let detail = String(english.dropFirst(prefix.count))
        return translatedPrefix + exact(detail)
    }

    if let version = value(between: "Backup schema version ", and: " is not supported.") {
        return "Версія схеми резервної копії \(version) не підтримується."
    }
    if let limit = value(between: "The backup exceeds the allowed ", and: " limit.") {
        return "Резервна копія перевищує дозволене обмеження: \(exact(limit))."
    }
    if let status = value(between: "The secure session could not be accessed (", and: ").") {
        return "Не вдалося отримати доступ до захищеної сесії (\(status))."
    }
    if let status = value(between: "Cloud sync failed (HTTP ", and: ").") {
        return "Хмарна синхронізація не вдалася (HTTP \(status))."
    }
    if let status = value(between: "Garmin cloud sync failed (HTTP ", and: ").") {
        return "Хмарна синхронізація Garmin не вдалася (HTTP \(status))."
    }
    return english
}

func gymLocalized(_ english: String, locale: Locale) -> String {
    gymLocalized(
        english,
        languageCode: locale.language.languageCode?.identifier ?? AppLanguage.english.rawValue
    )
}

func gymFormattedDate(
    _ value: Date,
    date: Date.FormatStyle.DateStyle,
    time: Date.FormatStyle.TimeStyle,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    return value.formatted(Date.FormatStyle(date: date, time: time, locale: locale))
}

func gymErrorMessage(
    _ error: Error,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let english: String
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet:
            english = "The Internet connection appears to be offline."
        case .timedOut:
            english = "The request timed out."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            english = "The server could not be reached."
        case .networkConnectionLost:
            english = "The network connection was lost."
        case .cancelled:
            english = "The request was cancelled."
        case .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected:
            english = "A secure connection could not be established."
        default:
            english = "The network request failed. Try again."
        }
    } else {
        english = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    return gymLocalized(english, languageCode: languageCode)
}

func gymCount(
    _ count: Int,
    englishOne: String,
    englishMany: String,
    ukrainianOne: String,
    ukrainianFew: String,
    ukrainianMany: String,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    guard languageCode == AppLanguage.ukrainian.rawValue else {
        return "\(count) \(count == 1 ? englishOne : englishMany)"
    }
    let absolute = abs(count)
    let lastTwo = absolute % 100
    let last = absolute % 10
    let noun: String
    if last == 1, lastTwo != 11 {
        noun = ukrainianOne
    } else if (2 ... 4).contains(last), !(12 ... 14).contains(lastTwo) {
        noun = ukrainianFew
    } else {
        noun = ukrainianMany
    }
    return "\(count) \(noun)"
}
