import Combine
import ConnectIQ
import CoreFoundation
import CryptoKit
import Foundation

struct GarminPhoneDeviceSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String
    let connected: Bool
}

struct GarminPhoneBinding: Equatable {
    let account: String
    let device: String
    let pairingGeneration: String
}

struct GarminPhoneSetStatistics: Codable, Equatable {
    let activeSeconds: Int64?
    let restBeforeSeconds: Int64?
    let startHeartRate: Int?
    let peakHeartRate: Int?
    let endHeartRate: Int?
    let recoveryHeartRateDrop: Int?
    let detectionConfidence: Int?
}

struct GarminPhoneWorkoutCommand: Codable, Equatable {
    let requestID: String
    let startedAtSeconds: Int64
    let sets: [NamedWorkoutSetDraft]
    let durationSeconds: Int64?
    let gymCalories: Double?
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
    let setStatistics: [GarminPhoneSetStatistics?]

    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return data.garminSHA256Hex
    }
}

enum GarminPhoneWorkoutParser {
    static let bindingVersion = 2
    static let maximumMessageEntries = 32
    static let maximumSets = 60
    static let maximumSetEntries = 8
    static let maximumExerciseCharacters = 160
    static let maximumExerciseBytes = 640
    static let maximumTotalExerciseBytes = 12_000
    static let maximumRequestIDBytes = 128
    static let maximumDurationSeconds: Int64 = 7 * 24 * 60 * 60
    static let minimumStartedAtSeconds: Int64 = 946_684_800
    static let maximumFutureSkewSeconds: Int64 = 24 * 60 * 60

