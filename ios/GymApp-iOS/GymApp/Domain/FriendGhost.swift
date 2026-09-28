import Foundation

/// A friend's latest result on one exercise, shown on the matching exercise
/// card during a workout ("Саша: 85 × 8 · 3 дня назад").
struct FriendGhost: Equatable, Sendable {
    let friendName: String
    let weightKg: Double
    let reps: Int
    /// The friend's workout day, `yyyy-MM-dd`.
    let workoutDay: String
    let startedAt: Date
}

enum FriendGhosts {
    /// Built-in exercises match by catalog key, custom ones by normalized name.
    static func exerciseKey(catalogKey: String?, name: String) -> String {
        if let catalogKey, let definition = BuiltInExerciseCatalog.definition(forKey: catalogKey) {
            return "catalog:\(definition.key)"
        }
        if let key = BuiltInExerciseCatalog.canonicalKey(forName: name) {
            return "catalog:\(key)"
        }
        return "custom:\(normalizeExerciseIdentityName(name))"
    }

    /// The latest result per exercise across the friends' pages. The most
    /// recent workout wins; within it the heaviest set, then the most reps.
    /// Pages come from friends who share workout details; the caller never
    /// passes a page it was not allowed to load.
    static func ghosts(from pages: [SocialFriendWorkoutPage]) -> [String: FriendGhost] {
        var result: [String: FriendGhost] = [:]
        for page in pages {
            for workout in page.items {
                guard let startedAt = parseTimestamp(workout.startedAt) else { continue }
                for exercise in workout.exercises {
                    guard let top = exercise.sets.max(by: { left, right in
                        left.weightKg == right.weightKg ? left.reps < right.reps : left.weightKg < right.weightKg
                    }), top.reps > 0 else { continue }
                    let key = exerciseKey(catalogKey: exercise.catalogKey, name: exercise.name)
                    if let existing = result[key], existing.startedAt >= startedAt { continue }
                    result[key] = FriendGhost(
                        friendName: page.displayName,
                        weightKg: top.weightKg,
                        reps: top.reps,
                        workoutDay: workout.workoutDay,
                        startedAt: startedAt
                    )
                }
            }
        }
        return result
    }

    /// "Саша: 85 × 8 · 3 дня назад"; a bodyweight result reads "Саша: 12 повторений · вчера".
    static func line(
        for ghost: FriendGhost,
        now: Date = Date(),
        calendar: Calendar = .current,
        languageCode: String
    ) -> String {
        let result: String
        if ghost.weightKg > 0 {
            let weight = ghost.weightKg.formatted(
                .number.locale(gymAppLocale(languageCode: languageCode)).precision(.fractionLength(0 ... 2))
            )
            result = "\(weight) × \(ghost.reps)"
        } else {
            result = "\(ghost.reps) " + gymPlural(
                ghost.reps,
                en: ("rep", "reps"),
                uk: ("повторення", "повторення", "повторень"),
                ru: ("повторение", "повторения", "повторений"),
                languageCode: languageCode
            )
        }
        let when = relativeDay(ghost.workoutDay, now: now, calendar: calendar, languageCode: languageCode)
        return "\(ghost.friendName): \(result) · \(when)"
    }

    static func relativeDay(
        _ workoutDay: String,
        now: Date,
        calendar: Calendar,
        languageCode: String
    ) -> String {
        let parts = workoutDay.split(separator: "-").compactMap { Int($0) }
        let days: Int
        if parts.count == 3,
           let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
            days = max(0, calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0)
        } else {
            days = 0
        }
        switch days {
        case 0:
            return gymText("today", "сьогодні", "сегодня", languageCode: languageCode)
        case 1:
            return gymText("yesterday", "учора", "вчера", languageCode: languageCode)
        default:
            let noun = gymPlural(
                days,
                en: ("day", "days"),
                uk: ("день", "дні", "днів"),
                ru: ("день", "дня", "дней"),
                languageCode: languageCode
            )
            return gymText(
                "\(days) \(noun) ago",
                "\(days) \(noun) тому",
                "\(days) \(noun) назад",
                languageCode: languageCode
            )
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
