import Foundation

/// Cross-client rank contract: 34 named ranks keyed by level, aligned with the
/// Android/PWA rank tables. This is the single source of truth for any UI that
/// displays a rank/title name (post-workout summary, profile, goals/missions,
/// progress hero, leaderboard, ranks screen). It is intentionally more granular
/// than `GamificationEngine.title(for:)`'s 6 coarse tiers, which remains for
/// non-display logic (e.g. `GamificationTitle`/`TitleTier` embedded in
/// `ProgressionSnapshot` for parity with the shared snapshot shape) but must
/// not be used to render a rank name in the UI.
struct RankDefinition: Identifiable, Equatable {
    let id: String
    let level: Int
    let english: String
    let ukrainian: String
    let russian: String
    var requiredXP: Int { RankCatalog.cumulativeXP(for: level) }
    func title(_ language: String) -> String { gymText(english, ukrainian, russian, languageCode: language) }
}

enum RankCatalog {
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

    /// Next rank strictly above `level`, or `nil` when `level` is already at or above the top rank.
    static func next(afterLevel level: Int) -> RankDefinition? {
        ranks.first { $0.level > level }
    }

    /// Localized display title for a level, e.g. "Level 3 · Starter" rows across the app.
    static func title(forLevel level: Int, languageCode: String) -> String {
        current(level: level).title(languageCode)
    }
}
