import Combine
import CryptoKit
import Foundation
import HealthKit

// MARK: - Client seam

/// What the import needs from Apple Health. The live implementation wraps `HKHealthStore`;
/// tests substitute a double. Read-only: nothing is ever written to Health.
protocol HealthKitImportClient: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Workouts that start at or after `since`, newest first, at most `limit`.
    /// Heart-rate samples are not included; they are read per workout.
    func fetchWorkouts(since: Date, limit: Int) async throws -> [HealthImportSession]
    /// Average and maximum of the heart-rate samples Apple Health associated with this workout
    /// itself (whichever device measured them), or nil when the workout carries none.
    func heartRateStatistics(recordId: String) async throws -> HealthImportHeartRateStatistics?
    /// Heart-rate samples written by `sourceId` only; other sources never fill in.
    /// Fallback for workouts without their own heart-rate statistics.
    func heartRateSamples(
        startMillis: Int64,
        endMillis: Int64,
        sourceId: String
    ) async throws -> [HealthImportHeartRateSample]
}

/// Heart rate of one workout in beats per minute, as Apple Health computed it.
struct HealthImportHeartRateStatistics: Equatable, Sendable {
    let average: Double
    let maximum: Double
}

extension HealthKitImportClient {
    func heartRateStatistics(recordId: String) async throws -> HealthImportHeartRateStatistics? {
        nil
    }
}

struct LiveHealthKitImportClient: HealthKitImportClient, @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            heartRateType,
            energyType
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchWorkouts(since: Date, limit: Int) async throws -> [HealthImportSession] {
        let predicate = HKQuery.predicateForSamples(
            withStart: since,
            end: nil,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { workout in
            HealthImportSession(
                recordId: workout.uuid.uuidString,
                startMillis: Self.millis(workout.startDate),
                endMillis: Self.millis(workout.endDate),
                exerciseType: Self.contractName(workout.workoutActivityType),
                sourceId: workout.sourceRevision.source.bundleIdentifier,
                kilocalories: workout.sourceRevision.source.bundleIdentifier.isEmpty
                    ? nil : kilocalories(of: workout),
                heartRateSamples: []
            )
        }
    }

    /// A third-party Apple Watch app saves the workout, but the samples of its session belong
    /// to the watch, so a source filter finds none. The workout's own statistics cover them.
    func heartRateStatistics(recordId: String) async throws -> HealthImportHeartRateStatistics? {
        guard let uuid = UUID(uuidString: recordId) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 1
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let statistics = try await descriptor.result(for: store).first?
            .statistics(for: heartRateType),
              let average = statistics.averageQuantity()?.doubleValue(for: unit),
              let maximum = statistics.maximumQuantity()?.doubleValue(for: unit) else {
            return nil
        }
        return HealthImportHeartRateStatistics(average: average, maximum: maximum)
    }

    /// Upper bound of raw samples read for one workout before the source filter.
    static let maxHeartRateSamplesRead = 100_000
    /// Samples kept for one workout after the source filter.
    static let maxHeartRateSamplesPerWorkout = 20_000

    func heartRateSamples(
        startMillis: Int64,
        endMillis: Int64,
        sourceId: String
    ) async throws -> [HealthImportHeartRateSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: Date(timeIntervalSince1970: TimeInterval(startMillis) / 1_000),
            end: Date(timeIntervalSince1970: TimeInterval(endMillis) / 1_000),
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: Self.maxHeartRateSamplesRead
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        // The per-workout limit applies to this source's samples, not to everything in range.
        return try await descriptor.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier == sourceId }
            .prefix(Self.maxHeartRateSamplesPerWorkout)
            .map {
            HealthImportHeartRateSample(
                timeMillis: Self.millis($0.startDate),
                bpm: $0.quantity.doubleValue(for: unit)
            )
        }
    }

    private func kilocalories(of workout: HKWorkout) -> Double? {
        let unit = HKUnit.kilocalorie()
        if let sum = workout.statistics(for: energyType)?.sumQuantity() {
            return sum.doubleValue(for: unit)
        }
        return Self.legacyEnergy(of: workout)?.doubleValue(for: unit)
    }

    /// Workouts written by older apps carry a total energy value instead of statistics.
    @available(iOS, deprecated: 18.0, message: "Legacy fallback for workouts without statistics.")
    private static func legacyEnergy(of workout: HKWorkout) -> HKQuantity? {
        workout.totalEnergyBurned
    }

    private static func millis(_ date: Date) -> Int64 {
        let value = (date.timeIntervalSince1970 * 1_000).rounded()
        guard value.isFinite else { return 0 }
        return Int64(max(min(value, 9e15), -9e15))
    }

    static func contractName(_ type: HKWorkoutActivityType) -> String? {
        switch type {
        case .traditionalStrengthTraining: "traditionalStrengthTraining"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .coreTraining: "coreTraining"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        case .crossTraining: "crossTraining"
        case .gymnastics: "gymnastics"
        default: nil
        }
    }
}

