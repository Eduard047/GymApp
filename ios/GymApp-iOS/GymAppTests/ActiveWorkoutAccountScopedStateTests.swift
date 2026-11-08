import Foundation
import XCTest
@testable import GymApp

/// The active workout keeps per-account cue and rest maps in state; they must read as empty for any other account.
final class ActiveWorkoutAccountScopedStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "account-scoped-state-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEntriesAreVisibleOnlyForTheirOwner() {
        let map = AccountScopedMap(ownerKey: "account-a", entries: ["bench": 90])
        XCTAssertEqual(map.entries(forOwner: "account-a"), ["bench": 90])
        XCTAssertEqual(map.entries(forOwner: "account-b"), [:])
        XCTAssertEqual(AccountScopedMap<Int>.empty.entries(forOwner: "account-a"), [:])
    }

    func testApplyingUpdatesOnlyAMapOfTheSameOwner() throws {
        let map = AccountScopedMap(ownerKey: "account-a", entries: ["bench": 90])
        let stored = try XCTUnwrap(map.applying(key: "squat", value: 120, forOwner: "account-a"))
        XCTAssertEqual(stored.entries(forOwner: "account-a"), ["bench": 90, "squat": 120])
        let removed = try XCTUnwrap(stored.applying(key: "bench", value: nil, forOwner: "account-a"))
        XCTAssertEqual(removed.entries(forOwner: "account-a"), ["squat": 120])
        XCTAssertNil(map.applying(key: "squat", value: 120, forOwner: "account-b"), "a stale map must be reloaded")
    }

    func testRestCacheServesStoredValuesAndFollowsInvalidationAndAccountSwitch() {
        let store = ExerciseRestTimeStore(defaults: defaults)
        let cache = ExerciseRestTimesCache(makeStore: { ExerciseRestTimeStore(defaults: self.defaults) })
        store.setRestSeconds(90, accountStorageKey: "account-a", identityKey: "bench")
        store.setRestSeconds(45, accountStorageKey: "account-b", identityKey: "bench")

        XCTAssertEqual(cache.restSeconds(accountStorageKey: "account-a", identityKey: "bench"), 90)
        XCTAssertEqual(cache.restSeconds(accountStorageKey: "account-b", identityKey: "bench"), 45)
        XCTAssertEqual(cache.restSeconds(accountStorageKey: "account-a", identityKey: "bench"), 90)

        store.setRestSeconds(120, accountStorageKey: "account-a", identityKey: "bench")
        XCTAssertEqual(cache.restSeconds(accountStorageKey: "account-a", identityKey: "bench"), 90, "cached until invalidated")
        cache.invalidate()
        XCTAssertEqual(cache.restSeconds(accountStorageKey: "account-a", identityKey: "bench"), 120)
        XCTAssertNil(cache.restSeconds(accountStorageKey: "account-a", identityKey: "squat"))
    }
}
