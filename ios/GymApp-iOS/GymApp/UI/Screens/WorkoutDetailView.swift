import SwiftUI

enum GarminWorkoutDetailCopy {
    static func workoutTitle(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Garmin workout",
            uk: "Тренування Garmin",
            ru: "Тренировка Garmin"
        )
    }

    static func syncedSupporting(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Garmin-format metrics are shown as charts below. Imported or edited notes may not prove watch origin.",
            uk: "Показники у форматі Garmin показано графіками нижче. Імпортована або змінена нотатка не підтверджує походження з годинника.",
            ru: "Показатели в формате Garmin показаны графиками ниже. Импортированная или изменённая заметка не подтверждает происхождение с часов."
        )
    }

    static func metricsTitle(languageCode: String) -> String {
        localized(languageCode, en: "Workout metrics", uk: "Показники тренування", ru: "Показатели тренировки")
    }

    static func metricsSupporting(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Garmin and GymApp values parsed from this saved workout note.",
            uk: "Значення Garmin і GymApp, прочитані зі збереженої нотатки тренування.",
            ru: "Значения Garmin и GymApp, прочитанные из сохранённой заметки тренировки."
        )
    }

    static func duration(languageCode: String) -> String {
        localized(languageCode, en: "Duration", uk: "Тривалість", ru: "Длительность")
    }

    static func averageHeartRate(languageCode: String) -> String {
        localized(languageCode, en: "Average HR", uk: "Середній пульс", ru: "Средний пульс")
    }

    static func maximumHeartRate(languageCode: String) -> String {
        localized(languageCode, en: "Maximum HR", uk: "Максимальний пульс", ru: "Максимальный пульс")
    }

    static func heartRateChart(languageCode: String) -> String {
        localized(languageCode, en: "Heart-rate range", uk: "Діапазон пульсу", ru: "Диапазон пульса")
    }

    static func endingZone(languageCode: String) -> String {
        localized(languageCode, en: "Ending zone", uk: "Кінцева зона", ru: "Конечная зона")
    }

    static func activeTime(languageCode: String) -> String {
        localized(languageCode, en: "Active", uk: "Робота", ru: "Работа")
    }

    static func restTime(languageCode: String) -> String {
        localized(languageCode, en: "Rest before", uk: "Відпочинок до", ru: "Отдых до")
    }

    static func confidence(languageCode: String) -> String {
        localized(languageCode, en: "Detection", uk: "Розпізнавання", ru: "Распознавание")
    }

    static func recovery(languageCode: String) -> String {
        localized(languageCode, en: "Recovery", uk: "Відновлення", ru: "Восстановление")
    }

    static func heartRatePath(languageCode: String) -> String {
        localized(languageCode, en: "Set heart rate", uk: "Пульс підходу", ru: "Пульс подхода")
    }

    static func heartRateZones(languageCode: String) -> String {
        localized(languageCode, en: "Time in heart-rate zones", uk: "Час у пульсових зонах", ru: "Время в пульсовых зонах")
    }

    static func beatsPerMinute(_ value: Int, languageCode: String) -> String {
        localized(languageCode, en: "\(value) bpm", uk: "\(value) уд/хв", ru: "\(value) уд/мин")
    }

    static func heartRatePoints(
        start: Int?,
        peak: Int?,
        end: Int?,
        languageCode: String
    ) -> String {
        let missing = "—"
        return localized(
            languageCode,
            en: "Start \(start.map(String.init) ?? missing), peak \(peak.map(String.init) ?? missing), end \(end.map(String.init) ?? missing) bpm",
            uk: "Початок \(start.map(String.init) ?? missing), пік \(peak.map(String.init) ?? missing), кінець \(end.map(String.init) ?? missing) уд/хв",
            ru: "Начало \(start.map(String.init) ?? missing), пик \(peak.map(String.init) ?? missing), конец \(end.map(String.init) ?? missing) уд/мин"
        )
    }

    static func heartRateRangeValue(
        average: Int?,
        maximum: Int?,
        languageCode: String
    ) -> String {
        let missing = "—"
        return localized(
            languageCode,
            en: "Average \(average.map(String.init) ?? missing), maximum \(maximum.map(String.init) ?? missing) bpm",
            uk: "Середній \(average.map(String.init) ?? missing), максимальний \(maximum.map(String.init) ?? missing) уд/хв",
            ru: "Средний \(average.map(String.init) ?? missing), максимальный \(maximum.map(String.init) ?? missing) уд/мин"
        )
    }

    static func shareWorkout(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Share editable workout",
            uk: "Поділитися редагованим тренуванням",
            ru: "Поделиться редактируемой тренировкой"
        )
    }

    static func shareMessage(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Open this editable workout plan in GymApp.",
            uk: "Відкрий цей редагований план тренування у GymApp.",
            ru: "Открой этот редактируемый план тренировки в GymApp."
        )
    }

    static func sharePrivacy(languageCode: String) -> String {
        localized(
            languageCode,
            en: "The link contains only exercises, weights, and reps.",
            uk: "Посилання містить лише вправи, вагу й повтори.",
            ru: "Ссылка содержит только упражнения, веса и повторы."
        )
    }

    static func intervalsTitle(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Chronological watch sets",
            uk: "Хронологічні підходи з годинника",
            ru: "Хронологические подходы с часов"
        )
    }

    static func intervalsSupporting(languageCode: String) -> String {
        localized(
            languageCode,
            en: "S# follows the watch timeline and may differ from exercise-grouped set order. Read from the workout note; imported or manually edited notes are not proof of watch origin. Calories and heart-rate-zone time are slices of the full workout.",
            uk: "S# відповідає хронології годинника й може відрізнятися від порядку підходів, згрупованих за вправами. Прочитано з нотатки тренування; імпортована або вручну змінена нотатка не підтверджує походження з годинника. Калорії та час у пульсових зонах — це відрізки від загального тренування.",
            ru: "S# соответствует хронологии часов и может отличаться от порядка подходов, сгруппированных по упражнениям. Прочитано из заметки тренировки; импортированная или изменённая вручную заметка не подтверждает происхождение с часов. Калории и время в пульсовых зонах — это отрезки от общей тренировки."
        )
    }

    static func originalPartial(
        completed: Int,
        planned: Int,
        languageCode: String
    ) -> String {
        localized(
            languageCode,
            en: "Original Garmin result: completed \(completed) of \(planned) planned sets.",
            uk: "Початковий результат Garmin: виконано \(completed) із \(planned) запланованих підходів.",
            ru: "Исходный результат Garmin: выполнено \(completed) из \(planned) запланированных подходов."
        )
    }

    static func intervalLabel(
        setIndex: Int,
        startSeconds: Int64,
        endSeconds: Int64,
        languageCode: String
    ) -> String {
        localized(
            languageCode,
            en: "Watch set S\(setIndex) · \(startSeconds)–\(endSeconds)s",
            uk: "Підхід з годинника S\(setIndex) · \(startSeconds)–\(endSeconds)с",
            ru: "Подход с часов S\(setIndex) · \(startSeconds)–\(endSeconds)с"
        )
    }

    static func setLabel(_ setIndex: Int, languageCode: String) -> String {
        localized(
            languageCode,
            en: "Watch set S\(setIndex)",
            uk: "Підхід з годинника S\(setIndex)",
            ru: "Подход с часов S\(setIndex)"
        )
    }

    static func omittedRows(_ count: Int, languageCode: String) -> String {
        localized(
            languageCode,
            en: "Set metric rows omitted from the bounded workout note: \(count).",
            uk: "Рядків показників підходів, що не вмістилися в обмежену нотатку тренування: \(count).",
            ru: "Строк показателей подходов, не вместившихся в ограниченную заметку тренировки: \(count)."
        )
    }

    static func noTimedHeartRateZone(languageCode: String) -> String {
        localized(
            languageCode,
            en: "No timed heart-rate zone",
            uk: "Немає зафіксованого часу в пульсових зонах",
            ru: "Нет зафиксированного времени в пульсовых зонах"
        )
    }

    static func calorieUnit(languageCode: String) -> String {
        normalized(languageCode) == "en" ? "kcal" : "ккал"
    }

    static func secondsUnit(languageCode: String) -> String {
        normalized(languageCode) == "en" ? "s" : "с"
    }

    private static func localized(
        _ languageCode: String,
        en: String,
        uk: String,
        ru: String
    ) -> String {
        switch normalized(languageCode) {
        case "uk": uk
        case "ru": ru
        default: en
        }
    }

    private static func normalized(_ languageCode: String) -> String {
        let value = languageCode.lowercased()
        if value.hasPrefix("uk") { return "uk" }
        if value.hasPrefix("ru") { return "ru" }
        return "en"
    }
}

