import Combine
import Foundation

enum LiveWorkoutInvitationResponseOutcome: Equatable, Sendable {
    case declined
    case active
    case confirmedRestoring
}

@MainActor
final class LiveWorkoutCoordinator: ObservableObject {
    @Published private(set) var inbox: LiveWorkoutInbox?
    @Published private(set) var snapshot: LiveWorkoutSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isMutating = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastStatus: String?
    @Published private(set) var realtimeConnected = false
    @Published private(set) var restoringRoomIDs: Set<String> = []
    @Published private(set) var confirmedDraftConsumption: LiveWorkoutDraftConsumption?

    let sidecar: LiveWorkoutSidecarStore
    let draftConsumptionStore: LiveWorkoutDraftConsumptionStore
    private var slotReservation: LiveWorkoutSlotReservationStore {
        activeWorkoutStore.liveSlotReservationStore
    }

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
        self.draftConsumptionStore = LiveWorkoutDraftConsumptionStore(
            accountStorageKey: workoutStore.accountStorageKey,
            workoutStorageURL: workoutStore.storageURL
        )
    }

    deinit {
        pollTask?.cancel()
        flushTask?.cancel()
    }

    var pendingInvitationCount: Int { inbox?.invitations.count ?? 0 }

    var hasBlockingLiveWorkout: Bool {
        slotReservation.reservation != nil
            || sidecar.attachment != nil
            || !restoringRoomIDs.isEmpty
            || inbox?.rooms.contains(where: {
                [.waiting, .ready, .active].contains($0.status)
            }) == true
    }

    func isRestoring(roomID: String) -> Bool {
        restoringRoomIDs.contains(roomID)
    }

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

    var selfDisplayName: String? {
        snapshot?.currentParticipant?.profile.displayName
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
        restoringRoomIDs = []
        confirmedDraftConsumption = nil
    }

    func refreshAll(showErrors: Bool = true) async {
        guard !isRefreshing, !expectedUserID.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let context = try await gateway.currentContext(expectedUserID: expectedUserID)
            let sessionMismatchedAttachment: LiveWorkoutAttachment?
            do {
                try sidecar.bind(to: context)
                sessionMismatchedAttachment = nil
            } catch LiveWorkoutSidecarError.sessionMismatch {
                snapshot = nil
                sessionMismatchedAttachment = sidecar.attachment
            } catch LiveWorkoutSidecarError.accountMismatch {
                snapshot = nil
                // Preserve the unexpected envelope for recovery, but never use
                // its room identifier from another account as a network target.
                throw LiveWorkoutSidecarError.accountMismatch
            } catch {
                throw error
            }
            let sessionMismatchedReservation: LiveWorkoutSlotReservation?
            do {
                try slotReservation.bind(to: context)
                sessionMismatchedReservation = nil
            } catch LiveWorkoutSlotReservationError.sessionMismatch {
                snapshot = nil
                sessionMismatchedReservation = slotReservation.reservation
            } catch LiveWorkoutSlotReservationError.accountMismatch {
                snapshot = nil
                sessionMismatchedReservation = nil
            }
            var sessionMismatchedConsumption: LiveWorkoutDraftConsumption?
            do {
                try draftConsumptionStore.bind(to: context)
                sessionMismatchedConsumption = nil
                if let current = try draftConsumptionStore.current(context: context),
                   current.phase == .confirmed {
                    confirmedDraftConsumption = current
                }
            } catch LiveWorkoutDraftConsumptionError.sessionMismatch {
                confirmedDraftConsumption = nil
                sessionMismatchedConsumption = draftConsumptionStore.consumption
            } catch LiveWorkoutDraftConsumptionError.accountMismatch {
                confirmedDraftConsumption = nil
                throw LiveWorkoutDraftConsumptionError.accountMismatch
            }
            let freshInbox = try await gateway.inbox(expectedUserID: expectedUserID)
            try ensureCurrent(context)
            if let sessionMismatchedConsumption {
                try draftConsumptionStore.clearAfterSessionChange(
                    sessionMismatchedConsumption,
                    context: context
                )
            }
            if let sessionMismatchedReservation {
                try reconcileSessionMismatchedReservation(
                    sessionMismatchedReservation,
                    with: freshInbox,
                    context: context
                )
            }
            try promoteRoomBoundDraftConsumption(context: context)
            try reconcileSlotReservation(with: freshInbox, context: context)
            try reconcileDraftConsumption(with: freshInbox, context: context)
            inbox = freshInbox

            if let sessionMismatchedAttachment {
                try await reconcileSessionMismatchedAttachment(
                    sessionMismatchedAttachment,
                    with: freshInbox,
                    context: context
                )
            }

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
            let openRoomIDs = Set(freshInbox.rooms.map(\.roomID))
            restoringRoomIDs = restoringRoomIDs.filter { roomID in
                openRoomIDs.contains(roomID)
                    && (!isAttachedToCurrentDraft || sidecar.attachment?.roomID != roomID)
            }
            lastError = nil
            scheduleFlush()
        } catch is CancellationError {
            return
        } catch {
            if showErrors { lastError = gymSafeEnglishErrorMessage(error) }
        }
    }

    @discardableResult
    func sendInvite(
        to profileID: String,
        plan: SharedWorkoutPlan,
        draftRequest: LiveWorkoutDraftSendRequest? = nil
    ) async throws -> Bool {
        try beginMutation()
        defer { endMutation() }
        let context = try await gateway.currentContext(expectedUserID: expectedUserID)
        try sidecar.bind(to: context)
        try draftConsumptionStore.bind(to: context)
        if let draftRequest {
            guard draftRequest.recipientProfileID == profileID else {
                throw LiveWorkoutGatewayError.invalidRequest
            }
        }
        let canonical = try JSONSerialization.data(
            withJSONObject: LiveWorkoutPayloadParser.workoutObject(for: plan),
            options: [.sortedKeys]
        )
        let digest = canonical.base64EncodedString() + ":" + profileID
        let requestID = pendingInviteRequestIDs[digest] ?? UUID()
        pendingInviteRequestIDs[digest] = requestID
        let createdAt = Date()
        let reservation = LiveWorkoutSlotReservation(
            version: 1,
            userID: context.userID,
            sessionID: context.sessionID,
            role: .owner,
            operationID: requestID,
            roomID: nil,
            phase: .preparing,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(Self.invitationReservationDuration)
        )
        try slotReservation.reserve(reservation, context: context) {
            activeWorkoutStore.draft == nil
        }
        if let draftRequest {
            do {
                try draftConsumptionStore.prepare(
                    LiveWorkoutDraftConsumption(
                        version: 1,
                        userID: context.userID,
                        sessionID: context.sessionID,
                        operationID: requestID,
                        roomID: nil,
                        phase: .preparing,
                        recipientProfileID: draftRequest.recipientProfileID,
                        friendshipID: draftRequest.friendshipID,
                        friendshipRevision: draftRequest.friendshipRevision,
                        draftFingerprint: draftRequest.draftFingerprint,
                        createdAt: createdAt,
                        expiresAt: reservation.expiresAt
                    ),
                    context: context
                )
            } catch {
                try? slotReservation.clear(operationID: requestID, context: context)
                throw error
            }
        }
        let result: LiveWorkoutSendResult
        do {
            result = try await gateway.sendInvite(
                profileID: profileID,
                clientRequestID: requestID,
                plan: plan,
                expectedUserID: expectedUserID
            )
        } catch {
            await reconcileReservationAfterFailedMutation(
                context: context,
                preservePreparingOnNoRoom: draftRequest != nil
            )
            throw error
        }
        try ensureCurrent(context)
        if let roomID = result.roomID {
            try slotReservation.replace(
                operationID: requestID,
                with: LiveWorkoutSlotReservation(
                    version: 1,
                    userID: context.userID,
                    sessionID: context.sessionID,
                    role: .owner,
                    operationID: requestID,
                    roomID: roomID,
                    phase: .waiting,
                    createdAt: createdAt,
                    expiresAt: reservation.expiresAt
                ),
                context: context
            )
            if draftRequest != nil {
                confirmedDraftConsumption = try draftConsumptionStore.confirm(
                    operationID: requestID,
                    roomID: roomID,
                    context: context
                )
            }
        } else {
            try slotReservation.clear(operationID: requestID, context: context)
            if draftRequest != nil {
                try draftConsumptionStore.clear(
                    operationID: requestID,
                    context: context
                )
            }
        }
        pendingInviteRequestIDs.removeValue(forKey: digest)
        lastStatus = result.submitted
            ? "Live workout invitation sent. The plan is frozen for this room."
            : "Invitation submitted. The recipient may be unavailable."
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.refreshAll(showErrors: false)
        }
        return result.roomID != nil
    }

    func acknowledgeConfirmedDraftConsumption(
        _ consumption: LiveWorkoutDraftConsumption
    ) throws {
        guard confirmedDraftConsumption == consumption,
              consumption.phase == .confirmed,
              let roomID = consumption.roomID,
              let cloud = auth.session?.cloud,
              cloud.userID.lowercased() == consumption.userID,
              NativePushAuthSessionIdentity.sessionID(from: cloud) == consumption.sessionID,
              workoutStore.accountStorageKey == auth.session?.storageKey,
              activeWorkoutStore.accountStorageKey == workoutStore.accountStorageKey else {
            throw AuthServiceError.sessionChanged
        }
        let context = LiveWorkoutSessionContext(
            userID: consumption.userID,
            sessionID: consumption.sessionID,
            accessToken: cloud.accessToken
        )
        try draftConsumptionStore.clear(
            operationID: consumption.operationID,
            roomID: roomID,
            context: context
        )
        confirmedDraftConsumption = nil
    }

    func respond(
        to invitation: LiveWorkoutInvitation,
        accept: Bool
    ) async throws -> LiveWorkoutInvitationResponseOutcome {
        try beginMutation()
        defer { endMutation() }
        if accept, restoringRoomIDs.contains(invitation.roomID) {
            throw LiveWorkoutGatewayError.invalidRequest
        }
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
        let operationID = UUID()
        if accept {
            let createdAt = try LiveWorkoutPayloadParser.validatedDate(from: invitation.createdAt)
            let expiresAt = try LiveWorkoutPayloadParser.validatedDate(from: invitation.inviteExpiresAt)
            try slotReservation.reserve(
                LiveWorkoutSlotReservation(
                    version: 1,
                    userID: context.userID,
                    sessionID: context.sessionID,
                    role: .participant,
                    operationID: operationID,
                    roomID: invitation.roomID,
                    phase: .waiting,
                    createdAt: createdAt,
                    expiresAt: expiresAt
                ),
                context: context
            ) { activeWorkoutStore.draft == nil }
        }
        let result: LiveWorkoutRespondResult
        do {
            result = try await gateway.respondInvite(
                roomID: invitation.roomID,
                decision: accept ? "accept" : "decline",
                expectedRoomRevision: invitation.roomRevision,
                clientOperationID: operationID,
                expectedUserID: expectedUserID
            )
        } catch {
            if accept { await reconcileReservationAfterFailedMutation(context: context) }
            throw error
        }
        try ensureCurrent(context)
        guard accept ? result.result == "joined" : result.result == "declined" else {
            throw LiveWorkoutGatewayError.invalidResponse
        }
        if accept {
            guard result.roomID == invitation.roomID,
                  [.ready, .active].contains(result.status),
                  result.roomRevision >= invitation.roomRevision else {
                throw LiveWorkoutGatewayError.invalidResponse
            }
            do {
                try await refreshSnapshot(
                    roomID: invitation.roomID,
                    context: context,
                    materializeWhenActive: true
                )
                try ensureCurrent(context)
                guard snapshot?.room.roomID == invitation.roomID,
                      snapshot?.room.status == .active,
                      isAttachedToCurrentDraft else {
                    throw LiveWorkoutGatewayError.invalidResponse
                }
                restoringRoomIDs.remove(invitation.roomID)
                lastStatus = "Live workout started."
                inbox = try? await gateway.inbox(expectedUserID: expectedUserID)
                scheduleFlush()
                return .active
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try ensureCurrent(context)
                restoringRoomIDs.insert(invitation.roomID)
                lastError = nil
                lastStatus = "Acceptance was confirmed. Restoring the started workout…"
                Task { @MainActor [weak self] in
                    await self?.refreshAll(showErrors: false)
                }
                return .confirmedRestoring
            }
        } else {
            lastStatus = "Live workout invitation declined."
            await refreshAll(showErrors: true)
            return .declined
        }
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
        if let reservation = try slotReservation.current(context: context),
           reservation.roomID == room.roomID {
            try slotReservation.clear(
                operationID: reservation.operationID,
                roomID: room.roomID,
                context: context
            )
        }
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
        if let reservation = try slotReservation.current(context: context),
           reservation.roomID == room.roomID {
            try slotReservation.clear(
                operationID: reservation.operationID,
                roomID: room.roomID,
                context: context
            )
        }
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

    func receiveSocialInvalidation() async {
        guard auth.session?.cloud?.userID == expectedUserID else { return }
        // The opaque Broadcast carries no state. Friends performs its own
        // account-bound authenticated refetch; live remains untouched.
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
            try ensureSlotReservation(for: fresh, context: context)
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
            if let reservation = try slotReservation.current(context: context),
               reservation.roomID == fresh.room.roomID {
                try slotReservation.clear(
                    operationID: reservation.operationID,
                    roomID: fresh.room.roomID,
                    context: context
                )
            }
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
                reservationContext: context,
                roomID: snapshot.room.roomID,
                persistBindingBeforeCommit: { candidate in
                    _ = try self.sidecar.attach(
                        snapshot: snapshot,
                        draft: candidate,
                        context: context
                    )
                }
            )
            if let reservation = try slotReservation.current(context: context),
               reservation.roomID == snapshot.room.roomID {
                try slotReservation.clear(
                    operationID: reservation.operationID,
                    roomID: snapshot.room.roomID,
                    context: context
                )
            }
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

    private func reconcileReservationAfterFailedMutation(
        context: LiveWorkoutSessionContext,
        preservePreparingOnNoRoom: Bool = false
    ) async {
        guard auth.session?.cloud?.userID == expectedUserID else { return }
        do {
            let freshInbox = try await gateway.inbox(expectedUserID: expectedUserID)
            try ensureCurrent(context)
            try promoteRoomBoundDraftConsumption(context: context)
            try reconcileSlotReservation(
                with: freshInbox,
                context: context,
                ignoreInFlight: !preservePreparingOnNoRoom
            )
            try reconcileDraftConsumption(
                with: freshInbox,
                context: context,
                ignoreInFlight: !preservePreparingOnNoRoom
            )
        } catch {
            // An unknown RPC outcome keeps the durable reservation fail-closed until
            // a later authenticated inbox can prove whether it should be bound or released.
        }
    }

    private func promoteRoomBoundDraftConsumption(
        context: LiveWorkoutSessionContext
    ) throws {
        guard let current = try draftConsumptionStore.current(context: context) else {
            confirmedDraftConsumption = nil
            return
        }
        if current.phase == .confirmed {
            confirmedDraftConsumption = current
            return
        }
        guard let reservation = try slotReservation.current(context: context),
              reservation.operationID == current.operationID,
              reservation.role == .owner,
              let roomID = reservation.roomID else { return }
        confirmedDraftConsumption = try draftConsumptionStore.confirm(
            operationID: current.operationID,
            roomID: roomID,
            context: context
        )
    }

    private func reconcileDraftConsumption(
        with freshInbox: LiveWorkoutInbox,
        context: LiveWorkoutSessionContext,
        ignoreInFlight: Bool = false
    ) throws {
        guard let current = try draftConsumptionStore.current(context: context) else {
            confirmedDraftConsumption = nil
            return
        }
        if current.phase == .confirmed {
            confirmedDraftConsumption = current
            return
        }
        if let reservation = try slotReservation.current(context: context),
           reservation.operationID == current.operationID,
           reservation.role == .owner {
            if let roomID = reservation.roomID,
               freshInbox.rooms.contains(where: {
                   $0.roomID == roomID
                       && $0.role == .owner
                       && [.waiting, .ready, .active].contains($0.status)
                       && [.joined, .finished].contains($0.memberState)
                       && $0.peer.profileID == current.recipientProfileID
               }) {
                confirmedDraftConsumption = try draftConsumptionStore.confirm(
                    operationID: current.operationID,
                    roomID: roomID,
                    context: context
                )
                return
            }
            if !ignoreInFlight && isMutating { return }
        }
        guard ignoreInFlight || !isMutating else { return }
        try draftConsumptionStore.clear(
            operationID: current.operationID,
            context: context
        )
        confirmedDraftConsumption = nil
    }

    private func reconcileSlotReservation(
        with freshInbox: LiveWorkoutInbox,
        context: LiveWorkoutSessionContext,
        ignoreInFlight: Bool = false
    ) throws {
        let current = try slotReservation.current(context: context)
        let openRooms = freshInbox.rooms.filter {
            [.waiting, .ready, .active].contains($0.status) &&
                [.joined, .finished].contains($0.memberState)
        }

        guard let current else {
            // A current authenticated inbox can recover a crash that happened after the
            // server mutation but before the local reservation was rebound to its room.
            guard openRooms.count == 1, let room = openRooms.first,
                  activeWorkoutStore.draft == nil else { return }
            let createdAt = try LiveWorkoutPayloadParser.validatedDate(from: room.createdAt)
            let expiresAt = try room.activeExpiresAt.map {
                try LiveWorkoutPayloadParser.validatedDate(from: $0)
            } ?? createdAt.addingTimeInterval(Self.invitationReservationDuration)
            try slotReservation.reserve(
                LiveWorkoutSlotReservation(
                    version: 1,
                    userID: context.userID,
                    sessionID: context.sessionID,
                    role: room.role,
                    operationID: UUID(),
                    roomID: room.roomID,
                    phase: room.status == .active ? .active : .waiting,
                    createdAt: createdAt,
                    expiresAt: expiresAt
                ),
                context: context
            ) { activeWorkoutStore.draft == nil }
            return
        }

        if current.phase == .preparing {
            let pendingConsumption = try draftConsumptionStore.current(context: context)
            let ownerRooms = openRooms.filter { room in
                guard room.role == .owner else { return false }
                guard pendingConsumption?.operationID == current.operationID else {
                    return true
                }
                return room.peer.profileID == pendingConsumption?.recipientProfileID
            }
            if ownerRooms.count == 1, let room = ownerRooms.first {
                let expiresAt = try room.activeExpiresAt.map {
                    try LiveWorkoutPayloadParser.validatedDate(from: $0)
                } ?? current.expiresAt
                try slotReservation.replace(
                    operationID: current.operationID,
                    with: LiveWorkoutSlotReservation(
                        version: 1,
                        userID: current.userID,
                        sessionID: current.sessionID,
                        role: current.role,
                        operationID: current.operationID,
                        roomID: room.roomID,
                        phase: room.status == .active ? .active : .waiting,
                        createdAt: current.createdAt,
                        expiresAt: expiresAt
                    ),
                    context: context
                )
            } else if ignoreInFlight || !isMutating {
                try slotReservation.clear(
                    operationID: current.operationID,
                    context: context
                )
            }
            return
        }

        guard let currentRoomID = current.roomID else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        guard let room = openRooms.first(where: { $0.roomID == currentRoomID }) else {
            let invitationStillWaiting = freshInbox.invitations.contains {
                $0.roomID == currentRoomID
            }
            let responseInFlight = !ignoreInFlight && isMutating &&
                current.role == .participant
            if !invitationStillWaiting && !responseInFlight ||
                invitationStillWaiting && current.role == .participant &&
                    (ignoreInFlight || !responseInFlight) {
                try slotReservation.clear(
                    operationID: current.operationID,
                    roomID: currentRoomID,
                    context: context
                )
            }
            return
        }

        let nextPhase: LiveWorkoutSlotPhase = room.status == .active ? .active : .waiting
        let nextExpiry = try room.activeExpiresAt.map {
            try LiveWorkoutPayloadParser.validatedDate(from: $0)
        } ?? current.expiresAt
        if current.phase != nextPhase || current.expiresAt != nextExpiry {
            try slotReservation.replace(
                operationID: current.operationID,
                with: LiveWorkoutSlotReservation(
                    version: current.version,
                    userID: current.userID,
                    sessionID: current.sessionID,
                    role: current.role,
                    operationID: current.operationID,
                    roomID: currentRoomID,
                    phase: nextPhase,
                    createdAt: current.createdAt,
                    expiresAt: nextExpiry
                ),
                context: context
            )
        }
    }

    private func reconcileSessionMismatchedReservation(
        _ previous: LiveWorkoutSlotReservation,
        with freshInbox: LiveWorkoutInbox,
        context: LiveWorkoutSessionContext
    ) throws {
        guard previous.userID == context.userID,
              previous.sessionID != context.sessionID else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        let openRooms = freshInbox.rooms.filter {
            [.waiting, .ready, .active].contains($0.status) &&
                [.joined, .finished].contains($0.memberState)
        }
        let room: LiveWorkoutOpenRoom?
        if previous.phase == .preparing {
            let ownerRooms = openRooms.filter { $0.role == .owner }
            guard ownerRooms.count <= 1 else {
                throw LiveWorkoutSlotReservationError.slotReserved
            }
            room = ownerRooms.first
        } else {
            room = openRooms.first { $0.roomID == previous.roomID }
        }
        if let room {
            guard activeWorkoutStore.draft == nil else {
                throw LiveWorkoutSlotReservationError.slotReserved
            }
            let expiry = try room.activeExpiresAt.map {
                try LiveWorkoutPayloadParser.validatedDate(from: $0)
            } ?? previous.expiresAt
            try slotReservation.reconcileAfterSessionChange(
                expectedOperationID: previous.operationID,
                with: LiveWorkoutSlotReservation(
                    version: previous.version,
                    userID: previous.userID,
                    sessionID: context.sessionID,
                    role: room.role,
                    operationID: previous.operationID,
                    roomID: room.roomID,
                    phase: room.status == .active ? .active : .waiting,
                    createdAt: previous.createdAt,
                    expiresAt: expiry
                ),
                context: context
            )
            return
        }
        try slotReservation.reconcileAfterSessionChange(
            expectedOperationID: previous.operationID,
            with: nil,
            context: context
        )
    }

    private func reconcileSessionMismatchedAttachment(
        _ previous: LiveWorkoutAttachment,
        with freshInbox: LiveWorkoutInbox,
        context: LiveWorkoutSessionContext
    ) async throws {
        guard previous.userID == context.userID,
              previous.sessionID != context.sessionID else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        guard freshInbox.rooms.contains(where: {
            $0.roomID == previous.roomID
                && $0.status == .active
                && [.joined, .finished].contains($0.memberState)
        }) else {
            // A successful, account-fenced inbox is authoritative evidence that
            // the old session's room can no longer accept queued mutations. Keep
            // the local draft, but release only the stale collaboration sidecar.
            try sidecar.clear()
            snapshot = nil
            lastStatus = "The previous live room is no longer active. Your local workout remains on this iPhone."
            return
        }
        let fresh = try await gateway.snapshot(
            roomID: previous.roomID,
            expectedUserID: expectedUserID
        )
        try ensureCurrent(context)
        if let draft = activeWorkoutStore.draft,
           draft.id == previous.localDraftID {
            try sidecar.reconcileAfterSessionChange(
                snapshot: fresh,
                draft: draft,
                context: context
            )
        } else if let committed = workoutStore.workout(id: previous.localDraftID) {
            try sidecar.reconcileAfterSessionChange(
                snapshot: fresh,
                committedWorkout: committed,
                context: context
            )
        } else {
            throw LiveWorkoutSidecarError.sessionMismatch
        }
        snapshot = fresh
        lastStatus = "Live workout restored after sign-in. Queued updates will continue syncing."
    }

    private func ensureSlotReservation(
        for fresh: LiveWorkoutSnapshot,
        context: LiveWorkoutSessionContext
    ) throws {
        guard fresh.room.status == .active,
              let participant = fresh.currentParticipant,
              participant.state == .joined,
              let activeExpiresAtText = fresh.room.activeExpiresAt else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        let roomID = fresh.room.roomID
        let current = try slotReservation.current(context: context)
        if sidecar.attachment?.roomID == roomID, activeWorkoutStore.draft != nil {
            if let current, current.roomID == roomID {
                try slotReservation.clear(
                    operationID: current.operationID,
                    roomID: roomID,
                    context: context
                )
            }
            return
        }

        let createdAt = try LiveWorkoutPayloadParser.validatedDate(from: fresh.room.createdAt)
        let activeExpiresAt = try LiveWorkoutPayloadParser.validatedDate(from: activeExpiresAtText)
        if let current {
            guard current.roomID == roomID else {
                throw LiveWorkoutSlotReservationError.slotReserved
            }
            if current.phase != .active || current.expiresAt != activeExpiresAt {
                try slotReservation.replace(
                    operationID: current.operationID,
                    with: LiveWorkoutSlotReservation(
                        version: current.version,
                        userID: current.userID,
                        sessionID: current.sessionID,
                        role: current.role,
                        operationID: current.operationID,
                        roomID: roomID,
                        phase: .active,
                        createdAt: current.createdAt,
                        expiresAt: activeExpiresAt
                    ),
                    context: context
                )
            }
        } else {
            try slotReservation.reserve(
                LiveWorkoutSlotReservation(
                    version: 1,
                    userID: context.userID,
                    sessionID: context.sessionID,
                    role: participant.role,
                    operationID: UUID(),
                    roomID: roomID,
                    phase: .active,
                    createdAt: createdAt,
                    expiresAt: activeExpiresAt
                ),
                context: context
            ) { activeWorkoutStore.draft == nil }
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
        guard let cloud = auth.session?.cloud,
              cloud.userID == expectedUserID,
              NativePushAuthSessionIdentity.sessionID(from: cloud) == context.sessionID,
              context.userID == expectedUserID,
              workoutStore.accountStorageKey == auth.session?.storageKey,
              activeWorkoutStore.accountStorageKey == workoutStore.accountStorageKey else {
            throw AuthServiceError.sessionChanged
        }
    }

    private static let invitationReservationDuration: TimeInterval = 7 * 24 * 60 * 60
}
