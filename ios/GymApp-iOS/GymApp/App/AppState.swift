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

    private var sessionSubscription: AnyCancellable?
    private var storeSubscription: AnyCancellable?
    private var pendingCloudSave: Task<Void, Never>?
    private var applyingRemoteState = false
    private let defaults: UserDefaults

    private static let pendingDeletionStorageKey = "gymapp.pending-account-deletion-storage-key"
    private static let trainingProfileKeyPrefix = "gymapp.training-profile.v1."
    private static let hiddenLeaderboardProfilesKey = "leaderboard-hidden-profile-ids"

    init(auth: AuthService, defaults: UserDefaults = .standard) throws {
        self.auth = auth
        self.defaults = defaults

        let hadPendingDeletion = defaults.string(forKey: Self.pendingDeletionStorageKey) != nil
        Self.finishPendingDeletionCleanupIfNeeded(auth: auth, defaults: defaults)

        self.restTimers = RestTimerManager()
        self.cloudSync = CloudSyncService(auth: auth)
        self.garminCloud = GarminCloudService(auth: auth)
        let openedStore = try WorkoutStore.openRecoveringCorruptStore(
            accountStorageKey: auth.session?.storageKey ?? "signed-out"
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
            .removeDuplicates()
            .sink { [weak self] session in
                guard let self else { return }
                Task { @MainActor in await self.activate(session) }
            }
    }

    deinit {
        pendingCloudSave?.cancel()
    }

    var backupOwner: BackupOwner {
        switch auth.session {
        case .cloud(let cloud):
            return BackupOwner(
                accountID: auth.session?.storageKey,
                userID: cloud.userID,
                email: cloud.email,
                remote: true
            )
        case .local(let id, _):
            return BackupOwner(accountID: "local_\(id)", remote: false)
        case nil:
            return BackupOwner(accountID: workoutStore.accountStorageKey, remote: false)
        }
    }

    func activate(_ session: AppAccountSession?) async {
        pendingCloudSave?.cancel()
        guard let session else { return }
        isPreparingAccount = true
        applyingRemoteState = true
        defer {
            applyingRemoteState = false
            isPreparingAccount = false
        }
        do {
            try workoutStore.switchAccount(to: session.storageKey)
            if case .cloud = session {
                if let remoteData = try await cloudSync.withSyncIndicator({
                    try await self.cloudSync.loadRemoteState()
                }) {
                    _ = try workoutStore.restoreBackup(data: remoteData, activeOwner: backupOwner)
                } else {
                    try await uploadCurrentState()
                }
            }
        } catch {
            show(error: error)
        }
    }

    func forceCloudSync() async {
        guard auth.session?.cloud != nil else {
            show(message: "Cloud sync is available after signing in.", isError: true)
            return
        }
        do {
            try await cloudSync.withSyncIndicator {
                try await self.uploadCurrentState()
            }
            show(message: "Cloud data is up to date.", isError: false)
        } catch {
            show(error: error)
        }
    }

    func importBackup(_ data: Data) throws -> BackupImportResult {
        try workoutStore.importBackup(data: data, activeOwner: backupOwner)
    }

    func exportBackup(includeDiagnostics: Bool = false) throws -> Data {
        try workoutStore.exportBackupData(
            includeDiagnostics: includeDiagnostics,
            owner: backupOwner,
            prettyPrinted: true
        )
    }

    func deleteCurrentAccountAndData() async throws {
        pendingCloudSave?.cancel()
        let storageKey = auth.session?.storageKey ?? workoutStore.accountStorageKey
        defaults.set(storageKey, forKey: Self.pendingDeletionStorageKey)

        do {
            if auth.session?.cloud != nil {
                try await auth.deleteCloudAccountOnServer()
            }
        } catch {
            // The server account still exists, so retain the local account and let the user retry.
            defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
            throw error
        }

        restTimers.cancelAll()
        defaults.removeObject(forKey: Self.trainingProfileKeyPrefix + storageKey)
        defaults.removeObject(forKey: Self.hiddenLeaderboardProfilesKey)

        var cleanupError: Error?
        do {
            try workoutStore.destroyAccountData()
        } catch {
            cleanupError = error
        }
        do {
            try workoutStore.switchAccount(to: "signed-out")
        } catch {
            cleanupError = cleanupError ?? error
        }
        do {
            try auth.clearSession()
        } catch {
            cleanupError = cleanupError ?? error
        }

        guard cleanupError == nil else {
            // The marker intentionally survives. Startup retries secure local cleanup before
            // exposing any account UI, including after a server-side account was deleted.
            throw cleanupError!
        }

        defaults.removeObject(forKey: Self.pendingDeletionStorageKey)
        statusMessage = nil
    }

    func saveBeforeBackgrounding() {
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
        storeSubscription = workoutStore.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.applyingRemoteState, self.auth.session?.cloud != nil else { return }
                self.scheduleCloudSave()
            }
        }
    }

    private func scheduleCloudSave(delay: Duration = .milliseconds(1_500)) {
        pendingCloudSave?.cancel()
        pendingCloudSave = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                try await self.uploadCurrentState()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.show(error: error)
            }
        }
    }

    private func uploadCurrentState() async throws {
        guard auth.session?.cloud != nil else { return }
        let profile = workoutStore.syncProfileStats()
        let data = try workoutStore.exportBackupData(
            owner: backupOwner,
            prettyPrinted: false
        )
        try await cloudSync.saveRemoteState(
            backupData: data,
            xp: profile.xp,
            level: profile.level,
            workouts: profile.workouts
        )
    }

    private static func finishPendingDeletionCleanupIfNeeded(
        auth: AuthService,
        defaults: UserDefaults
    ) {
        guard let storageKey = defaults.string(forKey: pendingDeletionStorageKey),
              !storageKey.isEmpty else { return }

        var cleanupFailed = false
        do {
            let staleStore = try WorkoutStore(accountStorageKey: storageKey)
            try staleStore.destroyAccountData()
        } catch {
            cleanupFailed = true
        }

        defaults.removeObject(forKey: trainingProfileKeyPrefix + storageKey)
        defaults.removeObject(forKey: hiddenLeaderboardProfilesKey)
        do {
            try auth.clearSession()
        } catch {
            // AuthService still clears the in-memory session, so deleted data is never shown.
            cleanupFailed = true
        }

        if !cleanupFailed {
            defaults.removeObject(forKey: pendingDeletionStorageKey)
        }
    }
}
