import XCTest
@testable import GymApp

@MainActor
final class FriendGhostTests: XCTestCase {
    private func page(
        _ name: String,
        _ workouts: [(startedAt: String, day: String, exercises: [SocialFriendWorkoutExercise])]
    ) -> SocialFriendWorkoutPage {
        SocialFriendWorkoutPage(
            profileID: "p_" + String(repeating: "a", count: 32),
            displayName: name,
            activityRevision: nil,
            items: workouts.enumerated().map { index, workout in
                SocialFriendWorkout(
                    workoutID: "w\(index)-\(name)",
                    startedAt: workout.startedAt,
                    workoutDay: workout.day,
                    exerciseCount: workout.exercises.count,
                    setCount: workout.exercises.reduce(0) { $0 + $1.sets.count },
                    durationSeconds: nil,
                    truncated: false,
                    exercises: workout.exercises
                )
            },
            nextCursor: nil
        )
    }

    private func exercise(_ catalogKey: String?, _ name: String, _ sets: [(Double, Int)]) -> SocialFriendWorkoutExercise {
        SocialFriendWorkoutExercise(
            catalogKey: catalogKey,
            name: name,
            sets: sets.map { SocialFriendWorkoutSet(weightKg: $0.0, reps: $0.1) }
        )
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
        let sasha = page("Саша", [
            ("2026-09-25T10:00:00Z", "2026-09-25", [exercise("bench_press", "Bench Press", [(80, 8), (85, 8), (85, 6)])]),
            ("2026-09-20T10:00:00Z", "2026-09-20", [exercise("bench_press", "Bench Press", [(90, 3)])])
        ])
        let olena = page("Олена", [
            ("2026-09-22T10:00:00.123Z", "2026-09-22", [
                exercise("bench_press", "Bench Press", [(60, 10)]),
                exercise(nil, "Cable Kickback", [(15, 12)])
            ])
        ])

        let ghosts = FriendGhosts.ghosts(from: [olena, sasha])

        XCTAssertEqual(ghosts["catalog:bench_press"]?.friendName, "Саша")
        XCTAssertEqual(ghosts["catalog:bench_press"]?.weightKg, 85)
        XCTAssertEqual(ghosts["catalog:bench_press"]?.reps, 8)
        XCTAssertEqual(ghosts["custom:cable kickback"]?.friendName, "Олена")
    }

    func testEmptyExercisesAndUnparseableTimestampsAreSkipped() {
        let ghosts = FriendGhosts.ghosts(from: [page("Саша", [
            ("not-a-date", "2026-09-25", [exercise("squat", "Squat", [(100, 5)])]),
            ("2026-09-24T10:00:00Z", "2026-09-24", [exercise("deadlift", "Deadlift", [])])
        ])])

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
        let friends = (0 ..< 12).map { index in
            SocialFriendSummary(
                friendshipID: "f\(index)",
                profileID: "p_" + String(repeating: String(index % 10), count: 32),
                displayName: "Friend \(index)",
                xp: nil,
                level: nil,
                workouts: nil,
                progressShared: true,
                statsAvailable: true,
                progressUpdatedAt: index == 11 ? "2026-09-27T10:00:00Z" : (index == 0 ? nil : "2026-09-0\(index % 9 + 1)T10:00:00Z"),
                friendshipRevision: 1
            )
        }

        let queried = FriendGhostLoader.friendsToQuery(friends)

        XCTAssertEqual(queried.count, FriendGhostLoader.maximumFriends)
        XCTAssertEqual(queried.first?.friendshipID, "f11")
        XCTAssertFalse(queried.contains { $0.friendshipID == "f0" })
    }
}
