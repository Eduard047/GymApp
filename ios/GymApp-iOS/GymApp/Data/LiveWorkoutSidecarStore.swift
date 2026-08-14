import Combine
import Foundation

enum LiveWorkoutSidecarError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case invalidState
    case accountMismatch
    case sessionMismatch
    case noAttachment
    case setUnavailable
    case queueFull
    case staleOperation

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Live workout synchronization could not be saved. Local workout progress is still safe."
        case .invalidState:
            "Live workout synchronization state is invalid and was not used."
        case .accountMismatch, .sessionMismatch:
            "This live workout belongs to another signed-in session."
        case .noAttachment:
            "This local workout is not attached to a live room."
        case .setUnavailable:
            "This set is not part of the frozen live workout plan."
        case .queueFull:
            "Too many live workout updates are waiting to sync. Reconnect before recording more sets."
        case .staleOperation:
            "Live workout progress changed before this update could be confirmed."
        }
    }
}

enum LiveWorkoutPendingOperationKind: String, Codable, Sendable {
    case completeSet = "complete_set"
    case undoSet = "undo_set"
    case finish
}

struct LiveWorkoutPendingOperation: Codable, Equatable, Sendable {
    let clientOperationID: UUID
    let kind: LiveWorkoutPendingOperationKind
    let expectedProgressRevision: Int
    let serverSetID: String?
    let weight: Double?
    let reps: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(kind, forKey: .kind)
        try container.encode(expectedProgressRevision, forKey: .expectedProgressRevision)
        if let serverSetID { try container.encode(serverSetID, forKey: .serverSetID) }
        else { try container.encodeNil(forKey: .serverSetID) }
        if let weight { try container.encode(weight, forKey: .weight) }
        else { try container.encodeNil(forKey: .weight) }
        if let reps { try container.encode(reps, forKey: .reps) }
        else { try container.encodeNil(forKey: .reps) }
    }
}

struct LiveWorkoutAttachment: Codable, Equatable, Sendable {
    let version: Int
    let userID: String
    let sessionID: String
    let roomID: String
    let role: LiveWorkoutRole
    let peerProfileID: String
    let peerDisplayName: String
    var roomRevision: Int
    var membershipRevision: Int
    var progressRevision: Int
    let localDraftID: UUID
    let serverToLocalSetIDs: [String: UUID]
    var pendingOperations: [LiveWorkoutPendingOperation]
}

enum LiveWorkoutQueueReconcileResult: Equatable, Sendable {
    case reconciled(LiveWorkoutAttachment)
    case unsafe
}

@MainActor
final class LiveWorkoutSidecarStore: ObservableObject {
    @Published private(set) var attachment: LiveWorkoutAttachment?
    @Published private(set) var recoveryMessage: String?

    let accountStorageKey: String
    let storageURL: URL

    private let fileManager: FileManager
    private let envelopeWriter: (Data, URL) throws -> Void
    private var writesBlocked = false