enum GarminWorkoutChartModel {
    static let minimumHeartRate = 40
    static let maximumHeartRate = 240

    static func heartRatePosition(_ value: Int) -> Double {
        let bounded = min(max(value, minimumHeartRate), maximumHeartRate)
        return Double(bounded - minimumHeartRate) /
            Double(maximumHeartRate - minimumHeartRate)
    }

    static func zoneFractions(_ seconds: [Int64]) -> [Double] {
        guard seconds.count == 6,
              seconds.allSatisfy({ $0 >= 0 }) else {
            return []
        }
        let total = seconds.reduce(Int64(0)) { partial, value in
            partial > Int64.max - value ? Int64.max : partial + value
        }
        guard total > 0, total < Int64.max else { return [] }
        return seconds.map { Double($0) / Double(total) }
    }
}

enum SharedWorkoutLinkError: Error, Equatable {
    case invalidExerciseCount
    case missingExercise
    case invalidExerciseName
    case invalidCatalogKey
    case invalidSetCount
    case tooManySets
    case invalidWeight
    case invalidRepetitions
    case payloadTooLarge
    case encodingFailed
}

enum SharedWorkoutLinkEncoder {
    static let maximumEncodedLength = 12_000
    static let maximumDecodedBytes = 9_000
    static let maximumExercises = 20
    static let maximumSetsPerExercise = 12
    static let maximumTotalSets = 120
    static let maximumExerciseNameCharacters = 120
    static let maximumExerciseNameBytes = 480
    static let maximumCatalogKeyCharacters = 64
    static let maximumWeight = 1_000_000.0
    static let maximumRepetitions = 10_000

    static func makeURL(
        workout: WorkoutSession,
        exercises: [UUID: Exercise]
    ) throws -> URL {
        let blocks = workout.exercises.filter { !$0.sets.isEmpty }
        guard !blocks.isEmpty, blocks.count <= maximumExercises else {
            throw SharedWorkoutLinkError.invalidExerciseCount
        }

        var totalSets = 0
        var compactExercises: [[Any]] = []
        compactExercises.reserveCapacity(blocks.count)
        for block in blocks {
            guard let exercise = exercises[block.exerciseID] else {
                throw SharedWorkoutLinkError.missingExercise
            }
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.unicodeScalars.count <= maximumExerciseNameCharacters,
                  name.utf8.count <= maximumExerciseNameBytes,
                  !name.unicodeScalars.contains(where: {
                    $0.value <= 0x1F || $0.value == 0x7F
                  }) else {
                throw SharedWorkoutLinkError.invalidExerciseName
            }

            let catalogKey = exercise.catalogKey ?? ""
            guard validCatalogKey(catalogKey) else {
                throw SharedWorkoutLinkError.invalidCatalogKey
            }
            guard block.sets.count <= maximumSetsPerExercise else {
                throw SharedWorkoutLinkError.invalidSetCount
            }
            totalSets += block.sets.count
            guard totalSets <= maximumTotalSets else {
                throw SharedWorkoutLinkError.tooManySets
            }

            let compactSets: [[Any]] = try block.sets.map { set in
                guard set.weight.isFinite,
                      (0 ... maximumWeight).contains(set.weight) else {
                    throw SharedWorkoutLinkError.invalidWeight
                }
                guard (1 ... maximumRepetitions).contains(set.reps) else {
                    throw SharedWorkoutLinkError.invalidRepetitions
                }
                return [set.weight, set.reps]
            }
            compactExercises.append([catalogKey, name, compactSets])
        }

        let compactPayload: [String: Any] = ["v": 1, "e": compactExercises]
        guard JSONSerialization.isValidJSONObject(compactPayload),
              let data = try? JSONSerialization.data(withJSONObject: compactPayload),
              data.count <= maximumDecodedBytes else {
            throw SharedWorkoutLinkError.payloadTooLarge
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=+$", with: "", options: .regularExpression)
        guard !encoded.isEmpty, encoded.count <= maximumEncodedLength,
              let url = URL(string: "https://gymapptracker.com/#workout=\(encoded)") else {
            throw SharedWorkoutLinkError.encodingFailed
        }
        return url
    }

    private static func validCatalogKey(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard value.count <= maximumCatalogKeyCharacters else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x61 && scalar.value <= 0x7A) ||
                (scalar.value >= 0x30 && scalar.value <= 0x39) ||
                scalar.value == 0x5F
        }
    }
}

