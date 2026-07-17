import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let auth: AuthService
    let restTimers: RestTimerManager
    let cloudSync: CloudSyncService
    let garminCloud: GarminCloudService

    @Published private(set) var workoutStore: WorkoutStore
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published private(set) var isPreparingAccount = false
    @Published private(set) var activeAccountStorageKey: String?
    @Published private(set) var accountPreparationError: String?

    private var sessionSubscription: AnyCancellable?
    private var storeSubscription: AnyCancellable?
    private var pendingCloudSave: Task<Void, Never>?
    private var accountActivationTask: Task<Void, Never>?
    private var accountActivationGeneration: UInt64 = 0
    private var applyingRemoteState = false
    private var cloudWritableAccountStorageKey: String?
    private let defaults: UserDefaults
    private let workoutDirectoryURL: URL?
    private let remoteStateLoader: (@MainActor (String) async throws -> Data?)?

    private static let pendingDeletionStorageKey = "gymapp.pending-account-deletion-storage-key"
    private static let legacyPendingDeletionGarminUserIDKey =
        "gymapp.pending-account-deletion-garmin-user-id"
    private static let trainingProfileKeyPrefix = "gymapp.training-profile.v1."
    private static let hiddenLeaderboardProfilesKey = "leaderboard-hidden-profile-ids"

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        workoutDirectoryURL: URL? = nil,
        cloudURLSession: URLSession = .shared,
        remoteStateLoader: (@MainActor (String) async throws -> Data?)? = nil,
        garminBindingStore: GarminDeviceBindingStore = GarminDeviceBindingStore()
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

        self.restTimers = RestTimerManager()
        self.cloudSync = CloudSyncService(auth: auth, urlSession: cloudURLSession)
        self.garminCloud = GarminCloudService(
            auth: auth,
            urlSession: cloudURLSession,
            bindingStore: garminBindingStore
        )
        let openedStore = try WorkoutStore.openRecoveringCorruptStore(
            accountStorageKey: "signed-out",
            directoryURL: workoutDirectoryURL
        )
        self.workoutStore = openedStore.store
        if hadPendingDeletion { self.restTimers.cancelAll() }
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

    private func scheduleActivation(_ session: AppAccountSession?) {
        accountActivationTask?.cancel()
        let generation = beginAccountTransition(session)
        accountActivationTask = Task { [weak self] in
            await self?.prepareAccount(session, generation: generation)
        }
    }

    private func beginAccountTransition(_ session: AppAccountSession?) -> UInt64 {
        accountActivationGeneration &+= 1
        pendingCloudSave?.cancel()
        pendingCloudSave = nil
        cloudSync.resetForAccountTransition()
        cloudWritableAccountStorageKey = nil
        activeAccountStorageKey = nil
        accountPreparationError = nil
        isPreparingAccount = session != nil
        return accountActivationGeneration
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
            var seededExerciseCount = try candidate.seedBuiltInExercises()
            _ = try candidate.seedDefaultMuscleMappings()

            var cloudError: Error?
            var cloudWritesAllowed = false
            var loadedReadOnlyPWAState = false
            if let expectedUserID {
                do {
                    let remoteData: Data?
                    if let remoteStateLoader {
                        remoteData = try await remoteStateLoader(expectedUserID)
                    } else {
                        remoteData = try await cloudSync.withSyncIndicator({
                            try await self.cloudSync.loadRemoteState(expectedUserID: expectedUserID)
                        })
                    }
                    if let remoteData {
                        try ensureActivationIsCurrent(
                            generation: generation,
                            expectedStorageKey: expectedStorageKey
                        )
                        let preparedBackup = try WorkoutStore.prepareCloudBackup(
                            remoteData,
                            activeOwner: expectedOwner
                        )
                        _ = try candidate.restoreBackup(
                            data: preparedBackup.data,
                            activeOwner: expectedOwner
                        )
                        cloudWritesAllowed = preparedBackup.roundTripSafe
                        loadedReadOnlyPWAState = !preparedBackup.roundTripSafe
                    } else {
                        try await uploadCurrentState(
                            from: candidate,
                            owner: expectedOwner,
                            expectedStorageKey: expectedStorageKey,
                            expectedUserID: expectedUserID
                        )
                        cloudWritesAllowed = true
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard accountActivationGeneration == generation,
                          auth.session?.storageKey == expectedStorageKey else { return }
                    cloudError = error
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

    func exportBackup(includeDiagnostics: Bool = false) throws -> Data {
        guard isAccountReady else { throw WorkoutStoreError.storageAccountMismatch }
        return try workoutStore.exportBackupData(
            includeDiagnostics: includeDiagnostics,
            owner: backupOwner,
            prettyPrinted: true
        )
    }

    func deleteCurrentAccountAndData() async throws {
        pendingCloudSave?.cancel()
        guard isAccountReady, let session = auth.session else {
            throw WorkoutStoreError.storageAccountMismatch
        }
        let storageKey = session.storageKey
        let deletingStore = workoutStore
        defaults.set(storageKey, forKey: Self.pendingDeletionStorageKey)
        defaults.removeObject(forKey: Self.legacyPendingDeletionGarminUserIDKey)

        do {
            if let cloud = session.cloud {
                try await auth.deleteCloudAccountOnServer(expectedUserID: cloud.userID)
            }
        } catch {
            // The server account still exists, so retain the local account and let the user retry.
            defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
            throw error
        }

        let deletingSessionIsStillCurrent = auth.session?.storageKey == storageKey
        if deletingSessionIsStillCurrent {
            accountActivationTask?.cancel()
            accountActivationTask = nil
            accountActivationGeneration &+= 1
            pendingCloudSave?.cancel()
            pendingCloudSave = nil
            cloudSync.resetForAccountTransition()
            cloudWritableAccountStorageKey = nil
            activeAccountStorageKey = nil
            isPreparingAccount = true
            applyingRemoteState = true
        }

        var cleanupError: Error?
        if deletingSessionIsStillCurrent { restTimers.cancelAll() }
        if let cloudUserID = session.cloud?.userID {
            do {
                try garminCloud.clearLocalBindingData(for: cloudUserID)
            } catch {
                cleanupError = cleanupError ?? error
            }
        }
        defaults.removeObject(forKey: Self.trainingProfileKeyPrefix + storageKey)
        defaults.removeObject(forKey: Self.hiddenLeaderboardProfilesKey)

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
                      self.isAccountReady,
                      self.auth.session?.cloud != nil else { return }
                self.scheduleCloudSave()
            }
        }
    }

    private func scheduleCloudSave(delay: Duration = .milliseconds(1_500)) {
        pendingCloudSave?.cancel()
        guard isAccountReady,
              let session = auth.session,
              let cloud = session.cloud,
              cloudWritableAccountStorageKey == session.storageKey else { return }
        let store = workoutStore
        let owner = Self.backupOwner(for: session, fallbackStorageKey: session.storageKey)
        pendingCloudSave = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                guard self.isAccountReady,
                      self.workoutStore === store,
                      self.auth.session?.cloud?.userID == cloud.userID,
                      self.cloudWritableAccountStorageKey == session.storageKey else { return }
                try await self.uploadCurrentState(
                    from: store,
                    owner: owner,
                    expectedStorageKey: session.storageKey,
                    expectedUserID: cloud.userID
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.show(error: error)
            }
        }
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
        let data = try store.exportBackupData(
            owner: owner,
            prettyPrinted: false
        )
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
