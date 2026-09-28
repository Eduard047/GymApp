import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case ukrainian = "uk"
    case russian = "ru"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: "EN"
        case .ukrainian: "UK"
        case .russian: "RU"
        }
    }
    /// The language's own full name, in itself (not translated into the
    /// currently selected app language) — e.g. for a trailing "current
    /// language" label that should always read "Русский", never "RU" or a
    /// translation of "Russian".
    var fullTitle: String {
        switch self {
        case .english: "English"
        case .ukrainian: "Українська"
        case .russian: "Русский"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }

    static var firstRunDefault: AppLanguage {
        firstRunDefault(preferredLanguages: Locale.preferredLanguages)
    }

    static func firstRunDefault(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
            if let code, let supported = AppLanguage(rawValue: code) {
                return supported
            }
        }
        return .english
    }

    static func resolved(
        savedCode: String?,
        preferredLanguages: [String]
    ) -> AppLanguage {
        if let savedCode, let saved = AppLanguage(rawValue: savedCode) {
            return saved
        }
        return firstRunDefault(preferredLanguages: preferredLanguages)
    }
}

private let gymAppLanguageDefaultsKey = "app-language"

func gymCurrentLanguageCode(
    defaults: UserDefaults = .standard,
    preferredLanguages: [String] = Locale.preferredLanguages
) -> String {
    AppLanguage.resolved(
        savedCode: defaults.string(forKey: gymAppLanguageDefaultsKey),
        preferredLanguages: preferredLanguages
    ).rawValue
}

func gymText(
    _ english: String,
    _ ukrainian: String,
    _ russian: String,
    languageCode: String
) -> String {
    switch languageCode {
    case AppLanguage.ukrainian.rawValue: ukrainian
    case AppLanguage.russian.rawValue: russian
    default: english
    }
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
    if english != gymGenericErrorMessage, gymContainsUnsafeErrorDetail(english) {
        return gymLocalized(gymGenericErrorMessage, languageCode: languageCode)
    }
    guard let language = AppLanguage(rawValue: languageCode), language != .english,
          let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return english
    }
    let localized = bundle.localizedString(forKey: english, value: english, table: "Localizable")
    guard localized == english else { return localized }
    if language == .ukrainian {
        return gymUkrainianDynamicFallback(english, bundle: bundle)
    }
    return gymRussianDynamicFallback(english)
}

private func gymContainsUnsafeErrorDetail(_ message: String) -> Bool {
    let rules: [(String, String)] = [
        ("The local workout store is invalid: ", ""),
        ("The workout is invalid: ", ""),
        ("The backup is invalid: ", ""),
        ("Workout data could not be saved: ", ""),
        ("Unsupported local schema ", "."),
        ("Backup schema version ", " is not supported."),
        ("The backup exceeds the allowed ", " limit."),
        ("The secure session could not be accessed (", ")."),
        ("Cloud sync failed (HTTP ", ")."),
        ("Garmin cloud sync failed (HTTP ", ").")
    ]
    return rules.contains { message.hasPrefix($0.0) && message.hasSuffix($0.1) }
}

private func gymRussianDynamicFallback(_ english: String) -> String {
    let rawErrorRules: [(String, String)] = [
        ("The local workout store is invalid: ", ""),
        ("The workout is invalid: ", ""),
        ("The backup is invalid: ", ""),
        ("Workout data could not be saved: ", ""),
        ("Backup schema version ", " is not supported."),
        ("The backup exceeds the allowed ", " limit."),
        ("The secure session could not be accessed (", ")."),
        ("Cloud sync failed (HTTP ", ")."),
        ("Garmin cloud sync failed (HTTP ", ").")
    ]
    if rawErrorRules.contains(where: { english.hasPrefix($0.0) && english.hasSuffix($0.1) }) {
        return "Что-то пошло не так. Попробуй ещё раз."
    }
    return english
}

