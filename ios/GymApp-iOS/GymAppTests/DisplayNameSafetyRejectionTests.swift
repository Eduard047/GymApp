import Foundation
import XCTest
@testable import GymApp

@MainActor
final class DisplayNameSafetyRejectionTests: XCTestCase {
    private let serverMessage = "Display name violates the leaderboard safety policy."

    func testServerTriggerRejectionIsDetected() {
        let error = CloudSyncError.postgRESTFailure(
            statusCode: 400,
            code: "23514",
            message: serverMessage
        )
        XCTAssertTrue(error.isDisplayNameSafetyRejection)
    }

    func testOtherFailuresAreNotDetected() {
        XCTAssertFalse(CloudSyncError.isDisplayNameSafetyRejection(code: "23514", message: "new row violates check constraint"))
        XCTAssertFalse(CloudSyncError.isDisplayNameSafetyRejection(code: "23505", message: serverMessage))
        XCTAssertFalse(CloudSyncError.isDisplayNameSafetyRejection(code: nil, message: serverMessage))
        XCTAssertFalse(CloudSyncError.isDisplayNameSafetyRejection(code: "23514", message: nil))
        XCTAssertFalse(CloudSyncError.requestFailed(serverMessage).isDisplayNameSafetyRejection)
        XCTAssertFalse(
            CloudSyncError.postgRESTFailure(statusCode: 401, code: "PGRST301", message: "JWT expired")
                .isDisplayNameSafetyRejection
        )
    }

    func testRejectionShowsTheRulesMessageAndIsNotRetried() throws {
        let error = CloudSyncError.postgRESTFailure(
            statusCode: 400,
            code: "23514",
            message: serverMessage
        )
        XCTAssertEqual(
            gymSafeEnglishErrorMessage(error),
            try XCTUnwrap(AuthServiceError.unsafeDisplayName.errorDescription)
        )
        XCTAssertFalse(AppState.isTransientCloudError(error))
        XCTAssertEqual(
            AppState.cloudSaveFailureAction(error: error, announce: false, isCurrentGeneration: true),
            .show
        )
        // Other PostgREST failures keep the generic text.
        XCTAssertEqual(
            gymSafeEnglishErrorMessage(
                CloudSyncError.postgRESTFailure(statusCode: 400, code: "23514", message: "other")
            ),
            "Something went wrong. Try again."
        )
    }
}
