import Combine
import CryptoKit
import Foundation

func leaderboardHiddenProfilesDefaultsKey(for accountStorageKey: String) -> String {
    "leaderboard-hidden-profile-ids.\(accountStorageKey)"
}

struct PendingSharedWorkout: Identifiable, Equatable, Sendable {
    let id: UUID
    let plan: SharedWorkoutPlan

    init(id: UUID = UUID(), plan: SharedWorkoutPlan) {
        self.id = id
        self.plan = plan
    }
}

@MainActor
final class AppState: ObservableObject {
    enum CloudSyncPresentationStatus: Equatable {
        case idle
        case checking
        case pending
        case syncing
        case synced(Date)
        case conflict
        case failed(String)
    }

    struct CloudSyncConflictSummary: Equatable {
        let localWorkoutCount: Int
        let cloudWorkoutCount: Int
    }

    private enum CloudSavePhase {
        case idle
        case debouncing
        case uploading
    }

    struct CloudWorkoutIdentity: Hashable {
        /// Catalog position is not semantic. Sorting preserves duplicate multiplicity while
        /// avoiding dictionary overwrite behavior for attacker-controlled backup entries.
        let configuredExercises: [BackupExercise]
        let sessions: [BackupSession]
        fileprivate let exactWire: Data

        init(
            configuredExercises: [BackupExercise],
            sessions: [BackupSession],
            exactWire: Data
        ) {
            self.configuredExercises = configuredExercises
            self.sessions = sessions
            self.exactWire = exactWire
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.exactWire == rhs.exactWire
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(exactWire)
        }
    }

    private struct CloudWorkoutExactWire: Encodable {
        let configuredExercises: [BackupExercise]
        let sessions: [BackupSession]
    }

    private struct PendingCloudSyncConflict {
        let generation: UInt64
        let storageKey: String
        let userID: String
        let owner: BackupOwner
        let localStore: WorkoutStore
        let localIdentity: CloudWorkoutIdentity
        let remoteIdentity: CloudWorkoutIdentity
    }

    private struct PendingWorkoutInviteRequestKey: Hashable {
        let generation: UInt64
        let storageKey: String
        let userID: String
        let profileID: String
        let canonicalWorkout: Data
    }

    let auth: AuthService
    let restTimers: RestTimerManager
    let cloudSync: CloudSyncService
    let garminCloud: GarminCloudService
    let garminPhoneSync: GarminPhoneSyncService

    @Published private(set) var workoutStore: WorkoutStore
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published private(set) var isPreparingAccount = false
    @Published private(set) var activeAccountStorageKey: String?
    @Published private(set) var accountPreparationError: String?
    @Published private(set) var isSigningOut = false
    @Published private(set) var cloudSyncConflict: CloudSyncConflictSummary?
    @Published private(set) var isResolvingCloudSyncConflict = false
    @Published private(set) var cloudSyncStatus: CloudSyncPresentationStatus = .idle
    @Published private(set) var pendingSharedWorkout: PendingSharedWorkout?
    @Published private(set) var socialDashboard: SocialDashboard?
    @Published private(set) var socialWorkoutInbox: SocialWorkoutInbox?
    @Published private(set) var socialDashboardRefreshRevision: UInt64 = 0

    private var sessionSubscription: AnyCancellable?
    private var storeSubscription: AnyCancellable?
    private var pendingCloudSave: Task<Void, Never>?
    private var cloudSavePhase = CloudSavePhase.idle
    private var cloudSaveQueued = false
    private var cloudSaveGeneration: UInt64 = 0
    private var accountActivationTask: Task<Void, Never>?
    private var accountActivationGeneration: UInt64 = 0
    private var accountDeletionTask: Task<Void, Error>?
    private var accountDeletionTarget: AccountDeletionTarget?
    private var accountDeletionGeneration: UInt64 = 0
    private var restTimerOwnerFingerprint: String?
    private var applyingRemoteState = false
    private var cloudWritableAccountStorageKey: String?
    private var pendingCloudSyncConflict: PendingCloudSyncConflict?
    private var socialCacheGeneration: UInt64 = 0
    private var pendingWorkoutInviteRequestIDs: [PendingWorkoutInviteRequestKey: UUID] = [:]
    private let defaults: UserDefaults
    private let workoutDirectoryURL: URL?
    private let remoteStateLoader: (@MainActor (String) async throws -> Data?)?

    private static let pendingDeletionStorageKey = "gymapp.pending-account-deletion-storage-key"
    private static let legacyPendingDeletionGarminUserIDKey =
        "gymapp.pending-account-deletion-garmin-user-id"
    private static let trainingProfileKeyPrefix = "gymapp.training-profile.v1."
    private static let hiddenLeaderboardProfilesKey = "leaderboard-hidden-profile-ids"
    private static let cloudCheckpointKeyPrefix = "gymapp.cloud-sync-checkpoint.v1."
    static let maximumPendingWorkoutInviteRequests = 25

    private struct CloudSyncCheckpoint: Codable {
        let version: Int
        var baselineDigest: Data?
        var dirty: Bool
        var pending: Bool
        var lastSuccessfulAt: Date?

        static let empty = CloudSyncCheckpoint(
            version: 1,
            baselineDigest: nil,
            dirty: false,
            pending: false,
            lastSuccessfulAt: nil
        )
    }

