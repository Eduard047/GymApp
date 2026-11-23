import Foundation

/// Every Apple Watch string in EN/UK/RU. Wording matches the Wear OS app
/// (wear/src/main/res/values*/strings.xml) wherever the meaning is the same.
enum WatchTextKey: String, CaseIterable, Sendable {
    case appTitle
    case startPlan
    case freeWorkout
    case setsCount
    case weightStep
    case weightKg
    case openPhone
    case phoneOff
    case logSet
    case setKOfN
    case setK
    case weightReps
    case exercise
    case unitKg
    case unitReps
    case labelWeight
    case labelReps
    case saveSet
    case setSaved
    case undo
    case rest
    case restAdd
    case skip
    case next
    case restDone
    case sectionPlan
    case sectionAll
    case noExercises
    case paused
    case resume
    case finish
    case needSet
    case discard
    case discardTitle
    case discardBody
    case keep
    case summary
    case labelDuration
    case labelSets
    case labelVolume
    case labelAvgHR
    case labelMaxHR
    case valueBpm
    case valueKcal
    case calories
    case save
    case sending
    case savedPhone
    case sendLater
    case done
    case hrOff
    case a11yHeartRate
    case a11yHeartRateWaiting
    case a11yHeartRateOff
    case a11ySetValues
    case a11yRest
    case a11yChangeExercise
    case chooseExercise
    case queuedTitle
    case sendNow
    case unsentCount
    case outboxFull
    case notAccepted
    case sameAccount
    case close
}

enum WatchText {
    /// Owner decision: the watch follows its system locale (uk/ru, else en).
    static func language(preferredLanguages: [String]) -> String {
        for identifier in preferredLanguages {
            let code = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if code == "uk" || code == "ru" { return code }
            if code == "en" { return "en" }
        }
        return "en"
    }

    static func string(_ key: WatchTextKey, _ language: String) -> String {
        let entry = table[key] ?? ("", "", "")
        switch language {
        case "uk": return entry.uk
        case "ru": return entry.ru
        default: return entry.en
        }
    }

    static func format(_ key: WatchTextKey, _ language: String, _ arguments: CVarArg...) -> String {
        String(format: string(key, language), locale: Locale(identifier: language), arguments: arguments)
    }

    // MARK: Helpers

    static func setLine(_ position: WatchSetPosition, _ language: String) -> String {
        if let count = position.count { return format(.setKOfN, language, position.index, count) }
        return format(.setK, language, position.index)
    }

    static func weightReps(weight: Double, reps: Int, _ language: String) -> String {
        format(.weightReps, language, WatchCrownSteps.formatWeight(weight, language: language), String(reps))
    }

    static func weightKg(_ weight: Double, _ language: String) -> String {
        format(.weightKg, language, WatchCrownSteps.formatWeight(weight, language: language))
    }

    static func restAccessibility(seconds: Int, _ language: String) -> String {
        format(.a11yRest, language, seconds / 60, seconds % 60)
    }

    // MARK: Table (en, uk, ru)

