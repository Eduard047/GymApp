import XCTest
@testable import GymApp

final class GymTrackedPageSwipeTests: XCTestCase {
    private let width: CGFloat = 300

    func testAxisIsLockedOnlyAfterSlopAndHorizontalNeedsClearDominance() {
        XCTAssertNil(GymPageSwipe.lockAxis(translation: CGSize(width: 5, height: 2)))
        XCTAssertEqual(GymPageSwipe.lockAxis(translation: CGSize(width: 20, height: 4)), .horizontal)
        XCTAssertEqual(GymPageSwipe.lockAxis(translation: CGSize(width: 20, height: 18)), .vertical)
        XCTAssertEqual(GymPageSwipe.lockAxis(translation: CGSize(width: 3, height: -30)), .vertical)
    }

    func testContentFollowsTheFingerWhereAPageExists() {
        XCTAssertEqual(
            GymPageSwipe.displacement(translation: 80, width: width, canGoPrevious: true, canGoNext: false),
            80
        )
        XCTAssertEqual(
            GymPageSwipe.displacement(translation: -120, width: width, canGoPrevious: false, canGoNext: true),
            -120
        )
    }

    func testRubberBandDampsAndIsBoundedByWidthWhereThereIsNoPage() {
        let damped = GymPageSwipe.displacement(translation: -100, width: width, canGoPrevious: true, canGoNext: false)
        XCTAssertLessThan(abs(damped), 100)
        XCTAssertLessThan(damped, 0)
        let far = GymPageSwipe.displacement(translation: -5_000, width: width, canGoPrevious: true, canGoNext: false)
        XCTAssertGreaterThan(far, -width)
        XCTAssertLessThan(far, damped)
    }

    func testReleaseCommitsOnTravelOrFlickAndRespectsLimits() {
        // Slow drag: below 40% springs back, at 40% commits.
        XCTAssertNil(GymPageSwipe.commitDirection(
            translation: 100, velocity: 0, width: width, canGoPrevious: true, canGoNext: true))
        XCTAssertEqual(GymPageSwipe.commitDirection(
            translation: 120, velocity: 0, width: width, canGoPrevious: true, canGoNext: true), .previous)
        // Short flick commits in the drag direction.
        XCTAssertEqual(GymPageSwipe.commitDirection(
            translation: -30, velocity: -700, width: width, canGoPrevious: true, canGoNext: true), .next)
        // Past the 40% mark but flicked back: cancels.
        XCTAssertNil(GymPageSwipe.commitDirection(
            translation: 200, velocity: -700, width: width, canGoPrevious: true, canGoNext: true))
        // No newer page: never commits, however far or fast.
        XCTAssertNil(GymPageSwipe.commitDirection(
            translation: -250, velocity: -900, width: width, canGoPrevious: true, canGoNext: false))
        XCTAssertNil(GymPageSwipe.commitDirection(
            translation: 0, velocity: 900, width: width, canGoPrevious: true, canGoNext: true))
    }
}
