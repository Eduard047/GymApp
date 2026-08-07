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
        if localized != english { return localized }
        if let exact = gymRussianEnglishFallbacks[english] { return exact }
        return gymRussianFromUkrainian(ukrainian)
    default:
        return english
    }
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

private let gymRussianExactFallbacks: [String: String] = [
    "Груди": "Грудь",
    "Плечі": "Плечи",
    "Біцепс": "Бицепс",
    "Тріцепс": "Трицепс",
    "Передпліччя": "Предплечья",
    "Прес": "Пресс",
    "Косі мʼязи": "Косые мышцы",
    "Широчайші": "Широчайшие",
    "Верх спини": "Верх спины",
    "Поперек": "Поясница",
    "Сідниці": "Ягодицы",
    "Квадрицепси": "Квадрицепсы",
    "Біцепс стегна": "Бицепс бедра",
    "Привідні": "Приводящие мышцы",
    "Ікри": "Икры"
]

private let gymRussianEnglishFallbacks: [String: String] = [
    "Workout sync": "Синхронизация тренировок",
    "Which workout history should GymApp keep?": "Какую историю тренировок сохранить?",
    "This iPhone and the cloud contain different changes. Nothing has been deleted or overwritten.":
        "На этом iPhone и в облаке разные изменения. Пока ничего не удалено и не перезаписано.",
    "On this iPhone": "На этом iPhone",
    "In the cloud": "В облаке",
    "Saved workouts": "Сохранено тренировок",
    "Choose this if your latest workouts were recorded on this iPhone. This history will replace the cloud copy.":
        "Выбери это, если последние тренировки записывал на этом iPhone. Эта история заменит облачную копию.",
    "Keep workouts from this iPhone": "Сохранить тренировки с этого iPhone",
    "Choose this if your latest workouts were recorded on another device or in the PWA. The cloud history will replace workouts on this iPhone.":
        "Выбери это, если последние тренировки записывал на другом устройстве или в PWA. Облачная история заменит тренировки на этом iPhone.",
    "Use workouts from the cloud": "Загрузить тренировки из облака",
    "Back up this iPhone first": "Сначала сделать копию этого iPhone",
    "Sign out without changes": "Выйти без изменений",
    "Checking both histories again…": "Снова проверяем обе истории…",
    "The workout histories changed before your choice was applied. Review both versions again.":
        "Истории тренировок изменились до применения выбора. Проверь обе версии ещё раз.",
    "Cloud workout history was loaded on this iPhone.":
        "Облачная история тренировок загружена на этот iPhone.",
    "This iPhone's workout history was saved to the cloud.":
        "История тренировок с этого iPhone сохранена в облаке.",
    "Protected progress": "Защищённый прогресс",
    "Rating status": "Статус рейтинга",
    "Rating not available yet": "Рейтинг пока недоступен",
    "Workouts are currently scored on your device, so public ranking is disabled, not queued for review. It will appear only after a future app and server update adds verified scoring; no release date is set. Your private progress remains available.":
        "Сейчас тренировки оцениваются на устройстве, поэтому публичный рейтинг отключён, а не поставлен в очередь на проверку. Он появится только после будущего обновления приложения и сервера с проверяемым подсчётом; даты выпуска пока нет. Твой приватный прогресс остаётся доступным.",
    "Private progress only": "Только приватный прогресс",
    "YOUR PROGRESS": "ТВОЙ ПРОГРЕСС",
    "Your synced progress": "Твой синхронизированный прогресс",
    "Loading protected cloud progress…": "Загружаем защищённый облачный прогресс…",
    "Your own cloud progress is up to date.": "Твой собственный облачный прогресс актуален.",
    "Refresh updates only your own cloud XP. It does not start a rating check.":
        "Обновление загружает только твои собственные XP из облака. Оно не запускает проверку рейтинга.",
    "Uploads and reloads your protected progress": "Загружает и обновляет твой защищённый прогресс",
    "Local progress": "Локальный прогресс",
    "No synced progress yet": "Синхронизированного прогресса пока нет",
    "Sign in and sync to restore your protected progress here.":
        "Войди и синхронизируй данные, чтобы восстановить здесь свой защищённый прогресс.",
    "This is an offline account. Sign in with a cloud account to protect and synchronize your progress; your workouts remain available on this device.":
        "Это офлайн-аккаунт. Войди в облачный аккаунт, чтобы защитить и синхронизировать прогресс; твои тренировки останутся доступными на этом устройстве.",
    "Protected cloud progress is unavailable, so the latest on-device XP, level and workouts are shown. Pull down or tap Refresh to try again.":
        "Защищённый облачный прогресс недоступен, поэтому показаны актуальные XP, уровень и тренировки с этого устройства. Потяни вниз или нажми «Обновить», чтобы повторить попытку.",
    "Report this display name?": "Пожаловаться на это имя?",
    "GymApp will send the profile identifier and a fixed offensive-name reason to the moderation queue. No free-form text is sent.":
        "GymApp отправит идентификатор профиля и фиксированную причину «неприемлемое имя» в очередь модерации. Произвольный текст не отправляется.",
    "Report": "Пожаловаться",
    "Showing on-device stats.": "Показана статистика с этого устройства.",
    "Synced through Supabase.": "Синхронизировано через Supabase.",
    "Show blocked athletes again": "Снова показывать заблокированных атлетов",
    "Blocked athletes are visible again.": "Заблокированные атлеты снова видны.",
    "Loading": "Загрузка",
    "Refresh": "Обновить",
    "Refresh progress": "Обновить прогресс",
    "Sign in with a cloud account to refresh": "Войди в облачный аккаунт, чтобы обновить",
    "Refreshes only your cloud progress; it does not start a rating check":
        "Обновляет только твой облачный прогресс и не запускает проверку рейтинга",
    "Uploads your latest stats and reloads the ranking": "Загружает твою актуальную статистику и обновляет рейтинг",
    "Report display name": "Пожаловаться на имя",
    "Block from leaderboard": "Заблокировать в рейтинге",
    "Safety options": "Параметры безопасности",
    "You": "Ты",
    "Report sent. The display name was added to the moderation queue.": "Жалоба отправлена. Имя добавлено в очередь модерации.",
    "Athlete blocked from your leaderboard.": "Атлет заблокирован в твоём рейтинге.",
    "Exercise": "Упражнение",
    "Add an exercise and log a workout to see progress.": "Добавь упражнение и запиши тренировку, чтобы увидеть прогресс.",
    "Selects which exercise to analyze": "Выбирает упражнение для анализа",
    "Muscle Breakdown": "Распределение по мышцам",
    "No muscle mapping is available for this exercise yet.": "Для этого упражнения пока нет сопоставления с мышцами.",
    "Progress Summary": "Сводка прогресса",
    "Volume = weight × reps across all completed sets.": "Объём = вес × повторения во всех завершённых подходах.",
    "Month best": "Лучшее за месяц",
    "Month volume": "Объём за месяц",
    "All-time PR": "Личный рекорд",
    "No progress this month": "В этом месяце прогресса пока нет",
    "Log sets for the selected exercise to unlock trends.": "Запиши подходы выбранного упражнения, чтобы открыть тренды.",
    "Recent sessions": "Последние сессии",
    "Workout History": "История тренировок",
    "This list changes with the selected month and exercise.": "Список меняется в зависимости от выбранных месяца и упражнения.",
    "Delete set": "Удалить подход",
    "Create an exercise and log a workout first.": "Сначала создай упражнение и запиши тренировку.",
    "best weight": "лучший вес",
    "volume": "объём",
    "No change vs prior month": "Без изменений по сравнению с прошлым месяцем",
    "Delete this set?": "Удалить этот подход?",
    "Couldn’t delete set": "Не удалось удалить подход",
    "Visual Trends": "Визуальные тренды",
    "No chart data": "Нет данных для графика",
    "Max Weight Trend": "Динамика максимального веса",
    "Baseline": "Базовый уровень",
    "Maximum weight chart": "График максимального веса",
    "Volume by Session": "Объём по сессиям",
    "Session volume chart": "График объёма по сессиям",
    "No trend yet": "Пока нет тренда",
    "Holding steady": "Без изменений"
]

