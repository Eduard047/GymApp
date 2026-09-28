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
                            Label(item.shortTitle(languageCode), systemImage: "checkmark")
                        } else {
                            Text(item.shortTitle(languageCode))
                        }
                    }
                }
            } label: {
                HStack(spacing: GymTheme.Spacing.small) {
                    Text(period.shortTitle(languageCode))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: GymTheme.Spacing.small)
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(GymSecondaryButtonStyle())
            .accessibilityLabel(label)
            .accessibilityValue(period.shortTitle(languageCode))
        } else {
            Picker(label, selection: $period) {
                ForEach(MissionCadence.allCases) { item in
                    Text(item.shortTitle(languageCode)).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var levelSummaryText: String {
        let levelText = gymText(
            "Level \(snapshot.progression.level)",
            "Рівень \(snapshot.progression.level)",
            "Уровень \(snapshot.progression.level)",
            languageCode: languageCode
        )
        let titleText = RankCatalog.title(forLevel: snapshot.progression.level, languageCode: languageCode)
        let xpText = "\(snapshot.progression.totalXP.formatted(.number.locale(gymAppLocale()))) XP"
        return "\(levelText) · \(titleText) · \(xpText)"
    }

    private var hero: some View {
        Button(action: onOpenRanks) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(GymTheme.primary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                Text(levelSummaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: GymTheme.panelCornerRadius, style: .continuous)
                    .fill(GymTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: GymTheme.panelCornerRadius, style: .continuous)
                            .strokeBorder(GymTheme.outlineSoft.opacity(0.68), lineWidth: GymTheme.hairlineWidth)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelSummaryText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(
            gymText("Opens ranks", "Відкриває ранги", "Открывает ранги", languageCode: languageCode)
        )
    }

    private func missionCard(_ mission: MissionSnapshot) -> some View {
        let progressLabel = missionValue(mission.progress)
        let targetLabel = missionValue(mission.target)
        return GymPanel(
            highlighted: mission.completed,
            contentPadding: EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mission.completed ? "checkmark.seal.fill" : mission.systemImage)
                        .font(.title3)
                        .foregroundStyle(GymTheme.primary)
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(progressLabel) / \(targetLabel)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(GymTheme.textSecondary)
                        if mission.completed {
                            GymInfoPill(
                                gymText("Completed", "Виконано", "Выполнено", languageCode: languageCode),
                                systemImage: "checkmark"
                            )
                        }
                    }
                }

                ProgressView(value: mission.fraction)
                    .tint(mission.completed ? GymTheme.primary : GymTheme.secondary)
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
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0)))
    }
}

private extension MissionCadence {
    func shortTitle(_ languageCode: String) -> String {
        switch self {
        case .daily:
            gymText("Day", "День", "День", languageCode: languageCode)
        case .weekly:
            gymText("Week", "Тиждень", "Неделя", languageCode: languageCode)
        case .monthly:
            gymText("Month", "Місяць", "Месяц", languageCode: languageCode)
        }
    }
}
