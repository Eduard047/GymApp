import Foundation

/// Weight/reps wheel rules for the watch set entry.
enum WatchCrownSteps {
    /// The Start row "Weight step" cycles 1 → 2.5 → 5 kg (same as Wear OS).
    static let weightSteps: [Double] = [1, 2.5, 5]
    static let defaultWeightStep = 2.5
    static let wheelWeightRange: ClosedRange<Double> = 0 ... 500
    static let wheelRepsRange: ClosedRange<Int> = 1 ... 100
    /// Values outside the wheel grid (plan targets) are still accepted up to this limit.
    static let maximumWeight = 2_000.0
    static let maximumReps = 999

    static func nextWeightStep(after step: Double) -> Double {
        guard let index = weightSteps.firstIndex(of: step) else { return defaultWeightStep }
        return weightSteps[(index + 1) % weightSteps.count]
    }

    static func validWeightStep(_ step: Double) -> Double {
        weightSteps.contains(step) ? step : defaultWeightStep
    }

    /// Clamped to 0…2000 and rounded to two decimals.
    static func normalizedWeight(_ weight: Double) -> Double {
        guard weight.isFinite else { return 0 }
        let clamped = min(max(weight, 0), maximumWeight)
        return (clamped * 100).rounded() / 100
    }

    static func normalizedReps(_ reps: Int) -> Int {
        min(max(reps, 1), maximumReps)
    }

    /// 0…500 by `step`, plus any off-grid value in `extras` (the planned or current value).
    static func weightOptions(step: Double, including extras: [Double] = []) -> [Double] {
        let safeStep = validWeightStep(step)
        let count = Int((wheelWeightRange.upperBound / safeStep).rounded(.down))
        var values = Set((0 ... count).map { normalizedWeight(Double($0) * safeStep) })
        for extra in extras { values.insert(normalizedWeight(extra)) }
        return values.sorted()
    }

    /// 1…100, plus the current value when it lies outside.
    static func repsOptions(including extras: [Int] = []) -> [Int] {
        var values = Set(wheelRepsRange)
        for extra in extras { values.insert(normalizedReps(extra)) }
        return values.sorted()
    }

    /// Weight for display: decimals only when needed, comma separator for uk/ru.
    static func formatWeight(_ weight: Double, language: String) -> String {
        let value = normalizedWeight(weight)
        let hundredths = Int((value * 100).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        guard fraction != 0 else { return String(whole) }
        let separator = language == "en" ? "." : ","
        let digits = fraction % 10 == 0 ? String(fraction / 10) : String(format: "%02d", fraction)
        return "\(whole)\(separator)\(digits)"
    }

    /// Duration as m:ss, or h:mm:ss from one hour.
    static func formatDuration(seconds: Int64) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%lld:%02lld:%02lld", hours, minutes, secs) }
        return String(format: "%lld:%02lld", minutes, secs)
    }

    /// Volume with thin grouping ("5 240") for uk/ru and a comma group for en ("5,240").
    static func formatVolume(_ kilograms: Double, language: String) -> String {
        let rounded = Int(kilograms.rounded())
        let digits = String(rounded)
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(language == "en" ? "," : "\u{00A0}") }
            grouped.append(character)
        }
        return String(grouped.reversed())
    }
}
