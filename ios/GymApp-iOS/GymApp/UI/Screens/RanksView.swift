import SwiftUI

struct RanksView: View {
    @ObservedObject var store: WorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    private var totalXP: Int { store.syncProfileStats().xp }
    private var level: Int { RankCatalog.level(for: totalXP) }
    private var current: RankDefinition { RankCatalog.current(level: level) }
    private var next: RankDefinition? { RankCatalog.next(afterLevel: level) }

    /// Progress toward `next` within the current rank's XP segment, shared by the hero bar
    /// and the ladder row for `next` so both stay in sync.
    private var nextRankProgress: Double {
        guard let next else { return 1 }
        let start = current.requiredXP
        let span = max(1, next.requiredXP - start)
        return Double(max(0, totalXP - start)) / Double(span)
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    heroPanel
                    ladderPanel
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(gymText("Ranks", "Ранги", "Ранги", languageCode: languageCode))
    }

    private var heroPanel: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(current.title(languageCode), systemImage: "trophy.fill")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(gymText(
                    "Level \(level) · \(totalXP.formatted()) XP",
                    "Рівень \(level) · \(totalXP.formatted()) XP",
                    "Уровень \(level) · \(totalXP.formatted()) XP",
                    languageCode: languageCode
                ))
                .foregroundStyle(Color.white.opacity(0.82))

                if let next {
                    let remaining = max(0, next.requiredXP - totalXP)

                    RankProgressTrack(progress: nextRankProgress, trackColor: Color.white.opacity(0.25), fillColor: .white)
                        .frame(height: 6)
                        .accessibilityHidden(true)

                    Text(gymText(
                        "\(remaining.formatted()) XP to \(next.title(languageCode))",
                        "\(remaining.formatted()) XP до «\(next.title(languageCode))»",
                        "\(remaining.formatted()) XP до «\(next.title(languageCode))»",
                        languageCode: languageCode
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
                }
            }
        }
    }

    private var ladderPanel: some View {
        GymPanel(contentPadding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(RankCatalog.ranks.enumerated()), id: \.element.id) { index, rank in
                    rankRow(rank)
                    if index < RankCatalog.ranks.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
        }
    }

    private func rankRow(_ rank: RankDefinition) -> some View {
        let unlocked = level >= rank.level
        let isCurrent = rank.id == current.id
        let isNext = next?.id == rank.id
        let remaining = max(0, rank.requiredXP - totalXP)

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(unlocked ? GymTheme.primary.opacity(0.14) : GymTheme.surfaceVariant)
                Image(systemName: unlocked ? "trophy.fill" : "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(unlocked ? GymTheme.primary : GymTheme.textSecondary)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(rank.title(languageCode))
                    .font(.headline)
                Text(gymText(
                    "Level \(rank.level) · from \(rank.requiredXP.formatted()) XP",
                    "Рівень \(rank.level) · від \(rank.requiredXP.formatted()) XP",
                    "Уровень \(rank.level) · от \(rank.requiredXP.formatted()) XP",
                    languageCode: languageCode
                ))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)

                if isNext {
                    RankProgressTrack(progress: nextRankProgress, trackColor: GymTheme.outlineSoft, fillColor: GymTheme.primary)
                        .frame(height: 6)
                    Text(gymText(
                        "\(remaining.formatted()) XP to go",
                        "ще \(remaining.formatted()) XP",
                        "ещё \(remaining.formatted()) XP",
                        languageCode: languageCode
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GymTheme.primary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GymTheme.primary.opacity(0.08))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isCurrent
                ? gymLocalized("Current", languageCode: languageCode)
                : unlocked
                    ? gymLocalized("Unlocked", languageCode: languageCode)
                    : gymLocalized("Locked", languageCode: languageCode)
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A capsule progress bar with a deliberately visible track, used in place of the platform
/// `ProgressView` (whose default track is too faint against both hero and card backgrounds).
private struct RankProgressTrack: View {
    let progress: Double
    let trackColor: Color
    let fillColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * min(1, max(0, progress)))
            }
        }
    }
}