    static func parse(
        _ rawMessage: Any,
        expectedBinding: GarminPhoneBinding,
        now: Date = Date()
    ) -> GarminPhoneWorkoutCommand? {
        guard let message = dictionary(rawMessage),
              message.count <= maximumMessageEntries,
              string(message["type"], maximumBytes: 20) == "create_workout",
              integer(message["bindingVersion"], minimum: 2, maximum: 2) == bindingVersion,
              string(message["accountBinding"], maximumBytes: 64) == expectedBinding.account,
              string(message["deviceBinding"], maximumBytes: 128) == expectedBinding.device,
              string(message["pairingGeneration"], maximumBytes: 64) ==
                expectedBinding.pairingGeneration,
              let requestID = string(
                message["requestId"],
                maximumBytes: maximumRequestIDBytes
              ),
              requestID.utf8.count >= 16,
              requestID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
              }),
              let rawSets = array(message["sets"]),
              (1 ... maximumSets).contains(rawSets.count) else {
            return nil
        }

        var totalExerciseBytes = 0
        var sets: [NamedWorkoutSetDraft] = []
        sets.reserveCapacity(rawSets.count)
        for rawSet in rawSets {
            guard let set = dictionary(rawSet),
                  set.count <= maximumSetEntries,
                  let rawName = string(
                    set["exerciseName"],
                    maximumBytes: maximumExerciseBytes
                  ),
                  rawName.utf16.count <= maximumExerciseCharacters else {
                return nil
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !name.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }),
                  let weight = finiteDouble(set["weight"], minimum: 0, maximum: 1_000_000),
                  let reps = integer(set["reps"], minimum: 1, maximum: 10_000) else {
                return nil
            }
            totalExerciseBytes += name.utf8.count
            guard totalExerciseBytes <= maximumTotalExerciseBytes else { return nil }
            sets.append(
                NamedWorkoutSetDraft(
                    exerciseName: name,
                    weight: weight,
                    reps: reps
                )
            )
        }

        let setStatistics: [GarminPhoneSetStatistics?]
        if message["setMetrics"] == nil || message["setMetrics"] is NSNull {
            setStatistics = Array(repeating: nil, count: sets.count)
        } else {
            guard let metrics = array(message["setMetrics"]),
                  metrics.count == sets.count else {
                return nil
            }
            var parsed: [GarminPhoneSetStatistics?] = []
            parsed.reserveCapacity(metrics.count)
            for value in metrics {
                guard let items = array(value), items.count == 7 else { return nil }
                let statistics = GarminPhoneSetStatistics(
                    activeSeconds: optionalInteger(items[0], minimum: 0, maximum: 7_200),
                    restBeforeSeconds: optionalInteger(items[1], minimum: 0, maximum: 86_400),
                    startHeartRate: optionalInteger(items[2], minimum: 0, maximum: 240),
                    peakHeartRate: optionalInteger(items[3], minimum: 0, maximum: 240),
                    endHeartRate: optionalInteger(items[4], minimum: 0, maximum: 240),
                    recoveryHeartRateDrop: optionalInteger(items[5], minimum: 0, maximum: 240),
                    detectionConfidence: optionalInteger(items[6], minimum: 0, maximum: 100)
                )
                guard optionalNumberWasValid(items[0], parsed: statistics.activeSeconds),
                      optionalNumberWasValid(items[1], parsed: statistics.restBeforeSeconds),
                      optionalNumberWasValid(items[2], parsed: statistics.startHeartRate),
                      optionalNumberWasValid(items[3], parsed: statistics.peakHeartRate),
                      optionalNumberWasValid(items[4], parsed: statistics.endHeartRate),
                      optionalNumberWasValid(items[5], parsed: statistics.recoveryHeartRateDrop),
                      optionalNumberWasValid(items[6], parsed: statistics.detectionConfidence),
                      statistics.startHeartRate == nil ||
                        statistics.peakHeartRate == nil ||
                        statistics.startHeartRate! <= statistics.peakHeartRate!,
                      statistics.endHeartRate == nil ||
                        statistics.peakHeartRate == nil ||
                        statistics.endHeartRate! <= statistics.peakHeartRate! else {
                    return nil
                }
                parsed.append(statistics == GarminPhoneSetStatistics(
                    activeSeconds: nil,
                    restBeforeSeconds: nil,
                    startHeartRate: nil,
                    peakHeartRate: nil,
                    endHeartRate: nil,
                    recoveryHeartRateDrop: nil,
                    detectionConfidence: nil
                ) ? nil : statistics)
            }
            setStatistics = parsed
        }

        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let startedAtSeconds = optionalInteger(
            message["startedAtSeconds"],
            minimum: minimumStartedAtSeconds,
            maximum: nowSeconds + maximumFutureSkewSeconds
        ) ?? nowSeconds
        guard optionalNumberWasValid(
            message["startedAtSeconds"],
            parsed: optionalInteger(
                message["startedAtSeconds"],
                minimum: minimumStartedAtSeconds,
                maximum: nowSeconds + maximumFutureSkewSeconds
            )
        ) else {
            return nil
        }
        let averageHeartRate = optionalInteger(
            message["avgHeartRate"],
            minimum: 0,
            maximum: 300
        )
        let maximumHeartRate = optionalInteger(
            message["maxHeartRate"],
            minimum: 0,
            maximum: 300
        )
        guard optionalNumberWasValid(message["avgHeartRate"], parsed: averageHeartRate),
              optionalNumberWasValid(message["maxHeartRate"], parsed: maximumHeartRate),
              averageHeartRate == nil ||
                maximumHeartRate == nil ||
                averageHeartRate! <= maximumHeartRate! else {
            return nil
        }

        let duration = optionalInteger(
            message["durationSeconds"],
            minimum: 0,
            maximum: maximumDurationSeconds
        )
        let gymCalories = optionalFiniteDouble(
            message["gymCalories"],
            minimum: 0,
            maximum: 100_000
        )
        let garminCalories = optionalInteger(
            message["garminCalories"],
            minimum: 0,
            maximum: 100_000
        )
        let heartRateZone = optionalInteger(
            message["heartRateZone"],
            minimum: 0,
            maximum: 5
        )
        guard optionalNumberWasValid(message["durationSeconds"], parsed: duration),
              optionalNumberWasValid(message["gymCalories"], parsed: gymCalories),
              optionalNumberWasValid(message["garminCalories"], parsed: garminCalories),
              optionalNumberWasValid(message["heartRateZone"], parsed: heartRateZone) else {
            return nil
        }

        return GarminPhoneWorkoutCommand(
            requestID: requestID,
            startedAtSeconds: startedAtSeconds,
            sets: sets,
            durationSeconds: duration,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            endingHeartRateZone: heartRateZone,
            setStatistics: setStatistics
        )
    }

    static func messageType(_ rawMessage: Any) -> String? {
        guard let message = dictionary(rawMessage) else { return nil }
        return string(message["type"], maximumBytes: 20)
    }

    private static func dictionary(_ value: Any) -> [AnyHashable: Any]? {
        if let value = value as? [AnyHashable: Any] { return value }
        guard let value = value as? NSDictionary else { return nil }
        var result: [AnyHashable: Any] = [:]
        guard value.count <= maximumMessageEntries else { return nil }
        for (key, item) in value {
            guard let key = key as? AnyHashable else { return nil }
            result[key] = item
        }
        return result
    }

    private static func array(_ value: Any?) -> [Any]? {
        if let value = value as? [Any] { return value }
        return (value as? NSArray)?.map { $0 }
    }

    private static func string(_ value: Any?, maximumBytes: Int) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.prefix(maximumBytes + 1).count <= maximumBytes else {
            return nil
        }
        return value
    }

    private static func finiteDouble(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let result = number.doubleValue
        guard result.isFinite, (minimum ... maximum).contains(result) else { return nil }
        return result
    }

    private static func optionalFiniteDouble(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard value != nil, !(value is NSNull) else { return nil }
        return finiteDouble(value, minimum: minimum, maximum: maximum)
    }

    private static func integer<T: FixedWidthInteger>(
        _ value: Any?,
        minimum: T,
        maximum: T
    ) -> T? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let raw = number.doubleValue
        guard raw.isFinite,
              raw.rounded(.towardZero) == raw,
              raw >= Double(minimum),
              raw <= Double(maximum) else {
            return nil
        }
        return T(raw)
    }

    private static func optionalInteger<T: FixedWidthInteger>(
        _ value: Any?,
        minimum: T,
        maximum: T
    ) -> T? {
        guard value != nil, !(value is NSNull) else { return nil }
        return integer(value, minimum: minimum, maximum: maximum)
    }

    private static func optionalNumberWasValid<T>(_ raw: Any?, parsed: T?) -> Bool {
        raw == nil || raw is NSNull || parsed != nil
    }
}

