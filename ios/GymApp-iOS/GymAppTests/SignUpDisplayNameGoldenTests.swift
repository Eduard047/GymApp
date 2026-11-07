import Foundation
import XCTest
@testable import GymApp

/// Runs shared/display-name-v1.json, the same cases the Android suite and the node mirror test run.
final class SignUpDisplayNameGoldenTests: XCTestCase {
    func testSharedNameCasesMatchAndroidAndServerRules() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 40)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let actual = AuthDisplayNameRule.checkSignUp(input)
            if let normalized = item["normalized"] as? String {
                XCTAssertEqual(actual, .valid(normalized), id)
            } else {
                let reason = try XCTUnwrap(item["reason"] as? String, id)
                let expected: AuthDisplayNameRule.SignUpRejection
                switch reason {
                case "length": expected = .length
                case "characters": expected = .characters
                default: expected = .serverRules
                }
                XCTAssertEqual(actual, .rejected(expected), id)
            }
        }
    }

    func testSharedDraftCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["draftCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let draft = try XCTUnwrap(item["draft"] as? String)
            XCTAssertEqual(AuthDisplayNameRule.sanitizedDraft(input), draft, id)
        }
    }

    func testServerRuleMessageIsLocalized() throws {
        let english = try XCTUnwrap(AuthServiceError.unsafeDisplayName.errorDescription)
        XCTAssertEqual(english, "Name can't contain links or long numbers and needs a letter or digit.")
        XCTAssertEqual(
            gymLocalized(english, languageCode: "uk"),
            "Ім’я не може містити посилань чи довгих чисел і має містити літеру або цифру."
        )
        XCTAssertEqual(
            gymLocalized(english, languageCode: "ru"),
            "Имя не может содержать ссылок или длинных чисел и должно содержать букву или цифру."
        )
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/display-name-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