    private struct AccountDeletionTarget: Equatable {
        let storageKey: String
        let cloudUserID: String?
    }

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        workoutDirectoryURL: URL? = nil,
        cloudURLSession: URLSession = .shared,
        remoteStateLoader: (@MainActor (String) async throws -> Data?)? = nil,
        garminBindingStore: GarminDeviceBindingStore = GarminDeviceBindingStore(),
        restTimers: RestTimerManager? = nil
    ) throws {
        self.auth = auth
        self.defaults = defaults
        self.workoutDirectoryURL = workoutDirectoryURL
        self.remoteStateLoader = remoteStateLoader

        let hadPendingDeletion = defaults.string(forKey: Self.pendingDeletionStorageKey) != nil
        Self.finishPendingDeletionCleanupIfNeeded(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: workoutDirectoryURL,
            garminBindingStore: garminBindingStore
        )

        self.restTimers = restTimers ?? RestTimerManager()
        let initialRestTimerOwnerFingerprint = auth.session.map {
            RestTimerManager.ownerFingerprint(for: $0.storageKey)
        }
        self.restTimerOwnerFingerprint = initialRestTimerOwnerFingerprint
        self.cloudSync = CloudSyncService(auth: auth, urlSession: cloudURLSession)
        self.garminCloud = GarminCloudService(
            auth: auth,
            urlSession: cloudURLSession,
            bindingStore: garminBindingStore
        )
        self.garminPhoneSync = GarminPhoneSyncService(
            auth: auth,
            defaults: defaults
        )
        let openedStore = try WorkoutStore.openRecoveringCorruptStore(
            accountStorageKey: "signed-out",
            directoryURL: workoutDirectoryURL
        )
        self.workoutStore = openedStore.store
        self.garminPhoneSync.bind(workoutStore: openedStore.store)
        self.restTimers.bindToAccount(
            ownerFingerprint: initialRestTimerOwnerFingerprint,
            discardPersistedState: hadPendingDeletion
        )
        observeStore()

        if openedStore.quarantinedFileURL != nil {
            statusMessage = gymText(
                "A damaged local data file was preserved for recovery. Cloud data will restore after sign-in; offline profiles should contact support before deleting the app.",
                "Пошкоджений локальний файл збережено для відновлення. Хмарні дані відновляться після входу; для офлайн-профілю звернися до підтримки перед видаленням застосунку.",
                languageCode: defaults.string(forKey: "app-language") ?? AppLanguage.english.rawValue
            )
            statusIsError = true
        }

        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                self?.scheduleActivation(session)
            }
    }

    deinit {
        pendingCloudSave?.cancel()
        accountActivationTask?.cancel()
        accountDeletionTask?.cancel()
    }

    var isAccountReady: Bool {
        guard let expectedKey = auth.session?.storageKey else { return false }
        return !isPreparingAccount &&
            activeAccountStorageKey == expectedKey &&
            workoutStore.accountStorageKey == expectedKey
    }

    /// Unknown future core fields remain read-only. Shared PWA extension namespaces are
    /// validated, stored account-locally, and carried through iOS cloud writes.
    var isCloudWritePaused: Bool {
        guard isAccountReady, auth.session?.cloud != nil else { return false }
        return cloudWritableAccountStorageKey != activeAccountStorageKey
    }

    var backupOwner: BackupOwner {
        Self.backupOwner(for: auth.session, fallbackStorageKey: workoutStore.accountStorageKey)
    }

    /// Consumes only GymApp's exact shared-workout destinations. Recognized malformed
    /// links fail closed and never fall through into Garmin or authentication handlers.
    func handleSharedWorkoutURL(_ url: URL) -> Bool {
        guard SharedWorkoutLinkDecoder.isRecognizedDestination(url) else { return false }
        do {
            let plan = try SharedWorkoutLinkDecoder.decode(url)
            do {
                try stageSharedWorkoutPlan(plan)
            } catch {
                show(
                    message: gymText(
                        "Finish or close the current shared workout preview before opening another link.",
                        "Заверши або закрий поточний перегляд спільного тренування, перш ніж відкривати інше посилання.",
                        "Заверши или закрой текущий просмотр общей тренировки, прежде чем открывать другую ссылку.",
                        languageCode: defaults.string(forKey: "app-language") ?? AppLanguage.english.rawValue
                    ),
                    isError: true
                )
            }
        } catch {
            show(
                message: gymText(
                    "This shared workout link is invalid or no longer supported.",
                    "Це посилання на спільне тренування недійсне або більше не підтримується.",
                    "Эта ссылка на общую тренировку недействительна или больше не поддерживается.",
                    languageCode: defaults.string(forKey: "app-language") ?? AppLanguage.english.rawValue
                ),
                isError: true
            )
        }
        return true
    }

    func dismissPendingSharedWorkout(id: UUID) {
        guard pendingSharedWorkout?.id == id else { return }
        pendingSharedWorkout = nil
    }

    func stageSharedWorkoutPlan(
        _ plan: SharedWorkoutPlan,
        replacingPendingID: UUID? = nil
    ) throws {
        let validated = try SharedWorkoutLinkValidator.validate(plan)
        if let pendingSharedWorkout {
            if pendingSharedWorkout.plan == validated { return }
            guard replacingPendingID == pendingSharedWorkout.id else {
                throw CloudSyncError.invalidWorkoutInvite
            }
        }
        pendingSharedWorkout = PendingSharedWorkout(plan: validated)
    }

    private static func backupOwner(
        for session: AppAccountSession?,
        fallbackStorageKey: String
    ) -> BackupOwner {
        switch session {
        case .cloud(let cloud):
            return BackupOwner(
                // Keep the device-local `cloud_<uuid>` storage namespace out of the shared
                // envelope. Android and PWA use the authenticated Supabase UUID here.
                accountID: cloud.userID,
                userID: cloud.userID,
                email: cloud.email,
                remote: true
            )
        case .local:
            return BackupOwner(accountID: session?.storageKey, remote: false)
        case nil:
            return BackupOwner(accountID: fallbackStorageKey, remote: false)
        }
    }

    func activate(_ session: AppAccountSession?) async {
        accountActivationTask?.cancel()
        accountActivationTask = nil
        let generation = beginAccountTransition(session)
        await prepareAccount(session, generation: generation)
    }

    func retryAccountActivation() {
        scheduleActivation(auth.session)
    }

    func cloudSyncConflictBackupData() throws -> Data {
        guard let pending = pendingCloudSyncConflict,
              pending.generation == accountActivationGeneration,
              auth.session?.storageKey == pending.storageKey,
              auth.session?.cloud?.userID == pending.userID else {
            throw AuthServiceError.sessionChanged
        }
        return try pending.localStore.exportBackupData(owner: pending.owner)
    }

    func resolveCloudSyncConflict(useCloudVersion: Bool) {
        guard !isResolvingCloudSyncConflict,
              let pending = pendingCloudSyncConflict else { return }
        isResolvingCloudSyncConflict = true
        accountPreparationError = nil
        Task { [weak self] in
            await self?.resolveCloudSyncConflict(
                pending,
                useCloudVersion: useCloudVersion
            )
        }
    }

    @discardableResult
    func signOut() async -> Bool {
        guard !isSigningOut else { return false }
        isSigningOut = true
        var shouldRescheduleCloudSave = false
        defer {
            isSigningOut = false
            if shouldRescheduleCloudSave {
                scheduleCloudSave()
            }
        }

        if isAccountReady,
           let session = auth.session,
           let cloud = session.cloud,
           cloudWritableAccountStorageKey == session.storageKey {
            let scheduledSave = pendingCloudSave
            // Cancelling a PATCH after it reaches the server leaves its outcome
            // unknown and our CAS revision stale. Only cancel the debounce sleep;
            // an upload that already started must finish before the final flush.
            if cloudSavePhase == .debouncing {
                scheduledSave?.cancel()
            }
            await scheduledSave?.value

            let store = workoutStore
            let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
            do {
                try await cloudSync.withSyncIndicator {
                    // UI interaction is frozen while signing out, and the snapshot
                    // check also catches any programmatic mutation during the await.
                    // Do not clear the session until the uploaded snapshot is stable.
                    for attempt in 1 ... 3 {
                        let uploadedSnapshot = store.snapshot
                        try store.saveNow()
                        try await self.uploadCurrentState(
                            from: store,
                            owner: owner,
                            expectedStorageKey: session.storageKey,
                            expectedUserID: cloud.userID
                        )
                        guard self.workoutStore === store,
                              self.auth.session?.storageKey == session.storageKey else {
                            throw AuthServiceError.sessionChanged
                        }
                        if store.snapshot == uploadedSnapshot { break }
                        if attempt == 3 {
                            throw CloudSyncError.requestFailed(
                                "Workout data kept changing during sign-out. Try again."
                            )
                        }
                    }
                }
            } catch {
                // Keep the authenticated account and writable store intact. The user
                // can retry sign-out after connectivity or cloud state is repaired.
                shouldRescheduleCloudSave = isAccountReady
                    && auth.session?.storageKey == session.storageKey
                    && workoutStore === store
                    && cloudWritableAccountStorageKey == session.storageKey
                show(error: error)
                return false
            }
        }
        clearRestTimersForAccountTransition(to: nil)
        await auth.signOut()
        return auth.session == nil
    }

    private func scheduleActivation(_ session: AppAccountSession?) {
        accountActivationTask?.cancel()
        let generation = beginAccountTransition(session)
        accountActivationTask = Task { [weak self] in
            await self?.prepareAccount(session, generation: generation)
        }
    }

    private func beginAccountTransition(_ session: AppAccountSession?) -> UInt64 {
        let nextOwnerFingerprint = session.map {
            RestTimerManager.ownerFingerprint(for: $0.storageKey)
        }
        if restTimerOwnerFingerprint != nextOwnerFingerprint {
            clearRestTimersForAccountTransition(to: nextOwnerFingerprint)
        }
        accountActivationGeneration &+= 1
        abandonPendingCloudSave()
        cloudSync.resetForAccountTransition()
        socialDashboard = nil
        socialWorkoutInbox = nil
        socialCacheGeneration &+= 1
        socialDashboardRefreshRevision &+= 1
        pendingWorkoutInviteRequestIDs.removeAll(keepingCapacity: false)
        pendingSharedWorkout = nil
        cloudWritableAccountStorageKey = nil
        pendingCloudSyncConflict = nil
        cloudSyncConflict = nil
        isResolvingCloudSyncConflict = false
        cloudSyncStatus = session?.cloud == nil ? .idle : .checking
        activeAccountStorageKey = nil
        accountPreparationError = nil
        isPreparingAccount = session != nil
        return accountActivationGeneration
    }

    private func clearRestTimersForAccountTransition(to ownerFingerprint: String?) {
        restTimers.bindToAccount(ownerFingerprint: ownerFingerprint)
        restTimerOwnerFingerprint = ownerFingerprint
    }

    private func prepareAccount(
        _ session: AppAccountSession?,
        generation: UInt64
    ) async {
        applyingRemoteState = true
        defer {
            applyingRemoteState = false
        }

        guard let session else {
            do {
                let signedOut = try WorkoutStore.openRecoveringCorruptStore(
                    accountStorageKey: "signed-out",
                    directoryURL: workoutDirectoryURL
                ).store
                try ensureActivationIsCurrent(generation: generation, expectedStorageKey: nil)
                publish(store: signedOut, activeStorageKey: nil)
                isPreparingAccount = false
            } catch is CancellationError {
                return
            } catch {
                guard accountActivationGeneration == generation, auth.session == nil else { return }
                accountPreparationError = gymErrorMessage(error)
                isPreparingAccount = false
                show(error: error)
            }
            return
        }

        let expectedStorageKey = session.storageKey
        let expectedOwner = Self.backupOwner(
            for: session,
            fallbackStorageKey: expectedStorageKey
        )
        let expectedUserID = session.cloud?.userID

        do {
            let openedStore = try WorkoutStore.openRecoveringCorruptStore(
                accountStorageKey: expectedStorageKey,
                directoryURL: workoutDirectoryURL
            )
            let candidate = openedStore.store
            try ensureActivationIsCurrent(
                generation: generation,
                expectedStorageKey: expectedStorageKey
            )
            let persistedCatalogSeedVersion = candidate.catalogSeedVersion
            var seededExerciseCount = try candidate.seedBuiltInExercises()
            _ = try candidate.seedDefaultMuscleMappings()

            var cloudError: Error?
            var cloudWritesAllowed = false
            var loadedReadOnlyUnsupportedState = false
            var requiresCanonicalCloudUpload = false
            if let expectedUserID {
                let remoteData: Data?
                do {
                    if let remoteStateLoader {
                        remoteData = try await remoteStateLoader(expectedUserID)
                    } else {
                        remoteData = try await cloudSync.withSyncIndicator({
                            try await self.cloudSync.loadRemoteState(expectedUserID: expectedUserID)
                        })
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // Do not publish an editable account from an unverified local snapshot when
                    // the authoritative cloud read itself failed. The retry screen must reload
                    // the current remote revision before this account can become active.
                    throw error
                }

                if let remoteData {
                    do {
                        try ensureActivationIsCurrent(
                            generation: generation,
                            expectedStorageKey: expectedStorageKey
                        )
                        let preparedBackup = try WorkoutStore.prepareCloudBackup(
                            remoteData,
                            activeOwner: expectedOwner,
                            localCatalogSeedVersion: persistedCatalogSeedVersion
                        )
                        let localBackup = try candidate.makeBackup(owner: expectedOwner)
                        let remoteBackup = try JSONDecoder().decode(
                            GymBackup.self,
                            from: preparedBackup.data
                        )
                        let localIdentity = try Self.cloudWorkoutIdentity(localBackup)
                        let remoteIdentity = try Self.cloudWorkoutIdentity(remoteBackup)
                        let persistedCheckpoint = cloudCheckpoint(for: expectedStorageKey)
                        let baselineDigest = persistedCheckpoint.baselineDigest
                        let localMatchesBaseline = baselineDigest ==
                            Self.cloudIdentityDigest(localIdentity)
                        let remoteMatchesBaseline = baselineDigest ==
                            Self.cloudIdentityDigest(remoteIdentity)
                        let historiesDiffer = localIdentity != remoteIdentity
                        let keepLocalThreeWay = preparedBackup.roundTripSafe &&
                            Self.hasUserWorkoutData(localIdentity) && historiesDiffer &&
                            remoteMatchesBaseline && !localMatchesBaseline
                        if preparedBackup.roundTripSafe,
                           Self.hasUserWorkoutData(localIdentity),
                           historiesDiffer,
                           !localMatchesBaseline,
                           !remoteMatchesBaseline {
                            try candidate.setCloudExtensionsData(
                                preparedBackup.extensionsData
                            )
                            pendingCloudSyncConflict = PendingCloudSyncConflict(
                                generation: generation,
                                storageKey: expectedStorageKey,
                                userID: expectedUserID,
                                owner: expectedOwner,
                                localStore: candidate,
                                localIdentity: localIdentity,
                                remoteIdentity: remoteIdentity
                            )
                            cloudSyncConflict = CloudSyncConflictSummary(
                                localWorkoutCount: localBackup.sessions.count,
                                cloudWorkoutCount: remoteBackup.sessions.count
                            )
                            cloudSyncStatus = .conflict
                            isPreparingAccount = false
                            accountPreparationError = nil
                            return
                        }
                        if keepLocalThreeWay {
                            try candidate.setCloudExtensionsData(
                                preparedBackup.extensionsData
                            )
                            recordCloudBaseline(
                                remoteIdentity,
                                storageKey: expectedStorageKey,
                                clean: false,
                                successfulAt: nil
                            )
                        } else {
                            _ = try candidate.restoreBackup(
                                data: preparedBackup.data,
                                activeOwner: expectedOwner
                            )
                            if preparedBackup.roundTripSafe {
                                try candidate.setCloudExtensionsData(
                                    preparedBackup.extensionsData
                                )
                                recordCloudBaseline(
                                    remoteIdentity,
                                    storageKey: expectedStorageKey,
                                    clean: !persistedCheckpoint.pending
                                )
                            }
                        }
                        cloudWritesAllowed = preparedBackup.roundTripSafe
                        loadedReadOnlyUnsupportedState = !preparedBackup.roundTripSafe
                        requiresCanonicalCloudUpload = preparedBackup.roundTripSafe &&
                            (preparedBackup.requiresCanonicalUpload || keepLocalThreeWay ||
                                persistedCheckpoint.pending)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard accountActivationGeneration == generation,
                              auth.session?.storageKey == expectedStorageKey else { return }
                        // A payload that was fetched successfully but cannot be accepted for
                        // this owner remains readable only from the existing local snapshot.
                        cloudError = error
                    }
                } else {
                    try candidate.setCloudExtensionsData(nil)
                    try await uploadCurrentState(
                        from: candidate,
                        owner: expectedOwner,
                        expectedStorageKey: expectedStorageKey,
                        expectedUserID: expectedUserID
                    )
                    cloudWritesAllowed = true
                }
            }
            // A remote restore may replace local rows. Accounts without a seed marker receive
            // the catalog once; a current marker preserves exercises the user intentionally deleted.
            let catalogSeedVersionBeforeFinalSeed = candidate.catalogSeedVersion
            seededExerciseCount += try candidate.seedBuiltInExercises()
            let catalogSeedMarkerChanged =
                candidate.catalogSeedVersion != catalogSeedVersionBeforeFinalSeed
            _ = try candidate.seedDefaultMuscleMappings()
            try ensureActivationIsCurrent(
                generation: generation,
                expectedStorageKey: expectedStorageKey
            )
            cloudWritableAccountStorageKey = cloudWritesAllowed ? expectedStorageKey : nil
            publish(store: candidate, activeStorageKey: expectedStorageKey)
            if expectedUserID != nil, cloudSyncStatus == .checking {
                restoreCloudCheckpointStatus(storageKey: expectedStorageKey)
            }
            isPreparingAccount = false
            accountPreparationError = nil
            if (seededExerciseCount > 0 || catalogSeedMarkerChanged ||
                requiresCanonicalCloudUpload) && cloudWritesAllowed {
                scheduleCloudSave(delay: .zero)
            }

            if openedStore.quarantinedFileURL != nil {
                show(
                    message: "A damaged local data file was preserved for recovery.",
                    isError: true
                )
            }
            if let cloudError {
                cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(cloudError))
                show(error: cloudError)
            }
            if loadedReadOnlyUnsupportedState {
                cloudSyncStatus = .failed(
                    "Cloud data contains unsupported future workout fields."
                )
                show(
                    message: gymText(
                        "This cloud row contains unsupported future workout fields. Automatic uploads are paused so another platform's data is not lost.",
                        "Цей хмарний запис містить непідтримувані майбутні поля тренувань. Автоматичне надсилання призупинено, щоб не втратити дані з іншої платформи.",
                        languageCode: defaults.string(forKey: "app-language") ?? AppLanguage.english.rawValue
                    ),
                    isError: false
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard accountActivationGeneration == generation,
                  auth.session?.storageKey == expectedStorageKey else { return }
            activeAccountStorageKey = nil
            isPreparingAccount = false
            accountPreparationError = gymErrorMessage(error)
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    private func resolveCloudSyncConflict(
        _ pending: PendingCloudSyncConflict,
        useCloudVersion: Bool
    ) async {
        defer { isResolvingCloudSyncConflict = false }
        do {
            try ensureActivationIsCurrent(
                generation: pending.generation,
                expectedStorageKey: pending.storageKey
            )
            let remoteData: Data?
            if let remoteStateLoader {
                remoteData = try await remoteStateLoader(pending.userID)
            } else {
                remoteData = try await cloudSync.withSyncIndicator {
                    try await self.cloudSync.loadRemoteState(
                        expectedUserID: pending.userID
                    )
                }
            }
            guard let remoteData else {
                throw CloudSyncError.staleRemoteState
            }
            let preparedBackup = try WorkoutStore.prepareCloudBackup(
                remoteData,
                activeOwner: pending.owner,
                localCatalogSeedVersion: pending.localStore.catalogSeedVersion
            )
            guard preparedBackup.roundTripSafe else {
                throw CloudSyncError.staleRemoteState
            }
            let reloadedRemoteBackup = try JSONDecoder().decode(
                GymBackup.self,
                from: preparedBackup.data
            )
            guard try Self.cloudWorkoutIdentity(reloadedRemoteBackup) == pending.remoteIdentity else {
                throw CloudSyncError.staleRemoteState
            }
            let currentLocalBackup = try pending.localStore.makeBackup(owner: pending.owner)
            guard try Self.cloudWorkoutIdentity(currentLocalBackup) == pending.localIdentity else {
                throw CloudSyncError.staleRemoteState
            }
            try ensureActivationIsCurrent(
                generation: pending.generation,
                expectedStorageKey: pending.storageKey
            )

            var catalogChanged = false
            try pending.localStore.setCloudExtensionsData(
                preparedBackup.extensionsData
            )
            if useCloudVersion {
                _ = try pending.localStore.restoreBackup(
                    data: preparedBackup.data,
                    activeOwner: pending.owner
                )
                catalogChanged = try pending.localStore.seedBuiltInExercises() > 0
                _ = try pending.localStore.seedDefaultMuscleMappings()
                recordCloudBaseline(
                    pending.remoteIdentity,
                    storageKey: pending.storageKey,
                    clean: true
                )
            } else {
                try await cloudSync.withSyncIndicator {
                    try await self.uploadCurrentState(
                        from: pending.localStore,
                        owner: pending.owner,
                        expectedStorageKey: pending.storageKey,
                        expectedUserID: pending.userID
                    )
                }
            }
            try ensureActivationIsCurrent(
                generation: pending.generation,
                expectedStorageKey: pending.storageKey
            )

            cloudWritableAccountStorageKey = pending.storageKey
            pendingCloudSyncConflict = nil
            cloudSyncConflict = nil
            accountPreparationError = nil
            publish(store: pending.localStore, activeStorageKey: pending.storageKey)
            isPreparingAccount = false
            if catalogChanged {
                scheduleCloudSave(delay: .zero)
            }
            show(
                message: useCloudVersion
                    ? gymText(
                        "Cloud workout history was loaded on this iPhone.",
                        "Хмарну історію тренувань завантажено на цей iPhone.",
                        languageCode: defaults.string(forKey: "app-language") ??
                            AppLanguage.english.rawValue
                    )
                    : gymText(
                        "This iPhone's workout history was saved to the cloud.",
                        "Історію тренувань із цього iPhone збережено в хмарі.",
                        languageCode: defaults.string(forKey: "app-language") ??
                            AppLanguage.english.rawValue
                    ),
                isError: false
            )
        } catch is CancellationError {
            return
        } catch {
            guard pending.generation == accountActivationGeneration,
                  auth.session?.storageKey == pending.storageKey else { return }
            accountPreparationError = gymText(
                "The workout histories changed before your choice was applied. Review both versions again.",
                "Історії тренувань змінилися до застосування вибору. Перевір обидві версії ще раз.",
                languageCode: defaults.string(forKey: "app-language") ?? AppLanguage.english.rawValue
            )
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    static func cloudWorkoutIdentity(_ backup: GymBackup) throws -> CloudWorkoutIdentity {
        let canonical = try WorkoutStore.canonicalCloudWorkoutIdentityInput(backup)
        let configuredExercises = canonical.exercises
            .filter {
                BuiltInExerciseCatalog.resolvedKey(
                    catalogKey: $0.catalogKey,
                    name: $0.name
                ) == nil
            }
            .map { exercise in
                var portable = exercise
                portable.machineLoadProfile = nil
                return portable
            }
            .sorted(by: BackupExercisePortableWireOrder.precedes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let exactWire = try encoder.encode(CloudWorkoutExactWire(
            configuredExercises: configuredExercises,
            sessions: canonical.sessions
        ))
        return CloudWorkoutIdentity(
            configuredExercises: configuredExercises,
            sessions: canonical.sessions,
            exactWire: exactWire
        )
    }

    private static func hasUserWorkoutData(_ identity: CloudWorkoutIdentity) -> Bool {
        !identity.sessions.isEmpty || !identity.configuredExercises.isEmpty
    }

    private func cloudCheckpoint(for storageKey: String) -> CloudSyncCheckpoint {
        let key = Self.cloudCheckpointKeyPrefix + storageKey
        guard let data = defaults.data(forKey: key),
              data.count <= 64 * 1_024,
              let checkpoint = try? JSONDecoder().decode(CloudSyncCheckpoint.self, from: data),
              checkpoint.version == 1 else {
            return .empty
        }
        return checkpoint
    }

    private func persistCloudCheckpoint(
        _ checkpoint: CloudSyncCheckpoint,
        storageKey: String
    ) {
        guard let data = try? JSONEncoder().encode(checkpoint),
              data.count <= 64 * 1_024 else { return }
        defaults.set(data, forKey: Self.cloudCheckpointKeyPrefix + storageKey)
    }

    private func markCloudPending(storageKey: String) {
        var checkpoint = cloudCheckpoint(for: storageKey)
        checkpoint.dirty = true
        checkpoint.pending = true
        persistCloudCheckpoint(checkpoint, storageKey: storageKey)
        cloudSyncStatus = .pending
    }

    private func recordCloudBaseline(
        _ identity: CloudWorkoutIdentity,
        storageKey: String,
        clean: Bool,
        successfulAt: Date? = Date()
    ) {
        var checkpoint = cloudCheckpoint(for: storageKey)
        checkpoint.baselineDigest = Self.cloudIdentityDigest(identity)
        checkpoint.dirty = !clean
        checkpoint.pending = !clean
        if let successfulAt { checkpoint.lastSuccessfulAt = successfulAt }
        persistCloudCheckpoint(checkpoint, storageKey: storageKey)
        cloudSyncStatus = clean
            ? .synced(checkpoint.lastSuccessfulAt ?? Date())
            : .pending
    }

    private func restoreCloudCheckpointStatus(storageKey: String) {
        let checkpoint = cloudCheckpoint(for: storageKey)
        if checkpoint.pending || checkpoint.dirty {
            cloudSyncStatus = .pending
        } else if let lastSuccessfulAt = checkpoint.lastSuccessfulAt {
            cloudSyncStatus = .synced(lastSuccessfulAt)
        } else {
            cloudSyncStatus = .pending
        }
    }

    var cloudLastSuccessfulSyncAt: Date? {
        switch cloudSyncStatus {
        case .synced(let date): date
        default:
            activeAccountStorageKey.flatMap {
                cloudCheckpoint(for: $0).lastSuccessfulAt
            }
        }
    }

    private static func cloudIdentityDigest(_ identity: CloudWorkoutIdentity) -> Data {
        Data(SHA256.hash(data: identity.exactWire))
    }

    func forceCloudSync() async {
        guard isAccountReady,
              let session = auth.session,
              let cloud = session.cloud else {
            show(message: "Cloud sync is available after signing in.", isError: true)
            return
        }
        guard cloudWritableAccountStorageKey == session.storageKey else {
            show(
                message: "Cloud upload is paused because this row contains unsupported future workout fields.",
                isError: true
            )
            return
        }
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        do {
            cloudSyncStatus = .syncing
            try await cloudSync.withSyncIndicator {
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            }
            guard self.isAccountReady,
                  self.workoutStore === store,
                  self.auth.session?.cloud?.userID == cloud.userID else {
                throw AuthServiceError.sessionChanged
            }
            show(message: "Cloud data is up to date.", isError: false)
        } catch CloudSyncError.staleRemoteState {
            await reconcileStaleManualSync(
                store: store,
                session: session,
                userID: cloud.userID,
                owner: owner
            )
        } catch {
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    private func reconcileStaleManualSync(
        store: WorkoutStore,
        session: AppAccountSession,
        userID: String,
        owner: BackupOwner
    ) async {
        let storageKey = session.storageKey
        do {
            cloudSyncStatus = .checking
            let remoteData = try await cloudSync.withSyncIndicator {
                if let remoteStateLoader {
                    return try await remoteStateLoader(userID)
                }
                return try await self.cloudSync.loadRemoteState(expectedUserID: userID)
            }
            guard isAccountReady,
                  workoutStore === store,
                  auth.session?.storageKey == storageKey,
                  auth.session?.cloud?.userID == userID else {
                throw AuthServiceError.sessionChanged
            }

            guard let remoteData else {
                // The reload established a current "missing" revision. Recreating the row is
                // safe and still uses the normal insert conflict guard.
                cloudSyncStatus = .syncing
                try await cloudSync.withSyncIndicator {
                    try await self.uploadCurrentState(
                        from: store,
                        owner: owner,
                        expectedStorageKey: storageKey,
                        expectedUserID: userID
                    )
                }
                show(message: "Cloud data is up to date.", isError: false)
                return
            }

            let prepared = try WorkoutStore.prepareCloudBackup(
                remoteData,
                activeOwner: owner,
                localCatalogSeedVersion: store.catalogSeedVersion
            )
            guard prepared.roundTripSafe else {
                cloudWritableAccountStorageKey = nil
                throw CloudSyncError.requestFailed(
                    "Cloud data contains unsupported future workout fields."
                )
            }
            let remoteBackup = try JSONDecoder().decode(GymBackup.self, from: prepared.data)
            let localBackup = try store.makeBackup(owner: owner)
            let remoteIdentity = try Self.cloudWorkoutIdentity(remoteBackup)
            let localIdentity = try Self.cloudWorkoutIdentity(localBackup)
            let baselineDigest = cloudCheckpoint(for: storageKey).baselineDigest

            try store.setCloudExtensionsData(prepared.extensionsData)
            if remoteIdentity == localIdentity {
                recordCloudBaseline(remoteIdentity, storageKey: storageKey, clean: true)
                show(message: "Cloud data is up to date.", isError: false)
                return
            }

            if baselineDigest == Self.cloudIdentityDigest(remoteIdentity) {
                // Only this device changed since the last common baseline. Retry once using
                // the freshly loaded CAS revision instead of the stale revision.
                cloudSyncStatus = .syncing
                try await cloudSync.withSyncIndicator {
                    try await self.uploadCurrentState(
                        from: store,
                        owner: owner,
                        expectedStorageKey: storageKey,
                        expectedUserID: userID
                    )
                }
                show(message: "Cloud data is up to date.", isError: false)
                return
            }

            if baselineDigest == Self.cloudIdentityDigest(localIdentity) {
                // Only the cloud changed. This is a whole-state fast-forward, not a merge.
                applyingRemoteState = true
                defer { applyingRemoteState = false }
                _ = try store.restoreBackup(data: prepared.data, activeOwner: owner)
                _ = try store.seedBuiltInExercises()
                _ = try store.seedDefaultMuscleMappings()
                recordCloudBaseline(remoteIdentity, storageKey: storageKey, clean: true)
                show(message: "Newer cloud workout data was loaded.", isError: false)
                return
            }

            pendingCloudSyncConflict = PendingCloudSyncConflict(
                generation: accountActivationGeneration,
                storageKey: storageKey,
                userID: userID,
                owner: owner,
                localStore: store,
                localIdentity: localIdentity,
                remoteIdentity: remoteIdentity
            )
            cloudSyncConflict = CloudSyncConflictSummary(
                localWorkoutCount: localBackup.sessions.count,
                cloudWorkoutCount: remoteBackup.sessions.count
            )
            cloudSyncStatus = .conflict
        } catch {
            guard auth.session?.storageKey == storageKey else { return }
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    func refreshSocialDashboard() async throws -> SocialDashboard {
        guard isAccountReady,
              let session = auth.session,
              let cloud = session.cloud else {
            throw AuthServiceError.notCloudAccount
        }
        let generation = accountActivationGeneration
        let cacheGeneration = socialCacheGeneration
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        defer {
            // Every completed refresh attempt invalidates an open detail, including a
            // failed foreground refresh. The detail surface then refetches or clears.
            if accountActivationGeneration == generation,
               auth.session?.storageKey == session.storageKey,
               auth.session?.cloud?.userID == cloud.userID,
               socialCacheGeneration == cacheGeneration {
                socialDashboardRefreshRevision &+= 1
            }
        }
        return try await cloudSync.withSyncIndicator {
            // An unsupported future row is intentionally read-only: fetching standings
            // must never become an alternate path that overwrites its unknown core fields.
            if cloudWritableAccountStorageKey == session.storageKey {
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            }
            guard self.socialCacheGeneration == cacheGeneration else {
                throw AuthServiceError.sessionChanged
            }
            let dashboard = try await self.cloudSync.socialDashboard(
                expectedUserID: cloud.userID
            )
            guard self.isAccountReady,
                  self.accountActivationGeneration == generation,
                  self.workoutStore === store,
                  self.auth.session?.storageKey == session.storageKey,
                  self.auth.session?.cloud?.userID == cloud.userID,
                  self.socialCacheGeneration == cacheGeneration else {
                throw AuthServiceError.sessionChanged
            }
            self.socialDashboard = dashboard
            return dashboard
        }
    }

    func socialFriendDetails(profileID: String) async throws -> SocialFriendDetails {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let details = try await cloudSync.socialFriendDetails(
            profileID: profileID,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        return details
    }

    func sendFriendRequest(friendCode: String) async throws {
        let context = try socialContext()
        try await cloudSync.socialSendFriendRequest(
            friendCode: friendCode,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
    }

    func respondFriendRequest(
        _ request: SocialFriendRequest,
        accept: Bool
    ) async throws {
        let context = try socialContext()
        guard socialDashboard?.incoming.contains(request) == true else {
            throw CloudSyncError.invalidFriendship
        }
        _ = try await cloudSync.socialRespondFriendRequest(
            friendshipID: request.friendshipID,
            decision: accept ? "accept" : "decline",
            expectedRevision: request.friendshipRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
    }

    func cancelFriendRequest(_ request: SocialFriendRequest) async throws {
        let context = try socialContext()
        guard socialDashboard?.outgoing.contains(request) == true else {
            throw CloudSyncError.invalidFriendship
        }
        _ = try await cloudSync.socialCancelFriendRequest(
            friendshipID: request.friendshipID,
            expectedRevision: request.friendshipRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
    }

    func removeFriend(_ friend: SocialFriendSummary) async throws {
        let context = try socialContext()
        guard socialDashboard?.friends.contains(friend) == true else {
            throw CloudSyncError.invalidFriendship
        }
        // A relationship mutation may commit even if its response is lost. Hide every
        // relationship-derived surface and fence older reads before crossing the network.
        invalidateSocialRelationshipCaches()
        _ = try await cloudSync.socialRemoveFriend(
            friendshipID: friend.friendshipID,
            expectedRevision: friend.friendshipRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
        _ = try await refreshSocialWorkoutInbox()
    }

    func blockSocialProfile(profileID: String) async throws {
        let context = try socialContext()
        // Blocking revokes friend summaries, details, and workout-invite access. Fail closed
        // before the RPC in case the server commits but the client misses the response.
        invalidateSocialRelationshipCaches()
        let result = try await cloudSync.socialBlockProfile(
            profileID: profileID,
            expectedUserID: context.userID
        )
        guard result.profileID == profileID, result.blocked else {
            throw CloudSyncError.invalidResponse
        }
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
        _ = try await refreshSocialWorkoutInbox()
    }

    func unblockSocialProfile(profileID: String) async throws {
        let context = try socialContext()
        let result = try await cloudSync.socialUnblockProfile(
            profileID: profileID,
            expectedUserID: context.userID
        )
        guard result.profileID == profileID, !result.blocked else {
            throw CloudSyncError.invalidResponse
        }
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
    }

    func updateSocialPrivacy(_ privacy: SocialPrivacy) async throws {
        let context = try socialContext()
        guard let current = socialDashboard?.currentUser else {
            throw CloudSyncError.invalidResponse
        }
        let result = try await cloudSync.socialUpdatePrivacy(
            privacy,
            expectedRevision: current.settingsRevision,
            expectedUserID: context.userID
        )
        guard result.0 == privacy else { throw CloudSyncError.invalidResponse }
        try validateSocialContext(context)
        _ = try await refreshSocialDashboard()
    }

    func refreshSocialWorkoutInbox() async throws -> SocialWorkoutInbox {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let inbox = try await cloudSync.socialWorkoutInbox(expectedUserID: context.userID)
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        socialWorkoutInbox = inbox
        return inbox
    }

    func sendWorkoutInvite(
        to profileID: String,
        plan: SharedWorkoutPlan
    ) async throws {
        let context = try socialContext()
        guard socialDashboard?.friends.contains(where: { $0.profileID == profileID }) == true else {
            throw CloudSyncError.invalidSocialProfile
        }
        let requestKey = try workoutInviteRequestKey(
            context: context,
            profileID: profileID,
            plan: plan
        )
        let clientRequestID: UUID
        if let pendingID = pendingWorkoutInviteRequestIDs[requestKey] {
            clientRequestID = pendingID
        } else {
            guard pendingWorkoutInviteRequestIDs.count < Self.maximumPendingWorkoutInviteRequests else {
                throw CloudSyncError.requestFailed(
                    "Too many workout invitation attempts are awaiting a confirmed outcome."
                )
            }
            clientRequestID = UUID()
            pendingWorkoutInviteRequestIDs[requestKey] = clientRequestID
        }

        try await cloudSync.socialSendWorkoutInvite(
            profileID: profileID,
            clientRequestID: clientRequestID,
            workout: plan,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        pendingWorkoutInviteRequestIDs.removeValue(forKey: requestKey)

        do {
            _ = try await refreshSocialWorkoutInbox()
        } catch {
            // The mutation itself has a confirmed generic outcome. Do not make the UI
            // retry it with a fresh UUID merely because the follow-up inbox read failed.
            try validateSocialContext(context)
            socialWorkoutInbox = nil
        }
    }

    func respondWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        accept: Bool,
        replacingPendingSharedWorkoutID: UUID? = nil
    ) async throws -> SharedWorkoutPlan? {
        let context = try socialContext()
        guard invite.status == .pending,
              socialWorkoutInbox?.incoming.contains(invite) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        if accept, let pendingSharedWorkout {
            guard replacingPendingSharedWorkoutID == pendingSharedWorkout.id else {
                throw CloudSyncError.invalidWorkoutInvite
            }
        }
        if accept {
            guard let plan = invite.workout else {
                throw CloudSyncError.invalidWorkoutInvite
            }
            // The social wire contract intentionally does not infer local catalog aliases.
            // Preflight the local-copy boundary before accepting so a server-portable plan
            // that is ambiguous on this device stays pending and does not mutate remotely.
            try validateWorkoutInviteForLocalImport(plan)
        }
        let result = try await cloudSync.socialRespondWorkoutInvite(
            inviteID: invite.inviteID,
            decision: accept ? "accept" : "decline",
            expectedRevision: invite.inviteRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        if accept {
            guard result.status == .accepted, let plan = result.workout else {
                throw CloudSyncError.invalidResponse
            }
            try stageWorkoutInvitePlan(
                plan,
                replacingPendingID: replacingPendingSharedWorkoutID
            )
        } else if result.status != .declined || result.workout != nil {
            throw CloudSyncError.invalidResponse
        }
        _ = try await refreshSocialWorkoutInbox()
        return result.workout
    }

    func recoverAcceptedWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        replacingPendingSharedWorkoutID: UUID? = nil
    ) throws -> SharedWorkoutPlan {
        let context = try socialContext()
        guard invite.status == .accepted,
              let plan = invite.workout,
              socialWorkoutInbox?.incoming.contains(invite) == true,
              socialDashboard?.friends.contains(where: { $0.profileID == invite.profileID }) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        try validateSocialContext(context)
        try stageWorkoutInvitePlan(
            plan,
            replacingPendingID: replacingPendingSharedWorkoutID
        )
        try validateSocialContext(context)
        return plan
    }

    func cancelWorkoutInvite(_ invite: SocialWorkoutInvite) async throws {
        let context = try socialContext()
        guard invite.status == .pending,
              socialWorkoutInbox?.outgoing.contains(invite) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let result = try await cloudSync.socialCancelWorkoutInvite(
            inviteID: invite.inviteID,
            expectedRevision: invite.inviteRevision,
            expectedUserID: context.userID
        )
        guard result.status == .cancelled else { throw CloudSyncError.invalidResponse }
        try validateSocialContext(context)
        _ = try await refreshSocialWorkoutInbox()
    }

    private struct SocialContext {
        let generation: UInt64
        let storageKey: String
        let userID: String
        let store: WorkoutStore
    }

    private func socialContext() throws -> SocialContext {
        guard isAccountReady,
              let session = auth.session,
              let cloud = session.cloud else {
            throw AuthServiceError.notCloudAccount
        }
        return SocialContext(
            generation: accountActivationGeneration,
            storageKey: session.storageKey,
            userID: cloud.userID,
            store: workoutStore
        )
    }

    private func validateSocialContext(_ context: SocialContext) throws {
        guard isAccountReady,
              accountActivationGeneration == context.generation,
              workoutStore === context.store,
              auth.session?.storageKey == context.storageKey,
              auth.session?.cloud?.userID == context.userID else {
            throw AuthServiceError.sessionChanged
        }
    }

    private func invalidateSocialRelationshipCaches() {
        socialCacheGeneration &+= 1
        socialDashboard = nil
        socialWorkoutInbox = nil
        // FriendDetailView keys its refetch lifecycle to this revision. Increment it
        // synchronously so visible private data disappears before the mutation awaits.
        socialDashboardRefreshRevision &+= 1
    }

    private func validateWorkoutInviteForLocalImport(_ plan: SharedWorkoutPlan) throws {
        do {
            _ = try SharedWorkoutLinkValidator.validate(plan)
        } catch {
            throw CloudSyncError.invalidWorkoutInvite
        }
    }

    private func stageWorkoutInvitePlan(
        _ plan: SharedWorkoutPlan,
        replacingPendingID: UUID?
    ) throws {
        do {
            try stageSharedWorkoutPlan(plan, replacingPendingID: replacingPendingID)
        } catch {
            // Never expose raw imported names or validator internals to the social UI.
            throw CloudSyncError.invalidWorkoutInvite
        }
    }

    private func workoutInviteRequestKey(
        context: SocialContext,
        profileID: String,
        plan: SharedWorkoutPlan
    ) throws -> PendingWorkoutInviteRequestKey {
        guard SocialPayloadParser.isValidProfileID(profileID) else {
            throw CloudSyncError.invalidSocialProfile
        }
        let object: [String: Any]
        let canonicalWorkout: Data
        do {
            object = try SocialPayloadParser.workoutObject(for: plan)
            canonicalWorkout = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        } catch {
            throw CloudSyncError.invalidPayload
        }
        return PendingWorkoutInviteRequestKey(
            generation: context.generation,
            storageKey: context.storageKey,
            userID: context.userID,
            profileID: profileID,
            canonicalWorkout: canonicalWorkout
        )
    }

    func importBackup(_ data: Data) throws -> BackupImportResult {
        guard isAccountReady else { throw WorkoutStoreError.storageAccountMismatch }
        return try workoutStore.importBackup(data: data, activeOwner: backupOwner)
    }

    func exportBackup() throws -> Data {
        guard isAccountReady else { throw WorkoutStoreError.storageAccountMismatch }
        return try workoutStore.exportBackupData(
            owner: backupOwner,
            prettyPrinted: true
        )
    }

    func deleteCurrentAccountAndData(
        expectedStorageKey: String,
        expectedCloudUserID: String?
    ) async throws {
        let target = AccountDeletionTarget(
            storageKey: expectedStorageKey,
            cloudUserID: expectedCloudUserID
        )
        if let accountDeletionTask {
            guard accountDeletionTarget == target else {
                throw AuthServiceError.sessionChanged
            }
            try await accountDeletionTask.value
            return
        }

        try ensureDeletionTargetIsCurrent(target)
        accountDeletionGeneration &+= 1
        let generation = accountDeletionGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performAccountDeletion(target)
        }
        accountDeletionTarget = target
        accountDeletionTask = task

        do {
            try await task.value
            finishAccountDeletion(generation: generation)
        } catch {
            finishAccountDeletion(generation: generation)
            throw error
        }
    }

    private func performAccountDeletion(_ target: AccountDeletionTarget) async throws {
        try ensureDeletionTargetIsCurrent(target)
        let deletingStore = workoutStore
        let scheduledSave = pendingCloudSave
        if cloudSavePhase == .debouncing {
            scheduledSave?.cancel()
        }
        await scheduledSave?.value
        try ensureDeletionTargetIsCurrent(target, deletingStore: deletingStore)
        guard let session = auth.session else { throw AuthServiceError.sessionChanged }
        let storageKey = target.storageKey
        defaults.removeObject(forKey: Self.legacyPendingDeletionGarminUserIDKey)
        if target.cloudUserID == nil {
            // Local profiles have no server boundary. Persist before local cleanup so a
            // termination can safely resume deletion on the next launch.
            defaults.set(storageKey, forKey: Self.pendingDeletionStorageKey)
            _ = defaults.synchronize()
        }

        var requestDisposition = AccountDeletionRequestDisposition.notDispatched
        do {
            try ensureDeletionTargetIsCurrent(target, deletingStore: deletingStore)
            if let cloudUserID = target.cloudUserID {
                try await auth.deleteCloudAccountOnServer(
                    expectedUserID: cloudUserID,
                    onRequestDispositionChange: { disposition in
                        requestDisposition = disposition
                        switch disposition {
                        case .outcomeUnknown:
                            // Persist before each delete attempt can cross the network
                            // boundary. A relaunch must finish cleanup if that attempt's
                            // response is lost or malformed.
                            self.defaults.set(storageKey, forKey: Self.pendingDeletionStorageKey)
                        case .notDispatched, .definitivelyRejected:
                            // A bounded 4xx proves that this attempt did not delete the
                            // account. Remove the marker before a refresh/retry await so an
                            // intervening termination cannot erase valid local data.
                            self.defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
                        }
                        _ = self.defaults.synchronize()
                    }
                )
            }
        } catch {
            if requestDisposition != .outcomeUnknown {
                // No delete request crossed the network boundary, or the server returned an
                // authoritative 4xx rejection. The local account remains authoritative.
                defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
                _ = defaults.synchronize()
            }
            // For a lost/malformed response, 5xx, cancellation, or a stale result after a
            // successful response, the outcome remains unknown. Keep the marker so startup
            // finishes secure local cleanup before exposing this account again.
            throw error
        }
        try ensureDeletionTargetIsCurrent(target, deletingStore: deletingStore)

        let deletingSessionIsStillCurrent = auth.session?.storageKey == storageKey
        if deletingSessionIsStillCurrent {
            accountActivationTask?.cancel()
            accountActivationTask = nil
            accountActivationGeneration &+= 1
            abandonPendingCloudSave()
            cloudSync.resetForAccountTransition()
            cloudWritableAccountStorageKey = nil
            activeAccountStorageKey = nil
            isPreparingAccount = true
            applyingRemoteState = true
        }

        var cleanupError: Error?
        if deletingSessionIsStillCurrent {
            clearRestTimersForAccountTransition(to: nil)
        }
        if let cloudUserID = session.cloud?.userID {
            do {
                try garminCloud.clearLocalBindingData(for: cloudUserID)
            } catch {
                cleanupError = cleanupError ?? error
            }
        }
        garminPhoneSync.clearLocalData(storageKey: storageKey)
        defaults.removeObject(forKey: Self.trainingProfileKeyPrefix + storageKey)
        defaults.removeObject(forKey: Self.hiddenLeaderboardProfilesKey)
        defaults.removeObject(
            forKey: leaderboardHiddenProfilesDefaultsKey(for: storageKey)
        )

        do {
            try deletingStore.destroyAccountData()
        } catch {
            cleanupError = error
        }
        if deletingSessionIsStillCurrent {
            do {
                let signedOut = try WorkoutStore.openRecoveringCorruptStore(
                    accountStorageKey: "signed-out",
                    directoryURL: workoutDirectoryURL
                ).store
                publish(store: signedOut, activeStorageKey: nil)
            } catch {
                cleanupError = cleanupError ?? error
            }
            do {
                try auth.clearSession()
            } catch {
                cleanupError = cleanupError ?? error
            }
            applyingRemoteState = false
            isPreparingAccount = false
        }

        guard cleanupError == nil else {
            // The marker intentionally survives. Startup retries secure local cleanup before
            // exposing any account UI, including after a server-side account was deleted.
            throw cleanupError!
        }

        defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
        defaults.removeObject(forKey: Self.legacyPendingDeletionGarminUserIDKey)
        if deletingSessionIsStillCurrent { statusMessage = nil }
    }

    private func ensureDeletionTargetIsCurrent(
        _ target: AccountDeletionTarget,
        deletingStore: WorkoutStore? = nil
    ) throws {
        try Task.checkCancellation()
        guard let session = auth.session,
              session.storageKey == target.storageKey,
              session.cloud?.userID == target.cloudUserID else {
            throw AuthServiceError.sessionChanged
        }
        guard isAccountReady,
              workoutStore.accountStorageKey == target.storageKey,
              deletingStore.map({ workoutStore === $0 }) ?? true else {
            throw WorkoutStoreError.storageAccountMismatch
        }
    }

    private func finishAccountDeletion(generation: UInt64) {
        guard accountDeletionGeneration == generation else { return }
        accountDeletionTask = nil
        accountDeletionTarget = nil
    }

    func saveBeforeBackgrounding() {
        guard isAccountReady else { return }
        try? workoutStore.saveNow()
        if auth.session?.cloud != nil { scheduleCloudSave(delay: .zero) }
    }

#if DEBUG
    func bootstrapDemoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-mode") else { return }
        do {
            if auth.session == nil {
                try auth.continueOffline(displayName: "Demo Athlete")
            }
            if let session = auth.session {
                await activate(session)
            }
            _ = try workoutStore.seedDemoData()
        } catch {
            show(error: error)
        }
    }
#endif

    func show(error: Error) {
        show(message: gymErrorMessage(error), isError: true)
    }

    func show(message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    func clearStatus() {
        statusMessage = nil
    }

    private func observeStore() {
        storeSubscription?.cancel()
        storeSubscription = workoutStore.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.applyingRemoteState,
                      !self.isSigningOut,
                      self.isAccountReady,
                      let storageKey = self.auth.session?.storageKey,
                      self.auth.session?.cloud != nil else { return }
                self.markCloudPending(storageKey: storageKey)
                self.scheduleCloudSave()
            }
        }
    }

    private func scheduleCloudSave(delay: Duration = .milliseconds(1_500)) {
        guard !isSigningOut,
              isAccountReady,
              let session = auth.session,
              let cloud = session.cloud,
              cloudWritableAccountStorageKey == session.storageKey else { return }
        if cloudSavePhase == .uploading {
            // Let the in-flight request establish its returned CAS revision, then
            // serialize the newer snapshot behind it.
            cloudSaveQueued = true
            return
        }
        if cloudSavePhase == .debouncing {
            pendingCloudSave?.cancel()
        }
        cloudSaveGeneration &+= 1
        let generation = cloudSaveGeneration
        cloudSavePhase = .debouncing
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        pendingCloudSave = Task { [weak self] in
            guard let self else { return }
            defer { self.finishCloudSave(generation: generation) }
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                guard self.isAccountReady,
                      self.workoutStore === store,
                      self.auth.session?.cloud?.userID == cloud.userID,
                      self.cloudWritableAccountStorageKey == session.storageKey else { return }
                self.cloudSavePhase = .uploading
                self.cloudSyncStatus = .syncing
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            } catch is CancellationError {
                // Cancelling is allowed only during the debounce phase.
            } catch {
                self.cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
                self.show(error: error)
            }
        }
    }

    private func finishCloudSave(generation: UInt64) {
        guard generation == cloudSaveGeneration else { return }
        pendingCloudSave = nil
        cloudSavePhase = .idle
        let shouldRunQueuedSave = cloudSaveQueued
        cloudSaveQueued = false
        if shouldRunQueuedSave && !isSigningOut {
            scheduleCloudSave(delay: .zero)
        }
    }

    private func abandonPendingCloudSave() {
        cloudSaveGeneration &+= 1
        cloudSaveQueued = false
        if cloudSavePhase == .debouncing {
            pendingCloudSave?.cancel()
        }
        // A network-phase save is deliberately left alive. Its generation is now
        // stale, so it cannot overwrite scheduling state for the replacement owner.
        pendingCloudSave = nil
        cloudSavePhase = .idle
    }

    private func uploadCurrentState(
        from store: WorkoutStore,
        owner: BackupOwner,
        expectedStorageKey: String,
        expectedUserID: String
    ) async throws {
        guard store.accountStorageKey == expectedStorageKey,
              auth.session?.storageKey == expectedStorageKey,
              auth.session?.cloud?.userID == expectedUserID,
              owner.accountID == expectedUserID,
              owner.userID == expectedUserID else {
            throw AuthServiceError.sessionChanged
        }
        let profile = store.syncProfileStats()
        let data = try store.exportCloudBackupData(
            owner: owner,
            extensionsData: store.cloudExtensionsData
        )
        let uploadedBackup = try JSONDecoder().decode(GymBackup.self, from: data)
        let uploadedIdentity = try Self.cloudWorkoutIdentity(uploadedBackup)
        try await cloudSync.saveRemoteState(
            backupData: data,
            xp: profile.xp,
            level: profile.level,
            workouts: profile.workouts,
            expectedUserID: expectedUserID
        )
        guard auth.session?.storageKey == expectedStorageKey,
              auth.session?.cloud?.userID == expectedUserID else {
            throw AuthServiceError.sessionChanged
        }
        let currentIdentity = try Self.cloudWorkoutIdentity(
            store.makeBackup(owner: owner)
        )
        recordCloudBaseline(
            uploadedIdentity,
            storageKey: expectedStorageKey,
            clean: currentIdentity == uploadedIdentity
        )
    }

    private func ensureActivationIsCurrent(
        generation: UInt64,
        expectedStorageKey: String?
    ) throws {
        try Task.checkCancellation()
        guard accountActivationGeneration == generation,
              auth.session?.storageKey == expectedStorageKey else {
            throw CancellationError()
        }
    }

    private func publish(store: WorkoutStore, activeStorageKey: String?) {
        workoutStore = store
        garminPhoneSync.bind(workoutStore: store)
        observeStore()
        activeAccountStorageKey = activeStorageKey
    }

    private static func finishPendingDeletionCleanupIfNeeded(
        auth: AuthService,
        defaults: UserDefaults,
        workoutDirectoryURL: URL?,
        garminBindingStore: GarminDeviceBindingStore
    ) {
        guard let storageKey = defaults.string(forKey: pendingDeletionStorageKey),
              !storageKey.isEmpty else {
            defaults.removeObject(forKey: legacyPendingDeletionGarminUserIDKey)
            return
        }

        var cleanupFailed = false
        do {
            try WorkoutStore.destroyAccountFiles(
                accountStorageKey: storageKey,
                directoryURL: workoutDirectoryURL
            )
        } catch {
            cleanupFailed = true
        }

        defaults.removeObject(forKey: trainingProfileKeyPrefix + storageKey)
        defaults.removeObject(forKey: hiddenLeaderboardProfilesKey)
        defaults.removeObject(
            forKey: leaderboardHiddenProfilesDefaultsKey(for: storageKey)
        )
        GarminPhoneSyncService.clearStoredData(
            defaults: defaults,
            storageKey: storageKey
        )
        if let cloudUserID = cloudUserID(fromDeletionStorageKey: storageKey) {
            do {
                try garminBindingStore.deleteAll(for: cloudUserID)
            } catch {
                cleanupFailed = true
            }
        }
        if auth.session?.storageKey == storageKey {
            do {
                try auth.clearSession()
            } catch {
                // AuthService still clears the in-memory session, so deleted data is never shown.
                cleanupFailed = true
            }
        }

        if !cleanupFailed {
            defaults.removeObject(forKey: pendingDeletionStorageKey)
        }
        defaults.removeObject(forKey: legacyPendingDeletionGarminUserIDKey)
    }

    private static func cloudUserID(fromDeletionStorageKey storageKey: String) -> String? {
        let prefix = "cloud_"
        guard storageKey.hasPrefix(prefix) else { return nil }
        let suffix = String(storageKey.dropFirst(prefix.count))
        guard suffix.utf8.count == 36, let uuid = UUID(uuidString: suffix) else { return nil }
        return uuid.uuidString.lowercased()
    }
}
