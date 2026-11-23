import XCTest
@testable import GymApp

/// The Profile "Watches" row status: connected sources joined by " · ".
final class WatchesStatusTests: XCTestCase {
    func testNothingConnectedReadsNotConnectedInEveryLanguage() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: false, languageCode: "en"),
            "Not connected"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: false, languageCode: "uk"),
            "Не підключено"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: false, languageCode: "ru"),
            "Не подключено"
        )
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
            "Дані здоров’я"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: false, healthConnected: true, languageCode: "ru"),
            "Данные здоровья"
        )
    }

    func testBothSourcesAreJoinedWithMiddleDotGarminFirst() {
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "en"),
            "Garmin · Health data"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "uk"),
            "Garmin · Дані здоров’я"
        )
        XCTAssertEqual(
            WatchesStatus.summary(garminPaired: true, healthConnected: true, languageCode: "ru"),
            "Garmin · Данные здоровья"
        )
    }
}
