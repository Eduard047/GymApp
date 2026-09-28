import Foundation

/// In-process bridge between the GymAppLiveActivity widget extension's App
/// Intents (which run inside the app's process once the app is launched via
/// `openAppWhenRun = true`) and the app's own `WorkoutStore`/rest-timer
/// state, without the extension needing to compile against app-only types.
///
/// The app registers closures here at startup (see
/// `WorkoutLiveActivityController` in the app target). The extension's
/// intents only ever call through this bridge — they never see
/// `WorkoutStore`, `AppState`, or any other app-only type. Because these
/// intents launch/foreground the app before `perform()` runs, the call
/// happens in the same process as the rest of the app, so no App Group or
/// IPC is required.
///
/// Compiled into both the app and the extension via the shared
/// "GymAppShared" synchronized group.
public enum LiveActivityActionBridge {
    /// Records the current set with its currently planned values, using the
    /// exact same store path as the in-app "Log" button.
    ///
    /// `expectedSetID` is the specific set this button was rendered for
    /// (from `ContentState.currentSetID` at render time). This makes the
    /// action idempotent: a duplicate or replayed invocation of the *same*
    /// tap (the system can redeliver a `LiveActivityIntent` while the app is
    /// cold-launching, and taps made while the intent type couldn't route —
    /// before both targets compiled it — could be queued and replayed once
    /// it could) only records once, because the second call's `expectedSetID`
    /// no longer matches the new current set and becomes a no-op instead of
    /// marching forward to the *next* set. No-op if there is no matching
    /// active workout, the set is locked, or `expectedSetID` is stale/nil.
    @MainActor public static var recordCurrentSet: (@MainActor (_ workoutID: UUID, _ expectedSetID: UUID?) -> Void)?

    /// Skips (stops) the currently running rest timer, if any.
    ///
    /// `expectedRestEndsAt` is the rest period this button was rendered for
    /// (from `ContentState.restEndsAt` at render time). Same idempotency
    /// reasoning as `recordCurrentSet`: a replayed/duplicate invocation only
    /// ends rest if that exact rest period is still the one running, so it
    /// can never cascade into ending a *later* rest period it was never
    /// shown for.
    @MainActor public static var skipRest: (@MainActor (_ workoutID: UUID, _ expectedRestEndsAt: Date) -> Void)?
}
