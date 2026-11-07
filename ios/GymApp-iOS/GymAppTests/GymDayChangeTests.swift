import Combine
import XCTest
@testable import GymApp

final class GymDayChangeTests: XCTestCase {
    func testPublisherFiresOnCalendarDayChange() {
        var count = 0
        let cancellable = GymDayChange.publisher.sink { count += 1 }
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        XCTAssertEqual(count, 1)
        cancellable.cancel()
    }

    func testPublisherFiresOnSystemTimeZoneChange() {
        var count = 0
        let cancellable = GymDayChange.publisher.sink { count += 1 }
        NotificationCenter.default.post(name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(count, 1)
        cancellable.cancel()
    }
}