private struct GarminHeartRateRangeChart: View {
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GarminWorkoutDetailCopy.heartRateChart(languageCode: languageCode))
                .font(.caption.weight(.bold))
                .foregroundStyle(GymTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.35)

            Canvas { context, size in
                let startX: CGFloat = 10
                let endX = max(startX, size.width - 10)
                let centerY = size.height / 2
                let x: (Int) -> CGFloat = { value in
                    startX + CGFloat(GarminWorkoutChartModel.heartRatePosition(value)) *
                        (endX - startX)
                }

                var track = Path()
                track.move(to: CGPoint(x: startX, y: centerY))
                track.addLine(to: CGPoint(x: endX, y: centerY))
                context.stroke(track, with: .color(GymTheme.outlineSoft), lineWidth: 6)

                if let averageHeartRate, let maximumHeartRate {
                    var range = Path()
                    range.move(to: CGPoint(x: x(averageHeartRate), y: centerY))
                    range.addLine(to: CGPoint(x: x(maximumHeartRate), y: centerY))
                    context.stroke(range, with: .color(GymTheme.primary), lineWidth: 8)
                }
                if let averageHeartRate {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x(averageHeartRate) - 7,
                            y: centerY - 7,
                            width: 14,
                            height: 14
                        )),
                        with: .color(GymTheme.secondary)
                    )
                }
                if let maximumHeartRate {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x(maximumHeartRate) - 7,
                            y: centerY - 7,
                            width: 14,
                            height: 14
                        )),
                        with: .color(GymTheme.tertiary)
                    )
                }
            }
            .frame(height: 54)
            .padding(.horizontal, 6)
            .background(
                GymTheme.surfaceVariant.opacity(0.7),
                in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GarminWorkoutDetailCopy.heartRateChart(languageCode: languageCode))
            .accessibilityValue(
                GarminWorkoutDetailCopy.heartRateRangeValue(
                    average: averageHeartRate,
                    maximum: maximumHeartRate,
                    languageCode: languageCode
                )
            )

            HStack {
                if let averageHeartRate {
                    Label(
                        GarminWorkoutDetailCopy.beatsPerMinute(
                            averageHeartRate,
                            languageCode: languageCode
                        ),
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(GymTheme.secondary)
                }
                Spacer()
                if let maximumHeartRate {
                    Label(
                        GarminWorkoutDetailCopy.beatsPerMinute(
                            maximumHeartRate,
                            languageCode: languageCode
                        ),
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(GymTheme.tertiary)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }
}

private struct GarminSetMetricsCard: View {
    let setIndex: Int
    let interval: GarminWorkoutNoteInterval?
    let metrics: GarminWorkoutNoteSetMetrics?
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(GymTheme.textPrimary)
                Spacer(minLength: 8)
                if let seconds = interval.map({ $0.endSeconds - $0.startSeconds }) ?? metrics?.activeSeconds {
                    Text(garminDuration(seconds))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GymTheme.primary)
                }
            }

            if metrics != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if let active = metrics?.activeSeconds {
                            GymInfoPill(
                                "\(GarminWorkoutDetailCopy.activeTime(languageCode: languageCode)) \(garminDuration(active))",
                                systemImage: "figure.strengthtraining.traditional"
                            )
                        }
                        if let rest = metrics?.restBeforeSeconds, rest > 0 {
                            GymInfoPill(
                                "\(GarminWorkoutDetailCopy.restTime(languageCode: languageCode)) \(garminDuration(rest))",
                                systemImage: "timer",
                                accent: GymTheme.tertiary
                            )
                        }
                        if let confidence = metrics?.detectionConfidence {
                            GymInfoPill(
                                "\(GarminWorkoutDetailCopy.confidence(languageCode: languageCode)) \(confidence)%",
                                systemImage: "waveform.path.ecg",
                                accent: GymTheme.secondary
                            )
                        }
                        if let recovery = metrics?.recoveryHeartRateDrop {
                            GymInfoPill(
                                "\(GarminWorkoutDetailCopy.recovery(languageCode: languageCode)) ↓\(recovery)",
                                systemImage: "heart.fill",
                                accent: GymTheme.secondary
                            )
                        }
                    }
                }
            }

            if let metrics, metrics.hasHeartRate {
                GarminSetHeartRateChart(metrics: metrics, languageCode: languageCode)
            }

            if let interval {
                let gym = interval.gymCalories.formatted(
                    .number.precision(.fractionLength(0 ... 2))
                )
                let unit = GarminWorkoutDetailCopy.calorieUnit(languageCode: languageCode)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(label: "GymApp", value: "\(gym) \(unit)")
                    if let garminCalories = interval.garminCalories {
                        GymMetricTile(label: "Garmin", value: "\(garminCalories) \(unit)")
                    }
                }

                GarminHeartRateZoneChart(
                    seconds: interval.heartRateZoneSeconds,
                    languageCode: languageCode
                )
            }
        }
        .padding(13)
        .background(
            GymTheme.surfaceVariant.opacity(0.54),
            in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
                .strokeBorder(GymTheme.outlineSoft.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        if let interval {
            return GarminWorkoutDetailCopy.intervalLabel(
                setIndex: setIndex,
                startSeconds: interval.startSeconds,
                endSeconds: interval.endSeconds,
                languageCode: languageCode
            )
        }
        return GarminWorkoutDetailCopy.setLabel(setIndex, languageCode: languageCode)
    }
}

private struct GarminSetHeartRateChart: View {
    let metrics: GarminWorkoutNoteSetMetrics
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(GarminWorkoutDetailCopy.heartRatePath(languageCode: languageCode))
                .font(.caption.weight(.bold))
                .foregroundStyle(GymTheme.textSecondary)