private struct GarminPhoneReceiptLedger: Codable {
    static let currentVersion = 1
    static let maximumRecords = 256

    struct Record: Codable {
        enum State: String, Codable {
            case pending
            case committed
        }

        let requestID: String
        let digest: String
        let createdAt: TimeInterval
        var state: State
    }

    let version: Int
    var records: [Record]
}

@MainActor
final class GarminPhoneSyncService: NSObject, ObservableObject {
    private static let returnURLScheme = "com.setforge.gymapp.ios"
    private static let restorationIdentifier = "com.setforge.gymapp.ios.connectiq"
    private static let appUUID = UUID(uuidString: "A72A5B9F-4E3D-4E5A-8B72-C1D9F6123E40")!
    private static let storeUUID = UUID(uuidString: "fe82a300-4d9f-4588-8b10-365d75280b8f")!
    private static let maximumArchivedDevicesBytes = 128 * 1_024
    private static let maximumDevices = 8
    private static let maximumInboundBatch = 8
    private static let maximumReceiptsPerHour = 60

    @Published private(set) var devices: [GarminPhoneDeviceSummary] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false

    private let auth: AuthService
    private let defaults: UserDefaults
    private let connectIQ: ConnectIQ
    private weak var workoutStore: WorkoutStore?
    private var sessionSubscription: AnyCancellable?
    private var activeStorageKey: String?
    private var rawDevices: [UUID: IQDevice] = [:]
    private var apps: [UUID: IQApp] = [:]

