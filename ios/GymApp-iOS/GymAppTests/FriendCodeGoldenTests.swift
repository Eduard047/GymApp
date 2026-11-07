import Foundation
import XCTest
@testable import GymApp

/// Runs shared/friend-code-v1.json, the same cases the Android suite runs.
final class FriendCodeGoldenTests: XCTestCase {
    func testSharedNormalizeCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["normalizeCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 40)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let expected = item["normalized"] as? String
            XCTAssertEqual(SocialFriendCode.normalize(input), expected, id)
        }
    }

    func testSharedDisplayCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["displayCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 3)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let canonical = try XCTUnwrap(item["canonical"] as? String)
            let display = try XCTUnwrap(item["display"] as? String)
            XCTAssertEqual(SocialFriendCode.display(canonical), display, id)
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/friend-code-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
