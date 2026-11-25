import Combine
import CryptoKit
import Foundation
import WatchConnectivity

// MARK: - Transport seam

/// What the service needs from WCSession; tests supply a fake.
@MainActor
protocol WatchSessionTransport: AnyObject {
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isActivated: Bool { get }
    func activate(handler: WatchSessionTransportHandler)
    func updateApplicationContext(_ context: [String: Any]) throws
    func transferUserInfo(_ userInfo: [String: Any])
}

@MainActor
protocol WatchSessionTransportHandler: AnyObject {
    func watchTransportStateDidChange()
    /// Bytes of a valid single-key envelope (already size-checked off the main thread).
    func watchTransportDidReceive(envelopeBytes: Data)
}

/// WCSession-backed transport. Delegate callbacks arrive off the main thread:
/// the envelope bytes are copied out there and handed to the main actor.
final class LiveWatchSessionTransport: NSObject, WatchSessionTransport, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession
    @MainActor private weak var handler: WatchSessionTransportHandler?

    @MainActor static func makeIfSupported() -> LiveWatchSessionTransport? {
        WCSession.isSupported() ? LiveWatchSessionTransport(session: .default) : nil
    }

    private init(session: WCSession) {
        self.session = session
        super.init()
    }

    @MainActor var isPaired: Bool { session.activationState == .activated && session.isPaired }
    @MainActor var isWatchAppInstalled: Bool { session.activationState == .activated && session.isWatchAppInstalled }
    @MainActor var isActivated: Bool { session.activationState == .activated }

    @MainActor func activate(handler: WatchSessionTransportHandler) {
        self.handler = handler
        session.delegate = self
        session.activate()
    }

    @MainActor func updateApplicationContext(_ context: [String: Any]) throws {
        try session.updateApplicationContext(context)
    }

    @MainActor func transferUserInfo(_ userInfo: [String: Any]) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        notifyStateChange()
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: re-activate so the session follows it.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStateChange()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let bytes = WatchSyncCodec.envelopeBytes(from: userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.handler?.watchTransportDidReceive(envelopeBytes: bytes)
        }
    }

    private nonisolated func notifyStateChange() {
        Task { @MainActor [weak self] in
            self?.handler?.watchTransportStateDidChange()
        }
    }
}

// MARK: - Account binding

enum WatchAccountBinding {
    static func localKey(storageKey: String) -> String {
        "watch-phone-local-account.v1.\(Data(storageKey.utf8).watchSHA256Hex)"
    }

    /// Domain-separated account hash: cannot be linked to the Garmin binding.
    static func make(session: AppAccountSession, defaults: UserDefaults) -> String? {
        if let cloud = session.cloud {
            guard UUID(uuidString: cloud.userID)?.uuidString.lowercased() == cloud.userID.lowercased() else {
                return nil
            }
            return Data("gymapp-watch-account/v1\u{0}\(cloud.userID.lowercased())".utf8).watchSHA256Hex
        }
        let key = localKey(storageKey: session.storageKey)
        if let existing = defaults.string(forKey: key), WatchSync.isValidHash(existing) {
            return existing
        }
        let generated = Data(
            "gymapp-watch-local-account/v1\u{0}\(UUID().uuidString.lowercased())".utf8
        ).watchSHA256Hex
        defaults.set(generated, forKey: key)
        guard defaults.string(forKey: key) == generated else { return nil }
        return generated
    }
}

/// Bindings of deleted accounts whose `account-deleted` notice has not reached WatchConnectivity
/// yet. Written before the account's watch data is cleared, so an interrupted deletion (finished
/// by startup recovery) or a watch that is not reachable still gets the notice later.
enum WatchDeletedAccountNotices {
    static let defaultsKey = "watch-phone-deleted-accounts.v1"
    static let maximumEntries = 16

    /// The binding an account had, without creating one: cloud is derived from the storage key,
    /// local is read from its stored key (nil when the account never had a watch binding).
    static func binding(storageKey: String, defaults: UserDefaults) -> String? {
        if storageKey.hasPrefix("cloud_") {
            let userID = String(storageKey.dropFirst("cloud_".count))
            guard UUID(uuidString: userID)?.uuidString.lowercased() == userID.lowercased() else { return nil }
            return Data("gymapp-watch-account/v1\u{0}\(userID.lowercased())".utf8).watchSHA256Hex
        }
        guard let stored = defaults.string(forKey: WatchAccountBinding.localKey(storageKey: storageKey)),
              WatchSync.isValidHash(stored) else { return nil }
        return stored
    }

