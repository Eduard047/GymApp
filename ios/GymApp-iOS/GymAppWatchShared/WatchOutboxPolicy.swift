import Foundation

enum WatchOutboxStatus: String, Codable, Sendable {
    /// Waiting to be sent (or to be retried after a transient nack).
    case queued
    /// Handed to WatchConnectivity; waiting for the phone's reply.
    case sent
    /// Hold nack: not sent until a matching context arrives.
    case held
    /// Deterministic nack: kept until the user discards it.
    case failed
}

/// One finished workout waiting for the phone's ack. The exact encoded
/// envelope is stored so every resend is byte-identical (the phone digest matches).
struct WatchOutboxItem: Codable, Equatable, Sendable {
    let requestId: String
    let accountBinding: String
    var envelope: Data
    var status: WatchOutboxStatus
    var reason: String?
    var attempts: Int
    var nextAttemptAtMillis: Int64
    /// The phone's context protocol version last seen when the item was held (unsupported-version hold).
    var heldProtocolVersion: Int?
    /// Once sent, the envelope is never rewritten.
    var everSent: Bool
    let createdAtMillis: Int64
    var summary: WatchWorkoutSummary
}

/// Pure state transitions for outbox items (shared/watch-sync-v1.json watchOutboxRules).
enum WatchOutboxPolicy {
    static let backoffSeconds: [Int64] = [60, 300, 900, 3_600]

    /// Backoff after the n-th attempt: 60, 300, 900, 3600 s, capped at 3600.
    static func backoffMillis(afterAttempts attempts: Int) -> Int64 {
        let index = min(max(attempts - 1, 0), backoffSeconds.count - 1)
        return backoffSeconds[index] * 1_000
    }

    static func makeItem(
        message: WatchWorkoutMessage,
        envelope: Data,
        summary: WatchWorkoutSummary,
        nowMillis: Int64
    ) -> WatchOutboxItem {
        WatchOutboxItem(
            requestId: message.requestId,
            accountBinding: message.accountBinding,
            envelope: envelope,
            status: .queued,
            reason: nil,
            attempts: 0,
            nextAttemptAtMillis: nowMillis,
            heldProtocolVersion: nil,
            everSent: false,
            createdAtMillis: nowMillis,
            summary: summary
        )
    }

    /// Whether the envelope may still be rewritten (for example healthKit "failed"): only before the first send.
    static func canRewrite(_ item: WatchOutboxItem) -> Bool { !item.everSent }

    /// The item with other envelope bytes, or nil once it was handed to WatchConnectivity:
    /// a resend with other bytes under the same requestId is a conflict on the phone.
    static func rewriting(_ item: WatchOutboxItem, envelope: Data) -> WatchOutboxItem? {
        guard canRewrite(item) else { return nil }
        var next = item
        next.envelope = envelope
        return next
    }

    /// An active snapshot whose requestId is already in the outbox was finished before
    /// the app died (killed between the outbox write and the snapshot delete).
    static func isAlreadyFinished(requestId: String, outbox: [WatchOutboxItem]) -> Bool {
        outbox.contains { $0.requestId == requestId }
    }

    enum ReplyOutcome: Equatable, Sendable {
        case delete
        case update(WatchOutboxItem)
        case ignore
    }

    /// Applies an ack or nack. An item is deleted only by an ack whose requestId and accountBinding match.
    /// `contextProtocolVersion` is the protocol version of the phone's last context: an
    /// unsupported-version hold remembers it and is released by a context with a greater one.
    static func apply(
        _ reply: WatchReply,
        to item: WatchOutboxItem,
        nowMillis: Int64,
        contextProtocolVersion: Int = WatchSync.protocolVersion
    ) -> ReplyOutcome {
        switch reply {
        case .ack(let ack):
            guard ack.requestId == item.requestId, ack.accountBinding == item.accountBinding else { return .ignore }
            return .delete
        case .nack(let nack):
            guard nack.requestId == item.requestId else { return .ignore }
            var next = item
            next.reason = nack.reason.rawValue
            switch nack.reason.group {
            case .transient:
                next.status = .queued
                next.nextAttemptAtMillis = nowMillis + backoffMillis(afterAttempts: max(item.attempts, 1))
                next.heldProtocolVersion = nil
            case .hold:
                next.status = .held
                next.heldProtocolVersion = nack.reason == .unsupportedVersion ? contextProtocolVersion : nil
            case .deterministic:
                next.status = .failed
                next.heldProtocolVersion = nil
            }
            return .update(next)
        }
    }

