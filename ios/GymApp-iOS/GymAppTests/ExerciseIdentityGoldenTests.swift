import Foundation
import XCTest
@testable import GymApp

/// Runs shared/exercise-identity-v1.json, the same cases the Android suite runs.
final class ExerciseIdentityGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let normalized = try XCTUnwrap(item["normalized"] as? String)
            let expectedKey = item["catalogKey"] as? String

            XCTAssertEqual(normalizeExerciseIdentityName(input), normalized, "\(id) normalized")
            XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: input), expectedKey, "\(id) canonicalKey")
            if !normalized.isEmpty {
                // The raw name is authoritative; untrusted catalogKey metadata never overrides it.
                XCTAssertEqual(
                    BuiltInExerciseCatalog.resolvedKey(catalogKey: "bench_press", name: input),
                    expectedKey,
                    "\(id) resolvedKey"
                )
                XCTAssertEqual(
                    BuiltInExerciseCatalog.resolvedKey(catalogKey: nil, name: input),
                    expectedKey,
                    "\(id) resolvedKey no metadata"
                )
            } else {
                // Whitespace-only raw names fall back to the supplied catalog key.
                XCTAssertEqual(
                    BuiltInExerciseCatalog.resolvedKey(catalogKey: "bench_press", name: input),
                    "bench_press",
                    "\(id) resolvedKey falls back to catalogKey"
                )
                XCTAssertNil(BuiltInExerciseCatalog.resolvedKey(catalogKey: nil, name: input), "\(id) resolvedKey nil")
            }
        }
    }

    func testSharedCreateCasesCanonicalizeTypedNames() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["createCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let language = try XCTUnwrap(item["language"] as? String)
            let expectedKey = item["expectedCatalogKey"] as? String

            XCTAssertEqual(
                BuiltInExerciseCatalog.catalogKeyForTypedName(input, languageCode: language),
                expectedKey,
                "\(id) catalogKeyForTypedName"
            )
            let stored = BuiltInExerciseCatalog.canonicalTypedName(input.gymTrimmed, languageCode: language)
            XCTAssertEqual(
                BuiltInExerciseCatalog.canonicalKey(forName: stored),
                expectedKey,
                "\(id) stored name resolves to the same key"
            )
        }
    }

    func testRussianCatalogNamesStaySearchOnlyForIdentity() {
        XCTAssertNil(BuiltInExerciseCatalog.canonicalKey(forName: "Приседания со штангой"))
        XCTAssertEqual(
            BuiltInExerciseCatalog.canonicalTypedName("Приседания со штангой", languageCode: "ru"),
            "Squat"
        )
        XCTAssertEqual(
            BuiltInExerciseCatalog.canonicalTypedName("Приседания со штангой", languageCode: "uk"),
            "Приседания со штангой"
        )
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-identity-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
