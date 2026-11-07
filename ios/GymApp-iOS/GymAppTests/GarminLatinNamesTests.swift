import Foundation
import XCTest
@testable import GymApp

/// Runs shared/garmin-latin-names-v1.json, the same cases the Android suite runs.
final class GarminLatinNamesTests: XCTestCase {
    // Fake catalog built from the fixture so the cases do not depend on the real catalog data.
    private struct FixtureBuiltIns: GarminBuiltInNames {
        var byName: [String: String] = [:]
        var reserved = Set<String>()

        init(_ fixture: [String: Any]) {
            for item in fixture["builtIns"] as? [[String: Any]] ?? [] {
                guard let nameEn = item["nameEn"] as? String else { continue }
                reserved.insert(nameEn.lowercased())
                for name in item["names"] as? [String] ?? [] {
                    byName[name.lowercased()] = nameEn
                    reserved.insert(name.lowercased())
                }
            }
        }

        func nameEn(for raw: String) -> String? { byName[raw.lowercased()] }
        func isReservedLatin(_ latin: String) -> Bool { reserved.contains(latin.lowercased()) }
    }

    func testSwiftTableMatchesTheSharedFixture() throws {
        let fixture = try loadFixture()
        let expected = try XCTUnwrap(fixture["transliteration"] as? [String: String])
        XCTAssertEqual(GarminLatinNames.table, expected)
        let dropped = try XCTUnwrap(fixture["droppedCharacters"] as? [String])
        XCTAssertEqual(Set(GarminLatinNames.dropped.unicodeScalars), Set(dropped.flatMap(\.unicodeScalars)))
        XCTAssertEqual(GarminLatinNames.maxLength, fixture["maxNameLength"] as? Int)
        XCTAssertEqual(GarminLatinNames.fallbackName, fixture["fallbackName"] as? String)
        XCTAssertEqual(garminWatchLanguageTag, fixture["watchLanguage"] as? String)
    }

    func testAssignCasesMatchTheFixture() throws {
        let fixture = try loadFixture()
        let builtIns = FixtureBuiltIns(fixture)
        let cases = try XCTUnwrap(fixture["assignCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let assignment = GarminLatinNames.assign(
                names: try XCTUnwrap(item["names"] as? [String]),
                existing: entries(item["existing"]),
                builtIns: builtIns
            )
            let expected = try XCTUnwrap(item["expected"] as? [String: String])
            XCTAssertEqual(assignment.latinByRaw, expected, id)
            XCTAssertEqual(assignment.newEntries, entries(item["newEntries"]), id)
            for latin in assignment.latinByRaw.values {
                XCTAssertTrue(GarminLatinNames.isAscii(latin), "\(id) ascii")
            }
        }
    }

    func testInvertCasesMatchTheFixture() throws {
        let fixture = try loadFixture()
        let builtIns = FixtureBuiltIns(fixture)
        let cases = try XCTUnwrap(fixture["invertCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let actual = GarminLatinNames.invert(
                try XCTUnwrap(item["latin"] as? String),
                table: entries(item["table"]),
                currentNames: try XCTUnwrap(item["currentNames"] as? [String]),
                builtIns: builtIns
            )
            XCTAssertEqual(actual, item["expected"] as? String, id)
        }
    }

    func testRealCatalogMapsBuiltInsToEnglishAndKeepsRussianNamesCustom() {
        let sets = [
            NamedWorkoutSetDraft(exerciseName: "Станова тяга", weight: 100, reps: 5),
            NamedWorkoutSetDraft(exerciseName: "Жим лёжа", weight: 80, reps: 8)
        ]
        let assignment = GarminLatinNames.assign(names: sets.map(\.exerciseName), existing: [])
        let plan = GarminLatinNames.watchPlan(sets, assignment: assignment)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.last?.exerciseName, "Zhym lyozha")
        XCTAssertTrue(GarminLatinNames.areWatchNamesAscii(plan: plan ?? [], catalog: []))
        // A russian display name of a built-in is not catalog identity, so it is transliterated.
        let russian = GarminLatinNames.assign(names: ["Жим штанги лежа"], existing: [])
        XCTAssertEqual(russian.newEntries.count, 1)
    }

    func testTableIsPrunedOnlyAboveTheCapAndOnlyForDeletedExercises() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarminPhonePlanStore(root: root)
        let first = try XCTUnwrap(store.assignLatinNames(account: "a", names: ["Присед"], currentExerciseNames: ["Присед"]))
        XCTAssertEqual(first.latin(for: "Присед"), "Prysed")
        XCTAssertEqual(try store.loadLatinNames(account: "a"), [GarminLatinEntry(latin: "Prysed", raw: "Присед")])
        // The row survives a reopen and the same raw name keeps its latin name (append-only).
        let again = try XCTUnwrap(GarminPhonePlanStore(root: root)
            .assignLatinNames(account: "a", names: ["Присед"], currentExerciseNames: []))
        XCTAssertEqual(again.latin(for: "Присед"), "Prysed")
        XCTAssertTrue(again.newEntries.isEmpty)
        // retain() keeps the account table; clear() forgets it.
        XCTAssertTrue(store.retain(account: "a", devices: []))
        XCTAssertEqual(try store.loadLatinNames(account: "a").count, 1)
        XCTAssertTrue(store.clear(account: "a"))
        XCTAssertTrue(try store.loadLatinNames(account: "a").isEmpty)
    }

    func testStoredTableStateDecodesWithoutVersion() throws {
        let legacy = try JSONDecoder().decode(
            GarminLatinNameTableState.self,
            from: Data(#"{"entries":[{"latin":"Prysed","raw":"Присед"}]}"#.utf8)
        )
        XCTAssertEqual(legacy.version, 1)
        XCTAssertEqual(legacy.entries.count, 1)
    }

    private func entries(_ value: Any?) -> [GarminLatinEntry] {
        (value as? [[String: String]] ?? []).compactMap { row in
            guard let latin = row["latin"], let raw = row["raw"] else { return nil }
            return GarminLatinEntry(latin: latin, raw: raw)
        }
    }

    private func loadFixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/garmin-latin-names-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