    /// A new context releases matching holds and makes transient items due now.
    /// `protocolVersion` is the incoming phone context's protocol version.
    static func applyContext(
        _ context: WatchContextMessage,
        to item: WatchOutboxItem,
        nowMillis: Int64,
        protocolVersion: Int = WatchSync.protocolVersion
    ) -> WatchOutboxItem {
        guard let bound = context.bound, bound.accountBinding == item.accountBinding else { return item }
        var next = item
        switch item.status {
        case .held:
            let releases: Bool
            if item.reason == WatchNackReason.unsupportedVersion.rawValue {
                releases = protocolVersion > (item.heldProtocolVersion ?? protocolVersion)
            } else {
                releases = true
            }
            guard releases else { return item }
            next.status = .queued
            next.heldProtocolVersion = nil
            next.nextAttemptAtMillis = nowMillis
        case .queued, .sent:
            next.nextAttemptAtMillis = min(item.nextAttemptAtMillis, nowMillis)
        case .failed:
            break
        }
        return next
    }

    /// Sent only while the latest context is bound to the item's account, when due and not already in flight.
    static func isSendable(
        _ item: WatchOutboxItem,
        context: WatchContextMessage?,
        nowMillis: Int64,
        outstanding: Set<String>
    ) -> Bool {
        guard item.status == .queued || item.status == .sent,
              let bound = context?.bound,
              bound.accountBinding == item.accountBinding,
              item.nextAttemptAtMillis <= nowMillis else { return false }
        return !outstanding.contains(item.requestId)
    }

    static func markSent(_ item: WatchOutboxItem, nowMillis: Int64) -> WatchOutboxItem {
        var next = item
        next.status = .sent
        next.attempts = item.attempts + 1
        next.everSent = true
        next.nextAttemptAtMillis = nowMillis + backoffMillis(afterAttempts: next.attempts)
        return next
    }

    /// Starting a new workout is blocked only when the outbox is full; the oldest item is never evicted.
    static func canStartWorkout(itemCount: Int) -> Bool {
        itemCount < WatchSync.maximumOutboxItems
    }

    /// What the watch drops after an `account-deleted` message: only that owner's work.
    /// A workout being saved is not discarded mid-save; its item is dropped once the save settles.
    static func accountDeleted(
        _ accountBinding: String,
        outbox: [WatchOutboxItem],
        workout: WatchActiveWorkout?,
        isSaving: Bool
    ) -> WatchAccountDeletionPlan {
        guard WatchSync.isValidHash(accountBinding) else {
            return .init(deleteRequestIds: [], discardWorkout: false, dropSavedItem: false)
        }
        let ownsWorkout = workout?.accountBinding == accountBinding
        return .init(
            deleteRequestIds: outbox.filter { $0.accountBinding == accountBinding }.map(\.requestId),
            discardWorkout: ownsWorkout && !isSaving,
            dropSavedItem: ownsWorkout && isSaving
        )
    }

    /// A save that failed before its outbox write normally returns to Summary. If the owner
    /// was deleted on the phone during that save, the workout is discarded instead.
    static func discardsAfterFailedSave(_ workout: WatchActiveWorkout, deletedWhileSaving: Set<String>) -> Bool {
        deletedWhileSaving.contains(workout.accountBinding)
    }
}

struct WatchAccountDeletionPlan: Equatable, Sendable {
    /// Outbox items of the deleted owner (every status).
    let deleteRequestIds: [String]
    /// The live or summary workout belongs to the deleted owner: discard it silently.
    let discardWorkout: Bool
    /// The workout being saved belongs to the deleted owner: drop its item when the save settles.
    let dropSavedItem: Bool
}
