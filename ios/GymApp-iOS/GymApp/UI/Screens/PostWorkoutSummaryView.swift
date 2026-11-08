import SwiftUI

struct PostWorkoutRewardDelta: Equatable {
    let completedMissions: [MissionSnapshot]
    let unlockedBadges: [BadgeSnapshot]

    static let empty = PostWorkoutRewardDelta(completedMissions: [], unlockedBadges: [])
}

struct PostWorkoutAttribution {
    let current: WorkoutSessionSummary
    let sessionsThroughCurrent: [WorkoutSessionSummary]
    let previousSessions: [WorkoutSessionSummary]
    let afterSnapshot: GamificationSnapshot
    /// Level before this workout's XP; with `afterSnapshot` it drives the level-up pill.
    let previousLevel: Int
    let weeklyStreakWeeks: Int
    let rewards: PostWorkoutRewardDelta
}

/// The "Level up! N → M" pill's content: non-nil only when the workout raised the level.
func postWorkoutLevelUp(previousLevel: Int, currentLevel: Int) -> (from: Int, to: Int)? {
    currentLevel > previousLevel ? (from: previousLevel, to: currentLevel) : nil
}

private func isPostWorkoutEarlier(
    candidateDate: Date,
    candidateID: UUID,
    currentDate: Date,
    currentID: UUID
) -> Bool {
    if candidateDate != currentDate {
        return candidateDate < currentDate
    }
    return candidateID.uuidString < currentID.uuidString
}

func postWorkoutAttribution(
    sessions: [WorkoutSessionSummary],
    workoutID: UUID,
    targetTrainingDays: Int,
    calendar: Calendar
) -> PostWorkoutAttribution? {
    guard let current = sessions.first(where: { $0.workoutID == workoutID }) else {
        return nil
    }

    let isEarlierThanCurrent: (WorkoutSessionSummary) -> Bool = { candidate in
        isPostWorkoutEarlier(
            candidateDate: candidate.date,
            candidateID: candidate.workoutID,
            currentDate: current.date,
            currentID: current.workoutID
        )
    }
    let sessionsThroughCurrent = sessions
        .filter { $0.workoutID == workoutID || isEarlierThanCurrent($0) }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.workoutID.uuidString < $1.workoutID.uuidString
        }
    let previousSessions = sessionsThroughCurrent.filter(isEarlierThanCurrent)

    let after = GamificationEngine.buildSnapshot(
        sessions: sessionsThroughCurrent,
        targetTrainingDays: targetTrainingDays,
        now: current.date,
        calendar: calendar
    )
    let before = GamificationEngine.buildSnapshot(
        sessions: previousSessions,
        targetTrainingDays: targetTrainingDays,
        now: current.date,
        calendar: calendar
    )
    let completedMissionIDsBefore = Set(
        before.missions.all.lazy.filter(\.completed).map(\.id)
    )
    let unlockedBadgeIDsBefore = Set(before.unlockedBadges.lazy.map(\.id))
    let rewards = PostWorkoutRewardDelta(
        completedMissions: after.missions.all.filter {
            $0.completed && !completedMissionIDsBefore.contains($0.id)
        },
        unlockedBadges: after.unlockedBadges.filter {
            !unlockedBadgeIDsBefore.contains($0.id)
        }
    )

    return PostWorkoutAttribution(
        current: current,
        sessionsThroughCurrent: sessionsThroughCurrent,
        previousSessions: previousSessions,
        afterSnapshot: after,
        previousLevel: before.progression.level,
        weeklyStreakWeeks: WeeklyStreakCalculator.current(
            sessions: sessionsThroughCurrent,
            targetTrainingDays: targetTrainingDays,
            now: current.date,
            calendar: calendar
        ),
        rewards: rewards
    )
}

func postWorkoutRewardDelta(
    sessions: [WorkoutSessionSummary],
    workoutID: UUID,
    targetTrainingDays: Int,
    calendar: Calendar
) -> PostWorkoutRewardDelta {
    postWorkoutAttribution(
        sessions: sessions,
        workoutID: workoutID,
        targetTrainingDays: targetTrainingDays,
        calendar: calendar
    )?.rewards ?? .empty
}