    private struct Envelope: Codable {
        let schemaVersion: Int
        let accountStorageKey: String
        let savedAt: Date
        let attachment: LiveWorkoutAttachment?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(accountStorageKey, forKey: .accountStorageKey)
            try container.encode(savedAt, forKey: .savedAt)
            if let attachment { try container.encode(attachment, forKey: .attachment) }
            else { try container.encodeNil(forKey: .attachment) }
        }
    }

    private static let schemaVersion = 1
    private static let maximumFileBytes = 96 * 1_024
    private static let maximumOperations = 256
    private static let maximumSets = 120
    private static let maximumRevision = 2_147_483_647
    private static let roomPattern = try! NSRegularExpression(pattern: #"^lr_[0-9a-f]{32}$"#)
    private static let profilePattern = try! NSRegularExpression(pattern: #"^p_[0-9a-f]{32}$"#)
    private static let setPattern = try! NSRegularExpression(pattern: #"^s_[0-9]{2}_[0-9]{2}$"#)
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
        options: [.caseInsensitive]
    )

    init(
        accountStorageKey: String,
        workoutStorageURL: URL,
        fileManager: FileManager = .default,
        envelopeWriter: ((Data, URL) throws -> Void)? = nil
    ) {
        self.accountStorageKey = accountStorageKey
        self.storageURL = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        self.fileManager = fileManager
        self.envelopeWriter = envelopeWriter ?? Self.writeEnvelopeAtomically
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.excludeFromBackup(storageURL.deletingLastPathComponent())
            attachment = try Self.load(
                accountStorageKey: accountStorageKey,
                storageURL: storageURL,
                fileManager: fileManager
            )
        } catch {
            attachment = nil
            writesBlocked = true
            recoveryMessage = "Live workout synchronization state could not be opened safely. It was not replayed."
        }
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("live-workout.json")
    }

    /// The JWT session is part of the replay boundary. A refreshed access token keeps the
    /// same session id; a new sign-in session cannot replay the old queue until the
    /// coordinator proves it against a fresh authenticated inbox and snapshot.
    func bind(to context: LiveWorkoutSessionContext) throws {
        guard !writesBlocked else { throw LiveWorkoutSidecarError.storageUnavailable }
        guard let current = attachment else { return }
        guard current.userID == context.userID else {
            // Account-keyed storage should make this impossible. Preserve the
            // envelope for forensic/recovery safety instead of deleting another
            // owner's queued mutations from an unexpected context.
            throw LiveWorkoutSidecarError.accountMismatch
        }
        guard current.sessionID == context.sessionID else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
    }

    /// A new JWT session for the same user may adopt the durable queue only after
    /// an authenticated snapshot proves that the room, membership, peer, plan,
    /// local draft mapping, and queued-operation prefix are still authoritative.
    func reconcileAfterSessionChange(
        snapshot: LiveWorkoutSnapshot,
        draft: ActiveWorkoutDraft,
        context: LiveWorkoutSessionContext
    ) throws {
        guard let previous = attachment,
              previous.localDraftID == draft.id else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        let draftSetIDs = Set(draft.exercises.flatMap { exercise in
            exercise.sets.map(\.id)
        })
        guard draftSetIDs.count == previous.serverToLocalSetIDs.count,
              Set(previous.serverToLocalSetIDs.values) == draftSetIDs else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        try persistReboundCandidate(
            try sessionReboundCandidate(snapshot: snapshot, context: context)
        )
    }

    /// A locally committed history row is the durable continuation marker after the
    /// active draft has been cleared. Rebind only when the authoritative snapshot plus
    /// the retained operation suffix projects to that exact row; this permits an offline
    /// queued finish to survive a same-user sign-in without letting unrelated history
    /// adopt another room's queue.
    func reconcileAfterSessionChange(
        snapshot: LiveWorkoutSnapshot,
        committedWorkout: WorkoutSession,
        context: LiveWorkoutSessionContext
    ) throws {
        guard let previous = attachment,
              previous.localDraftID == committedWorkout.id else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        let candidate = try sessionReboundCandidate(snapshot: snapshot, context: context)
        try Self.validate(
            committedWorkout: committedWorkout,
            against: snapshot,
            attachment: candidate
        )
        try persistReboundCandidate(candidate)
    }

    private func sessionReboundCandidate(
        snapshot: LiveWorkoutSnapshot,
        context: LiveWorkoutSessionContext
    ) throws -> LiveWorkoutAttachment {
        guard !writesBlocked else { throw LiveWorkoutSidecarError.storageUnavailable }
        guard let previous = attachment,
              previous.userID == context.userID,
              previous.sessionID != context.sessionID,
              snapshot.room.roomID == previous.roomID,
              snapshot.room.status == .active,
              let participant = snapshot.currentParticipant,
              participant.role == previous.role,
              [.joined, .finished].contains(participant.state),
              let peer = snapshot.peerParticipant,
              peer.profile.profileID == previous.peerProfileID else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        let snapshotSetIDs = Set(snapshot.plan.exercises.flatMap { exercise in
            exercise.sets.map(\.setID)
        })
        guard snapshotSetIDs.count == previous.serverToLocalSetIDs.count,
              Set(previous.serverToLocalSetIDs.keys) == snapshotSetIDs else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        guard case .reconciled(let reconciled) = try Self.reconcile(
            attachment: previous,
            snapshot: snapshot
        ) else {
            throw LiveWorkoutSidecarError.staleOperation
        }
        let candidate = LiveWorkoutAttachment(
            version: reconciled.version,
            userID: reconciled.userID,
            sessionID: context.sessionID,
            roomID: reconciled.roomID,
            role: reconciled.role,
            peerProfileID: reconciled.peerProfileID,
            peerDisplayName: reconciled.peerDisplayName,
            roomRevision: reconciled.roomRevision,
            membershipRevision: reconciled.membershipRevision,
            progressRevision: reconciled.progressRevision,
            localDraftID: reconciled.localDraftID,
            serverToLocalSetIDs: reconciled.serverToLocalSetIDs,
            pendingOperations: reconciled.pendingOperations
        )
        try Self.validate(candidate)
        return candidate
    }

    private func persistReboundCandidate(_ candidate: LiveWorkoutAttachment) throws {
        try persist(candidate)
        attachment = candidate
        recoveryMessage = nil
    }

    private static func validate(
        committedWorkout: WorkoutSession,
        against snapshot: LiveWorkoutSnapshot,
        attachment: LiveWorkoutAttachment
    ) throws {
        guard committedWorkout.id == attachment.localDraftID,
              let progress = snapshot.currentParticipant?.progress else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        var projected = Dictionary(
            uniqueKeysWithValues: progress.completedSets.map {
                ($0.setID, (weight: $0.weight, reps: $0.reps))
            }
        )
        var projectedOrder = progress.completedSets.map(\.setID)
        for operation in attachment.pendingOperations {
            switch operation.kind {
            case .completeSet:
                guard let setID = operation.serverSetID,
                      let weight = operation.weight,
                      let reps = operation.reps,
                      projected[setID] == nil else {
                    throw LiveWorkoutSidecarError.staleOperation
                }
                projected[setID] = (weight, reps)
                projectedOrder.append(setID)
            case .undoSet:
                guard let setID = operation.serverSetID,
                      projectedOrder.last == setID else {
                    throw LiveWorkoutSidecarError.staleOperation
                }
                projected.removeValue(forKey: setID)
                projectedOrder.removeLast()
            case .finish:
                break
            }
        }

        let localRows = committedWorkout.exercises.flatMap { $0.sets }
        guard !localRows.isEmpty,
              Set(localRows.map(\.id)).count == localRows.count,
              localRows.count == projected.count else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        let localByID = Dictionary(uniqueKeysWithValues: localRows.map { ($0.id, $0) })
        for (serverSetID, values) in projected {
            guard let localID = attachment.serverToLocalSetIDs[serverSetID],
                  let local = localByID[localID],
                  local.weight == values.weight,
                  local.reps == values.reps else {
                throw LiveWorkoutSidecarError.sessionMismatch
            }
        }
    }

    @discardableResult
    func attach(
        snapshot: LiveWorkoutSnapshot,
        draft: ActiveWorkoutDraft,
        context: LiveWorkoutSessionContext
    ) throws -> LiveWorkoutAttachment {
        guard !writesBlocked else { throw LiveWorkoutSidecarError.storageUnavailable }
        guard snapshot.room.status == .active,
              let current = snapshot.currentParticipant,
              let peer = snapshot.peerParticipant,
              let progress = current.progress,
              current.state == .joined,
              current.finishedAt == nil,
              progress.finishedAt == nil,
              let startedAtText = snapshot.room.startedAt,
              draft.exercises.count == snapshot.plan.exercises.count,
              draft.plannedSetCount == snapshot.plan.exercises.reduce(0, { $0 + $1.sets.count }) else {
            throw LiveWorkoutSidecarError.invalidState
        }
        let startedAt: Date
        let activeExpiresAt: Date
        do {
            startedAt = try LiveWorkoutPayloadParser.validatedDate(from: startedAtText)
            activeExpiresAt = try LiveWorkoutPayloadParser.validatedDate(
                from: snapshot.room.activeExpiresAt ?? ""
            )
        } catch {
            throw LiveWorkoutSidecarError.invalidState
        }
        guard draft.startedAt == startedAt, draft.workoutDate == startedAt else {
            throw LiveWorkoutSidecarError.invalidState
        }
        let completedByID = Dictionary(
            uniqueKeysWithValues: progress.completedSets.map { ($0.setID, $0) }
        )
        var mapping: [String: UUID] = [:]
        for (exerciseIndex, serverExercise) in snapshot.plan.exercises.enumerated() {
            let localExercise = draft.exercises[exerciseIndex]
            let identityMatches: Bool
            if let expectedCatalogKey = BuiltInExerciseCatalog.canonicalKey(
                forName: serverExercise.name
            ) {
                identityMatches = localExercise.exerciseName.map {
                    BuiltInExerciseCatalog.resolvedKey(
                        catalogKey: localExercise.exerciseCatalogKey,
                        name: $0
                    )
                } == expectedCatalogKey
            } else {
                identityMatches = localExercise.exerciseName.map(normalizeExerciseIdentityName) ==
                    normalizeExerciseIdentityName(serverExercise.name)
            }
            guard identityMatches, localExercise.sets.count == serverExercise.sets.count else {
                throw LiveWorkoutSidecarError.invalidState
            }
            for (setIndex, serverSet) in serverExercise.sets.enumerated() {
                let localSet = localExercise.sets[setIndex]
                guard mapping[serverSet.setID] == nil else {
                    throw LiveWorkoutSidecarError.invalidState
                }
                if let completed = completedByID[serverSet.setID] {
                    let completedAt: Date
                    do {
                        completedAt = try LiveWorkoutPayloadParser.validatedDate(
                            from: completed.completedAt
                        )
                    } catch {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                    guard completedAt >= startedAt,
                          completedAt <= activeExpiresAt,
                          localSet.completedAt == completedAt,
                          localSet.weight == completed.weight,
                          localSet.reps == completed.reps else {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                } else {
                    guard localSet.completedAt == nil,
                          localSet.weight == serverSet.weight,
                          localSet.reps == serverSet.reps else {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                }
                mapping[serverSet.setID] = localSet.id
            }
        }
        let localUndoableSetID = progress.undoableSetID.flatMap { mapping[$0] }
        guard (progress.undoableSetID == nil) == (localUndoableSetID == nil),
              draft.undoableSetID == localUndoableSetID else {
            throw LiveWorkoutSidecarError.invalidState
        }
        let candidate = LiveWorkoutAttachment(
            version: 1,
            userID: context.userID,
            sessionID: context.sessionID,
            roomID: snapshot.room.roomID,
            role: current.role,
            peerProfileID: peer.profile.profileID,
            peerDisplayName: peer.profile.displayName,
            roomRevision: snapshot.room.roomRevision,
            membershipRevision: current.membershipRevision,
            progressRevision: progress.revision,
            localDraftID: draft.id,
            serverToLocalSetIDs: mapping,
            pendingOperations: []
        )
        try Self.validate(candidate)
        try persist(candidate)
        attachment = candidate
        recoveryMessage = nil
        return candidate
    }

    func enqueueCompletedSet(localSetID: UUID, weight: Double, reps: Int) throws {
        try enqueue(kind: .completeSet, localSetID: localSetID, weight: weight, reps: reps)
    }

    /// Checks the entire batch against mapping and queue bounds before the caller
    /// commits the matching local draft revision. No sidecar bytes are changed.
    func preflightCompletedSets(
        _ sets: [(id: UUID, weight: Double, reps: Int)]
    ) throws {
        guard let current = attachment else { throw LiveWorkoutSidecarError.noAttachment }
        _ = try Self.appendingCompletedSets(sets, to: current)
    }

    /// Appends a Save All batch with one atomic envelope replacement. A capacity,
    /// mapping, validation, or disk failure therefore retains the complete old queue
    /// instead of publishing a prefix.
    func enqueueCompletedSets(
        _ sets: [(id: UUID, weight: Double, reps: Int)]
    ) throws {
        guard let current = attachment else { throw LiveWorkoutSidecarError.noAttachment }
        let candidate = try Self.appendingCompletedSets(sets, to: current)
        try persist(candidate)
        attachment = candidate
    }

    func enqueueUndo(localSetID: UUID) throws {
        try enqueue(kind: .undoSet, localSetID: localSetID, weight: nil, reps: nil)
    }

    func enqueueFinish() throws {
        try enqueue(kind: .finish, localSetID: nil, weight: nil, reps: nil)
    }

    func acknowledge(
        operationID: UUID,
        progressRevision: Int,
        roomRevision: Int,
        membershipRevision: Int? = nil
    ) throws {
        guard var current = attachment,
              let acknowledged = current.pendingOperations.first,
              acknowledged.clientOperationID == operationID,
              acknowledged.expectedProgressRevision < Self.maximumRevision,
              progressRevision == acknowledged.expectedProgressRevision + 1,
              Self.validRevision(progressRevision),
              Self.validRevision(roomRevision) else {
            throw LiveWorkoutSidecarError.staleOperation
        }
        current.pendingOperations.removeFirst()
        current.progressRevision = progressRevision
        current.roomRevision = roomRevision
        if let membershipRevision {
            guard Self.validRevision(membershipRevision) else {
                throw LiveWorkoutSidecarError.staleOperation
            }
            current.membershipRevision = membershipRevision
        }
        current.pendingOperations = try Self.revisionBoundOperations(
            current.pendingOperations,
            startingAt: progressRevision
        )
        try Self.validate(current)
        try persist(current)
        attachment = current
    }

    /// Resolves an unknown mutation outcome only when the authoritative snapshot can
    /// prove an exact applied prefix and the retained suffix remains semantically legal.
    /// An unsafe result performs no write so the coordinator can detach fail closed.
    @discardableResult
    func reconcileWithSnapshot(
        _ snapshot: LiveWorkoutSnapshot,
        newOperationID: () -> UUID = UUID.init
    ) throws -> Bool {
        guard let current = attachment else { throw LiveWorkoutSidecarError.noAttachment }
        switch try Self.reconcile(
            attachment: current,
            snapshot: snapshot,
            newOperationID: newOperationID
        ) {
        case .unsafe:
            return false
        case .reconciled(let candidate):
            try persist(candidate)
            attachment = candidate
            return true
        }
    }

    static func reconcile(
        attachment current: LiveWorkoutAttachment,
        snapshot: LiveWorkoutSnapshot,
        newOperationID: () -> UUID = UUID.init
    ) throws -> LiveWorkoutQueueReconcileResult {
        guard snapshot.room.status == .active,
              snapshot.room.roomID == current.roomID,
              let participant = snapshot.currentParticipant,
              participant.role == current.role,
              let peer = snapshot.peerParticipant,
              peer.profile.profileID == current.peerProfileID,
              let progress = participant.progress else {
            return .unsafe
        }
        let appliedCount = progress.revision - current.progressRevision
        guard appliedCount >= 0, appliedCount <= current.pendingOperations.count else {
            return .unsafe
        }

        enum ExpectedSetState {
            case present(weight: Double, reps: Int)
            case absent
        }
        var expectedTouchedSets: [String: ExpectedSetState] = [:]
        var expectedFinished = false
        for operation in current.pendingOperations.prefix(appliedCount) {
            switch operation.kind {
            case .completeSet:
                guard let setID = operation.serverSetID,
                      let weight = operation.weight,
                      let reps = operation.reps else { return .unsafe }
                expectedTouchedSets[setID] = .present(weight: weight, reps: reps)
            case .undoSet:
                guard let setID = operation.serverSetID else { return .unsafe }
                expectedTouchedSets[setID] = .absent
            case .finish:
                expectedFinished = true
            }
        }
        let remoteCompleted = Dictionary(
            uniqueKeysWithValues: progress.completedSets.map { ($0.setID, $0) }
        )
        for (setID, expected) in expectedTouchedSets {
            switch expected {
            case .absent:
                guard remoteCompleted[setID] == nil else { return .unsafe }
            case .present(let weight, let reps):
                guard let completed = remoteCompleted[setID],
                      completed.weight == weight, completed.reps == reps else {
                    return .unsafe
                }
            }
        }
        let remotelyFinished = participant.state == .finished || progress.finishedAt != nil
        if expectedFinished != remotelyFinished && (expectedFinished || remotelyFinished) {
            return .unsafe
        }

        let retained = Array(current.pendingOperations.dropFirst(appliedCount))
        var simulatedCompleted = progress.completedSets.map(\.setID)
        var simulatedUndoable = progress.undoableSetID
        var simulatedFinished = remotelyFinished
        for operation in retained {
            switch operation.kind {
            case .completeSet:
                guard let setID = operation.serverSetID,
                      !simulatedFinished,
                      !simulatedCompleted.contains(setID) else { return .unsafe }
                simulatedCompleted.append(setID)
                simulatedUndoable = setID
            case .undoSet:
                guard let setID = operation.serverSetID,
                      !simulatedFinished,
                      simulatedUndoable == setID,
                      simulatedCompleted.last == setID else { return .unsafe }
                simulatedCompleted.removeLast()
                simulatedUndoable = simulatedCompleted.last
            case .finish:
                guard !simulatedFinished else { return .unsafe }
                simulatedFinished = true
                simulatedUndoable = nil
            }
        }
        guard progress.revision <= maximumRevision - retained.count else {
            return .unsafe
        }
        var candidate = current
        candidate.roomRevision = snapshot.room.roomRevision
        candidate.membershipRevision = participant.membershipRevision
        candidate.progressRevision = progress.revision
        candidate.pendingOperations = retained.enumerated().map { index, operation in
            let expectedRevision = progress.revision + index
            return LiveWorkoutPendingOperation(
                clientOperationID: operation.expectedProgressRevision == expectedRevision
                    ? operation.clientOperationID
                    : newOperationID(),
                kind: operation.kind,
                expectedProgressRevision: expectedRevision,
                serverSetID: operation.serverSetID,
                weight: operation.weight,
                reps: operation.reps
            )
        }
        do {
            try validate(candidate)
        } catch {
            return .unsafe
        }
        return .reconciled(candidate)
    }

    func updateRoomRevisions(
        roomRevision: Int,
        membershipRevision: Int? = nil,
        progressRevision: Int? = nil
    ) throws {
        guard var current = attachment, Self.validRevision(roomRevision) else {
            throw LiveWorkoutSidecarError.invalidState
        }
        current.roomRevision = roomRevision
        if let membershipRevision {
            guard Self.validRevision(membershipRevision) else {
                throw LiveWorkoutSidecarError.invalidState
            }
            current.membershipRevision = membershipRevision
        }
        if let progressRevision {
            guard Self.validRevision(progressRevision), current.pendingOperations.isEmpty else {
                throw LiveWorkoutSidecarError.invalidState
            }
            current.progressRevision = progressRevision
        }
        try Self.validate(current)
        try persist(current)
        attachment = current
    }

    /// Repairs the narrow crash window where a local set commit succeeded but the
    /// following sidecar replacement did not. The server list must be an exact prefix
    /// of the locally completed order (or exactly one latest set ahead after a local
    /// undo); every other divergence is unsafe and leaves the sidecar untouched.
    @discardableResult
    func recoverLocalDraft(
        from snapshot: LiveWorkoutSnapshot,
        draft: ActiveWorkoutDraft
    ) throws -> Bool {
        guard var current = attachment,
              current.pendingOperations.isEmpty,
              current.localDraftID == draft.id,
              snapshot.room.status == .active,
              snapshot.room.roomID == current.roomID,
              let participant = snapshot.currentParticipant,
              participant.role == current.role,
              participant.state == .joined,
              participant.finishedAt == nil,
              let progress = participant.progress,
              progress.finishedAt == nil else {
            return false
        }
        let localSets = Dictionary(
            uniqueKeysWithValues: draft.exercises.flatMap { exercise in
                exercise.sets.map { ($0.id, $0) }
            }
        )
        let planSetIDs = snapshot.plan.exercises.flatMap { $0.sets.map(\.setID) }
        guard Set(planSetIDs) == Set(current.serverToLocalSetIDs.keys),
              localSets.count == current.serverToLocalSetIDs.count else {
            return false
        }
        var completedRows: [(serverID: String, local: ActiveWorkoutSet, planIndex: Int)] = []
        for (planIndex, serverID) in planSetIDs.enumerated() {
            guard let localID = current.serverToLocalSetIDs[serverID],
                  let local = localSets[localID] else { return false }
            if local.completedAt != nil {
                completedRows.append((serverID, local, planIndex))
            }
        }
        completedRows.sort { left, right in
            let leftDate = left.local.completedAt!
            let rightDate = right.local.completedAt!
            return leftDate == rightDate ? left.planIndex < right.planIndex : leftDate < rightDate
        }
        let remote = progress.completedSets
        let commonCount = min(remote.count, completedRows.count)
        for index in 0 ..< commonCount {
            guard remote[index].setID == completedRows[index].serverID,
                  remote[index].weight == completedRows[index].local.weight,
                  remote[index].reps == completedRows[index].local.reps else {
                return false
            }
        }

        current.roomRevision = snapshot.room.roomRevision
        current.membershipRevision = participant.membershipRevision
        current.progressRevision = progress.revision
        if remote.count <= completedRows.count {
            guard remote.count == commonCount else { return false }
            let missing = completedRows.dropFirst(remote.count).map {
                (id: $0.local.id, weight: $0.local.weight, reps: $0.local.reps)
            }
            if !missing.isEmpty {
                current = try Self.appendingCompletedSets(missing, to: current)
            }
        } else {
            guard remote.count == completedRows.count + 1,
                  progress.undoableSetID == remote.last?.setID,
                  let serverSetID = remote.last?.setID,
                  let localID = current.serverToLocalSetIDs[serverSetID],
                  let local = localSets[localID],
                  local.completedAt == nil,
                  remote.last?.weight == local.weight,
                  remote.last?.reps == local.reps,
                  progress.revision < Self.maximumRevision else {
                return false
            }
            current.pendingOperations = [LiveWorkoutPendingOperation(
                clientOperationID: UUID(),
                kind: .undoSet,
                expectedProgressRevision: progress.revision,
                serverSetID: serverSetID,
                weight: nil,
                reps: nil
            )]
        }
        try Self.validate(current)
        if current == attachment { return true }
        try persist(current)
        attachment = current
        return true
    }

    func clear() throws {
        guard !writesBlocked else { throw LiveWorkoutSidecarError.storageUnavailable }
        try persist(nil)
        attachment = nil
        recoveryMessage = nil
    }

    func serverSetID(for localSetID: UUID) -> String? {
        attachment?.serverToLocalSetIDs.first(where: { $0.value == localSetID })?.key
    }

    private static func appendingCompletedSets(
        _ sets: [(id: UUID, weight: Double, reps: Int)],
        to current: LiveWorkoutAttachment
    ) throws -> LiveWorkoutAttachment {
        guard !sets.isEmpty,
              Set(sets.map(\.id)).count == sets.count,
              !current.pendingOperations.contains(where: { $0.kind == .finish }),
              sets.count <= maximumOperations - current.pendingOperations.count,
              current.progressRevision <=
                maximumRevision - current.pendingOperations.count - sets.count else {
            throw LiveWorkoutSidecarError.queueFull
        }
        let localToServer = Dictionary(
            uniqueKeysWithValues: current.serverToLocalSetIDs.map { ($0.value, $0.key) }
        )
        var candidate = current
        for set in sets {
            guard let serverSetID = localToServer[set.id],
                  set.weight.isFinite, (0 ... 1_000_000).contains(set.weight),
                  (1 ... 10_000).contains(set.reps) else {
                throw LiveWorkoutSidecarError.setUnavailable
            }
            candidate.pendingOperations.append(LiveWorkoutPendingOperation(
                clientOperationID: UUID(),
                kind: .completeSet,
                expectedProgressRevision: candidate.progressRevision +
                    candidate.pendingOperations.count,
                serverSetID: serverSetID,
                weight: set.weight,
                reps: set.reps
            ))
        }
        try validate(candidate)
        return candidate
    }

    private func enqueue(
        kind: LiveWorkoutPendingOperationKind,
        localSetID: UUID?,
        weight: Double?,
        reps: Int?
    ) throws {
        guard var current = attachment else { throw LiveWorkoutSidecarError.noAttachment }
        guard current.pendingOperations.count < Self.maximumOperations,
              current.progressRevision <= Self.maximumRevision - current.pendingOperations.count - 1 else {
            throw LiveWorkoutSidecarError.queueFull
        }
        let serverSetID: String?
        switch kind {
        case .completeSet, .undoSet:
            guard let localSetID,
                  let resolved = current.serverToLocalSetIDs.first(where: {
                      $0.value == localSetID
                  })?.key else {
                throw LiveWorkoutSidecarError.setUnavailable
            }
            serverSetID = resolved
        case .finish:
            guard localSetID == nil else { throw LiveWorkoutSidecarError.invalidState }
            serverSetID = nil
        }
        if kind == .completeSet {
            guard let weight, weight.isFinite, (0 ... 1_000_000).contains(weight),
                  let reps, (1 ... 10_000).contains(reps) else {
                throw LiveWorkoutSidecarError.invalidState
            }
        } else if weight != nil || reps != nil {
            throw LiveWorkoutSidecarError.invalidState
        }
        current.pendingOperations.append(LiveWorkoutPendingOperation(
            clientOperationID: UUID(),
            kind: kind,
            expectedProgressRevision: current.progressRevision + current.pendingOperations.count,
            serverSetID: serverSetID,
            weight: weight,
            reps: reps
        ))
        try Self.validate(current)
        try persist(current)
        attachment = current
    }

    private func persist(_ candidate: LiveWorkoutAttachment?) throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            attachment: candidate
        )
        do {
            let data = try Self.encoder().encode(envelope)
            guard data.count <= Self.maximumFileBytes else {
                throw LiveWorkoutSidecarError.invalidState
            }
            try envelopeWriter(data, storageURL)
            try Self.excludeFromBackup(storageURL)
        } catch let error as LiveWorkoutSidecarError {
            throw error
        } catch {
            throw LiveWorkoutSidecarError.storageUnavailable
        }
    }

    private static func load(
        accountStorageKey: String,
        storageURL: URL,
        fileManager: FileManager
    ) throws -> LiveWorkoutAttachment? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: storageURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= maximumFileBytes else {
            throw LiveWorkoutSidecarError.invalidState
        }
        let data = try Data(contentsOf: storageURL, options: .mappedIfSafe)
        try validateEnvelopeShape(data)
        let envelope = try decoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion,
              envelope.accountStorageKey == accountStorageKey,
              envelope.savedAt.timeIntervalSince1970.isFinite else {
            throw LiveWorkoutSidecarError.accountMismatch
        }
        if let attachment = envelope.attachment { try validate(attachment) }
        try excludeFromBackup(storageURL)
        return envelope.attachment
    }

    private static func validate(_ value: LiveWorkoutAttachment) throws {
        guard value.version == 1,
              matches(value.userID, pattern: uuidPattern),
              matches(value.sessionID, pattern: uuidPattern),
              matches(value.roomID, pattern: roomPattern),
              matches(value.peerProfileID, pattern: profilePattern),
              !value.peerDisplayName.isEmpty,
              value.peerDisplayName.first != " ", value.peerDisplayName.last != " ",
              value.peerDisplayName.count <= 40,
              value.peerDisplayName.utf8.count <= 160,
              !value.peerDisplayName.unicodeScalars.contains(where: { scalar in
                  CharacterSet.controlCharacters.contains(scalar) ||
                      scalar.properties.generalCategory == .format ||
                      scalar.value == 0x2028 || scalar.value == 0x2029
              }),
              validRevision(value.roomRevision),
              validRevision(value.membershipRevision),
              validRevision(value.progressRevision),
              !value.serverToLocalSetIDs.isEmpty,
              value.serverToLocalSetIDs.count <= maximumSets,
              Set(value.serverToLocalSetIDs.values).count == value.serverToLocalSetIDs.count,
              value.serverToLocalSetIDs.keys.allSatisfy({ matches($0, pattern: setPattern) }),
              value.pendingOperations.count <= maximumOperations,
              Set(value.pendingOperations.map(\.clientOperationID)).count == value.pendingOperations.count else {
            throw LiveWorkoutSidecarError.invalidState
        }
        for (index, operation) in value.pendingOperations.enumerated() {
            guard operation.expectedProgressRevision == value.progressRevision + index,
                  validRevision(operation.expectedProgressRevision) else {
                throw LiveWorkoutSidecarError.invalidState
            }
            switch operation.kind {
            case .completeSet:
                guard let setID = operation.serverSetID,
                      value.serverToLocalSetIDs[setID] != nil,
                      let weight = operation.weight,
                      weight.isFinite,
                      (0 ... 1_000_000).contains(weight),
                      let reps = operation.reps,
                      (1 ... 10_000).contains(reps) else {
                    throw LiveWorkoutSidecarError.invalidState
                }
            case .undoSet:
                guard let setID = operation.serverSetID,
                      value.serverToLocalSetIDs[setID] != nil,
                      operation.weight == nil,
                      operation.reps == nil else {
                    throw LiveWorkoutSidecarError.invalidState
                }
            case .finish:
                guard operation.serverSetID == nil,
                      operation.weight == nil,
                      operation.reps == nil,
                      index == value.pendingOperations.count - 1 else {
                    throw LiveWorkoutSidecarError.invalidState
                }
            }
        }
    }

    private static func revisionBoundOperations(
        _ operations: [LiveWorkoutPendingOperation],
        startingAt revision: Int
    ) throws -> [LiveWorkoutPendingOperation] {
        guard revision <= maximumRevision - operations.count else {
            throw LiveWorkoutSidecarError.queueFull
        }
        return operations.enumerated().map { index, operation in
            LiveWorkoutPendingOperation(
                clientOperationID: operation.clientOperationID,
                kind: operation.kind,
                expectedProgressRevision: revision + index,
                serverSetID: operation.serverSetID,
                weight: operation.weight,
                reps: operation.reps
            )
        }
    }

    private static func validateEnvelopeShape(_ data: Data) throws {
        try StrictLiveWorkoutJSONScanner.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "accountStorageKey", "savedAt", "attachment"]) else {
            throw LiveWorkoutSidecarError.invalidState
        }
        if let attachment = root["attachment"], !(attachment is NSNull) {
            guard let row = attachment as? [String: Any],
                  Set(row.keys) == Set([
                    "version", "userID", "sessionID", "roomID", "role", "peerProfileID",
                    "peerDisplayName", "roomRevision", "membershipRevision", "progressRevision",
                    "localDraftID", "serverToLocalSetIDs", "pendingOperations"
                  ]),
                  let operations = row["pendingOperations"] as? [[String: Any]],
                  operations.allSatisfy({
                      Set($0.keys) == Set([
                        "clientOperationID", "kind", "expectedProgressRevision", "serverSetID",
                        "weight", "reps"
                      ])
                  }) else {
                throw LiveWorkoutSidecarError.invalidState
            }
        }
    }

    private static func validRevision(_ value: Int) -> Bool {
        (1 ... maximumRevision).contains(value)
    }

    private static func matches(_ value: String, pattern: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return pattern.firstMatch(in: value, range: range)?.range == range
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func excludeFromBackup(_ url: URL) throws {
        try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    private static func writeEnvelopeAtomically(_ data: Data, to url: URL) throws {
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