    static func pending(defaults: UserDefaults) -> [String] {
        (defaults.stringArray(forKey: defaultsKey) ?? []).filter(WatchSync.isValidHash)
    }

    static func remember(storageKey: String, defaults: UserDefaults) {
        guard let binding = binding(storageKey: storageKey, defaults: defaults) else { return }
        var list = pending(defaults: defaults).filter { $0 != binding }
        list.append(binding)
        defaults.set(Array(list.suffix(maximumEntries)), forKey: defaultsKey)
    }

    static func remove(_ bindings: Set<String>, defaults: UserDefaults) {
        let list = pending(defaults: defaults).filter { !bindings.contains($0) }
        if list.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(list, forKey: defaultsKey)
        }
    }
}

// MARK: - Protected per-account files

struct WatchStoredPlan: Codable, Equatable {
    var version = 1
    var planRevision: Int64
    var plan: [WatchPlanExercise]
    var updatedAt: TimeInterval
}

struct WatchReceiptRecord: Codable, Equatable {
    enum State: String, Codable { case pending, committed }
    let requestID: String
    let digest: String
    let createdAt: TimeInterval
    var state: State
}

struct WatchReceiptLedger: Codable, Equatable {
    var version = 1
    var records: [WatchReceiptRecord] = []
}

enum WatchSyncFileError: Error {
    case corrupt
    case tooLarge
}

