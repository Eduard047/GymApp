import Foundation
import XCTest
@testable import GymApp

/// Runs shared/exercise-rest-v1.json (the same cases the Android suite runs) and checks the store.
final class ExerciseRestTimeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "exercise-rest-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        XCTAssertEqual(root["minSeconds"] as? Int, ExerciseRestTime.minimumSeconds)
        XCTAssertEqual(root["maxSeconds"] as? Int, ExerciseRestTime.maximumSeconds)
        XCTAssertEqual(root["stepSeconds"] as? Int, ExerciseRestTime.stepSeconds)
        XCTAssertEqual(root["maxEntries"] as? Int, ExerciseRestTimeStore.maximumEntries)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let stored = item["stored"] as? Int
            XCTAssertEqual(ExerciseRestTime.normalize(stored), item["normalized"] as? Int, id)
            let effective = ExerciseRestTime.effectiveSeconds(stored: stored, defaultSeconds: try XCTUnwrap(item["defaultSeconds"] as? Int))
            XCTAssertEqual(effective, item["effectiveSeconds"] as? Int, id)
            XCTAssertTrue((5...1800).contains(effective), id)
        }
    }

    func testSharedIdentityKeyCasesMatchAndroid() throws {
        let root = try contract()
        let usable = try XCTUnwrap(root["usableIdentityKeys"] as? [String])
        let unusable = try XCTUnwrap(root["unusableIdentityKeys"] as? [String])
        let store = ExerciseRestTimeStore(defaults: defaults)
        for key in usable {
            XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: key), .stored(60), key)
        }
        for key in unusable {
            XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: key), .failed, key)
            XCTAssertNil(store.restSeconds(accountStorageKey: "a", identityKey: key), key)
        }
        XCTAssertEqual(store.restTimes(accountStorageKey: "a").count, usable.count)
    }

    func testStoresClampedSecondsScopedPerAccount() {
        let store = ExerciseRestTimeStore(defaults: defaults)
        XCTAssertEqual(store.setRestSeconds(90, accountStorageKey: "a", identityKey: "k"), .stored(90))
        XCTAssertEqual(store.setRestSeconds(100_000, accountStorageKey: "b", identityKey: "k"), .stored(600))
        XCTAssertEqual(store.setRestSeconds(3, accountStorageKey: "b", identityKey: "j"), .stored(15))
        XCTAssertEqual(store.restSeconds(accountStorageKey: "a", identityKey: "k"), 90)
        XCTAssertEqual(store.restSeconds(accountStorageKey: "b", identityKey: "k"), 600)
        XCTAssertNil(store.restSeconds(accountStorageKey: "c", identityKey: "k"))
        XCTAssertEqual(store.setRestSeconds(nil, accountStorageKey: "a", identityKey: "k"), .removed)
        XCTAssertNil(store.restSeconds(accountStorageKey: "a", identityKey: "k"))
        XCTAssertEqual(store.setRestSeconds(0, accountStorageKey: "b", identityKey: "j"), .removed)
        XCTAssertEqual(store.restTimes(accountStorageKey: "b"), ["k": 600])
    }

    func testClearRemovesOnlyThatAccount() {
        let store = ExerciseRestTimeStore(defaults: defaults)
        store.setRestSeconds(60, accountStorageKey: "a", identityKey: "k")
        store.setRestSeconds(75, accountStorageKey: "b", identityKey: "k")
        store.clear(accountStorageKey: "a")
        XCTAssertTrue(store.restTimes(accountStorageKey: "a").isEmpty)
        XCTAssertEqual(store.restSeconds(accountStorageKey: "b", identityKey: "k"), 75)
    }

    func testThousandEntriesWithMaxLengthCyrillicKeysAllSave() throws {
        let store = ExerciseRestTimeStore(defaults: defaults)
        func key(_ number: Int) -> String {
            let head = "custom:\(String(format: "%04d", number))"
            return head + String(repeating: "Я", count: 512 - head.count)
        }
        XCTAssertEqual(key(0).count, 512)
        XCTAssertTrue(ExerciseCueStore.isUsableIdentityKey(key(0)))
        // 999 entries are seeded in one write; the last two go through setRestSeconds, which checks the cap and the byte limit.
        var seeded: [String: Int] = [:]
        for number in 0 ..< ExerciseRestTimeStore.maximumEntries - 1 { seeded[key(number)] = ExerciseRestTime.maximumSeconds }
        defaults.set(try JSONEncoder().encode(seeded), forKey: "gymapp.exercise-rest.v1.a")
        let last = key(ExerciseRestTimeStore.maximumEntries - 1)
        XCTAssertEqual(store.setRestSeconds(600, accountStorageKey: "a", identityKey: last), .stored(600))
        XCTAssertEqual(store.restTimes(accountStorageKey: "a").count, ExerciseRestTimeStore.maximumEntries)
        XCTAssertEqual(store.restSeconds(accountStorageKey: "a", identityKey: last), 600)
        XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: key(ExerciseRestTimeStore.maximumEntries)), .tooMany)
        XCTAssertEqual(store.setRestSeconds(90, accountStorageKey: "a", identityKey: key(0)), .stored(90))
        XCTAssertEqual(store.restTimes(accountStorageKey: "a").count, ExerciseRestTimeStore.maximumEntries)
    }

    func testRefusesNewEntryBeyondTheCapButStillEditsExisting() {
        let store = ExerciseRestTimeStore(defaults: defaults)
        for index in 0..<ExerciseRestTimeStore.maximumEntries {
            XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: "k\(index)"), .stored(60))
        }
        XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: "extra"), .tooMany)
        XCTAssertNil(store.restSeconds(accountStorageKey: "a", identityKey: "extra"))
        XCTAssertEqual(store.setRestSeconds(120, accountStorageKey: "a", identityKey: "k0"), .stored(120))
        XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "b", identityKey: "k"), .stored(60))
        XCTAssertEqual(store.setRestSeconds(nil, accountStorageKey: "a", identityKey: "k1"), .removed)
        XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "a", identityKey: "extra"), .stored(60))
    }

    func testRejectsUnusableAccount() {
        let store = ExerciseRestTimeStore(defaults: defaults)
        XCTAssertEqual(store.setRestSeconds(60, accountStorageKey: "  ", identityKey: "k"), .failed)
        XCTAssertTrue(store.restTimes(accountStorageKey: "").isEmpty)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-rest-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
