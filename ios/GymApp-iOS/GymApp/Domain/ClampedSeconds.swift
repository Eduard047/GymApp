import Foundation

/// Converts a persisted `TimeInterval` to whole seconds without trapping.
/// Non-finite values (NaN, +/-infinity) become 0; finite values are rounded up
/// (so a partial second still counts) and clamped to `0...maximum`.
func gymClampedSeconds(_ interval: TimeInterval, max maximum: Int) -> Int {
    guard interval.isFinite, maximum > 0 else { return 0 }
    let upper = TimeInterval(maximum)
    guard interval > 0 else { return 0 }
    guard interval < upper else { return maximum }
    return min(Int(interval.rounded(.up)), maximum)
}

/// Whole seconds elapsed between two dates, truncated (matches the previous
/// `Int(...)` behaviour), clamped to `0...7 days`, never trapping on corrupt dates.
func gymElapsedWholeSeconds(from start: Date, to end: Date) -> Int {
    let maximum = 7 * 24 * 60 * 60
    let interval = end.timeIntervalSince(start)
    guard interval.isFinite, interval > 0 else { return 0 }
    guard interval < TimeInterval(maximum) else { return maximum }
    return Int(interval)
}