private func gymUkrainianDynamicFallback(_ english: String, bundle _: Bundle) -> String {
    func value(between prefix: String, and suffix: String) -> String? {
        guard english.hasPrefix(prefix), english.hasSuffix(suffix) else { return nil }
        let start = english.index(english.startIndex, offsetBy: prefix.count)
        let end = english.index(english.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return nil }
        return String(english[start ..< end])
    }

    let rawErrorPrefixes = [
        "The local workout store is invalid: ",
        "The workout is invalid: ",
        "The backup is invalid: ",
        "Workout data could not be saved: "
    ]
    if rawErrorPrefixes.contains(where: english.hasPrefix) {
        return "Щось пішло не так. Спробуй ще раз."
    }

    let rawErrorRules = [
        ("Backup schema version ", " is not supported."),
        ("The backup exceeds the allowed ", " limit."),
        ("The secure session could not be accessed (", ")."),
        ("Cloud sync failed (HTTP ", ")."),
        ("Garmin cloud sync failed (HTTP ", ").")
    ]
    if rawErrorRules.contains(where: { value(between: $0.0, and: $0.1) != nil }) {
        return "Щось пішло не так. Спробуй ще раз."
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
    var style = Date.FormatStyle(date: date, time: time, locale: locale)
    if date != .omitted {
        style = style.weekday(date == .long ? .wide : .abbreviated)
    }
    return value.formatted(style)
}

func gymFormattedTimestamp(
    _ value: Date,
    date: Date.FormatStyle.DateStyle,
    time: Date.FormatStyle.TimeStyle,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    gymFormattedDateWithoutWeekday(
        value,
        date: date,
        time: time,
        languageCode: languageCode
    )
}

func gymFormattedDateWithoutWeekday(
    _ value: Date,
    date: Date.FormatStyle.DateStyle,
    time: Date.FormatStyle.TimeStyle,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    return value.formatted(Date.FormatStyle(date: date, time: time, locale: locale))
}

func gymFormattedWeekday(
    _ value: Date,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    return value.formatted(.dateTime.weekday(.wide).locale(locale))
}

/// Compact, locale-aware range like "21–27 сент." (same month) or
/// "29 сент. – 5 окт." (cross-month), including the year only when it
/// differs from the current year.
func gymFormattedDateRange(
    from start: Date,
    to end: Date,
    calendar: Calendar = .current,
    now: Date = Date(),
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    let includeYear = calendar.component(.year, from: end) != calendar.component(.year, from: now)
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.dateTemplate = includeYear ? "d MMM yyyy" : "d MMM"
    return formatter.string(from: start, to: end) ?? ""
}

/// "Сб, 26 сент." — abbreviated weekday + day + abbreviated month in the
/// app's language locale. The year is appended only when it differs from
/// `now`'s year.
func gymShortDate(
    _ value: Date,
    calendar: Calendar = .current,
    now: Date = Date(),
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    let sameYear = calendar.component(.year, from: value) == calendar.component(.year, from: now)
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEE d MMM" : "EEE d MMM yyyy")
    return formatter.string(from: value)
}

/// "3 ч 52 мин" — locale-aware, abbreviated hour/minute duration built from
/// a `DateComponentsFormatter`. Returns "" when the duration is zero or the
/// formatter has nothing to show.
func gymCompactDuration(
    _ seconds: Int,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    guard seconds > 0 else { return "" }
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.hour, .minute]
    formatter.maximumUnitCount = 2
    var durationCalendar = Calendar(identifier: .gregorian)
    durationCalendar.locale = locale
    formatter.calendar = durationCalendar
    return formatter.string(from: TimeInterval(seconds)) ?? ""
}

func gymErrorMessage(
    _ error: Error,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    gymLocalized(gymSafeEnglishErrorMessage(error), languageCode: languageCode)
}