func postWorkoutPreviousHistory(
    _ history: [ExerciseHistoryEntry],
    current: WorkoutSessionSummary
) -> [ExerciseHistoryEntry] {
    history.filter { entry in
        isPostWorkoutEarlier(
            candidateDate: entry.sessionDate,
            candidateID: entry.workoutID,
            currentDate: current.date,
            currentID: current.workoutID
        )
    }
}

/// One resolved row of the "Compared with last time" card (title in the app language).
struct SummaryVsLastRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: VsLastStatus
    let basis: VsLastBasis?
    let delta: Double?
    let best: VsLastSet
    let previousBest: VsLastSet?
}

@MainActor
struct PostWorkoutSummaryView: View {
    @ObservedObject private var store: WorkoutStore
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    @State private var feedbackErrorMessage: String?
    @State private var failedFeedback: WorkoutFeedback?
    /// Computed once per history revision off the main actor, not on every body pass.
    @State private var vsLastRows: [SummaryVsLastRow] = []

    private let workoutID: UUID
    private let onOpenDetail: (UUID) -> Void
    private let onDone: () -> Void

    init(
        appState: AppState,
        workoutID: UUID,
        onOpenDetail: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            store: appState.workoutStore,
            workoutID: workoutID,
            onOpenDetail: onOpenDetail,
            onDone: onDone
        )
    }

    init(
        store: WorkoutStore,
        workoutID: UUID,
        onOpenDetail: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.workoutID = workoutID
        self.onOpenDetail = onOpenDetail
        self.onDone = onDone
    }

    var body: some View {
        let rewards = postWorkoutRewards
        let personalRecords = personalRecords
        return GymBackground {
            if let workout = store.workout(id: workoutID) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        rewardHero(workout)
                        metricsPanel(workout)
                        feedbackPanel
                        if !trainedMuscles.isEmpty {
                            musclesPanel
                        }
                        if !vsLastRows.isEmpty {
                            vsLastPanel(vsLastRows)
                        }
                        if !personalRecords.isEmpty {
                            personalRecordsPanel(personalRecords)
                        }
                        if !rewards.completedMissions.isEmpty {
                            missionsPanel(rewards.completedMissions)
                        }
                        if !rewards.unlockedBadges.isEmpty {
                            badgesPanel(rewards.unlockedBadges)
                        }
                        actions
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.vertical, 12)
                    .padding(.bottom, 30)
                }
            } else {
                GymContentUnavailableView(
                    "Summary unavailable",
                    systemImage: "chart.bar.xaxis",
                    description: Text("The workout may have been deleted.")
                )
            }
        }
        .navigationTitle(gymText(
            "Workout summary", "Підсумок тренування", "Итог тренировки",
            languageCode: languageCode
        ))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.derivedDataRevision) { await refreshVsLast() }
    }

    private var gamification: GamificationSnapshot {
        postWorkoutExperience?.afterSnapshot ?? store.gamificationSnapshot(calendar: calendar)
    }

    private var postWorkoutExperience: PostWorkoutAttribution? {
        let target = TrainingProfileStore().load(
            accountStorageKey: store.accountStorageKey
        ).workoutsPerWeek
        return postWorkoutAttribution(
            sessions: store.workoutSummaries,
            workoutID: workoutID,
            targetTrainingDays: target,
            calendar: calendar
        )
    }

    private var postWorkoutRewards: PostWorkoutRewardDelta {
        postWorkoutExperience?.rewards ?? .empty
    }

    private var languageCode: String {
        gymCurrentLanguageCode()
    }

    private var sessionSummary: WorkoutSessionSummary? {
        store.workoutSummaries.first { $0.workoutID == workoutID }
    }

    private var sessionHistory: [ExerciseHistoryEntry] {
        store.allExerciseHistory().filter { $0.workoutID == workoutID }
    }

    private var trainedMuscles: [MuscleLoad] {
        MuscleMappingEngine.muscleLoads(
            history: sessionHistory,
            mappings: store.muscleMappings
        )
        .filter { $0.load > 0 }
        .sorted { $0.load > $1.load }
    }

    /// One PR row per exercise (blocks of the same exercise are merged, like Android) under
    /// the same rules as the live record badge (`LivePersonalRecords`); see
    /// `postWorkoutPersonalRecords`.
    private var personalRecords: [PostWorkoutPersonalRecord] {
        guard let workout = store.workout(id: workoutID),
              let current = sessionSummary else { return [] }
        return postWorkoutPersonalRecords(
            blocks: workout.exercises,
            previousHistory: { exerciseID in
                postWorkoutPreviousHistory(
                    store.exerciseHistory(exerciseID: exerciseID),
                    current: current
                )
            },
            title: { exerciseID in
                store.exercise(id: exerciseID).map { gymExerciseName($0) }
            }
        )
    }

    /// Compares every exercise with its previous session (shared/exercise-vs-last-v1.json).
    private func refreshVsLast() async {
        guard let date = store.workout(id: workoutID)?.date else {
            vsLastRows = []
            return
        }
        let history = store.allExerciseHistory()
        let id = workoutID
        let rows = await Task.detached(priority: .userInitiated) {
            GymExerciseVsLast.rows(history: history, workoutID: id, currentDate: date)
        }.value
        guard !Task.isCancelled else { return }
        vsLastRows = rows.map { row in
            SummaryVsLastRow(
                id: row.exerciseID,
                title: UUID(uuidString: row.exerciseID)
                    .flatMap { store.exercise(id: $0) }
                    .map { gymExerciseName($0) } ?? "—",
                status: row.status,
                basis: row.basis,
                delta: row.delta,
                best: row.best,
                previousBest: row.previousBest
            )
        }
    }

    private func recordDetail(_ record: PostWorkoutPersonalRecord) -> String {
        var parts: [String] = []
        if let weight = record.weight {
            parts.append(
                gymText(
                    "\(formattedRecordValue(weight)) kg",
                    "\(formattedRecordValue(weight)) кг",
                    "\(formattedRecordValue(weight)) кг",
                    languageCode: languageCode
                )
            )
        }
        if let oneRepMax = record.estimatedOneRepMax {
            parts.append(
                gymText(
                    "Est. 1RM \(formattedRecordValue(oneRepMax)) kg",
                    "Розрах. 1ПМ \(formattedRecordValue(oneRepMax)) кг",
                    "1ПМ \(formattedRecordValue(oneRepMax)) кг",
                    languageCode: languageCode
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private func formattedRecordValue(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 1)))
    }

    /// Compact "sets · volume · duration" row at the top of the hero.
    private func heroStatsRow(_ workout: WorkoutSession) -> some View {
        let duration = gymCompactDuration(workout.durationSeconds ?? 0, languageCode: languageCode)
        // At large text the three stats stack so values and labels keep whole words.
        let layout: AnyLayout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            heroStat(
                value: workout.setCount.formatted(.number.locale(gymAppLocale())),
                label: gymText("Sets", "Підходи", "Подходы", languageCode: languageCode)
            )
            heroStat(
                value: heroVolumeText(workout.totalVolume),
                label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode)
            )
            heroStat(
                value: duration.isEmpty ? "—" : duration,
                label: gymText("Duration", "Тривалість", "Длительность", languageCode: languageCode)
            )
        }
        .accessibilityElement(children: .combine)
    }

    /// Full grouped integer with the unit ("10,570 kg", "10 570 кг") so the hero
    /// matches Android and the web app. The shared `gymVolumeText` keeps its
    /// one-decimal format for the other screens.
    private func heroVolumeText(_ volume: Double) -> String {
        gymHeroVolumeText(volume, languageCode: languageCode)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(GymTheme.onHero)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GymTheme.onHeroSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rewardHero(_ workout: WorkoutSession) -> some View {
        let xp = sessionSummary.map(GamificationEngine.xpForSession) ?? 0
        let experience = postWorkoutExperience
        let progression = (experience?.afterSnapshot ?? store.gamificationSnapshot(calendar: calendar)).progression
        let levelUp = experience.flatMap {
            postWorkoutLevelUp(previousLevel: $0.previousLevel, currentLevel: progression.level)
        }
        return GymHeroPanel {
            VStack(alignment: .leading, spacing: 16) {
                GymAdaptiveStack(rowAlignment: .top, spacing: 12, columnSpacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .gymScaledFont(size: 30, weight: .bold, relativeTo: .title2, maxScale: 1.6)
                        .foregroundStyle(GymTheme.heroAccentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymText(
                            "Workout complete",
                            "Тренування завершено",
                            "Тренировка завершена",
                            languageCode: languageCode
                        ))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        Text(summaryDateLine(workout))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.onHeroSecondary)
                    }
                }

                heroStatsRow(workout)

                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(xp) XP")
                        .gymScaledFont(size: 34, weight: .semibold, design: .rounded, relativeTo: .largeTitle, monospacedDigit: true, maxScale: 1.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(GymTheme.heroAccentText)
                    Text(gymText(
                        "Session XP",
                        "XP тренування",
                        "XP тренировки",
                        languageCode: languageCode
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.onHeroSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(gymText(
                        "Level \(progression.level) · \(RankCatalog.title(forLevel: progression.level, languageCode: languageCode))",
                        "Рівень \(progression.level) · \(RankCatalog.title(forLevel: progression.level, languageCode: languageCode))",
                        "Уровень \(progression.level) · \(RankCatalog.title(forLevel: progression.level, languageCode: languageCode))",
                        languageCode: languageCode
                    ))
                    .font(.subheadline.weight(.semibold))

                    ProgressView(value: progression.levelProgress)
                        .progressViewStyle(GymHeroProgressStyle())
                        .accessibilityHidden(true)

                    Text(gymText(
                        "\(progression.xpToNextLevel) XP to level \(progression.level + 1)",
                        "\(progression.xpToNextLevel) XP до рівня \(progression.level + 1)",
                        "\(progression.xpToNextLevel) XP до уровня \(progression.level + 1)",
                        languageCode: languageCode
                    ))
                    .font(.caption)
                    .foregroundStyle(GymTheme.onHeroSecondary)
                }

                if let levelUp {
                    levelUpPill(from: levelUp.from, to: levelUp.to)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Flat tonal capsule on the hero, matching Android's `post_workout_level_up` InfoPill.
    private func levelUpPill(from: Int, to: Int) -> some View {
        Text(gymText(
            "Level up! \(from) → \(to)",
            "Новий рівень! \(from) → \(to)",
            "Новый уровень! \(from) → \(to)",
            languageCode: languageCode
        ))
        .font(.caption.weight(.semibold))
        .foregroundStyle(GymTheme.heroAccentText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(GymTheme.heroAccentText.opacity(0.12)))
        .overlay { Capsule().strokeBorder(GymTheme.heroOutline, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    /// "Сб, 26 сент. · 4 ч 31 мин" — abbreviated weekday + day + abbreviated
    /// month in the app's language locale, then the workout's duration
    /// (omitted when unknown). The year is appended only when it differs
    /// from the current year.
    private func summaryDateLine(_ workout: WorkoutSession) -> String {
        let datePart = gymShortDate(workout.date, calendar: calendar, languageCode: languageCode)
        guard let seconds = workout.durationSeconds, seconds > 0 else { return datePart }
        let durationText = gymCompactDuration(seconds, languageCode: languageCode)
        guard !durationText.isEmpty else { return datePart }
        return "\(datePart) · \(durationText)"
    }

    private func metricsPanel(_ workout: WorkoutSession) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    title: "Training metrics",
                    supporting: workout.note
                )
                // One tile per row at accessibility sizes: two narrow columns would hyphenate and cut the labels.
                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.adaptive(minimum: 112), spacing: 10)],
                    spacing: 10
                ) {
                    GymMetricTile(label: "Exercises", value: workout.exercises.count.formatted(.number.locale(gymAppLocale())))
                    GymMetricTile(
                        label: "Top muscle",
                        value: trainedMuscles.first.map(muscleTitle) ?? "—"
                    )
                }
            }
        }
    }

    private var feedbackPanel: some View {
        GymPanel(highlighted: store.feedback(for: workoutID) != nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text(gymText(
                    "How did it feel?",
                    "Як було?",
                    "Как было?",
                    languageCode: languageCode
                ))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

                feedbackChoices

                if let feedbackErrorMessage, let failedFeedback {
                    GymStatusBanner(message: feedbackErrorMessage, isError: true)

                    Button {
                        saveFeedback(failedFeedback)
                    } label: {
                        Label(
                            gymText(
                                "Try again",
                                "Спробувати ще раз",
                                "Попробовать ещё раз",
                                languageCode: languageCode
                            ),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackChoices: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(WorkoutFeedback.allCases) { feedback in
                    feedbackButton(feedback)
                }
            }
        } else {
            // Three equal chips in a row; a label may wrap by words to two lines (like the web app)
            // but is never shrunk or cut off. They stack only when a single word would not fit.
            ViewThatFits(in: .horizontal) {
                EqualWidthHStack(spacing: 8, minimumChildWidth: feedbackMinimumChipWidth) {
                    ForEach(WorkoutFeedback.allCases) { feedback in
                        feedbackButton(feedback)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(WorkoutFeedback.allCases) { feedback in
                        feedbackButton(feedback)
                    }
                }
            }
        }
    }

    /// Narrowest chip in which every label fits in at most two lines: for each label the best
    /// split of its words into two lines, plus the chip's horizontal padding, measured at the
    /// view's own Dynamic Type size.
    private var feedbackMinimumChipWidth: CGFloat {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)),
            UITraitCollection(legibilityWeight: legibilityWeight == .bold ? .bold : .regular)
        ])
        // "Bold Text" in the system settings makes the semibold labels heavier (and wider).
        let font = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize,
            weight: legibilityWeight == .bold ? .bold : .semibold
        )
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let widest = WorkoutFeedback.allCases.map { feedback -> CGFloat in
            let words = feedbackTitle(feedback)
                .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
                .map(String.init)
            guard words.count > 1 else { return width(words.first ?? "") }
            return (1 ..< words.count).map { split in
                max(width(words[..<split].joined(separator: " ")), width(words[split...].joined(separator: " ")))
            }.min() ?? 0
        }.max() ?? 0
        return ceil(widest) + 2 * Self.feedbackChipPadding + 2
    }

    private static let feedbackChipPadding: CGFloat = 12

    private func feedbackButton(_ feedback: WorkoutFeedback) -> some View {
        let selected = store.feedback(for: workoutID) == feedback
        return Button {
            saveFeedback(feedback)
        } label: {
            Text(feedbackTitle(feedback))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Self.feedbackChipPadding)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(WorkoutFeedbackButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func saveFeedback(_ feedback: WorkoutFeedback) {
        do {
            try store.setWorkoutFeedback(feedback, for: workoutID)
            feedbackErrorMessage = nil
            failedFeedback = nil
        } catch {
            feedbackErrorMessage = gymErrorMessage(error, languageCode: languageCode)
            failedFeedback = feedback
        }
    }

    private func feedbackTitle(_ feedback: WorkoutFeedback) -> String {
        switch feedback {
        case .easy:
            gymText("Easy", "Легко", "Легко", languageCode: languageCode)
        case .normal:
            gymText("Just right", "Саме те", "В самый раз", languageCode: languageCode)
        case .hard:
            gymText("Hard", "Важко", "Тяжело", languageCode: languageCode)
        }
    }

    @ViewBuilder
    private var musclesPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: "Loaded today"
                )
                ForEach(Array(trainedMuscles.prefix(8))) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(muscleTitle(item))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.load.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        ProgressView(value: item.load, total: max(1, trainedMuscles.first?.load ?? 1))
                            .tint(GymTheme.heroAccent)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "+20 kg" / "−3 reps" (true minus, no-break space before the unit); nil for "new" and "same".
    private func vsLastDeltaText(_ row: SummaryVsLastRow) -> String? {
        guard row.status == .up || row.status == .down, let delta = row.delta else { return nil }
        let sign = delta > 0 ? "+" : "\u{2212}"
        let magnitude = abs(delta)
        if row.basis == .reps {
            let count = Int(magnitude.rounded()).formatted(.number.locale(gymAppLocale()))
            return sign + vsLastRepsText(count)
        }
        return sign + gymVolumeText(magnitude, languageCode: languageCode)
    }

    private func vsLastRepsText(_ count: String) -> String {
        gymText(
            "\(count)\u{00A0}reps",
            "\(count)\u{00A0}повт.",
            "\(count)\u{00A0}повт.",
            languageCode: languageCode
        )
    }

    private func vsLastSetText(_ set: VsLastSet) -> String {
        guard set.weight > 0 else {
            return vsLastRepsText(set.reps.formatted(.number.locale(gymAppLocale())))
        }
        let weight = set.weight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))
        return "\(weight) × \(set.reps.formatted(.number.locale(gymAppLocale())))"
    }

    /// "60 × 8 → 62,5 × 8", or just the current best for a new exercise or an unchanged best set.
    private func vsLastBestText(_ row: SummaryVsLastRow) -> String {
        let current = vsLastSetText(row.best)
        guard let previous = row.previousBest, previous != row.best else { return current }
        return "\(vsLastSetText(previous)) → \(current)"
    }

    private func vsLastStatusLabel(_ status: VsLastStatus) -> String {
        switch status {
        case .new: gymText("New", "Нове", "Новое", languageCode: languageCode)
        case .up: gymText("Up", "Більше", "Больше", languageCode: languageCode)
        case .down: gymText("Down", "Менше", "Меньше", languageCode: languageCode)
        case .same: gymText("Same", "Так само", "Так же", languageCode: languageCode)
        }
    }

    private func vsLastStatusColor(_ status: VsLastStatus) -> Color {
        switch status {
        case .up: GymTheme.secondary
        case .down: GymTheme.error
        case .new, .same: GymTheme.textSecondary
        }
    }

    /// Per-exercise comparison with the previous session, flat tonal panel like the neighbours.
    private func vsLastPanel(_ rows: [SummaryVsLastRow]) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText(
                        "Compared with last time",
                        "Порівняно з минулим разом",
                        "По сравнению с прошлым разом",
                        languageCode: languageCode
                    )
                )
                ForEach(rows) { row in
                    let color = vsLastStatusColor(row.status)
                    HStack(alignment: .center, spacing: 11) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(vsLastBestText(row))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(GymTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                if row.status == .up || row.status == .down {
                                    Image(systemName: row.status == .up ? "arrow.up" : "arrow.down")
                                        .font(.caption.weight(.bold))
                                        .accessibilityLabel(row.status == .up
                                            ? gymText("Higher than last time", "Більше, ніж минулого разу", "Больше, чем в прошлый раз", languageCode: languageCode)
                                            : gymText("Lower than last time", "Менше, ніж минулого разу", "Меньше, чем в прошлый раз", languageCode: languageCode))
                                }
                                Text(vsLastStatusLabel(row.status))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(color)
                            if let delta = vsLastDeltaText(row) {
                                Text(delta)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(color)
                                    .lineLimit(1)
                            }
                        }
                        .layoutPriority(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func personalRecordsPanel(_ personalRecords: [PostWorkoutPersonalRecord]) -> some View {
        GymPanel(highlighted: !personalRecords.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: "New bests"
                )
                ForEach(personalRecords) { record in
                    HStack(alignment: .center, spacing: 11) {
                        if let exercise = store.exercise(id: record.exerciseID) {
                            ExerciseMediaButton(
                                rawExerciseName: exercise.name,
                                catalogKey: exercise.catalogKey,
                                exerciseID: exercise.id,
                                ownerKey: store.accountStorageKey,
                                editable: false,
                                width: 40,
                                height: 40,
                                playOverlayDiameter: 18
                            )
                        } else {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(GymTheme.record)
                                .frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(recordDetail(record))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func missionsPanel(_ missions: [MissionSnapshot]) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("Completed missions", "Виконані місії", "Выполненные миссии", languageCode: languageCode)
                )

                ForEach(missions) { mission in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(
                                mission.title.resolved(languageCode: languageCode),
                                systemImage: mission.completed ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(missionValue(mission.progress)) / \(missionValue(mission.target))")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        ProgressView(value: mission.fraction)
                            .tint(mission.completed ? GymTheme.primary : GymTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func badgesPanel(_ badges: [BadgeSnapshot]) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("New badges", "Нові значки", "Новые значки", languageCode: languageCode)
                )
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(badges) { badge in
                        GymBadgeRingTile(
                            systemImage: AchievementIconCatalog.icon(forID: badge.id),
                            title: gymLocalized(badge.name),
                            accent: gymBadgeAccent(badge.rarity)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(gymLocalized(badge.name)), \(badge.rarity.displayName)"
                        )
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onDone) {
                Text(gymText("Done", "Готово", "Готово", languageCode: languageCode))
            }
            .buttonStyle(GymPrimaryButtonStyle())

            Button {
                onOpenDetail(workoutID)
            } label: {
                Text(gymText(
                    "Workout details",
                    "Деталі тренування",
                    "Детали тренировки",
                    languageCode: languageCode
                ))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GymTheme.primary)
        }
    }

    private func muscleTitle(_ load: MuscleLoad) -> String {
        guard let definition = MuscleMappingEngine.muscleDefinitions.first(where: { $0.id == load.muscleID }) else {
            return load.muscleID
        }
        return gymText(definition.titleEn, definition.titleUk, definition.titleRu, languageCode: gymCurrentLanguageCode())
    }

    private func missionValue(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0)))
    }
}

/// One "new best" row of the post-workout summary. The id is the exercise id, so it
/// is stable across renders.
struct PostWorkoutPersonalRecord: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let title: String
    let weight: Double?
    let estimatedOneRepMax: Double?
}

