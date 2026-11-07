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

    func testSavesTrimmedSingleLineTextAndReadsItBack() {
        let store = ExerciseCueStore(defaults: defaults)
        XCTAssertEqual(store.setCue("  seat 4\nnarrow ", accountStorageKey: "a", identityKey: "k"), "seat 4 narrow")
        XCTAssertEqual(store.cue(accountStorageKey: "a", identityKey: "k"), "seat 4 narrow")
    }

    func testEmptyTextRemovesTheCue() {
        let store = ExerciseCueStore(defaults: defaults)
        store.setCue("seat 4", accountStorageKey: "a", identityKey: "k")
        XCTAssertNil(store.setCue(" \n ", accountStorageKey: "a", identityKey: "k"))
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
        XCTAssertNil(store.setCue("x", accountStorageKey: "", identityKey: "k"))
        XCTAssertNil(store.setCue("x", accountStorageKey: "a", identityKey: "  "))
        XCTAssertNil(store.setCue("x", accountStorageKey: "a", identityKey: "k\u{0}"))
        XCTAssertNil(defaults.data(forKey: "gymapp.exercise-cues.v1.a"))
    }

    func testRefusesNewCueBeyondTheEntryCapButStillEditsExisting() {
        let store = ExerciseCueStore(defaults: defaults)
        for index in 0..<ExerciseCueStore.maximumEntries {
            store.setCue("x", accountStorageKey: "a", identityKey: "k\(index)")
        }
        XCTAssertNil(store.setCue("x", accountStorageKey: "a", identityKey: "extra"))
        XCTAssertEqual(store.setCue("changed", accountStorageKey: "a", identityKey: "k0"), "changed")
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
