import Foundation
import HealthKit

/// HKWorkoutSession + HKLiveWorkoutBuilder for traditional strength training:
/// live heart rate, average/max and active energy; pause/resume; crash recovery.
@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {
    struct Statistics: Equatable {
        var averageHeartRate: Double?
        var maximumHeartRate: Double?
        var activeKilocalories: Double?
    }

    @Published private(set) var heartRate: Double?
    @Published private(set) var statistics = Statistics()
    @Published private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Workouts can be saved (the share permission is the only one HealthKit reports).
    var canSaveWorkouts: Bool {
        isAvailable && healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Asks once per type; HealthKit shows the sheet only the first time.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            return false
        }
        return canSaveWorkouts
    }

    func start(requestId: String, startDate: Date) async -> Bool {
        guard isAvailable, session == nil else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            attach(session, configuration: configuration)
            session.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)
            try await builder?.addMetadata([HKMetadataKeyExternalUUID: requestId])
            isRunning = true
            return true
        } catch {
            session?.end()
            builder?.discardWorkout()
            teardown()
            return false
        }
    }

    /// Reattaches to a session the system kept alive across an app relaunch.
    func recover() async -> Bool {
        if session != nil { return true }
        guard isAvailable else { return false }
        let store = healthStore
        let recovered: HKWorkoutSession? = await withCheckedContinuation { continuation in
            store.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        // A session started while the recovery was pending stays the attached one.
        if session != nil { return true }
        guard let recovered else { return false }
        attach(recovered, configuration: recovered.workoutConfiguration)
        isRunning = true
        return true
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the session and collection and returns the final statistics. The Health save is separate.
    func end(at date: Date) async -> Statistics {
        guard let session, let builder else { return Statistics() }
        session.end()
        try? await builder.endCollection(at: date)
        read(builder)
        return statistics
    }

    /// Saves the workout to Apple Health.
    func finishWorkout() async -> Bool {
        guard let builder else { return false }
        defer { teardown() }
        do {
            return try await builder.finishWorkout() != nil
        } catch {
            return false
        }
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        teardown()
    }

    private func attach(_ session: HKWorkoutSession, configuration: HKWorkoutConfiguration) {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        read(builder)
    }

    private func teardown() {
        session = nil
        builder = nil
        isRunning = false
        heartRate = nil
    }

    fileprivate func read(_ builder: HKLiveWorkoutBuilder) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = builder.statistics(for: HKQuantityType(.heartRate))
        heartRate = heart?.mostRecentQuantity()?.doubleValue(for: bpm)
        statistics = Statistics(
            averageHeartRate: heart?.averageQuantity()?.doubleValue(for: bpm),
            maximumHeartRate: heart?.maximumQuantity()?.doubleValue(for: bpm),
            activeKilocalories: builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
        )
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.read(workoutBuilder)
        }
    }
}
