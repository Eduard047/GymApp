import ActivityKit
import Foundation
import OSLog

private let liveActivityControllerLog = Logger(subsystem: "com.setforge.gymapp.ios", category: "LiveActivityController")

/// A single live activity's operations, abstracted away from the concrete
/// `Activity<WorkoutActivityAttributes>` type so `WorkoutLiveActivityController`'s
/// start/update/end decisions can be unit-tested with a fake in
/// `GymAppTests/WorkoutLiveActivityControllerTests.swift`.
@MainActor
protocol LiveActivityHandle: AnyObject {
    func update(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>) async
    func end(dismissalPolicy: ActivityUIDismissalPolicy) async
}

/// One Live Activity ActivityKit already knows about, independent of
/// whether this controller instance is the one that started it. Used to
/// detect and adopt an activity still running from a previous process (the
/// app was relaunched or updated) instead of leaving it un-adopted: no
/// controller handle, a `ContentState` that never updates again, and button
/// taps that silently no-op.
@MainActor
struct LiveActivitySnapshot {
    let workoutID: UUID
    let handle: LiveActivityHandle
}

/// Requests new activities and reports authorization, abstracted for the
/// same testing reason as `LiveActivityHandle`.
@MainActor
protocol LiveActivityRequesting {
    func areActivitiesEnabled() -> Bool
    /// Every Live Activity of this attributes type ActivityKit currently
    /// knows about, including ones a previous process started that this
    /// controller instance has never seen.
    func currentActivities() -> [LiveActivitySnapshot]
    func request(
        attributes: WorkoutActivityAttributes,
        content: ActivityContent<WorkoutActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle
}

/// The real ActivityKit-backed implementation used in the app.
struct SystemLiveActivityRequester: LiveActivityRequesting {
    func areActivitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func currentActivities() -> [LiveActivitySnapshot] {
        Activity<WorkoutActivityAttributes>.activities.map {
            LiveActivitySnapshot(
                workoutID: $0.attributes.workoutID,
                handle: SystemLiveActivityHandle(activity: $0)
            )
        }
    }

    func request(
        attributes: WorkoutActivityAttributes,
        content: ActivityContent<WorkoutActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle {
        let activity = try Activity<WorkoutActivityAttributes>.request(
            attributes: attributes,
            content: content
        )
        return SystemLiveActivityHandle(activity: activity)
    }
}

private final class SystemLiveActivityHandle: LiveActivityHandle {
    private let activity: Activity<WorkoutActivityAttributes>

    init(activity: Activity<WorkoutActivityAttributes>) {
        self.activity = activity
    }

    func update(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>) async {
        await activity.update(content)
    }

    func end(dismissalPolicy: ActivityUIDismissalPolicy) async {
        await activity.end(nil, dismissalPolicy: dismissalPolicy)
    }
}

/// Starts, updates, and ends the Lock Screen / Dynamic Island Live Activity
/// for the active workout's rest timer and next set.
///
/// Owned once by `MainTabShell` (see `AppRootView.swift`) — the single
/// observation point for `ActiveWorkoutStore.draft` changes — rather than
/// being called from scattered points inside `ActiveWorkoutView`. That view
/// keeps recording/undoing/resting through its normal store calls; this
/// controller only *observes* the resulting draft and mirrors it into
/// ActivityKit.
///
/// No personal data beyond what is already visible on the active workout
/// screen (exercise name, weights, reps, set counts) ever leaves the device
/// through the activity content.
@MainActor
final class WorkoutLiveActivityController: ObservableObject {
    private let requester: LiveActivityRequesting
    private var activity: LiveActivityHandle?
    private weak var workoutStore: WorkoutStore?
    private weak var activeWorkoutStore: ActiveWorkoutStore?
    private weak var restTimers: RestTimerManager?

    init(requester: LiveActivityRequesting? = nil) {
        self.requester = requester ?? SystemLiveActivityRequester()
    }

