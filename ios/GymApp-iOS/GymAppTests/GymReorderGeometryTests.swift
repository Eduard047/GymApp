import XCTest
@testable import GymApp

final class GymReorderGeometryTests: XCTestCase {
    private let heights: [CGFloat] = [100, 200, 100, 150]
    private let spacing: CGFloat = 10

    func testSlotStaysUntilCentreCrossesNeighbourMidpoint() {
        // Dragging item 0 down: next midpoint is 50 + 10 + 100 = 160 away.
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 0, heights: heights, spacing: spacing), 0)
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 160, heights: heights, spacing: spacing), 0)
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 161, heights: heights, spacing: spacing), 1)
        // Passing item 1 adds 200 + 10, so item 2 midpoint: 60 + 210 + 50 = 320.
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 320, heights: heights, spacing: spacing), 1)
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 321, heights: heights, spacing: spacing), 2)
    }

    func testSlotMovesSeveralPlacesUpAndDown() {
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 3, offset: -1_000, heights: heights, spacing: spacing), 0)
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 0, offset: 1_000, heights: heights, spacing: spacing), 3)
        // Up from the last item: first midpoint is 75 + 10 + 50 = 135 away.
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 3, offset: -135, heights: heights, spacing: spacing), 3)
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 3, offset: -136, heights: heights, spacing: spacing), 2)
    }

    func testSlotIgnoresOutOfRangeOrigin() {
        XCTAssertEqual(GymReorderGeometry.slotIndex(origin: 9, offset: 500, heights: heights, spacing: spacing), 9)
    }

    func testLayoutDeltaIsSumOfPassedNeighbours() {
        XCTAssertEqual(GymReorderGeometry.layoutDelta(origin: 0, target: 2, heights: heights, spacing: spacing), 320)
        XCTAssertEqual(GymReorderGeometry.layoutDelta(origin: 3, target: 1, heights: heights, spacing: spacing), -320)
        XCTAssertEqual(GymReorderGeometry.layoutDelta(origin: 1, target: 1, heights: heights, spacing: spacing), 0)
        XCTAssertEqual(GymReorderGeometry.layoutDelta(origin: 1, target: 9, heights: heights, spacing: spacing), 0)
    }

    func testNeighbourShiftOpensTheSlot() {
        // Origin 1 dragged down to slot 3: items 2 and 3 move up by the extent.
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 0, origin: 1, slot: 3, draggedExtent: 210), 0)
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 2, origin: 1, slot: 3, draggedExtent: 210), -210)
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 3, origin: 1, slot: 3, draggedExtent: 210), -210)
        // Origin 2 dragged up to slot 0: items 0 and 1 move down.
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 0, origin: 2, slot: 0, draggedExtent: 110), 110)
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 1, origin: 2, slot: 0, draggedExtent: 110), 110)
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 3, origin: 2, slot: 0, draggedExtent: 110), 0)
        XCTAssertEqual(GymReorderGeometry.neighbourShift(index: 1, origin: 2, slot: 2, draggedExtent: 110), 0)
    }

    func testAutoScrollStepIsProportionalAndCapped() {
        let top: CGFloat = 100
        let bottom: CGFloat = 700
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 400, visibleTop: top, visibleBottom: bottom), 0)
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 164, visibleTop: top, visibleBottom: bottom), 0)
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 132, visibleTop: top, visibleBottom: bottom), -6)
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 20, visibleTop: top, visibleBottom: bottom), -12)
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 668, visibleTop: top, visibleBottom: bottom), 6)
        XCTAssertEqual(GymReorderGeometry.autoScrollStep(fingerY: 900, visibleTop: top, visibleBottom: bottom), 12)
    }
}