/// Records set by one session, one row per exercise in first-appearance order: the
/// blocks of an exercise are merged, a row carries a weight only when the heaviest set
/// beat the previous best weight and an estimated 1RM only when the best estimate beat
/// the previous best estimate. An exercise without earlier history never has a record,
/// a 0 value is never a record. Mirrors Android's `buildPostWorkoutPersonalRecords`.
func postWorkoutPersonalRecords(
    blocks: [WorkoutExercise],
    previousHistory: (UUID) -> [ExerciseHistoryEntry],
    title: (UUID) -> String?
) -> [PostWorkoutPersonalRecord] {
    var order: [UUID] = []
    var setsByExercise: [UUID: [WorkoutSet]] = [:]
    for block in blocks where !block.sets.isEmpty {
        if setsByExercise[block.exerciseID] == nil { order.append(block.exerciseID) }
        setsByExercise[block.exerciseID, default: []].append(contentsOf: block.sets)
    }
    return order.compactMap { exerciseID -> PostWorkoutPersonalRecord? in
        guard let sets = setsByExercise[exerciseID], let name = title(exerciseID) else { return nil }
        let previous = previousHistory(exerciseID)
        guard let previousMaxWeight = previous.map(\.weight).max(),
              let previousEstimatedMax = previous.map(\.estimatedOneRepMax).max() else {
            return nil
        }

        var weightRecord: Double?
        if let bestWeight = sets.max(by: { $0.weight < $1.weight }),
           bestWeight.weight > previousMaxWeight, bestWeight.weight > 0 {
            weightRecord = bestWeight.weight
        }
        var oneRepMaxRecord: Double?
        if let bestEstimated = sets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }),
           bestEstimated.estimatedOneRepMax > previousEstimatedMax + 1e-9,
           bestEstimated.estimatedOneRepMax > 0 {
            oneRepMaxRecord = bestEstimated.estimatedOneRepMax
        }

        guard weightRecord != nil || oneRepMaxRecord != nil else { return nil }
        return PostWorkoutPersonalRecord(
            exerciseID: exerciseID,
            title: name,
            weight: weightRecord,
            estimatedOneRepMax: oneRepMaxRecord
        )
    }
}