    /// Registers this controller's store references and wires the widget
    /// extension's App Intent buttons through `LiveActivityActionBridge`.
    /// Safe to call again (e.g. after an account switch): any activity
    /// started under the previous account is ended immediately first.
    func attach(
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        restTimers: RestTimerManager
    ) {
        if self.workoutStore !== workoutStore {
            endImmediately()
        }
        self.workoutStore = workoutStore
        self.activeWorkoutStore = activeWorkoutStore
        self.restTimers = restTimers

        LiveActivityActionBridge.recordCurrentSet = { [weak self] workoutID, expectedSetID in
            self?.recordCurrentSet(workoutID: workoutID, expectedSetID: expectedSetID)
        }
        LiveActivityActionBridge.skipRest = { [weak self] workoutID, expectedRestEndsAt in
            self?.skipRest(workoutID: workoutID, expectedRestEndsAt: expectedRestEndsAt)
        }

        adoptRunningActivities(draft: activeWorkoutStore.draft)
        sync(draft: activeWorkoutStore.draft)
    }

    /// Adopts a Live Activity ActivityKit already has running — e.g. one the
    /// previous process started before the app was relaunched or updated —
    /// so it keeps receiving updates and its buttons keep working, instead
    /// of being left orphaned with a stale `ContentState` (no
    /// `currentSetID`) that makes "record set"/"skip rest" silent no-ops.
    ///
    /// - Any running activity that matches `draft`'s workout id becomes this
    ///   controller's handle and is immediately updated with a fresh
    ///   `ContentState`.
    /// - Every other running activity (a different workout, or any of them
    ///   when there is no active draft) is ended immediately.
    ///
    /// Call on attach (covers a cold launch, including one driven by a
    /// background Live Activity intent) and again whenever the app returns
    /// to the foreground, so an activity left running through a relaunch or
    /// update is picked back up as soon as the app can act on it.
    func adoptRunningActivities(draft: ActiveWorkoutDraft?) {
        let snapshots = requester.currentActivities()
        guard !snapshots.isEmpty else { return }
        liveActivityControllerLog.info(
            "adoptRunningActivities: found \(snapshots.count, privacy: .public) existing activities"
        )

        var adopted: LiveActivitySnapshot?
        for snapshot in snapshots {
            if adopted == nil, let draft, snapshot.workoutID == draft.id {
                adopted = snapshot
            } else {
                liveActivityControllerLog.info("adoptRunningActivities: ending non-matching activity")
                Task { await snapshot.handle.end(dismissalPolicy: .immediate) }
            }
        }

        guard let adopted, let draft else {
            liveActivityControllerLog.info("adoptRunningActivities: no matching activity to adopt")
            return
        }
        liveActivityControllerLog.info("adoptRunningActivities: adopted matching activity")
        activity = adopted.handle
        let content = ActivityContent(
            state: Self.contentState(for: draft, workoutStore: workoutStore),
            staleDate: nil
        )
        Task { await adopted.handle.update(content) }
    }

    /// Call whenever the active draft changes (start, set recorded/undone,
    /// rest started/stopped/adjusted, exercise progression). `nil` ends the
    /// activity with a short "still visible for a moment" dismissal, matching
    /// a normal finish; call `endImmediately()` first for an explicit discard.
    func sync(draft: ActiveWorkoutDraft?) {
        guard let draft else {
            endAfterDelay()
            return
        }
        guard requester.areActivitiesEnabled() else { return }
        let state = Self.contentState(for: draft, workoutStore: workoutStore)
        if let activity {
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) }
        } else {
            start(draft: draft, state: state)
        }
    }

    /// Ends the activity right away (workout discarded).
    func endImmediately() {
        end(dismissalPolicy: .immediate)
    }

    /// Ends the activity after a short delay so the trainee still sees the
    /// final state on the lock screen for a moment (workout finished).
    func endAfterDelay() {
        end(dismissalPolicy: .after(Date().addingTimeInterval(3 * 60)))
    }

