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

    private struct ManualCloudSyncLease: Equatable {
        let accountGeneration: UInt64
        let storageKey: String
        let userID: String
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
        let storageKey: String
        let userID: String
        let profileID: String
        let canonicalWorkoutDigest: Data
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
    @Published private(set) var socialFriendCode: String?
    @Published private(set) var socialWorkoutInbox: SocialWorkoutInbox?
    @Published private(set) var socialWorkoutDetailPrivacy: SocialWorkoutDetailPrivacy?
    @Published private(set) var socialDashboardRefreshRevision: UInt64 = 0
    @Published private(set) var isRestoringConfirmedSocialMutation = false

    private var sessionSubscription: AnyCancellable?
    private var storeSubscription: AnyCancellable?
    private var pendingCloudSave: Task<Void, Never>?
    private var cloudSavePhase = CloudSavePhase.idle
    private var cloudSaveQueued = false
    private var cloudSaveGeneration: UInt64 = 0
    private var manualCloudSyncLease: ManualCloudSyncLease?
    private var accountActivationTask: Task<Void, Never>?
    private var accountActivationGeneration: UInt64 = 0
    private var accountDeletionTask: Task<Void, Error>?
    private var accountDeletionTarget: AccountDeletionTarget?
    private var accountDeletionGeneration: UInt64 = 0
    private var restTimerOwnerFingerprint: String?
    private var applyingRemoteState = false
    private var cloudWritableAccountStorageKey: String?
    /// A previously verified, account-keyed local snapshot may remain available while
    /// the first authoritative cloud read is offline. Uploads stay blocked until a
    /// later full read proves the current remote revision and completes three-way
    /// reconciliation for this exact account.
    private var cloudReconciliationRequiredStorageKey: String?
    private var pendingCloudSyncConflict: PendingCloudSyncConflict?
    private var socialCacheGeneration: UInt64 = 0
    private var pendingSocialReconciliationSurfaces: SocialReconciliationSurfaces = []
    private var socialReconciliationTask: Task<Void, Never>?
    private var socialReconciliationTaskID: UUID?
    private weak var nativePushManager: NativePushManager?
    private let defaults: UserDefaults
    private let workoutDirectoryURL: URL?
    private let exerciseMediaDirectoryURL: URL?
    private let exerciseMediaFileManager: FileManager
    private let remoteStateLoader: (@MainActor (String) async throws -> Data?)?

    private static let pendingDeletionStorageKey = PendingAccountDeletionStore.storageKey
    private static let legacyPendingDeletionGarminUserIDKey =
        "gymapp.pending-account-deletion-garmin-user-id"
    private static let hiddenLeaderboardProfilesKey = "leaderboard-hidden-profile-ids"
    private static let cloudCheckpointKeyPrefix = "gymapp.cloud-sync-checkpoint.v1."
    static let maximumPendingWorkoutInviteRequests = WorkoutInviteRequestStore.maximumEntries

    private struct CloudSyncCheckpoint: Codable {
        let version: Int
        var baselineDigest: Data?
        var dirty: Bool
        var pending: Bool
        var lastSuccessfulAt: Date?
        var activityBaselineDigest: Data?
        var activityDirty: Bool?
        var activityPending: Bool?

        static let empty = CloudSyncCheckpoint(
            version: 1,
            baselineDigest: nil,
            dirty: false,
            pending: false,
            lastSuccessfulAt: nil,
            activityBaselineDigest: nil,
            activityDirty: false,
            activityPending: false
        )
    }

    private struct ActivityOnlyCloudSyncReport {
        let localItems: [ActivityOnlyWorkoutCloudItem]
        let clean: Bool
    }

    private struct AccountDeletionTarget: Equatable {
        let storageKey: String
        let cloudUserID: String?
    }

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        workoutDirectoryURL: URL? = nil,
        exerciseMediaDirectoryURL: URL? = nil,
        exerciseMediaFileManager: FileManager = .default,
        cloudURLSession: URLSession = .shared,
        remoteStateLoader: (@MainActor (String) async throws -> Data?)? = nil,
        garminBindingStore: GarminDeviceBindingStore = GarminDeviceBindingStore(),
        restTimers: RestTimerManager? = nil
    ) throws {
        self.auth = auth
        self.defaults = defaults
        self.workoutDirectoryURL = workoutDirectoryURL
        self.exerciseMediaDirectoryURL = exerciseMediaDirectoryURL
        self.exerciseMediaFileManager = exerciseMediaFileManager
        self.remoteStateLoader = remoteStateLoader

        let hadPendingDeletion = PendingAccountDeletionStore.state(defaults: defaults) != .none
        Self.finishPendingDeletionCleanupIfNeeded(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: workoutDirectoryURL,
            exerciseMediaDirectoryURL: exerciseMediaDirectoryURL,
            exerciseMediaFileManager: exerciseMediaFileManager,
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
                languageCode: gymCurrentLanguageCode(defaults: defaults)
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
        socialReconciliationTask?.cancel()
    }

    var isAccountReady: Bool {
        guard let expectedKey = auth.session?.storageKey else { return false }
        return !isPreparingAccount &&
            activeAccountStorageKey == expectedKey &&
            workoutStore.accountStorageKey == expectedKey
    }

    func attachNativePushManager(_ manager: NativePushManager) {
        nativePushManager = manager
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
                        languageCode: gymCurrentLanguageCode(defaults: defaults)
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
                    languageCode: gymCurrentLanguageCode(defaults: defaults)
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
        let signingOutCloudUserID = auth.session?.cloud?.userID
        let signingOutAuthSessionID = NativePushAuthSessionIdentity.sessionID(
            from: auth.session?.cloud
        )
        var shouldRescheduleCloudSave = false
        var deferredCloudUploadStorageKey: String?
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
                // Logout is a local security boundary and must not depend on network
                // availability. Keep the account-bound store and dirty checkpoint for
                // a later sign-in, then continue to clear reusable local credentials.
                try? store.saveNow()
                markCloudPending(storageKey: session.storageKey)
                deferredCloudUploadStorageKey = session.storageKey
                shouldRescheduleCloudSave = isAccountReady
                    && auth.session?.storageKey == session.storageKey
                    && workoutStore === store
                    && cloudWritableAccountStorageKey == session.storageKey
            }
        }
        if let cloudUserID = signingOutCloudUserID {
            guard signOutSessionIsCurrent(
                userID: cloudUserID,
                authSessionID: signingOutAuthSessionID
            ) else { return false }
            do {
                try await garminCloud.prepareForSessionEnd(
                    expectedUserID: cloudUserID
                )
            } catch {
                // Do not complete logout while an outcome-unknown Garmin
                // bearer remains in Keychain. The user can retry after the
                // current Garmin operation or local storage failure resolves.
                show(error: error)
                return false
            }
            if auth.session != nil {
                guard signOutSessionIsCurrent(
                    userID: cloudUserID,
                    authSessionID: signingOutAuthSessionID
                ) else { return false }
                await nativePushManager?.prepareForSessionEnd(expectedUserID: cloudUserID)
                guard signOutSessionIsCurrent(
                    userID: cloudUserID,
                    authSessionID: signingOutAuthSessionID
                ) else {
                    await nativePushManager?.resumeAfterFailedSessionEnd(
                        expectedUserID: cloudUserID
                    )
                    return false
                }
            }
        }
        await auth.signOut()
        guard auth.session == nil else {
            if let signingOutCloudUserID {
                await nativePushManager?.resumeAfterFailedSessionEnd(
                    expectedUserID: signingOutCloudUserID
                )
            }
            return false
        }
        shouldRescheduleCloudSave = false
        clearRestTimersForAccountTransition(to: nil)
        if deferredCloudUploadStorageKey != nil {
            show(
                message: gymText(
                    "Signed out. Unsynced workouts remain in this account’s isolated local app storage and will be reconciled after the next sign-in.",
                    "Вихід виконано. Несинхронізовані тренування залишилися в локальному сховищі цього акаунта й будуть узгоджені після наступного входу.",
                    "Выход выполнен. Несинхронизированные тренировки остались в локальном хранилище этого аккаунта и будут согласованы после следующего входа.",
                    languageCode: gymCurrentLanguageCode(defaults: defaults)
                ),
                isError: false
            )
        }
        return true
    }

    private func signOutSessionIsCurrent(
        userID: String,
        authSessionID: String?
    ) -> Bool {
        guard let current = auth.session else { return true }
        guard let cloud = current.cloud, cloud.userID == userID else { return false }
        guard let authSessionID else { return true }
        return NativePushAuthSessionIdentity.sessionID(from: cloud) == authSessionID
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
        manualCloudSyncLease = nil
        abandonPendingCloudSave()
        cloudSync.resetForAccountTransition()
        socialReconciliationTask?.cancel()
        socialReconciliationTask = nil
        socialReconciliationTaskID = nil
        pendingSocialReconciliationSurfaces = []
        isRestoringConfirmedSocialMutation = false
        socialDashboard = nil
        socialFriendCode = nil
        socialWorkoutInbox = nil
        socialWorkoutDetailPrivacy = nil
        socialCacheGeneration &+= 1
        socialDashboardRefreshRevision &+= 1
        pendingSharedWorkout = nil
        cloudWritableAccountStorageKey = nil
        cloudReconciliationRequiredStorageKey = nil
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
            // Capture this before seeding can create the first persisted envelope. Only
            // a pre-existing, successfully decoded account-keyed snapshot is eligible
            // for offline activation; a new or quarantined store still waits for cloud.
            let hadVerifiedLocalSnapshot = openedStore.quarantinedFileURL == nil &&
                FileManager.default.fileExists(atPath: candidate.storageURL.path)
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
            var requiresAuthoritativeCloudReconciliation = false
            var activitySidecarRequiresUpload = false
            var performedInitialCloudUpload = false
            if let expectedUserID {
                try migrateLegacyActivityOnlyCloudPreferences(
                    into: candidate,
                    storageKey: expectedStorageKey,
                    userID: expectedUserID
                )
                let localActivityItemsBeforeCoreRestore =
                    try candidate.activityOnlyCloudSnapshotItems()
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
                    guard hadVerifiedLocalSnapshot else {
                        // A first-time cloud account has no owner-bound local state to show.
                        // Keep it behind the retry screen until an authoritative read succeeds.
                        throw error
                    }
                    // Keep the verified local projection usable offline, but never infer a
                    // writable cloud revision from a transport failure. Local changes remain
                    // account-scoped and pending until forceCloudSync performs a full read and
                    // three-way reconciliation; the failed request itself is never replayed as
                    // an upload.
                    cloudError = error
                    requiresAuthoritativeCloudReconciliation = true
                    remoteData = nil
                }

                if requiresAuthoritativeCloudReconciliation {
                    // The local snapshot is published below with cloud writes paused.
                } else if let remoteData {
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
                            let postRestoreActivityItems =
                                try candidate.activityOnlyCloudSnapshotItems()
                            _ = try candidate.applyActivityOnlyCloudItems(
                                localActivityItemsBeforeCoreRestore,
                                expectedLocalItems: postRestoreActivityItems
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
                    performedInitialCloudUpload = true
                    cloudWritesAllowed = true
                }

                if cloudWritesAllowed,
                   !performedInitialCloudUpload,
                   remoteStateLoader == nil {
                    do {
                        activitySidecarRequiresUpload = try await
                            loadAndMergeActivityOnlyCloudSidecar(
                                into: candidate,
                                storageKey: expectedStorageKey,
                                userID: expectedUserID
                            )
                    } catch is CancellationError {
                        return
                    } catch {
                        // The schema-v2 row remains independently usable. Preserve every
                        // local activity and keep its private sidecar visibly pending.
                        cloudError = cloudError ?? error
                        let localItems = try candidate.activityOnlyCloudSnapshotItems()
                        try recordActivityOnlyCloudBaseline(
                            localItems,
                            store: candidate,
                            storageKey: expectedStorageKey,
                            ownerUserID: expectedUserID,
                            clean: false,
                            successfulAt: nil
                        )
                    }
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
            cloudReconciliationRequiredStorageKey =
                requiresAuthoritativeCloudReconciliation ? expectedStorageKey : nil
            publish(store: candidate, activeStorageKey: expectedStorageKey)
            if expectedUserID != nil, cloudSyncStatus == .checking {
                restoreCloudCheckpointStatus(storageKey: expectedStorageKey)
            }
            isPreparingAccount = false
            accountPreparationError = nil
            if (seededExerciseCount > 0 || catalogSeedMarkerChanged ||
                requiresCanonicalCloudUpload || activitySidecarRequiresUpload) &&
                cloudWritesAllowed && remoteStateLoader == nil {
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
                        languageCode: gymCurrentLanguageCode(defaults: defaults)
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
                let activityItemsBeforeCoreRestore =
                    try pending.localStore.activityOnlyCloudSnapshotItems()
                _ = try pending.localStore.restoreBackup(
                    data: preparedBackup.data,
                    activeOwner: pending.owner
                )
                let postRestoreActivityItems =
                    try pending.localStore.activityOnlyCloudSnapshotItems()
                _ = try pending.localStore.applyActivityOnlyCloudItems(
                    activityItemsBeforeCoreRestore,
                    expectedLocalItems: postRestoreActivityItems
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
            cloudReconciliationRequiredStorageKey = nil
            pendingCloudSyncConflict = nil
            cloudSyncConflict = nil
            accountPreparationError = nil
            publish(store: pending.localStore, activeStorageKey: pending.storageKey)
            isPreparingAccount = false
            if remoteStateLoader == nil && (catalogChanged || useCloudVersion) {
                scheduleCloudSave(delay: .zero)
            }
            show(
                message: useCloudVersion
                    ? gymText(
                        "Cloud workout history was loaded on this iPhone.",
                        "Хмарну історію тренувань завантажено на цей iPhone.",
                        languageCode: gymCurrentLanguageCode(defaults: defaults)
                    )
                    : gymText(
                        "This iPhone's workout history was saved to the cloud.",
                        "Історію тренувань із цього iPhone збережено в хмарі.",
                        languageCode: gymCurrentLanguageCode(defaults: defaults)
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
                languageCode: gymCurrentLanguageCode(defaults: defaults)
            )
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    static func cloudWorkoutIdentity(_ backup: GymBackup) throws -> CloudWorkoutIdentity {
        let canonical = try WorkoutStore.canonicalV229CloudWorkoutCore(backup)
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
        checkpoint.activityDirty = true
        checkpoint.activityPending = true
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
        let fullyClean = clean && checkpoint.activityDirty != true &&
            checkpoint.activityPending != true
        cloudSyncStatus = fullyClean
            ? .synced(checkpoint.lastSuccessfulAt ?? Date())
            : .pending
    }

    private func recordActivityOnlyCloudBaseline(
        _ items: [ActivityOnlyWorkoutCloudItem],
        store: WorkoutStore,
        storageKey: String,
        ownerUserID: String,
        clean: Bool,
        successfulAt: Date? = Date()
    ) throws {
        guard store.accountStorageKey == storageKey else {
            throw WorkoutStoreError.storageAccountMismatch
        }
        try ActivityOnlyWorkoutCloudCodec.validate(items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = Data(SHA256.hash(data: try encoder.encode(items)))
        var checkpoint = cloudCheckpoint(for: storageKey)
        if clean {
            let baseline = try ActivityOnlyWorkoutCloudBaseline(
                ownerUserID: ownerUserID,
                items: items
            )
            try store.saveActivityOnlyCloudBaseline(baseline)
            checkpoint.activityBaselineDigest = digest
        }
        checkpoint.activityDirty = !clean
        checkpoint.activityPending = !clean
        if clean, let successfulAt { checkpoint.lastSuccessfulAt = successfulAt }
        persistCloudCheckpoint(checkpoint, storageKey: storageKey)
        let fullyClean = !checkpoint.dirty && !checkpoint.pending && clean
        cloudSyncStatus = fullyClean
            ? .synced(checkpoint.lastSuccessfulAt ?? Date())
            : .pending
    }

    private func restoreCloudCheckpointStatus(storageKey: String) {
        let checkpoint = cloudCheckpoint(for: storageKey)
        if checkpoint.pending || checkpoint.dirty ||
            checkpoint.activityPending == true || checkpoint.activityDirty == true {
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
        // A zero-delay canonical save can still be in flight immediately after account
        // activation. Let that request establish (or reject) its CAS revision before a
        // user-requested sync begins. Store mutations that arrive while either request is
        // awaiting the network are queued and serialized behind the manual reconciliation.
        guard manualCloudSyncLease == nil else { return }
        let manualLease = ManualCloudSyncLease(
            accountGeneration: accountActivationGeneration,
            storageKey: session.storageKey,
            userID: cloud.userID
        )
        manualCloudSyncLease = manualLease
        defer { finishManualCloudSyncScheduling(lease: manualLease) }

        let scheduledSave = pendingCloudSave
        if cloudSavePhase == .debouncing {
            scheduledSave?.cancel()
        }
        await scheduledSave?.value
        guard manualCloudSyncLease == manualLease else { return }
        // Any mutation observed while the older save was settling is part of the fresh
        // store snapshot below. Newer mutations will set this flag again at the next await.
        cloudSaveQueued = false

        guard isAccountReady,
              accountActivationGeneration == manualLease.accountGeneration,
              workoutStore.accountStorageKey == session.storageKey,
              auth.session?.storageKey == session.storageKey,
              auth.session?.cloud?.userID == cloud.userID else {
            return
        }
        guard cloudWritableAccountStorageKey == session.storageKey else {
            if cloudReconciliationRequiredStorageKey == session.storageKey {
                await reconcileStaleManualSync(
                    store: workoutStore,
                    session: session,
                    userID: cloud.userID,
                    owner: Self.backupOwner(
                        for: session,
                        fallbackStorageKey: session.storageKey
                    )
                )
                return
            }
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
                  self.accountActivationGeneration == manualLease.accountGeneration,
                  self.workoutStore === store,
                  self.auth.session?.storageKey == session.storageKey,
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
            guard accountActivationGeneration == manualLease.accountGeneration,
                  auth.session?.storageKey == session.storageKey,
                  auth.session?.cloud?.userID == cloud.userID else {
                return
            }
            cloudSyncStatus = .failed(gymSafeEnglishErrorMessage(error))
            show(error: error)
        }
    }

    private func finishManualCloudSyncScheduling(lease: ManualCloudSyncLease) {
        guard manualCloudSyncLease == lease else { return }
        let shouldRunQueuedSave = cloudSaveQueued &&
            !isSigningOut &&
            isAccountReady &&
            accountActivationGeneration == lease.accountGeneration &&
            auth.session?.storageKey == lease.storageKey &&
            auth.session?.cloud?.userID == lease.userID &&
            cloudWritableAccountStorageKey == lease.storageKey &&
            pendingCloudSyncConflict == nil &&
            cloudSyncConflict == nil &&
            cloudSyncStatus != .conflict
        cloudSaveQueued = false
        manualCloudSyncLease = nil
        if shouldRunQueuedSave {
            scheduleCloudSave()
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
            let activityItemsBeforeCore = try store.activityOnlyCloudSnapshotItems()
            let preparedPendingActivityReport = try await
                replayPendingActivityOnlySyncIfNeeded(
                    store: store,
                    storageKey: storageKey,
                    userID: userID
                )
            if let preparedPendingActivityReport {
                try recordActivityOnlyCloudBaseline(
                    preparedPendingActivityReport.localItems,
                    store: store,
                    storageKey: storageKey,
                    ownerUserID: userID,
                    clean: false,
                    successfulAt: nil
                )
            }
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
                        expectedUserID: userID,
                        preparedActivityReport: preparedPendingActivityReport,
                        activityPendingAlreadyReplayed: true
                    )
                }
                cloudWritableAccountStorageKey = storageKey
                cloudReconciliationRequiredStorageKey = nil
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
                try await finishManualActivityOnlyCloudSync(
                    store: store,
                    storageKey: storageKey,
                    userID: userID,
                    preparedPendingReport: preparedPendingActivityReport
                )
                cloudWritableAccountStorageKey = storageKey
                cloudReconciliationRequiredStorageKey = nil
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
                        expectedUserID: userID,
                        preparedActivityReport: preparedPendingActivityReport,
                        activityPendingAlreadyReplayed: true
                    )
                }
                cloudWritableAccountStorageKey = storageKey
                cloudReconciliationRequiredStorageKey = nil
                show(message: "Cloud data is up to date.", isError: false)
                return
            }

            if baselineDigest == Self.cloudIdentityDigest(localIdentity) {
                // Only the cloud changed. This is a whole-state fast-forward, not a merge.
                try performCloudStoreMutation {
                    _ = try store.restoreBackup(data: prepared.data, activeOwner: owner)
                    _ = try store.seedBuiltInExercises()
                    _ = try store.seedDefaultMuscleMappings()
                    let postRestoreActivityItems = try store.activityOnlyCloudSnapshotItems()
                    _ = try store.applyActivityOnlyCloudItems(
                        activityItemsBeforeCore,
                        expectedLocalItems: postRestoreActivityItems
                    )
                }
                recordCloudBaseline(remoteIdentity, storageKey: storageKey, clean: true)
                try await finishManualActivityOnlyCloudSync(
                    store: store,
                    storageKey: storageKey,
                    userID: userID,
                    preparedPendingReport: preparedPendingActivityReport
                )
                cloudWritableAccountStorageKey = storageKey
                cloudReconciliationRequiredStorageKey = nil
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
            let friendCode: String
            do {
                friendCode = try await self.cloudSync.socialMyFriendCode(
                    expectedUserID: cloud.userID
                )
            } catch CloudSyncError.postgRESTFailure(let statusCode, let code, _)
                        where statusCode == 404 && (code == "PGRST202" || code == "42883") {
                // The short-code RPC is deployed independently. Older backends keep
                // working with the dashboard's opaque legacy p_ code.
                friendCode = dashboard.currentUser.friendCode
            }
            try Task.checkCancellation()
            guard self.isAccountReady,
                  self.accountActivationGeneration == generation,
                  self.workoutStore === store,
                  self.auth.session?.storageKey == session.storageKey,
                  self.auth.session?.cloud?.userID == cloud.userID,
                  self.socialCacheGeneration == cacheGeneration else {
                throw AuthServiceError.sessionChanged
            }
            self.socialDashboard = dashboard
            self.socialFriendCode = friendCode
            self.markSocialSurfaceReconciled(.dashboard)
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

    func socialFriendWorkoutPage(
        profileID: String,
        expectedActivityRevision: String? = nil
    ) async throws -> SocialFriendWorkoutPage? {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let page = try await cloudSync.socialFriendWorkoutPage(
            profileID: profileID,
            expectedActivityRevision: expectedActivityRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        return page
    }

    func socialFriendWorkoutDetailCapability(
        profileID: String
    ) async throws -> SocialFriendWorkoutDetailCapability {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let capability = try await cloudSync.socialFriendWorkoutDetailCapability(
            profileID: profileID,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        return capability
    }

    func refreshSocialWorkoutDetailPrivacy() async throws -> SocialWorkoutDetailPrivacy {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let privacy = try await cloudSync.socialWorkoutDetailPrivacy(
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        socialWorkoutDetailPrivacy = privacy
        markSocialSurfaceReconciled(.workoutDetailPrivacy)
        return privacy
    }

    func sendFriendRequest(friendCode: String) async throws {
        let context = try socialContext()
        guard let normalizedFriendCode = SocialFriendCode.normalize(friendCode) else {
            throw CloudSyncError.invalidSocialProfile
        }
        // If the RPC commits but its response is lost, an old request action must
        // not remain reusable from a dashboard read started before this mutation.
        invalidateSocialDashboardCache()
        try await cloudSync.socialSendFriendRequest(
            friendCode: normalizedFriendCode,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard]
        )
    }

    func respondFriendRequest(
        _ request: SocialFriendRequest,
        accept: Bool
    ) async throws {
        let context = try socialContext()
        guard socialDashboard?.incoming.contains(request) == true else {
            throw CloudSyncError.invalidFriendship
        }
        invalidateSocialRelationshipCaches()
        _ = try await cloudSync.socialRespondFriendRequest(
            friendshipID: request.friendshipID,
            decision: accept ? "accept" : "decline",
            expectedRevision: request.friendshipRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutInbox]
        )
    }

    func cancelFriendRequest(_ request: SocialFriendRequest) async throws {
        let context = try socialContext()
        guard socialDashboard?.outgoing.contains(request) == true else {
            throw CloudSyncError.invalidFriendship
        }
        invalidateSocialRelationshipCaches()
        _ = try await cloudSync.socialCancelFriendRequest(
            friendshipID: request.friendshipID,
            expectedRevision: request.friendshipRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutInbox]
        )
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
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutInbox]
        )
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
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutInbox]
        )
    }

    func unblockSocialProfile(profileID: String) async throws {
        let context = try socialContext()
        invalidateSocialRelationshipCaches()
        let result = try await cloudSync.socialUnblockProfile(
            profileID: profileID,
            expectedUserID: context.userID
        )
        guard result.profileID == profileID, !result.blocked else {
            throw CloudSyncError.invalidResponse
        }
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutInbox]
        )
    }

    func updateSocialPrivacy(_ privacy: SocialPrivacy) async throws {
        let context = try socialContext()
        guard let current = socialDashboard?.currentUser else {
            throw CloudSyncError.invalidResponse
        }
        invalidateSocialDashboardCache()
        let result = try await cloudSync.socialUpdatePrivacy(
            privacy,
            expectedRevision: current.settingsRevision,
            expectedUserID: context.userID
        )
        guard result.0 == privacy else { throw CloudSyncError.invalidResponse }
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.dashboard, .workoutDetailPrivacy]
        )
    }

    func updateSocialWorkoutDetailPrivacy(_ enabled: Bool) async throws {
        let context = try socialContext()
        guard let current = socialWorkoutDetailPrivacy else {
            throw CloudSyncError.invalidResponse
        }
        invalidateSocialWorkoutDetailPrivacyCache()
        let result = try await cloudSync.socialUpdateWorkoutDetailPrivacy(
            enabled,
            expectedRevision: current.settingsRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        socialWorkoutDetailPrivacy = result
        socialDashboardRefreshRevision &+= 1
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
        markSocialSurfaceReconciled(.workoutInbox)
        return inbox
    }

    func loadMoreSocialWorkoutInbox() async throws -> SocialWorkoutInbox {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        guard let current = socialWorkoutInbox else {
            throw CloudSyncError.invalidResponse
        }
        guard current.nextCursor != nil else { return current }
        let maximumNewRows = min(
            SocialPayloadParser.workoutInboxPageLimit,
            SocialPayloadParser.workoutInboxMaximumIncomingCount - current.incoming.count
        )
        guard maximumNewRows > 0 else { return current }

        var merged = current
        var loadedRows = 0
        while loadedRows < maximumNewRows, let cursor = merged.nextCursor {
            let limit = min(
                SocialPayloadParser.workoutInboxPageLimit,
                maximumNewRows - loadedRows,
                SocialPayloadParser.workoutInboxMaximumIncomingCount - merged.incoming.count
            )
            guard limit > 0 else { break }
            try validateSocialContext(context)
            guard socialCacheGeneration == cacheGeneration,
                  socialWorkoutInbox == current else {
                throw AuthServiceError.sessionChanged
            }
            let page = try await cloudSync.socialWorkoutInboxPage(
                after: cursor,
                limit: limit,
                expectedUserID: context.userID
            )
            try validateSocialContext(context)
            guard socialCacheGeneration == cacheGeneration,
                  socialWorkoutInbox == current else {
                throw AuthServiceError.sessionChanged
            }
            if current.pendingIncomingCount != page.pendingIncomingCount
                || current.outgoing != page.outgoing {
                // A valid page can still belong to a newer server snapshot (privacy,
                // cancellation, expiry, or another device changed the list between
                // requests). Never splice revisions and never leave the stale cursor
                // as the next retry target. Invalidate it, then perform exactly one
                // bounded first-page read for this same account/generation.
                socialWorkoutInbox = nil
                let refreshed = try await cloudSync.socialWorkoutInbox(
                    expectedUserID: context.userID
                )
                try validateSocialContext(context)
                guard socialCacheGeneration == cacheGeneration,
                      socialWorkoutInbox == nil else {
                    throw AuthServiceError.sessionChanged
                }
                socialWorkoutInbox = refreshed
                markSocialSurfaceReconciled(.workoutInbox)
                return refreshed
            }
            let previousCount = merged.incoming.count
            merged = try SocialPayloadParser.mergingWorkoutInboxPage(
                page,
                into: merged,
                after: cursor
            )
            loadedRows += merged.incoming.count - previousCount
        }
        socialWorkoutInbox = merged
        return merged
    }

    func resolveSocialWorkoutInvite(
        inviteID: String,
        minimumRevision: Int
    ) async throws -> Bool {
        guard SocialPayloadParser.isValidInviteID(inviteID),
              (1 ... 2_147_483_647).contains(minimumRevision),
              socialWorkoutInbox != nil else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        for pageIndex in 0 ..< SocialPayloadParser.workoutInboxMaximumPageCount {
            guard let inbox = socialWorkoutInbox else {
                throw CloudSyncError.invalidResponse
            }
            if let invite = inbox.incoming.first(where: { $0.inviteID == inviteID })
                ?? inbox.outgoing.first(where: { $0.inviteID == inviteID }) {
                return invite.inviteRevision >= minimumRevision
            }
            guard inbox.nextCursor != nil,
                  pageIndex + 1 < SocialPayloadParser.workoutInboxMaximumPageCount else {
                return false
            }
            _ = try await loadMoreSocialWorkoutInbox()
        }
        return false
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
        let requestStore = try WorkoutInviteRequestStore(
            accountStorageKey: requestKey.storageKey,
            userID: requestKey.userID,
            workoutStorageURL: workoutStore.storageURL
        )
        let clientRequestID = try requestStore.requestID(
            profileID: requestKey.profileID,
            canonicalWorkoutDigest: requestKey.canonicalWorkoutDigest
        )

        try await cloudSync.socialSendWorkoutInvite(
            profileID: profileID,
            clientRequestID: clientRequestID,
            workout: plan,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        // The server has confirmed this idempotency key. If the local cleanup
        // itself fails, retaining the same key is conservative: a later retry
        // can only ask the server to return the already committed result.
        try? requestStore.confirm(
            profileID: requestKey.profileID,
            canonicalWorkoutDigest: requestKey.canonicalWorkoutDigest,
            clientRequestID: clientRequestID
        )
        invalidateSocialWorkoutInboxCache()
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.workoutInbox]
        )
    }

    func respondWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        accept: Bool,
        replacingPendingSharedWorkoutID: UUID? = nil
    ) async throws -> SharedWorkoutPlan? {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        guard invite.status == .pending,
              socialWorkoutInbox?.incoming.contains(invite) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let pendingSharedWorkoutID = pendingSharedWorkout?.id
        if accept {
            guard replacingPendingSharedWorkoutID == pendingSharedWorkoutID else {
                throw CloudSyncError.invalidWorkoutInvite
            }
        }
        let acceptedPlan: SharedWorkoutPlan?
        if accept {
            let plan = try await workoutInvitePlan(
                for: invite,
                context: context,
                cacheGeneration: cacheGeneration
            )
            guard pendingSharedWorkout?.id == pendingSharedWorkoutID else {
                throw CloudSyncError.invalidWorkoutInvite
            }
            // The social wire contract intentionally does not infer local catalog aliases.
            // Preflight the local-copy boundary before accepting so a server-portable plan
            // that is ambiguous on this device stays pending and does not mutate remotely.
            try validateWorkoutInviteForLocalImport(plan)
            acceptedPlan = plan
        } else {
            acceptedPlan = nil
        }
        let result = try await cloudSync.socialRespondWorkoutInvite(
            inviteID: invite.inviteID,
            decision: accept ? "accept" : "decline",
            expectedRevision: invite.inviteRevision,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration else {
            throw AuthServiceError.sessionChanged
        }
        if accept {
            guard result.status == .accepted,
                  let acceptedPlan,
                  result.workout == acceptedPlan else {
                throw CloudSyncError.invalidResponse
            }
            try stageWorkoutInvitePlan(
                acceptedPlan,
                replacingPendingID: replacingPendingSharedWorkoutID
            )
        } else if result.status != .declined || result.workout != nil {
            throw CloudSyncError.invalidResponse
        }
        // The mutation is confirmed. Remove the stale action before the refetch so a
        // transient read failure cannot invite a duplicate response with a new UI task.
        invalidateSocialWorkoutInboxCache()
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.workoutInbox]
        )
        return acceptedPlan
    }

    func recoverAcceptedWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        replacingPendingSharedWorkoutID: UUID? = nil
    ) async throws -> SharedWorkoutPlan {
        let context = try socialContext()
        let cacheGeneration = socialCacheGeneration
        let pendingSharedWorkoutID = pendingSharedWorkout?.id
        guard invite.status == .accepted,
              socialWorkoutInbox?.incoming.contains(invite) == true,
              socialDashboard?.friends.contains(where: { $0.profileID == invite.profileID }) == true,
              replacingPendingSharedWorkoutID == pendingSharedWorkoutID else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let plan = try await workoutInvitePlan(
            for: invite,
            context: context,
            cacheGeneration: cacheGeneration
        )
        guard pendingSharedWorkout?.id == pendingSharedWorkoutID,
              socialDashboard?.friends.contains(where: {
                  $0.profileID == invite.profileID
              }) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
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
        invalidateSocialWorkoutInboxCache()
        let result = try await cloudSync.socialCancelWorkoutInvite(
            inviteID: invite.inviteID,
            expectedRevision: invite.inviteRevision,
            expectedUserID: context.userID
        )
        guard result.status == .cancelled else { throw CloudSyncError.invalidResponse }
        try validateSocialContext(context)
        try await reconcileConfirmedSocialMutation(
            context: context,
            surfaces: [.workoutInbox]
        )
    }

    private struct SocialReconciliationSurfaces: OptionSet, Sendable {
        let rawValue: Int

        static let dashboard = Self(rawValue: 1 << 0)
        static let workoutInbox = Self(rawValue: 1 << 1)
        static let workoutDetailPrivacy = Self(rawValue: 1 << 2)
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
        socialFriendCode = nil
        socialWorkoutInbox = nil
        // FriendDetailView keys its refetch lifecycle to this revision. Increment it
        // synchronously so visible private data disappears before the mutation awaits.
        socialDashboardRefreshRevision &+= 1
    }

    private func invalidateSocialDashboardCache() {
        socialCacheGeneration &+= 1
        socialDashboard = nil
        socialFriendCode = nil
        socialDashboardRefreshRevision &+= 1
    }

    private func invalidateSocialWorkoutInboxCache() {
        socialCacheGeneration &+= 1
        socialWorkoutInbox = nil
    }

    private func invalidateSocialWorkoutDetailPrivacyCache() {
        socialCacheGeneration &+= 1
        socialWorkoutDetailPrivacy = nil
        socialDashboardRefreshRevision &+= 1
    }

    /// Once a mutation response has been validated, only authoritative reads are
    /// retried. The mutating RPC is never replayed merely because a read failed.
    private func reconcileConfirmedSocialMutation(
        context: SocialContext,
        surfaces: SocialReconciliationSurfaces
    ) async throws {
        try validateSocialContext(context)
        pendingSocialReconciliationSurfaces.formUnion(surfaces)
        isRestoringConfirmedSocialMutation = true
        try await attemptPendingSocialReconciliation(context: context)
        try validateSocialContext(context)
        guard !pendingSocialReconciliationSurfaces.isEmpty else { return }
        schedulePendingSocialReconciliation(context: context)
    }

    private func attemptPendingSocialReconciliation(
        context: SocialContext
    ) async throws {
        let requested = pendingSocialReconciliationSurfaces
        if requested.contains(.dashboard) {
            do {
                _ = try await refreshSocialDashboard()
            } catch {
                try validateSocialContext(context)
            }
        }
        if requested.contains(.workoutInbox) {
            do {
                _ = try await refreshSocialWorkoutInbox()
            } catch {
                try validateSocialContext(context)
            }
        }
        if requested.contains(.workoutDetailPrivacy) {
            do {
                _ = try await refreshSocialWorkoutDetailPrivacy()
            } catch {
                try validateSocialContext(context)
            }
        }
        try validateSocialContext(context)
    }

    private func markSocialSurfaceReconciled(_ surface: SocialReconciliationSurfaces) {
        pendingSocialReconciliationSurfaces.subtract(surface)
        isRestoringConfirmedSocialMutation = !pendingSocialReconciliationSurfaces.isEmpty
    }

    private func schedulePendingSocialReconciliation(context: SocialContext) {
        guard socialReconciliationTask == nil,
              !pendingSocialReconciliationSurfaces.isEmpty else { return }
        let taskID = UUID()
        socialReconciliationTaskID = taskID
        socialReconciliationTask = Task { [weak self] in
            guard let self else { return }
            let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(12)]
            for delay in delays {
                do {
                    try await Task.sleep(for: delay)
                    try Task.checkCancellation()
                    guard self.socialReconciliationTaskID == taskID else { return }
                    try await self.attemptPendingSocialReconciliation(context: context)
                    guard !self.pendingSocialReconciliationSurfaces.isEmpty else { break }
                } catch {
                    break
                }
            }
            guard self.socialReconciliationTaskID == taskID else { return }
            self.socialReconciliationTask = nil
            self.socialReconciliationTaskID = nil
            self.isRestoringConfirmedSocialMutation =
                !self.pendingSocialReconciliationSurfaces.isEmpty
        }
    }

    private func validateWorkoutInviteForLocalImport(_ plan: SharedWorkoutPlan) throws {
        do {
            _ = try SharedWorkoutLinkValidator.validate(plan)
        } catch {
            throw CloudSyncError.invalidWorkoutInvite
        }
    }

    private func workoutInvitePlan(
        for invite: SocialWorkoutInvite,
        context: SocialContext,
        cacheGeneration: UInt64
    ) async throws -> SharedWorkoutPlan {
        guard socialWorkoutInbox?.incoming.contains(invite) == true else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let plan = try await cloudSync.socialWorkoutInvitePlan(
            inviteID: invite.inviteID,
            expectedRevision: invite.inviteRevision,
            legacyWorkout: invite.workout,
            expectedUserID: context.userID
        )
        try validateSocialContext(context)
        guard socialCacheGeneration == cacheGeneration,
              socialWorkoutInbox?.incoming.contains(invite) == true,
              invite.summary.exerciseCount == plan.exercises.count,
              invite.summary.setCount == plan.totalSetCount,
              invite.summary.exerciseNames == plan.exercises.map(\.name) else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        return plan
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
            storageKey: context.storageKey,
            userID: context.userID,
            profileID: profileID,
            canonicalWorkoutDigest: Data(SHA256.hash(data: canonicalWorkout))
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
        expectedCloudUserID: String?,
        currentPassword: String? = nil
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

        try PendingAccountDeletionStore.requireNoPendingDeletion(defaults: defaults)
        try ensureDeletionTargetIsCurrent(target)
        accountDeletionGeneration &+= 1
        let generation = accountDeletionGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performAccountDeletion(target, currentPassword: currentPassword)
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

    private func performAccountDeletion(
        _ target: AccountDeletionTarget,
        currentPassword: String?
    ) async throws {
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
            // Local profiles have no request boundary, so persist before cleanup.
            try PendingAccountDeletionStore.begin(storageKey, defaults: defaults)
            auth.pendingAccountDeletionStateDidChange()
        }

        var requestDisposition = AccountDeletionRequestDisposition.notDispatched
        do {
            try ensureDeletionTargetIsCurrent(target, deletingStore: deletingStore)
            if let cloudUserID = target.cloudUserID {
                await nativePushManager?.prepareForSessionEnd(expectedUserID: cloudUserID)
                try await auth.deleteCloudAccountOnServer(
                    expectedUserID: cloudUserID,
                    currentPassword: currentPassword ?? "",
                    beforeRequest: {
                        // This throwing hook runs immediately before each actual
                        // DELETE URLSession load (including a retry). An initial
                        // token refresh therefore remains marker-free, while a
                        // failed durable write prevents the DELETE from dispatching.
                        try PendingAccountDeletionStore.begin(
                            storageKey,
                            defaults: self.defaults
                        )
                        self.auth.pendingAccountDeletionStateDidChange()
                    },
                    onRequestDispositionChange: { disposition in
                        requestDisposition = disposition
                        switch disposition {
                        case .outcomeUnknown:
                            break
                        case .notDispatched, .definitivelyRejected:
                            // A bounded 4xx proves that this request attempt did not
                            // delete the account. Clear before a possible token refresh;
                            // the retry's throwing hook must persist it again.
                            if PendingAccountDeletionStore.clearExact(
                                storageKey,
                                defaults: self.defaults
                            ) {
                                self.auth.pendingAccountDeletionStateDidChange()
                            }
                        }
                    }
                )
            }
        } catch {
            if requestDisposition != .outcomeUnknown {
                if let cloudUserID = target.cloudUserID {
                    await nativePushManager?.resumeAfterFailedSessionEnd(
                        expectedUserID: cloudUserID
                    )
                }
                // No delete request crossed the network boundary, or the server returned an
                // authoritative 4xx rejection. The local account remains authoritative.
                if PendingAccountDeletionStore.clearExact(
                    storageKey,
                    defaults: defaults
                ) {
                    auth.pendingAccountDeletionStateDidChange()
                }
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
        TrainingProfileStore(defaults: defaults).clear(accountStorageKey: storageKey)
        AppTutorialStore(defaults: defaults).clear(accountStorageKey: storageKey)
        defaults.removeObject(forKey: Self.hiddenLeaderboardProfilesKey)
        defaults.removeObject(
            forKey: leaderboardHiddenProfilesDefaultsKey(for: storageKey)
        )

        do {
            try ExerciseMediaStore.clearAccount(
                ownerKey: storageKey,
                mediaDirectoryURL: exerciseMediaDirectoryURL,
                fileManager: exerciseMediaFileManager
            )
        } catch {
            cleanupError = cleanupError ?? error
        }

        do {
            try deletingStore.destroyAccountData()
        } catch {
            cleanupError = error
        }
        do {
            try auth.removeSavedLocalProfile(storageKey: storageKey)
        } catch {
            cleanupError = cleanupError ?? error
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
        if !Self.clearActivityOnlyCloudDeletionArtifacts(
            defaults: defaults,
            storageKey: storageKey
        ) {
            cleanupError = cleanupError ?? AuthServiceError.accountDeletionCleanupPending
        }

        guard cleanupError == nil else {
            // The marker intentionally survives. Startup retries secure local cleanup before
            // exposing any account UI, including after a server-side account was deleted.
            throw cleanupError!
        }

        guard PendingAccountDeletionStore.clearExact(
            storageKey,
            defaults: defaults
        ) else {
            throw AuthServiceError.accountDeletionCleanupPending
        }
        auth.pendingAccountDeletionStateDidChange()
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
            // WorkoutStore is MainActor-isolated and ObservableObjectPublisher delivers
            // synchronously. Handle the mutation in that same turn so a manual sync can
            // reliably cancel the resulting debounce instead of racing a queued Task that
            // may schedule a second CAS write after reconciliation has already started.
            MainActor.assumeIsolated {
                guard let self else { return }
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

    private func performCloudStoreMutation<T>(
        _ mutation: () throws -> T
    ) rethrows -> T {
        let wasApplyingRemoteState = applyingRemoteState
        applyingRemoteState = true
        defer { applyingRemoteState = wasApplyingRemoteState }
        return try mutation()
    }

    private func scheduleCloudSave(delay: Duration = .milliseconds(1_500)) {
        guard !isSigningOut,
              isAccountReady,
              let session = auth.session,
              let cloud = session.cloud else { return }
        if manualCloudSyncLease != nil {
            cloudSaveQueued = true
            return
        }
        guard cloudWritableAccountStorageKey == session.storageKey else { return }
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

    private func loadAndMergeActivityOnlyCloudSidecar(
        into store: WorkoutStore,
        storageKey: String,
        userID: String
    ) async throws -> Bool {
        let report = try await synchronizeActivityOnlyCloudSidecar(
            store: store,
            storageKey: storageKey,
            userID: userID
        )
        return !report.clean
    }

    private func ensureCurrentActivityOnlyOwner(
        store: WorkoutStore,
        storageKey: String,
        userID: String
    ) throws {
        guard store.accountStorageKey == storageKey,
              auth.session?.storageKey == storageKey,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
    }

    private func submitExactPendingActivityOnlySync(
        _ pending: PendingActivityOnlyWorkoutCloudSync,
        store: WorkoutStore,
        storageKey: String,
        userID: String
    ) async throws -> ActivityOnlyWorkoutCloudSyncResult {
        guard let requestID = pending.requestUUID else {
            throw CloudSyncError.invalidPayload
        }
        for attempt in 0 ..< 2 {
            do {
                return try await cloudSync.syncActivityOnlyWorkouts(
                    expectedRevision: pending.expectedRevision,
                    requestID: requestID,
                    items: pending.items,
                    exactRequestBody: pending.requestBody,
                    expectedUserID: userID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt == 0,
                      Self.activityOnlyOutcomeRequiresExactReplay(error) else {
                    throw error
                }
                try await Task.sleep(for: .milliseconds(250))
                try ensureCurrentActivityOnlyOwner(
                    store: store,
                    storageKey: storageKey,
                    userID: userID
                )
            }
        }
        throw CloudSyncError.invalidResponse
    }

    /// Replays an outcome-unknown full-snapshot request before any fresh read or
    /// materialization. A non-nil report means the exact request remains pending and
    /// the caller must not create or reconcile a replacement sidecar request yet.
    private func replayPendingActivityOnlySyncIfNeeded(
        store: WorkoutStore,
        storageKey: String,
        userID: String
    ) async throws -> ActivityOnlyCloudSyncReport? {
        try ensureCurrentActivityOnlyOwner(
            store: store,
            storageKey: storageKey,
            userID: userID
        )
        try migrateLegacyActivityOnlyCloudPreferences(
            into: store,
            storageKey: storageKey,
            userID: userID
        )
        guard let pending = store.loadPendingActivityOnlyCloudSync(
            ownerUserID: userID
        ) else { return nil }

        let result = try await submitExactPendingActivityOnlySync(
            pending,
            store: store,
            storageKey: storageKey,
            userID: userID
        )
        try ensureCurrentActivityOnlyOwner(
            store: store,
            storageKey: storageKey,
            userID: userID
        )
        switch result {
        case .unavailable, .rateLimited:
            return ActivityOnlyCloudSyncReport(
                localItems: try store.activityOnlyCloudSnapshotItems(),
                clean: false
            )
        case .synced, .conflict, .requestConflict:
            // A confirmed replay or a known rejected CAS outcome releases this UUID.
            // Conflict cases proceed to a fresh authoritative read with a new UUID.
            try store.clearPendingActivityOnlyCloudSync()
            return nil
        case .invalidPayload:
            try store.clearPendingActivityOnlyCloudSync()
            throw CloudSyncError.invalidPayload
        case .revisionExhausted:
            try store.clearPendingActivityOnlyCloudSync()
            throw CloudSyncError.requestFailed(
                "The activity-only cloud revision is exhausted. Local activities remain preserved."
            )
        }
    }

    private func migrateLegacyActivityOnlyCloudPreferences(
        into store: WorkoutStore,
        storageKey: String,
        userID: String
    ) throws {
        if store.loadPendingActivityOnlyCloudSync(ownerUserID: userID) == nil,
           let legacyPending =
            LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.loadForMigration(
                defaults: defaults,
                storageKey: storageKey,
                ownerUserID: userID
            ) {
            try store.savePendingActivityOnlyCloudSync(legacyPending)
        }
        if store.loadActivityOnlyCloudBaseline(ownerUserID: userID) == nil,
           let legacyBaseline =
            LegacyActivityOnlyWorkoutCloudBaselinePreferences.loadForMigration(
                defaults: defaults,
                storageKey: storageKey,
                ownerUserID: userID
            ) {
            try store.saveActivityOnlyCloudBaseline(legacyBaseline)
        }
        guard LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.clearAndVerify(
            defaults: defaults,
            storageKey: storageKey
        ),
        LegacyActivityOnlyWorkoutCloudBaselinePreferences.clearAndVerify(
            defaults: defaults,
            storageKey: storageKey
        ) else {
            throw WorkoutStoreError.persistenceFailure(
                "Legacy activity-only cloud preferences could not be removed safely."
            )
        }
    }

    private func synchronizeActivityOnlyCloudSidecar(
        store: WorkoutStore,
        storageKey: String,
        userID: String,
        pendingAlreadyReplayed: Bool = false
    ) async throws -> ActivityOnlyCloudSyncReport {
        func currentLocalItems() throws -> [ActivityOnlyWorkoutCloudItem] {
            try store.activityOnlyCloudSnapshotItems()
        }
        func report(
            _ items: [ActivityOnlyWorkoutCloudItem],
            clean: Bool
        ) throws -> ActivityOnlyCloudSyncReport {
            try recordActivityOnlyCloudBaseline(
                items,
                store: store,
                storageKey: storageKey,
                ownerUserID: userID,
                clean: clean,
                successfulAt: clean ? Date() : nil
            )
            return ActivityOnlyCloudSyncReport(localItems: items, clean: clean)
        }
        try ensureCurrentActivityOnlyOwner(
            store: store,
            storageKey: storageKey,
            userID: userID
        )

        if !pendingAlreadyReplayed,
           let pendingReport = try await replayPendingActivityOnlySyncIfNeeded(
            store: store,
            storageKey: storageKey,
            userID: userID
           ) {
            return try report(pendingReport.localItems, clean: false)
        }

        let baselineItems = store.loadActivityOnlyCloudBaseline(
            ownerUserID: userID
        )?.items ?? []

        for attempt in 0 ..< 2 {
            let readResult = try await cloudSync.loadActivityOnlyWorkouts(
                expectedUserID: userID
            )
            try ensureCurrentActivityOnlyOwner(
                store: store,
                storageKey: storageKey,
                userID: userID
            )
            guard case .snapshot(let snapshot) = readResult else {
                return try report(try currentLocalItems(), clean: false)
            }

            let localItems = try currentLocalItems()
            let reconciled = try ActivityOnlyWorkoutCloudCodec.reconciledItems(
                base: baselineItems,
                remote: snapshot.items,
                local: localItems,
                coreWorkoutTimestamps: ActivityOnlyWorkoutCloudCodec.coreWorkoutTimestamps(
                    store.workouts
                )
            )
            _ = try performCloudStoreMutation {
                try store.applyActivityOnlyCloudItems(
                    reconciled.outbound,
                    expectedLocalItems: localItems
                )
            }
            try ensureCurrentActivityOnlyOwner(
                store: store,
                storageKey: storageKey,
                userID: userID
            )
            let mergedLocalItems = try currentLocalItems()
            guard reconciled.outbound != snapshot.items else {
                return try report(mergedLocalItems, clean: true)
            }

            let pending = try PendingActivityOnlyWorkoutCloudSync(
                ownerUserID: userID,
                expectedRevision: snapshot.revision,
                items: reconciled.outbound
            )
            try store.savePendingActivityOnlyCloudSync(pending)
            let result = try await submitExactPendingActivityOnlySync(
                pending,
                store: store,
                storageKey: storageKey,
                userID: userID
            )
            try ensureCurrentActivityOnlyOwner(
                store: store,
                storageKey: storageKey,
                userID: userID
            )
            switch result {
            case .synced:
                try store.clearPendingActivityOnlyCloudSync()
                return try report(try currentLocalItems(), clean: true)
            case .unavailable, .rateLimited:
                // Keep the exact pending tuple for the next bounded retry.
                return try report(try currentLocalItems(), clean: false)
            case .conflict, .requestConflict:
                try store.clearPendingActivityOnlyCloudSync()
                if attempt == 0 { continue }
                throw CloudSyncError.requestFailed(
                    "Activity-only cloud data changed repeatedly. Local and remote activities remain preserved."
                )
            case .invalidPayload:
                try store.clearPendingActivityOnlyCloudSync()
                throw CloudSyncError.invalidPayload
            case .revisionExhausted:
                try store.clearPendingActivityOnlyCloudSync()
                throw CloudSyncError.requestFailed(
                    "The activity-only cloud revision is exhausted. Local activities remain preserved."
                )
            }
        }
        throw CloudSyncError.staleRemoteState
    }

    static func activityOnlyOutcomeRequiresExactReplay(_ error: Error) -> Bool {
        if case CloudSyncError.postgRESTFailure(_, let code, _) = error {
            return code == "55P03" || code == "57014"
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return false
    }

    private func finishManualActivityOnlyCloudSync(
        store: WorkoutStore,
        storageKey: String,
        userID: String,
        preparedPendingReport: ActivityOnlyCloudSyncReport?
    ) async throws {
        let report: ActivityOnlyCloudSyncReport
        if let preparedPendingReport {
            report = preparedPendingReport
        } else {
            report = try await synchronizeActivityOnlyCloudSidecar(
                store: store,
                storageKey: storageKey,
                userID: userID,
                pendingAlreadyReplayed: true
            )
        }
        let currentItems = try store.activityOnlyCloudSnapshotItems()
        try recordActivityOnlyCloudBaseline(
            report.localItems,
            store: store,
            storageKey: storageKey,
            ownerUserID: userID,
            clean: report.clean && currentItems == report.localItems
        )
    }

    private func uploadCurrentState(
        from store: WorkoutStore,
        owner: BackupOwner,
        expectedStorageKey: String,
        expectedUserID: String,
        preparedActivityReport: ActivityOnlyCloudSyncReport? = nil,
        activityPendingAlreadyReplayed: Bool = false
    ) async throws {
        guard store.accountStorageKey == expectedStorageKey,
              auth.session?.storageKey == expectedStorageKey,
              auth.session?.cloud?.userID == expectedUserID,
              owner.accountID == expectedUserID,
              owner.userID == expectedUserID else {
            throw AuthServiceError.sessionChanged
        }
        let activityReport: ActivityOnlyCloudSyncReport
        if let preparedActivityReport {
            activityReport = preparedActivityReport
        } else {
            activityReport = try await synchronizeActivityOnlyCloudSidecar(
                store: store,
                storageKey: expectedStorageKey,
                userID: expectedUserID,
                pendingAlreadyReplayed: activityPendingAlreadyReplayed
            )
        }
        let profile = store.syncProfileStats()
        let data = try store.exportCloudBackupData(
            owner: owner,
            extensionsData: store.cloudExtensionsData
        )
        let uploadedBackup = try JSONDecoder().decode(GymBackup.self, from: data)
        let uploadedIdentity = try Self.cloudWorkoutIdentity(uploadedBackup)
        let workoutDurations = try Self.workoutDurationSyncItems(store.workouts)
        try await cloudSync.saveRemoteState(
            backupData: data,
            xp: profile.xp,
            level: profile.level,
            workouts: profile.workouts,
            workoutDurations: workoutDurations,
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
        let currentActivityItems = try store.activityOnlyCloudSnapshotItems()
        try recordActivityOnlyCloudBaseline(
            activityReport.localItems,
            store: store,
            storageKey: expectedStorageKey,
            ownerUserID: expectedUserID,
            clean: activityReport.clean && currentActivityItems == activityReport.localItems
        )
    }

    static func workoutDurationSyncItems(
        _ workouts: [WorkoutSession]
    ) throws -> [[String: Any]] {
        guard workouts.count <= BackupImportLimits.standard.maximumSessions else {
            throw CloudSyncError.invalidPayload
        }
        var seen = Set<Int64>()
        var result: [[String: Any]] = []
        result.reserveCapacity(workouts.count)
        for workout in workouts {
            // Empty-set Garmin activities are owner-private and use their dedicated CAS
            // sidecar. Never leak or erase them through the social duration projection.
            guard !workout.exercises.isEmpty else { continue }
            guard let duration = workout.durationSeconds else { continue }
            let millisecondsValue = (workout.date.timeIntervalSince1970 * 1_000).rounded()
            guard millisecondsValue.isFinite,
                  millisecondsValue >= -62_135_769_600_000,
                  millisecondsValue <= 64_092_211_200_000,
                  (0 ... 7 * 24 * 60 * 60).contains(duration) else {
                throw CloudSyncError.invalidPayload
            }
            let milliseconds = Int64(millisecondsValue)
            guard seen.insert(milliseconds).inserted else {
                throw CloudSyncError.invalidPayload
            }
            result.append([
                "workoutStartedAt": milliseconds,
                "durationSeconds": duration
            ])
        }
        return result.sorted {
            ($0["workoutStartedAt"] as? Int64 ?? 0) <
                ($1["workoutStartedAt"] as? Int64 ?? 0)
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
        exerciseMediaDirectoryURL: URL?,
        exerciseMediaFileManager: FileManager,
        garminBindingStore: GarminDeviceBindingStore
    ) {
        guard case .pending(let storageKey) = PendingAccountDeletionStore.state(
            defaults: defaults
        ) else {
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

        TrainingProfileStore(defaults: defaults).clear(accountStorageKey: storageKey)
        AppTutorialStore(defaults: defaults).clear(accountStorageKey: storageKey)
        defaults.removeObject(forKey: hiddenLeaderboardProfilesKey)
        defaults.removeObject(
            forKey: leaderboardHiddenProfilesDefaultsKey(for: storageKey)
        )
        GarminPhoneSyncService.clearStoredData(
            defaults: defaults,
            storageKey: storageKey
        )
        do {
            try ExerciseMediaStore.clearAccount(
                ownerKey: storageKey,
                mediaDirectoryURL: exerciseMediaDirectoryURL,
                fileManager: exerciseMediaFileManager
            )
        } catch {
            cleanupFailed = true
        }
        do {
            try auth.removeSavedLocalProfile(storageKey: storageKey)
        } catch {
            cleanupFailed = true
        }
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
        if !clearActivityOnlyCloudDeletionArtifacts(
            defaults: defaults,
            storageKey: storageKey
        ) {
            cleanupFailed = true
        }

        if !cleanupFailed {
            _ = PendingAccountDeletionStore.clearExact(storageKey, defaults: defaults)
            auth.pendingAccountDeletionStateDidChange()
        }
        defaults.removeObject(forKey: legacyPendingDeletionGarminUserIDKey)
    }

    private static func clearActivityOnlyCloudDeletionArtifacts(
        defaults: UserDefaults,
        storageKey: String
    ) -> Bool {
        let pendingCleared =
            LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.clearAndVerify(
            defaults: defaults,
            storageKey: storageKey
        )
        let baselineCleared =
            LegacyActivityOnlyWorkoutCloudBaselinePreferences.clearAndVerify(
            defaults: defaults,
            storageKey: storageKey
        )
        let checkpointKey = cloudCheckpointKeyPrefix + storageKey
        defaults.removeObject(forKey: checkpointKey)
        let checkpointCleared = defaults.object(forKey: checkpointKey) == nil
        return pendingCleared && baselineCleared && checkpointCleared
    }

    private static func cloudUserID(fromDeletionStorageKey storageKey: String) -> String? {
        let prefix = "cloud_"
        guard storageKey.hasPrefix(prefix) else { return nil }
        let suffix = String(storageKey.dropFirst(prefix.count))
        guard suffix.utf8.count == 36, let uuid = UUID(uuidString: suffix) else { return nil }
        return uuid.uuidString.lowercased()
    }
}