private func gymRussianFromUkrainian(_ ukrainian: String) -> String {
    if let exact = gymRussianExactFallbacks[ukrainian] {
        return exact
    }
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
        ("Навантаження для", "Нагрузка для"),
        ("Тренування збережено, але", "Тренировка сохранена, но"),
        ("Тренування ·", "Тренировка ·"),
        ("Твоє поточне місце", "Твоё текущее место"),
        ("Оновлено", "Обновлено"),
        ("Місце", "Место"),
        ("поточний користувач", "текущий пользователь"),
        ("Сховати поле", "Скрыть поле"),
        ("Показати поле", "Показать поле"),
        ("у вибраному місяці", "в выбранном месяце"),
        ("не вибрано", "не выбрано"),
        ("вибрано", "выбрано"),
        ("цього місяця", "в этом месяце"),
        ("підх.", "подх."),
        ("повторів", "повторов"),
        ("Немає показника", "Нет показателя"),
        ("Перший місяць для", "Первый месяц для"),
        ("до попереднього місяця", "по сравнению с предыдущим месяцем"),
        ("повт. буде видалено. Якщо це останній підхід, вправу або тренування також буде видалено.", "повторений будет удалено. Если это последний подход, упражнение или тренировка также будут удалены."),
        ("Останні", "Последние"),
        ("до першої сесії", "по сравнению с первой сессией"),
        ("додати до черги Garmin не вдалося", "не удалось добавить в очередь Garmin"),
        ("і всі його підходи буде видалено з цього пристрою", "и все её подходы будут удалены с этого устройства"),
        ("усі його підходи буде видалено з цього пристрою", "все её подходы будут удалены с этого устройства"),
        ("із тренування", "из тренировки"),
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
        ("рівень", "уровень"),
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
    return value.formatted(Date.FormatStyle(date: date, time: time, locale: locale))
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
             .invalidPasswordReauthenticationNonce,
             .passwordReauthenticationRequired,
             .invalidDisplayName,
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
             .invalidLeaderboardProfile,
             .invalidResponse,
             .staleRemoteState,
             .reportAlreadySubmitted:
            return cloudError.errorDescription ?? gymGenericErrorMessage
        case .requestFailed:
            return gymGenericErrorMessage
        }
    }

    if let garminError = error as? GarminCloudError {
        switch garminError {
        case .invalidPlan,
             .invalidRequest,
             .invalidResponse,
             .invalidBinding,
             .pairingRequired,
             .busy,
             .pendingRevocation,
             .bindingPersistenceFailed,
             .deviceRefreshRequired,
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
    "rep": ["повтор", "повтора", "повторов"],
    "exercise": ["упражнение", "упражнения", "упражнений"],
    "active day": ["активный день", "активных дня", "активных дней"],
    "group": ["группа", "группы", "групп"],
    "duplicate": ["дубликат", "дубликата", "дубликатов"],
    "invalid set": ["некорректный подход", "некорректных подхода", "некорректных подходов"]
]
