import XCTest
@testable import GymApp

/// The Profile "Watches" row status: connected sources joined by " · ",
/// in the Android order Garmin · Apple Watch (Wear OS there) · Health data.
final class WatchesStatusTests: XCTestCase {
    func testNothingConnectedReadsNotConnectedInEveryLanguage() {
        for (language, expected) in [("en", "Not connected"), ("uk", "Не підключено"), ("ru", "Не подключено")] {
            XCTAssertEqual(
                WatchesStatus.summary(
                    garminPaired: false,
                    appleWatchLinked: false,
                    healthConnected: false,
                    languageCode: language
                ),
                expected
            )
        }
    }

    func testGarminOnlyAndHealthOnly() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: false, languageCode: "en"),
            "Garmin"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: false, languageCode: "ru"),
            "Garmin"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: true, languageCode: "en"),
            "Health data"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: true, languageCode: "uk"),
            "Дані про здоров’я"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: true, languageCode: "ru"),
            "Данные о здоровье"
        )
    }

    func testBothSourcesAreJoinedWithMiddleDotGarminFirst() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "en"),
            "Garmin · Health data"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "uk"),
            "Garmin · Дані про здоров’я"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "ru"),
            "Garmin · Данные о здоровье"
        )
    }

    func testAppleWatchOnlyReadsAppleWatchInEveryLanguage() {
        for language in ["en", "uk", "ru"] {
            XCTAssertEqual(
                WatchesStatus.summary(
                    garminPaired: false,
                    appleWatchLinked: true,
                    healthConnected: false,
                    languageCode: language
                ),
                "Apple Watch"
            )
        }
    }

    func testAppleWatchSitsBetweenGarminAndHealthData() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, appleWatchLinked: true, healthConnected: false, languageCode: "en"),
            "Garmin · Apple Watch"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, appleWatchLinked: true, healthConnected: true, languageCode: "en"),
            "Apple Watch · Health data"
        )
    }

    func testAllThreeSourcesFollowTheAndroidOrder() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, appleWatchLinked: true, healthConnected: true, languageCode: "en"),
            "Garmin · Apple Watch · Health data"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, appleWatchLinked: true, healthConnected: true, languageCode: "uk"),
            "Garmin · Apple Watch · Дані про здоров’я"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, appleWatchLinked: true, healthConnected: true, languageCode: "ru"),
            "Garmin · Apple Watch · Данные о здоровье"
        )
    }
}