private struct WorkoutFeedbackButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : GymTheme.textPrimary)
            .background(
                (selected ? GymTheme.primaryAction : GymTheme.surfaceVariant)
                    .opacity(configuration.isPressed ? 0.72 : 1),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(selected ? GymTheme.primaryAction : GymTheme.outlineSoft, lineWidth: 1)
            }
    }
}

private extension BadgeRarity {
    var displayName: String {
        gymLocalized(rawValue.capitalized)
    }
}


/// A row of equal-width children that fills the proposed width. Its ideal width is the minimum the
/// children need (`minimumChildWidth` each), which is what `ViewThatFits` compares with the space
/// available; children taller than the others make the whole row as tall as the tallest.
private struct EqualWidthHStack: Layout {
    var spacing: CGFloat = 8
    var minimumChildWidth: CGFloat = 0

    private func childWidth(for total: CGFloat, count: Int) -> CGFloat {
        (total - spacing * CGFloat(count - 1)) / CGFloat(count)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let count = subviews.count
        let ideal = minimumChildWidth * CGFloat(count) + spacing * CGFloat(count - 1)
        let width = proposal.width ?? ideal
        let each = proposal.width == nil ? minimumChildWidth : childWidth(for: width, count: count)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: each, height: nil)).height }
            .max() ?? 0
        // Below the minimum the row reports its ideal width, so ViewThatFits falls through to the stack.
        return CGSize(width: max(width, ideal), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = childWidth(for: bounds.width, count: subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}