/// Converts internal failures into a bounded, app-owned message before they reach UI.
/// Provider response bodies, persistence details, HTTP payloads and Keychain status
/// codes remain available on their typed errors for control flow, but are never shown.
func gymSafeEnglishErrorMessage(_ error: Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet:
            return "The Internet connection appears to be offline."
        case .timedOut:
            return "The request timed out."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "The server could not be reached."
        case .networkConnectionLost:
            return "The network connection was lost."
        case .cancelled:
            return "The request was cancelled."
        case .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected:
            return "A secure connection could not be established."
        default:
            return "The network request failed. Try again."
        }
    }

    if let authError = error as? AuthServiceError {
        switch authError {
        case .invalidEmail,
             .invalidPassword,
             .loginPasswordTooLong,
             .currentPasswordTooLong,
             .invalidPasswordReauthenticationNonce,
             .passwordReauthenticationRequired,
             .invalidDisplayName,
             .duplicateLocalProfile,
             .localProfileNotFound,
             .localProfileLimitReached,
             .secureSessionCleanupPending,
             .accountDeletionCleanupPending,
             .malformedResponse,
             .callbackMissingSession,
             .callbackNotExpected,
             .notCloudAccount,
             .sessionChanged,
             .sessionExpired:
            return authError.errorDescription ?? gymGenericErrorMessage
        case .requestFailed(_, let message),
             .server(let message):
            return gymSafeAuthServerErrorMessage(message)
        }
    }

    if let cloudError = error as? CloudSyncError {
        switch cloudError {
        case .invalidPayload,
             .invalidSocialProfile,
             .invalidFriendship,
             .invalidWorkoutInvite,
             .invalidResponse,
             .staleRemoteState:
            return cloudError.errorDescription ?? gymGenericErrorMessage
        case .postgRESTFailure,
             .requestFailed:
            return gymGenericErrorMessage
        }
    }

    if let garminError = error as? GarminCloudError {
        switch garminError {
        case .invalidPlan,
             .planSetLimitExceeded,
             .invalidRequest,
             .invalidResponse,
             .invalidBinding,
             .pairingRequired,
             .busy,
             .pendingRevocation,
             .bindingPersistenceFailed,
             .deviceRefreshRequired,
             .deviceCreationRecoveryRequired,
             .rotationConflict,
             .enqueueConflict:
            return garminError.errorDescription ?? gymGenericErrorMessage
        case .requestFailed:
            return gymGenericErrorMessage
        }
    }

    if error is KeychainStoreError {
        return gymGenericErrorMessage
    }

    if let storeError = error as? WorkoutStoreError {
        switch storeError {
        case .corruptStore,
             .invalidWorkout,
             .unsupportedBackupSchema,
             .malformedBackup,
             .importLimitExceeded,
             .persistenceFailure:
            return gymGenericErrorMessage
        case .invalidAccountStorageKey,
             .storageAccountMismatch,
             .invalidExerciseName,
             .duplicateExerciseName,
             .exerciseNotFound,
             .exerciseInUse,
             .builtInExerciseReadOnly,
             .workoutNotFound,
             .workoutExerciseNotFound,
             .setNotFound,
             .invalidWeight,
             .invalidReps,
             .backupOwnerMismatch:
            return storeError.errorDescription ?? gymGenericErrorMessage
        }
    }

    if let activeWorkoutError = error as? ActiveWorkoutStoreError {
        return activeWorkoutError.errorDescription ?? gymGenericErrorMessage
    }

    return gymGenericErrorMessage
}

private let gymGenericErrorMessage = "Something went wrong. Try again."

private func gymSafeAuthServerErrorMessage(_ raw: String) -> String {
    let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = message.lowercased()
    if lower.contains("invalid login") || lower.contains("invalid credentials") {
        return "Email or password is incorrect."
    }
    if lower.contains("email not confirmed") {
        return "Confirm your email first, then sign in."
    }
    if lower.contains("rate limit") || lower.contains("over_email_send_rate_limit") {
        return "Too many emails were requested. Try again later."
    }
    if lower.contains("already registered") || lower.contains("user_already_exists") {
        return "An account with this email already exists."
    }

    let safeMessages: Set<String> = [
        "Email or password is incorrect.",
        "Confirm your email first, then sign in.",
        "Too many emails were requested. Try again later.",
        "An account with this email already exists.",
        "Cloud service is temporarily unavailable. Try again later.",
        "Cloud request failed. Check your connection and try again."
    ]
    return safeMessages.contains(message) ? message : gymGenericErrorMessage
}

/// "82,5 кг" — a weight with the decimal separator and unit of the app language.
func gymWeightText(
    _ weight: Double,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    let number = weight.formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
    return "\(number) \(gymLocalized("kg", languageCode: languageCode))"
}

