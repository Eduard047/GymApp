import Foundation

/// Hero chip of the post-workout summary when the finished workout is the biggest by volume.
enum BiggestWorkoutBadge: String, Equatable, Sendable {
    case ever
    case month
}

/// A logged workout reduced to what the "biggest workout" rule needs: its date and total volume
/// (sum of weight x reps).
struct BiggestWorkoutSession: Equatable, Sendable {
    let date: Date
    let volume: Double
}

/// shared/biggest-workout-v1.json, identical to Android's `biggestWorkoutBadge`.
enum GymBiggestWorkout {
    /// Earlier workouts needed before "biggest ever" means anything.
    static let minEarlierForEver = 3
    /// Earlier workouts in the same calendar month needed before "biggest this month" means anything.
    static let minEarlierForMonth = 2
    private static let epsilon = 1e-9

    /// "ever" when there are at least 3 earlier workouts and `current` is strictly greater than every
    /// one of them, else "month" when at least 2 earlier workouts share `current`'s calendar month in
    /// `calendar` and it is strictly greater than each of them, else nil. A workout without volume
    /// never gets a chip; "ever" wins over "month". `earlier` holds only workouts earlier than `current`.
    static func badge(
        earlier: [BiggestWorkoutSession],
        current: BiggestWorkoutSession,
        calendar: Calendar
    ) -> BiggestWorkoutBadge? {
        guard current.volume > epsilon else { return nil }
        func beatsAll(_ sessions: [BiggestWorkoutSession]) -> Bool {
            sessions.allSatisfy { current.volume > $0.volume + epsilon }
        }
        if earlier.count >= minEarlierForEver, beatsAll(earlier) {
            return .ever
        }
        let sameMonth = earlier.filter {
            calendar.isDate($0.date, equalTo: current.date, toGranularity: .month)
        }
        return sameMonth.count >= minEarlierForMonth && beatsAll(sameMonth) ? .month : nil
    }
}
