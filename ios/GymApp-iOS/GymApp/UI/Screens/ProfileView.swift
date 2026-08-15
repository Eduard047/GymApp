import SwiftUI
import UniformTypeIdentifiers

enum NativePushScrollBehavior: Equatable, Sendable {
    case animated
    case immediate
}

func nativePushScrollBehavior(reduceMotion: Bool) -> NativePushScrollBehavior {
    reduceMotion ? .immediate : .animated
}

@MainActor
struct ProfileView: View {
    private enum ProfileSection: String, CaseIterable, Identifiable {
        case friends
        case settings

        var id: String { rawValue }
    }

    private enum ActiveAlert: Identifiable {
        case importBackup
        case error(String)

        var id: String {
            switch self {
            case .importBackup: "import-backup"
            case let .error(message): "error-\(message)"
            }
        }
    }

    @ObservedObject private var appState: AppState
    @ObservedObject private var auth: AuthService
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var garminCloud: GarminCloudService
    @ObservedObject private var garminPhoneSync: GarminPhoneSyncService
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedProfilePushTarget: NativePushProfileFocus?

    @State private var activeAlert: ActiveAlert?
    @State private var showsAccountSettings = false
    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var pendingImportData: Data?
    @State private var exportDocument: ProfileExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "GymApp-backup"
    @State private var resultMessage: String?
    @State private var fulfilledNativePushRequestID: UUID?
    @State private var requestedNativePushAccessibilityTarget: NativePushProfileFocus?
    @State private var selectedSection: ProfileSection = .friends
    private let canAcceptWorkoutInvites: Bool
    private let nativePushRequest: NativePushProfileRequest?
    private let onShowTutorial: () -> Void
    private let onOpenLiveWorkout: () -> Void

    init(
        appState: AppState,
        auth: AuthService,
        store: WorkoutStore,
        canAcceptWorkoutInvites: Bool = true,
        liveWorkoutCoordinator: LiveWorkoutCoordinator,
        nativePushRequest: NativePushProfileRequest? = nil,
        onShowTutorial: @escaping () -> Void = {},
        onOpenLiveWorkout: @escaping () -> Void
    ) {
        self.appState = appState
        self.auth = auth
        self.store = store
        self.garminCloud = appState.garminCloud
        self.garminPhoneSync = appState.garminPhoneSync
        self.canAcceptWorkoutInvites = canAcceptWorkoutInvites
        self.liveWorkoutCoordinator = liveWorkoutCoordinator
        self.nativePushRequest = nativePushRequest
        self.onShowTutorial = onShowTutorial
        self.onOpenLiveWorkout = onOpenLiveWorkout
    }

