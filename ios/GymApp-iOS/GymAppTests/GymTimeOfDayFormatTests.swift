import XCTest
@testable import GymApp

final class GymTimeOfDayFormatTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// 2026-08-24 14:05:09 in the current time zone, so the expectation is zone independent.
    private var afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 14, minute: 5, second: 9))!
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testTwentyFourHourFollowsSystemFlagInEveryLanguage() {
        for language in ["en", "uk", "ru"] {
            XCTAssertEqual(
                gymFormattedTimeOfDay(afternoon, languageCode: language, uses24Hour: true),
                "14:05",
                language
            )
        }
    }

    func testTwelveHourFollowsSystemFlagInEveryLanguage() {
        for language in ["en", "uk", "ru"] {
            let text = normalized(gymFormattedTimeOfDay(afternoon, languageCode: language, uses24Hour: false))
            XCTAssertTrue(text.hasPrefix("2:05 "), "\(language): \(text)")
            XCTAssertFalse(text.contains("14"), "\(language): \(text)")
        }
        XCTAssertEqual(
            normalized(gymFormattedTimeOfDay(afternoon, languageCode: "en", uses24Hour: false)),
            "2:05 PM"
        )
    }

    func testSecondsStyleKeepsHourCycle() {
        XCTAssertEqual(
            gymFormattedTimeOfDay(afternoon, time: .standard, languageCode: "en", uses24Hour: true),
            "14:05:09"
        )
    }

    func testDateTimeHelpersUseSystemHourCycleButAppLanguageWords() {
        let english24 = gymFormattedDate(afternoon, date: .abbreviated, time: .shortened, languageCode: "en", uses24Hour: true)
        XCTAssertTrue(english24.contains("14:05"), english24)
        XCTAssertTrue(english24.contains("Aug"), english24)
        let ukrainian12 = normalized(
            gymFormattedTimestamp(afternoon, date: .abbreviated, time: .shortened, languageCode: "uk", uses24Hour: false)
        )
        XCTAssertTrue(ukrainian12.contains("2:05"), ukrainian12)
        XCTAssertTrue(ukrainian12.contains("серп"), ukrainian12)
        let short24 = gymShortDateTime(afternoon, languageCode: "ru", uses24Hour: true)
        XCTAssertTrue(short24.hasSuffix(", 14:05"), short24)
    }

    func testSystemFlagReadsLocaleHourCyclePattern() {
        XCTAssertTrue(gymSystemUses24Hour(locale: Locale(identifier: "uk_UA")))
        XCTAssertFalse(gymSystemUses24Hour(locale: Locale(identifier: "en_US")))
    }
}
