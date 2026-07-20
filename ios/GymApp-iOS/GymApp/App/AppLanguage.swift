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
    var locale: Locale { Locale(identifier: rawValue) }
}

private let gymAppLanguageDefaultsKey = "app-language"

func gymCurrentLanguageCode() -> String {
    UserDefaults.standard.string(forKey: gymAppLanguageDefaultsKey) ?? AppLanguage.english.rawValue
}

func gymText(_ english: String, _ ukrainian: String, languageCode: String) -> String {
    switch languageCode {
    case AppLanguage.ukrainian.rawValue:
        return ukrainian
    case AppLanguage.russian.rawValue:
        let localized = gymLocalized(english, languageCode: languageCode)
        return localized == english ? gymRussianFromUkrainian(ukrainian) : localized
    default:
        return english
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

private func gymRussianDynamicFallback(_ english: String) -> String {
    let rules: [(String, String, String)] = [
        ("The local workout store is invalid: ", "", "Локальное хранилище тренировок повреждено: %@"),
        ("The workout is invalid: ", "", "Тренировка некорректна: %@"),
        ("The backup is invalid: ", "", "Резервная копия некорректна: %@"),
        ("Workout data could not be saved: ", "", "Не удалось сохранить данные тренировки: %@")
    ]
    for (prefix, suffix, format) in rules where english.hasPrefix(prefix) && english.hasSuffix(suffix) {
        let start = english.index(english.startIndex, offsetBy: prefix.count)
        let end = english.index(english.endIndex, offsetBy: -suffix.count)
        guard start <= end else { continue }
        return String(format: format, String(english[start ..< end]))
    }
    return english
}

private func gymRussianFromUkrainian(_ ukrainian: String) -> String {
    let replacements: [(String, String)] = [
        ("Космічний воєвода", "Космический воевода"),
        ("Понадмежний", "Запредельный"),
        ("Нескінченний", "Бесконечный"),
        ("Трансцендентний", "Трансцендентный"),
        ("Галактичний", "Галактический"),
        ("Сингулярність", "Сингулярность"),
        ("Вознесений", "Вознесённый"),
        ("Завойовник", "Завоеватель"),
        ("Безсмертний", "Бессмертный"),
        ("Міфічний", "Мифический"),
        ("Незламний", "Несокрушимый"),
        ("Вмотивований", "Мотивированный"),
        ("Стартовий", "Начинающий"),
        ("Стабільний", "Стабильный"),
        ("Ударний", "Ударник"),
        ("Домінатор", "Доминатор"),
        ("Еліта", "Элита"),
        ("Колос", "Колосс"),
        ("Воїн", "Рождённый воином"),
        ("Вічний", "Вечный"),
        ("Володар", "Властелин"),
        ("Омні", "Омни"),
        ("Емпірей", "Эмпирей"),
        ("Повернутися до поточного місяця", "Вернуться к текущему месяцу"),
        ("із групами м’язів", "с группами мышц"),
        ("у ручному зіставленні", "в ручном сопоставлении"),
        ("з каталогу вправ", "из каталога упражнений"),
        ("додати до черги Garmin не вдалося", "не удалось добавить в очередь Garmin"),
        ("усі його підходи буде видалено з цього пристрою", "все его подходы будут удалены с этого устройства"),
        ("до наступного рівня", "до следующего уровня"),
        ("на цьому рівні", "на этом уровне"),
        ("за тренування", "за тренировку"),
        ("Тренування за", "Тренировка за"),
        ("Видалити тренування", "Удалить тренировку"),
        ("Видалити підхід", "Удалить подход"),
        ("Видалити", "Удалить"),
        ("Додає або видаляє", "Добавляет или удаляет"),
        ("Дає змогу вручну зіставити", "Позволяет вручную сопоставить"),
        ("Показує всі збережені підходи", "Показывает все сохранённые подходы"),
        ("Більше дій для", "Больше действий для"),
        ("Попередній рекорд", "Предыдущий рекорд"),
        ("Новий рекорд ваги", "Новый рекорд веса"),
        ("Розрахунковий 1ПМ", "Расчётный 1ПМ"),
        ("Розумний тренер створив тренування", "Умный тренер создал тренировку"),
        ("завантажено", "загружен"),
        ("Замінює вміст редактора шаблоном", "Заменяет содержимое редактора шаблоном"),
        ("Запустити таймер відпочинку", "Запустить таймер отдыха"),
        ("Залишилося", "Осталось"),
        ("Використовує останню записану вагу", "Использует последний записанный вес"),
        ("Остання вага", "Последний вес"),
        ("Повторення для підходу", "Повторения для подхода"),
        ("Вага для підходу", "Вес для подхода"),
        ("Підхід", "Подход"),
        ("підхід", "подход"),
        ("підходи", "подходы"),
        ("підходів", "подходов"),
        ("Рівень", "Уровень"),
        ("Далі", "Далее"),
        ("на рівні", "на уровне"),
        ("Вправ", "Упражнений"),
        ("вправи", "упражнения"),
        ("вправ", "упражнений"),
        ("зіставлено", "сопоставлено"),
        ("Імпортовано", "Импортировано"),
        ("додано", "добавлено"),
        ("пропущено", "пропущено"),
        ("проігноровано", "проигнорировано"),
        ("Обсяг", "Объём"),
        ("обсяг", "объём"),
        ("навантаження", "нагрузка"),
        ("Створено", "Создано"),
        ("Час наступного підходу", "Время следующего подхода"),
        ("секунд", "секунд"),
        ("повт.", "повт."),
        ("кілограмів", "килограммов"),
        ("повторень", "повторений"),
        ("Поточний місяць", "Текущий месяц"),
        ("Серія у", "Серия в"),
        ("створює справжній темп", "создаёт хороший темп"),
        ("загалом", "всего")
    ]
    return replacements.reduce(ukrainian) { result, replacement in
        result.replacingOccurrences(of: replacement.0, with: replacement.1)
    }
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
    if languageCode == AppLanguage.russian.rawValue {
        let forms = gymRussianNounForms[englishOne] ?? [
            gymLocalized(englishOne, languageCode: languageCode),
            gymLocalized(englishMany, languageCode: languageCode),
            gymLocalized(englishMany, languageCode: languageCode)
        ]
        let absolute = abs(count)
        let lastTwo = absolute % 100
        let last = absolute % 10
        let noun = last == 1 && lastTwo != 11
            ? forms[0]
            : ((2 ... 4).contains(last) && !(12 ... 14).contains(lastTwo) ? forms[1] : forms[2])
        return "\(count) \(noun)"
    }
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

private let gymRussianNounForms: [String: [String]] = [
    "day": ["день", "дня", "дней"],
    "week": ["неделя", "недели", "недель"],
    "workout": ["тренировка", "тренировки", "тренировок"],
    "workout per week": ["тренировка в неделю", "тренировки в неделю", "тренировок в неделю"],
    "session": ["сессия", "сессии", "сессий"],
    "set": ["подход", "подхода", "подходов"],
    "exercise": ["упражнение", "упражнения", "упражнений"],
    "active day": ["активный день", "активных дня", "активных дней"],
    "group": ["группа", "группы", "групп"],
    "duplicate": ["дубликат", "дубликата", "дубликатов"],
    "invalid set": ["некорректный подход", "некорректных подхода", "некорректных подходов"]
]