    init(auth: AuthService, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.defaults = defaults
        self.connectIQ = ConnectIQ.sharedInstance()
        super.init()
        connectIQ.initialize(
            withUrlScheme: Self.returnURLScheme,
            uiOverrideDelegate: nil,
            stateRestorationIdentifier: Self.restorationIdentifier
        )
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                Task { @MainActor in self?.activate(session) }
            }
        activate(auth.session)
    }

    deinit {
        connectIQ.unregister(forAllDeviceEvents: self)
        connectIQ.unregister(forAllAppMessages: self)
    }

    func bind(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
    }

    func selectDevices() {
        guard auth.session != nil else {
            publishStatus("Sign in before connecting a Garmin watch.", isError: true)
            return
        }
        connectIQ.showDeviceSelection()
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.returnURLScheme else { return false }
        guard let selected = connectIQ.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        else {
            return false
        }
        guard selected.count <= Self.maximumDevices else {
            publishStatus("Garmin returned too many watches. Select at most eight.", isError: true)
            return true
        }
        rawDevices = Dictionary(
            uniqueKeysWithValues: selected.map { ($0.uuid as UUID, $0) }
        )
        guard persistDevices() else {
            rawDevices.removeAll()
            registerDevices()
            publishStatus("The selected Garmin watches could not be stored safely.", isError: true)
            return true
        }
        registerDevices()
        publishStatus(
            selected.isEmpty
                ? "No Garmin watches are connected to this iPhone."
                : "Garmin watches connected. Open GymApp on the watch to synchronize.",
            isError: false
        )
        return true
    }

    private func activate(_ session: AppAccountSession?) {
        connectIQ.unregister(forAllDeviceEvents: self)
        connectIQ.unregister(forAllAppMessages: self)
        apps.removeAll()
        rawDevices.removeAll()
        devices.removeAll()
        activeStorageKey = session?.storageKey
        guard session != nil else { return }
        restoreDevices()
        registerDevices()
    }

    private func registerDevices() {
        connectIQ.unregister(forAllDeviceEvents: self)
        connectIQ.unregister(forAllAppMessages: self)
        apps.removeAll()
        for device in rawDevices.values {
            connectIQ.register(forDeviceEvents: device, delegate: self)
            let app = IQApp(
                uuid: Self.appUUID,
                store: Self.storeUUID,
                device: device
            )
            apps[device.uuid as UUID] = app
            connectIQ.register(forAppMessages: app, delegate: self)
        }
        refreshDeviceSummaries()
    }

    private func refreshDeviceSummaries() {
        devices = rawDevices.values
            .map { device in
                let connected = connectIQ.getDeviceStatus(device) == .connected
                return GarminPhoneDeviceSummary(
                    id: (device.uuid as UUID).uuidString.lowercased(),
                    name: device.friendlyName,
                    model: device.modelName,
                    connected: connected
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistDevices() -> Bool {
        guard let storageKey = activeStorageKey,
              rawDevices.count <= Self.maximumDevices else {
            return false
        }
        do {
            let archive = try NSKeyedArchiver.archivedData(
                withRootObject: rawDevices,
                requiringSecureCoding: true
            )
            guard archive.count <= Self.maximumArchivedDevicesBytes else { return false }
            let key = deviceArchiveKey(storageKey: storageKey)
            defaults.set(archive, forKey: key)
            guard defaults.data(forKey: key) == archive else { return false }
            rememberStateKey(key, storageKey: storageKey)
            return true
        } catch {
            return false
        }
    }

    private func restoreDevices() {
        guard let storageKey = activeStorageKey,
              let archive = defaults.data(forKey: deviceArchiveKey(storageKey: storageKey)),
              archive.count <= Self.maximumArchivedDevicesBytes else {
            return
        }
        do {
            let classes: [AnyClass] = [
                NSDictionary.self,
                NSMutableDictionary.self,
                IQDevice.self,
                NSUUID.self,
                NSString.self
            ]
            guard let restored = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: classes,
                from: archive
            ) as? [UUID: IQDevice],
            restored.count <= Self.maximumDevices else {
                defaults.removeObject(forKey: deviceArchiveKey(storageKey: storageKey))
                return
            }
            rawDevices = restored
        } catch {
            defaults.removeObject(forKey: deviceArchiveKey(storageKey: storageKey))
        }
    }

    private func process(_ rawMessage: Any, app: IQApp) {
        let messages: [Any]
        if let batch = rawMessage as? [Any],
           batch.count <= Self.maximumInboundBatch,
           batch.allSatisfy({ $0 is NSDictionary || $0 is [AnyHashable: Any] }) {
            messages = batch
        } else {
            messages = [rawMessage]
        }
        for message in messages {
            switch GarminPhoneWorkoutParser.messageType(message) {
            case "request_sync":
                sendSync(to: app)
            case "create_workout":
                receiveWorkout(message, from: app)
            default:
                continue
            }
        }
    }

    private func sendSync(to app: IQApp) {
        guard let binding = binding(for: app.device),
              let store = readyWorkoutStore() else {
            return
        }
        let syncID = UUID().uuidString.lowercased()
        let revision = nextSyncRevision(binding: binding)
        let language = normalizedLanguage(defaults.string(forKey: "app-language"))
        let names = Array(
            store.exercises
                .map(\.name)
                .filter { !$0.isEmpty && $0.utf8.count <= 640 }
                .prefix(60)
        )
        let payload: [String: Any] = [
            "type": "sync",
            "bindingVersion": GarminPhoneWorkoutParser.bindingVersion,
            "syncId": syncID,
            "requestId": syncID,
            "bindingSource": "phone",
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "syncRevision": revision,
            "resetWorkout": false,
            "language": language,
            "planNames": [],
            "planWeights": [],
            "planReps": [],
            "exercises": names
        ]
        send(payload, to: app)
    }

    private func receiveWorkout(_ rawMessage: Any, from app: IQApp) {
        guard let binding = binding(for: app.device),
              let store = readyWorkoutStore(),
              let command = GarminPhoneWorkoutParser.parse(
                  rawMessage,
                  expectedBinding: binding
              ) else {
            publishStatus("A malformed or unbound Garmin workout was rejected.", isError: true)
            return
        }
        let receiptKey = receiptLedgerKey(binding: binding)
        if let activeStorageKey {
            rememberStateKey(receiptKey, storageKey: activeStorageKey)
        }
        var ledger = loadReceiptLedger(key: receiptKey)
        if let existing = ledger.records.first(where: { $0.requestID == command.requestID }) {
            guard existing.digest == command.digest else {
                publishStatus("A conflicting Garmin workout replay was rejected.", isError: true)
                return
            }
            if existing.state == .pending {
                guard matchingWorkout(command, in: store) else {
                    ledger.records.removeAll { $0.requestID == command.requestID }
                    guard saveReceiptLedger(ledger, key: receiptKey) else { return }
                    receiveWorkout(rawMessage, from: app)
                    return
                }
                updateReceipt(
                    requestID: command.requestID,
                    state: .committed,
                    ledger: &ledger
                )
                guard saveReceiptLedger(ledger, key: receiptKey) else { return }
            }
            sendAcknowledgement(for: command.requestID, binding: binding, to: app)
            return
        }

        let oneHourAgo = Date().timeIntervalSince1970 - 3_600
        guard ledger.records.lazy.filter({ $0.createdAt >= oneHourAgo }).count <
                Self.maximumReceiptsPerHour else {
            publishStatus("Garmin workout import is temporarily rate limited.", isError: true)
            return
        }
        ledger.records.append(
            .init(
                requestID: command.requestID,
                digest: command.digest,
                createdAt: Date().timeIntervalSince1970,
                state: .pending
            )
        )
        trimLedger(&ledger)
        guard saveReceiptLedger(ledger, key: receiptKey) else {
            publishStatus("The Garmin import receipt could not be stored.", isError: true)
            return
        }

        do {
            let created = try store.createWorkout(
                date: Date(timeIntervalSince1970: TimeInterval(command.startedAtSeconds)),
                note: workoutNote(command),
                namedSets: command.sets
            )
            guard created != nil,
                  readyWorkoutStore() === store else {
                throw GarminPhoneSyncError.accountChanged
            }
            updateReceipt(
                requestID: command.requestID,
                state: .committed,
                ledger: &ledger
            )
            guard saveReceiptLedger(ledger, key: receiptKey) else {
                publishStatus(
                    "The workout was saved, but Garmin acknowledgement is waiting for receipt recovery.",
                    isError: true
                )
                return
            }
            sendAcknowledgement(for: command.requestID, binding: binding, to: app)
            publishStatus("Workout received from Garmin.", isError: false)
        } catch {
            ledger.records.removeAll { $0.requestID == command.requestID }
            _ = saveReceiptLedger(ledger, key: receiptKey)
            publishStatus("The Garmin workout could not be saved.", isError: true)
        }
    }

    private func sendAcknowledgement(
        for requestID: String,
        binding: GarminPhoneBinding,
        to app: IQApp
    ) {
        send(
            [
                "type": "ack",
                "requestId": requestID,
                "bindingVersion": GarminPhoneWorkoutParser.bindingVersion,
                "accountBinding": binding.account,
                "deviceBinding": binding.device,
                "pairingGeneration": binding.pairingGeneration
            ],
            to: app
        )
    }

    private func send(_ message: [String: Any], to app: IQApp) {
        connectIQ.sendMessage(
            message,
            to: app,
            progress: { _, _ in },
            completion: { [weak self] result in
                guard result != .success else { return }
                Task { @MainActor in
                    self?.publishStatus(
                        "Garmin message delivery failed. Keep both apps open and retry.",
                        isError: true
                    )
                }
            },
            isTransient: false
        )
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

    private func binding(for device: IQDevice) -> GarminPhoneBinding? {
        guard let session = auth.session,
              activeStorageKey == session.storageKey else {
            return nil
        }
        let deviceBinding = (device.uuid as UUID).uuidString.lowercased()
        guard rawDevices[device.uuid as UUID] != nil else { return nil }
        let accountBinding: String
        if let cloud = session.cloud {
            guard UUID(uuidString: cloud.userID)?.uuidString.lowercased() ==
                    cloud.userID.lowercased() else {
                return nil
            }
            accountBinding = Data(cloud.userID.lowercased().utf8).garminSHA256Hex
        } else {
            let key = localAccountBindingKey(storageKey: session.storageKey)
            if let existing = defaults.string(forKey: key),
               existing.isGarminBinding {
                accountBinding = existing
            } else {
                let generated = Data(
                    "gymapp-local-account-binding/v1\u{0}\(UUID().uuidString.lowercased())".utf8
                ).garminSHA256Hex
            defaults.set(generated, forKey: key)
            guard defaults.string(forKey: key) == generated else { return nil }
            rememberStateKey(key, storageKey: session.storageKey)
                accountBinding = generated
            }
            rememberStateKey(key, storageKey: session.storageKey)
        }
        let generationKey = pairingGenerationKey(
            accountBinding: accountBinding,
            deviceBinding: deviceBinding
        )
        let generation: String
        if let existing = defaults.string(forKey: generationKey),
           existing.isGarminBinding {
            generation = existing
        } else {
            let generated = Data(
                "gymapp-garmin-pairing-generation/v1\u{0}\(UUID().uuidString.lowercased())".utf8
            ).garminSHA256Hex
            defaults.set(generated, forKey: generationKey)
            guard defaults.string(forKey: generationKey) == generated else { return nil }
            rememberStateKey(generationKey, storageKey: session.storageKey)
            generation = generated
        }
        rememberStateKey(generationKey, storageKey: session.storageKey)
        return GarminPhoneBinding(
            account: accountBinding,
            device: deviceBinding,
            pairingGeneration: generation
        )
    }

    private func nextSyncRevision(binding: GarminPhoneBinding) -> Int64 {
        let scope = "\(binding.account)\u{0}\(binding.device)\u{0}\(binding.pairingGeneration)"
        let key = "garmin-phone-sync-revision.v1.\(Data(scope.utf8).garminSHA256Hex)"
        let current = defaults.object(forKey: key) as? NSNumber
        let value = max(0, current?.int64Value ?? 0)
        let next = value >= 9_007_199_254_740_990 ? 1 : value + 1
        defaults.set(next, forKey: key)
        if let activeStorageKey {
            rememberStateKey(key, storageKey: activeStorageKey)
        }
        return next
    }

    private func workoutNote(_ command: GarminPhoneWorkoutCommand) -> String {
        let language = normalizedLanguage(defaults.string(forKey: "app-language"))
        var details = ["Garmin"]
        if let seconds = command.durationSeconds, seconds > 0 {
            let duration = String(format: "%lld:%02lld", seconds / 60, seconds % 60)
            details.append(
                language == "uk" ? "Тривалість \(duration)" :
                    language == "ru" ? "Длительность \(duration)" :
                    "Duration \(duration)"
            )
        }
        if let value = command.gymCalories, value > 0 {
            details.append(language == "uk" ? "Gym ккал \(Int(value))" : "Gym kcal \(Int(value))")
        }
        if let value = command.garminCalories, value > 0 {
            details.append(language == "uk" ? "Garmin ккал \(value)" : "Garmin kcal \(value)")
        }
        if let value = command.averageHeartRate, value > 0 {
            details.append(
                language == "uk" ? "Сер пульс \(value)" :
                    language == "ru" ? "Средний пульс \(value)" :
                    "Avg HR \(value)"
            )
        }
        if let value = command.maximumHeartRate, value > 0 {
            details.append(
                language == "uk" ? "Макс пульс \(value)" :
                    language == "ru" ? "Макс. пульс \(value)" :
                    "Max HR \(value)"
            )
        }
        if let value = command.endingHeartRateZone, value > 0 {
            details.append(
                language == "uk" ? "Кінцева зона пульсу Z\(value)" :
                    language == "ru" ? "Конечная зона пульса Z\(value)" :
                    "Ending HR zone Z\(value)"
            )
        }
        for (index, statistics) in command.setStatistics.enumerated() {
            guard let statistics else { continue }
            var values: [String] = []
            if let value = statistics.activeSeconds { values.append("\(value)s") }
            if let value = statistics.restBeforeSeconds, value > 0 {
                values.append("R\(value)s")
            }
            let heartRates = [
                statistics.startHeartRate,
                statistics.peakHeartRate,
                statistics.endHeartRate
            ]
            if heartRates.contains(where: { $0 != nil }) {
                values.append(
                    "HR" + heartRates.map { $0.map(String.init) ?? "-" }.joined(separator: "/")
                )
            }
            if let value = statistics.recoveryHeartRateDrop { values.append("↓\(value)") }
            if let value = statistics.detectionConfidence { values.append("C\(value)%") }
            if !values.isEmpty {
                details.append("S\(index + 1) \(values.joined(separator: " "))")
            }
        }
        return details.joined(separator: " · ")
    }

    private func matchingWorkout(
        _ command: GarminPhoneWorkoutCommand,
        in store: WorkoutStore
    ) -> Bool {
        let expectedDate = TimeInterval(command.startedAtSeconds)
        let expectedNote = workoutNote(command)
        let names = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0.name) })
        return store.workouts.contains { workout in
            guard abs(workout.date.timeIntervalSince1970 - expectedDate) < 1,
                  workout.note == expectedNote else {
                return false
            }
            let flattened = workout.exercises.flatMap { block in
                block.sets.map {
                    NamedWorkoutSetDraft(
                        exerciseName: names[block.exerciseID] ?? "",
                        weight: $0.weight,
                        reps: $0.reps
                    )
                }
            }
            return flattened == command.sets
        }
    }

    private func loadReceiptLedger(key: String) -> GarminPhoneReceiptLedger {
        guard let data = defaults.data(forKey: key),
              data.count <= 256 * 1_024,
              let value = try? JSONDecoder().decode(GarminPhoneReceiptLedger.self, from: data),
              value.version == GarminPhoneReceiptLedger.currentVersion,
              value.records.count <= GarminPhoneReceiptLedger.maximumRecords,
              Set(value.records.map(\.requestID)).count == value.records.count else {
            return GarminPhoneReceiptLedger(
                version: GarminPhoneReceiptLedger.currentVersion,
                records: []
            )
        }
        return value
    }

    private func saveReceiptLedger(
        _ ledger: GarminPhoneReceiptLedger,
        key: String
    ) -> Bool {
        guard ledger.records.count <= GarminPhoneReceiptLedger.maximumRecords,
              let data = try? JSONEncoder().encode(ledger),
              data.count <= 256 * 1_024 else {
            return false
        }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func updateReceipt(
        requestID: String,
        state: GarminPhoneReceiptLedger.Record.State,
        ledger: inout GarminPhoneReceiptLedger
    ) {
        guard let index = ledger.records.firstIndex(where: { $0.requestID == requestID }) else {
            return
        }
        ledger.records[index].state = state
    }

    private func trimLedger(_ ledger: inout GarminPhoneReceiptLedger) {
        if ledger.records.count > GarminPhoneReceiptLedger.maximumRecords {
            ledger.records.sort { $0.createdAt < $1.createdAt }
            ledger.records.removeFirst(
                ledger.records.count - GarminPhoneReceiptLedger.maximumRecords
            )
        }
    }

    private func deviceArchiveKey(storageKey: String) -> String {
        "garmin-phone-devices.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private static func stateIndexKey(storageKey: String) -> String {
        "garmin-phone-state-index.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private func rememberStateKey(_ key: String, storageKey: String) {
        let indexKey = Self.stateIndexKey(storageKey: storageKey)
        var keys = Set(defaults.stringArray(forKey: indexKey) ?? [])
        guard keys.count <= 1_024 else { return }
        keys.insert(key)
        defaults.set(keys.sorted(), forKey: indexKey)
    }

    func clearLocalData(storageKey: String) {
        Self.clearStoredData(defaults: defaults, storageKey: storageKey)
        if activeStorageKey == storageKey {
            activate(nil)
        }
    }

    static func clearStoredData(defaults: UserDefaults, storageKey: String) {
        let indexKey = stateIndexKey(storageKey: storageKey)
        let indexedKeys = defaults.stringArray(forKey: indexKey) ?? []
        for key in indexedKeys.prefix(1_024) {
            guard key.hasPrefix("garmin-phone-") else { continue }
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(
            forKey: "garmin-phone-devices.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
        )
        defaults.removeObject(forKey: indexKey)
    }

    private func localAccountBindingKey(storageKey: String) -> String {
        "garmin-phone-local-account.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private func pairingGenerationKey(
        accountBinding: String,
        deviceBinding: String
    ) -> String {
        "garmin-phone-generation.v1.\(Data("\(accountBinding)\u{0}\(deviceBinding)".utf8).garminSHA256Hex)"
    }

    private func receiptLedgerKey(binding: GarminPhoneBinding) -> String {
        "garmin-phone-receipts.v1.\(Data("\(binding.account)\u{0}\(binding.device)\u{0}\(binding.pairingGeneration)".utf8).garminSHA256Hex)"
    }

    private func normalizedLanguage(_ rawValue: String?) -> String {
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

extension GarminPhoneSyncService: IQDeviceEventDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor [weak self] in
            self?.refreshDeviceSummaries()
        }
    }

    nonisolated func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        Task { @MainActor [weak self] in
            self?.refreshDeviceSummaries()
        }
    }
}

extension GarminPhoneSyncService: IQAppMessageDelegate {
    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let message, let app else { return }
        Task { @MainActor [weak self] in
            self?.process(message, app: app)
        }
    }
}

private enum GarminPhoneSyncError: Error {
    case accountChanged
}

private extension Data {
    var garminSHA256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var isGarminBinding: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            ("0" ... "9").contains(Character($0)) ||
                ("a" ... "f").contains(Character($0))
        }
    }
}
