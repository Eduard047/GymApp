/*
THESIS: Focus Lens puts today's workout in one fluid focal form and refuses the stacked-dashboard default.
OWN-WORLD: Airy canvas, aquatic contextual color, continuous curves, solid content rows, and one Liquid Glass control layer.
STORY: See the next useful action, understand its size and weekly rhythm, start it, then review recent work without changing modes.
FIRST VIEWPORT: A large asymmetric lens leads; core facts sit inside it and the start capsule attaches near thumb reach, followed by progressive analytics.
FORM: User-selected Focus Lens from Fluid Focus; seed af1a1dee. iOS keeps native TabView, NavigationStack, Dynamic Type, Reduce Transparency, and system materials.
*/
import Combine
import SwiftUI

private let maximumTodayHeroVolume = 1_000_000_000_000_000.0

struct TodayHeroMetrics: Equatable {
    let totalWorkouts: Int
    let weeklyStreakWeeks: Int
    let totalVolume: Double

    init(sessions: [WorkoutSessionSummary], weeklyStreakWeeks: Int) {
        totalWorkouts = sessions.count
        self.weeklyStreakWeeks = max(0, weeklyStreakWeeks)
        totalVolume = sessions.reduce(0.0) { running, session in
            guard session.totalVolume.isFinite, session.totalVolume >= 0 else { return running }
            return min(maximumTodayHeroVolume, running + session.totalVolume)
        }
    }
}

enum TodayFocusPlanMetrics {
    static func estimatedMinutes(exerciseCount: Int, setCount: Int) -> Int {
        min(90, max(10, exerciseCount * 3 + setCount * 2))
    }
}

/// Pure, testable decision logic for the "Train with a friend" hero entry
/// point (the "С другом" pill). Computed from plain values passed into
/// `WorkoutsView` — never from a live `LiveWorkoutCoordinator` or `AppState`
/// observation, so the hero does not re-render on every coordinator poll
/// tick (see `LiveWorkoutRefreshState`).
enum TodayFriendEntryState: Equatable {
    case needsCloudAccount
    case needsFriends
    case pickFriend
    case pendingInvite(count: Int)
    case hidden

    init(
        isCloudAccount: Bool,
        friendCount: Int,
        pendingInvitationCount: Int,
        hasBlockingLiveWorkout: Bool
    ) {
        if hasBlockingLiveWorkout {
            self = .hidden
        } else if pendingInvitationCount > 0 {
            self = .pendingInvite(count: pendingInvitationCount)
        } else if !isCloudAccount {
            self = .needsCloudAccount
        } else if friendCount <= 0 {
            self = .needsFriends
        } else {
            self = .pickFriend
        }
    }

    var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }

    /// Pure decision for what a tap on the "С другом" hero pill should do.
    /// `forcedVisible` means a solo workout is already active
    /// (`activeFocusLens`): tapping never opens the friend picker there, but
    /// a pending invite still opens the invites screen — accepting it is
    /// guarded downstream by the existing live-workout logic.
    func tapAction(forcedVisible: Bool) -> TodayFriendTapAction {
        if forcedVisible {
            if case .pendingInvite = self {
                return .openInvites
            }
            return .blockedBySoloWorkout
        }
        switch self {
        case .needsCloudAccount:
            return .openAccount
        case .needsFriends:
            return .openFriends
        case .pickFriend:
            return .pickFriend
        case .pendingInvite:
            return .openInvites
        case .hidden:
            return .none
        }
    }
}

/// The effect a tap on the "С другом" hero pill should have, decided by
/// `TodayFriendEntryState.tapAction(forcedVisible:)`.
enum TodayFriendTapAction: Equatable {
    case openAccount
    case openFriends
    case pickFriend
    case openInvites
    case blockedBySoloWorkout
    case none
}

struct WeeklyTrainingSummary: Equatable {
    let weekStart: Date
    let completedSessionCount: Int
    let completedTrainingDays: Set<Int64>
    let totalMinutes: Int
    let totalVolume: Double
    /// Volume change against the same days of the previous week (current week) or the full previous week; nil when not comparable.
    let volumeDeltaPercent: Int?
    /// Both the shown week and its comparison window have a workout (see `TodayPresentation`).
    let showsVolumeComparison: Bool

    init(
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) {
        self.init(
            sessions: sessions,
            weekContaining: now,
            now: now,
            calendar: calendar
        )
    }

    init(
        sessions: [WorkoutSessionSummary],
        weekContaining referenceDate: Date,
        now: Date,
        calendar: Calendar
    ) {
        let start = calendar.gymMondayStart(of: referenceDate)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        let weeklySessions = sessions.filter { session in
            session.date >= start && session.date < end && session.date <= now
        }

        weekStart = start
        completedSessionCount = weeklySessions.count
        completedTrainingDays = Set(
            weeklySessions.map { calendar.gymEpochDay(for: $0.date) }
        )
        totalMinutes = weeklySessions.reduce(0) { running, session in
            let minutes = Self.durationMinutes(for: session)
            guard running <= Int.max - minutes else { return Int.max }
            return running + minutes
        }
        totalVolume = weeklySessions.reduce(0.0) { running, session in
            guard session.totalVolume.isFinite, session.totalVolume >= 0 else { return running }
            return min(maximumTodayHeroVolume, running + session.totalVolume)
        }
        volumeDeltaPercent = weekVolumeDeltaPercent(
            sessions: sessions,
            weekContaining: referenceDate,
            now: now,
            calendar: calendar
        )
        let counts = weekComparisonWorkoutCounts(
            sessions: sessions,
            weekContaining: referenceDate,
            now: now,
            calendar: calendar
        )
        showsVolumeComparison = TodayPresentation.showsWeekComparison(
            currentWorkouts: counts.current,
            comparisonWorkouts: counts.previous
        )
    }

    func hasWorkout(on date: Date, calendar: Calendar) -> Bool {
        completedTrainingDays.contains(calendar.gymEpochDay(for: date))
    }

    func hasCompletedWorkoutToday(now: Date, calendar: Calendar) -> Bool {
        hasWorkout(on: now, calendar: calendar)
    }

    static func durationMinutes(for session: WorkoutSessionSummary) -> Int {
        if let seconds = session.durationSeconds,
           (0 ... 7 * 24 * 60 * 60).contains(seconds) {
            return Int((seconds + 59) / 60)
        }
        if let seconds = GarminWorkoutNoteParser.parse(session.note)?.durationSeconds,
           seconds > 0 {
            return Int((seconds + 59) / 60)
        }
        return TodayFocusPlanMetrics.estimatedMinutes(
            exerciseCount: session.exerciseCount,
            setCount: session.setCount
        )
    }
}

let weekVolumeDeltaCapPercent = 999

/// The shown week's window and the equally long window of the previous week it is compared with.
private func weekComparisonWindows(
    weekContaining referenceDate: Date,
    now: Date,
    calendar: Calendar
) -> (weekStart: Date, currentEnd: Date, previousStart: Date, previousEnd: Date)? {
    let weekStart = calendar.gymMondayStart(of: referenceDate)
    let isCurrentWeek = weekStart == calendar.gymMondayStart(of: now)
    let elapsedDays: Int
    if isCurrentWeek {
        let days = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: now)).day ?? 0
        elapsedDays = min(7, max(0, days) + 1)
    } else {
        elapsedDays = 7
    }
    guard
        let currentEnd = calendar.date(byAdding: .day, value: elapsedDays, to: weekStart),
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
        let previousEnd = calendar.date(byAdding: .day, value: elapsedDays, to: previousStart)
    else { return nil }
    return (weekStart, currentEnd, previousStart, previousEnd)
}

/// Workouts in the shown week and in its comparison window (sessions after `now` ignored).
func weekComparisonWorkoutCounts(
    sessions: [WorkoutSessionSummary],
    weekContaining referenceDate: Date,
    now: Date,
    calendar: Calendar
) -> (current: Int, previous: Int) {
    guard let windows = weekComparisonWindows(
        weekContaining: referenceDate,
        now: now,
        calendar: calendar
    ) else { return (0, 0) }
    var current = 0
    var previous = 0
    for session in sessions where session.date <= now {
        if session.date >= windows.weekStart && session.date < windows.currentEnd {
            current += 1
        } else if session.date >= windows.previousStart && session.date < windows.previousEnd {
            previous += 1
        }
    }
    return (current, previous)
}

/// Volume change of the week containing `referenceDate` against the previous week, in whole percent
/// (half away from zero, capped at `weekVolumeDeltaCapPercent`). The current week is compared with the
/// same elapsed days (Monday..today) of the previous week; a past week with the whole previous week.
/// Nil when the previous volume is 0. Contract: shared/week-volume-delta-v1.json.
func weekVolumeDeltaPercent(
    sessions: [WorkoutSessionSummary],
    weekContaining referenceDate: Date,
    now: Date,
    calendar: Calendar
) -> Int? {
    guard let windows = weekComparisonWindows(
        weekContaining: referenceDate,
        now: now,
        calendar: calendar
    ) else { return nil }
    let weekStart = windows.weekStart
    let currentEnd = windows.currentEnd
    let previousStart = windows.previousStart
    let previousEnd = windows.previousEnd

    var current = 0.0
    var previous = 0.0
    for session in sessions where session.date <= now {
        let volume = session.totalVolume.isFinite && session.totalVolume >= 0 ? session.totalVolume : 0
        if session.date >= weekStart && session.date < currentEnd {
            current = min(maximumTodayHeroVolume, current + volume)
        } else if session.date >= previousStart && session.date < previousEnd {
            previous = min(maximumTodayHeroVolume, previous + volume)
        }
    }
    guard previous > 0 else { return nil }
    let raw = (current - previous) * 100 / previous
    let rounded = raw.rounded(.toNearestOrAwayFromZero)
    return Int(min(Double(weekVolumeDeltaCapPercent), rounded))
}

/// "+12%" / "−8%" (true minus sign) / "0%".
func weekVolumeDeltaText(_ percent: Int, locale: Locale) -> String {
    let sign = percent > 0 ? "+" : (percent < 0 ? "\u{2212}" : "")
    return sign + abs(percent).formatted(.number.locale(locale)) + "%"
}

enum TrainingHistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
}

/// Plain button look that keeps its label at full contrast when the button is
/// disabled; SwiftUI's built-in plain style dims disabled labels.
private struct HistoryRangeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct MonthlyTrainingSummary: Equatable {
    let monthStart: Date
    let completedSessionCount: Int
    let completedTrainingDays: Set<Int64>
    let totalMinutes: Int
    let totalVolume: Double

    init(
        sessions: [WorkoutSessionSummary],
        monthContaining referenceDate: Date,
        now: Date,
        calendar: Calendar
    ) {
        let interval = calendar.dateInterval(of: .month, for: referenceDate)
            ?? DateInterval(start: calendar.startOfDay(for: referenceDate), duration: 1)
        let monthlySessions = sessions.filter { session in
            interval.contains(session.date) && session.date <= now
        }
        monthStart = interval.start
        completedSessionCount = monthlySessions.count
        completedTrainingDays = Set(
            monthlySessions.map { calendar.gymEpochDay(for: $0.date) }
        )
        totalMinutes = monthlySessions.reduce(0) { running, session in
            let minutes = WeeklyTrainingSummary.durationMinutes(for: session)
            guard running <= Int.max - minutes else { return Int.max }
            return running + minutes
        }
        totalVolume = monthlySessions.reduce(0.0) { running, session in
            guard session.totalVolume.isFinite, session.totalVolume >= 0 else { return running }
            return min(maximumTodayHeroVolume, running + session.totalVolume)
        }
    }

    func hasWorkout(on date: Date, calendar: Calendar) -> Bool {
        completedTrainingDays.contains(calendar.gymEpochDay(for: date))
    }
}

