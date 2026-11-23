import Foundation

/// Finished workouts waiting for the phone's ack: outbox/<requestId>.json, one file per item.
final class OutboxStore {
    private let files: WatchFileStore
    private static let folder = "outbox"
    private static let maximumBytes = 256 * 1_024

    init(files: WatchFileStore) {
        self.files = files
    }

    func loadAll() -> [WatchOutboxItem] {
        let decoder = JSONDecoder()
        return files.list(in: Self.folder)
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> WatchOutboxItem? in
                guard let data = files.read(name: name, in: Self.folder, maximumBytes: Self.maximumBytes),
                      let item = try? decoder.decode(WatchOutboxItem.self, from: data),
                      WatchSync.isValidRequestID(item.requestId),
                      name == item.requestId + ".json" else { return nil }
                return item
            }
            .sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    func save(_ item: WatchOutboxItem) throws {
        guard WatchSync.isValidRequestID(item.requestId) else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try files.write(try encoder.encode(item), name: item.requestId + ".json", in: Self.folder)
    }

    func delete(requestId: String) throws {
        guard WatchSync.isValidRequestID(requestId) else { return }
        try files.delete(name: requestId + ".json", in: Self.folder)
    }
}