/// `ApplicationSupport/WatchSync/<sha256hex(storageKey)>/{plan,receipts}.json`, atomic,
/// protected until first unlock and excluded from backup (root, directory, file).
final class WatchSyncFileStore {
    static let maximumPlanBytes = 65_536
    static let maximumLedgerBytes = 262_144

    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchSync", isDirectory: true)
    }

    func directory(storageKey: String) -> URL {
        root.appendingPathComponent(Data(storageKey.utf8).watchSHA256Hex, isDirectory: true)
    }

    func loadPlan(storageKey: String) throws -> WatchStoredPlan? {
        guard let data = try read("plan.json", storageKey: storageKey, maximumBytes: Self.maximumPlanBytes) else {
            return nil
        }
        let value = try JSONDecoder().decode(WatchStoredPlan.self, from: data)
        // The stored plan must still pass the contract bounds, or it could never be published.
        guard value.version == 1,
              WatchSync.planRevisionRange.contains(value.planRevision),
              (try? WatchSyncCodec.encode(WatchContextMessage(
                  sentAtMillis: 0,
                  bound: .init(
                      accountBinding: String(repeating: "0", count: 64),
                      language: "en",
                      planRevision: value.planRevision,
                      plan: value.plan,
                      exercises: []
                  )
              ))) != nil else {
            throw WatchSyncFileError.corrupt
        }
        return value
    }

    func savePlan(_ plan: WatchStoredPlan, storageKey: String) throws {
        try write(JSONEncoder().encode(plan), name: "plan.json", storageKey: storageKey, maximumBytes: Self.maximumPlanBytes)
    }

    /// Missing file = empty ledger. A corrupt or unreadable file throws (fail closed).
    func loadLedger(storageKey: String) throws -> WatchReceiptLedger {
        guard let data = try read("receipts.json", storageKey: storageKey, maximumBytes: Self.maximumLedgerBytes) else {
            return WatchReceiptLedger()
        }
        let ledger = try JSONDecoder().decode(WatchReceiptLedger.self, from: data)
        guard ledger.version == 1,
              ledger.records.count <= WatchSync.maximumReceiptRecords,
              Set(ledger.records.map(\.requestID)).count == ledger.records.count,
              ledger.records.allSatisfy({
                  WatchSync.isValidRequestID($0.requestID) && WatchSync.isValidHash($0.digest) && $0.createdAt.isFinite
              }) else {
            throw WatchSyncFileError.corrupt
        }
        return ledger
    }

    func saveLedger(_ ledger: WatchReceiptLedger, storageKey: String) throws {
        try write(JSONEncoder().encode(ledger), name: "receipts.json", storageKey: storageKey, maximumBytes: Self.maximumLedgerBytes)
    }

    func clear(storageKey: String) throws {
        let directory = directory(storageKey: storageKey)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func read(_ name: String, storageKey: String, maximumBytes: Int) throws -> Data? {
        let file = directory(storageKey: storageKey).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximumBytes else { throw WatchSyncFileError.tooLarge }
        let data = try Data(contentsOf: file)
        guard data.count <= maximumBytes else { throw WatchSyncFileError.tooLarge }
        return data
    }

    private func write(_ data: Data, name: String, storageKey: String, maximumBytes: Int) throws {
        guard data.count <= maximumBytes else { throw WatchSyncFileError.tooLarge }
        let directory = directory(storageKey: storageKey)
        let file = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try (file as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        guard try Data(contentsOf: file) == data else { throw CocoaError(.fileWriteUnknown) }
    }
}

// MARK: - Service

enum WatchInboundOutcome: Equatable {
    case dropped
    case ack(WatchAckStatus)
    case nack(WatchNackReason)
}

enum WatchPlanError: Error {
    case notReady
    case invalidPlan
    case storage
}

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject, WatchSessionTransportHandler {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false

    private let auth: AuthService
    private let defaults: UserDefaults
    private let transport: WatchSessionTransport?
    private let files: WatchSyncFileStore
    private let now: () -> Date
    private let restSecondsOverride: ((String) -> Int?)?
    private weak var workoutStore: WorkoutStore?
    private var activeStorageKey: String?
    private var sessionSubscription: AnyCancellable?
    private var catalogSubscription: AnyCancellable?
    private var lastContextKey: Data?

    /// Test seam: runs after the pending receipt is durable and before the store write.
    var beforeStoreWriteForTesting: (() -> Void)?
    /// Test seam: runs after the store write and before the receipt is committed.
    var afterStoreWriteForTesting: (() -> Void)?

    init(
        auth: AuthService,
        defaults: UserDefaults,
        transport: WatchSessionTransport? = nil,
        useLiveTransport: Bool = true,
        fileRoot: URL? = nil,
        now: @escaping () -> Date = Date.init,
        restSeconds: ((String) -> Int?)? = nil
    ) {
        self.auth = auth
        self.defaults = defaults
        self.transport = transport ?? (useLiveTransport ? LiveWatchSessionTransport.makeIfSupported() : nil)
        self.files = WatchSyncFileStore(root: fileRoot)
        self.now = now
        self.restSecondsOverride = restSeconds
        super.init()
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                Task { @MainActor in self?.activate(session) }
            }
        activate(auth.session)
        self.transport?.activate(handler: self)
    }

    func bind(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
        catalogSubscription = workoutStore.$exercises
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishContext() }
            }
        publishContext()
    }

    // MARK: Plan

    /// Saves the plan for the active account (Unicode names kept verbatim) and publishes it.
    func publishPlan(_ plan: GarminWorkoutPlan) throws {
        guard let storageKey = activeStorageKey, let store = readyWorkoutStore() else { throw WatchPlanError.notReady }
        var exercises: [WatchPlanExercise] = []
        var totalSets = 0
        for exercise in plan.exercises {
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sets = exercise.sets
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { WatchPlanSet(weight: $0.weight, reps: $0.reps) }
            guard !sets.isEmpty else { continue }
            guard WatchSync.isValidExerciseName(name),
                  sets.count <= WatchSync.maximumSetsPerExercise,
                  sets.allSatisfy({ WatchSync.isValidWeight($0.weight) && WatchSync.repsRange.contains($0.reps) }) else {
                throw WatchPlanError.invalidPlan
            }
            totalSets += sets.count
            let rest = planRestSeconds(for: name, storageKey: storageKey, store: store)
            exercises.append(.init(name: name, restSeconds: rest, sets: sets))
        }
        guard exercises.count <= WatchSync.maximumPlanExercises,
              totalSets <= WatchSync.maximumPlanSets,
              GarminPhoneSyncProtocol.validatedPlan(Self.flattened(exercises)) != nil else {
            throw WatchPlanError.invalidPlan
        }
        try savePlan(exercises, storageKey: storageKey)
        publishStatus(
            gymText(
                "Plan saved. It appears when GymApp opens on Apple Watch.",
                "План збережено. Він з'явиться, коли GymApp відкриється на Apple Watch.",
                "План сохранён. Он появится, когда GymApp откроется на Apple Watch.",
                languageCode: gymCurrentLanguageCode(defaults: defaults)
            ),
            isError: false
        )
    }

    /// The exercise's own rest when the user set one (`ExerciseRestTimeStore`, the setting the
    /// active workout uses), else the contract default.
    private func planRestSeconds(for name: String, storageKey: String, store: WorkoutStore) -> Int {
        let custom: Int?
        if let restSecondsOverride {
            custom = restSecondsOverride(name)
        } else {
            let folded = name.lowercased()
            let catalogKey = store.exercises.first {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == folded
            }?.catalogKey
            custom = ExerciseRestTimeStore(defaults: defaults).restSeconds(
                accountStorageKey: storageKey,
                identityKey: FriendGhosts.exerciseKey(catalogKey: catalogKey, name: name)
            )
        }
        return custom.flatMap { WatchSync.restSecondsRange.contains($0) ? $0 : nil }
            ?? WatchSync.defaultRestSeconds
    }

    func clearPlan() throws {
        guard let storageKey = activeStorageKey, readyWorkoutStore() != nil else { throw WatchPlanError.notReady }
        try savePlan([], storageKey: storageKey)
    }

    private func savePlan(_ exercises: [WatchPlanExercise], storageKey: String) throws {
        // A context without a stored plan already carries revision 1, so the first saved plan is 2:
        // the watch replaces its cached plan only for a greater revision. After an unreadable file
        // the counter restarts from the clock, above anything sent before.
        let base: Int64
        do { base = try files.loadPlan(storageKey: storageKey)?.planRevision ?? 1 } catch { base = max(1, nowMillis()) }
        let revision = base + 1
        guard WatchSync.planRevisionRange.contains(revision) else { throw WatchPlanError.storage }
        do {
            try files.savePlan(
                .init(planRevision: revision, plan: exercises, updatedAt: now().timeIntervalSince1970),
                storageKey: storageKey
            )
        } catch {
            throw WatchPlanError.storage
        }
        publishContext()
    }

    // MARK: Account lifecycle

    /// Account deletion only (not sign-out): the binding is recorded before it is cleared, the
    /// plain unbound context goes out as before, and the queued `account-deleted` notice tells
    /// the watch to drop that owner's unsent work.
    func clearLocalData(storageKey: String) {
        WatchDeletedAccountNotices.remember(storageKey: storageKey, defaults: defaults)
        try? files.clear(storageKey: storageKey)
        defaults.removeObject(forKey: WatchAccountBinding.localKey(storageKey: storageKey))
        if activeStorageKey == storageKey || auth.session == nil {
            lastContextKey = nil
            sendContext(.init(sentAtMillis: nowMillis(), bound: nil))
        }
        sendDeletionNotices()
    }

    /// Startup recovery of an interrupted deletion: records the notice (sent once the watch
    /// session is up) before the binding key is removed.
    static func clearStoredData(defaults: UserDefaults, storageKey: String, fileRoot: URL? = nil) {
        WatchDeletedAccountNotices.remember(storageKey: storageKey, defaults: defaults)
        try? WatchSyncFileStore(root: fileRoot).clear(storageKey: storageKey)
        defaults.removeObject(forKey: WatchAccountBinding.localKey(storageKey: storageKey))
    }

    /// Hands pending `account-deleted` notices to WatchConnectivity's queue (delivered even when
    /// the watch is away). Kept until a paired watch with the app installed can take them.
    func sendDeletionNotices() {
        let pending = WatchDeletedAccountNotices.pending(defaults: defaults)
        guard !pending.isEmpty, let transport, transport.isActivated,
              transport.isPaired, transport.isWatchAppInstalled else { return }
        var sent = Set<String>()
        for binding in pending {
            guard let bytes = try? WatchSyncCodec.encode(
                WatchAccountDeletedMessage(accountBinding: binding, sentAtMillis: nowMillis())
            ) else { continue }
            transport.transferUserInfo(WatchSyncCodec.envelope(bytes))
            sent.insert(binding)
        }
        WatchDeletedAccountNotices.remove(sent, defaults: defaults)
    }

    private func activate(_ session: AppAccountSession?) {
        guard activeStorageKey != session?.storageKey || lastContextKey == nil else { return }
        activeStorageKey = session?.storageKey
        lastContextKey = nil
        publishContext()
    }

    // MARK: Context

    /// Builds the bound context for the ready account, or `unbound`.
    func currentContext() -> WatchContextMessage {
        guard let session = auth.session,
              let storageKey = activeStorageKey,
              let store = readyWorkoutStore(),
              let binding = WatchAccountBinding.make(session: session, defaults: defaults) else {
            return .init(sentAtMillis: nowMillis(), bound: nil)
        }
        let stored: WatchStoredPlan?
        do { stored = try files.loadPlan(storageKey: storageKey) } catch { stored = nil }
        let plan = stored?.plan ?? []
        let flat = Self.flattened(plan)
        let candidates = GarminPhoneSyncProtocol.exerciseCatalog(plan: flat, candidates: store.exercises.map(\.name))
            ?? plan.map(\.name)
        var catalog: [String] = []
        var seen = Set<String>()
        var bytes = 0
        for name in candidates where catalog.count < WatchSync.maximumCatalogNames {
            guard WatchSync.isValidExerciseName(name),
                  bytes + name.utf8.count <= WatchSync.maximumTotalExerciseBytes,
                  seen.insert(name).inserted else { continue }
            bytes += name.utf8.count
            catalog.append(name)
        }
        return .init(
            sentAtMillis: nowMillis(),
            bound: .init(
                accountBinding: binding,
                language: Self.normalizedLanguage(gymCurrentLanguageCode(defaults: defaults)),
                planRevision: stored?.planRevision ?? 1,
                plan: plan,
                exercises: catalog
            )
        )
    }

    func publishContext() {
        sendContext(currentContext())
    }

    private func sendContext(_ context: WatchContextMessage) {
        guard let transport, transport.isActivated else { return }
        refreshWatchState()
        // Inert without a paired watch that has the app: WCSession would only fail the update.
        // The next watch-state change publishes again.
        guard transport.isPaired, transport.isWatchAppInstalled else { return }
        // Unchanged content (ignoring the send time) is not re-sent.
        guard let key = try? WatchSyncCodec.encode(WatchContextMessage(sentAtMillis: 0, bound: context.bound)),
              key != lastContextKey,
              let bytes = try? WatchSyncCodec.encode(context) else { return }
        do {
            try transport.updateApplicationContext(WatchSyncCodec.envelope(bytes))
            lastContextKey = key
        } catch {
            // Throws while the watch app is not installed; the plan file is kept.
        }
    }

    private func refreshWatchState() {
        guard let transport else { return }
        if isPaired != transport.isPaired { isPaired = transport.isPaired }
        if isWatchAppInstalled != transport.isWatchAppInstalled {
            // A newly installed (or reinstalled) watch app has no context yet: send it again.
            if transport.isWatchAppInstalled { lastContextKey = nil }
            isWatchAppInstalled = transport.isWatchAppInstalled
        }
    }

    // MARK: WatchSessionTransportHandler

    func watchTransportStateDidChange() {
        refreshWatchState()
        publishContext()
        sendDeletionNotices()
    }

    func watchTransportDidReceive(envelopeBytes: Data) {
        guard WatchSyncCodec.messageType(of: envelopeBytes) == "workout" else { return }
        receiveWorkout(envelopeBytes)
    }

    // MARK: Inbound workout

    /// Decides, writes and replies for one inbound workout envelope (contract `phoneRules`).
    @discardableResult
    func receiveWorkout(_ bytes: Data) -> WatchInboundOutcome {
        let message: WatchWorkoutMessage
        switch WatchSyncCodec.decodeWorkout(bytes, nowMillis: nowMillis()) {
        case .drop:
            return .dropped
        case .unsupportedVersion(let requestId):
            return nack(requestId, .unsupportedVersion)
        case .malformed(let requestId):
            publishStatus(gymText("A malformed Apple Watch workout was rejected.", "Некоректне тренування з Apple Watch відхилено.", "Некорректная тренировка с Apple Watch отклонена.", languageCode: gymCurrentLanguageCode(defaults: defaults)), isError: true)
            return nack(requestId, .malformed)
        case .valid(let value):
            message = value
        }
        guard let session = auth.session,
              let storageKey = activeStorageKey,
              let store = readyWorkoutStore(),
              let binding = WatchAccountBinding.make(session: session, defaults: defaults) else {
            return nack(message.requestId, .notReady)
        }
        guard message.accountBinding == binding else {
            return nack(message.requestId, .foreignAccount)
        }
        let digest = Data(SHA256.hash(data: bytes)).map { String(format: "%02x", $0) }.joined()
        var ledger: WatchReceiptLedger
        do { ledger = try files.loadLedger(storageKey: storageKey) } catch {
            publishStatus(gymText("The Apple Watch import receipt could not be read.", "Не вдалося прочитати квитанцію імпорту з Apple Watch.", "Не удалось прочитать квитанцию импорта с Apple Watch.", languageCode: gymCurrentLanguageCode(defaults: defaults)), isError: true)
            return nack(message.requestId, .storage)
        }

        if let index = ledger.records.firstIndex(where: { $0.requestID == message.requestId }) {
            let existing = ledger.records[index]
            guard existing.digest == digest else {
                return nack(message.requestId, .conflict)
            }
            if existing.state == .committed {
                return ack(message, binding: binding, status: .duplicate)
            }
            if Self.matchesPersisted(message, in: store) {
                ledger.records[index].state = .committed
                do { try files.saveLedger(ledger, storageKey: storageKey) } catch {
                    return nack(message.requestId, .storage)
                }
                return ack(message, binding: binding, status: .committed)
            }
            ledger.records.remove(at: index)
            do { try files.saveLedger(ledger, storageKey: storageKey) } catch {
                return nack(message.requestId, .storage)
            }
        }

        let oneHourAgo = now().timeIntervalSince1970 - 3_600
        guard ledger.records.lazy.filter({ $0.createdAt >= oneHourAgo }).count < WatchSync.maximumReceiptsPerHour else {
            return nack(message.requestId, .rateLimited)
        }

        ledger.records.append(.init(
            requestID: message.requestId,
            digest: digest,
            createdAt: now().timeIntervalSince1970,
            state: .pending
        ))
        if ledger.records.count > WatchSync.maximumReceiptRecords {
            ledger.records.removeFirst(ledger.records.count - WatchSync.maximumReceiptRecords)
        }
        do { try files.saveLedger(ledger, storageKey: storageKey) } catch {
            publishStatus(gymText("The Apple Watch import receipt could not be stored.", "Не вдалося зберегти квитанцію імпорту з Apple Watch.", "Не удалось сохранить квитанцию импорта с Apple Watch.", languageCode: gymCurrentLanguageCode(defaults: defaults)), isError: true)
            return nack(message.requestId, .storage)
        }

        beforeStoreWriteForTesting?()
        guard readyWorkoutStore() === store, activeStorageKey == storageKey else {
            rollBackPending(message.requestId, storageKey: storageKey)
            return nack(message.requestId, .notReady)
        }

        // A late arrival that a stored workout already holds (activity-only over a workout with
        // sets, or the very same sets) is not stored again. The receipt is committed and the watch
        // gets the same positive ack as a store, so its queue clears and a replay is a duplicate.
        if Self.lateArrivalDecision(message, in: store) == .skip {
            if let index = ledger.records.firstIndex(where: { $0.requestID == message.requestId }) {
                ledger.records[index].state = .committed
            }
            do { try files.saveLedger(ledger, storageKey: storageKey) } catch {
                return nack(message.requestId, .storage)
            }
            publishStatus(
                gymText(
                    "This Apple Watch workout is already saved on the phone, so it was not added again.",
                    "Це тренування Apple Watch уже збережене на телефоні, тому повторно не додане.",
                    "Эта тренировка Apple Watch уже сохранена на телефоне, поэтому повторно не добавлена.",
                    languageCode: gymCurrentLanguageCode(defaults: defaults)
                ),
                isError: false
            )
            return ack(message, binding: binding, status: .committed)
        }

        let created: WorkoutSession?
        do {
            let date = Date(timeIntervalSince1970: TimeInterval(message.startedAtMillis / 1_000))
            let note = workoutNote(message)
            if message.sets.isEmpty {
                // Time-only workout: kcal and heart rate are stored as explicit fields (like the
                // Apple Health import), so the cloud sidecar item carries them. Deriving the
                // item from the note would lose them: that parser reads Garmin notes only.
                let metrics = Self.activityMetrics(message)
                created = try store.createImportedActivityWorkout(
                    date: date,
                    note: note,
                    durationSeconds: Int(message.durationSeconds),
                    gymCalories: metrics.gymCalories,
                    averageHeartRate: metrics.averageHeartRate,
                    maximumHeartRate: metrics.maximumHeartRate,
                    replacingHealthImport: true
                )
            } else {
                created = try store.createWorkout(
                    date: date,
                    note: note,
                    namedSets: message.sets.map {
                        NamedWorkoutSetDraft(exerciseName: $0.exerciseName, weight: $0.weight, reps: $0.reps)
                    },
                    durationSeconds: Int(message.durationSeconds)
                )
            }
        } catch {
            rollBackPending(message.requestId, storageKey: storageKey)
            publishStatus(gymText("The Apple Watch workout could not be saved.", "Не вдалося зберегти тренування з Apple Watch.", "Не удалось сохранить тренировку с Apple Watch.", languageCode: gymCurrentLanguageCode(defaults: defaults)), isError: true)
            return nack(message.requestId, Self.isPersistenceError(error) ? .storage : .invalid)
        }
        guard created != nil else {
            rollBackPending(message.requestId, storageKey: storageKey)
            return nack(message.requestId, .invalid)
        }
        afterStoreWriteForTesting?()
        // The account changed after the write. The workout is in `store`, which was verified to be
        // the message's own account right before the synchronous write, so nothing reached another
        // account. No ack is sent, and the pending receipt stays in that account's ledger: rolling
        // it back would import the workout twice on the retry. The retry is held (foreign-account)
        // while another account is active and commits without a second write once this one is back.
        guard readyWorkoutStore() === store, activeStorageKey == storageKey else {
            return nack(message.requestId, .notReady)
        }
        if let index = ledger.records.firstIndex(where: { $0.requestID == message.requestId }) {
            ledger.records[index].state = .committed
        }
        do { try files.saveLedger(ledger, storageKey: storageKey) } catch {
            publishStatus(
                gymText("The workout was saved, but the Apple Watch acknowledgement is waiting for receipt recovery.", "Тренування збережено, але підтвердження для Apple Watch чекає на відновлення квитанції.", "Тренировка сохранена, но подтверждение для Apple Watch ждёт восстановления квитанции.", languageCode: gymCurrentLanguageCode(defaults: defaults)),
                isError: true
            )
            return nack(message.requestId, .storage)
        }
        publishStatus(
            gymText(
                "Workout received from Apple Watch.",
                "Тренування отримано з Apple Watch.",
                "Тренировка получена с Apple Watch.",
                languageCode: gymCurrentLanguageCode(defaults: defaults)
            ),
            isError: false
        )
        return ack(message, binding: binding, status: .committed)
    }

    private func rollBackPending(_ requestId: String, storageKey: String) {
        guard var ledger = try? files.loadLedger(storageKey: storageKey) else { return }
        ledger.records.removeAll { $0.requestID == requestId && $0.state == .pending }
        try? files.saveLedger(ledger, storageKey: storageKey)
    }

    private func ack(_ message: WatchWorkoutMessage, binding: String, status: WatchAckStatus) -> WatchInboundOutcome {
        if let bytes = try? WatchSyncCodec.encode(
            WatchAckMessage(requestId: message.requestId, accountBinding: binding, status: status)
        ) {
            transport?.transferUserInfo(WatchSyncCodec.envelope(bytes))
        }
        return .ack(status)
    }

    private func nack(_ requestId: String, _ reason: WatchNackReason) -> WatchInboundOutcome {
        if let bytes = try? WatchSyncCodec.encode(WatchNackMessage(requestId: requestId, reason: reason)) {
            transport?.transferUserInfo(WatchSyncCodec.envelope(bytes))
        }
        return .nack(reason)
    }

    private static func isPersistenceError(_ error: Error) -> Bool {
        if let storeError = error as? WorkoutStoreError {
            switch storeError {
            case .persistenceFailure, .storageAccountMismatch: return true
            default: return false
            }
        }
        let domain = (error as NSError).domain
        return domain == NSCocoaErrorDomain || domain == NSPOSIXErrorDomain
    }

    /// Metrics of a time-only watch workout, bounded to what the activity-only sidecar accepts.
    /// A value outside its range is left out; an impossible pair (maximum below average) drops
    /// both heart-rate values. The workout itself is stored either way.
    static func activityMetrics(
        _ message: WatchWorkoutMessage
    ) -> (gymCalories: Int, averageHeartRate: Int?, maximumHeartRate: Int?) {
        func heartRate<Value: BinaryInteger>(_ value: Value?) -> Int? {
            guard let value, value > 0,
                  value <= Value(ActivityOnlyWorkoutCloudCodec.maximumHeartRate) else { return nil }
            return Int(value)
        }
        var average = heartRate(message.averageHeartRate)
        var maximum = heartRate(message.maximumHeartRate)
        if let low = average, let high = maximum, high < low {
            average = nil
            maximum = nil
        }
        var calories = 0
        if let value = message.activeKilocalories.map({ Double($0) }), value.isFinite, value >= 1,
           value <= Double(ActivityOnlyWorkoutCloudCodec.maximumCalories) {
            calories = Int(value.rounded())
        }
        return (calories, average, maximum)
    }

    /// "Apple Watch · Avg HR 118 · Max HR 161 · kcal 312" (segments only when > 0).
    private func workoutNote(_ message: WatchWorkoutMessage) -> String {
        let language = gymCurrentLanguageCode(defaults: defaults)
        var segments = ["Apple Watch"]
        if let value = message.averageHeartRate, value > 0 {
            segments.append(gymText("Avg HR \(value)", "Сер пульс \(value)", "Средний пульс \(value)", languageCode: language))
        }
        if let value = message.maximumHeartRate, value > 0 {
            segments.append(gymText("Max HR \(value)", "Макс пульс \(value)", "Макс. пульс \(value)", languageCode: language))
        }
        if let value = message.activeKilocalories, value >= 1 {
            let kcal = Int(value.rounded())
            segments.append(gymText("kcal \(kcal)", "ккал \(kcal)", "ккал \(kcal)", languageCode: language))
        }
        return String(segments.joined(separator: " · ").prefix(4_000))
    }

    /// Recovery check for a pending receipt: same start second and the same canonical sets
    /// (or an activity-only workout with the same duration).
    static func matchesPersisted(_ message: WatchWorkoutMessage, in store: WorkoutStore) -> Bool {
        let expectedSeconds = TimeInterval(message.startedAtMillis / 1_000)
        let names = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0.name) })
        let expectedSets = canonical(message.sets.map { ($0.exerciseName, $0.weight, $0.reps) })
        return store.workouts.contains { workout in
            guard abs(workout.date.timeIntervalSince1970 - expectedSeconds) < 1 else { return false }
            if message.sets.isEmpty {
                return workout.exercises.isEmpty && workout.durationSeconds == Int(message.durationSeconds)
            }
            let flat = workout.exercises.flatMap { block in
                block.sets.map { (names[block.exerciseID] ?? "", $0.weight, $0.reps) }
            }
            return canonical(flat) == expectedSets
        }
    }

    /// `LateWatchArrivalRule` over the store's workouts, using the same start second as the write.
    static func lateArrivalDecision(_ message: WatchWorkoutMessage, in store: WorkoutStore) -> LateWatchArrivalDecision {
        // Both values are already inside the contract ranges (start ≤ now + 1 day, duration ≤ 7 days).
        let startMillis = (message.startedAtMillis / 1_000) * 1_000
        return LateWatchArrivalRule.decide(
            startMillis: startMillis,
            endMillis: startMillis + Int64(message.durationSeconds) * 1_000,
            sets: message.sets.map { LateWatchArrivalSet(exerciseName: $0.exerciseName, weight: $0.weight, reps: $0.reps) },
            stored: LateWatchArrivalRule.storedWorkouts(
                store.workouts,
                exerciseNames: Dictionary(store.exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            )
        )
    }

    private struct CanonicalSet: Equatable {
        let key: String
        let weight: Double
        let reps: Int
    }

    private static func canonical(_ sets: [(String, Double, Int)]) -> [CanonicalSet] {
        var order: [String] = []
        var grouped: [String: [CanonicalSet]] = [:]
        for (name, weight, reps) in sets {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(.init(key: key, weight: weight, reps: reps))
        }
        return order.flatMap { grouped[$0] ?? [] }
    }

    // MARK: Helpers

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

    private func nowMillis() -> Int64 {
        Int64((now().timeIntervalSince1970 * 1_000).rounded())
    }

    private static func flattened(_ plan: [WatchPlanExercise]) -> [NamedWorkoutSetDraft] {
        plan.flatMap { exercise in
            exercise.sets.map { NamedWorkoutSetDraft(exerciseName: exercise.name, weight: $0.weight, reps: $0.reps) }
        }
    }

    private static func normalizedLanguage(_ rawValue: String?) -> String {
        switch rawValue {
        case AppLanguage.ukrainian.rawValue: return "uk"
        case AppLanguage.russian.rawValue: return "ru"
        default: return "en"
        }
    }


    private func publishStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

private extension Data {
    var watchSHA256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

#if DEBUG
extension WatchConnectivityService {
    /// QA audit seed (`-qaWatches`): shows the "Send to Apple Watch" panel for screenshots. DEBUG only.
    func applyQAPreset(_ preset: String) {
        let shown = preset == "a" || preset == "b" || preset == "d"
        // "g": Apple Watch paired, GymApp not installed on it.
        isPaired = shown || preset == "g"
        isWatchAppInstalled = shown
    }
}
#endif
