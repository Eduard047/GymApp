import Foundation

/// How a barbell total splits into plates on each side of the bar.
struct PlateLoad: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The total is lighter than the empty bar.
        case belowBar
        /// The total is exactly the empty bar.
        case barOnly
        /// Plates are needed on each side.
        case loaded
    }

    let status: Status
    /// Heaviest first, one side of the bar.
    let platesPerSide: [Double]
    /// Weight per side the available plates cannot make up.
    let remainderPerSide: Double
}

/// Splits a barbell total into standard plates per side (20 kg bar; 25, 20, 15,
/// 10, 5, 2.5, and 1.25 kg plates). Every plate is a multiple of the smallest
/// one, so filling greedily from the heaviest leaves the smallest remainder.
enum PlateCalculator {
    static let barWeight = 20.0
    static let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    static func load(total: Double, bar: Double = barWeight, plates: [Double] = plates) -> PlateLoad {
        // Work in hundredths of a kilogram so 2.5 and 1.25 add up exactly.
        // A non-finite or absurdly large total is invalid input; it must not trap in Int().
        let totalUnits = total.isFinite && total <= ActiveWorkoutStore.maximumWeight
            ? Int((total * 100).rounded())
            : 0
        let barUnits = Int((bar * 100).rounded())
        guard totalUnits >= barUnits else {
            return PlateLoad(status: .belowBar, platesPerSide: [], remainderPerSide: 0)
        }
        // An odd hundredth cannot be split evenly; the leftover half stays in the remainder.
        var remainingUnits = (totalUnits - barUnits) / 2
        guard remainingUnits > 0 else {
            return PlateLoad(status: .barOnly, platesPerSide: [], remainderPerSide: 0)
        }
        var perSide: [Double] = []
        for plate in plates.sorted(by: >) {
            let plateUnits = Int((plate * 100).rounded())
            guard plateUnits > 0 else { continue }
            while remainingUnits >= plateUnits {
                perSide.append(plate)
                remainingUnits -= plateUnits
            }
        }
        return PlateLoad(
            status: .loaded,
            platesPerSide: perSide,
            remainderPerSide: Double(remainingUnits) / 100
        )
    }

    /// One read-only warm-up step: the loaded total, its reps, and the plates on each side.
    struct WarmupStep: Equatable, Sendable {
        let weight: Double
        let reps: Int
        let load: PlateLoad
    }

    /// The ramp is skipped unless the working weight is more than this many kg above the bar.
    static let warmupMinimumAboveBar = 20.0
    private static let warmupBarReps = 10
    /// Share of the working weight (in percent) and reps for each step after the empty bar.
    private static let warmupRamp: [(percent: Int, reps: Int)] = [(50, 5), (70, 3), (85, 1)]

    /// Read-only warm-up for `workingWeight`: bar x 10, then 50% x 5, 70% x 3, 85% x 1, each rounded
    /// down to what `plates` can load (the same greedy fill as `load`). Steps at or below the bar, at
    /// or above the working weight, or equal to an earlier step are dropped; no steps at all when the
    /// working weight is at most `warmupMinimumAboveBar` over the bar. Matches Android
    /// (shared/warmup-ramp-v1.json).
    static func warmup(
        workingWeight: Double,
        bar: Double = barWeight,
        plates: [Double] = plates
    ) -> [WarmupStep] {
        // Hundredths of a kilogram, like `load`; invalid weights produce no ramp.
        let workingUnits = workingWeight.isFinite && workingWeight <= ActiveWorkoutStore.maximumWeight
            ? Int((workingWeight * 100).rounded())
            : 0
        let barUnits = Int((bar * 100).rounded())
        guard workingUnits > barUnits + Int((warmupMinimumAboveBar * 100).rounded()) else { return [] }
        var steps = [WarmupStep(weight: bar, reps: warmupBarReps, load: load(total: bar, bar: bar, plates: plates))]
        var seenUnits: Set<Int> = [barUnits]
        for (percent, reps) in warmupRamp {
            let target = load(total: Double(workingUnits * percent / 100) / 100, bar: bar, plates: plates)
            guard target.status == .loaded else { continue }
            let loadedUnits = barUnits + 2 * target.platesPerSide.reduce(0) { $0 + Int(($1 * 100).rounded()) }
            guard loadedUnits > barUnits, loadedUnits < workingUnits, seenUnits.insert(loadedUnits).inserted else {
                continue
            }
            steps.append(WarmupStep(
                weight: Double(loadedUnits) / 100,
                reps: reps,
                load: PlateLoad(status: .loaded, platesPerSide: target.platesPerSide, remainderPerSide: 0)
            ))
        }
        return steps
    }

    /// Plate math applies only to built-in barbell exercises.
    static func applies(toCatalogKey catalogKey: String?) -> Bool {
        guard let catalogKey else { return false }
        return RecommendationEngine.builtInEquipment[catalogKey] == .barbell
    }

    /// "На каждую сторону: 25 + 5 + 1,25", plus a remainder line when the
    /// plates cannot make the exact weight.
    static func summaryLines(for load: PlateLoad, languageCode: String) -> [String] {
        let locale = gymAppLocale(languageCode: languageCode)
        func number(_ value: Double) -> String {
            value.formatted(.number.locale(locale).precision(.fractionLength(0 ... 2)))
        }
        let bar = gymWeightText(barWeight, languageCode: languageCode)
        switch load.status {
        case .belowBar:
            return [gymText(
                "Less than the \(bar) bar",
                "Менше за гриф \(bar)",
                "Меньше грифа \(bar)",
                languageCode: languageCode
            )]
        case .barOnly:
            return [gymText(
                "Bar only (\(bar))",
                "Лише гриф (\(bar))",
                "Только гриф (\(bar))",
                languageCode: languageCode
            )]
        case .loaded:
            var lines: [String] = []
            if !load.platesPerSide.isEmpty {
                let plates = load.platesPerSide.map(number).joined(separator: " + ")
                lines.append(gymText(
                    "Per side: \(plates)",
                    "На кожну сторону: \(plates)",
                    "На каждую сторону: \(plates)",
                    languageCode: languageCode
                ))
            }
            if load.remainderPerSide > 0 {
                let remainder = gymWeightText(load.remainderPerSide, languageCode: languageCode)
                lines.append(gymText(
                    "Remainder: \(remainder) per side",
                    "Залишок: \(remainder) на сторону",
                    "Остаток: \(remainder) на сторону",
                    languageCode: languageCode
                ))
            }
            return lines
        }
    }
}