    private static let table: [WatchTextKey: (en: String, uk: String, ru: String)] = [
        .appTitle: ("GymApp", "GymApp", "GymApp"),
        .startPlan: ("Start plan", "Почати план", "Начать план"),
        .freeWorkout: ("Free workout", "Вільне тренування", "Свободная тренировка"),
        .setsCount: ("Sets: %d", "Підходи: %d", "Подходы: %d"),
        .weightStep: ("Weight step", "Крок ваги", "Шаг веса"),
        .weightKg: ("%@ kg", "%@ кг", "%@ кг"),
        .openPhone: ("Open GymApp on your phone", "Відкрий GymApp на телефоні", "Открой GymApp на телефоне"),
        .phoneOff: ("Phone not connected", "Телефон не підключено", "Телефон не подключён"),
        .logSet: ("Log set", "Записати підхід", "Записать подход"),
        .setKOfN: ("Set %d of %d", "Підхід %d з %d", "Подход %d из %d"),
        .setK: ("Set %d", "Підхід %d", "Подход %d"),
        .weightReps: ("%@ kg × %@", "%@ кг × %@", "%@ кг × %@"),
        .exercise: ("Exercise", "Вправа", "Упражнение"),
        .unitKg: ("kg", "кг", "кг"),
        .unitReps: ("reps", "повт.", "повт."),
        .labelWeight: ("Weight", "Вага", "Вес"),
        .labelReps: ("Reps", "Повторення", "Повторения"),
        .saveSet: ("Save set", "Зберегти підхід", "Сохранить подход"),
        .setSaved: ("Set saved", "Підхід збережено", "Подход сохранён"),
        .undo: ("Undo", "Скасувати", "Отменить"),
        .rest: ("Rest", "Відпочинок", "Отдых"),
        .restAdd: ("+15 s", "+15 с", "+15 с"),
        .skip: ("Skip", "Пропустити", "Пропустить"),
        .next: ("Next: %@", "Далі: %@", "Далее: %@"),
        .restDone: ("Rest timer done", "Відпочинок завершено", "Отдых завершён"),
        .sectionPlan: ("Plan", "План", "План"),
        .sectionAll: ("All exercises", "Усі вправи", "Все упражнения"),
        .noExercises: ("No exercises yet. Open GymApp on your phone.", "Вправ ще немає. Відкрий GymApp на телефоні.", "Упражнений пока нет. Открой GymApp на телефоне."),
        .paused: ("Paused", "Пауза", "Пауза"),
        .resume: ("Resume", "Продовжити", "Продолжить"),
        .finish: ("Finish", "Завершити", "Завершить"),
        .needSet: ("Record at least one set before finishing.", "Перед завершенням запиши хоча б один підхід.", "Перед завершением запиши хотя бы один подход."),
        .discard: ("Discard workout", "Відкинути тренування", "Удалить тренировку"),
        .discardTitle: ("Discard workout?", "Відкинути тренування?", "Удалить тренировку?"),
        .discardBody: ("Recorded sets will be removed.", "Записані підходи буде видалено.", "Записанные подходы будут удалены."),
        .keep: ("Keep workout", "Залишити тренування", "Оставить тренировку"),
        .summary: ("Workout summary", "Підсумок тренування", "Итог тренировки"),
        .labelDuration: ("Duration", "Тривалість", "Длительность"),
        .labelSets: ("Sets", "Підходи", "Подходы"),
        .labelVolume: ("Volume", "Обсяг", "Объём"),
        .labelAvgHR: ("Avg HR", "Сер пульс", "Сред. пульс"),
        .labelMaxHR: ("Max HR", "Макс пульс", "Макс. пульс"),
        .valueBpm: ("%d bpm", "%d уд/хв", "%d уд/мин"),
        .valueKcal: ("%d kcal", "%d ккал", "%d ккал"),
        .calories: ("Calories", "Калорії", "Калории"),
        .save: ("Save", "Зберегти", "Сохранить"),
        .sending: ("Sending…", "Надсилання…", "Отправка…"),
        .savedPhone: ("Saved on phone", "Збережено на телефоні", "Сохранено на телефоне"),
        .sendLater: ("Will send when the phone is nearby", "Надішлемо, коли телефон буде поруч", "Отправим, когда телефон будет рядом"),
        .done: ("Done", "Готово", "Готово"),
        .hrOff: ("Heart rate is off", "Пульс вимкнено", "Пульс выключен"),
        .a11yHeartRate: ("Heart rate %d beats per minute, zone %d", "Пульс %d ударів за хвилину, зона %d", "Пульс %d ударов в минуту, зона %d"),
        .a11yHeartRateWaiting: ("Measuring heart rate", "Вимірювання пульсу", "Измерение пульса"),
        .a11yHeartRateOff: ("Heart rate is off", "Пульс вимкнено", "Пульс выключен"),
        .a11ySetValues: ("%@ kilograms, %d reps", "%@ кг, %d повторень", "%@ кг, %d повторений"),
        .a11yRest: ("Rest, %d min %d s", "Відпочинок, %d хв %d с", "Отдых, %d мин %d с"),
        .a11yChangeExercise: ("Change exercise", "Змінити вправу", "Сменить упражнение"),
        .chooseExercise: ("Choose exercise", "Обрати вправу", "Выбрать упражнение"),
        .queuedTitle: ("Unsent", "Не надіслано", "Не отправлено"),
        .sendNow: ("Send now", "Надіслати", "Отправить"),
        .unsentCount: ("Unsent workouts: %d", "Невідправлені тренування: %d", "Неотправленные тренировки: %d"),
        .outboxFull: ("Too many unsent workouts. Open GymApp on your phone.", "Забагато невідправлених тренувань. Відкрий GymApp на телефоні.", "Слишком много неотправленных тренировок. Открой GymApp на телефоне."),
        .notAccepted: ("The phone did not accept this workout", "Телефон не прийняв це тренування", "Телефон не принял эту тренировку"),
        .sameAccount: ("Sign in to the same account on your phone", "Увійди в той самий акаунт на телефоні", "Войди в тот же аккаунт на телефоне"),
        .close: ("Close", "Закрити", "Закрыть")
    ]
}
