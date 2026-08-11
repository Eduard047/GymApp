import Combine
import Foundation

@MainActor
final class LiveWorkoutCoordinator: ObservableObject {
    @Published private(set) var inbox: LiveWorkoutInbox?
    @Published private(set) var snapshot: LiveWorkoutSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isMutating = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastStatus: String?
    @Published private(set) var realtimeConnected = false

    let sidecar: LiveWorkoutSidecarStore

    private let auth: AuthService
    private let workoutStore: WorkoutStore
    private let activeWorkoutStore: ActiveWorkoutStore
    private let gateway: LiveWorkoutGatewayService
    private let expectedUserID: String
    private lazy var realtimeInvalidator = LiveWorkoutRealtimeInvalidator(
        auth: auth,
        expectedUserID: expectedUserID,
        coordinator: self
    )
    private var pollTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pendingInviteRequestIDs: [String: UUID] = [:]

    init(
        auth: AuthService,
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        urlSession: URLSession = .shared
    ) {
        self.auth = auth
        self.workoutStore = workoutStore
        self.activeWorkoutStore = activeWorkoutStore
        self.gateway = LiveWorkoutGatewayService(auth: auth, urlSession: urlSession)
        self.expectedUserID = auth.session?.cloud?.userID ?? ""
        self.sidecar = LiveWorkoutSidecarStore(
            accountStorageKey: workoutStore.accountStorageKey,
            workoutStorageURL: workoutStore.storageURL
        )
    }

    deinit {
        pollTask?.cancel()
        flushTask?.cancel()
    }

    var pendingInvitationCount: Int { inbox?.invitations.count ?? 0 }

    var attachedRoomID: String? { sidecar.attachment?.roomID }

    var isAttachedToCurrentDraft: Bool {
        guard let attachment = sidecar.attachment, let draft = activeWorkoutStore.draft else {
            return false
        }
        return attachment.localDraftID == draft.id
    }

    var planIsFrozenForCurrentDraft: Bool { isAttachedToCurrentDraft }

    var peerProgress: LiveWorkoutProgress? { snapshot?.peerParticipant?.progress }

    var exerciseLaneSummaries: [LiveWorkoutExerciseLaneSummary] {
        snapshot?.exerciseLaneSummaries ?? []
    }

    var peerDisplayName: String? {
        snapshot?.peerParticipant?.profile.displayName ?? sidecar.attachment?.peerDisplayName
    }

