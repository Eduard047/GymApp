import SwiftUI
import XCTest
@testable import GymApp

final class GymHapticsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "GymHapticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testHapticsAreOnByDefaultAndFollowTheStoredPreference() {
        let defaults = makeDefaults()
        XCTAssertTrue(GymHaptics.isEnabled(defaults: defaults))
        defaults.set(false, forKey: GymHaptics.preferenceKey)
        XCTAssertFalse(GymHaptics.isEnabled(defaults: defaults))
        defaults.set(true, forKey: GymHaptics.preferenceKey)
        XCTAssertTrue(GymHaptics.isEnabled(defaults: defaults))
    }

    func testDisabledHapticsResolveToNoFeedback() {
        XCTAssertNil(GymHaptics.resolved(.success, enabled: false))
        XCTAssertNil(GymHaptics.resolved(.selection, enabled: false))
        XCTAssertNotNil(GymHaptics.resolved(.success, enabled: true))
    }

    func testAppGeneratedHapticsAllGoThroughTheGatedHelper() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GymApp")
        guard let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            throw XCTSkip("Source tree is not available")
        }
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            guard url.lastPathComponent != "GymHaptics.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(".sensoryFeedback(") || text.contains("UIImpactFeedbackGenerator")
                || text.contains("UINotificationFeedbackGenerator") || text.contains("UISelectionFeedbackGenerator") {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(offenders, [], "use gymSensoryFeedback so the Haptics switch applies")
    }
}
