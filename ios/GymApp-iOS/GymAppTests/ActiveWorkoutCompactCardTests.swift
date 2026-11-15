import XCTest
@testable import GymApp

final class ActiveWorkoutCompactCardTests: XCTestCase {
    private let nbsp = "\u{00A0}"

    func testDisplayNameBindsShortWordsToTheNextWord() {
        XCTAssertEqual(
            gymExerciseDisplayName("Жим штанги лежа на скамье"),
            "Жим штанги лежа на\(nbsp)скамье"
        )
        XCTAssertEqual(
            gymExerciseDisplayName("Отжимания на брусьях в гравитроне"),
            "Отжимания на\(nbsp)брусьях в\(nbsp)гравитроне"
        )
    }

    func testDisplayNameLeavesOtherNamesAndTrailingShortWordsAlone() {
        XCTAssertEqual(gymExerciseDisplayName("Bench press"), "Bench press")
        XCTAssertEqual(gymExerciseDisplayName("Приседания"), "Приседания")
        XCTAssertEqual(gymExerciseDisplayName("Тяга к"), "Тяга к")
        XCTAssertEqual(gymExerciseDisplayName("На подъём"), "На\(nbsp)подъём")
        XCTAssertEqual(gymExerciseDisplayName(""), "")
    }

    func testRestNotificationsNoteIsOfferedOnlyOncePerInstall() {
        let name = "ActiveWorkoutCompactCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(RestNotificationsNoteStore.shouldOffer(defaults: defaults))
        RestNotificationsNoteStore.markShown(defaults: defaults)
        XCTAssertFalse(RestNotificationsNoteStore.shouldOffer(defaults: defaults))
        RestNotificationsNoteStore.markShown(defaults: defaults)
        XCTAssertFalse(RestNotificationsNoteStore.shouldOffer(defaults: defaults))
    }
}
