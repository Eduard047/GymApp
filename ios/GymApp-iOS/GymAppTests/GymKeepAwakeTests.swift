import SwiftUI
import XCTest
@testable import GymApp

final class GymKeepAwakeTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "GymKeepAwakeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testKeepScreenOnIsOnByDefaultAndFollowsTheStoredPreference() {
        let defaults = makeDefaults()
        XCTAssertTrue(GymKeepAwake.isEnabled(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: GymKeepAwake.preferenceKey))
        defaults.set(false, forKey: GymKeepAwake.preferenceKey)
        XCTAssertFalse(GymKeepAwake.isEnabled(defaults: defaults))
        defaults.set(true, forKey: GymKeepAwake.preferenceKey)
        XCTAssertTrue(GymKeepAwake.isEnabled(defaults: defaults))
    }

    func testScreenIsHeldOnlyWhileEnabledAndTheAppIsActive() {
        XCTAssertTrue(GymKeepAwake.shouldHoldScreen(enabled: true, scenePhase: .active))
        XCTAssertFalse(GymKeepAwake.shouldHoldScreen(enabled: true, scenePhase: .inactive))
        XCTAssertFalse(GymKeepAwake.shouldHoldScreen(enabled: true, scenePhase: .background))
        XCTAssertFalse(GymKeepAwake.shouldHoldScreen(enabled: false, scenePhase: .active))
    }

    func testPreferenceKeyIsSeparateFromHaptics() {
        XCTAssertNotEqual(GymKeepAwake.preferenceKey, GymHaptics.preferenceKey)
    }
}
