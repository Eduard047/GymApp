import ActivityKit
import Foundation

/// Shared ActivityKit contract between the GymApp app target and the
/// GymAppLiveActivity widget extension target. This file is compiled into
/// BOTH targets via a shared PBXFileSystemSynchronizedRootGroup
/// ("GymAppShared"), so it must not reference any app-only or
/// extension-only symbols.
///
/// No personal data beyond what is already visible on the active workout
/// screen (exercise name, weights, reps, set counts) ever goes into this
/// type. All strings are already localized by the app before being placed
/// into `ContentState`, because the widget extension cannot see the app's
/// `gymText` localization helpers.
public struct WorkoutActivityAttributes: ActivityAttributes {
    /// Static data, fixed for the lifetime of the Live Activity.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Localized exercise name for the current (or most recently
        /// touched) exercise, e.g. "Жим лёжа".
        public let exerciseName: String
        /// 1-based index of the current set within the exercise.
        public let setIndex: Int
        /// Total number of sets planned for the current exercise.
        public let setCount: Int
        /// Already-localized "Подход 3 из 5" / "Set 3 of 5" line. Optional so
        /// a state encoded by an older app build still decodes; the widget
        /// then falls back to the language-neutral "3/5".
        public let setProgressLabel: String?
        /// Total sets completed so far in the whole workout.
        public let completedSets: Int
        /// Total sets planned in the whole workout.
        public let totalSets: Int
        /// When the current rest period ends. `nil` when not resting.
        public let restEndsAt: Date?
        /// Already-localized summary of the next set, e.g. "60 кг × 8".
        public let nextSetSummary: String
        /// Whether a rest timer is currently running.
        public let isResting: Bool
        /// The exact set the "Записать подход" button targets, i.e. the id
        /// `currentSet(in:)` resolved to when this state was built. `nil`
        /// once every set is recorded (there is nothing left to target).
        /// The button intent carries this id so a duplicate/replayed tap can
        /// only record the set it was drawn for, not "whatever is now
        /// current" — see `LiveActivityActionBridge.recordCurrentSet`.
        public let currentSetID: UUID?

        public init(
            exerciseName: String,
            setIndex: Int,
            setCount: Int,
            setProgressLabel: String? = nil,
            completedSets: Int,
            totalSets: Int,
            restEndsAt: Date?,
            nextSetSummary: String,
            isResting: Bool,
            currentSetID: UUID?
        ) {
            self.exerciseName = exerciseName
            self.setIndex = setIndex
            self.setCount = setCount
            self.setProgressLabel = setProgressLabel
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.restEndsAt = restEndsAt
            self.nextSetSummary = nextSetSummary
            self.isResting = isResting
            self.currentSetID = currentSetID
        }

        /// Fraction of the workout completed, clamped to [0, 1].
        public var progress: Double {
            guard totalSets > 0 else { return 0 }
            return min(1, max(0, Double(completedSets) / Double(totalSets)))
        }
    }

    /// Stable identifier of the workout this Live Activity represents.
    public let workoutID: UUID
    /// When the workout started (used for elapsed-time display if needed).
    public let startDate: Date
    /// Already-localized "Подход" / "Set" style label, so the widget never
    /// has to choose a language on its own.
    public let setLabel: String
    /// Already-localized "Следующий:" / "Next:" style label.
    public let nextLabel: String

    public init(workoutID: UUID, startDate: Date, setLabel: String, nextLabel: String) {
        self.workoutID = workoutID
        self.startDate = startDate
        self.setLabel = setLabel
        self.nextLabel = nextLabel
    }
}