            Canvas { context, size in
                let values: [(CGFloat, Int?)] = [
                    (0.08, metrics.startHeartRate),
                    (0.50, metrics.peakHeartRate),
                    (0.92, metrics.endHeartRate)
                ]
                let points = values.compactMap { relativeX, value -> CGPoint? in
                    guard let value else { return nil }
                    let normalized = GarminWorkoutChartModel.heartRatePosition(value)
                    return CGPoint(
                        x: size.width * relativeX,
                        y: 8 + (1 - CGFloat(normalized)) * max(0, size.height - 16)
                    )
                }
                if points.count >= 2 {
                    var line = Path()
                    line.move(to: points[0])
                    for point in points.dropFirst() {
                        line.addLine(to: point)
                    }
                    context.stroke(line, with: .color(GymTheme.primary), lineWidth: 3)
                }
                for point in points {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - 5,
                            y: point.y - 5,
                            width: 10,
                            height: 10
                        )),
                        with: .color(GymTheme.secondary)
                    )
                }
            }
            .frame(height: 76)
            .background(
                GymTheme.surface.opacity(0.76),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GarminWorkoutDetailCopy.heartRatePath(languageCode: languageCode))
            .accessibilityValue(
                GarminWorkoutDetailCopy.heartRatePoints(
                    start: metrics.startHeartRate,
                    peak: metrics.peakHeartRate,
                    end: metrics.endHeartRate,
                    languageCode: languageCode
                )
            )

            HStack {
                Text(metrics.startHeartRate.map(String.init) ?? "—")
                Spacer()
                Text(metrics.peakHeartRate.map(String.init) ?? "—")
                Spacer()
                Text(metrics.endHeartRate.map(String.init) ?? "—")
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .accessibilityHidden(true)
        }
    }
}

private struct GarminHeartRateZoneChart: View {
    let seconds: [Int64]
    let languageCode: String

    private let colors: [Color] = [
        GymTheme.outline,
        Color.blue.opacity(0.62),
        GymTheme.secondary,
        Color.yellow.opacity(0.82),
        Color.orange.opacity(0.86),
        GymTheme.error
    ]

    var body: some View {
        let fractions = GarminWorkoutChartModel.zoneFractions(seconds)
        VStack(alignment: .leading, spacing: 7) {
            Text(GarminWorkoutDetailCopy.heartRateZones(languageCode: languageCode))
                .font(.caption.weight(.bold))
                .foregroundStyle(GymTheme.textSecondary)

            if fractions.isEmpty {
                Text(GarminWorkoutDetailCopy.noTimedHeartRateZone(languageCode: languageCode))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(fractions.indices, id: \.self) { index in
                            if fractions[index] > 0 {
                                Rectangle()
                                    .fill(colors[index])
                                    .frame(
                                        width: max(
                                            2,
                                            (geometry.size.width - 10) * fractions[index]
                                        )
                                    )
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    GarminWorkoutDetailCopy.heartRateZones(languageCode: languageCode)
                )
                .accessibilityValue(accessibilityValue)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { zoneLegend }
                    VStack(alignment: .leading, spacing: 5) { zoneLegend }
                }
            }
        }
    }

    @ViewBuilder
    private var zoneLegend: some View {
        let unit = GarminWorkoutDetailCopy.secondsUnit(languageCode: languageCode)
        ForEach(seconds.indices, id: \.self) { index in
            if seconds[index] > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text("Z\(index) \(seconds[index])\(unit)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private var accessibilityValue: String {
        let unit = GarminWorkoutDetailCopy.secondsUnit(languageCode: languageCode)
        let values = seconds.enumerated().compactMap { index, value in
            value > 0 ? "Z\(index) \(value)\(unit)" : nil
        }
        return values.isEmpty
            ? GarminWorkoutDetailCopy.noTimedHeartRateZone(languageCode: languageCode)
            : values.joined(separator: ", ")
    }
}

private func garminDuration(_ seconds: Int64) -> String {
    let bounded = max(0, seconds)
    if bounded >= 3_600 {
        return String(format: "%lld:%02lld:%02lld", bounded / 3_600, (bounded / 60) % 60, bounded % 60)
    }
    return String(format: "%lld:%02lld", bounded / 60, bounded % 60)
}

struct WorkoutDetailWorkoutDeletionTarget: Equatable, Identifiable {
    let accountStorageKey: String
    let storeIdentifier: ObjectIdentifier
    let workoutSnapshot: WorkoutSession

    var id: UUID { workoutSnapshot.id }

    @MainActor
    init(store: WorkoutStore, workout: WorkoutSession) {
        accountStorageKey = store.accountStorageKey
        storeIdentifier = ObjectIdentifier(store)
        workoutSnapshot = workout
    }

    @MainActor
    func isCurrent(in store: WorkoutStore, expectedWorkoutID: UUID) -> Bool {
        storeIdentifier == ObjectIdentifier(store)
            && accountStorageKey == store.accountStorageKey
            && workoutSnapshot.id == expectedWorkoutID
            && store.workout(id: expectedWorkoutID) == workoutSnapshot
    }
}

enum WorkoutDetailDeletionTarget: Equatable, Identifiable {
    struct Context: Equatable {
        let accountStorageKey: String
        let storeIdentifier: ObjectIdentifier
        let workoutSnapshot: WorkoutSession

        var workoutID: UUID { workoutSnapshot.id }
        var workoutExerciseIDs: [UUID] { workoutSnapshot.exercises.map(\.id) }
    }

    enum Impact: Equatable {
        case setOnly
        case setAndExercise
        case setExerciseAndWorkout
        case exerciseOnly
        case exerciseAndWorkout
    }

    case set(
        context: Context,
        block: WorkoutExercise,
        set: WorkoutSet,
        position: Int,
        exerciseName: String
    )
    case exercise(
        context: Context,
        block: WorkoutExercise,
        exerciseName: String
    )

    var id: String {
        switch self {
        case let .set(context, block, set, _, _):
            "set-\(context.workoutID.uuidString)-\(block.id.uuidString)-\(set.id.uuidString)"
        case let .exercise(context, block, _):
            "exercise-\(context.workoutID.uuidString)-\(block.id.uuidString)"
        }
    }

    var workoutID: UUID { context.workoutID }
    var blockID: UUID { expectedBlock.id }

    var setID: UUID? {
        guard case let .set(_, _, set, _, _) = self else { return nil }
        return set.id
    }

    var undoMessage: String {
        switch self {
        case .set: "Set deleted"
        case .exercise: "Exercise deleted"
        }
    }

    var impact: Impact {
        switch self {
        case let .set(context, block, _, _, _):
            if block.sets.count > 1 { return .setOnly }
            return context.workoutExerciseIDs.count > 1
                ? .setAndExercise
                : .setExerciseAndWorkout
        case let .exercise(context, _, _):
            return context.workoutExerciseIDs.count > 1
                ? .exerciseOnly
                : .exerciseAndWorkout
        }
    }

    @MainActor
    static func set(
        store: WorkoutStore,
        workout: WorkoutSession,
        block: WorkoutExercise,
        set: WorkoutSet,
        position: Int,
        exerciseName: String
    ) -> Self {
        .set(
            context: context(store: store, workout: workout),
            block: block,
            set: set,
            position: position,
            exerciseName: exerciseName
        )
    }

    @MainActor
    static func exercise(
        store: WorkoutStore,
        workout: WorkoutSession,
        block: WorkoutExercise,
        exerciseName: String
    ) -> Self {
        .exercise(
            context: context(store: store, workout: workout),
            block: block,
            exerciseName: exerciseName
        )
    }

    @MainActor
    func isCurrent(in store: WorkoutStore, expectedWorkoutID: UUID) -> Bool {
        guard context.storeIdentifier == ObjectIdentifier(store),
              context.accountStorageKey == store.accountStorageKey,
              context.workoutID == expectedWorkoutID,
              let workout = store.workout(id: context.workoutID),
              workout == context.workoutSnapshot,
              let currentBlock = workout.exercises.first(where: { $0.id == expectedBlock.id }),
              currentBlock == expectedBlock else {
            return false
        }

        switch self {
        case let .set(_, _, expectedSet, _, _):
            return currentBlock.sets.contains(expectedSet)
        case .exercise:
            return true
        }
    }

    func confirmationTitle(languageCode: String) -> String {
        switch self {
        case let .set(_, _, _, position, exerciseName):
            return localizedFormat(
                "Delete set %1$lld from “%2$@”?",
                languageCode: languageCode,
                arguments: [Int64(position + 1), exerciseName]
            )
        case let .exercise(_, _, exerciseName):
            return localizedFormat(
                "Delete “%@” from this workout?",
                languageCode: languageCode,
                arguments: [exerciseName]
            )
        }
    }

    func confirmationMessage(languageCode: String) -> String {
        let key: String
        switch impact {
        case .setOnly:
            key = "Only this set will be deleted. Undo is available briefly while you stay on this screen."
        case .setAndExercise:
            key = "This is the final set for the exercise, so the exercise will also be deleted from the workout. Undo is available briefly while you stay on this screen."
        case .setExerciseAndWorkout:
            key = "This is the final set in the workout, so the exercise and the entire workout will also be deleted. Undo is available briefly while you stay on this screen."
        case .exerciseOnly:
            key = "This exercise and all of its sets will be deleted from the workout. Undo is available briefly while you stay on this screen."
        case .exerciseAndWorkout:
            key = "This is the last exercise, so deleting it will also delete the entire workout. Undo is available briefly while you stay on this screen."
        }
        return gymLocalized(key, languageCode: languageCode)
    }

    private var context: Context {
        switch self {
        case let .set(context, _, _, _, _), let .exercise(context, _, _): context
        }
    }

    private var expectedBlock: WorkoutExercise {
        switch self {
        case let .set(_, block, _, _, _), let .exercise(_, block, _): block
        }
    }

    @MainActor
    private static func context(store: WorkoutStore, workout: WorkoutSession) -> Context {
        Context(
            accountStorageKey: store.accountStorageKey,
            storeIdentifier: ObjectIdentifier(store),
            workoutSnapshot: workout
        )
    }

    private func localizedFormat(
        _ key: String,
        languageCode: String,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: gymLocalized(key, languageCode: languageCode),
            locale: AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale,
            arguments: arguments
        )
    }
}

@MainActor
struct WorkoutDetailView: View {
    private enum ActiveAlert: Identifiable {
        case deleteWorkout(WorkoutDetailWorkoutDeletionTarget)
        case deleteItem(WorkoutDetailDeletionTarget)

