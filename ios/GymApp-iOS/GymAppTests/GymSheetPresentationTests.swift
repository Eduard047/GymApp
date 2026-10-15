import SwiftUI
import XCTest
@testable import GymApp

final class GymSheetPresentationTests: XCTestCase {
    func testSizeToDetentMapping() {
        XCTAssertEqual(GymSheetSize.standard.detents, [.medium, .large])
        XCTAssertEqual(GymSheetSize.full.detents, [.large])
        XCTAssertEqual(GymSheetSize.compact.detents, [.medium])
        XCTAssertEqual(GymSheetSize.height(320).detents, [.height(320)])
        XCTAssertEqual(GymSheetStyle.topCornerRadius, 32)
    }

    /// Every sheet takes its detents, drag handle, radius and material from the
    /// shared modifier; raw presentation modifiers may only live in its file.
    func testNoRawSheetPresentationModifiersOutsideSharedModifier() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GymApp")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            if url.lastPathComponent == "GymSheetPresentation.swift" { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in ["presentationDetents(", "presentationDragIndicator(", "presentationCornerRadius("]
            where text.contains(token) {
                offenders.append("\(url.lastPathComponent): \(token)")
            }
        }
        XCTAssertEqual(offenders, [])
    }
}
