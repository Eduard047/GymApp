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
                        progressionPanel
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

    private var weeklyStreakWeeks: Int {
        postWorkoutExperience?.weeklyStreakWeeks ?? 0
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

    private var personalRecords: [SummaryPersonalRecord] {
        guard let workout = store.workout(id: workoutID),
              let current = sessionSummary else { return [] }
        return workout.exercises.flatMap { block -> [SummaryPersonalRecord] in
            guard let exercise = store.exercise(id: block.exerciseID), !block.sets.isEmpty else {
                return []
            }
            let previous = postWorkoutPreviousHistory(
                store.exerciseHistory(exerciseID: block.exerciseID),
                current: current
            )
            let previousMaxWeight = previous.map(\.weight).max() ?? -1
            let previousEstimatedMax = previous.map(\.estimatedOneRepMax).max() ?? -1
            var values: [SummaryPersonalRecord] = []
            if let bestWeight = block.sets.max(by: { $0.weight < $1.weight }),
               bestWeight.weight > previousMaxWeight {
                values.append(
                    SummaryPersonalRecord(
                        exerciseID: exercise.id,
                        title: gymExerciseName(exercise),
                        detail: gymText(
                            "New weight best · \(bestWeight.weight.formatted(.number.precision(.fractionLength(0 ... 2))))",
                            "Новий рекорд ваги · \(bestWeight.weight.formatted(.number.precision(.fractionLength(0 ... 2))))",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "dumbbell.fill"
                    )
                )
            }
            if let bestEstimated = block.sets.max(by: {
                $0.estimatedOneRepMax < $1.estimatedOneRepMax
            }), bestEstimated.estimatedOneRepMax > previousEstimatedMax {
                values.append(
                    SummaryPersonalRecord(
                        exerciseID: exercise.id,
                        title: gymExerciseName(exercise),
                        detail: gymText(
                            "Estimated 1RM · \(bestEstimated.estimatedOneRepMax.formatted(.number.precision(.fractionLength(0 ... 1))))",
                            "Розрахунковий 1ПМ · \(bestEstimated.estimatedOneRepMax.formatted(.number.precision(.fractionLength(0 ... 1))))",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "bolt.fill"
                    )
                )
            }
            return values
        }
    }

    private func rewardHero(_ workout: WorkoutSession) -> some View {
        let xp = sessionSummary.map(GamificationEngine.xpForSession) ?? 0
        return GymHeroPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout complete")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(gymFormattedDate(workout.date, date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    GymMetricTile(label: "Session XP", value: "+\(xp)", emphasized: true, onHero: true)
                    GymMetricTile(label: "Level", value: gamification.progression.level.formatted(), onHero: true)
                    GymMetricTile(label: "Title", value: gamification.progression.title.name, onHero: true)
                    GymMetricTile(
                        label: gymText(
                            "Week streak",
                            "Серія тижнів",
                            "Серия недель",
                            languageCode: languageCode
                        ),
                        value: gymText(
                            "\(weeklyStreakWeeks) wk",
                            "\(weeklyStreakWeeks) тиж",
                            "\(weeklyStreakWeeks) нед",
                            languageCode: languageCode
                        ),
                        onHero: true
                    )
                }
            }
        }
    }

    private func metricsPanel(_ workout: WorkoutSession) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    title: "Training metrics",
                    supporting: workout.note
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    GymMetricTile(label: "Exercises", value: workout.exercises.count.formatted())
                    GymMetricTile(label: "Sets", value: workout.setCount.formatted())
                    GymMetricTile(
                        label: "Volume",
                        value: workout.totalVolume.formatted(.number.precision(.fractionLength(0 ... 1)))
                    )
                    GymMetricTile(
                        label: "Top muscle",
                        value: trainedMuscles.first.map(muscleTitle) ?? "—"
                    )
                }
            }
        }
    }

    private var progressionPanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText(
                        "Level \(gamification.progression.level) · \(gamification.progression.title.name)",
                        "Рівень \(gamification.progression.level) · \(gymLocalized(gamification.progression.title.name))",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    supporting: gymText(
                        "\(gamification.progression.xpToNextLevel) XP to the next level",
                        "\(gamification.progression.xpToNextLevel) XP до наступного рівня",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                ProgressView(value: gamification.progression.levelProgress)
                    .tint(GymTheme.primary)
                    .accessibilityLabel("Level progress")
                    .accessibilityValue(
                        gamification.progression.levelProgress.formatted(.percent.precision(.fractionLength(0)))
                    )
                HStack {
                    Text(
                        gymText(
                            "\(gamification.progression.xpIntoLevel) XP this level",
                            "\(gamification.progression.xpIntoLevel) XP на цьому рівні",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    Spacer()
                    Text(
                        gymText(
                            "\(gamification.progression.totalXP) total XP",
                            "\(gamification.progression.totalXP) XP загалом",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
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
                .lineLimit(2)
                .minimumScaleFactor(0.75)
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
            gymText("Too easy", "Надто легко", "Слишком легко", languageCode: languageCode)
        case .normal:
            gymText("Just right", "Саме так", "В самый раз", languageCode: languageCode)
        case .hard:
            gymText("Too hard", "Надто важко", "Слишком тяжело", languageCode: languageCode)
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
                            Text(item.load.formatted(.number.precision(.fractionLength(0))))
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
                    HStack(alignment: .top, spacing: 11) {
                        if let exercise = store.exercise(id: record.exerciseID) {
                            ExerciseMediaButton(
                                rawExerciseName: exercise.name,
                                catalogKey: exercise.catalogKey,
                                exerciseID: exercise.id,
                                ownerKey: store.accountStorageKey
                            )
                        } else {
                            Image(systemName: record.systemImage)
                                .foregroundStyle(GymTheme.tertiary)
                                .frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.subheadline.weight(.semibold))
                            Text(gymLocalized(record.detail))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
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
                    title: "Unlocked badges"
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 9)], spacing: 9) {
                    ForEach(badges) { badge in
                        VStack(spacing: 7) {
                            Image(systemName: "medal.fill")
                                .font(.title2)
                                .foregroundStyle(badgeColor(badge.rarity))
                            Text(gymLocalized(badge.name))
                                .font(.subheadline.weight(.bold))
                                .multilineTextAlignment(.center)
                            Text(badge.rarity.displayName)
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(GymTheme.surfaceVariant.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(spacing: 10) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            onOpenDetail(workoutID)
        } label: {
            Label("Workout detail", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(GymSecondaryButtonStyle())

        Button(action: onDone) {
            Label("Done", systemImage: "checkmark")
        }
        .buttonStyle(GymPrimaryButtonStyle())
    }

    private func muscleTitle(_ load: MuscleLoad) -> String {
        guard let definition = MuscleMappingEngine.muscleDefinitions.first(where: { $0.id == load.muscleID }) else {
            return load.muscleID
        }
        return gymText(definition.titleEn, definition.titleUk, languageCode: gymCurrentLanguageCode())
    }

    private func missionValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func badgeColor(_ rarity: BadgeRarity) -> Color {
        switch rarity {
        case .common: GymTheme.textSecondary
        case .uncommon: GymTheme.primary
        case .rare: GymTheme.secondary
        case .epic: .purple
        case .legendary: GymTheme.tertiary
        }
    }
}

private struct SummaryPersonalRecord: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    let title: String
    let detail: String
    let systemImage: String
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