struct TodayScreenProjection {
    let accountStorageKey: String
    let trainingProfile: TrainingProfile
    let weeklyGuidance: WeeklyTrainingGuidance
    let weeklySummary: WeeklyTrainingSummary
    let historyWeekSummary: WeeklyTrainingSummary
    let historyWeekWorkouts: [WorkoutSessionSummary]
    let monthSummary: MonthlyTrainingSummary
    let launchSeed: WorkoutLaunchSeed?
    let heroMetrics: TodayHeroMetrics
    let monthWorkouts: [WorkoutSessionSummary]
}

@MainActor
final class TodayScreenProjectionCache: ObservableObject {
    private struct Key: Equatable {
        let storeIdentity: ObjectIdentifier
        let accountStorageKey: String
        let derivedDataRevision: UInt64
        let referenceDate: Date
        let calendar: Calendar
        let trainingProfile: TrainingProfile
        let monthOffset: Int
        let weekOffset: Int
    }

    private var cached: (key: Key, projection: TodayScreenProjection)?
    private(set) var buildCount = 0

    func projection(
        store: WorkoutStore,
        referenceDate: Date,
        calendar: Calendar,
        trainingProfile: TrainingProfile,
        monthOffset: Int,
        weekOffset: Int = 0
    ) -> TodayScreenProjection {
        let boundedWeekOffset = min(0, max(-5_200, weekOffset))
        let boundedMonthOffset = min(0, max(-1_200, monthOffset))
        let key = Key(
            storeIdentity: ObjectIdentifier(store),
            accountStorageKey: store.accountStorageKey,
            derivedDataRevision: store.derivedDataRevision,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: trainingProfile,
            monthOffset: boundedMonthOffset,
            weekOffset: boundedWeekOffset
        )
        if let cached, cached.key == key {
            return cached.projection
        }

        let sessions = store.workoutSummaries
        let history = store.allExerciseHistory()
        let latestFeedback = store.latestWorkoutFeedbackContext(now: referenceDate)
        let weeklySummary = WeeklyTrainingSummary(
            sessions: sessions,
            now: referenceDate,
            calendar: calendar
        )
        let selectedWeekReferenceDate = calendar.date(
            byAdding: .day,
            value: boundedWeekOffset * 7,
            to: referenceDate
        ) ?? referenceDate
        let historyWeekSummary = WeeklyTrainingSummary(
            sessions: sessions,
            weekContaining: selectedWeekReferenceDate,
            now: referenceDate,
            calendar: calendar
        )
        let historyWeekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: historyWeekSummary.weekStart
        ) ?? historyWeekSummary.weekStart.addingTimeInterval(7 * 24 * 60 * 60)
        let historyWeekWorkouts = sessions
            .filter { session in
                session.date >= historyWeekSummary.weekStart &&
                    session.date < historyWeekEnd &&
                    session.date <= referenceDate
            }
            .sorted { $0.date > $1.date }
        let weeklyGuidance = RecommendationEngine.weeklyTrainingGuidance(
            history: history,
            trainingProfile: trainingProfile,
            latestFeedback: latestFeedback,
            now: referenceDate,
            calendar: calendar
        )
        let launchSeed: WorkoutLaunchSeed?
        if weeklySummary.hasCompletedWorkoutToday(now: referenceDate, calendar: calendar) {
            launchSeed = nil
        } else {
            let effort: SmartWorkoutEffort = weeklyGuidance.decision == .train
                ? .auto
                : .recovery
            let plan = RecommendationEngine.buildWorkoutPlan(
                exercises: store.exercises,
                history: history,
                muscleMappings: store.muscleMappings,
                trainingProfile: trainingProfile,
                effort: effort,
                latestFeedback: latestFeedback,
                now: referenceDate,
                calendar: calendar
            )
            launchSeed = plan.exercises.isEmpty ? nil : WorkoutLaunchSeed(
                accountStorageKey: store.accountStorageKey,
                profile: trainingProfile,
                requestedEffort: effort,
                plan: plan,
                catalog: store.exercises,
                history: history,
                muscleMappings: store.muscleMappings,
                createdAt: referenceDate
            )
        }

        let weeklyStreakWeeks = WeeklyStreakCalculator.current(
            sessions: sessions,
            targetTrainingDays: trainingProfile.workoutsPerWeek,
            now: referenceDate,
            calendar: calendar
        )
        let selectedMonth = calendar.date(
            byAdding: .month,
            value: boundedMonthOffset,
            to: referenceDate
        ) ?? referenceDate
        let selectedMonthInterval = calendar.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: calendar.startOfDay(for: selectedMonth), duration: 1)
        let monthWorkouts = sessions
            .filter { selectedMonthInterval.contains($0.date) && $0.date <= referenceDate }
            .sorted { $0.date > $1.date }
        let projection = TodayScreenProjection(
            accountStorageKey: store.accountStorageKey,
            trainingProfile: trainingProfile,
            weeklyGuidance: weeklyGuidance,
            weeklySummary: weeklySummary,
            historyWeekSummary: historyWeekSummary,
            historyWeekWorkouts: historyWeekWorkouts,
            monthSummary: MonthlyTrainingSummary(
                sessions: monthWorkouts,
                monthContaining: selectedMonth,
                now: referenceDate,
                calendar: calendar
            ),
            launchSeed: launchSeed,
            heroMetrics: TodayHeroMetrics(
                sessions: sessions,
                weeklyStreakWeeks: weeklyStreakWeeks
            ),
            monthWorkouts: monthWorkouts
        )
        buildCount += 1
        cached = (key, projection)
        return projection
    }
}

/// Fires when the local day rolls over or the system timezone changes while the app stays
/// open, so screens that cache "today" can re-read the clock (`scenePhase` does not change
/// in either case).
enum GymDayChange {
    static let publisher: AnyPublisher<Void, Never> = {
        let center = NotificationCenter.default
        return Publishers.Merge(
            center.publisher(for: .NSCalendarDayChanged),
            center.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
        )
        .map { _ in () }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }()
}

/// One row of the Today card's grouped action list.
struct TodayRowItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isDestructive = false
    var badge: Int?
    var showsChevron = true
    let hint: String
    let action: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        badge: Int? = nil,
        showsChevron: Bool = true,
        hint: String,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.badge = badge
        self.showsChevron = showsChevron
        self.hint = hint
        self.action = action
    }
}

/// Disclosure row of the Today hero card: the label at the leading edge and the small grey
/// chevron the card's navigation rows use. The system style draws a heavy label-coloured
/// chevron, which reads as a second title next to the grey chevrons below it.
private struct TodayHeroDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        TodayHeroDisclosureBody(configuration: configuration)
    }
}

private struct TodayHeroDisclosureBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: DisclosureGroupStyleConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GymTheme.onHeroSecondary.opacity(0.7))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded
                ? gymText("Expanded", "Розгорнуто", "Развёрнуто", languageCode: gymCurrentLanguageCode())
                : gymText("Collapsed", "Згорнуто", "Свёрнуто", languageCode: gymCurrentLanguageCode())
            )
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}

