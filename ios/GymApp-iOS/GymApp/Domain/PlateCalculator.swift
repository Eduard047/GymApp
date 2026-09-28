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
        let totalUnits = total.isFinite ? Int((total * 100).rounded()) : 0
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
