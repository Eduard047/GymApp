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
        localized(languageCode, en: "Set signal", uk: "Сигнал підходу", ru: "Сигнал подхода")
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

    static func insightsTitle(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Session overview",
            uk: "Огляд сесії",
            ru: "Обзор сессии"
        )
    }

    static func insightsSupporting(partial: Bool, languageCode: String) -> String {
        if partial {
            return localized(
                languageCode,
                en: "Calculated only from the set rows retained in this bounded workout note; some rows were omitted.",
                uk: "Розраховано лише за рядками підходів, що збереглися в обмеженій нотатці; частину рядків пропущено.",
                ru: "Рассчитано только по строкам подходов, сохранившимся в ограниченной заметке; часть строк пропущена."
            )
        }
        return localized(
            languageCode,
            en: "A visual summary of set data stored in this Garmin-format workout note.",
            uk: "Візуальний підсумок даних підходів зі збереженої нотатки тренування у форматі Garmin.",
            ru: "Визуальная сводка данных подходов из сохранённой заметки тренировки в формате Garmin."
        )
    }

    static func workoutTimeline(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Set timeline",
            uk: "Хронологія підходів",
            ru: "Хронология подходов"
        )
    }

    static func timelineValue(setCount: Int, duration: Int64, languageCode: String) -> String {
        localized(
            languageCode,
            en: "\(setCount) recorded sets across \(garminDuration(duration))",
            uk: "Записано підходів: \(setCount), тривалість \(garminDuration(duration))",
            ru: "Записано подходов: \(setCount), длительность \(garminDuration(duration))"
        )
    }

    static func recordedWork(languageCode: String) -> String {
        localized(languageCode, en: "Recorded work", uk: "Записана робота", ru: "Записанная работа")
    }

    static func recordedRest(languageCode: String) -> String {
        localized(languageCode, en: "Recorded rest", uk: "Записаний відпочинок", ru: "Записанный отдых")
    }

    static func workDensity(languageCode: String) -> String {
        localized(languageCode, en: "Work density", uk: "Щільність роботи", ru: "Плотность работы")
    }

    static func averageDetection(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Avg set signal",
            uk: "Сер. сигнал підходу",
            ru: "Сред. сигнал подхода"
        )
    }

    static func averageRecovery(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Avg HR recovery",
            uk: "Сер. відновлення пульсу",
            ru: "Сред. восстановление пульса"
        )
    }

    static func dominantZone(languageCode: String) -> String {
        localized(languageCode, en: "Most zone time", uk: "Найбільше часу", ru: "Больше всего времени")
    }

    static func peakSet(setIndex: Int, heartRate: Int, languageCode: String) -> String {
        localized(
            languageCode,
            en: "Highest recorded set peak: S\(setIndex), \(heartRate) bpm.",
            uk: "Найвищий записаний пік підходу: S\(setIndex), \(heartRate) уд/хв.",
            ru: "Самый высокий записанный пик подхода: S\(setIndex), \(heartRate) уд/мин."
        )
    }

    static func longestRest(setIndex: Int, seconds: Int64, languageCode: String) -> String {
        localized(
            languageCode,
            en: "Longest recorded rest was before S\(setIndex): \(garminDuration(seconds)).",
            uk: "Найдовший записаний відпочинок був перед S\(setIndex): \(garminDuration(seconds)).",
            ru: "Самый длинный записанный отдых был перед S\(setIndex): \(garminDuration(seconds))."
        )
    }

    static func lowConfidenceSets(_ indexes: [Int], languageCode: String) -> String {
        let values = indexes.map { "S\($0)" }.joined(separator: ", ")
        return localized(
            languageCode,
            en: "Review set detection for \(values): the sensor signal was below 40%.",
            uk: "Перевір визначення підходів \(values): сигнал сенсорів був нижчим за 40%.",
            ru: "Проверь определение подходов \(values): сигнал датчиков был ниже 40%."
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

    static func timelinePosition(_ seconds: Int64, duration: Int64) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, Double(seconds) / Double(duration)))
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