        var id: String {
            switch self {
            case let .deleteWorkout(target): "delete-workout-\(target.id.uuidString)"
            case let .deleteItem(target): "delete-\(target.id)"
            }
        }
    }

    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var restTimers: RestTimerManager

    @State private var date: Date
    @State private var note: String
    @State private var showingExercisePicker = false
    @State private var activeAlert: ActiveAlert?
    @State private var statusMessage: String?
    @State private var pendingDeletion: WorkoutDetailDeletionTarget?
    @State private var deletionTask: Task<Void, Never>?

    private let workoutID: UUID
    private let onFinish: (UUID) -> Void
    private let onDeleted: () -> Void
    private let reportStatus: (String, Bool) -> Void
    private let isStoreContextCurrent: () -> Bool

    init(
        appState: AppState,
        workoutID: UUID,
        onFinish: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.init(
            store: appState.workoutStore,
            restTimers: appState.restTimers,
            workoutID: workoutID,
            onFinish: onFinish,
            onDeleted: onDeleted,
            onStatus: { [weak appState] message, isError in
                appState?.show(message: message, isError: isError)
            },
            isStoreContextCurrent: { [weak appState, weak store = appState.workoutStore] in
                guard let appState, let store else { return false }
                return appState.isAccountReady
                    && appState.workoutStore === store
                    && appState.activeAccountStorageKey == store.accountStorageKey
            }
        )
    }

    init(
        store: WorkoutStore,
        restTimers: RestTimerManager,
        workoutID: UUID,
        onFinish: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void = {},
        onStatus: @escaping (String, Bool) -> Void = { _, _ in },
        isStoreContextCurrent: @escaping () -> Bool = { true }
    ) {
        _store = ObservedObject(wrappedValue: store)
        _restTimers = ObservedObject(wrappedValue: restTimers)
        self.workoutID = workoutID
        self.onFinish = onFinish
        self.onDeleted = onDeleted
        self.reportStatus = onStatus
        self.isStoreContextCurrent = isStoreContextCurrent
        let workout = store.workout(id: workoutID)
        _date = State(initialValue: workout?.date ?? Date())
        _note = State(initialValue: workout?.note ?? "")
    }

