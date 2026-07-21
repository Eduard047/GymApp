import Foundation

public struct MuscleDefinition: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let titleEn: String
    public let titleUk: String

    public init(id: String, titleEn: String, titleUk: String) {
        self.id = id
        self.titleEn = titleEn
        self.titleUk = titleUk
    }
}

public struct MuscleContribution: Codable, Identifiable, Hashable, Sendable {
    public var id: String { muscleID }
    public let muscleID: String
    public let weight: Double

    public init(muscleID: String, weight: Double) {
        self.muscleID = muscleID
        self.weight = weight
    }
}

/// Pure Swift port of Android's `MuscleMappingEngine.kt`.
public enum MuscleMappingEngine {
    public static let bodyweightLoadProxy = 72.0
    public static let setCompletionLoad = 35.0

    public static let muscleDefinitions: [MuscleDefinition] = [
        MuscleDefinition(id: "chest", titleEn: "Chest", titleUk: "Груди"),
        MuscleDefinition(id: "shoulders", titleEn: "Shoulders", titleUk: "Плечі"),
        MuscleDefinition(id: "biceps", titleEn: "Biceps", titleUk: "Біцепс"),
        MuscleDefinition(id: "triceps", titleEn: "Triceps", titleUk: "Тріцепс"),
        MuscleDefinition(id: "forearms", titleEn: "Forearms", titleUk: "Передпліччя"),
        MuscleDefinition(id: "abs", titleEn: "Abs", titleUk: "Прес"),
        MuscleDefinition(id: "obliques", titleEn: "Obliques", titleUk: "Косі мʼязи"),
        MuscleDefinition(id: "lats", titleEn: "Lats", titleUk: "Широчайші"),
        MuscleDefinition(id: "upperBack", titleEn: "Upper back", titleUk: "Верх спини"),
        MuscleDefinition(id: "lowerBack", titleEn: "Lower back", titleUk: "Поперек"),
        MuscleDefinition(id: "glutes", titleEn: "Glutes", titleUk: "Сідниці"),
        MuscleDefinition(id: "quads", titleEn: "Quads", titleUk: "Квадрицепси"),
        MuscleDefinition(id: "hamstrings", titleEn: "Hamstrings", titleUk: "Біцепс стегна"),
        MuscleDefinition(id: "adductors", titleEn: "Adductors", titleUk: "Привідні"),
        MuscleDefinition(id: "calves", titleEn: "Calves", titleUk: "Ікри")
    ]

