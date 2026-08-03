import SwiftUI

@MainActor
struct PostWorkoutSummaryView: View {
    @ObservedObject private var store: WorkoutStore
    @Environment(\.calendar) private var calendar

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
        GymBackground {
            if let workout = store.workout(id: workoutID) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        rewardHero(workout)
                        metricsPanel(workout)
                        progressionPanel
                        musclesPanel
                        personalRecordsPanel
                        missionsPanel
                        badgesPanel
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
        store.gamificationSnapshot(calendar: calendar)
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

    private var personalRecords: [SummaryPersonalRecord] {
        guard let workout = store.workout(id: workoutID) else { return [] }
        return workout.exercises.flatMap { block -> [SummaryPersonalRecord] in
            guard let exercise = store.exercise(id: block.exerciseID), !block.sets.isEmpty else {
                return []
            }
            let previous = store.exerciseHistory(exerciseID: block.exerciseID)
                .filter { $0.workoutID != workoutID }
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

    private var completedMissions: [MissionSnapshot] {
        (gamification.missions.daily + gamification.missions.weekly).filter(\.completed)
    }

    private var highlightedBadges: [BadgeSnapshot] {
        guard let workout = store.workout(id: workoutID) else { return [] }
        let workoutDay = calendar.gymEpochDay(for: workout.date)
        let newlyUnlocked = gamification.achievements
            .filter { $0.unlockedAtEpochDay == workoutDay }
            .map(\.badge)
        return newlyUnlocked.isEmpty
            ? Array(gamification.unlockedBadges.suffix(3))
            : newlyUnlocked
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
                        label: "Streak",
                        value: gymCount(
                            gamification.streak.currentDays,
                            englishOne: "day",
                            englishMany: "days",
                            ukrainianOne: "день",
                            ukrainianFew: "дні",
                            ukrainianMany: "днів"
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
                    eyebrow: "Session",
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
                    eyebrow: "Progress",
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

    @ViewBuilder
    private var musclesPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Muscles",
                    title: "Loaded today",
                    supporting: "Estimated from weight, repetitions, bodyweight movements, and your manual mappings."
                )
                if trainedMuscles.isEmpty {
                    Text("No mapped muscle load for this workout.")
                        .foregroundStyle(GymTheme.textSecondary)
                } else {
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
    }

    @ViewBuilder
    private var personalRecordsPanel: some View {
        GymPanel(highlighted: !personalRecords.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Personal records",
                    title: personalRecords.isEmpty ? "Keep building" : "New bests",
                    supporting: personalRecords.isEmpty
                        ? "No new weight or estimated 1RM records in this session."
                        : "This workout moved your exercise history forward."
                )
                ForEach(personalRecords) { record in
                    HStack(alignment: .top, spacing: 11) {
                        if let exercise = store.exercise(id: record.exerciseID) {
                            ExerciseMediaButton(
                                exerciseName: exercise.name,
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
    private var missionsPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Missions",
                    title: completedMissions.isEmpty ? "Next targets" : "Completed",
                    supporting: completedMissions.isEmpty
                        ? "Keep logging sets to complete daily and weekly missions."
                        : "Completed mission rewards are included in your progression."
                )

                let missions = completedMissions.isEmpty
                    ? Array((gamification.missions.daily + gamification.missions.weekly).prefix(4))
                    : completedMissions
                ForEach(missions) { mission in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(
                                gymLocalized(mission.title),
                                systemImage: mission.completed ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("+\(mission.rewardXP) XP")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(GymTheme.primary)
                        }
                        ProgressView(value: min(mission.progress, mission.target), total: max(1, mission.target))
                            .tint(mission.completed ? GymTheme.primary : GymTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var badgesPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Badges",
                    title: highlightedBadges.isEmpty ? "No badges yet" : "Unlocked collection",
                    supporting: highlightedBadges.isEmpty
                        ? "Complete workouts, streaks, and volume milestones to earn badges."
                        : "Badges unlocked on this day, or your latest unlocked badges."
                )
                if !highlightedBadges.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 9)], spacing: 9) {
                        ForEach(highlightedBadges) { badge in
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

private extension BadgeRarity {
    var displayName: String {
        gymLocalized(rawValue.capitalized)
    }
}
