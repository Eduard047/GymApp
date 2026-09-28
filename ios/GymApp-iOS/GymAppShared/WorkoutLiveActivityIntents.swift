import ActivityKit
import AppIntents
import Foundation
import OSLog

/// Lives in `GymAppShared` (synced into both the `GymApp` app target and the
/// `GymAppLiveActivity` extension target) rather than in the extension's own
/// folder. This is required, not cosmetic: `LiveActivityIntent.perform()`
/// runs in the *app's* process, and the system routes the tap by looking up
/// the intent type inside the app's own compiled binary — if the intent
/// struct only exists in the extension target, the app has no matching type
/// to invoke and the tap silently no-ops. Compiling the same declaration
/// into both targets is what lets `perform()` run at all.
///
/// Both intents below also carry the exact state they were rendered for
/// (a set id / a rest end date) rather than just the workout id. This is
/// what makes them safe against duplicate delivery: `LiveActivityIntent`
/// invocations can be redelivered by the system while the app cold-launches
/// in the background (and, before this file lived in both targets, taps
/// that couldn't route at all could be queued and replayed once it could).
/// A workout-id-only intent has no way to tell "this is the same tap
/// replayed" from "this is a new tap on the next set" — every redelivery
/// would advance the workout by one more set/rest. Carrying the specific
/// target makes a redelivered call a no-op once the store has already moved
/// past it. See `LiveActivityActionBridge` and
/// `WorkoutLiveActivityController.recordCurrentSet(workoutID:expectedSetID:)`
/// / `.skipRest(workoutID:expectedRestEndsAt:)` for the matching guards.
private let liveActivityIntentLog = Logger(subsystem: "com.setforge.gymapp.ios", category: "LiveActivityIntent")

/// Tapped from the Live Activity / Dynamic Island "Записать подход" button.
/// The system launches the app in the background if it isn't already
/// running, without bringing it to the foreground — so the trainee never
/// leaves the Lock Screen / Dynamic Island. Recording goes through
/// `LiveActivityActionBridge`, which `AppState` points at the single,
/// process-wide `ActiveWorkoutStore` (see `AppState.bindLiveActivityController()`
/// in the app target); there is no second, divergent copy of the draft.
struct RecordCurrentSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Record current set"

    @Parameter(title: "Workout ID")
    var workoutIDString: String

    /// The set this button was drawn for (`ContentState.currentSetID`).
    /// Empty when the state had no current set (workout already finished).
    @Parameter(title: "Set ID")
    var setIDString: String

    init() {}

    init(workoutID: UUID, setID: UUID?) {
        self.workoutIDString = workoutID.uuidString
        self.setIDString = setID?.uuidString ?? ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let workoutID = UUID(uuidString: workoutIDString) else {
            liveActivityIntentLog.info("RecordCurrentSetIntent: unparseable workoutID, ignored")
            return .result()
        }
        let expectedSetID = UUID(uuidString: setIDString)
        liveActivityIntentLog.info("RecordCurrentSetIntent.perform invoked")
        LiveActivityActionBridge.recordCurrentSet?(workoutID, expectedSetID)
        return .result()
    }
}

/// Tapped from the Live Activity / Dynamic Island "Пропустить отдых" button.
/// Same in-process, no-foreground execution as `RecordCurrentSetIntent`.
struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"

    @Parameter(title: "Workout ID")
    var workoutIDString: String

    /// The rest period this button was drawn for
    /// (`ContentState.restEndsAt`, as seconds since 1970). The button is
    /// only ever shown while `isResting` is true, so this is always a real
    /// rest end date at render time.
    @Parameter(title: "Rest Ends At")
    var restEndsAtInterval: Double

    init() {}

    init(workoutID: UUID, restEndsAt: Date) {
        self.workoutIDString = workoutID.uuidString
        self.restEndsAtInterval = restEndsAt.timeIntervalSince1970
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let workoutID = UUID(uuidString: workoutIDString) else {
            liveActivityIntentLog.info("SkipRestIntent: unparseable workoutID, ignored")
            return .result()
        }
        liveActivityIntentLog.info("SkipRestIntent.perform invoked")
        LiveActivityActionBridge.skipRest?(workoutID, Date(timeIntervalSince1970: restEndsAtInterval))
        return .result()
    }
}