private struct GarminSessionInsightsCard: View {
    let insights: GarminWorkoutSessionInsights
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(GarminWorkoutDetailCopy.insightsTitle(languageCode: languageCode))
                    .font(.headline)
                    .foregroundStyle(GymTheme.textPrimary)
                Text(
                    GarminWorkoutDetailCopy.insightsSupporting(
                        partial: insights.isPartial,
                        languageCode: languageCode
                    )
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let duration = insights.timelineDurationSeconds,
               !insights.timelineSlices.isEmpty {
                GarminWorkoutTimelineChart(
                    slices: insights.timelineSlices,
                    durationSeconds: duration,
                    languageCode: languageCode
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 8)],
                spacing: 8
            ) {
                if let seconds = insights.recordedActiveSeconds {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.recordedWork(languageCode: languageCode),
                        value: garminDuration(seconds)
                    )
                }
                if let seconds = insights.recordedRestSeconds {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.recordedRest(languageCode: languageCode),
                        value: garminDuration(seconds)
                    )
                }
                if let density = insights.workDensityPercent {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.workDensity(languageCode: languageCode),
                        value: "\(density)%"
                    )
                }
                if let confidence = insights.averageDetectionConfidence {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.averageDetection(languageCode: languageCode),
                        value: "\(confidence)%"
                    )
                }
                if let recovery = insights.averageRecoveryHeartRateDrop {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.averageRecovery(languageCode: languageCode),
                        value: "↓\(recovery)"
                    )
                }
                if let zone = insights.dominantHeartRateZone {
                    GymMetricTile(
                        label: GarminWorkoutDetailCopy.dominantZone(languageCode: languageCode),
                        value: "Z\(zone)"
                    )
                }
            }

            if let zoneSeconds = insights.aggregateHeartRateZoneSeconds {
                GarminHeartRateZoneChart(
                    seconds: zoneSeconds,
                    languageCode: languageCode
                )
            }

            if let setIndex = insights.peakHeartRateSetIndex,
               let heartRate = insights.peakHeartRate {
                insightLine(
                    GarminWorkoutDetailCopy.peakSet(
                        setIndex: setIndex,
                        heartRate: heartRate,
                        languageCode: languageCode
                    ),
                    systemImage: "heart.fill",
                    color: GymTheme.secondary
                )
            }
            if let setIndex = insights.longestRestSetIndex,
               let seconds = insights.longestRestSeconds {
                insightLine(
                    GarminWorkoutDetailCopy.longestRest(
                        setIndex: setIndex,
                        seconds: seconds,
                        languageCode: languageCode
                    ),
                    systemImage: "timer",
                    color: GymTheme.tertiary
                )
            }
            if !insights.lowConfidenceSetIndexes.isEmpty {
                insightLine(
                    GarminWorkoutDetailCopy.lowConfidenceSets(
                        insights.lowConfidenceSetIndexes,
                        languageCode: languageCode
                    ),
                    systemImage: "exclamationmark.triangle.fill",
                    color: GymTheme.error
                )
            }
        }
        .padding(13)
        .background(
            GymTheme.surfaceVariant.opacity(0.62),
            in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
                .strokeBorder(GymTheme.outlineSoft.opacity(0.8), lineWidth: 1)
        }
    }

    private func insightLine(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(GymTheme.textSecondary)
    }
}

private struct GarminWorkoutTimelineChart: View {
    let slices: [GarminWorkoutTimelineSlice]
    let durationSeconds: Int64
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(GarminWorkoutDetailCopy.workoutTimeline(languageCode: languageCode))
                .font(.caption.weight(.bold))
                .foregroundStyle(GymTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.35)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(GymTheme.outlineSoft.opacity(0.72))
                        .frame(height: 16)

                    ForEach(slices) { slice in
                        let start = GarminWorkoutChartModel.timelinePosition(
                            slice.startSeconds,
                            duration: durationSeconds
                        )
                        let end = GarminWorkoutChartModel.timelinePosition(
                            slice.endSeconds,
                            duration: durationSeconds
                        )
                        let x = geometry.size.width * start
                        let width = max(4, geometry.size.width * max(0, end - start))
                        Capsule()
                            .fill(confidenceColor(slice.detectionConfidence))
                            .frame(width: width, height: 22)
                            .overlay {
                                if width >= 28 {
                                    Text("S\(slice.setIndex)")
                                        .font(.caption2.monospacedDigit().weight(.black))
                                        .foregroundStyle(Color.white)
                                }
                            }
                            .offset(x: min(x, max(0, geometry.size.width - width)))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                GarminWorkoutDetailCopy.workoutTimeline(languageCode: languageCode)
            )
            .accessibilityValue(
                GarminWorkoutDetailCopy.timelineValue(
                    setCount: slices.count,
                    duration: durationSeconds,
                    languageCode: languageCode
                )
            )

