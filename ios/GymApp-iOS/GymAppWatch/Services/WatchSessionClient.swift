import Foundation
import WatchConnectivity

/// WCSession on the watch: context in, ack/nack in, finished workouts out (transferUserInfo).
/// Delegate callbacks arrive off the main thread; only the envelope bytes cross to the main actor.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    var onContextBytes: ((Data) -> Void)?
    var onReplyBytes: ((Data) -> Void)?
    var onActivated: (() -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Queues the exact envelope bytes; the system delivers them even if the phone app is not running.
    func transfer(_ envelope: Data) -> Bool {
        guard let session, session.activationState == .activated else { return false }
        session.transferUserInfo(WatchSyncCodec.envelope(envelope))
        return true
    }

    /// Request ids still waiting in WatchConnectivity's own queue (never re-sent while there).
    func outstandingRequestIDs() -> Set<String> {
        guard let session else { return [] }
        return Set(session.outstandingUserInfoTransfers.compactMap { transfer -> String? in
            guard let bytes = WatchSyncCodec.envelopeBytes(from: transfer.userInfo),
                  let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
            return object["requestId"] as? String
        })
    }
}

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let bytes = WatchSyncCodec.envelopeBytes(from: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            // The newest context first, so the flush never runs against a stale account binding.
            if let bytes { self.onContextBytes?(bytes) }
            self.onActivated?()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.onActivated?() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let bytes = WatchSyncCodec.envelopeBytes(from: applicationContext) else { return }
        Task { @MainActor in self.onContextBytes?(bytes) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let bytes = WatchSyncCodec.envelopeBytes(from: userInfo) else { return }
        Task { @MainActor in self.onReplyBytes?(bytes) }
    }
}
