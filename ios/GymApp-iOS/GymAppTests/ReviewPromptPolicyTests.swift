import XCTest
@testable import GymApp

final class ReviewPromptPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func eligible(
        saved: Int = 1,
        sets: Int = 1,
        last: Date? = nil,
        count: Int = 0,
        isDemo: Bool = false
    ) -> Bool {
        ReviewPromptPolicy.isEligible(
            savedWorkoutCount: saved,
            loggedSetsInWorkout: sets,
            lastRequestAt: last,
            requestCount: count,
            now: now,
            isDemo: isDemo
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    func testFirstWorkoutIsEligible() {
        XCTAssertTrue(eligible())
    }

    func testWorkoutWithoutLoggedSetsIsNotEligible() {
        XCTAssertFalse(eligible(sets: 0))
    }

    func testNoSavedWorkoutsIsNotEligible() {
        XCTAssertFalse(eligible(saved: 0))
    }

    func testMinimumGapIs90Days() {
        XCTAssertFalse(eligible(last: daysAgo(89), count: 1))
        XCTAssertTrue(eligible(last: daysAgo(90), count: 1))
    }

    func testThreeRequestsIsTheLimit() {
        XCTAssertTrue(eligible(last: daysAgo(400), count: 2))
        XCTAssertFalse(eligible(last: daysAgo(400), count: 3))
    }

    func testDemoModeIsNotEligible() {
        XCTAssertFalse(eligible(isDemo: true))
    }

    func testStoreRecordsAttempts() throws {
        let suite = "ReviewPromptStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReviewPromptStore(defaults: defaults)
        XCTAssertNil(store.lastRequestAt)
        XCTAssertEqual(store.requestCount, 0)
        store.recordRequest(at: now)
        XCTAssertEqual(store.lastRequestAt, now)
        XCTAssertEqual(store.requestCount, 1)
    }
}