    var body: some View {
        ScrollViewReader { proxy in
            GymBackground {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                        header
                        sectionPicker

                        if let resultMessage {
                            GymStatusBanner(message: resultMessage, isError: false)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if selectedSection == .friends {
                            FriendsView(
                                appState: appState,
                                auth: auth,
                                canAcceptWorkoutInvites: canAcceptWorkoutInvites,
                                liveWorkoutCoordinator: liveWorkoutCoordinator,
                                nativePushAccessibilityTarget: requestedNativePushAccessibilityTarget,
                                onOpenAccountSettings: {
                                    showsAccountSettings = true
                                },
                                onOpenLiveWorkout: onOpenLiveWorkout
                            )
                            .id(NativePushProfileFocus.friends)
                            .accessibilityFocused(
                                $focusedProfilePushTarget,
                                equals: .friends
                            )
                        } else {
                            accountCard
                            garminCard
                            backupCard
                            helpCard
                        }
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .task(id: nativePushRequest?.id) {
                requestedNativePushAccessibilityTarget = nil
                focusedProfilePushTarget = nil
                guard let nativePushRequest else { return }
                await scrollToNativePushRequest(
                    nativePushRequest,
                    using: proxy,
                    allowFallback: true
                )
            }
            .onChange(of: appState.socialDashboard != nil) { _ in
                retryPendingNativePushScroll(using: proxy, allowFallback: true)
            }
            .onChange(of: liveWorkoutCoordinator.inbox) { _ in
                retryPendingNativePushScroll(using: proxy, allowFallback: false)
            }
        }
        .sheet(isPresented: $showsAccountSettings) {
            NavigationStack {
                AccountSettingsView(
                    showsCloseButton: true,
                    hasBlockingLiveWorkout: liveWorkoutCoordinator.hasBlockingLiveWorkout
                )
            }
            .environmentObject(appState)
            .environmentObject(auth)
        }
        .alert(item: $activeAlert, content: makeAlert)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .task(id: auth.session?.storageKey) {
            guard isCloudAccount, !garminCloud.isWorking else { return }
            try? await garminCloud.refreshDevices()
        }
    }

    private func retryPendingNativePushScroll(
        using proxy: ScrollViewProxy,
        allowFallback: Bool
    ) {
        guard let request = nativePushRequest,
              fulfilledNativePushRequestID != request.id else {
            return
        }
        Task { @MainActor in
            await scrollToNativePushRequest(
                request,
                using: proxy,
                allowFallback: allowFallback
            )
        }
    }

    private func scrollToNativePushRequest(
        _ request: NativePushProfileRequest,
        using proxy: ScrollViewProxy,
        allowFallback: Bool
    ) async {
        guard nativePushRequest?.id == request.id,
              fulfilledNativePushRequestID != request.id else {
            return
        }
        selectedSection = .friends
        await Task.yield()

        let exactAnchor: NativePushProfileFocus?
        switch request.focus {
        case .friends:
            exactAnchor = .friends
        case let .friendRequest(friendshipID):
            exactAnchor = socialFriendshipIsVisible(friendshipID) ? .friendRequest(friendshipID) : nil
        case let .workoutInvite(inviteID):
            exactAnchor = socialWorkoutInviteIsVisible(inviteID) ? .workoutInvite(inviteID) : nil
        case .liveWorkouts:
            exactAnchor = appState.socialDashboard == nil ? nil : .liveWorkouts
        case let .liveRoom(roomID):
            let invitations = liveWorkoutCoordinator.inbox?.invitations ?? []
            let rooms = liveWorkoutCoordinator.inbox?.rooms ?? []
            let roomIsVisible = invitations.contains { $0.roomID == roomID }
                || rooms.contains { $0.roomID == roomID }
            exactAnchor = roomIsVisible ? .liveRoom(roomID) : nil
        }

        if let exactAnchor {
            scroll(proxy, to: exactAnchor)
            requestedNativePushAccessibilityTarget = exactAnchor
            focusedProfilePushTarget = exactAnchor == .friends ? .friends : nil
            // Let the exact card appear and accept VoiceOver focus before this
            // route is considered fulfilled.
            await Task.yield()
            fulfilledNativePushRequestID = request.id
        } else if allowFallback {
            let fallback: NativePushProfileFocus = appState.socialDashboard == nil
                ? .friends
                : .liveWorkouts
            scroll(proxy, to: fallback)
            requestedNativePushAccessibilityTarget = fallback
            focusedProfilePushTarget = fallback == .friends ? .friends : nil
            // The parent creates this request only after its bounded authoritative
            // fetch/open attempt finishes. A missing exact object therefore resolves
            // once to the nearest safe surface instead of repeatedly pulling the user
            // back on every later dashboard or inbox refresh.
            await Task.yield()
            fulfilledNativePushRequestID = request.id
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to target: NativePushProfileFocus) {
        switch nativePushScrollBehavior(reduceMotion: reduceMotion) {
        case .animated:
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        case .immediate:
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func socialFriendshipIsVisible(_ friendshipID: String) -> Bool {
        guard let dashboard = appState.socialDashboard else { return false }
        return dashboard.incoming.contains { $0.friendshipID == friendshipID }
            || dashboard.outgoing.contains { $0.friendshipID == friendshipID }
            || dashboard.friends.contains { $0.friendshipID == friendshipID }
    }

    private func socialWorkoutInviteIsVisible(_ inviteID: String) -> Bool {
        guard let inbox = appState.socialWorkoutInbox else { return false }
        return inbox.incoming.contains { $0.inviteID == inviteID }
            || inbox.outgoing.contains { $0.inviteID == inviteID }
    }

    private var header: some View {
        GymScreenHeader(
            title: auth.session?.displayName ?? "GymApp athlete"
        )
    }

    private var sectionPicker: some View {
        GymPanel(
            contentPadding: EdgeInsets(
                top: 7,
                leading: 7,
                bottom: 7,
                trailing: 7
            )
        ) {
            Picker(
                gymText("Profile section", "Розділ профілю", "Раздел профиля", languageCode: languageCode),
                selection: $selectedSection
            ) {
                Text(gymText("Friends", "Друзі", "Друзья", languageCode: languageCode))
                    .tag(ProfileSection.friends)
                Text(gymText("Settings", "Налаштування", "Настройки", languageCode: languageCode))
                    .tag(ProfileSection.settings)
            }
            .pickerStyle(.segmented)
        }
    }

    private var accountCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isCloudAccount ? "person.crop.circle.badge.checkmark" : "iphone")
                        .font(.title2)
                        .foregroundStyle(GymTheme.primary)
                        .frame(width: 32)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymLocalized(isCloudAccount ? "Cloud account" : "Local profile"))
                            .font(.headline)
                            .foregroundStyle(GymTheme.textPrimary)
                        Text(accountSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    GymInfoPill(
                        isCloudAccount ? "Cloud" : "Local",
                        systemImage: isCloudAccount ? "icloud" : "internaldrive"
                    )
                }

                Button {
                    showsAccountSettings = true
                } label: {
                    Label("Account, privacy & deletion", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens account settings, Garmin, support, sign out, and account deletion")
            }
        }
    }

    private var helpCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("Help", "Допомога", "Помощь", languageCode: languageCode)
                )
                Button(action: onShowTutorial) {
                    Label(
                        gymText(
                            "Show tutorial",
                            "Показати навчання",
                            "Показать обучение",
                            languageCode: languageCode
                        ),
                        systemImage: "questionmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
            }
        }
    }

