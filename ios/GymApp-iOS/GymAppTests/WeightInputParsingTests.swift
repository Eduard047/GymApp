import XCTest
@testable import GymApp

final class WeightInputParsingTests: XCTestCase {
    func testAcceptsBothDecimalSeparators() {
        XCTAssertEqual(GymWeightFieldFormat.parse("2,5"), 2.5)
        XCTAssertEqual(GymWeightFieldFormat.parse("2.5"), 2.5)
        XCTAssertEqual(GymWeightFieldFormat.parse("1,25"), 1.25)
        XCTAssertEqual(GymWeightFieldFormat.parse(" 82,5 "), 82.5)
        XCTAssertEqual(GymWeightFieldFormat.parse(" 80 "), 80)
    }

    func testZeroIsValidBodyweightValue() {
        XCTAssertEqual(GymWeightFieldFormat.parse("0"), 0)
    }

    func testRejectsBlankAndGarbage() {
        XCTAssertNil(GymWeightFieldFormat.parse(""))
        XCTAssertNil(GymWeightFieldFormat.parse("   "))
        XCTAssertNil(GymWeightFieldFormat.parse("abc"))
        XCTAssertNil(GymWeightFieldFormat.parse("2,5,0"))
        XCTAssertNil(GymWeightFieldFormat.parse("2.5.0"))
    }

    func testRejectsNonFiniteNegativeAndOutOfRange() {
        XCTAssertNil(GymWeightFieldFormat.parse("NaN"))
        XCTAssertNil(GymWeightFieldFormat.parse("Infinity"))
        XCTAssertNil(GymWeightFieldFormat.parse("-Infinity"))
        XCTAssertNil(GymWeightFieldFormat.parse("-5"))
        XCTAssertNil(GymWeightFieldFormat.parse("-0.01"))
        XCTAssertEqual(GymWeightFieldFormat.parse("1000000"), 1_000_000)
        XCTAssertNil(GymWeightFieldFormat.parse("1000000.01"))
        XCTAssertNil(GymWeightFieldFormat.parse(String(repeating: "1", count: 65)))
    }

    func testFormatStyleParseThrowsOnInvalid() throws {
        let style = GymWeightFieldFormat(languageCode: "ru")
        XCTAssertEqual(try style.parseStrategy.parse("2,5"), 2.5)
        XCTAssertThrowsError(try style.parseStrategy.parse("abc"))
    }
}