// MARK: - Per-account state

/// Receipts and bookkeeping of the Apple Health import for one account. Receipts outlive
/// the imported workout so a workout the user deleted never returns.
struct HealthImportLedger: Codable, Equatable {
    static let currentVersion = 1
    static let maximumReceipts = 5_000

    /// Where an imported workout was stored. Kept next to its receipt so a later watch
    /// transfer of the same session can replace the imported copy.
    struct ImportedWorkout: Codable, Equatable {
        var startMillis: Int64
        var durationSeconds: Int
    }

    var version = HealthImportLedger.currentVersion
    var connected = false
    var receipts: [String] = []
    var lastImportAt: Double?
    var importedTotal = 0
    /// Receipt key -> stored workout. Optional: files written before this field existed
    /// decode without it (those older imports are simply not matched to watch workouts).
    var importedWorkouts: [String: ImportedWorkout]?

    mutating func add(receipt: String, workout: ImportedWorkout? = nil) {
        guard !receipts.contains(receipt) else { return }
        receipts.append(receipt)
        if let workout {
            if importedWorkouts == nil { importedWorkouts = [:] }
            importedWorkouts?[receipt] = workout
        }
        if receipts.count > Self.maximumReceipts {
            let dropped = receipts.prefix(receipts.count - Self.maximumReceipts)
            for key in dropped { importedWorkouts?[key] = nil }
            receipts.removeFirst(dropped.count)
        }
    }

    /// Start (epoch ms) -> duration (s) of every workout this import stored.
    var importedWorkoutDurationsByStart: [Int64: Int] {
        var result: [Int64: Int] = [:]
        for workout in (importedWorkouts ?? [:]).values {
            result[workout.startMillis] = workout.durationSeconds
        }
        return result
    }
}

/// One protected file per account: complete file protection, excluded from backups.
final class HealthImportStateStore {
    private let root: URL
    private let lock = NSLock()

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthImport", isDirectory: true)
    }

    func load(account: String) -> HealthImportLedger {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: file(account)),
              data.count <= 1_048_576,
              let ledger = try? JSONDecoder().decode(HealthImportLedger.self, from: data),
              ledger.version == HealthImportLedger.currentVersion else {
            return HealthImportLedger()
        }
        return ledger
    }

    @discardableResult
    func save(_ ledger: HealthImportLedger, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            let target = file(account)
            try JSONEncoder().encode(ledger).write(
                to: target,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try (target as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            return load(accountUnlocked: account) == ledger
        } catch {
            return false
        }
    }

    @discardableResult
    func clear(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let target = file(account)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            return true
        } catch {
            return false
        }
    }

    private func load(accountUnlocked account: String) -> HealthImportLedger? {
        guard let data = try? Data(contentsOf: file(account)) else { return nil }
        return try? JSONDecoder().decode(HealthImportLedger.self, from: data)
    }

    private func file(_ account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest + ".json")
    }
}

// MARK: - Service

struct HealthImportRunSummary: Equatable {
    var imported = 0
    var skipped: [HealthImportSkipReason: Int] = [:]
    var truncated = 0
    /// Records that could not be read or stored this run; they are retried next time.
    var failed = 0
    var finishedAt = Date()

    var skippedTotal: Int { skipped.values.reduce(0, +) }
}

enum HealthImportFailure: Equatable {
    case authorization
    case query
    case storage
}

private enum HealthImportError: Error {
    case accountChanged
}

@MainActor
final class HealthKitImportService: ObservableObject {
    @Published private(set) var isAvailable: Bool
    @Published private(set) var isConnected = false
    @Published private(set) var isImporting = false
    @Published private(set) var importedTotal = 0
    @Published private(set) var lastImportAt: Date?
    @Published private(set) var lastSummary: HealthImportRunSummary?
    @Published private(set) var failure: HealthImportFailure?
    /// HealthKit read permission can only be revoked in Settings. True after the user
    /// disconnected here, so the UI can point to Settings > Health > Data Access.
    @Published private(set) var revokeRequiresSettings = false