    var body: some View {
        GymBackground {
            if let workout = store.workout(id: workoutID) {
                let garminSummary = GarminWorkoutNoteParser.parse(workout.note)
                ScrollView {
                    LazyVStack(spacing: 14) {
                        hero(workout, garminSummary: garminSummary)

                        if let summary = garminSummary {
                            if summary.hasWorkoutMetrics {
                                garminMetricsPanel(summary)
                            }
                            if !summary.visualSetIndexes.isEmpty || summary.omittedMetricRows != nil ||
                                (summary.completedSetCount != nil &&
                                    (summary.plannedSetCount ?? 0) >
                                        (summary.completedSetCount ?? Int.max)) {
                                garminSetIntervalsPanel(summary)
                            }
                        }

                        if let statusMessage {
                            GymStatusBanner(message: statusMessage, isError: true)
                        }

                        metadataPanel(isGarminWorkout: garminSummary != nil)
                        exerciseSection(workout)
                        finishPanel(workout)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                GymContentUnavailableView(
                    "Workout unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("It may have been deleted on another screen.")
                )
            }
        }
        .navigationTitle("Workout detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    presentWorkoutDeletionConfirmation()
                } label: {
                    Label("Delete workout", systemImage: "trash")
                }
                .disabled(pendingDeletion != nil)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                exercises: store.exercises,
                selectedExerciseIDs: Set(store.workout(id: workoutID)?.exercises.map(\.exerciseID) ?? []),
                muscleMappings: store.muscleMappings,
                sessionCounts: exerciseSessionCounts,
                onSelect: addExercise,
                onCreate: { try store.addExercise(name: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(item: $activeAlert, content: makeAlert)
        .safeAreaInset(edge: .bottom) {
            if let pendingDeletion {
                undoBar(pendingDeletion)
            }
        }
        .onDisappear {
            commitPendingDeletion()
        }
    }

    private func hero(
        _ workout: WorkoutSession,
        garminSummary: GarminWorkoutNoteSummary?
    ) -> some View {
        let languageCode = gymCurrentLanguageCode()
        return GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(gymFormattedDate(workout.date, date: .long, time: .shortened))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(
                    garminSummary == nil
                        ? (workout.note?.isEmpty == false ? workout.note! : gymLocalized("Saved workout"))
                        : GarminWorkoutDetailCopy.workoutTitle(languageCode: languageCode)
                )
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                if garminSummary != nil {
                    Text(GarminWorkoutDetailCopy.syncedSupporting(languageCode: languageCode))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    GymMetricTile(label: "Exercises", value: workout.exercises.count.formatted(), onHero: true)
                    GymMetricTile(label: "Sets", value: workout.setCount.formatted(), onHero: true)
                    GymMetricTile(
                        label: "Volume",
                        value: workout.totalVolume.formatted(.number.precision(.fractionLength(0 ... 1))),
                        onHero: true
                    )
                }

                if let shareURL = sharedWorkoutURL(workout) {
                    ShareLink(
                        item: shareURL,
                        subject: Text("GymApp workout"),
                        message: Text(
                            GarminWorkoutDetailCopy.shareMessage(languageCode: languageCode)
                        )
                    ) {
                        Label(
                            GarminWorkoutDetailCopy.shareWorkout(languageCode: languageCode),
                            systemImage: "square.and.arrow.up"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityHint(
                        GarminWorkoutDetailCopy.sharePrivacy(languageCode: languageCode)
                    )

                    Text(GarminWorkoutDetailCopy.sharePrivacy(languageCode: languageCode))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.76))
                }
            }
        }
    }

    private func sharedWorkoutURL(_ workout: WorkoutSession) -> URL? {
        var exercisesByID: [UUID: Exercise] = [:]
        for exercise in store.exercises {
            exercisesByID[exercise.id] = exercise
        }
        return try? SharedWorkoutLinkEncoder.makeURL(
            workout: workout,
            exercises: exercisesByID
        )
    }

    private var exerciseSessionCounts: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: store.exercises.map { exercise in
                (exercise.id, store.progressStats(exerciseID: exercise.id).sessionCount)
            }
        )
    }

    private func garminMetricsPanel(_ summary: GarminWorkoutNoteSummary) -> some View {
        let languageCode = gymCurrentLanguageCode()
        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Garmin",
                    title: GarminWorkoutDetailCopy.metricsTitle(languageCode: languageCode),
                    supporting: GarminWorkoutDetailCopy.metricsSupporting(languageCode: languageCode)
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    if let duration = summary.durationSeconds {
                        GymMetricTile(
                            label: GarminWorkoutDetailCopy.duration(languageCode: languageCode),
                            value: garminDuration(duration)
                        )
                    }
                    if let gymCalories = summary.gymCalories {
                        GymMetricTile(
                            label: "GymApp",
                            value: "\(gymCalories) \(GarminWorkoutDetailCopy.calorieUnit(languageCode: languageCode))"
                        )
                    }
                    if let garminCalories = summary.garminCalories {
                        GymMetricTile(
                            label: "Garmin",
                            value: "\(garminCalories) \(GarminWorkoutDetailCopy.calorieUnit(languageCode: languageCode))"
                        )
                    }
                    if let average = summary.averageHeartRate {
                        GymMetricTile(
                            label: GarminWorkoutDetailCopy.averageHeartRate(languageCode: languageCode),
                            value: GarminWorkoutDetailCopy.beatsPerMinute(
                                average,
                                languageCode: languageCode
                            )
                        )
                    }
                    if let maximum = summary.maximumHeartRate {
                        GymMetricTile(
                            label: GarminWorkoutDetailCopy.maximumHeartRate(languageCode: languageCode),
                            value: GarminWorkoutDetailCopy.beatsPerMinute(
                                maximum,
                                languageCode: languageCode
                            )
                        )
                    }
                    if let zone = summary.endingHeartRateZone {
                        GymMetricTile(
                            label: GarminWorkoutDetailCopy.endingZone(languageCode: languageCode),
                            value: "Z\(zone)"
                        )
                    }
                }

