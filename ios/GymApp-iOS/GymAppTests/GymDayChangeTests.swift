import Combine
import XCTest
@testable import GymApp

final class GymDayChangeTests: XCTestCase {
    func testPublisherFiresOnCalendarDayChange() {
        assertFires(for: .NSCalendarDayChanged)
    }

    func testPublisherFiresOnSystemTimeZoneChange() {
        assertFires(for: NSNotification.Name.NSSystemTimeZoneDidChange)
    }

    /// The publisher delivers on the main queue, so the sink fires after the post returns.
    private func assertFires(for name: Notification.Name) {
        let fired = expectation(description: "publisher fired on main")
        var onMain = false
        let cancellable = GymDayChange.publisher.sink {
            onMain = Thread.isMainThread
            fired.fulfill()
        }
        NotificationCenter.default.post(name: name, object: nil)
        wait(for: [fired], timeout: 2)
        XCTAssertTrue(onMain)
        cancellable.cancel()
    }
}