    private let auth: AuthService
    private let defaults: UserDefaults
    private let client: HealthKitImportClient
    private let stateStore: HealthImportStateStore
    private let now: () -> Date
    private weak var workoutStore: WorkoutStore?
    private var sessionSubscription: AnyCancellable?
    private var activeStorageKey: String?
    private var ledger = HealthImportLedger()
    /// Token of the run that owns `isImporting`. Only that run may clear the flag or write; a
    /// run left behind by an account change keeps its old token and can do neither.
    private var activeRun: UInt64?
    private var lastRunToken: UInt64 = 0

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        client: HealthKitImportClient = LiveHealthKitImportClient(),
        stateStore: HealthImportStateStore = HealthImportStateStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.defaults = defaults
        self.client = client
        self.stateStore = stateStore
        self.now = now
        self.isAvailable = client.isAvailable
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                Task { @MainActor in self?.activate(session) }
            }
        activate(auth.session)
    }

    func bind(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
        // A watch workout that covers an imported session replaces the imported copy; the
        // store asks which activity-only workouts this import created for its account.
        workoutStore.healthImportedActivityWorkouts = { [weak self, weak workoutStore] in
            guard let self, let workoutStore,
                  self.workoutStore === workoutStore,
                  self.activeStorageKey == workoutStore.accountStorageKey else { return [:] }
            return self.ledger.importedWorkoutDurationsByStart
        }
    }

    /// Asks Apple Health for read access, remembers the choice and imports right away.
    func connect() async {
        guard isAvailable, readyWorkoutStore() != nil, let account = activeStorageKey else {
            return
        }
        failure = nil
        do {
            try await client.requestAuthorization()
        } catch {
            guard activeStorageKey == account else { return }
            failure = .authorization
            return
        }
        guard activeStorageKey == account else { return }
        ledger.connected = true
        revokeRequiresSettings = false
        guard stateStore.save(ledger, account: account) else {
            ledger.connected = false
            failure = .storage
            return
        }
        isConnected = true
        await runImport(automatic: false)
    }

    @discardableResult
    func importNow() async -> Bool {
        await runImport(automatic: false)
    }

    /// Foreground trigger: runs at most once per `minAutoImportIntervalSeconds`.
    func autoImportIfDue() async {
        await runImport(automatic: true)
    }

    /// Stops importing. Receipts stay so a later reconnect never re-adds deleted workouts.
    /// Apple Health itself keeps the read permission until the user removes it in Settings.
    func disconnect() {
        guard let account = activeStorageKey, isConnected else { return }
        ledger.connected = false
        _ = stateStore.save(ledger, account: account)
        isConnected = false
        revokeRequiresSettings = true
        failure = nil
    }

    func clearLocalData(storageKey: String) {
        stateStore.clear(account: storageKey)
        if activeStorageKey == storageKey { activate(nil) }
    }

    // MARK: Run

    @discardableResult
    private func runImport(automatic: Bool) async -> Bool {
        guard isConnected, isAvailable, activeRun == nil,
              let store = readyWorkoutStore(),
              let account = activeStorageKey else {
            return false
        }
        let started = now()
        if automatic, let last = ledger.lastImportAt {
            // Throttled only while the last run is in the past and less than the interval ago.
            // A clock that was set back (negative elapsed time) never blocks the import.
            let elapsed = started.timeIntervalSince1970 - last
            if elapsed >= 0,
               elapsed < TimeInterval(HealthImportRules.minAutoImportIntervalSeconds) {
                return false
            }
        }
        lastRunToken &+= 1
        let run = lastRunToken
        activeRun = run
        isImporting = true
        failure = nil
        defer {
            if activeRun == run {
                activeRun = nil
                isImporting = false
            }
        }

        var working = ledger
        var summary = HealthImportRunSummary()
        do {
            let since = started.addingTimeInterval(
                -TimeInterval(HealthImportRules.windowDays) * 86_400
            )
            let fetched = try await fetch(since: since)
            try ensureBound(store: store, account: account, run: run)

            let selection = HealthImportRules.select(fetched)
            summary.skipped = selection.skipped
            summary.truncated = selection.truncated
            var existing = store.workouts.map {
                HealthImportExistingWorkout(
                    startMillis: $0.date.gymEpochMilliseconds,
                    durationSeconds: $0.durationSeconds
                )
            }
            var receipts = Set(working.receipts)
            let language = gymCurrentLanguageCode(defaults: defaults)
            let nowMillis = started.gymEpochMilliseconds
            var heartRateBudget = HealthImportRules.maxHeartRateSamplesPerRun

            for candidate in selection.candidates {
                // Disconnect while running stops the rest of the run.
                guard isConnected else { break }
                if let reason = HealthImportRules.skipReason(
                    for: candidate,
                    existingWorkouts: existing,
                    receipts: receipts,
                    nowMillis: nowMillis
                ) {
                    summary.skipped[reason, default: 0] += 1
                    continue
                }
                // Heart rate: first the statistics Apple Health keeps for the workout itself
                // (they cover a third-party watch app, whose samples belong to the watch),
                // otherwise samples of the session's own source. The per-run sample budget is
                // shared: a session that would cross it, and every later one, is imported
                // without heart rate (never a partial average).
                var samples: [HealthImportHeartRateSample] = []
                var workoutHeartRate: (average: Int, maximum: Int)?
                if !candidate.sourceId.isEmpty {
                    do {
                        workoutHeartRate = Self.heartRateSummary(
                            try await client.heartRateStatistics(recordId: candidate.recordId)
                        )
                        if workoutHeartRate == nil, heartRateBudget > 0 {
                            samples = try await client.heartRateSamples(
                                startMillis: candidate.startMillis,
                                endMillis: candidate.endMillis,
                                sourceId: candidate.sourceId
                            )
                        }
                    } catch {
                        // One unreadable record never stops the run; it is retried next time.
                        summary.failed += 1
                        continue
                    }
                    if samples.count > heartRateBudget {
                        samples = []
                        heartRateBudget = 0
                    } else {
                        heartRateBudget -= samples.count
                    }
                }
                // The account may have changed while Health was being read.
                try ensureBound(store: store, account: account, run: run)
                switch HealthImportRules.evaluate(
                    candidate.withHeartRateSamples(samples),
                    existingWorkouts: existing,
                    receipts: receipts,
                    languageCode: language,
                    nowMillis: nowMillis
                ) {
                case let .skipped(reason):
                    summary.skipped[reason, default: 0] += 1
                case let .imported(key, evaluated):
                    let workout = Self.applying(
                        workoutHeartRate,
                        to: evaluated,
                        type: candidate.exerciseType,
                        languageCode: language
                    )
                    do {
                        try store.createImportedActivityWorkout(
                            date: Date(gymEpochMilliseconds: workout.workoutStartedAt),
                            note: workout.note,
                            durationSeconds: workout.durationSeconds,
                            gymCalories: workout.gymCalories,
                            averageHeartRate: workout.averageHeartRate,
                            maximumHeartRate: workout.maximumHeartRate
                        )
                    } catch {
                        summary.failed += 1
                        continue
                    }
                    let stored = HealthImportLedger.ImportedWorkout(
                        startMillis: workout.workoutStartedAt,
                        durationSeconds: workout.durationSeconds
                    )
                    working.add(receipt: key, workout: stored)
                    // Known at once (not only when the run ends), so a watch workout that
                    // arrives during this run already finds the imported copy.
                    ledger.add(receipt: key, workout: stored)
                    working.importedTotal += 1
                    receipts.insert(key)
                    existing.append(HealthImportExistingWorkout(
                        startMillis: workout.workoutStartedAt,
                        durationSeconds: workout.durationSeconds
                    ))
                    summary.imported += 1
                    // Persist per workout: a later failure must not forget what was added.
                    working.connected = isConnected
                    _ = stateStore.save(working, account: account)
                }
            }
            try ensureBound(store: store, account: account, run: run)
            working.connected = isConnected
            working.lastImportAt = started.timeIntervalSince1970
            summary.finishedAt = now()
            guard stateStore.save(working, account: account) else {
                throw HealthImportFailureError.storage
            }
            apply(working, summary: summary)
            return true
        } catch HealthImportError.accountChanged {
            // The new account has its own state (see `activate`); persist nothing for it.
            return false
        } catch let error as HealthImportFailureError {
            if activeStorageKey == account {
                apply(working, summary: summary.imported > 0 ? summary : nil)
                failure = error.failure
            }
            return false
        } catch {
            if activeStorageKey == account {
                apply(working, summary: nil)
                failure = .query
            }
            return false
        }
    }


    /// Workout statistics are used only when both values are plausible; otherwise the
    /// source-filtered samples decide.
    static func heartRateSummary(
        _ statistics: HealthImportHeartRateStatistics?
    ) -> (average: Int, maximum: Int)? {
        guard let statistics,
              statistics.average.isFinite, statistics.maximum.isFinite,
              statistics.average >= HealthImportRules.minPlausibleBpm,
              statistics.maximum <= HealthImportRules.maxPlausibleBpm,
              statistics.maximum >= statistics.average else { return nil }
        return (
            average: Int((statistics.average + 0.5).rounded(.down)),
            maximum: Int(statistics.maximum.rounded())
        )
    }

    /// The evaluated workout with the workout's own heart rate, the note rebuilt to match.
    private static func applying(
        _ heartRate: (average: Int, maximum: Int)?,
        to workout: HealthImportWorkout,
        type: String?,
        languageCode: String
    ) -> HealthImportWorkout {
        guard let heartRate, let type else { return workout }
        return HealthImportWorkout(
            workoutStartedAt: workout.workoutStartedAt,
            durationSeconds: workout.durationSeconds,
            gymCalories: workout.gymCalories,
            averageHeartRate: heartRate.average,
            maximumHeartRate: heartRate.maximum,
            note: HealthImportRules.buildNote(
                type: type,
                durationSeconds: workout.durationSeconds,
                gymCalories: workout.gymCalories,
                averageHeartRate: heartRate.average,
                maximumHeartRate: heartRate.maximum,
                languageCode: languageCode
            )
        )
    }

    private func fetch(since: Date) async throws -> [HealthImportSession] {
        do {
            return try await client.fetchWorkouts(
                since: since,
                limit: HealthImportRules.maxRecordsScannedPerRun
            )
        } catch {
            throw HealthImportFailureError.query
        }
    }

    private func ensureBound(store: WorkoutStore, account: String, run: UInt64) throws {
        guard activeRun == run,
              readyWorkoutStore() === store,
              activeStorageKey == account,
              store.accountStorageKey == account else {
            throw HealthImportError.accountChanged
        }
    }

    private func apply(_ updated: HealthImportLedger, summary: HealthImportRunSummary?) {
        ledger = updated
        ledger.connected = isConnected
        importedTotal = updated.importedTotal
        lastImportAt = updated.lastImportAt.map { Date(timeIntervalSince1970: $0) }
        if let summary { lastSummary = summary }
    }

    private func activate(_ session: AppAccountSession?) {
        activeStorageKey = session?.storageKey
        isAvailable = client.isAvailable
        lastSummary = nil
        failure = nil
        revokeRequiresSettings = false
        // A run of the previous account is abandoned here: it loses the token, so it can no
        // longer write or clear the flag of a run started for the new account.
        activeRun = nil
        isImporting = false
        if let key = session?.storageKey {
            ledger = stateStore.load(account: key)
        } else {
            ledger = HealthImportLedger()
        }
        isConnected = ledger.connected
        importedTotal = ledger.importedTotal
        lastImportAt = ledger.lastImportAt.map { Date(timeIntervalSince1970: $0) }
    }

    private func readyWorkoutStore() -> WorkoutStore? {
        guard let session = auth.session,
              let activeStorageKey,
              activeStorageKey == session.storageKey,
              let workoutStore,
              workoutStore.accountStorageKey == session.storageKey else {
            return nil
        }
        return workoutStore
    }
}

private enum HealthImportFailureError: Error {
    case query
    case storage

    var failure: HealthImportFailure {
        switch self {
        case .query: .query
        case .storage: .storage
        }
    }
}

#if DEBUG
extension HealthKitImportService {
    /// QA audit seed (`-qaWatches`): forces the card state for screenshots. DEBUG only.
    func applyQAPreset(_ preset: String) {
        isAvailable = true
        isImporting = false
        failure = nil
        lastSummary = nil
        revokeRequiresSettings = false
        switch preset {
        case "a":
            isConnected = true; importedTotal = 21; lastImportAt = Date().addingTimeInterval(-300)
        case "b":
            isConnected = true; importedTotal = 1; lastImportAt = Date().addingTimeInterval(-26 * 3_600)
            lastSummary = HealthImportRunSummary()
        case "c":
            isConnected = true; importedTotal = 3; lastImportAt = Date().addingTimeInterval(-3_600)
            isImporting = true
        case "d":
            isConnected = true; importedTotal = 3; lastImportAt = Date().addingTimeInterval(-120)
            failure = .query
        case "e":
            isAvailable = false; isConnected = false
        case "f":
            isConnected = false; revokeRequiresSettings = true
        default:
            break
        }
    }
}
#endif