    func startMonitoring() {
        guard pollTask == nil, !expectedUserID.isEmpty else { return }
        realtimeInvalidator.start()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshAll(showErrors: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.snapshot?.room.status == .active ? 2 : 5))
                guard !Task.isCancelled else { return }
                await self.refreshAll(showErrors: false)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        flushTask?.cancel()
        flushTask = nil
        realtimeInvalidator.stop()
        gateway.resetForAccountTransition()
        inbox = nil
        snapshot = nil
        lastError = nil
        lastStatus = nil
        realtimeConnected = false
    }

    func refreshAll(showErrors: Bool = true) async {
        guard !isRefreshing, !expectedUserID.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let context = try await gateway.currentContext(expectedUserID: expectedUserID)
            do { try sidecar.bind(to: context) } catch LiveWorkoutSidecarError.sessionMismatch {
                snapshot = nil
            } catch LiveWorkoutSidecarError.accountMismatch {
                snapshot = nil
            }
            let freshInbox = try await gateway.inbox(expectedUserID: expectedUserID)
            try ensureCurrent(context)
            inbox = freshInbox

            if let attachedRoomID = sidecar.attachment?.roomID,
               !freshInbox.rooms.contains(where: { $0.roomID == attachedRoomID }) {
                // Friendship removal/blocking closes the room and intentionally makes
                // its snapshot undiscoverable. Detach only after this authenticated,
                // account-fenced inbox proves that the attached room is gone.
                try sidecar.clear()
                if snapshot?.room.roomID == attachedRoomID { snapshot = nil }
                lastStatus = "The live room is no longer available. Your local workout remains on this iPhone."
            }

            let preferredRoomID = sidecar.attachment?.roomID
                ?? freshInbox.rooms.first(where: { $0.status == .active })?.roomID
                ?? freshInbox.rooms.first?.roomID
            if let preferredRoomID {
                try await refreshSnapshot(
                    roomID: preferredRoomID,
                    context: context,
                    materializeWhenActive: true
                )
            } else if snapshot?.room.status != .completed {
                snapshot = nil
            }
            lastError = nil
            scheduleFlush()
        } catch is CancellationError {
            return
        } catch {
            if showErrors { lastError = gymSafeEnglishErrorMessage(error) }
        }
    }

    func sendInvite(to profileID: String, plan: SharedWorkoutPlan) async throws {
        try beginMutation()
        defer { endMutation() }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        try sidecar.bind(to: context)
        let canonical = try JSONSerialization.data(
            withJSONObject: LiveWorkoutPayloadParser.workoutObject(for: plan),
            options: [.sortedKeys]
        )
        let digest = canonical.base64EncodedString() + ":" + profileID
        let requestID = pendingInviteRequestIDs[digest] ?? UUID()
        pendingInviteRequestIDs[digest] = requestID
        let result = try await gateway.sendInvite(
            profileID: profileID,
            clientRequestID: requestID,
            plan: plan,
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        pendingInviteRequestIDs.removeValue(forKey: digest)
        lastStatus = result.submitted
            ? "Live workout invitation sent. The plan is frozen for this room."
            : "Invitation submitted. The recipient may be unavailable."
        inbox = try? await gateway.inbox(expectedUserID: expectedUserID)
    }

    func respond(to invitation: LiveWorkoutInvitation, accept: Bool) async throws {
        try beginMutation()
        defer { endMutation() }
        if accept, activeWorkoutStore.draft != nil {
            throw ActiveWorkoutStoreError.alreadyActive
        }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        try sidecar.bind(to: context)
        if accept {
            // The inbox intentionally carries only a summary. Read the immutable server
            // snapshot and prove that this exact pending invitation is locally importable
            // before changing membership. In particular, a portable pair of distinct names
            // that resolves to one iOS catalog exercise must stay waiting on the server.
            let frozen = try await gateway.snapshot(
                roomID: invitation.roomID,
                expectedUserID: expectedUserID
            )
            try ensureCurrent(context)
            try Self.validateInvitationAcceptance(snapshot: frozen, invitation: invitation)
            try workoutStore.preflightSharedWorkoutMaterialization(frozen.plan.sharedPlan)
            try ensureCurrent(context)
            guard activeWorkoutStore.draft == nil else {
                throw ActiveWorkoutStoreError.alreadyActive
            }
        }
        let result = try await gateway.respondInvite(
            roomID: invitation.roomID,
            decision: accept ? "accept" : "decline",
            expectedRoomRevision: invitation.roomRevision,
            clientOperationID: UUID(),
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        guard accept ? result.result == "joined" : result.result == "declined" else {
            throw LiveWorkoutGatewayError.invalidResponse
        }
        lastStatus = accept
            ? "Joined the live workout lobby. The owner starts the workout when both are ready."
            : "Live workout invitation declined."
        await refreshAll(showErrors: true)
    }

    static func validateInvitationAcceptance(
        snapshot: LiveWorkoutSnapshot,
        invitation: LiveWorkoutInvitation
    ) throws {
        guard snapshot.room.roomID == invitation.roomID,
              snapshot.room.status == .waiting,
              snapshot.room.roomRevision == invitation.roomRevision,
              snapshot.room.createdAt == invitation.createdAt,
              snapshot.room.inviteExpiresAt == invitation.inviteExpiresAt,
              snapshot.room.summary == invitation.summary,
              let participant = snapshot.currentParticipant,
              participant.role == .participant,
              participant.state == .invited,
              participant.joinedAt == nil,
              participant.progress == nil,
              let owner = snapshot.peerParticipant,
              owner.role == .owner,
              owner.state == .joined,
              owner.profile == invitation.owner,
              owner.progress == nil else {
            throw LiveWorkoutGatewayError.invalidResponse
        }
        do {
            _ = try SharedWorkoutLinkValidator.validate(snapshot.plan.sharedPlan)
        } catch {
            throw LiveWorkoutGatewayError.invalidRequest
        }
    }

    func startRoom(_ room: LiveWorkoutOpenRoom) async throws {
        try beginMutation()
        defer { endMutation() }
        guard room.role == .owner, room.status == .ready, activeWorkoutStore.draft == nil else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        _ = try await gateway.start(
            roomID: room.roomID,
            expectedRoomRevision: room.roomRevision,
            clientOperationID: UUID(),
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        try await refreshSnapshot(
            roomID: room.roomID,
            context: context,
            materializeWhenActive: true
        )
        lastStatus = "Live workout started. Each person records only their own sets."
    }

    func openRoom(_ roomID: String) async throws {
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        try await refreshSnapshot(roomID: roomID, context: context, materializeWhenActive: true)
    }

    func cancelRoom() async throws {
        try beginMutation()
        defer { endMutation() }
        guard let room = snapshot?.room,
              let participant = snapshot?.currentParticipant,
              participant.role == .owner else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        _ = try await gateway.cancel(
            roomID: room.roomID,
            clientOperationID: UUID(),
            expectedRoomRevision: room.roomRevision,
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        try? sidecar.clear()
        await refreshAll(showErrors: true)
        lastStatus = "Live room cancelled. Any local workout progress remains on this iPhone."
    }

    func leaveRoom() async throws {
        try beginMutation()
        defer { endMutation() }
        guard let room = snapshot?.room,
              let participant = snapshot?.currentParticipant,
              participant.role == .participant else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        _ = try await gateway.leave(
            roomID: room.roomID,
            clientOperationID: UUID(),
            expectedMembershipRevision: participant.membershipRevision,
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        try? sidecar.clear()
        await refreshAll(showErrors: true)
        lastStatus = "Left the live room. Any local workout progress remains on this iPhone."
    }

    /// Call only after ActiveWorkoutStore has durably recorded the local set.
    func localSetWasCompleted(localSetID: UUID, weight: Double, reps: Int) throws {
        guard isAttachedToCurrentDraft else { return }
        do {
            try sidecar.enqueueCompletedSet(localSetID: localSetID, weight: weight, reps: reps)
        } catch {
            scheduleFlush()
            throw error
        }
        scheduleFlush()
    }

    /// Call only after ActiveWorkoutStore has durably undone the local set.
    func localSetWasUndone(localSetID: UUID) throws {
        guard isAttachedToCurrentDraft else { return }
        do {
            try sidecar.enqueueUndo(localSetID: localSetID)
        } catch {
            scheduleFlush()
            throw error
        }
        scheduleFlush()
    }

    /// Call only after ActiveWorkoutStore has committed history and cleared its local draft.
    func localWorkoutWasFinished(localDraftID: UUID) throws {
        guard sidecar.attachment?.localDraftID == localDraftID else { return }
        do {
            try sidecar.enqueueFinish()
        } catch {
            scheduleFlush()
            throw error
        }
        scheduleFlush()
    }

    func preflightLocalSetsCompletion(
        _ sets: [(id: UUID, weight: Double, reps: Int)]
    ) throws {
        guard isAttachedToCurrentDraft else { return }
        do {
            try sidecar.preflightCompletedSets(sets)
        } catch {
            scheduleFlush()
            throw error
        }
    }

    func localSetsWereCompleted(_ sets: [(id: UUID, weight: Double, reps: Int)]) throws {
        guard isAttachedToCurrentDraft else { return }
        do {
            try sidecar.enqueueCompletedSets(sets)
        } catch {
            scheduleFlush()
            throw error
        }
        scheduleFlush()
    }

    func clearMessages() {
        lastError = nil
        lastStatus = nil
    }

    /// Realtime and push transports are intentionally only invalidators. Their payloads
    /// never mutate local workout state; an authenticated gateway snapshot remains truth.
    func receiveRealtimeInvalidation(_ value: Any) async {
        do {
            let hint = try LiveWorkoutPayloadParser.realtimeHint(from: value)
            if snapshot?.room.roomID == hint.roomID,
               let currentRevision = snapshot?.room.roomRevision,
               hint.roomRevision <= currentRevision {
                return
            }
            await refreshAll(showErrors: false)
        } catch {
            // A malformed or replayed invalidation is ignored without touching the
            // current room. Polling will still obtain a bounded authoritative snapshot.
        }
    }

    func receiveExternalInvalidation(roomID: String? = nil) async {
        if let roomID,
           snapshot?.room.roomID != roomID,
           sidecar.attachment?.roomID != roomID,
           inbox?.invitations.contains(where: { $0.roomID == roomID }) != true,
           inbox?.rooms.contains(where: { $0.roomID == roomID }) != true {
            return
        }
        await refreshAll(showErrors: false)
    }

    func setRealtimeConnectionState(_ connected: Bool) {
        realtimeConnected = connected
    }

    private func refreshSnapshot(
        roomID: String,
        context: LiveWorkoutSessionContext,
        materializeWhenActive: Bool
    ) async throws {
        let fresh: LiveWorkoutSnapshot
        do {
            fresh = try await gateway.snapshot(roomID: roomID, expectedUserID: expectedUserID)
        } catch LiveWorkoutGatewayError.resourceUnavailable {
            try ensureCurrent(context)
            if sidecar.attachment?.roomID == roomID {
                try sidecar.clear()
            }
            if snapshot?.room.roomID == roomID { snapshot = nil }
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        try ensureCurrent(context)
        snapshot = fresh
        switch fresh.room.status {
        case .active:
            if let attachment = sidecar.attachment {
                guard attachment.roomID == fresh.room.roomID else {
                    throw LiveWorkoutSidecarError.invalidState
                }
                try recoverAttachedLocalState(from: fresh)
            } else if materializeWhenActive,
                      fresh.currentParticipant?.state == .joined {
                try materializeActiveRoom(fresh, context: context)
            }
        case .completed, .cancelled, .expired:
            if sidecar.attachment?.roomID == fresh.room.roomID,
               sidecar.attachment?.pendingOperations.isEmpty == true {
                try sidecar.clear()
            }
        case .waiting, .ready:
            break
        }
    }

    private func materializeActiveRoom(
        _ snapshot: LiveWorkoutSnapshot,
        context: LiveWorkoutSessionContext
    ) throws {
        guard activeWorkoutStore.draft == nil else {
            throw ActiveWorkoutStoreError.alreadyActive
        }
        guard snapshot.room.status == .active,
              let participant = snapshot.currentParticipant,
              participant.state == .joined,
              participant.finishedAt == nil,
              let progress = participant.progress,
              progress.finishedAt == nil,
              let startedAtText = snapshot.room.startedAt,
              let activeExpiresAtText = snapshot.room.activeExpiresAt else {
            throw LiveWorkoutSidecarError.invalidState
        }
        let startedAt: Date
        let activeExpiresAt: Date
        do {
            startedAt = try LiveWorkoutPayloadParser.validatedDate(from: startedAtText)
            activeExpiresAt = try LiveWorkoutPayloadParser.validatedDate(from: activeExpiresAtText)
        } catch {
            throw LiveWorkoutSidecarError.invalidState
        }
        let completedByID = Dictionary(
            uniqueKeysWithValues: progress.completedSets.map { ($0.setID, $0) }
        )
        let drafts = try workoutStore.materializeSharedWorkoutDraft(snapshot.plan.sharedPlan)
        guard drafts.count == snapshot.plan.exercises.count else {
            throw LiveWorkoutSidecarError.invalidState
        }
        var serverToLocalSetID: [String: UUID] = [:]
        let activeExercises = try drafts.enumerated().map { exerciseIndex, draft in
            let serverExercise = snapshot.plan.exercises[exerciseIndex]
            guard draft.sets.count == serverExercise.sets.count else {
                throw LiveWorkoutSidecarError.invalidState
            }
            return ActiveWorkoutExercise(
                exerciseID: draft.exerciseID,
                sets: try draft.sets.enumerated().map { setIndex, localPlanSet in
                    let serverSet = serverExercise.sets[setIndex]
                    let localID = UUID()
                    guard serverToLocalSetID.updateValue(localID, forKey: serverSet.setID) == nil else {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                    guard let completed = completedByID[serverSet.setID] else {
                        return ActiveWorkoutSet(
                            id: localID,
                            weight: localPlanSet.weight,
                            reps: localPlanSet.reps
                        )
                    }
                    let completedAt: Date
                    do {
                        completedAt = try LiveWorkoutPayloadParser.validatedDate(
                            from: completed.completedAt
                        )
                    } catch {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                    guard completedAt >= startedAt, completedAt <= activeExpiresAt else {
                        throw LiveWorkoutSidecarError.invalidState
                    }
                    return ActiveWorkoutSet(
                        id: localID,
                        weight: completed.weight,
                        reps: completed.reps,
                        completedAt: completedAt
                    )
                }
            )
        }
        let undoableLocalSetID = progress.undoableSetID.flatMap { serverToLocalSetID[$0] }
        guard (progress.undoableSetID == nil) == (undoableLocalSetID == nil) else {
            throw LiveWorkoutSidecarError.invalidState
        }
        do {
            _ = try activeWorkoutStore.startRecoveredLiveWorkout(
                startedAt: startedAt,
                exercises: activeExercises,
                undoableSetID: undoableLocalSetID,
                workoutStore: workoutStore,
                persistBindingBeforeCommit: { candidate in
                    _ = try self.sidecar.attach(
                        snapshot: snapshot,
                        draft: candidate,
                        context: context
                    )
                }
            )
        } catch {
            if activeWorkoutStore.draft == nil,
               sidecar.attachment?.roomID == snapshot.room.roomID {
                try? sidecar.clear()
            }
            throw error
        }
    }

    private func recoverAttachedLocalState(from fresh: LiveWorkoutSnapshot) throws {
        guard let attachment = sidecar.attachment,
              let participant = fresh.currentParticipant,
              let progress = participant.progress else {
            throw LiveWorkoutSidecarError.invalidState
        }
        if let draft = activeWorkoutStore.draft,
           draft.id == attachment.localDraftID {
            guard participant.state == .joined,
                  progress.finishedAt == nil else {
                try sidecar.clear()
                throw LiveWorkoutSidecarError.staleOperation
            }
            if attachment.pendingOperations.isEmpty {
                let recovered = try sidecar.recoverLocalDraft(from: fresh, draft: draft)
                if !recovered {
                    try sidecar.clear()
                    throw LiveWorkoutSidecarError.staleOperation
                }
            }
            return
        }

        guard workoutStore.workout(id: attachment.localDraftID) != nil else {
            try sidecar.clear()
            throw LiveWorkoutSidecarError.noAttachment
        }
        if participant.state == .joined, progress.finishedAt == nil {
            if !attachment.pendingOperations.contains(where: { $0.kind == .finish }) {
                // The durable history row is the recovery marker for a crash or disk
                // failure between local completion and queueing the finish mutation.
                do {
                    try sidecar.enqueueFinish()
                } catch LiveWorkoutSidecarError.queueFull {
                    // Drain the already durable prefix first. refreshAll schedules that
                    // drain after this method returns, then a later snapshot appends finish.
                    return
                }
            }
        } else if participant.state == .finished, attachment.pendingOperations.isEmpty {
            try sidecar.updateRoomRevisions(
                roomRevision: fresh.room.roomRevision,
                membershipRevision: participant.membershipRevision,
                progressRevision: progress.revision
            )
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil,
              let attachment = sidecar.attachment,
              !attachment.pendingOperations.isEmpty else { return }
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.flushTask = nil }
            await self.flushPendingOperations()
        }
    }

    private func flushPendingOperations() async {
        do {
            let context = try await gateway.currentContext(expectedUserID: expectedUserID)
            try sidecar.bind(to: context)
            while let attachment = sidecar.attachment,
                  let operation = attachment.pendingOperations.first {
                try ensureCurrent(context)
                if activeWorkoutStore.draft == nil,
                   workoutStore.workout(id: attachment.localDraftID) == nil {
                    throw LiveWorkoutSidecarError.noAttachment
                }
                do {
                    switch operation.kind {
                    case .completeSet:
                        guard let setID = operation.serverSetID,
                              let weight = operation.weight,
                              let reps = operation.reps else {
                            throw LiveWorkoutSidecarError.invalidState
                        }
                        let result = try await gateway.apply(
                            roomID: attachment.roomID,
                            clientOperationID: operation.clientOperationID,
                            expectedProgressRevision: operation.expectedProgressRevision,
                            kind: operation.kind.rawValue,
                            setID: setID,
                            weight: weight,
                            reps: reps,
                            expectedUserID: expectedUserID
                        )
                        try sidecar.acknowledge(
                            operationID: operation.clientOperationID,
                            progressRevision: result.progressRevision,
                            roomRevision: result.roomRevision
                        )
                    case .undoSet:
                        guard let setID = operation.serverSetID else {
                            throw LiveWorkoutSidecarError.invalidState
                        }
                        let result = try await gateway.apply(
                            roomID: attachment.roomID,
                            clientOperationID: operation.clientOperationID,
                            expectedProgressRevision: operation.expectedProgressRevision,
                            kind: operation.kind.rawValue,
                            setID: setID,
                            expectedUserID: expectedUserID
                        )
                        try sidecar.acknowledge(
                            operationID: operation.clientOperationID,
                            progressRevision: result.progressRevision,
                            roomRevision: result.roomRevision
                        )
                    case .finish:
                        let result = try await gateway.finish(
                            roomID: attachment.roomID,
                            clientOperationID: operation.clientOperationID,
                            expectedProgressRevision: operation.expectedProgressRevision,
                            expectedUserID: expectedUserID
                        )
                        try sidecar.acknowledge(
                            operationID: operation.clientOperationID,
                            progressRevision: result.progressRevision,
                            roomRevision: result.roomRevision,
                            membershipRevision: result.membershipRevision
                        )
                    }
                } catch LiveWorkoutGatewayError.conflict {
                    try await reconcileAfterConflict(context: context)
                    // Do not retry a recovered 409 in this drain turn. Polling or the
                    // next authenticated invalidation provides a bounded retry cadence.
                    lastError = nil
                    return
                } catch LiveWorkoutGatewayError.resourceUnavailable {
                    do {
                        let fresh = try await gateway.snapshot(
                            roomID: attachment.roomID,
                            expectedUserID: expectedUserID
                        )
                        try ensureCurrent(context)
                        snapshot = fresh
                        guard [.completed, .cancelled, .expired].contains(fresh.room.status) else {
                            throw LiveWorkoutGatewayError.resourceUnavailable
                        }
                    } catch LiveWorkoutGatewayError.resourceUnavailable {
                        // A removed friendship intentionally makes the closed room
                        // unreadable. The authenticated 404 is terminal for this binding.
                        try ensureCurrent(context)
                    }
                    try sidecar.clear()
                    if snapshot?.room.roomID == attachment.roomID { snapshot = nil }
                    lastStatus = "Live synchronization ended. Your local workout remains saved."
                    return
                }
            }
            if let roomID = sidecar.attachment?.roomID {
                try? await refreshSnapshot(
                    roomID: roomID,
                    context: context,
                    materializeWhenActive: false
                )
            }
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            lastError = gymSafeEnglishErrorMessage(error)
        }
    }

    private func reconcileAfterConflict(context: LiveWorkoutSessionContext) async throws {
        guard let attachment = sidecar.attachment,
              !attachment.pendingOperations.isEmpty else {
            throw LiveWorkoutSidecarError.staleOperation
        }
        let fresh: LiveWorkoutSnapshot
        do {
            fresh = try await gateway.snapshot(
                roomID: attachment.roomID,
                expectedUserID: expectedUserID
            )
        } catch LiveWorkoutGatewayError.resourceUnavailable {
            try ensureCurrent(context)
            if sidecar.attachment?.roomID == attachment.roomID {
                try sidecar.clear()
            }
            if snapshot?.room.roomID == attachment.roomID { snapshot = nil }
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        try ensureCurrent(context)
        snapshot = fresh
        guard fresh.room.status == .active else {
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        guard try sidecar.reconcileWithSnapshot(fresh) else {
            // Preserve the local workout, but permanently detach this ambiguous queue.
            // Polling must not turn an impossible operation into a retry/rate-limit loop.
            try sidecar.clear()
            throw LiveWorkoutSidecarError.staleOperation
        }
    }

    private func beginMutation() throws {
        guard !isMutating else { throw LiveWorkoutGatewayError.conflict }
        isMutating = true
    }

    private func endMutation() {
        isMutating = false
    }

    private func ensureCurrent(_ context: LiveWorkoutSessionContext) throws {
        guard auth.session?.cloud?.userID == expectedUserID,
              context.userID == expectedUserID,
              workoutStore.accountStorageKey == auth.session?.storageKey,
              activeWorkoutStore.accountStorageKey == workoutStore.accountStorageKey else {
            throw AuthServiceError.sessionChanged
        }
    }
}
