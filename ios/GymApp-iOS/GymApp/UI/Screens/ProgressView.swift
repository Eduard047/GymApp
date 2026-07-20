import Charts
import SwiftUI

@MainActor
struct ExerciseProgressView: View {
    private enum ActiveAlert: Identifiable {
        case delete(ExerciseHistoryEntry)
        case error(String)

        var id: String {
            switch self {
            case let .delete(entry): "delete-\(entry.setID.uuidString)"
            case let .error(message): "error-\(message)"
            }
        }
    }

    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue
    @Environment(\.calendar) private var calendar
    @ObservedObject private var store: WorkoutStore

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var selectedExerciseID: UUID?
    @State private var activeAlert: ActiveAlert?

    init(store: WorkoutStore) {
        self.store = store
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 12) {
                    WorkoutMonthSwitcher(
                        month: selectedMonth,
                        isCurrentMonth: monthOffset == 0,
                        onPrevious: { monthOffset -= 1 },
                        onCurrent: { monthOffset = 0 },
                        onNext: { monthOffset = min(0, monthOffset + 1) }
                    )

                    exerciseSelector

                    if let selectedExercise {
                        muscleBreakdown(for: selectedExercise)
                        summaryCard
                        spotlightCard(for: selectedExercise)
                        ExerciseProgressChartsCard(
                            points: visibleChartPoints,
                            languageCode: languageCode,
                            locale: appLocale
                        )
                        historySection
                    } else {
                        noExerciseState
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(t("Progress", "Прогрес"))
        .environment(\.locale, appLocale)
        .onAppear(perform: selectDefaultExerciseIfNeeded)
        .onChange(of: store.exercises) { _, _ in selectDefaultExerciseIfNeeded() }
        .alert(item: $activeAlert, content: makeAlert)
    }

    private var exerciseSelector: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(t("Exercise", "Вправа"), systemImage: "dumbbell.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if sortedExercises.isEmpty {
                    Text(t("Add an exercise and log a workout to see progress.", "Додай вправу й запиши тренування, щоб побачити прогрес."))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                } else {
                    Picker(t("Exercise", "Вправа"), selection: $selectedExerciseID) {
                        ForEach(sortedExercises) { exercise in
                            Text(gymExerciseName(exercise)).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        GymTheme.surfaceVariant.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                            .strokeBorder(GymTheme.outline.opacity(0.45), lineWidth: 1)
                    }
                    .accessibilityHint(t("Selects which exercise to analyze", "Обирає вправу для аналізу"))
                }
            }
        }
    }

    private func muscleBreakdown(for exercise: Exercise) -> some View {
        let contributions = muscleContributions(for: exercise)
        return GymPanel(highlighted: !contributions.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Muscle Breakdown", "Розподіл по м’язах"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(gymExerciseName(exercise))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    GymInfoPill(
                        gymCount(
                            contributions.count,
                            englishOne: "group",
                            englishMany: "groups",
                            ukrainianOne: "група",
                            ukrainianFew: "групи",
                            ukrainianMany: "груп",
                            languageCode: languageCode
                        ),
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }

                if contributions.isEmpty {
                    Text(t("No muscle mapping is available for this exercise yet.", "Для цієї вправи ще немає мапи м’язів."))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                } else {
                    ForEach(contributions) { contribution in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(contribution.label)
                                    .font(.subheadline.weight(.medium))
                                Spacer(minLength: 8)
                                Text(contribution.weight, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                            SwiftUI.ProgressView(value: contribution.weight, total: 1)
                                .tint(contribution.weight >= 0.75 ? GymTheme.tertiary : GymTheme.primary)
                                .accessibilityLabel(contribution.label)
                                .accessibilityValue(
                                    contribution.weight.formatted(.percent.precision(.fractionLength(0)))
                                )
                        }
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Progress Summary", "Зведення прогресу"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(t("Volume = weight × reps across all completed sets.", "Обсяг = вага × повтори в усіх виконаних підходах."))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(
                        label: t("Sessions", "Сесії"),
                        value: progressPoints.count.formatted()
                    )
                    GymMetricTile(
                        label: t("Total Sets", "Підходи"),
                        value: monthHistory.count.formatted()
                    )
                    GymMetricTile(
                        label: t("Total Reps", "Повторів"),
                        value: totalReps.formatted()
                    )
                    GymMetricTile(
                        label: t("Best Weight", "Найкраща вага"),
                        value: bestWeight.map(formatWeight) ?? "—",
                        emphasized: true
                    )
                    GymMetricTile(
                        label: t("Average Max", "Середній максимум"),
                        value: averageMaximumWeight.map(formatWeight) ?? "—"
                    )
                    GymMetricTile(
                        label: t("Total Volume", "Загальний обсяг"),
                        value: formatNumber(totalVolume)
                    )
                }
            }
        }
    }

    private func spotlightCard(for exercise: Exercise) -> some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(gymExerciseName(exercise))
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(spotlightSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.86))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(
                        label: t("Month best", "Найкраще за місяць"),
                        value: bestWeight.map(formatWeight) ?? "—",
                        emphasized: true,
                        onHero: true
                    )
                    GymMetricTile(
                        label: t("Month volume", "Обсяг за місяць"),
                        value: formatNumber(totalVolume),
                        onHero: true
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    spotlightPill(weightDeltaLabel)
                    spotlightPill(volumeDeltaLabel)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(
                        label: t("All-time PR", "Особистий рекорд"),
                        value: allTimeBestWeight.map { "PR \(formatWeight($0))" } ?? "PR —",
                        onHero: true
                    )
                    GymMetricTile(
                        label: t("Consistency", "Регулярність"),
                        value: t("\(progressPoints.count) this month", "\(progressPoints.count) цього місяця"),
                        onHero: true
                    )
                }
            }
        }
    }

    private func spotlightPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var historySection: some View {
        if historyGroups.isEmpty {
            GymPanel {
                ContentUnavailableView {
                    Label(t("No progress this month", "Немає прогресу за цей місяць"), systemImage: "chart.xyaxis.line")
                } description: {
                    Text(t("Log sets for the selected exercise to unlock trends.", "Додай підходи для вибраної вправи, щоб відкрити тренди."))
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            GymSectionTitle(
                eyebrow: t("Recent sessions", "Останні сесії"),
                title: t("Workout History", "Історія тренувань"),
                supporting: t("This list changes with the selected month and exercise.", "Список оновлюється для вибраного місяця і вправи.")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            ForEach(historyGroups) { group in
                historyCard(group)
            }
        }
    }

    private func historyCard(_ group: ExerciseHistoryGroup) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.date.formatted(.dateTime.day().month(.wide).year().locale(appLocale)))
                        .font(.headline)
                    Spacer(minLength: 8)
                    GymInfoPill(
                        t("\(group.entries.count) sets", "\(group.entries.count) підх."),
                        systemImage: "list.number"
                    )
                }

                Text(
                    t(
                        "\(group.totalReps) reps • \(formatNumber(group.totalVolume)) volume",
                        "\(group.totalReps) повт. • обсяг \(formatNumber(group.totalVolume))"
                    )
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)

                Divider()

                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    setRow(entry, index: index)
                    if index < group.entries.count - 1 {
                        Divider().opacity(0.55)
                    }
                }
            }
        }
    }

    private func setRow(_ entry: ExerciseHistoryEntry, index: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(t("Set \(index + 1)", "Підхід \(index + 1)"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(formatWeight(entry.weight))
                Text(t("\(entry.reps) reps", "\(entry.reps) повт."))
                deleteSetButton(entry)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(t("Set \(index + 1)", "Підхід \(index + 1)"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    deleteSetButton(entry)
                }
                Text("\(formatWeight(entry.weight)) • \(t("\(entry.reps) reps", "\(entry.reps) повт."))")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(GymTheme.textPrimary)
        .accessibilityElement(children: .contain)
    }

    private func deleteSetButton(_ entry: ExerciseHistoryEntry) -> some View {
        Button(role: .destructive) {
            activeAlert = .delete(entry)
        } label: {
            Image(systemName: "trash")
                .frame(width: 36, height: 36)
                .background(GymTheme.error.opacity(0.1), in: Circle())
        }
        .foregroundStyle(GymTheme.error)
        .accessibilityLabel(t("Delete set", "Видалити підхід"))
        .accessibilityValue(
            "\(formatWeight(entry.weight)), \(t("\(entry.reps) reps", "\(entry.reps) повторів"))"
        )
    }

    private var noExerciseState: some View {
        GymPanel {
            ContentUnavailableView {
                Label(t("No exercises yet", "Ще немає вправ"), systemImage: "dumbbell")
            } description: {
                Text(t("Create an exercise and log a workout first.", "Спочатку створи вправу й запиши тренування."))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var appLocale: Locale {
        AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    }

    private var sortedExercises: [Exercise] {
        store.exercises.sorted {
            gymExerciseName($0).localizedCaseInsensitiveCompare(gymExerciseName($1)) == .orderedAscending
        }
    }

    private var selectedExercise: Exercise? {
        selectedExerciseID.flatMap(store.exercise(id:))
    }

    private var selectedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: referenceDate) ?? referenceDate
    }

    private var selectedMonthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedMonth) ??
            DateInterval(start: calendar.startOfDay(for: selectedMonth), duration: 1)
    }

    private var previousMonthInterval: DateInterval {
        let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return calendar.dateInterval(of: .month, for: previous) ??
            DateInterval(start: calendar.startOfDay(for: previous), duration: 1)
    }

    private var fullHistory: [ExerciseHistoryEntry] {
        guard let selectedExerciseID else { return [] }
        return store.exerciseHistory(exerciseID: selectedExerciseID)
    }

    private var monthHistory: [ExerciseHistoryEntry] {
        fullHistory.filter { selectedMonthInterval.contains($0.sessionDate) }
    }

    private var previousMonthHistory: [ExerciseHistoryEntry] {
        fullHistory.filter { previousMonthInterval.contains($0.sessionDate) }
    }

    private var progressPoints: [ExerciseProgressPoint] {
        ExerciseProgressPoint.make(from: monthHistory)
    }

    private var previousMonthPoints: [ExerciseProgressPoint] {
        ExerciseProgressPoint.make(from: previousMonthHistory)
    }

    private var visibleChartPoints: [ExerciseProgressPoint] {
        Array(progressPoints.suffix(8))
    }

    private var historyGroups: [ExerciseHistoryGroup] {
        Dictionary(grouping: monthHistory, by: \.workoutID)
            .values
            .compactMap(ExerciseHistoryGroup.init)
            .sorted { $0.date > $1.date }
    }

    private var totalReps: Int {
        monthHistory.reduce(0) { $0 + $1.reps }
    }

    private var totalVolume: Double {
        monthHistory.reduce(0) { $0 + $1.volume }
    }

    private var bestWeight: Double? {
        progressPoints.map(\.maxWeight).max()
    }

    private var averageMaximumWeight: Double? {
        guard !progressPoints.isEmpty else { return nil }
        return progressPoints.reduce(0) { $0 + $1.maxWeight } / Double(progressPoints.count)
    }

    private var allTimeBestWeight: Double? {
        fullHistory.map(\.weight).max()
    }

    private var spotlightSubtitle: String {
        t(
            "\(progressPoints.count) \(progressPoints.count == 1 ? "session" : "sessions") in the selected month.",
            "\(progressPoints.count) сес. у вибраному місяці."
        )
    }

    private var weightDeltaLabel: String {
        deltaLabel(
            current: bestWeight,
            previous: previousMonthPoints.map(\.maxWeight).max(),
            unit: t("kg", "кг"),
            metric: t("best weight", "найкраща вага")
        )
    }

    private var volumeDeltaLabel: String {
        let previousVolume = previousMonthHistory.reduce(0) { $0 + $1.volume }
        return deltaLabel(
            current: monthHistory.isEmpty ? nil : totalVolume,
            previous: previousMonthHistory.isEmpty ? nil : previousVolume,
            unit: t("volume", "обсягу"),
            metric: t("volume", "обсяг")
        )
    }

    private func muscleContributions(for exercise: Exercise) -> [ExerciseMuscleContribution] {
        let manual = MuscleMappingEngine.manualContributionMap(from: store.muscleMappings)
        let labelByID = Dictionary(
            uniqueKeysWithValues: MuscleMappingEngine.muscleDefinitions.map { definition in
                (
                    definition.id,
                    gymText(definition.titleEn, definition.titleUk, languageCode: languageCode)
                )
            }
        )
        return MuscleMappingEngine.contributions(for: exercise.name, manualMappings: manual)
            .map {
                ExerciseMuscleContribution(
                    id: $0.muscleID,
                    label: labelByID[$0.muscleID] ?? $0.muscleID,
                    weight: $0.weight
                )
            }
            .sorted { $0.weight > $1.weight }
    }

    private func deltaLabel(
        current: Double?,
        previous: Double?,
        unit: String,
        metric: String
    ) -> String {
        guard let current else {
            return t("No \(metric) in this month", "Немає показника «\(metric)» цього місяця")
        }
        guard let previous else {
            return t("First month for \(metric)", "Перший місяць для «\(metric)»")
        }
        let delta = current - previous
        if abs(delta) < 0.05 {
            return t("No change vs prior month", "Без змін до попереднього місяця")
        }
        let prefix = delta > 0 ? "+" : "−"
        return t(
            "\(prefix)\(formatNumber(abs(delta))) \(unit) vs prior month",
            "\(prefix)\(formatNumber(abs(delta))) \(unit) до попереднього місяця"
        )
    }

    private func selectDefaultExerciseIfNeeded() {
        guard !store.exercises.isEmpty else {
            selectedExerciseID = nil
            return
        }
        if let selectedExerciseID,
           store.exercises.contains(where: { $0.id == selectedExerciseID }) {
            return
        }
        selectedExerciseID = sortedExercises.first?.id
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .delete(entry):
            return Alert(
                title: Text(t("Delete this set?", "Видалити цей підхід?")),
                message: Text(
                    t(
                        "\(formatWeight(entry.weight)) × \(entry.reps) reps will be removed. If it is the final set, its exercise or workout will also be removed.",
                        "\(formatWeight(entry.weight)) × \(entry.reps) повт. буде видалено. Якщо це останній підхід, вправу або тренування також буде видалено."
                    )
                ),
                primaryButton: .destructive(Text(t("Delete", "Видалити"))) {
                    deleteSet(entry)
                },
                secondaryButton: .cancel(Text(t("Cancel", "Скасувати")))
            )
        case let .error(message):
            return Alert(
                title: Text(t("Couldn’t delete set", "Не вдалося видалити підхід")),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func deleteSet(_ entry: ExerciseHistoryEntry) {
        do {
            guard let workout = store.workout(id: entry.workoutID),
                  let block = workout.exercises.first(where: { exercise in
                      exercise.sets.contains { $0.id == entry.setID }
                  }) else {
                throw WorkoutStoreError.setNotFound
            }
            try store.deleteSet(
                workoutID: entry.workoutID,
                workoutExerciseID: block.id,
                setID: entry.setID
            )
        } catch {
            activeAlert = .error(gymErrorMessage(error, languageCode: languageCode))
        }
    }

    private func formatWeight(_ value: Double) -> String {
        "\(formatDecimal(value, maximumFractionDigits: 1)) \(t("kg", "кг"))"
    }

    private func formatNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(appLocale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func formatDecimal(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .locale(appLocale)
                .precision(.fractionLength(0 ... maximumFractionDigits))
        )
    }

    private func t(_ english: String, _ ukrainian: String) -> String {
        gymText(english, ukrainian, languageCode: languageCode)
    }
}

private struct ExerciseMuscleContribution: Identifiable, Hashable {
    let id: String
    let label: String
    let weight: Double
}

private struct ExerciseProgressPoint: Identifiable, Hashable {
    var id: UUID { workoutID }

    let workoutID: UUID
    let date: Date
    let maxWeight: Double
    let totalVolume: Double
    let totalReps: Int

    static func make(from history: [ExerciseHistoryEntry]) -> [ExerciseProgressPoint] {
        Dictionary(grouping: history, by: \.workoutID)
            .values
            .compactMap { entries in
                guard let first = entries.first else { return nil }
                return ExerciseProgressPoint(
                    workoutID: first.workoutID,
                    date: first.sessionDate,
                    maxWeight: entries.map(\.weight).max() ?? 0,
                    totalVolume: entries.reduce(0) { $0 + $1.volume },
                    totalReps: entries.reduce(0) { $0 + $1.reps }
                )
            }
            .sorted { $0.date < $1.date }
    }
}

private struct ExerciseHistoryGroup: Identifiable {
    var id: UUID { workoutID }

    let workoutID: UUID
    let date: Date
    let entries: [ExerciseHistoryEntry]

    init?(_ entries: [ExerciseHistoryEntry]) {
        guard let first = entries.first else { return nil }
        self.workoutID = first.workoutID
        self.date = first.sessionDate
        self.entries = entries.sorted { $0.setOrderIndex < $1.setOrderIndex }
    }

    var totalReps: Int { entries.reduce(0) { $0 + $1.reps } }
    var totalVolume: Double { entries.reduce(0) { $0 + $1.volume } }
}

private struct ExerciseProgressChartsCard: View {
    let points: [ExerciseProgressPoint]
    let languageCode: String
    let locale: Locale

    private var chartPoints: [ExerciseProgressPoint] { Array(points.suffix(8)) }
    private var latestPointID: UUID? { chartPoints.last?.id }

    var body: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Visual Trends", "Візуальні тренди"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(t("Last \(chartPoints.count) sessions in the selected month.", "Останні \(chartPoints.count) сес. у вибраному місяці."))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }

                if chartPoints.isEmpty {
                    Text(t("No chart data", "Немає даних для графіка"))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                } else {
                    weightChart
                    volumeChart

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                        spacing: 8
                    ) {
                        GymMetricTile(
                            label: t("Peak weight", "Пікова вага"),
                            value: formatWeight(chartPoints.map(\.maxWeight).max() ?? 0)
                        )
                        GymMetricTile(
                            label: t("Avg volume", "Сер. обсяг"),
                            value: formatNumber(
                                chartPoints.reduce(0) { $0 + $1.totalVolume } /
                                    Double(max(1, chartPoints.count))
                            )
                        )
                    }
                }
            }
        }
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Max Weight Trend", "Тренд максимальної ваги"))
                .font(.subheadline.weight(.semibold))
            Text(weightTrendLabel)
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value(t("Session", "Сесія"), point.date),
                    yStart: .value(t("Baseline", "Основа"), 0),
                    yEnd: .value(t("Max weight", "Максимальна вага"), point.maxWeight)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [GymTheme.primary.opacity(0.28), GymTheme.primary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value(t("Session", "Сесія"), point.date),
                    y: .value(t("Max weight", "Максимальна вага"), point.maxWeight)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(GymTheme.primary)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value(t("Session", "Сесія"), point.date),
                    y: .value(t("Max weight", "Максимальна вага"), point.maxWeight)
                )
                .foregroundStyle(point.id == latestPointID ? GymTheme.tertiary : GymTheme.primary)
                .symbolSize(point.id == latestPointID ? 75 : 40)
                .accessibilityLabel(point.date.formatted(.dateTime.day().month(.wide).locale(locale)))
                .accessibilityValue(formatWeight(point.maxWeight))
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(4, chartPoints.count))) {
                    AxisGridLine().foregroundStyle(GymTheme.outline.opacity(0.25))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(GymTheme.outline.opacity(0.25))
                    AxisValueLabel()
                }
            }
            .frame(minHeight: 210)
            .accessibilityLabel(t("Maximum weight chart", "Графік максимальної ваги"))
            .accessibilityValue(weightTrendLabel)
        }
    }

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Volume by Session", "Обсяг по сесіях"))
                .font(.subheadline.weight(.semibold))
            Text(volumeTrendLabel)
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)

            Chart(chartPoints) { point in
                BarMark(
                    x: .value(t("Session", "Сесія"), point.date),
                    y: .value(t("Volume", "Обсяг"), point.totalVolume)
                )
                .foregroundStyle(
                    point.id == latestPointID
                        ? GymTheme.tertiary.gradient
                        : GymTheme.secondary.gradient
                )
                .cornerRadius(7)
                .accessibilityLabel(point.date.formatted(.dateTime.day().month(.wide).locale(locale)))
                .accessibilityValue(
                    t(
                        "\(formatNumber(point.totalVolume)) volume, \(point.totalReps) reps",
                        "обсяг \(formatNumber(point.totalVolume)), \(point.totalReps) повт."
                    )
                )
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(4, chartPoints.count))) {
                    AxisGridLine().foregroundStyle(GymTheme.outline.opacity(0.25))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(GymTheme.outline.opacity(0.25))
                    AxisValueLabel()
                }
            }
            .frame(minHeight: 210)
            .accessibilityLabel(t("Session volume chart", "Графік обсягу сесій"))
            .accessibilityValue(volumeTrendLabel)
        }
    }

    private var weightTrendLabel: String {
        trendLabel(
            start: chartPoints.first?.maxWeight,
            end: chartPoints.last?.maxWeight,
            unit: t("kg", "кг")
        )
    }

    private var volumeTrendLabel: String {
        trendLabel(
            start: chartPoints.first?.totalVolume,
            end: chartPoints.last?.totalVolume,
            unit: t("volume", "обсягу")
        )
    }

    private func trendLabel(start: Double?, end: Double?, unit: String) -> String {
        guard let start, let end else { return t("No trend yet", "Тренду ще немає") }
        let delta = end - start
        if abs(delta) < 0.05 { return t("Holding steady", "Стабільно") }
        let prefix = delta > 0 ? "+" : "−"
        return t(
            "\(prefix)\(formatNumber(abs(delta))) \(unit) vs first session",
            "\(prefix)\(formatNumber(abs(delta))) \(unit) до першої сесії"
        )
    }

    private func formatWeight(_ value: Double) -> String {
        "\(value.formatted(.number.locale(locale).precision(.fractionLength(0 ... 1)))) \(t("kg", "кг"))"
    }

    private func formatNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func t(_ english: String, _ ukrainian: String) -> String {
        gymText(english, ukrainian, languageCode: languageCode)
    }
}