    private var isCloudAccount: Bool { auth.session?.cloud != nil }

    private var garminCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("Your watch", "Твій годинник", "Твои часы", languageCode: languageCode),
                    supporting: gymText(
                        "Live Bluetooth status is available for watches shared with this iPhone. Cloud watches show their latest synchronization state.",
                        "Поточний статус Bluetooth доступний для годинників, підключених до цього iPhone. Для хмарних годинників показано стан останньої синхронізації.",
                        "Текущий статус Bluetooth доступен для часов, подключённых к этому iPhone. Для облачных часов показано состояние последней синхронизации.",
                        languageCode: languageCode
                    )
                )

                if garminPhoneSync.devices.isEmpty && selectedCloudDevice == nil {
                    GymInlineState(
                        gymText(
                            "No Garmin watch connected yet. Connect one from Account & devices.",
                            "Годинник Garmin ще не підключено. Підключи його в розділі «Акаунт і пристрої».",
                            "Часы Garmin ещё не подключены. Подключи их в разделе «Аккаунт и устройства».",
                            languageCode: languageCode
                        ),
                        systemImage: "applewatch"
                    )
                } else {
                    ForEach(garminPhoneSync.devices) { device in
                        garminDeviceRow(
                            name: device.name,
                            detail: device.model,
                            status: device.connected
                                ? gymText("Connected now", "Зараз підключено", "Подключены сейчас", languageCode: languageCode)
                                : gymText("Not connected now", "Зараз не підключено", "Сейчас не подключены", languageCode: languageCode),
                            connected: device.connected
                        )
                    }
                    if garminPhoneSync.devices.isEmpty, let device = selectedCloudDevice {
                        garminDeviceRow(
                            name: device.displayName,
                            detail: gymText("Garmin cloud watch", "Хмарний годинник Garmin", "Облачные часы Garmin", languageCode: languageCode),
                            status: device.lastSeenAt == nil
                                ? gymText("Waiting for first watch sync", "Очікуємо першу синхронізацію годинника", "Ожидаем первую синхронизацию часов", languageCode: languageCode)
                                : gymText("Recently synchronized with GymApp cloud", "Нещодавно синхронізовано з хмарою GymApp", "Недавно синхронизировано с облаком GymApp", languageCode: languageCode),
                            connected: device.lastSeenAt != nil
                        )
                    }
                }
            }
        }
    }

    private var selectedCloudDevice: GarminDeviceSummary? {
        guard let selectedID = garminCloud.selectedDevice?.deviceID else { return nil }
        return garminCloud.availableDevices.first { $0.id == selectedID }
    }

    private func garminDeviceRow(
        name: String,
        detail: String,
        status: String,
        connected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(connected ? GymTheme.primary : GymTheme.textSecondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(GymTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connected ? GymTheme.primary : GymTheme.textSecondary)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(GymTheme.surfaceVariant)
        )
        .accessibilityElement(children: .combine)
    }

    private var accountSubtitle: String {
        if auth.session?.cloud != nil {
            return gymText(
                "Protected workout synchronization is active. Open settings to manage identity and privacy.",
                "Захищена синхронізація тренувань активна. Відкрий налаштування, щоб керувати профілем і приватністю.",
                "Защищённая синхронизация тренировок активна. Открой настройки, чтобы управлять профилем и конфиденциальностью.",
                languageCode: languageCode
            )
        }
        return gymText(
            "Workout data is stored on this device. Export a backup before changing devices.",
            "Дані тренувань зберігаються на цьому пристрої. Експортуй резервну копію перед зміною пристрою.",
            "Данные тренировок хранятся на этом устройстве. Экспортируй резервную копию перед сменой устройства.",
            languageCode: languageCode
        )
    }

    private var backupCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Backup & diagnostics",
                    supporting: "Backups merge into the current profile and skip duplicate sessions."
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        exportBackupButton
                        importBackupButton
                    }
                    VStack(spacing: 10) {
                        exportBackupButton
                        importBackupButton
                    }
                }

                Menu {
                    Button {
                        prepareDiagnosticsJSON()
                    } label: {
                        Label("Diagnostics JSON", systemImage: "curlybraces")
                    }

                    Button {
                        prepareDiagnosticsPDF()
                    } label: {
                        Label("Diagnostics PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Label("Export diagnostics", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Diagnostics contain app metadata and aggregate counts only. They exclude authentication tokens, account identifiers, exercise names, workout dates, notes, and set values.")

                Text("A JSON backup contains your exercise names, workout dates, sets, notes, and account ownership metadata. Share it only with people you trust.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Diagnostics contain app metadata and aggregate counts only. They exclude authentication tokens, account identifiers, exercise names, workout dates, notes, and set values.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportBackupButton: some View {
        Button {
            prepareBackupJSON()
        } label: {
            Label("Export backup", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint("Saves a GymApp JSON backup using the Files picker")
    }

    private var importBackupButton: some View {
        Button {
            showsImporter = true
        } label: {
            Label("Import backup", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint("Selects a GymApp JSON backup to merge into this profile")
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case .importBackup:
            return Alert(
                title: Text("Merge this backup?"),
                message: Text("New exercises and sessions will be added to this profile. Matching sessions are skipped; existing data is kept."),
                primaryButton: .default(Text("Merge")) {
                    performPendingImport()
                },
                secondaryButton: .cancel {
                    pendingImportData = nil
                }
            )
        case let .error(message):
            return Alert(
                title: Text("Couldn’t complete the action"),
                message: Text(gymLocalized(message)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var diagnosticsContext: ExportService.DiagnosticsContext {
        ExportService.DiagnosticsContext(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? gymLocalized("Unknown"),
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? gymLocalized("Unknown"),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            localeIdentifier: Locale.current.identifier,
            cloudSyncEnabled: isCloudAccount,
            hasSuccessfulSync: appState.cloudSync.lastSyncedAt != nil,
            hasError: appState.cloudSync.lastError != nil
        )
    }

    private func currentDiagnosticsSnapshot() throws -> WorkoutDiagnosticsSnapshot {
        guard appState.isAccountReady,
              store.accountStorageKey == appState.activeAccountStorageKey else {
            throw WorkoutStoreError.storageAccountMismatch
        }
        return store.diagnosticsSnapshot()
    }

    private func prepareBackupJSON() {
        do {
            let data = try appState.exportBackup()
            exportDocument = ProfileExportDocument(data: data)
            exportContentType = .json
            exportFilename = "GymApp-backup"
            showsExporter = true
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func prepareDiagnosticsJSON() {
        do {
            let data = try ExportService.diagnosticsJSON(
                snapshot: try currentDiagnosticsSnapshot(),
                context: diagnosticsContext
            )
            exportDocument = ProfileExportDocument(data: data)
            exportContentType = .json
            exportFilename = "GymApp-diagnostics"
            showsExporter = true
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func prepareDiagnosticsPDF() {
        do {
            let snapshot = try currentDiagnosticsSnapshot()
            let context = diagnosticsContext
            let accountMode = gymLocalized(isCloudAccount ? "Cloud account" : "Local profile")
            let pdfURL = try ExportService.writeDiagnosticsPDF(sections: [
                (
                    heading: gymLocalized("Application"),
                    lines: [
                        "\(gymLocalized("Version")): \(context.version) (\(context.build))",
                        "\(gymLocalized("System")): \(context.operatingSystemVersion)",
                        "\(gymLocalized("Locale")): \(context.localeIdentifier)",
                        "\(gymLocalized("Account mode")): \(accountMode)"
                    ]
                ),
                (
                    heading: gymLocalized("Workout data"),
                    lines: [
                        "\(gymLocalized("Exercises")): \(snapshot.exerciseCount)",
                        "\(gymLocalized("Workouts")): \(snapshot.workoutCount)",
                        "\(gymLocalized("Sets")): \(snapshot.setCount)",
                        "\(gymLocalized("Manual muscle mappings")): \(snapshot.manualMuscleMappingCount)"
                    ]
                ),
                (
                    heading: gymLocalized("Privacy"),
                    lines: [
                        gymLocalized("No passwords, access tokens, refresh tokens, or Keychain values are included."),
                        gymLocalized("Generated only after an explicit user action.")
                    ]
                )
            ])
            defer { try? FileManager.default.removeItem(at: pdfURL) }
            exportDocument = ProfileExportDocument(data: try Data(contentsOf: pdfURL))
            exportContentType = .pdf
            exportFilename = "GymApp-diagnostics"
            showsExporter = true
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= BackupImportLimits.standard.maximumFileBytes else {
                throw WorkoutStoreError.importLimitExceeded("file size")
            }
            pendingImportData = try BackupFileReader.read(
                from: url,
                maximumBytes: BackupImportLimits.standard.maximumFileBytes
            )
            activeAlert = .importBackup
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func performPendingImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let result = try appState.importBackup(data)
            resultMessage = importSummary(result)
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            resultMessage = "Export saved."
        case let .failure(error):
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func importSummary(_ result: BackupImportResult) -> String {
        let sessions = gymCount(
            result.importedSessions,
            englishOne: "session",
            englishMany: "sessions",
            ukrainianOne: "сесію",
            ukrainianFew: "сесії",
            ukrainianMany: "сесій"
        )
        let exercises = gymCount(
            result.addedExercises,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправу",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ"
        )
        let duplicates = gymCount(
            result.skippedDuplicateSessions,
            englishOne: "duplicate",
            englishMany: "duplicates",
            ukrainianOne: "дублікат",
            ukrainianFew: "дублікати",
            ukrainianMany: "дублікатів"
        )
        let invalidSets = gymCount(
            result.ignoredInvalidSets,
            englishOne: "invalid set",
            englishMany: "invalid sets",
            ukrainianOne: "некоректний підхід",
            ukrainianFew: "некоректні підходи",
            ukrainianMany: "некоректних підходів"
        )
        return gymText(
            "\(sessions) imported · \(exercises) added · \(duplicates) skipped · \(invalidSets) ignored",
            "Імпортовано: \(sessions) · додано: \(exercises) · пропущено: \(duplicates) · проігноровано: \(invalidSets)",
            languageCode: gymCurrentLanguageCode()
        )
    }
}

enum BackupFileReader {
    static func read(from url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var result = Data()
        result.reserveCapacity(min(maximumBytes, 256 * 1_024))
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            guard chunk.count <= maximumBytes - result.count else {
                throw WorkoutStoreError.importLimitExceeded("file size")
            }
            result.append(chunk)
        }
        return result
    }
}

private struct ProfileExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