    private static let exactMuscleMap: [String: [MuscleContribution]] = [
        "нахили в сторони на гіперекстензії": muscles(("obliques", 0.9), ("abs", 0.35), ("lowerBack", 0.25)),
        "бокові нахили на гіперекстензії": muscles(("obliques", 0.9), ("abs", 0.35), ("lowerBack", 0.25)),
        "присід зі штангою": muscles(("quads", 1), ("glutes", 0.7), ("hamstrings", 0.45), ("lowerBack", 0.25), ("abs", 0.2)),
        "присідання зі штангою": muscles(("quads", 1), ("glutes", 0.7), ("hamstrings", 0.45), ("lowerBack", 0.25), ("abs", 0.2)),
        "бокові нахили": muscles(("obliques", 0.9), ("abs", 0.3)),
        "бокові нахили з обтяженням": muscles(("obliques", 0.9), ("abs", 0.3)),
        "брусья": muscles(("triceps", 0.85), ("chest", 0.75), ("shoulders", 0.35)),
        "віджимання на брусах": muscles(("triceps", 0.85), ("chest", 0.75), ("shoulders", 0.35)),
        "біцепс з гантелями сидячи": muscles(("biceps", 1), ("forearms", 0.25)),
        "згинання рук з гантелями сидячи": muscles(("biceps", 1), ("forearms", 0.25)),
        "гантеля над головою": muscles(("triceps", 1), ("shoulders", 0.3)),
        "розгинання гантелі над головою": muscles(("triceps", 1), ("shoulders", 0.3)),
        "гантелі лежачи": muscles(("chest", 0.9), ("triceps", 0.55), ("shoulders", 0.45)),
        "жим гантелей лежачи": muscles(("chest", 0.9), ("triceps", 0.55), ("shoulders", 0.45)),
        "горизонтальна важільна тяга": muscles(("upperBack", 1), ("lats", 0.75), ("biceps", 0.45), ("forearms", 0.25)),
        "горизонтальна тяга у важільному тренажері": muscles(("upperBack", 1), ("lats", 0.75), ("biceps", 0.45), ("forearms", 0.25)),
        "гіперекстензія": muscles(("lowerBack", 1), ("glutes", 0.55), ("hamstrings", 0.45)),
        "жим лежачи": muscles(("chest", 1), ("triceps", 0.6), ("shoulders", 0.5)),
        "жим штанги лежачи": muscles(("chest", 1), ("triceps", 0.6), ("shoulders", 0.5)),
        "жим ногами": muscles(("quads", 1), ("glutes", 0.55), ("hamstrings", 0.35), ("calves", 0.15)),
        "жим ногами у тренажері": muscles(("quads", 1), ("glutes", 0.55), ("hamstrings", 0.35), ("calves", 0.15)),
        "жим сидячи": muscles(("shoulders", 1), ("triceps", 0.55), ("chest", 0.2)),
        "жим сидячи над головою": muscles(("shoulders", 1), ("triceps", 0.55), ("chest", 0.2)),
        "журавель": muscles(("lats", 1), ("upperBack", 0.75), ("biceps", 0.45), ("forearms", 0.25)),
        "тяга верхніх блоків у тренажері": muscles(("lats", 1), ("upperBack", 0.75), ("biceps", 0.45), ("forearms", 0.25)),
        "тяга верхних блоков в тренажере": muscles(("lats", 1), ("upperBack", 0.75), ("biceps", 0.45), ("forearms", 0.25)),
        "зведення ніг": muscles(("adductors", 1), ("quads", 0.25)),
        "зведення ніг у тренажері": muscles(("adductors", 1), ("quads", 0.25)),
        "розведення ніг": muscles(("glutes", 1)),
        "розведення ніг у тренажері": muscles(("glutes", 1)),
        "разведение ног": muscles(("glutes", 1)),
        "разведение ног в тренажере": muscles(("glutes", 1)),
        "згибання ніг": muscles(("hamstrings", 1), ("calves", 0.2)),
        "згинання ніг у тренажері": muscles(("hamstrings", 1), ("calves", 0.2)),
        "сгибание ног": muscles(("hamstrings", 1), ("calves", 0.2)),
        "сгибание ног в тренажере": muscles(("hamstrings", 1), ("calves", 0.2)),
        "сгибание ног лежа": muscles(("hamstrings", 1), ("calves", 0.2)),
        "сгибание ног сидя": muscles(("hamstrings", 1), ("calves", 0.2)),
        "махи в сторони": muscles(("shoulders", 1)),
        "підйоми гантелей через сторони": muscles(("shoulders", 1)),
        "метелик в середину": muscles(("chest", 1), ("shoulders", 0.25)),
        "зведення рук у тренажері": muscles(("chest", 1), ("shoulders", 0.25)),
        "метелик в сторони": muscles(("shoulders", 0.75), ("upperBack", 0.65)),
        "зворотні розведення у тренажері": muscles(("shoulders", 0.75), ("upperBack", 0.65)),
        "прес з диском в сторони": muscles(("obliques", 0.85), ("abs", 0.45)),
        "повороти корпусу з диском": muscles(("obliques", 0.85), ("abs", 0.45)),
        "прес звичайний з диском": muscles(("abs", 1), ("obliques", 0.25)),
        "скручування з диском": muscles(("abs", 1), ("obliques", 0.25)),
        "прес(підйом ніг)": muscles(("abs", 1)),
        "підйом ніг у висі": muscles(("abs", 1)),
        "протяжка": muscles(("shoulders", 0.85), ("upperBack", 0.55), ("biceps", 0.25)),
        "тяга штанги до підборіддя": muscles(("shoulders", 0.85), ("upperBack", 0.55), ("biceps", 0.25)),
        "підйом на носки": muscles(("calves", 1)),
        "підйом на носки стоячи": muscles(("calves", 1)),
        "підтягування в гравітроні": muscles(("lats", 1), ("upperBack", 0.65), ("biceps", 0.55), ("forearms", 0.3)),
        "підтягування у гравітроні": muscles(("lats", 1), ("upperBack", 0.65), ("biceps", 0.55), ("forearms", 0.3)),
        "підтягування з резинкою": muscles(("lats", 1), ("upperBack", 0.65), ("biceps", 0.55), ("forearms", 0.3)),
        "підтягування з еспандером": muscles(("lats", 1), ("upperBack", 0.65), ("biceps", 0.55), ("forearms", 0.3)),
        "розгинання ніг": muscles(("quads", 1)),
        "розгинання ніг у тренажері": muscles(("quads", 1)),
        "румунська тяга": muscles(("hamstrings", 1), ("glutes", 0.85), ("lowerBack", 0.65), ("upperBack", 0.2)),
        "станова тяга": muscles(("lowerBack", 0.9), ("glutes", 0.85), ("hamstrings", 0.8), ("upperBack", 0.45), ("quads", 0.35), ("forearms", 0.3)),
        "тренажер скота(біцепс)": muscles(("biceps", 1), ("forearms", 0.25)),
        "згинання рук на лаві скотта": muscles(("biceps", 1), ("forearms", 0.25)),
        "трицепс трикутник": muscles(("triceps", 1)),
        "розгинання рук на блоці з v-рукояттю": muscles(("triceps", 1)),
        "французький жим": muscles(("triceps", 1), ("shoulders", 0.15)),
        "фронтальна тяга": muscles(("lats", 1), ("upperBack", 0.7), ("biceps", 0.5), ("forearms", 0.25)),
        "тяга верхнього блока до грудей": muscles(("lats", 1), ("upperBack", 0.7), ("biceps", 0.5), ("forearms", 0.25)),
        "штанга на біцепс": muscles(("biceps", 1), ("forearms", 0.35)),
        "згинання рук зі штангою": muscles(("biceps", 1), ("forearms", 0.35))
    ]

