import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ProfileView: View {
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

    @State private var activeAlert: ActiveAlert?
    @State private var showsAccountSettings = false
    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var pendingImportData: Data?
    @State private var exportDocument: ProfileExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "GymApp-backup"
    @State private var resultMessage: String?

    init(appState: AppState, auth: AuthService, store: WorkoutStore) {
        self.appState = appState
        self.auth = auth
        self.store = store
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    accountCard

                    if let resultMessage {
                        GymStatusBanner(message: resultMessage, isError: false)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    backupCard
                    LeaderboardView(
                        store: store,
                        appState: appState,
                        auth: auth,
                        embedded: true
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showsAccountSettings) {
            NavigationStack {
                AccountSettingsView(showsCloseButton: true)
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
    }

    private var header: some View {
        GymSectionTitle(
            eyebrow: "Profile",
            title: auth.session?.displayName ?? "GymApp athlete",
            supporting: "Account controls, private data tools, and protected progress."
        )
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
                        Text(gymLocalized(accountSubtitle))
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

    private var isCloudAccount: Bool { auth.session?.cloud != nil }

    private var accountSubtitle: String {
        if let email = auth.session?.cloud?.email {
            return email
        }
        return "Workout data is stored on this device. Export a backup before changing devices."
    }

    private var backupCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    eyebrow: "Your data",
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
                        prepareJSONExport(includeDiagnostics: true)
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
                .accessibilityHint("Exports app and workout diagnostics without authentication tokens")

                Text("A JSON backup contains your exercise names, workout dates, sets, notes, and account ownership metadata. Share it only with people you trust.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportBackupButton: some View {
        Button {
            prepareJSONExport(includeDiagnostics: false)
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

    private func prepareJSONExport(includeDiagnostics: Bool) {
        do {
            let data = try appState.exportBackup(includeDiagnostics: includeDiagnostics)
            exportDocument = ProfileExportDocument(data: data)
            exportContentType = .json
            exportFilename = includeDiagnostics ? "GymApp-diagnostics" : "GymApp-backup"
            showsExporter = true
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func prepareDiagnosticsPDF() {
        do {
            let dashboard = store.dashboardStats()
            let sync = store.syncProfileStats()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? gymLocalized("Unknown")
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? gymLocalized("Unknown")
            let accountMode = gymLocalized(isCloudAccount ? "Cloud account" : "Local profile")
            let lastSync = appState.cloudSync.lastSyncedAt.map {
                gymFormattedDate($0, date: .abbreviated, time: .standard)
            } ?? gymLocalized("Never")
            let pdfURL = try ExportService.writeDiagnosticsPDF(sections: [
                (
                    heading: gymLocalized("Application"),
                    lines: [
                        "\(gymLocalized("Version")): \(version) (\(build))",
                        "\(gymLocalized("System")): \(ProcessInfo.processInfo.operatingSystemVersionString)",
                        "\(gymLocalized("Locale")): \(Locale.current.identifier)",
                        "\(gymLocalized("Account mode")): \(accountMode)"
                    ]
                ),
                (
                    heading: gymLocalized("Workout data"),
                    lines: [
                        "\(gymLocalized("Exercises")): \(store.exercises.count)",
                        "\(gymLocalized("Workouts")): \(dashboard.workoutCount)",
                        "\(gymLocalized("Total volume")): \(dashboard.totalVolume.formatted(.number.precision(.fractionLength(0 ... 1))))",
                        "\(gymLocalized("Profile XP")): \(sync.xp)",
                        "\(gymLocalized("Profile level")): \(sync.level)",
                        "\(gymLocalized("Manual muscle mappings")): \(store.muscleMappings.count)"
                    ]
                ),
                (
                    heading: gymLocalized("Cloud sync"),
                    lines: [
                        "\(gymLocalized("Last successful sync")): \(lastSync)",
                        "\(gymLocalized("Last error")): \(gymLocalized(appState.cloudSync.lastError ?? "None"))"
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
