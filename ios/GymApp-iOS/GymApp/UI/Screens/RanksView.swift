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
                // Same accent trophy as the ladder marks and the Android hero; the title stays
                // one step below the large navigation title.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(GymTheme.heroAccentText)
                        .accessibilityHidden(true)
                    Text(current.title(languageCode))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .font(.title2.bold())
                Text(gymText(
                    "Level\u{00A0}\(level) · \(totalXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    "Рівень\u{00A0}\(level) · \(totalXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    "Уровень\u{00A0}\(level) · \(totalXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    languageCode: languageCode
                ))
                .foregroundStyle(GymTheme.onHeroSecondary)

                if let next {
                    let remaining = max(0, next.requiredXP - totalXP)

                    RankProgressTrack(progress: nextRankProgress, trackColor: GymTheme.heroOutline, fillColor: GymTheme.heroAccent)
                        .frame(height: 6)
                        .accessibilityHidden(true)

                    Text(gymText(
                        "\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP to \(next.title(languageCode))",
                        "\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP до\u{00A0}«\(next.title(languageCode))»",
                        "\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP до\u{00A0}«\(next.title(languageCode))»",
                        languageCode: languageCode
                    ))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.onHeroSecondary)
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

        // The current rank carries the one solid mark; earned ranks stay tonal, locked ones
        // neutral. Two-line rows centre the mark; the row with the progress bar keeps it level
        // with the title.
        let markFill = isCurrent
            ? GymTheme.primaryAction
            : unlocked ? GymTheme.primary.opacity(0.14) : GymTheme.surfaceVariant
        let markGlyph = isCurrent
            ? GymTheme.onPrimary
            : unlocked ? GymTheme.primary : GymTheme.textSecondary

        return HStack(alignment: isNext ? .top : .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(markFill)
                Image(systemName: unlocked ? "trophy.fill" : "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(markGlyph)
            }
            .gymScaledFrame(width: 36, height: 36, relativeTo: .subheadline, maxScale: 1.6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(rank.title(languageCode))
                    .font(.headline)
                Text(gymText(
                    "Level\u{00A0}\(rank.level) · from\u{00A0}\(rank.requiredXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    "Рівень\u{00A0}\(rank.level) · від\u{00A0}\(rank.requiredXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    "Уровень\u{00A0}\(rank.level) · от\u{00A0}\(rank.requiredXP.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                    languageCode: languageCode
                ))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)

                if isNext {
                    RankProgressTrack(progress: nextRankProgress, trackColor: GymTheme.outlineSoft, fillColor: GymTheme.primary)
                        .frame(height: 6)
                    Text(gymText(
                        "\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP to go",
                        "ще\u{00A0}\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                        "ещё\u{00A0}\(remaining.formatted(.number.locale(gymAppLocale())))\u{00A0}XP",
                        languageCode: languageCode
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.primary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
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
