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
                plan: sets
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

/// The last requested plan stays scoped to one account, watch and pairing.
/// Keeping it after ACK prevents an ordinary reconnect from clearing the plan.
final class GarminPhonePlanStore {
    private let root: URL
    private let lock = NSLock()
    private let maximumBytes = 65_536

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
        let names = Set(devices.map { hash($0) + ".json" })
        do {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if !names.contains(file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
            }
            return true
        } catch { return false }
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