/// "82,5 кг × 8" — a set's weight and repetitions in the app language.
func gymWeightRepsText(
    weight: Double,
    reps: Int,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    "\(gymWeightText(weight, languageCode: languageCode)) × \(reps)"
}

enum GymPluralCategory: Equatable, Sendable {
    case one
    case few
    case many
}

/// Ukrainian and Russian share the standard one/few/many rules: 1, 21, 101 → one;
/// 2–4, 22–24 → few; 0, 5–20 (including 11–14), 25–30 → many. English only
/// distinguishes exactly one from everything else.
func gymPluralCategory(_ count: Int, languageCode: String) -> GymPluralCategory {
    let absolute = count.magnitude
    guard languageCode == AppLanguage.ukrainian.rawValue || languageCode == AppLanguage.russian.rawValue else {
        return absolute == 1 ? .one : .many
    }
    let last = absolute % 10
    let lastTwo = absolute % 100
    if last == 1, lastTwo != 11 { return .one }
    if (2 ... 4).contains(last), !(12 ... 14).contains(lastTwo) { return .few }
    return .many
}

/// Returns the noun form that agrees with `count` in the app language. Callers pass
/// the forms already localized (for example through `gymText`) and place the number
/// themselves, so phrases such as "Осталось 3 подхода" keep natural word order.
func gymPlural(
    _ count: Int,
    one: String,
    few: String,
    many: String,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    switch gymPluralCategory(count, languageCode: languageCode) {
    case .one: one
    case .few: few
    case .many: many
    }
}

/// Picks the noun form for `count` from per-language forms, e.g.
/// `gymPlural(n, en: ("set", "sets"), uk: ("підхід", "підходи", "підходів"),
/// ru: ("подход", "подхода", "подходов"))`.
func gymPlural(
    _ count: Int,
    en: (one: String, many: String),
    uk: (one: String, few: String, many: String),
    ru: (one: String, few: String, many: String),
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    switch languageCode {
    case AppLanguage.ukrainian.rawValue:
        gymPlural(count, one: uk.one, few: uk.few, many: uk.many, languageCode: languageCode)
    case AppLanguage.russian.rawValue:
        gymPlural(count, one: ru.one, few: ru.few, many: ru.many, languageCode: languageCode)
    default:
        gymPlural(count, one: en.one, few: en.many, many: en.many, languageCode: languageCode)
    }
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
    let noun: String
    switch languageCode {
    case AppLanguage.russian.rawValue:
        let forms = gymRussianNounForms[englishOne] ?? [
            gymLocalized(englishOne, languageCode: languageCode),
            gymLocalized(englishMany, languageCode: languageCode),
            gymLocalized(englishMany, languageCode: languageCode)
        ]
        noun = gymPlural(count, one: forms[0], few: forms[1], many: forms[2], languageCode: languageCode)
    case AppLanguage.ukrainian.rawValue:
        noun = gymPlural(count, one: ukrainianOne, few: ukrainianFew, many: ukrainianMany, languageCode: languageCode)
    default:
        noun = gymPlural(count, one: englishOne, few: englishMany, many: englishMany, languageCode: languageCode)
    }
    return "\(count) \(noun)"
}

private let gymRussianNounForms: [String: [String]] = [
    "day": ["день", "дня", "дней"],
    "week": ["неделя", "недели", "недель"],
    "workout": ["тренировка", "тренировки", "тренировок"],
    "workout per week": ["тренировка в неделю", "тренировки в неделю", "тренировок в неделю"],
    "session": ["сессия", "сессии", "сессий"],
    "set": ["подход", "подхода", "подходов"],
    "rep": ["повтор", "повтора", "повторов"],
    "exercise": ["упражнение", "упражнения", "упражнений"],
    "active day": ["активный день", "активных дня", "активных дней"],
    "group": ["группа", "группы", "групп"],
    "duplicate": ["дубликат", "дубликата", "дубликатов"],
    "invalid set": ["некорректный подход", "некорректных подхода", "некорректных подходов"]
]