    private func start(draft: ActiveWorkoutDraft, state: WorkoutActivityAttributes.ContentState) {
        guard activity == nil else { return }
        let languageCode = gymCurrentLanguageCode()
        let attributes = WorkoutActivityAttributes(
            workoutID: draft.id,
            startDate: draft.startedAt,
            setLabel: gymText("Set", "Підхід", "Подход", languageCode: languageCode),
            nextLabel: gymText("Next:", "Далі:", "Следующий:", languageCode: languageCode)
        )
        do {
            activity = try requester.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    private func end(dismissalPolicy: ActivityUIDismissalPolicy) {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(dismissalPolicy: dismissalPolicy) }
    }

    // MARK: - Button actions (called from LiveActivityActionBridge)

    /// - Parameter expectedSetID: the set `ContentState.currentSetID` was
    ///   showing when the tapped button was drawn. Only that exact set is
    ///   recorded — a duplicate/replayed invocation of an already-handled
    ///   tap no longer matches the (now different) current set and becomes
    ///   a no-op instead of recording whatever is next.
    private func recordCurrentSet(workoutID: UUID, expectedSetID: UUID?) {
        guard let activeWorkoutStore, let workoutStore else { return }
        guard let draft = activeWorkoutStore.draft, draft.id == workoutID else {
            // The persisted active draft no longer matches what this Live
            // Activity was showing (finished, discarded, or a different
            // account/workout since this button was last drawn) — no-op and
            // clear the now-stale activity instead of guessing at new state.
            liveActivityControllerLog.info("recordCurrentSet: workoutID mismatch, ending stale activity")
            endImmediately()
            return
        }
        guard draft.commitIntent == nil,
              let location = Self.currentSet(in: draft),
              let expectedSetID, location.set.id == expectedSetID else {
            liveActivityControllerLog.info("recordCurrentSet: no-op (locked, no current set, or stale setID)")
            return
        }
        liveActivityControllerLog.info("recordCurrentSet: recording matched set")
        let (exercise, set) = location
        let restSeconds = RecommendationEngine.restDurationSeconds(
            exerciseCatalogKey: workoutStore.exercise(id: exercise.exerciseID)?.catalogKey
                ?? exercise.exerciseCatalogKey,
            exerciseName: workoutStore.exercise(id: exercise.exerciseID)?.name
                ?? exercise.exerciseName ?? ""
        )
        do {
            let updated = try activeWorkoutStore.recordSet(
                draftID: draft.id,
                setID: set.id,
                expectedRevision: draft.revision,
                restSeconds: restSeconds
            )
            if let restTimers {
                _ = try? ActiveWorkoutRestReconciler.reconcile(
                    draft: updated,
                    store: activeWorkoutStore,
                    manager: restTimers,
                    title: Self.exerciseName(for: updated, workoutStore: workoutStore)
                )
            }
            sync(draft: updated)
        } catch {
            // Locked/stale/invalid — leave the activity showing its current
            // (still-correct) state rather than guessing at a new one.
        }
    }

    /// - Parameter expectedRestEndsAt: the rest end date `ContentState.restEndsAt`
    ///   was showing when the tapped button was drawn. Only that exact rest
    ///   period is ended — same idempotency reasoning as
    ///   `recordCurrentSet(workoutID:expectedSetID:)`. A small tolerance
    ///   absorbs floating-point round-trip noise without risking a match
    ///   against a genuinely later rest period (those differ by tens of
    ///   seconds or more in practice).
    private func skipRest(workoutID: UUID, expectedRestEndsAt: Date) {
        guard let activeWorkoutStore else { return }
        guard let draft = activeWorkoutStore.draft, draft.id == workoutID else {
            liveActivityControllerLog.info("skipRest: workoutID mismatch, ending stale activity")
            endImmediately()
            return
        }
        guard let restingUntil = draft.timing?.restingUntil,
              abs(restingUntil.timeIntervalSince(expectedRestEndsAt)) < 1.0 else {
            liveActivityControllerLog.info("skipRest: no-op (not resting or stale restEndsAt)")
            return
        }
        liveActivityControllerLog.info("skipRest: ending matched rest period")
        do {
            let updated = try activeWorkoutStore.endRest(
                draftID: draft.id,
                expectedRevision: draft.revision
            )
            if let restTimers {
                _ = try? ActiveWorkoutRestReconciler.reconcile(
                    draft: updated,
                    store: activeWorkoutStore,
                    manager: restTimers,
                    title: Self.exerciseName(for: updated, workoutStore: workoutStore)
                )
            }
            sync(draft: updated)
        } catch {
            // Ditto: no-op on failure.
        }
    }

    // MARK: - Pure mapping (unit-testable without ActivityKit)

    /// The current (next-to-record) exercise/set: the first uncompleted set
    /// across all exercises, mirroring `ActiveWorkoutView.currentSetID(in:)`.
    static func currentSet(
        in draft: ActiveWorkoutDraft
    ) -> (exercise: ActiveWorkoutExercise, set: ActiveWorkoutSet)? {
        for exercise in draft.exercises {
            if let set = exercise.sets.first(where: { !$0.isCompleted }) {
                return (exercise, set)
            }
        }
        return nil
    }

    static func exerciseName(for draft: ActiveWorkoutDraft, workoutStore: WorkoutStore?) -> String {
        guard let (exercise, _) = currentSet(in: draft) else {
            return gymText("Workout", "Тренування", "Тренировка", languageCode: gymCurrentLanguageCode())
        }
        return workoutStore?.exercise(id: exercise.exerciseID).map { gymExerciseName($0) }
            ?? exercise.exerciseName
            ?? gymText("Workout", "Тренування", "Тренировка", languageCode: gymCurrentLanguageCode())
    }

    /// "Set 3 of 5" / "Підхід 3 з 5" / "Подход 3 из 5", built in the app so the
    /// widget extension never has to pick a language on its own.
    static func setProgressLabel(setIndex: Int, setCount: Int, languageCode: String) -> String {
        gymText(
            "Set \(setIndex) of \(setCount)",
            "Підхід \(setIndex) з \(setCount)",
            "Подход \(setIndex) из \(setCount)",
            languageCode: languageCode
        )
    }

    /// Button titles built in the app (in-app language, not the system one).
    static func recordSetButtonTitle(languageCode: String) -> String {
        gymText("Record set", "Записати підхід", "Записать подход", languageCode: languageCode)
    }

    static func skipRestButtonTitle(languageCode: String) -> String {
        gymText("Skip rest", "Пропустити відпочинок", "Пропустить отдых", languageCode: languageCode)
    }

    static func contentState(
        for draft: ActiveWorkoutDraft,
        workoutStore: WorkoutStore?,
        now: Date = Date(),
        languageCode: String = gymCurrentLanguageCode()
    ) -> WorkoutActivityAttributes.ContentState {
        let allSets = draft.exercises.flatMap(\.sets)
        let totalSets = allSets.count
        let completedSets = allSets.filter(\.isCompleted).count

        guard let (exercise, set) = currentSet(in: draft) else {
            // Every set is completed; show the finishing state.
            return WorkoutActivityAttributes.ContentState(
                exerciseName: exerciseName(for: draft, workoutStore: workoutStore),
                setIndex: max(totalSets, 1),
                setCount: max(totalSets, 1),
                setProgressLabel: setProgressLabel(
                    setIndex: max(totalSets, 1),
                    setCount: max(totalSets, 1),
                    languageCode: languageCode
                ),
                completedSets: completedSets,
                totalSets: max(totalSets, 1),
                restEndsAt: nil,
                nextSetSummary: gymText(
                    "All sets recorded",
                    "Усі підходи записано",
                    "Все подходы записаны",
                    languageCode: languageCode
                ),
                isResting: false,
                currentSetID: nil,
                recordSetButtonTitle: recordSetButtonTitle(languageCode: languageCode),
                skipRestButtonTitle: skipRestButtonTitle(languageCode: languageCode)
            )
        }

        let setIndex = (exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1
        let restEndsAt = draft.timing?.restingUntil.flatMap { $0 > now ? $0 : nil }
        let nextSetSummary = gymWeightRepsText(weight: set.weight, reps: set.reps, languageCode: languageCode)
        let setCount = max(exercise.sets.count, 1)

        return WorkoutActivityAttributes.ContentState(
            exerciseName: workoutStore?.exercise(id: exercise.exerciseID).map { gymExerciseName($0) }
                ?? exercise.exerciseName
                ?? gymText("Exercise", "Вправа", "Упражнение", languageCode: languageCode),
            setIndex: setIndex,
            setCount: setCount,
            setProgressLabel: setProgressLabel(setIndex: setIndex, setCount: setCount, languageCode: languageCode),
            completedSets: completedSets,
            totalSets: max(totalSets, 1),
            restEndsAt: restEndsAt,
            nextSetSummary: nextSetSummary,
            isResting: restEndsAt != nil,
            currentSetID: set.id,
            recordSetButtonTitle: recordSetButtonTitle(languageCode: languageCode),
            skipRestButtonTitle: skipRestButtonTitle(languageCode: languageCode)
        )
    }
}
