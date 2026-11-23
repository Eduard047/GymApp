import Foundation

/// Protected, backup-excluded files under ApplicationSupport/GymAppWatch.
struct WatchFileStore {
    let root: URL

    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GymAppWatch", isDirectory: true)
    }

    func directory(_ sub: String?) throws -> URL {
        let url = sub.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        for folder in [root, url] {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try excludeFromBackup(folder)
        }
        return url
    }

    func write(_ data: Data, name: String, in sub: String? = nil) throws {
        let url = try directory(sub).appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try excludeFromBackup(url)
    }

    func read(name: String, in sub: String? = nil, maximumBytes: Int) -> Data? {
        guard let url = try? directory(sub).appendingPathComponent(name),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= maximumBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    func delete(name: String, in sub: String? = nil) throws {
        let url = try directory(sub).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func list(in sub: String) -> [String] {
        guard let url = try? directory(sub) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try target.setResourceValues(values)
    }
}