@MainActor
public struct WorkoutsView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var store: WorkoutStore
    @StateObject private var projectionCache = TodayScreenProjectionCache()
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var weekOffset = 0
    @State private var historyPeriod: TrainingHistoryPeriod = .week
    /// Today shows the compact history card; this opens the full one (period switch, search) in place.
    @State private var showsFullHistory = false
    @State private var historyReturnWorkoutID: UUID?
    /// Past-workout search by exercise name in the training-history panel; view state only.
    @State private var historySearchQuery = ""
    @FocusState private var historySearchFocused: Bool
    @State private var activationProfile: TrainingProfile
    @State private var activationEffort: SmartWorkoutEffort = .standard
    @State private var activationDismissed: Bool
    @State private var showsTrainingSettings = false
    @State private var showsFocusDetails = false
    @State private var showsActiveFocusDetails = false
    @State private var showsActivationOptions = false
    @State private var showsRetainedPlanCancelConfirmation = false
    @State private var showsFriendPicker = false

    private let onStartPlan: (WorkoutLaunchSeed) -> Bool
    private let onAddWorkout: (WorkoutLaunchSeed?) -> Bool
    private let onRepeatLastWorkout: () -> Void
    private let hasRetainedWorkoutDraft: Bool
    /// Exercise/set counts of the saved plan draft, so the Today card shows the
    /// edited plan instead of the generated one it started from.
    private let retainedPlanCounts: (exercises: Int, sets: Int)?
    private let activeWorkoutDraft: ActiveWorkoutDraft?
    private let onContinueWorkout: () -> Void
    private let onDiscardWorkout: () -> Void
    private let onCancelPlan: () -> Void
    private let tracksTutorialPrimaryActionFrame: Bool
    private let onTutorialPrimaryActionFrameChange: @MainActor (CGRect?) -> Void
    private let onOpenWorkout: (UUID) -> Void
    private let onOpenRanks: () -> Void
    private let isCloudAccount: Bool
    private let friends: [SocialFriendSummary]
    private let pendingInvitationCount: Int
    private let hasBlockingLiveWorkout: Bool
    private let onTrainWithFriend: (SocialFriendSummary) -> Void
    private let onTrainWithFriendBlocked: () -> Void
    private let onOpenFriends: () -> Void
    private let onOpenInvites: () -> Void
    private let onOpenAccount: () -> Void

    init(
        store: WorkoutStore,
        activeWorkoutDraft: ActiveWorkoutDraft? = nil,
        hasRetainedWorkoutDraft: Bool = false,
        retainedPlanCounts: (exercises: Int, sets: Int)? = nil,
        isCloudAccount: Bool = false,
        friends: [SocialFriendSummary] = [],
        pendingInvitationCount: Int = 0,
        hasBlockingLiveWorkout: Bool = false,
        onStartPlan: @escaping (WorkoutLaunchSeed) -> Bool,
        onAddWorkout: @escaping (WorkoutLaunchSeed?) -> Bool,
        onRepeatLastWorkout: @escaping () -> Void = {},
        onContinueWorkout: @escaping () -> Void = {},
        onDiscardWorkout: @escaping () -> Void = {},
        onCancelPlan: @escaping () -> Void = {},
        onTrainWithFriend: @escaping (SocialFriendSummary) -> Void = { _ in },
        onTrainWithFriendBlocked: @escaping () -> Void = {},
        onOpenFriends: @escaping () -> Void = {},
        onOpenInvites: @escaping () -> Void = {},
        onOpenAccount: @escaping () -> Void = {},
        tracksTutorialPrimaryActionFrame: Bool = false,
        onTutorialPrimaryActionFrameChange: @escaping @MainActor (CGRect?) -> Void = { _ in },
        onOpenWorkout: @escaping (UUID) -> Void,
        onOpenRanks: @escaping () -> Void
    ) {
        self.store = store
        self.activeWorkoutDraft = activeWorkoutDraft
        self.hasRetainedWorkoutDraft = hasRetainedWorkoutDraft
        self.retainedPlanCounts = retainedPlanCounts
        self.isCloudAccount = isCloudAccount
        self.friends = friends
        self.pendingInvitationCount = pendingInvitationCount
        self.hasBlockingLiveWorkout = hasBlockingLiveWorkout
        self.onStartPlan = onStartPlan
        self.onAddWorkout = onAddWorkout
        self.onRepeatLastWorkout = onRepeatLastWorkout
        self.onContinueWorkout = onContinueWorkout
        self.onDiscardWorkout = onDiscardWorkout
        self.onCancelPlan = onCancelPlan
        self.onTrainWithFriend = onTrainWithFriend
        self.onTrainWithFriendBlocked = onTrainWithFriendBlocked
        self.onOpenFriends = onOpenFriends
        self.onOpenInvites = onOpenInvites
        self.onOpenAccount = onOpenAccount
        self.tracksTutorialPrimaryActionFrame = tracksTutorialPrimaryActionFrame
        self.onTutorialPrimaryActionFrameChange = onTutorialPrimaryActionFrameChange
        self.onOpenWorkout = onOpenWorkout
        self.onOpenRanks = onOpenRanks
        _activationDismissed = State(
            initialValue: TrainingProfileStore().activationDismissed(
                accountStorageKey: store.accountStorageKey
            )
        )
        _activationProfile = State(
            initialValue: TrainingProfileStore().load(
                accountStorageKey: store.accountStorageKey
            )
        )
    }

    public var body: some View {
        GymBackground {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: GymTheme.contentSpacing) {
                        screenHeader
                        if activeWorkoutDraft != nil {
                            activeFocusLens
                        } else if store.workoutSummaries.isEmpty, !activationDismissed {
                            activationPanel
                            if !hasRetainedWorkoutDraft {
                                emptyStateHint
                            }
                        } else {
                            focusLens
                        }
                        if !store.workoutSummaries.isEmpty {
                            trainingHistoryPanel
                        }
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollIndicators(.hidden)
                .gymStatusBarScrollEdge()
                // Keep the history search field and its first results above the keyboard:
                // once the keyboard has finished opening, and again when the first typed
                // characters swap the period list for results.
                .onChange(of: historySearchFocused) { _, focused in
                    guard focused else { return }
                    revealHistorySearch(proxy, afterKeyboardOpens: true)
                }
                .onChange(of: historySearchQuery) { _, _ in
                    guard historySearchFocused else { return }
                    revealHistorySearch(proxy, afterKeyboardOpens: false)
                }
                .onAppear {
                    guard let historyReturnWorkoutID else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(historyReturnWorkoutID, anchor: .center)
                    }
                }
                .task {
#if DEBUG
                    guard let anchor = screenshotSectionAnchor else { return }
                    await Task.yield()
                    proxy.scrollTo(anchor, anchor: .top)
#endif
                }
#if DEBUG
                .onReceive(UIAuditRouter.shared.$pendingPresentation.compactMap { $0 }) { _ in
                    presentUIAuditRouteIfRequested(proxy)
                }
#endif
            }
        }
        .sheet(isPresented: $showsTrainingSettings) {
            TrainingSettingsSheet(profile: $activationProfile) { newValue in
                TrainingProfileStore().save(newValue, accountStorageKey: store.accountStorageKey)
            }
        }
        .sheet(isPresented: $showsFriendPicker) {
            friendPickerSheet
                .gymSheetPresentation()
        }
        .onAppear { referenceDate = Date() }
        .onReceive(store.objectWillChange) { _ in referenceDate = Date() }
        .onReceive(GymDayChange.publisher) { _ in referenceDate = Date() }
        .onChange(of: store.accountStorageKey) { _, storageKey in
            referenceDate = Date()
            monthOffset = 0
            weekOffset = 0
            historyPeriod = .week
            showsFullHistory = false
            historySearchQuery = ""
            historyReturnWorkoutID = nil
            showsFocusDetails = false
            showsActiveFocusDetails = false
            activationDismissed = TrainingProfileStore().activationDismissed(
                accountStorageKey: storageKey
            )
            activationProfile = TrainingProfileStore().load(
                accountStorageKey: storageKey
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { referenceDate = Date() }
        }
        .alert(
            gymText(
                "Cancel saved plan?",
                "Скасувати збережений план?",
                "Отменить сохранённый план?",
                languageCode: languageCode
            ),
            isPresented: $showsRetainedPlanCancelConfirmation
        ) {
            Button(gymText(
                "Keep plan", "Залишити план", "Оставить план",
                languageCode: languageCode
            ), role: .cancel) {}
            Button(gymText(
                "Cancel plan", "Скасувати план", "Отменить план",
                languageCode: languageCode
            ), role: .destructive) {
                onCancelPlan()
            }
        } message: {
            Text(gymText(
                "The saved plan and its selected LIVE recipient will be removed. Workout history and any active workout will stay.",
                "Збережений план і вибраний отримувач LIVE будуть видалені. Історія та активне тренування залишаться.",
                "Сохранённый план и выбранный получатель LIVE будут удалены. История и активная тренировка останутся.",
                languageCode: languageCode
            ))
        }
    }

    private var screenHeader: some View {
        GymScreenHeader(
            title: gymText("Today", "Сьогодні", "Сегодня", languageCode: languageCode)
        )
    }

    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasRetainedWorkoutDraft {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gymText(
                        "Saved plan",
                        "Збережений план",
                        "Сохранённый план",
                        languageCode: languageCode
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.onHeroSecondary)
                    Text(gymText(
                        "Continue your plan",
                        "Продовж свій план",
                        "Продолжить свой план",
                        languageCode: languageCode
                    ))
                    .font(.title2.bold())
                    .foregroundStyle(GymTheme.onHero)
                }
                focusPrimaryAction(
                    launchSeed: nil,
                    guidance: todayProjection.weeklyGuidance,
                    completedToday: false
                )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(gymText(
                            "Your first plan",
                            "Перший план",
                            "Первый план",
                            languageCode: languageCode
                        ))
                        .font(.title2.bold())
                        .foregroundStyle(GymTheme.onHero)

                        Spacer(minLength: 8)

                        Button {
                            withAnimation(GymMotion.animation(GymMotion.quick, reduceMotion: reduceMotion)) {
                                showsActivationOptions.toggle()
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundStyle(
                                    showsActivationOptions
                                        ? GymTheme.onPrimary
                                        : GymTheme.heroActionLabel
                                )
                                .frame(width: 44, height: 44)
                                .background(
                                    showsActivationOptions ? GymTheme.brandFill : GymTheme.heroTile,
                                    in: Circle()
                                )
                                .overlay {
                                    Circle().strokeBorder(
                                        showsActivationOptions ? Color.clear : GymTheme.heroOutline,
                                        lineWidth: GymTheme.hairlineWidth
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(gymText(
                            "Adjust recommendation",
                            "Налаштувати пораду",
                            "Настроить рекомендацию",
                            languageCode: languageCode
                        ))
                        .accessibilityAddTraits(showsActivationOptions ? .isSelected : [])
                        .accessibilityValue(showsActivationOptions
                            ? gymText("Open", "Відкрито", "Открыто", languageCode: languageCode)
                            : gymText("Closed", "Закрито", "Закрыто", languageCode: languageCode)
                        )
                    }
                    Text(gymText(
                        "Use the suggestion now or build the workout yourself. You can adjust every setting.",
                        "Скористайтеся порадою зараз або створіть тренування самостійно. Усі налаштування можна змінити.",
                        "Используйте рекомендацию сейчас или соберите тренировку сами. Все настройки можно изменить.",
                        languageCode: languageCode
                    ))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if showsActivationOptions {
                        VStack(alignment: .leading, spacing: 14) {
                            TrainingSettingsSummaryRow(
                                profile: activationProfile,
                                languageCode: languageCode,
                                textColor: GymTheme.onHeroSecondary,
                                linkColor: GymTheme.heroActionLabel
                            ) {
                                showsTrainingSettings = true
                            }
                            activationEffortRow(
                                title: gymText(
                                    "Today’s effort", "Навантаження сьогодні", "Нагрузка сегодня",
                                    languageCode: languageCode
                                ),
                                options: TrainingActivationChoices.efforts,
                                selection: $activationEffort
                            )
                            Button(action: editActivationPlan) {
                                Label(
                                    gymText(
                                        "Review exercises", "Переглянути вправи", "Посмотреть упражнения",
                                        languageCode: languageCode
                                    ),
                                    systemImage: "pencil"
                                )
                                .font(.headline)
                                .foregroundStyle(GymTheme.heroActionLabel)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .gymAccessibilityVerticalPadding()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                        .tint(GymTheme.heroActionLabel)
                        .foregroundStyle(GymTheme.onHero)
                        .transition(GymMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                    }
                }

                Button(action: startActivationPlan) {
                    Text(gymText(
                        "Use suggested plan",
                        "Використати пораду",
                        "Использовать рекомендацию",
                        languageCode: languageCode
                    ))
                    .font(.headline)
                    .foregroundStyle(GymTheme.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .gymAccessibilityVerticalPadding()
                    .background(GymTheme.brandFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .buttonStyle(.plain)
                .appTutorialPrimaryActionTarget()
                .appTutorialPrimaryActionFrame(
                    isEnabled: tracksTutorialPrimaryActionFrame,
                    onTutorialPrimaryActionFrameChange
                )

                Button(action: createActivationManually) {
                    Text(gymText(
                        "Build manually",
                        "Створити вручну",
                        "Собрать вручную",
                        languageCode: languageCode
                    ))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GymTheme.heroActionLabel)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            todayRows(
                hasRetainedWorkoutDraft
                    ? focusRowItems(launchSeed: nil, completedToday: false)
                    : [trainWithFriendRowItem()].compactMap { $0 }
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { activationLensShape.fill(GymTheme.heroSurface) }
        .overlay {
            activationLensShape.strokeBorder(GymTheme.heroOutline, lineWidth: 1)
        }
        .clipShape(activationLensShape)
        .appTutorialTarget(.todayFocus)
    }

    private func createActivationManually() {
        let profileStore = TrainingProfileStore()
        guard profileStore.setActivationDismissed(
            true,
            accountStorageKey: store.accountStorageKey
        ) else { return }
        guard onAddWorkout(nil) else {
            profileStore.setActivationDismissed(
                false,
                accountStorageKey: store.accountStorageKey
            )
            return
        }
        activationDismissed = true
    }

    private var emptyStateHint: some View {
        Text(gymLocalized(
            "Your workouts and weekly progress will show up here.",
            languageCode: languageCode
        ))
        .font(.subheadline)
        .foregroundStyle(GymTheme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var activationLensShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 28,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
            style: .continuous
        )
    }

    private func activationChoiceRow<Value: Hashable>(
        title: String,
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.onHeroSecondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = selection.wrappedValue == option
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            Text(label(option))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(ActivationChipButtonStyle(isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// A fixed single row of equal-width chips, used for the three-option
    /// effort picker so every label stays fully visible (no clipping, no
    /// two-column wrap) even for the longest supported-language string.
    private func activationEffortRow(
        title: String,
        options: [SmartWorkoutEffort],
        selection: Binding<SmartWorkoutEffort>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.onHeroSecondary)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.gymDisplayName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActivationChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func startActivationPlan() {
        commitActivationPlan(launch: onStartPlan)
    }

    private func editActivationPlan() {
        commitActivationPlan(launch: onAddWorkout)
    }

    private func commitActivationPlan(launch: (WorkoutLaunchSeed) -> Bool) {
        let now = Date()
        referenceDate = now
        let profile = activationProfile
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: store.exercises,
            history: [],
            muscleMappings: store.muscleMappings,
            trainingProfile: profile,
            effort: activationEffort,
            now: now,
            calendar: calendar
        )
        let seed = WorkoutLaunchSeed(
            accountStorageKey: store.accountStorageKey,
            profile: profile,
            requestedEffort: activationEffort,
            plan: plan,
            catalog: store.exercises,
            history: [],
            muscleMappings: store.muscleMappings,
            createdAt: now
        )
        let committed = FirstWorkoutActivation.commit(
            seed: seed,
            accountStorageKey: store.accountStorageKey,
            catalog: store.exercises,
            muscleMappings: store.muscleMappings,
            profileStore: TrainingProfileStore(),
            now: now,
            launch: launch
        )
        if committed { activationDismissed = true }
    }

    private var todayProjection: TodayScreenProjection {
        projectionCache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: TrainingProfileStore().load(
                accountStorageKey: store.accountStorageKey
            ),
            monthOffset: monthOffset,
            weekOffset: weekOffset
        )
    }

    private func todayTitle(
        guidance: WeeklyTrainingGuidance,
        plan: SmartWorkoutPlan?
    ) -> String {
        if guidance.decision == .rest {
            return gymText(
                "Rest today",
                "Сьогодні відпочинок",
                "Сегодня отдых",
                languageCode: languageCode
            )
        }
        if guidance.decision == .recovery {
            return gymText(
                "Recovery plan",
                "План відновлення",
                "План восстановления",
                languageCode: languageCode
            )
        }
        return plan?.focus.displayName ?? gymText(
            "Start workout",
            "Почати тренування",
            "Начать тренировку",
            languageCode: languageCode
        )
    }

    private func todayPrimaryActionTitle(
        guidance: WeeklyTrainingGuidance,
        hasRecommendedPlan: Bool
    ) -> String {
        guard hasRecommendedPlan else {
            return gymText(
                "Start workout",
                "Почати тренування",
                "Начать тренировку",
                languageCode: languageCode
            )
        }
        return guidance.decision != .train
            ? gymText("Train anyway", "Усе одно тренуватися", "Всё равно тренироваться", languageCode: languageCode)
            : gymText(
                "Start",
                "Почати",
                "Начать",
                languageCode: languageCode
            )
    }

    // MARK: - Today card

    private var focusLens: some View {
        let projection = todayProjection
        let guidance = projection.weeklyGuidance
        let completedToday = projection.weeklySummary.hasCompletedWorkoutToday(
            now: referenceDate,
            calendar: calendar
        )
        let launchSeed = projection.launchSeed
        return VStack(alignment: .leading, spacing: 14) {
            if completedToday {
                completedTodayHeader
            } else {
                planHeader(guidance: guidance, plan: launchSeed?.plan)
                if guidance.decision != .train {
                    recoverySummary(guidance)
                }
                if showsFocusDetails {
                    focusDetailsContent(projection, guidance: guidance)
                }
            }

            focusPrimaryAction(
                launchSeed: launchSeed,
                guidance: guidance,
                completedToday: completedToday
            )

            todayRows(focusRowItems(
                launchSeed: launchSeed,
                completedToday: completedToday
            ))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { activationLensShape.fill(GymTheme.heroSurface) }
        .overlay { activationLensShape.strokeBorder(GymTheme.heroOutline, lineWidth: 1) }
        .clipShape(activationLensShape)
        .appTutorialTarget(.todayFocus)
    }

    /// Plan title with its one-line size. Tapping it expands the plan details.
    private func planHeader(guidance: WeeklyTrainingGuidance, plan: SmartWorkoutPlan?) -> some View {
        let title = todayTitle(guidance: guidance, plan: plan)
        let subtitle = guidance.decision == .train ? planSubtitle(plan: plan) : nil
        return Button {
            withAnimation(GymMotion.animation(GymMotion.quick, reduceMotion: reduceMotion)) {
                showsFocusDetails.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(GymTheme.onHero)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.onHeroSecondary)
                    .rotationEffect(.degrees(showsFocusDetails ? 180 : 0))
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(gymText(
            "Plan details", "Деталі плану", "Детали плана",
            languageCode: languageCode
        ))
        .accessibilityValue(showsFocusDetails
            ? gymText("Expanded", "Розгорнуто", "Развёрнуто", languageCode: languageCode)
            : gymText("Collapsed", "Згорнуто", "Свёрнуто", languageCode: languageCode)
        )
    }

    /// "5 упражнений · 14 подходов · около 55 мин"; the saved plan draft wins over the generated one.
    private func planSubtitle(plan: SmartWorkoutPlan?) -> String? {
        let exerciseCount: Int
        let setCount: Int
        if hasRetainedWorkoutDraft, let counts = retainedPlanCounts, counts.exercises > 0 {
            exerciseCount = counts.exercises
            setCount = counts.sets
        } else if let plan {
            exerciseCount = plan.exercises.count
            setCount = plan.exercises.reduce(0) { $0 + $1.recommendation.sets.count }
        } else {
            return nil
        }
        let minutes = TodayFocusPlanMetrics.estimatedMinutes(
            exerciseCount: exerciseCount,
            setCount: setCount
        )
        let exercises = "\(exerciseCount) " + gymPlural(
            exerciseCount,
            en: ("exercise", "exercises"),
            uk: ("вправа", "вправи", "вправ"),
            ru: ("упражнение", "упражнения", "упражнений"),
            languageCode: languageCode
        )
        let sets = "\(setCount) " + gymPlural(
            setCount,
            en: ("set", "sets"),
            uk: ("підхід", "підходи", "підходів"),
            ru: ("подход", "подхода", "подходов"),
            languageCode: languageCode
        )
        let duration = gymText(
            "about \(minutes)\u{00A0}min",
            "близько \(minutes)\u{00A0}хв",
            "около \(minutes)\u{00A0}мин",
            languageCode: languageCode
        )
        return "\(exercises) · \(sets) · \(duration)"
    }

    private func focusDetailsContent(
        _ projection: TodayScreenProjection,
        guidance: WeeklyTrainingGuidance
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if guidance.decision == .train {
                Text(todayPlanExplanation(guidance))
                    .font(.footnote)
                    .foregroundStyle(GymTheme.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            todayHeroMetricsRow(projection.heroMetrics)
            todayRows([
                TodayRowItem(
                    id: "build-manually",
                    title: gymText("Build manually", "Створити вручну", "Собрать вручную", languageCode: languageCode),
                    systemImage: "plus",
                    showsChevron: true,
                    hint: gymText(
                        "Opens a blank workout plan",
                        "Відкриває порожній план тренування",
                        "Открывает пустой план тренировки",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    _ = onAddWorkout(nil)
                }
            ])
        }
    }

    @ViewBuilder
    private var completedTodayHeader: some View {
        Text(gymText(
            "Workout complete", "Тренування завершено", "Тренировка завершена",
            languageCode: languageCode
        ))
        .font(.title2.bold())
        .foregroundStyle(GymTheme.onHero)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        if let workout = todaysLatestWorkout {
            completedSummaryRow(workout)
        }
    }

    private var todaysLatestWorkout: WorkoutSessionSummary? {
        store.workoutSummaries
            .filter { calendar.isDate($0.date, inSameDayAs: referenceDate) && $0.date <= referenceDate }
            .max { $0.date < $1.date }
    }

    /// "Жим лёжа · 35 мин · 460 кг ›" opens the workout that was just saved.
    private func completedSummaryRow(_ workout: WorkoutSessionSummary) -> some View {
        let activityOnly = isActivityOnly(workout)
        let firstExerciseID = store.workouts.first { $0.id == workout.workoutID }?.exercises.first?.exerciseID
        let name = firstExerciseID.flatMap { store.exercise(id: $0) }.map { gymExerciseName($0) }
            ?? gymText("Workout", "Тренування", "Тренировка", languageCode: languageCode)
        let minutes = WeeklyTrainingSummary.durationMinutes(for: workout)
        var parts = [
            name,
            gymText(
                "\(minutes)\u{00A0}min", "\(minutes)\u{00A0}хв", "\(minutes)\u{00A0}мин",
                languageCode: languageCode
            )
        ]
        if !activityOnly, workout.totalVolume > 0 {
            parts.append(
                "\(formattedTodayHeroVolume(workout.totalVolume))\u{00A0}\(gymLocalized("kg", languageCode: languageCode))"
            )
        }
        return Button {
            historyReturnWorkoutID = workout.workoutID
            onOpenWorkout(workout.workoutID)
        } label: {
            HStack(spacing: 8) {
                Text(parts.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.onHero)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.onHeroSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .gymAccessibilityVerticalPadding()
            .background(GymTheme.heroTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(gymText(
            "Opens workout details",
            "Відкриває деталі тренування",
            "Открывает детали тренировки",
            languageCode: languageCode
        ))
    }

    // MARK: Primary action and rows

    private func todayPrimaryButton(
        title: String,
        systemImage: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(GymTheme.onPrimary)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 52)
                .gymAccessibilityVerticalPadding()
        }
        .buttonStyle(.plain)
        .background(GymTheme.brandFill, in: Capsule())
        .accessibilityHint(hint)
    }

    private var canRepeatLastWorkout: Bool {
        RepeatLastWorkout.shouldShowAction(
            hasRepeatableWorkout: store.workoutSummaries.contains { $0.setCount > 0 },
            hasActiveWorkout: activeWorkoutDraft != nil,
            hasRetainedWorkoutDraft: hasRetainedWorkoutDraft
        )
    }

    /// The one primary capsule of the card: continue the saved plan, start the plan, or repeat the
    /// last workout after today's.
    @ViewBuilder
    private func focusPrimaryAction(
        launchSeed: WorkoutLaunchSeed?,
        guidance: WeeklyTrainingGuidance,
        completedToday: Bool
    ) -> some View {
        if hasRetainedWorkoutDraft {
            todayPrimaryButton(
                title: gymText("Continue plan", "Продовжити план", "Продолжить план", languageCode: languageCode),
                systemImage: "pencil",
                hint: gymText(
                    "Opens your saved workout plan",
                    "Відкриває збережений план тренування",
                    "Открывает сохранённый план тренировки",
                    languageCode: languageCode
                )
            ) {
                referenceDate = Date()
                _ = onAddWorkout(nil)
            }
            .appTutorialPrimaryActionTarget()
            .appTutorialPrimaryActionFrame(
                isEnabled: tracksTutorialPrimaryActionFrame,
                onTutorialPrimaryActionFrameChange
            )
        } else if completedToday {
            if canRepeatLastWorkout {
                todayPrimaryButton(
                    title: gymText(
                        "Repeat last", "Повторити останнє", "Повторить последнюю",
                        languageCode: languageCode
                    ),
                    systemImage: "arrow.counterclockwise",
                    hint: gymText(
                        "Starts a copy of your latest workout now",
                        "Одразу починає копію останнього тренування",
                        "Сразу начинает копию последней тренировки",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    onRepeatLastWorkout()
                }
            }
        } else if let launchSeed {
            todayPrimaryButton(
                title: todayPrimaryActionTitle(guidance: guidance, hasRecommendedPlan: true),
                systemImage: "play.fill",
                hint: gymText(
                    "Starts this exact plan now",
                    "Одразу починає цей точний план",
                    "Сразу начинает этот точный план",
                    languageCode: languageCode
                )
            ) {
                referenceDate = Date()
                _ = onStartPlan(launchSeed)
            }
            .appTutorialPrimaryActionTarget()
            .appTutorialPrimaryActionFrame(
                isEnabled: tracksTutorialPrimaryActionFrame,
                onTutorialPrimaryActionFrameChange
            )
        } else {
            todayPrimaryButton(
                title: todayPrimaryActionTitle(guidance: guidance, hasRecommendedPlan: false),
                systemImage: "plus",
                hint: gymText(
                    "Opens a blank workout plan",
                    "Відкриває порожній план тренування",
                    "Открывает пустой план тренировки",
                    languageCode: languageCode
                )
            ) {
                referenceDate = Date()
                _ = onAddWorkout(nil)
            }
            .appTutorialPrimaryActionTarget()
            .appTutorialPrimaryActionFrame(
                isEnabled: tracksTutorialPrimaryActionFrame,
                onTutorialPrimaryActionFrameChange
            )
        }
    }

    /// Secondary actions as one grouped list under the primary capsule.
    private func focusRowItems(
        launchSeed: WorkoutLaunchSeed?,
        completedToday: Bool
    ) -> [TodayRowItem] {
        var items: [TodayRowItem] = []
        if hasRetainedWorkoutDraft {
            items.append(TodayRowItem(
                id: "cancel-plan",
                title: gymText("Cancel plan", "Скасувати план", "Отменить план", languageCode: languageCode),
                systemImage: "xmark",
                isDestructive: true,
                showsChevron: false,
                hint: gymText(
                    "Asks before removing this saved plan",
                    "Запитує підтвердження перед видаленням збереженого плану",
                    "Запрашивает подтверждение перед удалением сохранённого плана",
                    languageCode: languageCode
                )
            ) {
                showsRetainedPlanCancelConfirmation = true
            })
        } else if completedToday {
            items.append(TodayRowItem(
                id: "add-another",
                title: gymText(
                    "Add another workout", "Додати ще одне тренування", "Добавить ещё одну тренировку",
                    languageCode: languageCode
                ),
                systemImage: "plus",
                hint: gymText(
                    "Opens a blank workout plan without changing the completed workout",
                    "Відкриває порожній план, не змінюючи завершене тренування",
                    "Открывает пустой план, не изменяя завершённую тренировку",
                    languageCode: languageCode
                )
            ) {
                referenceDate = Date()
                _ = onAddWorkout(nil)
            })
        } else {
            if let launchSeed {
                items.append(TodayRowItem(
                    id: "edit-plan",
                    title: gymText("Edit plan", "Редагувати план", "Редактировать план", languageCode: languageCode),
                    systemImage: "pencil",
                    hint: gymText(
                        "Opens this plan in the editor",
                        "Відкриває цей план у редакторі",
                        "Открывает этот план в редакторе",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    _ = onAddWorkout(launchSeed)
                })
            }
            if canRepeatLastWorkout {
                items.append(TodayRowItem(
                    id: "repeat-last",
                    title: gymText(
                        "Repeat last workout", "Повторити останнє тренування", "Повторить последнюю тренировку",
                        languageCode: languageCode
                    ),
                    systemImage: "arrow.counterclockwise",
                    hint: gymText(
                        "Starts a copy of your latest workout now",
                        "Одразу починає копію останнього тренування",
                        "Сразу начинает копию последней тренировки",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    onRepeatLastWorkout()
                })
            }
        }
        if let friend = trainWithFriendRowItem() {
            items.append(friend)
        }
        return items
    }

    /// Inset grouped rows: accent label and icon, hairline separators, chevron where it navigates.
    @ViewBuilder
    private func todayRows(_ items: [TodayRowItem]) -> some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(GymTheme.heroOutline)
                    }
                    todayRow(item)
                }
            }
        }
    }

    private func todayRow(_ item: TodayRowItem) -> some View {
        let tint = item.isDestructive ? GymTheme.error : GymTheme.heroActionLabel
        return Button(action: item.action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.body.weight(.medium))
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = item.badge {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(GymTheme.onPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(GymTheme.brandFill, in: Capsule())
                }
                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GymTheme.onHeroSecondary.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(tint)
            .frame(minHeight: 48)
            .gymAccessibilityVerticalPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.hint)
    }

    // MARK: - Active workout card

    private var activeFocusLens: some View {
        let projection = todayProjection
        let draft = activeWorkoutDraft
        let currentExercise = draft?.exercises.first(where: { exercise in
            exercise.sets.contains(where: { !$0.isCompleted })
        })
        let currentSetIndex = currentExercise?.sets.firstIndex(where: { !$0.isCompleted })
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        currentExercise.flatMap { store.exercise(id: $0.exerciseID) }
                            .map { gymExerciseName($0) } ?? gymText(
                                "Next exercise",
                                "Наступна вправа",
                                "Следующее упражнение",
                                languageCode: languageCode
                            )
                    )
                    .font(.title2.bold())
                    .foregroundStyle(GymTheme.onHero)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                    if let draft {
                        Text(gymText(
                            "Set \((currentSetIndex ?? 0) + 1) · \(draft.completedSetCount) / \(draft.plannedSetCount) completed",
                            "Підхід \((currentSetIndex ?? 0) + 1) · виконано \(draft.completedSetCount) / \(draft.plannedSetCount)",
                            "Подход \((currentSetIndex ?? 0) + 1) · выполнено \(draft.completedSetCount) / \(draft.plannedSetCount)",
                            languageCode: languageCode
                        ))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(GymTheme.onHeroSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                activeWorkoutMenu
            }

            DisclosureGroup(
                gymText(
                    "Plan details",
                    "Деталі плану",
                    "Детали плана",
                    languageCode: languageCode
                ),
                isExpanded: $showsActiveFocusDetails
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    todayHeroMetricsRow(projection.heroMetrics)
                }
                .padding(.top, 8)
            }
            .disclosureGroupStyle(TodayHeroDisclosureStyle())
            .tint(GymTheme.heroActionLabel)
            .foregroundStyle(GymTheme.onHero)

            todayPrimaryButton(
                title: gymText(
                    "Continue workout", "Продовжити тренування", "Продолжить тренировку",
                    languageCode: languageCode
                ),
                systemImage: "play.fill",
                hint: ""
            ) {
                onContinueWorkout()
            }
            .appTutorialPrimaryActionTarget()
            .appTutorialPrimaryActionFrame(
                isEnabled: tracksTutorialPrimaryActionFrame,
                onTutorialPrimaryActionFrameChange
            )

            todayRows([trainWithFriendRowItem(forcedVisible: true)].compactMap { $0 })
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { activationLensShape.fill(GymTheme.heroSurface) }
        .overlay { activationLensShape.strokeBorder(GymTheme.heroOutline, lineWidth: 1) }
        .clipShape(activationLensShape)
        .appTutorialTarget(.todayFocus)
    }

    /// The card's ⋯ menu: the destructive discard lives here, behind the existing confirmation
    /// (`onDiscardWorkout` only asks), not as a full-width red button.
    private var activeWorkoutMenu: some View {
        Menu {
            Button(role: .destructive, action: onDiscardWorkout) {
                Label(
                    gymText(
                        "Discard workout", "Відкинути тренування", "Удалить тренировку",
                        languageCode: languageCode
                    ),
                    systemImage: "trash"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(GymTheme.heroActionLabel)
                .frame(width: 44, height: 44)
                .background(GymTheme.heroTile, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(gymText(
            "More workout options", "Інші дії", "Другие действия",
            languageCode: languageCode
        ))
    }

    private func todayPlanExplanation(_ guidance: WeeklyTrainingGuidance) -> String {
        switch guidance.decision {
        case .train:
            gymText(
                "Built from your goal, weekly rhythm, and recent workout history.",
                "План враховує ціль, ритм тижня та недавню історію тренувань.",
                "План учитывает цель, ритм недели и недавнюю историю тренировок.",
                languageCode: languageCode
            )
        case .recovery, .rest:
            gymText(
                "Recovery is recommended from your weekly rhythm and latest workout feedback.",
                "Відновлення рекомендовано за ритмом тижня та відгуком про останнє тренування.",
                "Восстановление рекомендовано по ритму недели и отзыву о последней тренировке.",
                languageCode: languageCode
            )
        }
    }

    private func recoverySummary(_ guidance: WeeklyTrainingGuidance) -> some View {
        let nextDay: Date
        if guidance.decision == .rest {
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: referenceDate)
                ?? referenceDate.addingTimeInterval(7 * 24 * 60 * 60)
            nextDay = calendar.gymMondayStart(of: nextWeek)
        } else {
            nextDay = calendar.date(byAdding: .day, value: 1, to: referenceDate)
                ?? referenceDate.addingTimeInterval(24 * 60 * 60)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(todayPlanExplanation(guidance))
                .font(.subheadline)
                .foregroundStyle(GymTheme.onHeroSecondary)
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text(gymText(
                    "Next recommended day: \(gymShortDate(nextDay))",
                    "Наступний рекомендований день: \(gymShortDate(nextDay))",
                    "Следующий рекомендуемый день: \(gymShortDate(nextDay))",
                    languageCode: languageCode
                ))
            }
            .font(.subheadline.bold())
            .foregroundStyle(GymTheme.onHero)
        }
    }

    /// One history card on Today: the compact version (current week, three recent workouts and an
    /// "All history" row) or, once opened in place, the full one with period switch, search and month.
    private var trainingHistoryPanel: some View {
        Group {
            if showsFullHistory {
                fullHistoryPanel
            } else {
                compactHistoryPanel
            }
        }
        .id("workout-history")
    }

    private var compactHistoryPanel: some View {
        let projection = todayProjection
        let weekly = projection.weeklySummary
        let recent = Array(
            store.workoutSummaries
                .filter { $0.date <= referenceDate }
                .sorted { $0.date > $1.date }
                .prefix(3)
        )
        return GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                historyHeader(
                    completedTrainingDays: weekly.completedTrainingDays.count,
                    targetTrainingDays: projection.trainingProfile.workoutsPerWeek,
                    isExpanded: false
                )
                weeklyTrainingDayStrip(weekly)
                historyStatsBlock(
                    weekly: weekly,
                    showsComparison: true,
                    workouts: weekly.completedSessionCount,
                    minutes: weekly.totalMinutes,
                    volume: weekly.totalVolume
                )
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, workout in
                        if index > 0 { Divider().overlay(GymTheme.outlineSoft) }
                        trainingHistoryRow(workout)
                    }
                    if !recent.isEmpty { Divider().overlay(GymTheme.outlineSoft) }
                    Button {
                        setHistoryExpanded(true)
                    } label: {
                        HStack(spacing: 12) {
                            Text(gymText(
                                "All history", "Уся історія", "Вся история",
                                languageCode: languageCode
                            ))
                            .font(.body)
                            .foregroundStyle(GymTheme.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(gymText(
                        "Shows the week and month calendar and searches past workouts",
                        "Показує тиждень, місяць і пошук за минулими тренуваннями",
                        "Показывает неделю, месяц и поиск по прошлым тренировкам",
                        languageCode: languageCode
                    ))
                }
            }
        }
    }

    private func setHistoryExpanded(_ expanded: Bool) {
        withAnimation(GymMotion.animation(GymMotion.quick, reduceMotion: reduceMotion)) {
            showsFullHistory = expanded
        }
        if !expanded {
            weekOffset = 0
            monthOffset = 0
            historyPeriod = .week
            historySearchQuery = ""
            historySearchFocused = false
        }
    }

    /// Title with the weekly goal as a plain subtitle (the day count in month view) and, in the
    /// full history, a way back to the compact card.
    private func historyHeader(
        completedTrainingDays: Int,
        targetTrainingDays: Int,
        isExpanded: Bool
    ) -> some View {
        let subtitle = historyPeriod == .week || !isExpanded
            ? gymText(
                "Goal: \(completedTrainingDays) of \(targetTrainingDays)",
                "Ціль: \(completedTrainingDays) з \(targetTrainingDays)",
                "Цель: \(completedTrainingDays) из \(targetTrainingDays)",
                languageCode: languageCode
            )
            : gymCount(
                completedTrainingDays,
                englishOne: "day",
                englishMany: "days",
                ukrainianOne: "день",
                ukrainianFew: "дні",
                ukrainianMany: "днів",
                languageCode: languageCode
            )
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gymText(
                    "Training history",
                    "Історія тренувань",
                    "История тренировок",
                    languageCode: languageCode
                ))
                .font(GymTheme.TypeScale.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isExpanded {
                Button {
                    setHistoryExpanded(false)
                } label: {
                    Text(gymText("Collapse", "Згорнути", "Свернуть", languageCode: languageCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "5 тренировок · 190 минут · 12 345 кг объём" with unit labels that agree with the numbers,
    /// plus the week-over-week line only when both weeks have a workout.
    private func historyStatsBlock(
        weekly: WeeklyTrainingSummary,
        showsComparison: Bool,
        workouts: Int,
        minutes: Int,
        volume: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GymAdaptiveStack(rowAlignment: .top, spacing: 8) {
                weeklyTrainingMetric(
                    value: workouts.formatted(.number.locale(gymAppLocale())),
                    label: TodayPresentation.statLabel(.workout, count: workouts, languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: minutes.formatted(.number.locale(gymAppLocale())),
                    label: TodayPresentation.statLabel(.minute, count: minutes, languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: formattedTodayHeroVolumeWithUnit(volume),
                    label: gymText("volume", "обсяг", "объём", languageCode: languageCode)
                )
            }
            if showsComparison, weekly.showsVolumeComparison, let deltaPercent = weekly.volumeDeltaPercent {
                Text(
                    weekVolumeDeltaText(deltaPercent, locale: gymAppLocale())
                        + " "
                        + (weekOffset == 0
                            ? gymText(
                                "vs same days last week",
                                "порівняно з тими ж днями минулого тижня",
                                "по сравнению с теми же днями прошлой недели",
                                languageCode: languageCode
                            )
                            : gymText(
                                "vs previous week",
                                "порівняно з попереднім тижнем",
                                "по сравнению с предыдущей неделей",
                                languageCode: languageCode
                            ))
                )
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var fullHistoryPanel: some View {
        let projection = todayProjection
        let weekly = projection.historyWeekSummary
        let monthly = projection.monthSummary
        let workouts = historyPeriod == .week
            ? projection.historyWeekWorkouts
            : projection.monthWorkouts
        let completedSessionCount = historyPeriod == .week
            ? weekly.completedSessionCount
            : monthly.completedSessionCount
        let completedTrainingDays = historyPeriod == .week
            ? weekly.completedTrainingDays.count
            : monthly.completedTrainingDays.count
        let totalMinutes = historyPeriod == .week ? weekly.totalMinutes : monthly.totalMinutes
        let totalVolume = historyPeriod == .week ? weekly.totalVolume : monthly.totalVolume
        return GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                historyHeader(
                    completedTrainingDays: completedTrainingDays,
                    targetTrainingDays: projection.trainingProfile.workoutsPerWeek,
                    isExpanded: true
                )

                GymSegmentedControl(
                    gymText(
                        "History period", "Період історії", "Период истории",
                        languageCode: languageCode
                    ),
                    selection: $historyPeriod,
                    options: [
                        (.week, gymText("Week", "Тиждень", "Неделя", languageCode: languageCode)),
                        (.month, gymText("Month", "Місяць", "Месяц", languageCode: languageCode))
                    ]
                )

                HStack(spacing: 8) {
                    weekNavigationButton(
                        systemImage: "chevron.left",
                        label: historyPeriod == .week
                            ? gymText(
                                "Previous week", "Попередній тиждень", "Предыдущая неделя",
                                languageCode: languageCode
                            )
                            : gymText(
                                "Previous month", "Попередній місяць", "Предыдущий месяц",
                                languageCode: languageCode
                            ),
                        action: moveHistoryBackward
                    )
                    Button(action: returnToCurrentHistoryPeriod) {
                        VStack(spacing: 2) {
                            Text(historyPeriodTitle(weeklySummary: weekly))
                                .font(.subheadline.bold())
                                .foregroundStyle(GymTheme.textPrimary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                                .multilineTextAlignment(.center)
                            Text(historyPeriodSubtitle)
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(HistoryRangeButtonStyle())
                    .disabled(selectedHistoryOffset == 0)
                    weekNavigationButton(
                        systemImage: "chevron.right",
                        label: historyPeriod == .week
                            ? gymText(
                                "Next week", "Наступний тиждень", "Следующая неделя",
                                languageCode: languageCode
                            )
                            : gymText(
                                "Next month", "Наступний місяць", "Следующий месяц",
                                languageCode: languageCode
                            ),
                        disabled: selectedHistoryOffset == 0,
                        action: moveHistoryForward
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    if historyPeriod == .week {
                        weeklyTrainingDayStrip(weekly)
                    } else {
                        monthlyTrainingCalendar(monthly)
                    }

                    historyStatsBlock(
                        weekly: weekly,
                        showsComparison: historyPeriod == .week,
                        workouts: completedSessionCount,
                        minutes: totalMinutes,
                        volume: totalVolume
                    )

                    Divider().overlay(GymTheme.outlineSoft)
                    if hasHistorySearchableWorkouts {
                        historySearchField
                    }
                    if isSearchingHistory {
                        let results = historySearchResults()
                        if results.isEmpty {
                            Text(gymText(
                                "No workouts with this exercise",
                                "Немає тренувань із такою вправою",
                                "Нет тренировок с таким упражнением",
                                languageCode: languageCode
                            ))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, workout in
                                if index > 0 { Divider().overlay(GymTheme.outlineSoft) }
                                trainingHistoryRow(workout)
                            }
                        }
                    } else if workouts.isEmpty {
                        Text(historyPeriod == .week
                            ? gymText(
                                "No workouts in this week yet.",
                                "Цього тижня тренувань поки немає.",
                                "На этой неделе тренировок пока нет.",
                                languageCode: languageCode
                            )
                            : gymText(
                                "No workouts in this month yet.",
                                "Цього місяця тренувань поки немає.",
                                "В этом месяце тренировок пока нет.",
                                languageCode: languageCode
                            ))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                            if index > 0 { Divider().overlay(GymTheme.outlineSoft) }
                            trainingHistoryRow(workout)
                        }
                    }
                }
                .gymTrackedPageSwipe(
                    canGoPrevious: historyPeriod == .week ? weekOffset > -5_200 : monthOffset > -1_200,
                    canGoNext: selectedHistoryOffset < 0
                ) { direction in
                    switch direction {
                    case .previous: moveHistoryBackward()
                    case .next: moveHistoryForward()
                    }
                }
            }
        }
    }

    private static let historySearchFieldID = "workout-history-search"

    /// Scrolls the search field to the top of the visible area (the scroll view is already
    /// shortened by the keyboard) so the results below it stay visible. Snaps instead of
    /// animating when Reduce Motion is on.
    private func revealHistorySearch(_ proxy: ScrollViewProxy, afterKeyboardOpens: Bool) {
        Task { @MainActor in
            if afterKeyboardOpens {
                try? await Task.sleep(for: .milliseconds(450))
            } else {
                await Task.yield()
            }
            guard historySearchFocused else { return }
            if reduceMotion {
                proxy.scrollTo(Self.historySearchFieldID, anchor: .top)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(Self.historySearchFieldID, anchor: .top)
                }
            }
        }
    }

    private var isSearchingHistory: Bool {
        !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasHistorySearchableWorkouts: Bool {
        !store.workouts.isEmpty
    }

    /// Matches among ALL past workouts (not in the future), newest first, capped for display. The
    /// period header, strip/grid and totals stay computed from the unfiltered period data.
    private func historySearchResults() -> [WorkoutSessionSummary] {
        let namesByExerciseID = Dictionary(
            store.exercises.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        var namesByWorkoutID: [UUID: [String]] = [:]
        for workout in store.workouts {
            namesByWorkoutID[workout.id] = workout.exercises.compactMap { namesByExerciseID[$0.exerciseID] }
        }
        let past = store.workoutSummaries
            .filter { $0.date <= referenceDate }
            .sorted { $0.date > $1.date }
        return Array(
            HistoryExerciseSearch.filter(past, query: historySearchQuery) { workout in
                namesByWorkoutID[workout.workoutID] ?? []
            }.prefix(HistoryExerciseSearch.displayLimit)
        )
    }

    private var historySearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(
                gymText("Search by exercise", "Пошук за вправою", "Поиск по упражнению", languageCode: languageCode),
                text: $historySearchQuery
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($historySearchFocused)
            .onSubmit { historySearchFocused = false }
            .onChange(of: historySearchQuery) { _, value in
                if value.count > HistoryExerciseSearch.maximumQueryCharacters {
                    historySearchQuery = String(value.prefix(HistoryExerciseSearch.maximumQueryCharacters))
                }
            }
            if !historySearchQuery.isEmpty {
                Button {
                    historySearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GymTheme.textSecondary)
                }
                // 44pt hit area without growing the field.
                .padding(12)
                .contentShape(Rectangle())
                .padding(-12)
                .accessibilityLabel(gymText("Clear search", "Очистити пошук", "Очистить поиск", languageCode: languageCode))
            }
        }
        .gymTextFieldChrome()
        .id(Self.historySearchFieldID)
    }

    private var selectedHistoryOffset: Int {
        historyPeriod == .week ? weekOffset : monthOffset
    }

    private var historyPeriodSubtitle: String {
        guard selectedHistoryOffset != 0 else {
            return historyPeriod == .week
                ? gymText(
                    "This week", "Цього тижня", "На этой неделе",
                    languageCode: languageCode
                )
                : gymText(
                    "Current month", "Поточний місяць", "Текущий месяц",
                    languageCode: languageCode
                )
        }
        return historyPeriod == .week
            ? gymText(
                "Return to this week",
                "Повернутися до цього тижня",
                "Вернуться к этой неделе",
                languageCode: languageCode
            )
            : gymText(
                "Return to current month",
                "Повернутися до поточного місяця",
                "Вернуться к текущему месяцу",
                languageCode: languageCode
            )
    }

    private func historyPeriodTitle(weeklySummary: WeeklyTrainingSummary) -> String {
        if historyPeriod == .week { return weeklyRangeTitle(weeklySummary) }
        let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
        return selectedMonth.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    private func moveHistoryBackward() {
        if historyPeriod == .week {
            weekOffset = max(-5_200, weekOffset - 1)
        } else {
            monthOffset = max(-1_200, monthOffset - 1)
        }
    }

    private func moveHistoryForward() {
        if historyPeriod == .week {
            weekOffset = min(0, weekOffset + 1)
        } else {
            monthOffset = min(0, monthOffset + 1)
        }
    }

    private func returnToCurrentHistoryPeriod() {
        if historyPeriod == .week { weekOffset = 0 } else { monthOffset = 0 }
    }

    private func weeklyTrainingDayStrip(_ summary: WeeklyTrainingSummary) -> some View {
        HStack(spacing: 8) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: summary.weekStart
                ) ?? summary.weekStart
                let completed = summary.hasWorkout(on: day, calendar: calendar)
                VStack(spacing: 6) {
                    Text(weeklyDaySymbol(day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            calendar.isDate(day, inSameDayAs: referenceDate)
                                ? GymTheme.primary
                                : GymTheme.textSecondary
                        )
                    Circle()
                        .fill(completed ? GymTheme.secondary : GymTheme.surfaceVariant)
                        .frame(width: 14, height: 14)
                        .overlay {
                            if calendar.isDate(day, inSameDayAs: referenceDate) {
                                Circle()
                                    .stroke(GymTheme.primary, lineWidth: 2)
                                    .padding(-4)
                            }
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    gymFormattedDate(
                        day,
                        date: .long,
                        time: .omitted,
                        languageCode: languageCode
                    )
                )
                .accessibilityValue(completed
                    ? gymText(
                        "Workout completed", "Тренування виконано", "Тренировка выполнена",
                        languageCode: languageCode
                    )
                    : gymText(
                        "No completed workout",
                        "Немає виконаного тренування",
                        "Нет выполненной тренировки",
                        languageCode: languageCode
                    ))
            }
        }
    }

    private func monthlyTrainingCalendar(_ summary: MonthlyTrainingSummary) -> some View {
        let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        let mondayFirstSymbols = Array(symbols.dropFirst()) + Array(symbols.prefix(1))
        let dayCount = calendar.range(of: .day, in: .month, for: summary.monthStart)?.count ?? 0
        let leading = (calendar.component(.weekday, from: summary.monthStart) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(minimum: 24), spacing: 4), count: 7)
        return VStack(spacing: 5) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(mondayFirstSymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased(with: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0 ..< (leading + dayCount), id: \.self) { index in
                    if index < leading {
                        Color.clear.frame(height: 32)
                    } else {
                        let dayNumber = index - leading + 1
                        let day = calendar.date(
                            byAdding: .day,
                            value: dayNumber - 1,
                            to: summary.monthStart
                        ) ?? summary.monthStart
                        let completed = summary.hasWorkout(on: day, calendar: calendar)
                        Text(dayNumber.formatted(.number.locale(gymAppLocale())))
                            .font(.caption.weight(completed ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(
                                completed ? GymTheme.textPrimary : GymTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                completed ? GymTheme.secondary.opacity(0.18) : Color.clear,
                                in: Circle()
                            )
                            .overlay {
                                if calendar.isDate(day, inSameDayAs: referenceDate) {
                                    Circle().stroke(GymTheme.primary, lineWidth: 1.5)
                                }
                            }
                            .accessibilityLabel(
                                gymFormattedDate(
                                    day,
                                    date: .long,
                                    time: .omitted,
                                    languageCode: languageCode
                                )
                            )
                            .accessibilityValue(completed
                                ? gymText(
                                    "Workout completed",
                                    "Тренування виконано",
                                    "Тренировка выполнена",
                                    languageCode: languageCode
                                )
                                : gymText(
                                    "No completed workout",
                                    "Немає виконаного тренування",
                                    "Нет выполненной тренировки",
                                    languageCode: languageCode
                                ))
                    }
                }
            }
        }
    }

    private func trainingHistoryRow(_ workout: WorkoutSessionSummary) -> some View {
        let activityOnly = isActivityOnly(workout)
        let exerciseLabel = gymCount(
            workout.exerciseCount,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправа",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ",
            languageCode: languageCode
        )
        let setLabel = gymCount(
            workout.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів",
            languageCode: languageCode
        )
        let supporting = activityOnly
            ? gymText(
                "Garmin free workout",
                "Вільне тренування Garmin",
                "Свободная тренировка Garmin",
                languageCode: languageCode
            )
            : "\(exerciseLabel)\u{00A0}· \(setLabel)"
        return Button {
            historyReturnWorkoutID = workout.workoutID
            onOpenWorkout(workout.workoutID)
        } label: {
            GymAdaptiveStack(rowAlignment: .center, spacing: 10, columnSpacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gymShortDate(workout.date, calendar: calendar, languageCode: languageCode))
                    .font(.subheadline.bold())
                    .foregroundStyle(GymTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    Text(supporting)
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                GymAdaptiveSpacer(minLength: 4)
                HStack(spacing: 10) {
                Text(
                    activityOnly
                        ? compactHistoryDuration(workout.durationSeconds ?? 0)
                        : "\(formattedTodayHeroVolume(workout.totalVolume)) \(gymLocalized("kg", languageCode: languageCode))"
                )
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityLabel(
                    activityOnly
                        ? compactHistoryDuration(workout.durationSeconds ?? 0)
                        : "\(formattedTodayHeroVolumeAccessibility(workout.totalVolume)) \(gymLocalized("kg", languageCode: languageCode))"
                )
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(GymTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(workout.workoutID)
        .accessibilityHint(gymText(
            "Opens workout details",
            "Відкриває деталі тренування",
            "Открывает детали тренировки",
            languageCode: languageCode
        ))
    }

    private func weeklyTrainingSummaryView(
        _ summary: WeeklyTrainingSummary,
        workouts: [WorkoutSessionSummary],
        targetTrainingDays: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(gymText(
                    "Weekly rhythm",
                    "Ритм тижня",
                    "Ритм недели",
                    languageCode: languageCode
                ))
                .font(GymTheme.TypeScale.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                GymInfoPill(
                    gymText(
                        "\(summary.completedTrainingDays.count) / \(targetTrainingDays) \(targetTrainingDays == 1 ? "day" : "days")",
                        "\(summary.completedTrainingDays.count) / \(targetTrainingDays) \(gymPlural(targetTrainingDays, one: "день", few: "дні", many: "днів", languageCode: "uk"))",
                        "\(summary.completedTrainingDays.count) / \(targetTrainingDays) \(gymPlural(targetTrainingDays, one: "день", few: "дня", many: "дней", languageCode: "ru"))",
                        languageCode: languageCode
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
            }

            HStack(spacing: 8) {
                weekNavigationButton(
                    systemImage: "chevron.left",
                    label: gymText(
                        "Previous week",
                        "Попередній тиждень",
                        "Предыдущая неделя",
                        languageCode: languageCode
                    )
                ) {
                    weekOffset = max(-5_200, weekOffset - 1)
                }

                Button {
                    weekOffset = 0
                } label: {
                    VStack(spacing: 2) {
                        Text(weeklyRangeTitle(summary))
                            .font(.subheadline.bold())
                            .foregroundStyle(GymTheme.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.74)
                            .multilineTextAlignment(.center)
                        Text(weekOffset == 0
                            ? gymText(
                                "This week", "Цього тижня", "На этой неделе",
                                languageCode: languageCode
                            )
                            : gymText(
                                "Return to this week",
                                "Повернутися до цього тижня",
                                "Вернуться к этой неделе",
                                languageCode: languageCode
                            ))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(HistoryRangeButtonStyle())
                .disabled(weekOffset == 0)

                weekNavigationButton(
                    systemImage: "chevron.right",
                    label: gymText(
                        "Next week",
                        "Наступний тиждень",
                        "Следующая неделя",
                        languageCode: languageCode
                    ),
                    disabled: weekOffset == 0
                ) {
                    weekOffset = min(0, weekOffset + 1)
                }
            }

            HStack(spacing: 8) {
                ForEach(0 ..< 7, id: \.self) { offset in
                    let day = calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: summary.weekStart
                    ) ?? summary.weekStart
                    let completed = summary.hasWorkout(on: day, calendar: calendar)
                    VStack(spacing: 6) {
                        Text(weeklyDaySymbol(day))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                        Circle()
                            .fill(completed ? GymTheme.secondary : GymTheme.surfaceVariant)
                            .frame(width: 14, height: 14)
                            .overlay {
                                if calendar.isDate(day, inSameDayAs: referenceDate) {
                                    Circle()
                                        .stroke(GymTheme.primary, lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        gymFormattedDate(day, date: .long, time: .omitted, languageCode: languageCode)
                    )
                    .accessibilityValue(
                        completed
                            ? gymText(
                                "Workout completed",
                                "Тренування виконано",
                                "Тренировка выполнена",
                                languageCode: languageCode
                            )
                            : gymText(
                                "No completed workout",
                                "Немає виконаного тренування",
                                "Нет выполненной тренировки",
                                languageCode: languageCode
                            )
                    )
                }
            }

            HStack(alignment: .top, spacing: 8) {
                weeklyTrainingMetric(
                    value: summary.completedSessionCount.formatted(.number.locale(gymAppLocale())),
                    label: gymText("Workouts", "Тренування", "Тренировки", languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: summary.totalMinutes.formatted(.number.locale(gymAppLocale())),
                    label: gymText("Minutes", "Хвилини", "Минуты", languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: formattedTodayHeroVolumeWithUnit(summary.totalVolume),
                    label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode)
                )
            }

            if weekOffset != 0 {
                Divider().overlay(GymTheme.outlineSoft)
                historicalWeekWorkouts(workouts)
            }
        }
    }

    private func weekNavigationButton(
        systemImage: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .frame(width: 44, height: 44)
                .background(GymTheme.surfaceVariant, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func weeklyRangeTitle(_ summary: WeeklyTrainingSummary) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: summary.weekStart)
            ?? summary.weekStart
        let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        return "\(summary.weekStart.formatted(style)) – \(end.formatted(style))"
    }

    @ViewBuilder
    private func historicalWeekWorkouts(_ workouts: [WorkoutSessionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(gymText(
                    "Workouts this week",
                    "Тренування цього тижня",
                    "Тренировки за неделю",
                    languageCode: languageCode
                ))
                .font(.subheadline.bold())
                Spacer(minLength: 8)
                Text(workouts.count.formatted(.number.locale(gymAppLocale())))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(GymTheme.textSecondary)
            }

            if workouts.isEmpty {
                Text(gymText(
                    "No workouts were saved in this week.",
                    "Цього тижня тренувань не збережено.",
                    "На этой неделе тренировок не сохранено.",
                    languageCode: languageCode
                ))
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
            } else {
                ForEach(workouts) { workout in
                    Button {
                        historyReturnWorkoutID = workout.id
                        onOpenWorkout(workout.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(GymTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gymShortDate(workout.date, calendar: calendar, languageCode: languageCode))
                                .font(.subheadline.bold())
                                Text(gymCount(
                                    workout.exerciseCount,
                                    englishOne: "exercise",
                                    englishMany: "exercises",
                                    ukrainianOne: "вправа",
                                    ukrainianFew: "вправи",
                                    ukrainianMany: "вправ",
                                    languageCode: languageCode
                                ))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func weeklyDaySymbol(_ date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return TodayPresentation.weekdayLabel(
            mondayIndex: (weekday + 5) % 7,
            languageCode: languageCode
        )
    }

    private func weeklyTrainingMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func todayHeroMetricsRow(_ metrics: TodayHeroMetrics) -> some View {
        HStack(alignment: .top, spacing: 8) {
            todayHeroMetric(
                value: formattedTodayHeroCount(metrics.totalWorkouts),
                label: gymText(
                    "Total workouts",
                    "Усього тренувань",
                    "Всего тренировок",
                    languageCode: languageCode
                ),
                accessibilityValue: metrics.totalWorkouts.formatted(
                    .number.locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                )
            )
            todayHeroMetric(
                value: gymText(
                    "\(metrics.weeklyStreakWeeks) wk",
                    "\(metrics.weeklyStreakWeeks) тиж",
                    "\(metrics.weeklyStreakWeeks) нед",
                    languageCode: languageCode
                ),
                label: gymText(
                    "Week streak",
                    "Серія тижнів",
                    "Серия недель",
                    languageCode: languageCode
                ),
                accessibilityValue: "\(metrics.weeklyStreakWeeks) " + gymPlural(
                    metrics.weeklyStreakWeeks,
                    en: ("week", "weeks"),
                    uk: ("тиждень", "тижні", "тижнів"),
                    ru: ("неделя", "недели", "недель"),
                    languageCode: languageCode
                )
            )
            todayHeroMetric(
                value: formattedTodayHeroVolumeWithUnit(metrics.totalVolume),
                label: gymText(
                    "Total volume",
                    "Загальний обсяг",
                    "Общий объём",
                    languageCode: languageCode
                ),
                accessibilityValue: formattedTodayHeroVolumeAccessibility(metrics.totalVolume)
            )
        }
    }

    private func todayHeroMetric(
        value: String,
        label: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GymTheme.onHeroSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private func formattedTodayHeroCount(_ value: Int) -> String {
        Double(max(0, value)).formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func formattedTodayHeroVolumeWithUnit(_ value: Double) -> String {
        "\(formattedTodayHeroVolume(value)) \(gymLocalized("kg", languageCode: languageCode))"
    }

    private func formattedTodayHeroVolume(_ value: Double) -> String {
        let safeValue = value.isFinite && value >= 0
            ? min(value, maximumTodayHeroVolume)
            : 0
        return safeValue.formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func formattedTodayHeroVolumeAccessibility(_ value: Double) -> String {
        let safeValue = value.isFinite && value >= 0
            ? min(value, maximumTodayHeroVolume)
            : 0
        return safeValue.formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .grouping(.automatic)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private var friendEntryState: TodayFriendEntryState {
        TodayFriendEntryState(
            isCloudAccount: isCloudAccount,
            friendCount: friends.count,
            pendingInvitationCount: pendingInvitationCount,
            hasBlockingLiveWorkout: hasBlockingLiveWorkout
        )
    }

    /// The "С другом" row. `forcedVisible` is used by `activeFocusLens`
    /// (a solo workout is already in progress): the row always shows there,
    /// but tapping it only surfaces the same "finish current workout" guard
    /// message `openDirectLiveWorkoutEditor` uses — it never opens the
    /// friend picker while a solo workout is active.
    private func trainWithFriendRowItem(forcedVisible: Bool = false) -> TodayRowItem? {
        let state = friendEntryState
        if !forcedVisible, state.isHidden { return nil }
        let badgeCount: Int? = {
            if case let .pendingInvite(count) = state { return count }
            return nil
        }()
        let title = badgeCount != nil
            ? gymText("Invitation", "Запрошення", "Приглашение", languageCode: languageCode)
            : gymText("With a friend", "З другом", "С другом", languageCode: languageCode)
        return TodayRowItem(
            id: "friend",
            title: title,
            systemImage: "person.2",
            badge: badgeCount,
            showsChevron: true,
            hint: trainWithFriendAccessibilityHint(forcedVisible: forcedVisible, state: state)
        ) {
            handleTrainWithFriendTap(forcedVisible: forcedVisible, state: state)
        }
    }

    private func handleTrainWithFriendTap(forcedVisible: Bool, state: TodayFriendEntryState) {
        switch state.tapAction(forcedVisible: forcedVisible) {
        case .openAccount:
            onOpenAccount()
        case .openFriends:
            onOpenFriends()
        case .pickFriend:
            showsFriendPicker = true
        case .openInvites:
            onOpenInvites()
        case .blockedBySoloWorkout:
            onTrainWithFriendBlocked()
        case .none:
            break
        }
    }

    private func trainWithFriendAccessibilityHint(
        forcedVisible: Bool,
        state: TodayFriendEntryState
    ) -> String {
        if forcedVisible, state.tapAction(forcedVisible: true) != .openInvites {
            return gymText(
                "Finish your current workout before starting a live workout with a friend",
                "Завершіть поточне тренування, перш ніж почати спільне тренування з другом",
                "Завершите текущую тренировку, прежде чем начать совместную тренировку с другом",
                languageCode: languageCode
            )
        }
        switch state {
        case .needsCloudAccount:
            return gymText(
                "Opens account settings to sign in with a cloud account",
                "Відкриває налаштування акаунта для входу в хмарний акаунт",
                "Открывает настройки аккаунта для входа в облачный аккаунт",
                languageCode: languageCode
            )
        case .needsFriends:
            return gymText(
                "Opens your friends list to add a friend",
                "Відкриває список друзів, щоб додати друга",
                "Открывает список друзей, чтобы добавить друга",
                languageCode: languageCode
            )
        case .pickFriend:
            return gymText(
                "Choose a friend to start a live workout together",
                "Оберіть друга, щоб почати спільне тренування",
                "Выберите друга, чтобы начать совместную тренировку",
                languageCode: languageCode
            )
        case .pendingInvite:
            return gymText(
                "Opens your pending live workout invitation",
                "Відкриває запрошення на спільне тренування, що очікує",
                "Открывает ожидающее приглашение на совместную тренировку",
                languageCode: languageCode
            )
        case .hidden:
            return ""
        }
    }

    private var friendPickerSheet: some View {
        NavigationStack {
            Group {
                if friends.isEmpty {
                    ContentUnavailableView(
                        gymText(
                            "No friends yet",
                            "Поки що немає друзів",
                            "Пока нет друзей",
                            languageCode: languageCode
                        ),
                        systemImage: "person.2.slash"
                    )
                } else {
                    List(friends) { friend in
                        Button {
                            showsFriendPicker = false
                            onTrainWithFriend(friend)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(GymTheme.primary)
                                Text(friend.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(GymTheme.textPrimary)
                                Spacer()
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(friend.displayName)
                        .accessibilityHint(gymText(
                            "Starts a live workout with this friend",
                            "Починає спільне тренування з цим другом",
                            "Начинает совместную тренировку с этим другом",
                            languageCode: languageCode
                        ))
                    }
                }
            }
            .navigationTitle(gymText(
                "Train with a friend",
                "Тренуватися з другом",
                "Тренироваться с другом",
                languageCode: languageCode
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(gymText("Close", "Закрити", "Закрыть", languageCode: languageCode)) {
                        showsFriendPicker = false
                    }
                }
            }
        }
    }

#if DEBUG
    /// UI-audit: scrolls to the history panel / opens Training settings once for
    /// `-uiAuditRoute today-history|training-settings`. Nothing is edited or saved.
    private func presentUIAuditRouteIfRequested(_ proxy: ScrollViewProxy) {
        guard let route = UIAuditRouter.shared.consume(anyOf: [.todayHistory, .trainingSettings]) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            switch route {
            case .todayHistory:
                if store.workoutSummaries.isEmpty {
                    UIAuditLaunch.log("today-history: no workouts, the history panel is not shown")
                } else {
                    proxy.scrollTo("workout-history", anchor: .top)
                }
            case .trainingSettings:
                showsTrainingSettings = true
            default:
                break
            }
        }
    }

    private var screenshotSectionAnchor: String? {
        let requested = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screenshot-section=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        switch requested {
        case "heatmap": return "activity-heatmap"
        case "muscles": return "muscle-map"
        default: return nil
        }
    }
#endif

    @ViewBuilder
    private var workoutListContent: some View {
        WorkoutMonthSwitcher(
            month: selectedMonth,
            isCurrentMonth: monthOffset == 0,
            onPrevious: { monthOffset = max(-1_200, monthOffset - 1) },
            onCurrent: { monthOffset = 0 },
            onNext: { monthOffset = min(0, monthOffset + 1) }
        )

        GymPanel(highlighted: true) {
            HStack(alignment: .center, spacing: 12) {
                Text(gymText(
                    "Saved workouts",
                    "Збережені тренування",
                    "Сохранённые тренировки",
                    languageCode: languageCode
                ))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                GymInfoPill(
                    gymCount(
                        monthWorkouts.count,
                        englishOne: "session",
                        englishMany: "sessions",
                        ukrainianOne: "тренування",
                        ukrainianFew: "тренування",
                        ukrainianMany: "тренувань"
                    ),
                    systemImage: "list.bullet"
                )
            }
        }
        .id("workout-history")

        if monthWorkouts.isEmpty {
            GymPanel {
                GymContentUnavailableView {
                    Label(
                        gymText(
                            "No workouts this month",
                            "Цього місяця тренувань немає",
                            "В этом месяце тренировок нет",
                            languageCode: languageCode
                        ),
                        systemImage: "calendar.badge.plus"
                    )
                } description: {
                    Text(gymText(
                        "Use Add workout when you are ready to log a session.",
                        "Щоб записати тренування, натисніть «Додати тренування».",
                        "Чтобы записать тренировку, нажмите «Добавить тренировку».",
                        languageCode: languageCode
                    ))
                } actions: {
                    Button(gymText(
                        "Add workout", "Додати тренування", "Добавить тренировку",
                        languageCode: languageCode
                    )) { _ = onAddWorkout(nil) }
                        .buttonStyle(GymPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ForEach(monthWorkouts) { workout in
                workoutCard(workout)
            }
        }
    }

    private func workoutCard(_ workout: WorkoutSessionSummary) -> some View {
        let activityOnly = isActivityOnly(workout)
        return GymPanel(highlighted: true) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    historyReturnWorkoutID = workout.workoutID
                    onOpenWorkout(workout.workoutID)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(gymShortDate(workout.date, calendar: calendar, languageCode: languageCode))
                                .font(.headline)
                                .foregroundStyle(GymTheme.textPrimary)
                            Spacer(minLength: 4)
                            GymInfoPill(
                                activityOnly
                                    ? compactHistoryDuration(workout.durationSeconds ?? 0)
                                    : gymCount(
                                        workout.setCount,
                                        englishOne: "set",
                                        englishMany: "sets",
                                        ukrainianOne: "підхід",
                                        ukrainianFew: "підходи",
                                        ukrainianMany: "підходів"
                                    )
                            )
                        }

                        Text(activityOnly ? gymText(
                            "Garmin free workout",
                            "Вільне тренування Garmin",
                            "Свободная тренировка Garmin",
                            languageCode: languageCode
                        ) : workoutNote(workout))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        if activityOnly {
                            Text(gymText(
                                "Time, heart rate, and calories — no exercises or sets",
                                "Час, пульс і калорії — без вправ і підходів",
                                "Время, пульс и калории — без упражнений и подходов",
                                languageCode: languageCode
                            ))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    workoutStat(
                                        label: "Exercises",
                                        value: workout.exerciseCount.formatted(.number.locale(gymAppLocale()))
                                    )
                                    workoutStat(label: "Sets", value: workout.setCount.formatted(.number.locale(gymAppLocale())))
                                    workoutStat(
                                        label: "Volume",
                                        value: gymVolumeText(workout.totalVolume, compact: true, languageCode: languageCode)
                                    )
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    workoutStat(
                                        label: "Exercises",
                                        value: workout.exerciseCount.formatted(.number.locale(gymAppLocale()))
                                    )
                                    workoutStat(label: "Sets", value: workout.setCount.formatted(.number.locale(gymAppLocale())))
                                    workoutStat(
                                        label: "Volume",
                                        value: gymVolumeText(workout.totalVolume, compact: true, languageCode: languageCode)
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    gymText(
                        "Workout on \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        "Тренування за \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        "Тренировка за \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        languageCode: languageCode
                    )
                )
                .accessibilityValue(
                    workoutAccessibilityValue(workout)
                )
                .accessibilityHint("Opens workout details")

            }
        }
        .id(workout.workoutID)
    }

    private func workoutStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(gymLocalized(label))
                .foregroundStyle(GymTheme.textSecondary)
            Text(value)
                .foregroundStyle(GymTheme.textPrimary)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var monthWorkouts: [WorkoutSessionSummary] {
        todayProjection.monthWorkouts
    }

    private var selectedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: referenceDate) ?? referenceDate
    }

    private func workoutNote(_ workout: WorkoutSessionSummary) -> String {
        guard let note = workout.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return gymLocalized("No note")
        }
        return note
    }

    private func formattedMetric(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func workoutAccessibilityValue(_ workout: WorkoutSessionSummary) -> String {
        if isActivityOnly(workout) {
            let duration = compactHistoryDuration(workout.durationSeconds ?? 0)
            return gymText(
                "Garmin free workout, \(duration), no exercises or sets",
                "Вільне тренування Garmin, \(duration), без вправ і підходів",
                "Свободная тренировка Garmin, \(duration), без упражнений и подходов",
                languageCode: languageCode
            )
        }
        let exercises = gymCount(
            workout.exerciseCount,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправа",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ"
        )
        let sets = gymCount(
            workout.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        return gymText(
            "\(exercises), \(sets), \(gymVolumeText(workout.totalVolume, compact: true, languageCode: languageCode)) volume",
            "\(exercises), \(sets), обсяг \(gymVolumeText(workout.totalVolume, compact: true, languageCode: languageCode))",
            "\(exercises), \(sets), объём \(gymVolumeText(workout.totalVolume, compact: true, languageCode: languageCode))",
            languageCode: languageCode
        )
    }

    private func isActivityOnly(_ workout: WorkoutSessionSummary) -> Bool {
        workout.exerciseCount == 0 && workout.setCount == 0 &&
            workout.durationSeconds.map { $0 > 0 } == true
    }

    private func compactHistoryDuration(_ seconds: Int) -> String {
        gymWorkoutDuration(seconds, languageCode: languageCode)
    }
}

private struct ActivationChipButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? GymTheme.onPrimary : GymTheme.onHero)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isSelected ? GymTheme.brandFill : GymTheme.heroTile,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(
                    isSelected ? GymTheme.brandFill : GymTheme.heroOutline,
                    lineWidth: 1
                )
            }
            .brightness(configuration.isPressed ? -0.04 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}

/// Status-bar scroll edge for tab roots whose large title is part of the scrolling content.
/// At rest nothing is drawn, so the title sits on the plain background. Once content moves
/// under the top safe area a bar material fades in over that area, so the title and rows blur
/// out behind the clock instead of being drawn over it. It is a system material (it turns
/// opaque under Reduce Transparency) and only its opacity animates. Blur only, no gradient.
private struct GymStatusBarScrollEdge: ViewModifier {
    @State private var contentIsUnderTopEdge = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, isUnderTopEdge in
                contentIsUnderTopEdge = isUnderTopEdge
            }
            .overlay(alignment: .top) {
                // A zero-height strip on the safe-area edge: its background grows up to the
                // screen edge, so it covers exactly the top safe area and nothing below it.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .background(.bar, ignoresSafeAreaEdges: .top)
                    .opacity(contentIsUnderTopEdge ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: contentIsUnderTopEdge)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Blurs scrolled content behind the status bar on a tab root whose title scrolls away.
    func gymStatusBarScrollEdge() -> some View {
        modifier(GymStatusBarScrollEdge())
    }
}
