import Combine
import Foundation

func leaderboardHiddenProfilesDefaultsKey(for accountStorageKey: String) -> String {
    "leaderboard-hidden-profile-ids.\(accountStorageKey)"
}

@MainActor
final class AppState: ObservableObject {
    struct CloudSyncConflictSummary: Equatable {
        let localWorkoutCount: Int
        let cloudWorkoutCount: Int
    }

    private enum CloudSavePhase {
        case idle
        case debouncing
        case uploading
    }

    private struct CloudWorkoutIdentity: Hashable {
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
    private let defaults: UserDefaults
    private let workoutDirectoryURL: URL?
    private let remoteStateLoader: (@MainActor (String) async throws -> Data?)?

    private static let pendingDeletionStorageKey = "gymapp.pending-account-deletion-storage-key"
    private static let legacyPendingDeletionGarminUserIDKey =
        "gymapp.pending-account-deletion-garmin-user-id"
    private static let trainingProfileKeyPrefix = "gymapp.training-profile.v1."
    private static let hiddenLeaderboardProfilesKey = "leaderboard-hidden-profile-ids"

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
                guard let self else { return }
                Task { @MainActor in self.scheduleActivation(session) }
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

    /// Legacy PWA rows can be read, but native serialization cannot preserve all of
    /// their fields. Keep those rows read-only until a lossless shared contract exists.
    var isCloudWritePaused: Bool {
        guard isAccountReady, auth.session?.cloud != nil else { return false }
        return cloudWritableAccountStorageKey != activeAccountStorageKey
    }

    var backupOwner: BackupOwner {
        Self.backupOwner(for: auth.session, fallbackStorageKey: workoutStore.accountStorageKey)
    }

    private static func backupOwner(
        for session: AppAccountSession?,
        fallbackStorageKey: String
    ) -> BackupOwner {
        switch session {
        case .cloud(let cloud):
            return BackupOwner(
                accountID: session?.storageKey,
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
        cloudWritableAccountStorageKey = nil
        pendingCloudSyncConflict = nil
        cloudSyncConflict = nil
        isResolvingCloudSyncConflict = false
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
            var loadedReadOnlyPWAState = false
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
                        let localIdentity = Self.cloudWorkoutIdentity(localBackup)
                        let remoteIdentity = Self.cloudWorkoutIdentity(remoteBackup)
                        if preparedBackup.roundTripSafe,
                           Self.hasUserWorkoutData(localBackup),
                           localIdentity != remoteIdentity {
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
                            isPreparingAccount = false
                            accountPreparationError = nil
                            return
                        }
                        _ = try candidate.restoreBackup(
                            data: preparedBackup.data,
                            activeOwner: expectedOwner
                        )
                        cloudWritesAllowed = preparedBackup.roundTripSafe
                        loadedReadOnlyPWAState = !preparedBackup.roundTripSafe
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
            isPreparingAccount = false
            accountPreparationError = nil
            if (seededExerciseCount > 0 || catalogSeedMarkerChanged) && cloudWritesAllowed {
                scheduleCloudSave(delay: .zero)
            }

            if openedStore.quarantinedFileURL != nil {
                show(
                    message: "A damaged local data file was preserved for recovery.",
                    isError: true
                )
            }
            if let cloudError { show(error: cloudError) }
            if loadedReadOnlyPWAState {
                show(
                    message: gymText(
                        "Legacy browser cloud data was loaded. Automatic cloud uploads are paused to preserve browser-only profile, language, and mapping fields.",
                        "Застарілі хмарні дані браузера завантажено. Автоматичне надсилання в хмару призупинено, щоб зберегти поля профілю, мови та мапінгу, доступні лише у браузері.",
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
            guard Self.cloudWorkoutIdentity(reloadedRemoteBackup) == pending.remoteIdentity else {
                throw CloudSyncError.staleRemoteState
            }
            let currentLocalBackup = try pending.localStore.makeBackup(owner: pending.owner)
            guard Self.cloudWorkoutIdentity(currentLocalBackup) == pending.localIdentity else {
                throw CloudSyncError.staleRemoteState
            }
            try ensureActivationIsCurrent(
                generation: pending.generation,
                expectedStorageKey: pending.storageKey
            )

            var catalogChanged = false
            if useCloudVersion {
                _ = try pending.localStore.restoreBackup(
                    data: preparedBackup.data,
                    activeOwner: pending.owner
                )
                catalogChanged = try pending.localStore.seedBuiltInExercises() > 0
                _ = try pending.localStore.seedDefaultMuscleMappings()
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
            show(error: error)
        }
    }

    private static func cloudWorkoutIdentity(_ backup: GymBackup) -> CloudWorkoutIdentity {
        CloudWorkoutIdentity(
            configuredExercises: backup.exercises.filter {
                $0.catalogKey == nil || $0.machineLoadProfile != nil
            },
            sessions: backup.sessions
        )
    }

    private static func hasUserWorkoutData(_ backup: GymBackup) -> Bool {
        !backup.sessions.isEmpty || backup.exercises.contains {
            $0.catalogKey == nil || $0.machineLoadProfile != nil
        }
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
                message: "Cloud upload is paused because this account uses a browser state format that iOS cannot preserve losslessly.",
                isError: true
            )
            return
        }
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        do {
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
        } catch {
            show(error: error)
        }
    }

    func refreshCloudLeaderboard() async throws -> [LeaderboardEntry] {
        guard isAccountReady,
              let session = auth.session,
              let cloud = session.cloud else {
            throw AuthServiceError.notCloudAccount
        }
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        return try await cloudSync.withSyncIndicator {
            // A legacy PWA row is intentionally read-only: fetching public standings
            // must never become an alternate path that overwrites that cloud state.
            if cloudWritableAccountStorageKey == session.storageKey {
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            }
            let entries = try await self.cloudSync.leaderboard(
                expectedUserID: cloud.userID
            )
            guard self.isAccountReady,
                  self.workoutStore === store,
                  self.auth.session?.storageKey == session.storageKey,
                  self.auth.session?.cloud?.userID == cloud.userID else {
                throw AuthServiceError.sessionChanged
            }
            return entries
        }
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
                      self.auth.session?.cloud != nil else { return }
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
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            } catch is CancellationError {
                // Cancelling is allowed only during the debounce phase.
            } catch {
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
              owner.accountID == expectedStorageKey,
              owner.userID == expectedUserID else {
            throw AuthServiceError.sessionChanged
        }
        let profile = store.syncProfileStats()
        let data = try store.exportCloudBackupData(owner: owner)
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
