package com.example.gymapp.data.repository

data class RankDefinition(
    val id: String,
    val levelRequirement: Int,
    val titleEn: String,
    val titleUk: String
)

val RANK_DEFINITIONS: List<RankDefinition> = listOf(
    RankDefinition("rookie", 1, "Rookie", "Новачок"),
    RankDefinition("starter", 3, "Starter", "Стартовий"),
    RankDefinition("steady", 5, "Steady", "Стабільний"),
    RankDefinition("driven", 7, "Driven", "Вмотивований"),
    RankDefinition("striker", 9, "Striker", "Ударний"),
    RankDefinition("ironclad", 11, "Ironclad", "Незламний"),
    RankDefinition("vanguard", 13, "Vanguard", "Авангард"),
    RankDefinition("challenger", 15, "Challenger", "Претендент"),
    RankDefinition("dominator", 17, "Dominator", "Домінатор"),
    RankDefinition("elite", 19, "Elite", "Еліта"),
    RankDefinition("titan", 21, "Titan", "Титан"),
    RankDefinition("colossus", 23, "Colossus", "Колос"),
    RankDefinition("warborn", 25, "Warborn", "Воїн"),
    RankDefinition("apex", 27, "Apex", "Апекс"),
    RankDefinition("mythic", 29, "Mythic", "Міфічний"),
    RankDefinition("legend", 31, "Legend", "Легенда"),
    RankDefinition("eternal", 33, "Eternal", "Вічний"),
    RankDefinition("immortal", 35, "Immortal", "Безсмертний"),
    RankDefinition("paragon", 37, "Paragon", "Парагон"),
    RankDefinition("overlord", 39, "Overlord", "Володар"),
    RankDefinition("ascendant", 41, "Ascendant", "Вознесений"),
    RankDefinition("conqueror", 43, "Conqueror", "Завойовник"),
    RankDefinition("sovereign", 45, "Sovereign", "Суверен"),
    RankDefinition("prime", 47, "Prime", "Прайм"),
    RankDefinition("omni", 49, "Omni", "Омні"),
    RankDefinition("galactic", 51, "Galactic", "Галактичний"),
    RankDefinition("nova", 53, "Nova", "Нова"),
    RankDefinition("singularity", 55, "Singularity", "Сингулярність"),
    RankDefinition("omega", 57, "Omega", "Омега"),
    RankDefinition("transcendent", 60, "Transcendent", "Трансцендентний"),
    RankDefinition("celestial", 64, "Celestial", "Небесний"),
    RankDefinition("empyrean", 68, "Empyrean", "Емпірей"),
    RankDefinition("infinite", 72, "Infinite", "Нескінченний"),
    RankDefinition("beyond", 76, "Beyond", "Понадмежний"),
    RankDefinition("cosmic-warlord", 80, "Cosmic Warlord", "Космічний воєвода")
)

fun rankDefinitionForLevel(level: Int): RankDefinition =
    RANK_DEFINITIONS.lastOrNull { level >= it.levelRequirement }
        ?: RANK_DEFINITIONS.first()

fun nextRankDefinitionAfter(level: Int): RankDefinition? =
    RANK_DEFINITIONS.firstOrNull { level < it.levelRequirement }
