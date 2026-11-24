import Foundation

/// The last valid context from the phone (context.json, the exact codec bytes).
final class PlanStore {
    private let files: WatchFileStore
    private static let name = "context.json"
    private(set) var context: WatchContextMessage?

    init(files: WatchFileStore) {
        self.files = files
        if let data = files.read(name: Self.name, maximumBytes: WatchSync.maximumEnvelopeBytes) {
            context = WatchSyncCodec.decodeContext(data)
        }
    }

    /// Merges and persists an incoming context; returns the context now in effect.
    @discardableResult
    func apply(_ incoming: WatchContextMessage) -> WatchContextMessage {
        replace(WatchContextMerge.merge(cached: context, incoming: incoming))
    }

    /// Stores an already merged context as it is.
    @discardableResult
    func replace(_ merged: WatchContextMessage) -> WatchContextMessage {
        context = merged
        if let data = try? WatchSyncCodec.encode(merged) {
            try? files.write(data, name: Self.name)
        }
        return merged
    }
}
