import SwiftUI

struct MissionsView: View {
    @ObservedObject var store: WorkoutStore
    let onOpenRanks: () -> Void
    let embedded: Bool

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @State private var period: MissionCadence = .daily

    init(
        store: WorkoutStore,
        onOpenRanks: @escaping () -> Void,
        embedded: Bool = false
    ) {
        self.store = store
        self.onOpenRanks = onOpenRanks
        self.embedded = embedded
    }

    private var snapshot: GamificationSnapshot {
        store.gamificationSnapshot(calendar: calendar)
    }

    private var trainingProfile: TrainingProfile {
        TrainingProfileStore().load(accountStorageKey: store.accountStorageKey)
    }

    private var weeklyStreakWeeks: Int {
        WeeklyStreakCalculator.current(
            sessions: store.workoutSummaries,
            targetTrainingDays: trainingProfile.workoutsPerWeek,
            now: snapshot.generatedAt,
            calendar: calendar
        )
    }

    private var missions: [MissionSnapshot] {
        snapshot.missions.missions(for: period)
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero

                    missionPeriodControl

                    ForEach(missions) { mission in
                        missionCard(mission)
                    }

                    AchievementGallery(achievements: snapshot.achievements)
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(
            embedded ? "" : gymText("Missions", "Місії", "Миссии", languageCode: languageCode)
        )
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenRanks) {
                        Label(
                            gymText("Ranks", "Ранги", "Ранги", languageCode: languageCode),
                            systemImage: "trophy.fill"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var missionPeriodControl: some View {
        let label = gymText(
            "Mission period",
            "Період місій",
            "Период миссий",
            languageCode: languageCode
        )
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(MissionCadence.allCases) { item in
                    Button {
                        period = item
                    } label: {
                        if period == item {
                            Label(item.title(languageCode), systemImage: "checkmark")
                        } else {
                            Text(item.title(languageCode))
                        }
                    }
                }
            } label: {
                HStack(spacing: GymTheme.Spacing.small) {
                    Text(period.title(languageCode))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: GymTheme.Spacing.small)
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(GymSecondaryButtonStyle())
            .accessibilityLabel(label)
            .accessibilityValue(period.title(languageCode))
        } else {
            Picker(label, selection: $period) {
                ForEach(MissionCadence.allCases) { item in
                    Text(item.title(languageCode)).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var hero: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymLocalized(snapshot.progression.title.name, languageCode: languageCode))
                            .font(.title2.bold())
                        Text(
                            gymText(
                                "Level \(snapshot.progression.level)",
                                "Рівень \(snapshot.progression.level)",
                                "Уровень \(snapshot.progression.level)",
                                languageCode: languageCode
                            )
                        )
                        .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "scope")
                        .font(.title.bold())
                        .accessibilityHidden(true)
                }

                ProgressView(value: snapshot.progression.levelProgress)
                    .tint(.white)

                HStack(spacing: 10) {
                    GymMetricTile(
                        label: "XP",
                        value: snapshot.progression.totalXP.formatted(),
                        emphasized: true,
                        onHero: true
                    )
                    GymMetricTile(
                        label: gymText(
                            "Week streak",
                            "Серія тижнів",
                            "Серия недель",
                            languageCode: languageCode
                        ),
                        value: streakValue,
                        onHero: true
                    )
                }

                if embedded {
                    Button(action: onOpenRanks) {
                        Label(
                            gymText("View ranks", "Переглянути ранги", "Посмотреть ранги", languageCode: languageCode),
                            systemImage: "trophy.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
    }

    private var streakValue: String {
        return gymText(
            "\(weeklyStreakWeeks) wk",
            "\(weeklyStreakWeeks) тиж",
            "\(weeklyStreakWeeks) нед",
            languageCode: languageCode
        )
    }

    private func missionCard(_ mission: MissionSnapshot) -> some View {
        let progressLabel = missionValue(mission.progress)
        let targetLabel = missionValue(mission.target)
        return GymPanel(highlighted: mission.completed) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mission.completed ? "checkmark.seal.fill" : mission.systemImage)
                        .font(.title3)
                        .foregroundStyle(mission.completed ? GymTheme.primary : GymTheme.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mission.title.resolved(languageCode: languageCode))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(mission.description.resolved(languageCode: languageCode))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    if mission.completed {
                        GymInfoPill(
                            gymText("Completed", "Виконано", "Выполнено", languageCode: languageCode),
                            systemImage: "checkmark"
                        )
                    }
                }

                ProgressView(value: mission.fraction)
                    .tint(mission.completed ? GymTheme.primary : GymTheme.secondary)

                Text("\(progressLabel) / \(targetLabel)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(
                mission.completed
                    ? gymText("Completed", "Виконано", "Выполнено", languageCode: languageCode)
                    : progressLabel + " / " + targetLabel
            )
        }
    }

    private func missionValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private extension MissionCadence {
    func title(_ languageCode: String) -> String {
        switch self {
        case .daily:
            gymText("Daily", "Щоденні", "Ежедневные", languageCode: languageCode)
        case .weekly:
            gymText("Weekly", "Щотижневі", "Еженедельные", languageCode: languageCode)
        case .monthly:
            gymText("Monthly", "Щомісячні", "Ежемесячные", languageCode: languageCode)
        }
    }
}
