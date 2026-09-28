import XCTest
@testable import GymApp

@MainActor
final class FriendGhostTests: XCTestCase {
    private struct WorkoutFixture {
        let startedAt: String
        let day: String
        let exercises: [SocialFriendWorkoutExercise]
    }

    private func workout(
        _ startedAt: String,
        _ day: String,
        _ exercises: [SocialFriendWorkoutExercise]
    ) -> WorkoutFixture {
        WorkoutFixture(startedAt: startedAt, day: day, exercises: exercises)
    }

    private func page(_ name: String, _ workouts: [WorkoutFixture]) -> SocialFriendWorkoutPage {
        let profileID: String = "p_" + String(repeating: "a", count: 32)
        var items: [SocialFriendWorkout] = []
        for (index, fixture) in workouts.enumerated() {
            var setCount = 0
            for exercise in fixture.exercises {
                setCount += exercise.sets.count
            }
            items.append(
                SocialFriendWorkout(
                    workoutID: "w\(index)-\(name)",
                    startedAt: fixture.startedAt,
                    workoutDay: fixture.day,
                    exerciseCount: fixture.exercises.count,
                    setCount: setCount,
                    durationSeconds: nil,
                    truncated: false,
                    exercises: fixture.exercises
                )
            )
        }
        return SocialFriendWorkoutPage(
            profileID: profileID,
            displayName: name,
            activityRevision: nil,
            items: items,
            nextCursor: nil
        )
    }

    private func exercise(
        _ catalogKey: String?,
        _ name: String,
        weights: [Double],
        reps: [Int]
    ) -> SocialFriendWorkoutExercise {
        var sets: [SocialFriendWorkoutSet] = []
        for index in weights.indices {
            sets.append(SocialFriendWorkoutSet(weightKg: weights[index], reps: reps[index]))
        }
        return SocialFriendWorkoutExercise(catalogKey: catalogKey, name: name, sets: sets)
    }

    func testBuiltInExercisesMatchByCatalogKeyAndCustomOnesByNormalizedName() {
        XCTAssertEqual(FriendGhosts.exerciseKey(catalogKey: "bench_press", name: "Anything"), "catalog:bench_press")
        XCTAssertEqual(FriendGhosts.exerciseKey(catalogKey: nil, name: "Bench Press"), "catalog:bench_press")
        XCTAssertEqual(FriendGhosts.exerciseKey(catalogKey: nil, name: "Жим штанги лежачи"), "catalog:bench_press")
        XCTAssertEqual(
            FriendGhosts.exerciseKey(catalogKey: nil, name: "  Cable   Kickback "),
            FriendGhosts.exerciseKey(catalogKey: nil, name: "cable kickback")
        )
        XCTAssertEqual(FriendGhosts.exerciseKey(catalogKey: "unknown_key", name: "Zercher Carry"), "custom:zercher carry")
    }

    func testLatestWorkoutWinsAcrossFriendsAndTheTopSetIsShown() {
        let sashaBench = exercise("bench_press", "Bench Press", weights: [80, 85, 85], reps: [8, 8, 6])
        let sashaOlderBench = exercise("bench_press", "Bench Press", weights: [90], reps: [3])
        let sasha = page("Саша", [
            workout("2026-09-25T10:00:00Z", "2026-09-25", [sashaBench]),
            workout("2026-09-20T10:00:00Z", "2026-09-20", [sashaOlderBench])
        ])
        let olenaBench = exercise("bench_press", "Bench Press", weights: [60], reps: [10])
        let olenaKickback = exercise(nil, "Cable Kickback", weights: [15], reps: [12])
        let olena = page("Олена", [
            workout("2026-09-22T10:00:00.123Z", "2026-09-22", [olenaBench, olenaKickback])
        ])

        let ghosts = FriendGhosts.ghosts(from: [olena, sasha])

        XCTAssertEqual(ghosts["catalog:bench_press"]?.friendName, "Саша")
        XCTAssertEqual(ghosts["catalog:bench_press"]?.weightKg, 85)
        XCTAssertEqual(ghosts["catalog:bench_press"]?.reps, 8)
        XCTAssertEqual(ghosts["custom:cable kickback"]?.friendName, "Олена")
    }

    func testEmptyExercisesAndUnparseableTimestampsAreSkipped() {
        let squat = exercise("squat", "Squat", weights: [100], reps: [5])
        let emptyDeadlift = exercise("deadlift", "Deadlift", weights: [], reps: [])
        let sasha = page("Саша", [
            workout("not-a-date", "2026-09-25", [squat]),
            workout("2026-09-24T10:00:00Z", "2026-09-24", [emptyDeadlift])
        ])
        let ghosts = FriendGhosts.ghosts(from: [sasha])

        XCTAssertTrue(ghosts.isEmpty)
    }

    func testLineIsLocalizedWithRelativeDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        func ghost(_ weight: Double, _ reps: Int, _ day: String) -> FriendGhost {
            FriendGhost(friendName: "Саша", weightKg: weight, reps: reps, workoutDay: day, startedAt: now)
        }

        XCTAssertEqual(
            FriendGhosts.line(for: ghost(85, 8, "2026-09-25"), now: now, calendar: calendar, languageCode: "ru"),
            "Саша: 85 × 8 · 3 дня назад"
        )
        XCTAssertEqual(
            FriendGhosts.line(for: ghost(82.5, 5, "2026-09-23"), now: now, calendar: calendar, languageCode: "uk"),
            "Саша: 82,5 × 5 · 5 днів тому"
        )
        XCTAssertEqual(
            FriendGhosts.line(for: ghost(82.5, 5, "2026-09-27"), now: now, calendar: calendar, languageCode: "en"),
            "Саша: 82.5 × 5 · yesterday"
        )
        XCTAssertEqual(
            FriendGhosts.line(for: ghost(0, 12, "2026-09-28"), now: now, calendar: calendar, languageCode: "ru"),
            "Саша: 12 повторений · сегодня"
        )
        XCTAssertEqual(
            FriendGhosts.line(for: ghost(100, 1, "2026-09-07"), now: now, calendar: calendar, languageCode: "ru"),
            "Саша: 100 × 1 · 21 день назад"
        )
    }

    func testAtMostTenFriendsAreQueriedMostRecentlyActiveFirst() {
        var friends: [SocialFriendSummary] = []
        for index in 0 ..< 12 {
            let updatedAt: String?
            if index == 11 {
                updatedAt = "2026-09-27T10:00:00Z"
            } else if index == 0 {
                updatedAt = nil
            } else {
                let day: Int = index % 9 + 1
                updatedAt = "2026-09-0\(day)T10:00:00Z"
            }
            let digit: String = String(index % 10)
            let profileID: String = "p_" + String(repeating: digit, count: 32)
            friends.append(
                SocialFriendSummary(
                    friendshipID: "f\(index)",
                    profileID: profileID,
                    displayName: "Friend \(index)",
                    xp: nil,
                    level: nil,
                    workouts: nil,
                    progressShared: true,
                    statsAvailable: true,
                    progressUpdatedAt: updatedAt,
                    friendshipRevision: 1
                )
            )
        }

        let queried = FriendGhostLoader.friendsToQuery(friends)

        XCTAssertEqual(queried.count, FriendGhostLoader.maximumFriends)
        XCTAssertEqual(queried.first?.friendshipID, "f11")
        XCTAssertFalse(queried.contains { $0.friendshipID == "f0" })
    }
}
