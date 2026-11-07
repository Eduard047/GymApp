import Foundation
import CryptoKit

struct GarminPhonePlanDelivery: Codable, Equatable {
    let version: Int
    let binding: GarminPhoneBinding
    let syncID: String
    let revision: Int64
    let language: String
    let sets: [NamedWorkoutSetDraft]
    let exercises: [String]
    var acknowledged: Bool

    var isValid: Bool {
        version == 1 && !sets.isEmpty && revision >= 0 && (!acknowledged || revision > 0) &&
            GarminPhoneSyncProtocol.syncPayload(
                binding: binding, syncID: syncID, revision: max(1, revision),
                language: language, exercises: exercises, resetWorkout: false,
                plan: sets, requireAsciiNames: false
            ) != nil
    }

    func matchesContent(
        binding: GarminPhoneBinding, language: String,
        sets: [NamedWorkoutSetDraft], exercises: [String]
    ) -> Bool {
        self.binding == binding && self.language == language &&
            self.sets == sets && self.exercises == exercises
    }
}

/// Persisted per-account Garmin watch name table (append-only latin <-> raw rows). Stored in its own
/// account-level file because plan deliveries are per watch while the table is per account.
struct GarminLatinNameTableState: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    var entries: [GarminLatinEntry]

    init(version: Int = GarminLatinNameTableState.currentVersion, entries: [GarminLatinEntry]) {
        self.version = version
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case version, entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backward compatible: a missing version reads as 1, a missing entries list as empty.
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try container.decodeIfPresent([GarminLatinEntry].self, forKey: .entries) ?? []
    }
}

/// The last requested plan stays scoped to one account, watch and pairing.
/// Keeping it after ACK prevents an ordinary reconnect from clearing the plan.
final class GarminPhonePlanStore {
    private let root: URL
    private let lock = NSLock()
    private let maximumBytes = 65_536
    private let maximumLatinTableBytes = 4_194_304
    private static let latinTableFileName = "latin-names.json"
    /// The table keeps at most twice the exercise limit; only rows of deleted exercises are pruned.
    static let maximumLatinTableEntries = BackupImportLimits.standard.maximumExercises * 2

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GarminPhonePlans", isDirectory: true)
    }

    func load(account: String, binding: GarminPhoneBinding) throws -> GarminPhonePlanDelivery? {
        lock.lock()
        defer { lock.unlock() }
        let file = location(account: account, device: binding.device)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let value = try JSONDecoder().decode(GarminPhonePlanDelivery.self, from: read(file))
        guard value.isValid else { throw GarminCloudError.invalidPlan }
        // A previous generation is never silently adopted by a new pairing.
        return value.binding == binding ? value : nil
    }

    func save(_ value: GarminPhonePlanDelivery, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard value.isValid else { throw GarminCloudError.invalidPlan }
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw GarminCloudError.invalidPlan }
        let file = location(account: account, device: value.binding.device)
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try (file as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        guard try read(file) == data else { throw CocoaError(.fileWriteUnknown) }
    }

    @discardableResult
    func clear(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let directory = root.appendingPathComponent(hash(account), isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            return true
        } catch { return false }
    }

    @discardableResult
    func retain(account: String, devices: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let directory = root.appendingPathComponent(hash(account), isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return true }
        let names = Set(devices.map { hash($0) + ".json" } + [Self.latinTableFileName])
        do {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if !names.contains(file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
            }
            return true
        } catch { return false }
    }

    /// Current append-only table rows of the account (empty when nothing was stored yet).
    func loadLatinNames(account: String) throws -> [GarminLatinEntry] {
        lock.lock()
        defer { lock.unlock() }
        return try loadLatinTable(account: account).entries
    }

    /// Assigns the watch names for `names` and appends the new rows before returning, so a name is
    /// never sent before it is stored. Returns nil when the table is full of names that still belong to
    /// current exercises (the caller must then refuse to send).
    func assignLatinNames(
        account: String,
        names: [String],
        currentExerciseNames: [String],
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames()
    ) throws -> GarminLatinAssignment? {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadLatinTable(account: account)
        let assignment = GarminLatinNames.assign(
            names: currentExerciseNames + names,
            existing: state.entries,
            builtIns: builtIns
        )
        guard !assignment.newEntries.isEmpty else { return assignment }
        let overflow = state.entries.count + assignment.newEntries.count - Self.maximumLatinTableEntries
        if overflow > 0 {
            let current = Set(currentExerciseNames)
            let removable = state.entries.filter { !current.contains($0.raw) }.prefix(overflow)
            guard removable.count >= overflow else { return nil }
            let removedLatin = Set(removable.map(\.latin))
            state.entries.removeAll { removedLatin.contains($0.latin) }
        }
        state.entries.append(contentsOf: assignment.newEntries)
        try saveLatinTable(state, account: account)
        return assignment
    }

    private func latinTableLocation(account: String) -> URL {
        root.appendingPathComponent(hash(account), isDirectory: true)
            .appendingPathComponent(Self.latinTableFileName)
    }

    private func loadLatinTable(account: String) throws -> GarminLatinNameTableState {
        let file = latinTableLocation(account: account)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return GarminLatinNameTableState(entries: [])
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maximumLatinTableBytes + 1)
        guard data.count <= maximumLatinTableBytes else { throw CocoaError(.fileReadTooLarge) }
        let state = try JSONDecoder().decode(GarminLatinNameTableState.self, from: data)
        // A newer app wrote this file: never guess at its meaning, refuse to send instead.
        guard state.version <= GarminLatinNameTableState.currentVersion else {
            throw GarminCloudError.invalidPlan
        }
        return state
    }

    private func saveLatinTable(_ state: GarminLatinNameTableState, account: String) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= maximumLatinTableBytes else { throw GarminCloudError.invalidPlan }
        let file = latinTableLocation(account: account)
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try (file as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    private func location(account: String, device: String) -> URL {
        root.appendingPathComponent(hash(account), isDirectory: true)
            .appendingPathComponent(hash(device) + ".json")
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func read(_ file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maximumBytes + 1)
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