                if summary.averageHeartRate != nil || summary.maximumHeartRate != nil {
                    GarminHeartRateRangeChart(
                        averageHeartRate: summary.averageHeartRate,
                        maximumHeartRate: summary.maximumHeartRate,
                        languageCode: languageCode
                    )
                }
            }
        }
    }

    private func garminSetIntervalsPanel(_ summary: GarminWorkoutNoteSummary) -> some View {
        let languageCode = gymCurrentLanguageCode()
        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Garmin",
                    title: GarminWorkoutDetailCopy.intervalsTitle(languageCode: languageCode),
                    supporting: GarminWorkoutDetailCopy.intervalsSupporting(
                        languageCode: languageCode
                    )
                )
                if let completedSetCount = summary.completedSetCount,
                   let plannedSetCount = summary.plannedSetCount,
                   plannedSetCount > completedSetCount {
                    Text(
                        GarminWorkoutDetailCopy.originalPartial(
                            completed: completedSetCount,
                            planned: plannedSetCount,
                            languageCode: languageCode
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                }
                ForEach(summary.visualSetIndexes, id: \.self) { setIndex in
                    GarminSetMetricsCard(
                        setIndex: setIndex,
                        interval: summary.interval(for: setIndex),
                        metrics: summary.metrics(for: setIndex),
                        languageCode: languageCode
                    )
                }
                if let omittedMetricRows = summary.omittedMetricRows {
                    Text(
                        GarminWorkoutDetailCopy.omittedRows(
                            omittedMetricRows,
                            languageCode: languageCode
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private func metadataPanel(isGarminWorkout: Bool) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    eyebrow: "Session",
                    title: isGarminWorkout ? "Date" : "Date and note",
                    supporting: isGarminWorkout
                        ? "Garmin receipt data is kept unchanged so charts remain accurate."
                        : "Save changes before finishing the workout."
                )
                DatePicker("Workout date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                if !isGarminWorkout {
                    TextField("Notes (optional)", text: $note, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .gymTextFieldChrome()
                }
                Button(action: saveMetadata) {
                    Label("Save session details", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GymSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ workout: WorkoutSession) -> some View {
        HStack {
            GymSectionTitle(
                eyebrow: "Log",
                title: "Exercises and sets",
                supporting: "Add Set starts a 90 second rest timer."
            )
            Spacer(minLength: 8)
            Button {
                showingExercisePicker = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add exercise to workout")
        }
        .padding(.horizontal, 4)

        ForEach(visibleExercises(workout)) { block in
            storedExerciseCard(workout: workout, block: block)
        }
    }

    private func storedExerciseCard(
        workout: WorkoutSession,
        block: WorkoutExercise
    ) -> some View {
        let exercise = store.exercise(id: block.exerciseID)
        let name = exercise.map { gymExerciseName($0) } ?? gymLocalized("Deleted exercise")
        let priorHistory = store.exerciseHistory(exerciseID: block.exerciseID)
            .filter { $0.workoutID != workout.id }
        let priorMaxWeight = priorHistory.map(\.weight).max()
        let priorEstimatedMax = priorHistory.map(\.estimatedOneRepMax).max()
        let timerID = timerKey(blockID: block.id)

        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    if let exercise {
                        ExerciseMediaButton(
                            exerciseName: exercise.name,
                            exerciseID: exercise.id,
                            ownerKey: store.accountStorageKey
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(priorMaxWeight.map {
                            gymText(
                                "Previous best: \($0.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                "Попередній рекорд: \($0.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                languageCode: gymCurrentLanguageCode()
                            )
                        } ?? gymLocalized("First logged workout"))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        presentDeletionConfirmation(
                            .exercise(
                                store: store,
                                workout: workout,
                                block: block,
                                exerciseName: name
                            )
                        )
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        gymText(
                            "Delete \(name) from workout",
                            "Видалити «\(name)» із тренування",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .disabled(pendingDeletion != nil)
                }

                WorkoutRestTimerControls(
                    manager: restTimers,
                    timerID: timerID,
                    exerciseName: name
                )

                ForEach(Array(visibleSets(block).enumerated()), id: \.element.id) { index, set in
                    StoredWorkoutSetEditorRow(
                        set: set,
                        position: index,
                        prLabels: prLabels(
                            set: set,
                            previousMaxWeight: priorMaxWeight,
                            previousEstimatedMax: priorEstimatedMax
                        ),
                        lastWeight: store.lastWeight(exerciseID: block.exerciseID, before: workout.date),
                        onSave: { weight, reps in
                            do {
                                try store.updateSet(
                                    workoutID: workout.id,
                                    workoutExerciseID: block.id,
                                    setID: set.id,
                                    weight: weight,
                                    reps: reps
                                )
                            } catch {
                                show(error)
                            }
                        },
                        onDelete: {
                            presentDeletionConfirmation(
                                .set(
                                    store: store,
                                    workout: workout,
                                    block: block,
                                    set: set,
                                    position: index,
                                    exerciseName: name
                                )
                            )
                        }
                    )
                    .disabled(pendingDeletion != nil)
                }

                Button {
                    addSet(to: block, workout: workout, exerciseName: name)
                } label: {
                    Label("Add set · start 90 sec rest", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Adds a set using the latest values and starts the rest timer")
            }
        }
    }

    private func finishPanel(_ workout: WorkoutSession) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Finish",
                    title: "Complete this workout",
                    supporting: "See XP, personal records, trained muscles, missions, and badges."
                )
                Button {
                    finish(workout)
                } label: {
                    Label("Finish and view summary", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(GymPrimaryButtonStyle())
            }
        }
    }

    private func undoBar(_ pending: WorkoutDetailDeletionTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(GymTheme.error)
                .accessibilityHidden(true)
            Text(gymLocalized(pending.undoMessage))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("Undo", action: undoDeletion)
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private func visibleExercises(_ workout: WorkoutSession) -> [WorkoutExercise] {
        workout.exercises.filter { block in
            guard case let .exercise(_, hiddenBlock, _) = pendingDeletion else { return true }
            return block.id != hiddenBlock.id
        }
    }

    private func visibleSets(_ block: WorkoutExercise) -> [WorkoutSet] {
        block.sets.filter { set in
            guard case let .set(_, pendingBlock, hiddenSet, _, _) = pendingDeletion,
                  pendingBlock.id == block.id else { return true }
            return set.id != hiddenSet.id
        }
    }

    private func prLabels(
        set: WorkoutSet,
        previousMaxWeight: Double?,
        previousEstimatedMax: Double?
    ) -> [String] {
        var labels: [String] = []
        if set.weight > (previousMaxWeight ?? -1) { labels.append("Weight PR") }
        if set.estimatedOneRepMax > (previousEstimatedMax ?? -1) { labels.append("Estimated 1RM PR") }
        return labels
    }

    private func addExercise(_ exercise: Exercise) {
        do {
            _ = try store.addExercise(
                toWorkout: workoutID,
                exerciseID: exercise.id,
                initialSet: WorkoutSetDraft(
                    weight: store.lastWeight(exerciseID: exercise.id) ?? 0,
                    reps: 10
                )
            )
        } catch {
            show(error)
        }
    }

    private func addSet(
        to block: WorkoutExercise,
        workout: WorkoutSession,
        exerciseName: String
    ) {
        let source = block.sets.last
        do {
            _ = try store.addSet(
                workoutID: workout.id,
                workoutExerciseID: block.id,
                weight: source?.weight ?? store.lastWeight(exerciseID: block.exerciseID) ?? 0,
                reps: source?.reps ?? 10
            )
            restTimers.start(
                id: timerKey(blockID: block.id),
                seconds: 90,
                title: exerciseName
            )
        } catch {
            show(error)
        }
    }

    private func saveMetadata() {
        do {
            try store.updateWorkout(id: workoutID, date: date, note: note)
            statusMessage = nil
            reportStatus("Workout details updated.", false)
        } catch {
            show(error)
        }
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .deleteWorkout(target):
            return Alert(
                title: Text("Delete workout?"),
                message: Text("This removes the workout and every set. This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteWorkout(target)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        case let .deleteItem(target):
            let languageCode = gymCurrentLanguageCode()
            return Alert(
                title: Text(target.confirmationTitle(languageCode: languageCode)),
                message: Text(target.confirmationMessage(languageCode: languageCode)),
                primaryButton: .destructive(Text(gymLocalized("Delete", languageCode: languageCode))) {
                    confirmDeletion(target)
                },
                secondaryButton: .cancel(Text(gymLocalized("Cancel", languageCode: languageCode)))
            )
        }
    }

    private func presentWorkoutDeletionConfirmation() {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              let workout = store.workout(id: workoutID) else {
            showStaleDeletion()
            return
        }
        activeAlert = .deleteWorkout(
            WorkoutDetailWorkoutDeletionTarget(store: store, workout: workout)
        )
    }

    private func presentDeletionConfirmation(_ target: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        activeAlert = .deleteItem(target)
    }

    private func confirmDeletion(_ target: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        stageDeletion(target)
    }

    private func finish(_ workout: WorkoutSession) {
        guard isStoreContextCurrent() else {
            showStaleDeletion()
            return
        }
        if commitPendingDeletion() { return }
        guard store.workout(id: workout.id) != nil else {
            onDeleted()
            return
        }
        do {
            try store.updateWorkout(id: workout.id, date: date, note: note)
            onFinish(workout.id)
        } catch {
            show(error)
        }
    }

    private func deleteWorkout(_ target: WorkoutDetailWorkoutDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        do {
            let timerIDs = target.workoutSnapshot.exercises.map { timerKey(blockID: $0.id) }
            try store.deleteWorkout(id: workoutID)
            deletionTask?.cancel()
            pendingDeletion = nil
            timerIDs.forEach { restTimers.cancel(id: $0) }
            reportStatus("Workout deleted.", false)
            onDeleted()
        } catch {
            show(error)
        }
    }

    private func stageDeletion(_ deletion: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil else { return }
        pendingDeletion = deletion
        deletionTask?.cancel()
        deletionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, pendingDeletion == deletion else { return }
                commitPendingDeletion()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func undoDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
        pendingDeletion = nil
    }

    @discardableResult
    private func commitPendingDeletion() -> Bool {
        deletionTask?.cancel()
        deletionTask = nil
        guard let deletion = pendingDeletion else { return false }
        pendingDeletion = nil
        guard isStoreContextCurrent(),
              deletion.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return false
        }
        do {
            switch deletion {
            case let .set(_, block, set, _, _):
                try store.deleteSet(
                    workoutID: workoutID,
                    workoutExerciseID: block.id,
                    setID: set.id
                )
                if store.workout(id: workoutID)?.exercises.contains(where: { $0.id == block.id }) != true {
                    restTimers.cancel(id: timerKey(blockID: block.id))
                }
            case let .exercise(_, block, _):
                try store.removeExercise(fromWorkout: workoutID, workoutExerciseID: block.id)
                restTimers.cancel(id: timerKey(blockID: block.id))
            }
            if store.workout(id: workoutID) == nil {
                onDeleted()
                return true
            }
        } catch {
            show(error)
        }
        return false
    }

    private func timerKey(blockID: UUID) -> String {
        "workout-\(workoutID.uuidString)-exercise-\(blockID.uuidString)"
    }

    private func show(_ error: Error) {
        statusMessage = gymErrorMessage(error)
    }

    private func showStaleDeletion() {
        statusMessage = gymLocalized(
            "The workout changed before deletion. Review it and try again."
        )
    }
}

private struct StoredWorkoutSetEditorRow: View {
    @State private var weight: Double
    @State private var reps: Int

    let set: WorkoutSet
    let position: Int
    let prLabels: [String]
    let lastWeight: Double?
    let onSave: (Double, Int) -> Void
    let onDelete: () -> Void

    init(
        set: WorkoutSet,
        position: Int,
        prLabels: [String],
        lastWeight: Double?,
        onSave: @escaping (Double, Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.position = position
        self.prLabels = prLabels
        self.lastWeight = lastWeight
        self.onSave = onSave
        self.onDelete = onDelete
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                    .font(.subheadline.weight(.bold))
                ForEach(prLabels, id: \.self) { label in
                    GymInfoPill(label, systemImage: "trophy.fill", accent: GymTheme.tertiary)
                }
                Spacer(minLength: 4)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    gymText(
                        "Delete set \(position + 1)",
                        "Видалити підхід \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { editors }
                VStack(spacing: 10) { editors }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(GymTheme.surfaceVariant.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: set.weight) { newValue in weight = newValue }
        .onChange(of: set.reps) { newValue in reps = newValue }
    }

    @ViewBuilder
    private var editors: some View {
        TextField(
            "Weight",
            value: $weight,
            format: .number.precision(.fractionLength(0 ... 2))
        )
        .keyboardType(.decimalPad)
        .gymTextFieldChrome()
        .accessibilityLabel(
            gymText(
                "Weight for set \(position + 1)",
                "Вага для підходу \(position + 1)",
                languageCode: gymCurrentLanguageCode()
            )
        )

        Stepper(value: $reps, in: 1 ... 10_000) {
            Text(
                gymText(
                    "\(reps) reps",
                    "\(reps) повт.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GymTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            if let lastWeight { weight = lastWeight }
        } label: {
            Label("Last", systemImage: "clock.arrow.circlepath")
        }
        .disabled(lastWeight == nil)

        Button {
            weight += 2.5
        } label: {
            Label("+2.5", systemImage: "plus")
        }

        Button {
            onSave(weight, reps)
        } label: {
            Label("Save set", systemImage: "checkmark")
        }
        .disabled(!weight.isFinite || weight < 0 || reps < 1)
    }
}
