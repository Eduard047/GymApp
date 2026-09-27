import SwiftUI

struct RanksView: View {
    @ObservedObject var store: WorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    private var totalXP: Int { store.syncProfileStats().xp }
    private var level: Int { RankCatalog.level(for: totalXP) }
    private var current: RankDefinition { RankCatalog.current(level: level) }
    private var next: RankDefinition? { RankCatalog.ranks.first { $0.level > level } }

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

private struct RankDefinition: Identifiable, Equatable {
    let id: String
    let level: Int
    let english: String
    let ukrainian: String
    let russian: String
    var requiredXP: Int { RankCatalog.cumulativeXP(for: level) }
    func title(_ language: String) -> String { gymText(english, ukrainian, russian, languageCode: language) }
}

private enum RankCatalog {
    static let ranks: [RankDefinition] = [
        .init(id: "rookie", level: 1, english: "Rookie", ukrainian: "Новачок", russian: "Новичок"),
        .init(id: "starter", level: 3, english: "Starter", ukrainian: "Стартовий", russian: "Начинающий"),
        .init(id: "steady", level: 5, english: "Steady", ukrainian: "Стабільний", russian: "Стабильный"),
        .init(id: "driven", level: 7, english: "Driven", ukrainian: "Вмотивований", russian: "Мотивированный"),
        .init(id: "striker", level: 9, english: "Striker", ukrainian: "Ударний", russian: "Ударник"),
        .init(id: "ironclad", level: 11, english: "Ironclad", ukrainian: "Незламний", russian: "Несокрушимый"),
        .init(id: "vanguard", level: 13, english: "Vanguard", ukrainian: "Авангард", russian: "Авангард"),
        .init(id: "challenger", level: 15, english: "Challenger", ukrainian: "Претендент", russian: "Претендент"),
        .init(id: "dominator", level: 17, english: "Dominator", ukrainian: "Домінатор", russian: "Доминатор"),
        .init(id: "elite", level: 19, english: "Elite", ukrainian: "Еліта", russian: "Элита"),
        .init(id: "titan", level: 21, english: "Titan", ukrainian: "Титан", russian: "Титан"),
        .init(id: "colossus", level: 23, english: "Colossus", ukrainian: "Колос", russian: "Колосс"),
        .init(id: "warborn", level: 25, english: "Warborn", ukrainian: "Воїн", russian: "Рождённый воином"),
        .init(id: "apex", level: 27, english: "Apex", ukrainian: "Апекс", russian: "Апекс"),
        .init(id: "mythic", level: 29, english: "Mythic", ukrainian: "Міфічний", russian: "Мифический"),
        .init(id: "legend", level: 31, english: "Legend", ukrainian: "Легенда", russian: "Легенда"),
        .init(id: "eternal", level: 33, english: "Eternal", ukrainian: "Вічний", russian: "Вечный"),
        .init(id: "immortal", level: 35, english: "Immortal", ukrainian: "Безсмертний", russian: "Бессмертный"),
        .init(id: "paragon", level: 37, english: "Paragon", ukrainian: "Парагон", russian: "Парагон"),
        .init(id: "overlord", level: 39, english: "Overlord", ukrainian: "Володар", russian: "Властелин"),
        .init(id: "ascendant", level: 41, english: "Ascendant", ukrainian: "Вознесений", russian: "Вознесенный"),
        .init(id: "conqueror", level: 43, english: "Conqueror", ukrainian: "Завойовник", russian: "Завоеватель"),
        .init(id: "sovereign", level: 45, english: "Sovereign", ukrainian: "Суверен", russian: "Суверен"),
        .init(id: "prime", level: 47, english: "Prime", ukrainian: "Прайм", russian: "Прайм"),
        .init(id: "omni", level: 49, english: "Omni", ukrainian: "Омні", russian: "Омни"),
        .init(id: "galactic", level: 51, english: "Galactic", ukrainian: "Галактичний", russian: "Галактический"),
        .init(id: "nova", level: 53, english: "Nova", ukrainian: "Нова", russian: "Нова"),
        .init(id: "singularity", level: 55, english: "Singularity", ukrainian: "Сингулярність", russian: "Сингулярность"),
        .init(id: "omega", level: 57, english: "Omega", ukrainian: "Омега", russian: "Омега"),
        .init(id: "transcendent", level: 60, english: "Transcendent", ukrainian: "Трансцендентний", russian: "Трансцендентный"),
        .init(id: "celestial", level: 64, english: "Celestial", ukrainian: "Небесний", russian: "Небесный"),
        .init(id: "empyrean", level: 68, english: "Empyrean", ukrainian: "Емпірей", russian: "Эмпирей"),
        .init(id: "infinite", level: 72, english: "Infinite", ukrainian: "Нескінченний", russian: "Бесконечный"),
        .init(id: "beyond", level: 76, english: "Beyond", ukrainian: "Понадмежний", russian: "Сверхпредельный"),
        .init(id: "cosmic-warlord", level: 80, english: "Cosmic Warlord", ukrainian: "Космічний воєвода", russian: "Космический воевода")
    ]

    static func requirement(for level: Int) -> Int {
        GamificationEngine.xpForNextLevel(level)
    }

    static func cumulativeXP(for level: Int) -> Int {
        GamificationEngine.xpForLevelStart(level)
    }

    static func level(for xp: Int) -> Int {
        GamificationEngine.level(for: max(0, xp))
    }

    static func current(level: Int) -> RankDefinition {
        ranks.last(where: { $0.level <= level }) ?? ranks[0]
    }
}