    public static func estimatedLoad(for entry: ExerciseHistoryEntry) -> Double {
        let reps = max(0, entry.reps)
        let trackedLoad = max(0, entry.weight) * Double(reps)
        let exerciseLoad = trackedLoad > 0 ? trackedLoad : bodyweightLoadProxy * Double(reps)
        return exerciseLoad + setCompletionLoad
    }

    public static func manualContributionMap(
        from mappings: [ExerciseMuscleMapping]
    ) -> [String: [MuscleContribution]] {
        let validIDs = Set(muscleDefinitions.map(\.id))
        return Dictionary(grouping: mappings, by: \.exerciseNameKey).mapValues { values in
            values.compactMap { mapping in
                guard validIDs.contains(mapping.muscleID) else { return nil }
                return MuscleContribution(
                    muscleID: mapping.muscleID,
                    weight: min(1, max(0, mapping.weight))
                )
            }
        }
    }

    public static func defaultContributions(for exerciseName: String) -> [MuscleContribution] {
        contributions(for: exerciseName, manualMappings: [:])
    }

    public static func contributions(
        for exerciseName: String,
        manualMappings: [String: [MuscleContribution]] = [:]
    ) -> [MuscleContribution] {
        let normalized = normalizeExerciseName(exerciseName)
        if let manual = manualMappings[normalized], !manual.isEmpty { return manual }
        if let exact = exactMuscleMap[normalized] { return exact }
        let legCurl = isLegCurlName(normalized)
        var inferred: [String: Double] = [:]

        func add(_ id: String, _ weight: Double) {
            inferred[id] = max(inferred[id, default: 0], min(1, max(0, weight)))
        }

        if legCurl {
            add("hamstrings", 1); add("calves", 0.2)
        }
        if !legCurl && containsAny(normalized, ["біцепс", "бицепс", "bicep", "curl", "сгибание рук", "згинання рук"]) {
            add("biceps", 1); add("forearms", 0.25)
        }
        if containsAny(normalized, ["трицепс", "tricep", "француз", "розгинання рук", "разгибание рук", "pushdown"]) {
            add("triceps", 1)
        }
        if containsAny(normalized, ["жим ног", "жим ногами", "leg press"]) {
            add("quads", 1); add("glutes", 0.55); add("hamstrings", 0.35)
        }
        if containsAny(normalized, ["жим", "press", "bench"]) && !containsAny(normalized, ["ног", "leg press"]) {
            add("chest", 0.85); add("triceps", 0.55); add("shoulders", 0.45)
        }
        if containsAny(normalized, ["плеч", "дельт", "махи", "розведення", "разведение", "підйом гантелей", "подъем гантелей", "shoulder", "lateral raise", "rear delt", "face pull", "overhead press", "press overhead"]) {
            add("shoulders", 1)
        }
        if containsAny(normalized, ["підтяг", "подтяг", "pull up", "pullup", "pulldown", "тяга верхнього блока", "тяга верхнего блока", "верхній блок", "верхний блок"]) {
            add("lats", 1); add("upperBack", 0.65); add("biceps", 0.55); add("forearms", 0.3)
        }
        if containsAny(normalized, ["тяга", "deadlift", "row"]) && containsAny(normalized, ["румун", "станов", "становая", "deadlift"]) {
            add("hamstrings", 0.9); add("glutes", 0.85); add("lowerBack", 0.75); add("upperBack", 0.3); add("forearms", 0.25)
        }
        if containsAny(normalized, ["тяга", "row"]) && !containsAny(normalized, ["румун", "станов", "становая", "deadlift", "підборід", "подбород"]) {
            add("lats", 0.9); add("upperBack", 0.85); add("biceps", 0.45); add("forearms", 0.25)
        }
        if containsAny(normalized, ["прис", "присед", "squat", "випади", "выпады", "lunge"]) {
            add("quads", 1); add("glutes", 0.7); add("hamstrings", 0.45); add("lowerBack", 0.25)
        }
        if containsAny(normalized, ["розгинання ніг", "разгибание ног", "leg extension"]) { add("quads", 1) }
        if legCurl { add("hamstrings", 1); add("calves", 0.2) }
        if containsAny(normalized, ["підйом на носки", "підйоми на носки", "подъем на носки", "икры", "calf"]) { add("calves", 1) }
        if containsAny(normalized, ["прес", "скруч", "планка", "crunch", "sit up", "leg raise", "plank"]) { add("abs", 1) }
        if containsAny(normalized, ["нахил", "наклон", "сторони", "стороны", "поворот корпус", "rotation", "side bend", "russian twist"]) { add("obliques", 0.85) }
        if containsAny(normalized, ["гіперекстензі", "гиперэкстенз", "hyperextension"]) {
            add("lowerBack", 1); add("glutes", 0.55); add("hamstrings", 0.45)
        }
        if containsAny(normalized, ["сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик"]) {
            add("glutes", 1); add("hamstrings", 0.35)
        }
        if containsAny(normalized, ["зведення ніг", "сведение ног", "adductor"]) { add("adductors", 1) }
        if containsAny(normalized, ["розведення ніг", "разведение ног", "hip abduction", "abductor"]) { add("glutes", 1) }
        if containsAny(normalized, ["метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies"]) {
            add("chest", 1); add("shoulders", 0.25)
        }

        return muscleDefinitions.compactMap { definition in
            inferred[definition.id].map {
                MuscleContribution(muscleID: definition.id, weight: $0)
            }
        }
    }

