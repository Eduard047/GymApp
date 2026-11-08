import Foundation
import XCTest
@testable import GymApp

/// Runs shared/exercise-cue-v1.json (the same cases the Android suite runs) and checks the store.
final class ExerciseCueStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "exercise-cue-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        XCTAssertEqual(root["maxCodePoints"] as? Int, ExerciseCue.maximumCodePoints)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let expected = item["stored"] as? String
            XCTAssertEqual(ExerciseCue.normalize(input), expected, id)
        }
    }

    func testSharedIdentityKeyCasesMatchAndroid() throws {
        let root = try contract()
        let usable = try XCTUnwrap(root["usableIdentityKeys"] as? [String])
        let unusable = try XCTUnwrap(root["unusableIdentityKeys"] as? [String])
        XCTAssertGreaterThanOrEqual(usable.count, 3)
        XCTAssertGreaterThanOrEqual(unusable.count, 4)
        let store = ExerciseCueStore(defaults: defaults)
        for key in usable { XCTAssertTrue(ExerciseCueStore.isUsableIdentityKey(key), key) }
        for key in unusable {
            XCTAssertFalse(ExerciseCueStore.isUsableIdentityKey(key), key)
            XCTAssertEqual(store.setCue("x", accountStorageKey: "a", identityKey: key), .failed, key)
        }
        XCTAssertNil(defaults.data(forKey: "gymapp.exercise-cues.v1.a"))
    }

    func testSavesTrimmedSingleLineTextAndReadsItBack() {
        let store = ExerciseCueStore(defaults: defaults)
        XCTAssertEqual(store.setCue("  seat 4\nnarrow ", accountStorageKey: "a", identityKey: "k"), .stored("seat 4 narrow"))
        XCTAssertEqual(store.cues(accountStorageKey: "a"), ["k": "seat 4 narrow"])
        XCTAssertEqual(store.cue(accountStorageKey: "a", identityKey: "k"), "seat 4 narrow")
    }

    func testEmptyTextRemovesTheCue() {
        let store = ExerciseCueStore(defaults: defaults)
        store.setCue("seat 4", accountStorageKey: "a", identityKey: "k")
        XCTAssertEqual(store.setCue(" \n ", accountStorageKey: "a", identityKey: "k"), .removed)
        XCTAssertNil(store.cue(accountStorageKey: "a", identityKey: "k"))
        XCTAssertNil(defaults.data(forKey: "gymapp.exercise-cues.v1.a"))
    }

    func testCuesDoNotLeakAcrossAccounts() {
        let store = ExerciseCueStore(defaults: defaults)
        store.setCue("mine", accountStorageKey: "a", identityKey: "k")
        XCTAssertNil(store.cue(accountStorageKey: "b", identityKey: "k"))
        store.setCue("other", accountStorageKey: "b", identityKey: "k")
        XCTAssertEqual(store.cue(accountStorageKey: "a", identityKey: "k"), "mine")
        XCTAssertEqual(store.cue(accountStorageKey: "b", identityKey: "k"), "other")
    }

    func testClearWipesOnlyThatAccount() {
        let store = ExerciseCueStore(defaults: defaults)
        store.setCue("one", accountStorageKey: "a", identityKey: "k1")
        store.setCue("two", accountStorageKey: "a", identityKey: "k2")
        store.setCue("keep", accountStorageKey: "b", identityKey: "k1")
        store.clear(accountStorageKey: "a")
        XCTAssertNil(store.cue(accountStorageKey: "a", identityKey: "k1"))
        XCTAssertNil(store.cue(accountStorageKey: "a", identityKey: "k2"))
        XCTAssertEqual(store.cue(accountStorageKey: "b", identityKey: "k1"), "keep")
    }

    func testRejectsUnusableAccountOrKey() {
        let store = ExerciseCueStore(defaults: defaults)
        XCTAssertEqual(store.setCue("x", accountStorageKey: "", identityKey: "k"), .failed)
        XCTAssertEqual(store.setCue("x", accountStorageKey: "a", identityKey: "  "), .failed)
        XCTAssertEqual(store.setCue("x", accountStorageKey: "a", identityKey: "k\u{0}"), .failed)
        XCTAssertNil(defaults.data(forKey: "gymapp.exercise-cues.v1.a"))
    }

    func testThousandEntriesWithMaxLengthCyrillicKeysAndCuesAllSave() throws {
        let store = ExerciseCueStore(defaults: defaults)
        let cue = String(repeating: "ж", count: ExerciseCue.maximumCodePoints)
        func key(_ number: Int) -> String {
            let head = "custom:\(String(format: "%04d", number))"
            return head + String(repeating: "Я", count: 512 - head.count)
        }
        XCTAssertEqual(key(0).count, 512)
        XCTAssertTrue(ExerciseCueStore.isUsableIdentityKey(key(0)))
        // 999 entries are seeded in one write; the last two go through setCue, which checks the cap and the byte limit.
        var seeded: [String: String] = [:]
        for number in 0 ..< ExerciseCueStore.maximumEntries - 1 { seeded[key(number)] = cue }
        defaults.set(try JSONEncoder().encode(seeded), forKey: "gymapp.exercise-cues.v1.a")
        let last = key(ExerciseCueStore.maximumEntries - 1)
        XCTAssertEqual(store.setCue(cue, accountStorageKey: "a", identityKey: last), .stored(cue))
        XCTAssertEqual(store.cues(accountStorageKey: "a").count, ExerciseCueStore.maximumEntries)
        XCTAssertEqual(store.cue(accountStorageKey: "a", identityKey: last), cue)
        XCTAssertEqual(store.cue(accountStorageKey: "a", identityKey: key(0)), cue)
        XCTAssertEqual(store.setCue(cue, accountStorageKey: "a", identityKey: key(ExerciseCueStore.maximumEntries)), .tooMany)
        XCTAssertEqual(store.setCue("новий", accountStorageKey: "a", identityKey: key(0)), .stored("новий"))
        XCTAssertEqual(store.cues(accountStorageKey: "a").count, ExerciseCueStore.maximumEntries)
    }

    func testRefusesNewCueBeyondTheEntryCapButStillEditsExisting() {
        let store = ExerciseCueStore(defaults: defaults)
        for index in 0..<ExerciseCueStore.maximumEntries {
            store.setCue("x", accountStorageKey: "a", identityKey: "k\(index)")
        }
        XCTAssertEqual(store.setCue("x", accountStorageKey: "a", identityKey: "extra"), .tooMany)
        XCTAssertNil(store.cue(accountStorageKey: "a", identityKey: "extra"))
        XCTAssertEqual(store.setCue("changed", accountStorageKey: "a", identityKey: "k0"), .stored("changed"))
        XCTAssertEqual(store.setCue("x", accountStorageKey: "b", identityKey: "extra"), .stored("x"))
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-cue-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
