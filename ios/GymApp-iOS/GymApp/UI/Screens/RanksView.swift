import SwiftUI

struct RanksView: View {
    @ObservedObject var store: WorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    private var totalXP: Int { store.syncProfileStats().xp }
    private var level: Int { RankCatalog.level(for: totalXP) }
    private var current: RankDefinition { RankCatalog.current(level: level) }
    private var next: RankDefinition? { RankCatalog.ranks.first { $0.level > level } }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    GymHeroPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(current.title(languageCode), systemImage: "trophy.fill")
                                .font(.title.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text(gymText("Level \(level) · \(totalXP.formatted()) XP", "Рівень \(level) · \(totalXP.formatted()) XP", languageCode: languageCode))
                                .foregroundStyle(Color.white.opacity(0.82))
                            if let next {
                                let start = current.requiredXP
                                let span = max(1, next.requiredXP - start)
                                ProgressView(value: Double(max(0, totalXP - start)) / Double(span))
                                    .tint(.white)
                                Text(gymText("Next: \(next.title(languageCode)) at level \(next.level)", "Далі: \(next.title(languageCode)) на рівні \(next.level)", languageCode: languageCode))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.78))
                            }
                        }
                    }

                    ForEach(RankCatalog.ranks) { rank in
                        rankCard(rank)
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(gymText("Ranks", "Ранги", languageCode: languageCode))
    }

    private func rankCard(_ rank: RankDefinition) -> some View {
        let unlocked = level >= rank.level
        let isCurrent = rank.id == current.id
        let previousXP = RankCatalog.ranks.firstIndex(of: rank).flatMap { index in
            index > 0 ? RankCatalog.ranks[index - 1].requiredXP : 0
        } ?? 0
        let segment = max(1, rank.requiredXP - previousXP)
        let progress = unlocked ? 1 : Double(max(0, totalXP - previousXP)) / Double(segment)

        return GymPanel(highlighted: isCurrent) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((unlocked ? GymTheme.primary : GymTheme.textSecondary).opacity(0.14))
                    Image(systemName: unlocked ? "trophy.fill" : "lock.fill")
                        .foregroundStyle(unlocked ? GymTheme.primary : GymTheme.textSecondary)
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(rank.title(languageCode))
                            .font(.headline)
                        if isCurrent {
                            GymInfoPill(gymText("Current", "Поточний", languageCode: languageCode), systemImage: "location.fill")
                        }
                    }
                    Text(gymText("Level \(rank.level) · \(rank.requiredXP.formatted()) XP", "Рівень \(rank.level) · \(rank.requiredXP.formatted()) XP", languageCode: languageCode))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    ProgressView(value: min(1, max(0, progress)))
                        .tint(unlocked ? GymTheme.primary : GymTheme.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(unlocked ? gymText("Unlocked", "Відкрито", languageCode: languageCode) : gymText("Locked", "Заблоковано", languageCode: languageCode))
        }
    }
}

private struct RankDefinition: Identifiable, Equatable {
    let id: String
    let level: Int
    let english: String
    let ukrainian: String
    var requiredXP: Int { RankCatalog.cumulativeXP(for: level) }
    func title(_ language: String) -> String { gymText(english, ukrainian, languageCode: language) }
}

private enum RankCatalog {
    static let ranks: [RankDefinition] = [
        .init(id: "rookie", level: 1, english: "Rookie", ukrainian: "Новачок"),
        .init(id: "starter", level: 3, english: "Starter", ukrainian: "Стартовий"),
        .init(id: "steady", level: 5, english: "Steady", ukrainian: "Стабільний"),
        .init(id: "driven", level: 7, english: "Driven", ukrainian: "Вмотивований"),
        .init(id: "striker", level: 9, english: "Striker", ukrainian: "Ударний"),
        .init(id: "ironclad", level: 11, english: "Ironclad", ukrainian: "Незламний"),
        .init(id: "vanguard", level: 13, english: "Vanguard", ukrainian: "Авангард"),
        .init(id: "challenger", level: 15, english: "Challenger", ukrainian: "Претендент"),
        .init(id: "dominator", level: 17, english: "Dominator", ukrainian: "Домінатор"),
        .init(id: "elite", level: 19, english: "Elite", ukrainian: "Еліта"),
        .init(id: "titan", level: 21, english: "Titan", ukrainian: "Титан"),
        .init(id: "colossus", level: 23, english: "Colossus", ukrainian: "Колос"),
        .init(id: "warborn", level: 25, english: "Warborn", ukrainian: "Воїн"),
        .init(id: "apex", level: 27, english: "Apex", ukrainian: "Апекс"),
        .init(id: "mythic", level: 29, english: "Mythic", ukrainian: "Міфічний"),
        .init(id: "legend", level: 31, english: "Legend", ukrainian: "Легенда"),
        .init(id: "eternal", level: 33, english: "Eternal", ukrainian: "Вічний"),
        .init(id: "immortal", level: 35, english: "Immortal", ukrainian: "Безсмертний"),
        .init(id: "paragon", level: 37, english: "Paragon", ukrainian: "Парагон"),
        .init(id: "overlord", level: 39, english: "Overlord", ukrainian: "Володар"),
        .init(id: "ascendant", level: 41, english: "Ascendant", ukrainian: "Вознесений"),
        .init(id: "conqueror", level: 43, english: "Conqueror", ukrainian: "Завойовник"),
        .init(id: "sovereign", level: 45, english: "Sovereign", ukrainian: "Суверен"),
        .init(id: "prime", level: 47, english: "Prime", ukrainian: "Прайм"),
        .init(id: "omni", level: 49, english: "Omni", ukrainian: "Омні"),
        .init(id: "galactic", level: 51, english: "Galactic", ukrainian: "Галактичний"),
        .init(id: "nova", level: 53, english: "Nova", ukrainian: "Нова"),
        .init(id: "singularity", level: 55, english: "Singularity", ukrainian: "Сингулярність"),
        .init(id: "omega", level: 57, english: "Omega", ukrainian: "Омега"),
        .init(id: "transcendent", level: 60, english: "Transcendent", ukrainian: "Трансцендентний"),
        .init(id: "celestial", level: 64, english: "Celestial", ukrainian: "Небесний"),
        .init(id: "empyrean", level: 68, english: "Empyrean", ukrainian: "Емпірей"),
        .init(id: "infinite", level: 72, english: "Infinite", ukrainian: "Нескінченний"),
        .init(id: "beyond", level: 76, english: "Beyond", ukrainian: "Понадмежний"),
        .init(id: "cosmic-warlord", level: 80, english: "Cosmic Warlord", ukrainian: "Космічний воєвода")
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