    public static func muscleLoads(
        history: [ExerciseHistoryEntry],
        mappings: [ExerciseMuscleMapping] = []
    ) -> [MuscleLoad] {
        let manual = manualContributionMap(from: mappings)
        var loadByID: [String: Double] = [:]
        var lastDateByID: [String: Date] = [:]
        for entry in history {
            let load = estimatedLoad(for: entry)
            for contribution in contributions(for: entry.exerciseName, manualMappings: manual) {
                loadByID[contribution.muscleID, default: 0] += load * contribution.weight
                if entry.sessionDate > lastDateByID[contribution.muscleID, default: .distantPast] {
                    lastDateByID[contribution.muscleID] = entry.sessionDate
                }
            }
        }
        return muscleDefinitions.map {
            MuscleLoad(
                muscleID: $0.id,
                load: loadByID[$0.id, default: 0],
                lastTrainedAt: lastDateByID[$0.id]
            )
        }
    }

    public static func normalizeExerciseName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .gymTrimmed
    }

    private static func muscles(_ values: (String, Double)...) -> [MuscleContribution] {
        let validIDs = Set(muscleDefinitions.map(\.id))
        return values.compactMap { id, weight in
            guard validIDs.contains(id) else { return nil }
            return MuscleContribution(muscleID: id, weight: min(1, max(0, weight)))
        }
    }

    private static func containsAny(_ value: String, _ tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }

    private static func isLegCurlName(_ value: String) -> Bool {
        containsAny(value, [
            "згинання ніг", "згибання ніг", "сгибание ног", "сгибания ног",
            "leg curl", "lying leg curl", "seated leg curl"
        ])
    }
}
