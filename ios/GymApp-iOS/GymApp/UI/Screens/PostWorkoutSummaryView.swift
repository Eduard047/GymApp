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
    let weeklyStreakWeeks: Int
    let rewards: PostWorkoutRewardDelta
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

@MainActor
struct PostWorkoutSummaryView: View {
    @ObservedObject private var store: WorkoutStore
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var feedbackErrorMessage: String?
    @State private var failedFeedback: WorkoutFeedback?

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
                        if !personalRecords.isEmpty {
                            personalRecordsPanel
                        }
                        if !rewards.completedMissions.isEmpty {
                            missionsPanel(rewards.completedMissions)
                        }
                        if !rewards.unlockedBadges.isEmpty {
                            badgesPanel(rewards.unlockedBadges)
                        }
                        actions
                    }
                    .padding(.horizontal, 14)
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
        .navigationTitle("Workout complete")
        .navigationBarTitleDisplayMode(.inline)
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

    /// Groups the session's PRs one row per exercise, and drops any record
    /// whose value is 0. A 0-weight "record" happens on an exercise with no
    /// prior history: `previousMaxWeight`/`previousEstimatedMax` default to
    /// -1 as a sentinel, so a first-time bodyweight set logged at weight 0
    /// (e.g. an assisted or bodyweight movement) satisfies `0 > -1` and is
    /// flagged as a new best even though it carries no real value. That
    /// sentinel comparison lives in this computed property, not in a deeper
    /// domain module, so the `> 0` guards below are the fix — no domain
    /// logic changes.
    private var personalRecords: [SummaryPersonalRecord] {
        guard let workout = store.workout(id: workoutID),
              let current = sessionSummary else { return [] }
        return workout.exercises.compactMap { block -> SummaryPersonalRecord? in
            guard let exercise = store.exercise(id: block.exerciseID), !block.sets.isEmpty else {
                return nil
            }
            let previous = postWorkoutPreviousHistory(
                store.exerciseHistory(exerciseID: block.exerciseID),
                current: current
            )
            let previousMaxWeight = previous.map(\.weight).max() ?? -1
            let previousEstimatedMax = previous.map(\.estimatedOneRepMax).max() ?? -1

            var weightRecord: Double?
            if let bestWeight = block.sets.max(by: { $0.weight < $1.weight }),
               bestWeight.weight > previousMaxWeight, bestWeight.weight > 0 {
                weightRecord = bestWeight.weight
            }
            var oneRepMaxRecord: Double?
            if let bestEstimated = block.sets.max(by: {
                $0.estimatedOneRepMax < $1.estimatedOneRepMax
            }), bestEstimated.estimatedOneRepMax > previousEstimatedMax, bestEstimated.estimatedOneRepMax > 0 {
                oneRepMaxRecord = bestEstimated.estimatedOneRepMax
            }

            guard weightRecord != nil || oneRepMaxRecord != nil else { return nil }
            return SummaryPersonalRecord(
                exerciseID: exercise.id,
                title: gymExerciseName(exercise),
                weight: weightRecord,
                estimatedOneRepMax: oneRepMaxRecord
            )
        }
    }

    private func recordDetail(_ record: SummaryPersonalRecord) -> String {
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

    private func rewardHero(_ workout: WorkoutSession) -> some View {
        let xp = sessionSummary.map(GamificationEngine.xpForSession) ?? 0
        let progression = gamification.progression
        return GymHeroPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.white)
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
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(xp) XP")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Text(gymText(
                        "Session XP",
                        "XP сесії",
                        "XP сессии",
                        languageCode: languageCode
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
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
                        .tint(Color.white)
                        .frame(height: 4)
                        .clipShape(Capsule())
                        .accessibilityHidden(true)

                    Text(gymText(
                        "\(progression.xpToNextLevel) XP to level \(progression.level + 1)",
                        "\(progression.xpToNextLevel) XP до рівня \(progression.level + 1)",
                        "\(progression.xpToNextLevel) XP до уровня \(progression.level + 1)",
                        languageCode: languageCode
                    ))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .accessibilityElement(children: .combine)
        }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    GymMetricTile(label: "Exercises", value: workout.exercises.count.formatted(.number.locale(gymAppLocale())))
                    GymMetricTile(label: "Sets", value: workout.setCount.formatted(.number.locale(gymAppLocale())))
                    GymMetricTile(
                        label: "Volume",
                        value: workout.totalVolume.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 1)))
                    )
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
            HStack(spacing: 8) {
                ForEach(WorkoutFeedback.allCases) { feedback in
                    feedbackButton(feedback)
                }
            }
        }
    }

    private func feedbackButton(_ feedback: WorkoutFeedback) -> some View {
        let selected = store.feedback(for: workoutID) == feedback
        return Button {
            saveFeedback(feedback)
        } label: {
            Text(feedbackTitle(feedback))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                            .tint(GymTheme.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var personalRecordsPanel: some View {
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
                                .foregroundStyle(GymTheme.tertiary)
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
                    "Workout detail",
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

private struct SummaryPersonalRecord: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    let title: String
    let weight: Double?
    let estimatedOneRepMax: Double?
}

private struct WorkoutFeedbackButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : GymTheme.textPrimary)
            .background(
                (selected ? GymTheme.primary : GymTheme.surfaceVariant)
                    .opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(
                    cornerRadius: GymTheme.controlCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GymTheme.controlCornerRadius,
                    style: .continuous
                )
                .strokeBorder(selected ? GymTheme.primary : GymTheme.outlineSoft, lineWidth: 1)
            }
    }
}

private extension BadgeRarity {
    var displayName: String {
        gymLocalized(rawValue.capitalized)
    }
}
