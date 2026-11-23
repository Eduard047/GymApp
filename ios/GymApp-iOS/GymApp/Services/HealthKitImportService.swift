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
    /// Heart-rate samples written by `sourceId` only; other sources never fill in.
    func heartRateSamples(
        startMillis: Int64,
        endMillis: Int64,
        sourceId: String
    ) async throws -> [HealthImportHeartRateSample]
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
            limit: 20_000
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier == sourceId }
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

    var version = HealthImportLedger.currentVersion
    var connected = false
    var receipts: [String] = []
    var lastImportAt: Double?
    var importedTotal = 0

    mutating func add(receipt: String) {
        guard !receipts.contains(receipt) else { return }
        receipts.append(receipt)
        if receipts.count > Self.maximumReceipts {
            receipts.removeFirst(receipts.count - Self.maximumReceipts)
        }
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
        guard isConnected, isAvailable, !isImporting,
              let store = readyWorkoutStore(),
              let account = activeStorageKey else {
            return false
        }
        let started = now()
        if automatic,
           let last = ledger.lastImportAt,
           started.timeIntervalSince1970 - last <
            TimeInterval(HealthImportRules.minAutoImportIntervalSeconds) {
            return false
        }
        isImporting = true
        failure = nil
        defer { isImporting = false }

        var working = ledger
        var summary = HealthImportRunSummary()
        do {
            let since = started.addingTimeInterval(
                -TimeInterval(HealthImportRules.windowDays) * 86_400
            )
            let fetched = try await fetch(since: since)
            try ensureBound(store: store, account: account)

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
                // Heart rate comes only from the session's own source. The per-run sample
                // budget is shared: a session that would cross it, and every later one, is
                // imported without heart rate (never a partial average).
                var samples: [HealthImportHeartRateSample] = []
                if heartRateBudget > 0, !candidate.sourceId.isEmpty {
                    do {
                        samples = try await client.heartRateSamples(
                            startMillis: candidate.startMillis,
                            endMillis: candidate.endMillis,
                            sourceId: candidate.sourceId
                        )
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
                try ensureBound(store: store, account: account)
                switch HealthImportRules.evaluate(
                    candidate.withHeartRateSamples(samples),
                    existingWorkouts: existing,
                    receipts: receipts,
                    languageCode: language,
                    nowMillis: nowMillis
                ) {
                case let .skipped(reason):
                    summary.skipped[reason, default: 0] += 1
                case let .imported(key, workout):
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
                    working.add(receipt: key)
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
            try ensureBound(store: store, account: account)
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

    private func ensureBound(store: WorkoutStore, account: String) throws {
        guard readyWorkoutStore() === store,
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
