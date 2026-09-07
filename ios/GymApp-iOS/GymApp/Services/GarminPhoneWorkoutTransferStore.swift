import Foundation
import CryptoKit

/// A caller supplies its trusted account storage key and registered device ID.
/// Workout parts never enter UserDefaults or backup-eligible storage.
final class GarminPhoneWorkoutTransferStore {
    private let root: URL
    private let lock = NSLock()

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GarminWorkoutTransfers", isDirectory: true)
    }

    func accept(
        account: String, device: String, frame: Any,
        binding: GarminPhoneBinding, now: Date = Date()
    ) -> GarminPhoneTransferStep? {
        lock.lock()
        defer { lock.unlock() }
        do {
            let directory = accountDirectory(account)
            let file = directory.appendingPathComponent(hash(device) + ".json")
            let previous = FileManager.default.fileExists(atPath: file.path) ? try read(file) : nil
            guard let step = GarminPhoneWorkoutTransfer.accept(previous: previous, raw: frame, binding: binding, now: now) else { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            try (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            try step.state.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try (file as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            guard try read(file) == step.state else { return nil }
            return step
        } catch { return nil }
    }

    @discardableResult
    func clear(account: String, device: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let directory = accountDirectory(account)
        let target = device.map { directory.appendingPathComponent(hash($0) + ".json") } ?? directory
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            return true
        } catch { return false }
    }

    private func accountDirectory(_ account: String) -> URL {
        root.appendingPathComponent(hash(account), isDirectory: true)
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func read(_ file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 65537)
        guard data.count <= 65536 else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