            HStack {
                Text("0:00")
                Spacer()
                Text(garminDuration(durationSeconds))
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .accessibilityHidden(true)
        }
    }

    private func confidenceColor(_ confidence: Int?) -> Color {
        guard let confidence else { return GymTheme.primary }
        if confidence < 40 { return GymTheme.error }
        if confidence < 70 { return GymTheme.tertiary }
        return GymTheme.secondary
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
                                accent: confidence < 40
                                    ? GymTheme.error
                                    : confidence < 70 ? GymTheme.tertiary : GymTheme.secondary
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

struct StoredWorkoutPRBaseline: Equatable {
    let maxWeight: Double
    let maxEstimatedOneRepMax: Double

    init(
        history: [ExerciseHistoryEntry],
        currentWorkoutDate: Date,
        currentWorkoutID: UUID
    ) {
        let priorHistory = history.filter { entry in
            if entry.sessionDate != currentWorkoutDate {
                return entry.sessionDate < currentWorkoutDate
            }
            return entry.workoutID.uuidString < currentWorkoutID.uuidString
        }
        let eligiblePriorHistory = priorHistory.filter { Self.isEligibleValue($0.weight) }
        maxWeight = eligiblePriorHistory.lazy
            .map(\.weight)
            .max() ?? 0
        maxEstimatedOneRepMax = eligiblePriorHistory.lazy
            .map(\.estimatedOneRepMax)
            .filter(Self.isEligibleValue)
            .max() ?? 0
    }

    func labels(for set: WorkoutSet) -> [String] {
        guard Self.isEligibleValue(set.weight) else { return [] }
        var labels: [String] = []
        if Self.isPersonalRecord(set.weight, baseline: maxWeight) {
            labels.append("Weight PR")
        }
        if Self.isPersonalRecord(set.estimatedOneRepMax, baseline: maxEstimatedOneRepMax) {
            labels.append("Estimated 1RM PR")
        }
        return labels
    }

    func containsPersonalRecord(in block: WorkoutExercise) -> Bool {
        block.sets.contains { !labels(for: $0).isEmpty }
    }

    private static func isEligibleValue(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private static func isPersonalRecord(_ value: Double, baseline: Double) -> Bool {
        isEligibleValue(value) && value > baseline
    }
}

struct StoredWorkoutExerciseSummary: Equatable {
    let setCount: Int
    let repCount: Int
    let volume: Double
    let hasPersonalRecord: Bool

    init(block: WorkoutExercise, personalRecordBaseline: StoredWorkoutPRBaseline) {
        setCount = block.sets.count
        repCount = block.sets.reduce(0) { $0 + $1.reps }
        volume = block.sets.reduce(0) { $0 + $1.volume }
        hasPersonalRecord = personalRecordBaseline.containsPersonalRecord(in: block)
    }
}

enum WorkoutDetailDisclosurePolicy {
    static func toggledExercise(current: UUID?, tapped: UUID) -> UUID? {
        current == tapped ? nil : tapped
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
    @State private var date: Date
    @State private var note: String
    @State private var isEditing = false
    @State private var expandedExerciseID: UUID?
    @State private var showsWatchMetrics = false
    @State private var showingExercisePicker = false
    @State private var activeAlert: ActiveAlert?
    @State private var statusMessage: String?
    @State private var pendingDeletion: WorkoutDetailDeletionTarget?
    @State private var deletionTask: Task<Void, Never>?
    @State private var showingShareChooser = false
    @State private var sharingPlan: SharedWorkoutPlan?
    @State private var shareFriends: [SocialFriendSummary] = []
    @State private var shareFriendsAreLoading = false
    @State private var sharingFriendID: String?
    @State private var shareChooserMessage: String?
    @State private var shareChooserMessageIsError = false

    private let workoutID: UUID
    private let onDeleted: () -> Void
    private let cancelLegacyRestTimer: (String) -> Void
    private let reportStatus: (String, Bool) -> Void
    private let isStoreContextCurrent: () -> Bool
    private let isCloudAccount: Bool
    private let loadSocialDashboard: (() async throws -> SocialDashboard)?
    private let sendSocialWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)?
    private let sendLiveWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)?

    init(
        appState: AppState,
        workoutID: UUID,
        liveWorkoutCoordinator: LiveWorkoutCoordinator? = nil,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.init(
            store: appState.workoutStore,
            workoutID: workoutID,
            onDeleted: onDeleted,
            cancelLegacyRestTimer: { [weak appState] timerID in
                appState?.restTimers.cancel(id: timerID)
            },
            onStatus: { [weak appState] message, isError in
                appState?.show(message: message, isError: isError)
            },
            isStoreContextCurrent: { [weak appState, weak store = appState.workoutStore] in
                guard let appState, let store else { return false }
                return appState.isAccountReady
                    && appState.workoutStore === store
                    && appState.activeAccountStorageKey == store.accountStorageKey
            },
            isCloudAccount: appState.auth.session?.cloud != nil,
            loadSocialDashboard: { try await appState.refreshSocialDashboard() },
            sendSocialWorkoutInvite: { profileID, plan in
                try await appState.sendWorkoutInvite(to: profileID, plan: plan)
            },
            sendLiveWorkoutInvite: liveWorkoutCoordinator.map { coordinator in
                { profileID, plan in
                    try await coordinator.sendInvite(to: profileID, plan: plan)
                }
            }
        )
    }

    init(
        store: WorkoutStore,
        workoutID: UUID,
        onDeleted: @escaping () -> Void = {},
        cancelLegacyRestTimer: @escaping (String) -> Void = { _ in },
        onStatus: @escaping (String, Bool) -> Void = { _, _ in },
        isStoreContextCurrent: @escaping () -> Bool = { true },
        isCloudAccount: Bool = false,
        loadSocialDashboard: (() async throws -> SocialDashboard)? = nil,
        sendSocialWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)? = nil,
        sendLiveWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)? = nil
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.workoutID = workoutID
        self.onDeleted = onDeleted
        self.cancelLegacyRestTimer = cancelLegacyRestTimer
        self.reportStatus = onStatus
        self.isStoreContextCurrent = isStoreContextCurrent
        self.isCloudAccount = isCloudAccount
        self.loadSocialDashboard = loadSocialDashboard
        self.sendSocialWorkoutInvite = sendSocialWorkoutInvite
        self.sendLiveWorkoutInvite = sendLiveWorkoutInvite
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

                        if !isEditing {
                            Button(action: beginEditing) {
                                Label(
                                    gymText(
                                        "Edit workout",
                                        "Редагувати тренування",
                                        "Редактировать тренировку",
                                        languageCode: gymCurrentLanguageCode()
                                    ),
                                    systemImage: "pencil"
                                )
                            }
                            .buttonStyle(GymSecondaryButtonStyle())
                        }

                        if let summary = garminSummary,
                           summary.hasWorkoutMetrics || hasGarminSetDetails(summary) {
                            watchMetricsSection(summary)
                        }

                        if let statusMessage {
                            GymStatusBanner(message: statusMessage, isError: true)
                        }

                        if isEditing {
                            metadataPanel(isGarminWorkout: garminSummary != nil)
                        }
                        exerciseSection(workout)
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button(role: .destructive) {
                        presentWorkoutDeletionConfirmation()
                    } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                    .disabled(pendingDeletion != nil)

                    Button(gymLocalized("Done"), action: finishEditing)
                        .disabled(pendingDeletion != nil)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                exercises: store.exercises,
                selectedExerciseIDs: Set(store.workout(id: workoutID)?.exercises.map(\.exerciseID) ?? []),
                exerciseMediaOwnerKey: store.accountStorageKey,
                muscleMappings: store.muscleMappings,
                sessionCounts: exerciseSessionCounts,
                onSelect: addExercise,
                onCreate: createExerciseForEditing
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingShareChooser) {
            if let sharingPlan {
                SavedWorkoutShareChooser(
                    plan: sharingPlan,
                    friends: shareFriends,
                    isCloudAccount: isCloudAccount,
                    canStartLive: sendLiveWorkoutInvite != nil,
                    isLoadingFriends: shareFriendsAreLoading,
                    sharingFriendID: sharingFriendID,
                    message: shareChooserMessage,
                    messageIsError: shareChooserMessageIsError,
                    onRefresh: { Task { await loadShareFriends(force: true) } },
                    onSendCopy: { friend in
                        Task { await sendWorkoutInvite(to: friend, live: false) }
                    },
                    onStartLive: { friend in
                        Task { await sendWorkoutInvite(to: friend, live: true) }
                    }
                )
                .presentationDetents([.medium, .large])
            }
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

                if sharedWorkoutURL(workout) != nil {
                    Button {
                        openWorkoutShareChooser(workout)
                    } label: {
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

    private func sharedWorkoutPlan(_ workout: WorkoutSession) throws -> SharedWorkoutPlan {
        var exercisesByID: [UUID: Exercise] = [:]
        for exercise in store.exercises {
            exercisesByID[exercise.id] = exercise
        }
        return try SharedWorkoutLinkEncoder.makePlan(
            workout: workout,
            exercises: exercisesByID
        )
    }

    private func openWorkoutShareChooser(_ workout: WorkoutSession) {
        guard isStoreContextCurrent() else { return }
        do {
            sharingPlan = try sharedWorkoutPlan(workout)
            shareChooserMessage = nil
            shareChooserMessageIsError = false
            showingShareChooser = true
            Task { await loadShareFriends(force: false) }
        } catch {
            reportStatus(
                gymText(
                    "This saved workout cannot be shared safely.",
                    "Цим збереженим тренуванням неможливо безпечно поділитися.",
                    "Этой сохранённой тренировкой нельзя безопасно поделиться.",
                    languageCode: gymCurrentLanguageCode()
                ),
                true
            )
        }
    }

    private func loadShareFriends(force: Bool) async {
        guard isStoreContextCurrent() else { return }
        guard isCloudAccount, let loadSocialDashboard else {
            shareFriends = []
            return
        }
        guard !shareFriendsAreLoading, force || shareFriends.isEmpty else { return }
        shareFriendsAreLoading = true
        if force {
            shareChooserMessage = nil
            shareChooserMessageIsError = false
        }
        defer { shareFriendsAreLoading = false }
        do {
            let dashboard = try await loadSocialDashboard()
            guard !Task.isCancelled, isStoreContextCurrent() else { return }
            shareFriends = dashboard.friends.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        } catch {
            guard !Task.isCancelled, isStoreContextCurrent() else { return }
            shareFriends = []
            shareChooserMessage = gymText(
                "Friends could not be loaded safely. You can still share a link.",
                "Не вдалося безпечно завантажити друзів. Посиланням усе ще можна поділитися.",
                "Не удалось безопасно загрузить друзей. Ссылкой всё ещё можно поделиться.",
                languageCode: gymCurrentLanguageCode()
            )
            shareChooserMessageIsError = true
        }
    }

    private func sendWorkoutInvite(to friend: SocialFriendSummary, live: Bool) async {
        guard isStoreContextCurrent(),
              sharingFriendID == nil,
              let plan = sharingPlan,
              let sender = live ? sendLiveWorkoutInvite : sendSocialWorkoutInvite else { return }
        sharingFriendID = friend.profileID
        shareChooserMessage = nil
        shareChooserMessageIsError = false
        defer { sharingFriendID = nil }
        do {
            try await sender(friend.profileID, plan)
            guard !Task.isCancelled, isStoreContextCurrent() else { return }
            shareChooserMessage = live
                ? gymText(
                    "Live invitation sent. Your friend joins before the workout starts for both of you.",
                    "Live-запрошення надіслано. Друг приєднається до старту тренування для вас обох.",
                    "Live-приглашение отправлено. Друг присоединится до старта тренировки для вас обоих.",
                    languageCode: gymCurrentLanguageCode()
                )
                : gymText(
                    "Workout copy sent inside GymApp.",
                    "Копію тренування надіслано в GymApp.",
                    "Копия тренировки отправлена в GymApp.",
                    languageCode: gymCurrentLanguageCode()
                )
        } catch {
            guard !Task.isCancelled, isStoreContextCurrent() else { return }
            shareChooserMessage = gymText(
                "The invitation could not be submitted safely. Refresh friends and try again.",
                "Не вдалося безпечно надіслати запрошення. Онови друзів і спробуй ще раз.",
                "Не удалось безопасно отправить приглашение. Обнови друзей и попробуй ещё раз.",
                languageCode: gymCurrentLanguageCode()
            )
            shareChooserMessageIsError = true
        }
    }

    private var exerciseSessionCounts: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: store.exercises.map { exercise in
                (exercise.id, store.progressStats(exerciseID: exercise.id).sessionCount)
            }
        )
    }

    private func hasGarminSetDetails(_ summary: GarminWorkoutNoteSummary) -> Bool {
        !summary.visualSetIndexes.isEmpty || summary.omittedMetricRows != nil ||
            (summary.completedSetCount != nil &&
                (summary.plannedSetCount ?? 0) > (summary.completedSetCount ?? Int.max))
    }

    private func watchMetricsSection(_ summary: GarminWorkoutNoteSummary) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: showsWatchMetrics ? 12 : 0) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        showsWatchMetrics.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(GymTheme.primary)
                            .frame(width: 34, height: 34)
                            .background(GymTheme.primary.opacity(0.1), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gymText(
                                "Watch metrics",
                                "Показники годинника",
                                "Показатели часов",
                                languageCode: gymCurrentLanguageCode()
                            ))
                            .font(.headline)
                            .foregroundStyle(GymTheme.textPrimary)
                            Text(gymText(
                                "Heart rate, timing and set insights",
                                "Пульс, час та аналітика підходів",
                                "Пульс, время и аналитика подходов",
                                languageCode: gymCurrentLanguageCode()
                            ))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: showsWatchMetrics ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(gymText(
                    showsWatchMetrics ? "Expanded" : "Collapsed",
                    showsWatchMetrics ? "Розгорнуто" : "Згорнуто",
                    showsWatchMetrics ? "Развернуто" : "Свернуто",
                    languageCode: gymCurrentLanguageCode()
                ))

                if showsWatchMetrics {
                    Divider()
                    if summary.hasWorkoutMetrics {
                        garminMetricsPanel(summary)
                    }
                    if hasGarminSetDetails(summary) {
                        garminSetIntervalsPanel(summary)
                    }
                }
            }
        }
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
        let insights = GarminWorkoutSessionInsights.make(from: summary)
        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Garmin",
                    title: GarminWorkoutDetailCopy.intervalsTitle(languageCode: languageCode),
                    supporting: GarminWorkoutDetailCopy.intervalsSupporting(
                        languageCode: languageCode
                    )
                )
                if let insights {
                    GarminSessionInsightsCard(
                        insights: insights,
                        languageCode: languageCode
                    )
                }
                if let completedSetCount = summary.completedSetCount,
                   let plannedSetCount = summary.plannedSetCount,
                   plannedSetCount > completedSetCount {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(
                            GarminWorkoutDetailCopy.originalPartial(
                                completed: completedSetCount,
                                planned: plannedSetCount,
                                languageCode: languageCode
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        ProgressView(
                            value: Double(completedSetCount),
                            total: Double(plannedSetCount)
                        )
                        .tint(GymTheme.primary)
                        .accessibilityValue("\(completedSetCount) / \(plannedSetCount)")
                    }
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
                        : gymText(
                            "Update the saved workout details.",
                            "Онови дані збереженого тренування.",
                            "Обновите данные сохранённой тренировки.",
                            languageCode: gymCurrentLanguageCode()
                        )
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
                eyebrow: isEditing
                    ? gymText(
                        "Edit",
                        "Редагування",
                        "Редактирование",
                        languageCode: gymCurrentLanguageCode()
                    )
                    : gymLocalized("Saved workout"),
                title: "Exercises and sets",
                supporting: isEditing
                    ? gymText(
                        "Open an exercise to update its saved sets.",
                        "Відкрий вправу, щоб змінити збережені підходи.",
                        "Откройте упражнение, чтобы изменить сохранённые подходы.",
                        languageCode: gymCurrentLanguageCode()
                    )
                    : gymText(
                        "Exercises are collapsed by default. Open one to review its sets.",
                        "Вправи спочатку згорнуті. Відкрий вправу, щоб переглянути підходи.",
                        "Упражнения изначально свёрнуты. Откройте упражнение, чтобы посмотреть подходы.",
                        languageCode: gymCurrentLanguageCode()
                    )
            )
            Spacer(minLength: 8)
            if isEditing {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add exercise to workout")
            }
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
        let personalRecordBaseline = StoredWorkoutPRBaseline(
            history: store.exerciseHistory(exerciseID: block.exerciseID),
            currentWorkoutDate: workout.date,
            currentWorkoutID: workout.id
        )
        let summary = StoredWorkoutExerciseSummary(
            block: block,
            personalRecordBaseline: personalRecordBaseline
        )
        let isExpanded = expandedExerciseID == block.id

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
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            expandedExerciseID = WorkoutDetailDisclosurePolicy.toggledExercise(
                                current: expandedExerciseID,
                                tapped: block.id
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(name)
                                    .font(.headline)
                                    .foregroundStyle(GymTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(exerciseSummaryText(summary))
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if summary.hasPersonalRecord {
                                    GymInfoPill(
                                        gymText(
                                            "Personal record",
                                            "Особистий рекорд",
                                            "Личный рекорд",
                                            languageCode: gymCurrentLanguageCode()
                                        ),
                                        systemImage: "trophy.fill",
                                        accent: GymTheme.tertiary
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(name), \(exerciseSummaryText(summary))"
                    )
                    .accessibilityHint(gymText(
                        isExpanded ? "Collapses sets" : "Expands sets",
                        isExpanded ? "Згортає підходи" : "Розгортає підходи",
                        isExpanded ? "Сворачивает подходы" : "Разворачивает подходы",
                        languageCode: gymCurrentLanguageCode()
                    ))

                    if isEditing {
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
                                "Удалить «\(name)» из тренировки",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .disabled(pendingDeletion != nil)
                    }
                }

                if isExpanded {
                    Divider()

                    ForEach(Array(visibleSets(block).enumerated()), id: \.element.id) { index, set in
                        if isEditing {
                            StoredWorkoutSetEditorRow(
                                set: set,
                                position: index,
                                prLabels: personalRecordBaseline.labels(for: set),
                                lastWeight: store.lastWeight(exerciseID: block.exerciseID, before: workout.date),
                                onSave: { weight, reps in
                                    guard isEditing, isStoreContextCurrent() else {
                                        showStaleDeletion()
                                        return
                                    }
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
                        } else {
                            StoredWorkoutSetSummaryRow(
                                set: set,
                                position: index,
                                prLabels: personalRecordBaseline.labels(for: set)
                            )
                        }
                    }

                    if isEditing {
                        Button {
                            addSet(to: block, workout: workout)
                        } label: {
                            Label(
                                gymText(
                                    "Add set",
                                    "Додати підхід",
                                    "Добавить подход",
                                    languageCode: gymCurrentLanguageCode()
                                ),
                                systemImage: "plus.circle.fill"
                            )
                        }
                        .buttonStyle(GymSecondaryButtonStyle())
                        .accessibilityHint(gymText(
                            "Adds a set to this saved workout",
                            "Додає підхід до цього збереженого тренування",
                            "Добавляет подход в эту сохранённую тренировку",
                            languageCode: gymCurrentLanguageCode()
                        ))
                    }
                }
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

    private func exerciseSummaryText(_ summary: StoredWorkoutExerciseSummary) -> String {
        let sets = gymCount(
            summary.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів",
            languageCode: gymCurrentLanguageCode()
        )
        let reps = gymCount(
            summary.repCount,
            englishOne: "rep",
            englishMany: "reps",
            ukrainianOne: "повтор",
            ukrainianFew: "повтори",
            ukrainianMany: "повторів",
            languageCode: gymCurrentLanguageCode()
        )
        let volume = summary.volume.formatted(
            .number
                .locale(AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
        return gymText(
            "\(sets) · \(reps) · \(volume) volume",
            "\(sets) · \(reps) · обсяг \(volume)",
            "\(sets) · \(reps) · объём \(volume)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func beginEditing() {
        guard isStoreContextCurrent(), let workout = store.workout(id: workoutID) else {
            showStaleDeletion()
            return
        }
        date = workout.date
        note = workout.note ?? ""
        isEditing = true
    }

    private func finishEditing() {
        if commitPendingDeletion() { return }
        guard isStoreContextCurrent(), store.workout(id: workoutID) != nil else {
            showStaleDeletion()
            return
        }
        do {
            try store.updateWorkout(id: workoutID, date: date, note: note)
            statusMessage = nil
            reportStatus("Workout details updated.", false)
            showingExercisePicker = false
            isEditing = false
        } catch {
            show(error)
        }
    }

    private func addExercise(_ exercise: Exercise) {
        guard isEditing, isStoreContextCurrent() else {
            showStaleDeletion()
            return
        }
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
        workout: WorkoutSession
    ) {
        guard isEditing, isStoreContextCurrent() else {
            showStaleDeletion()
            return
        }
        let source = block.sets.last
        do {
            _ = try store.addSet(
                workoutID: workout.id,
                workoutExerciseID: block.id,
                weight: source?.weight ?? store.lastWeight(exerciseID: block.exerciseID) ?? 0,
                reps: source?.reps ?? 10
            )
        } catch {
            show(error)
        }
    }

    private func createExerciseForEditing(_ name: String) throws -> Exercise {
        guard isEditing, isStoreContextCurrent() else {
            throw WorkoutStoreError.invalidWorkout("The workout changed. Reopen it and try again.")
        }
        return try store.addExercise(name: name)
    }

    private func saveMetadata() {
        guard isEditing, isStoreContextCurrent() else {
            showStaleDeletion()
            return
        }
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
        guard isEditing,
              pendingDeletion == nil,
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
        guard isEditing,
              pendingDeletion == nil,
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
            timerIDs.forEach(cancelLegacyRestTimer)
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
                    cancelLegacyRestTimer(timerKey(blockID: block.id))
                }
            case let .exercise(_, block, _):
                try store.removeExercise(fromWorkout: workoutID, workoutExerciseID: block.id)
                cancelLegacyRestTimer(timerKey(blockID: block.id))
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

private struct SavedWorkoutShareChooser: View {
    let plan: SharedWorkoutPlan
    let friends: [SocialFriendSummary]
    let isCloudAccount: Bool
    let canStartLive: Bool
    let isLoadingFriends: Bool
    let sharingFriendID: String?
    let message: String?
    let messageIsError: Bool
    let onRefresh: () -> Void
    let onSendCopy: (SocialFriendSummary) -> Void
    let onStartLive: (SocialFriendSummary) -> Void

    private var shareURL: URL? {
        try? SharedWorkoutLinkEncoder.makeURL(plan: plan)
    }

    var body: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        GymHeroPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    t("Share saved workout", "Поділитися збереженим тренуванням", "Поделиться сохранённой тренировкой"),
                                    systemImage: "person.2.wave.2.fill"
                                )
                                .font(.title2.bold())
                                Text(
                                    t(
                                        "Send a copy, start one synchronized room, or use any other app.",
                                        "Надішли копію, запусти одну синхронізовану кімнату або скористайся іншим застосунком.",
                                        "Отправь копию, запусти одну синхронизированную комнату или используй другое приложение."
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.84))
                            }
                        }

                        if let message {
                            GymStatusBanner(message: message, isError: messageIsError)
                        }

                        if let shareURL {
                            GymPanel(highlighted: true) {
                                VStack(alignment: .leading, spacing: 10) {
                                    GymSectionTitle(
                                        eyebrow: t("Link", "Посилання", "Ссылка"),
                                        title: t("Share through another app", "Надіслати через інший застосунок", "Отправить через другое приложение")
                                    )
                                    ShareLink(
                                        item: shareURL,
                                        subject: Text("GymApp workout"),
                                        message: Text(
                                            GarminWorkoutDetailCopy.shareMessage(
                                                languageCode: gymCurrentLanguageCode()
                                            )
                                        )
                                    ) {
                                        Label(
                                            t("Share link", "Поділитися посиланням", "Поделиться ссылкой"),
                                            systemImage: "link"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(GymSecondaryButtonStyle())
                                }
                            }
                        }

                        GymPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    GymSectionTitle(
                                        eyebrow: t("Friends", "Друзі", "Друзья"),
                                        title: t("Train together", "Тренуватися разом", "Тренироваться вместе")
                                    )
                                    Spacer()
                                    Button(action: onRefresh) {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoadingFriends)
                                    .accessibilityLabel(t("Refresh friends", "Оновити друзів", "Обновить друзей"))
                                }

                                if !isCloudAccount {
                                    Text(t(
                                        "Sign in to send a private workout invitation.",
                                        "Увійди, щоб надіслати приватне запрошення на тренування.",
                                        "Войди, чтобы отправить личное приглашение на тренировку."
                                    ))
                                    .foregroundStyle(GymTheme.textSecondary)
                                } else if isLoadingFriends && friends.isEmpty {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else if friends.isEmpty {
                                    Text(t(
                                        "Add and confirm a friend first.",
                                        "Спочатку додай і підтвердь друга.",
                                        "Сначала добавь и подтверди друга."
                                    ))
                                    .foregroundStyle(GymTheme.textSecondary)
                                } else {
                                    ForEach(friends, id: \.profileID) { friend in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(friend.displayName)
                                                .font(.headline)
                                                .lineLimit(1)
                                            ViewThatFits(in: .horizontal) {
                                                HStack(spacing: 8) {
                                                    friendShareButtons(friend)
                                                }
                                                VStack(spacing: 8) {
                                                    friendShareButtons(friend)
                                                }
                                            }
                                            .disabled(sharingFriendID != nil)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        Text(t(
                            "Only exercises and planned sets are shared. Notes, dates, account data, and health metrics stay private.",
                            "Передаються лише вправи й заплановані підходи. Нотатки, дати, дані акаунта й показники здоров’я залишаються приватними.",
                            "Передаются только упражнения и запланированные подходы. Заметки, даты, данные аккаунта и показатели здоровья остаются приватными."
                        ))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    }
                    .padding(14)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(t("Share workout", "Поділитися", "Поделиться"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func friendShareButtons(_ friend: SocialFriendSummary) -> some View {
        Button {
            onSendCopy(friend)
        } label: {
            Label(
                t("Send copy", "Надіслати копію", "Отправить копию"),
                systemImage: "doc.on.doc"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())

        Button {
            onStartLive(friend)
        } label: {
            Label("LIVE", systemImage: "figure.strengthtraining.traditional")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .disabled(!canStartLive)
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: gymCurrentLanguageCode())
    }
}

private struct StoredWorkoutSetSummaryRow: View {
    let set: WorkoutSet
    let position: Int
    let prLabels: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                setLabel
                Spacer(minLength: 6)
                valueLabel
                prPills
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    setLabel
                    Spacer(minLength: 6)
                    prPills
                }
                valueLabel
            }
        }
        .padding(12)
        .background(GymTheme.surfaceVariant.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var setLabel: some View {
        Text(gymText(
            "Set \(position + 1)",
            "Підхід \(position + 1)",
            "Подход \(position + 1)",
            languageCode: gymCurrentLanguageCode()
        ))
        .font(.subheadline.weight(.bold))
        .foregroundStyle(GymTheme.textPrimary)
    }

    private var valueLabel: some View {
        Text(
            "\(set.weight.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × " +
                gymText(
                    "\(set.reps) reps",
                    "\(set.reps) повт.",
                    "\(set.reps) повт.",
                    languageCode: gymCurrentLanguageCode()
                )
        )
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(GymTheme.textSecondary)
    }

    private var prPills: some View {
        HStack(spacing: 5) {
            ForEach(prLabels, id: \.self) { label in
                GymInfoPill(label, systemImage: "trophy.fill", accent: GymTheme.tertiary)
            }
        }
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
                        "Подход \(position + 1)",
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
                        "Удалить подход \(position + 1)",
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
                "Вес для подхода \(position + 1)",
                languageCode: gymCurrentLanguageCode()
            )
        )

        Stepper(value: $reps, in: 1 ... 10_000) {
            Text(
                gymText(
                    "\(reps) reps",
                    "\(reps) повт.",
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
