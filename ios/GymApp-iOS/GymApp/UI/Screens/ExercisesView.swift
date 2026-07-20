import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExercisesView: View {
    private enum BodyFilter: String, CaseIterable, Identifiable {
        case all
        case upper
        case lower
        case core

        var id: Self { self }

        var muscleIDs: Set<String> {
            switch self {
            case .all: []
            case .upper: ["chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upperBack"]
            case .lower: ["lowerBack", "glutes", "quads", "hamstrings", "adductors", "calves"]
            case .core: ["abs", "obliques"]
            }
        }
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case name
        case mostFrequent
        case leastFrequent

        var id: Self { self }
    }

    private enum PresentedSheet: Identifiable {
        case addExercise
        case editExercise(Exercise)
        case history(Exercise)
        case muscles(Exercise)

        var id: String {
            switch self {
            case .addExercise:
                return "add-exercise"
            case let .editExercise(exercise):
                return "edit-\(exercise.id.uuidString)"
            case let .history(exercise):
                return "history-\(exercise.id.uuidString)"
            case let .muscles(exercise):
                return "muscles-\(exercise.id.uuidString)"
            }
        }
    }

    private enum ActiveAlert: Identifiable {
        case delete(Exercise)
        case importBackup
        case error(String)

        var id: String {
            switch self {
            case let .delete(exercise):
                return "delete-\(exercise.id.uuidString)"
            case .importBackup:
                return "import-backup"
            case let .error(message):
                return "error-\(message)"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: WorkoutStore

    @State private var searchText = ""
    @State private var bodyFilter: BodyFilter = .all
    @State private var muscleFilter: String?
    @State private var sortMode: SortMode = .name
    @State private var presentedSheet: PresentedSheet?
    @State private var activeAlert: ActiveAlert?
    @State private var showsAccountSettings = false
    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var pendingImportData: Data?
    @State private var exportDocument: GymExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "GymApp-backup"
    @State private var resultMessage: String?

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    accountCard

                    if let resultMessage {
                        GymStatusBanner(message: resultMessage, isError: false)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    backupCard
                    exerciseLibrary
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $presentedSheet, content: presentedContent)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                headerCopy
                Spacer(minLength: 10)
                addExerciseButton
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                addExerciseButton
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exercises")
                .font(.largeTitle.bold())
                .foregroundStyle(GymTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Manage your library, history, muscle groups, and backups.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addExerciseButton: some View {
        Button {
            presentedSheet = .addExercise
        } label: {
            Label("Add exercise", systemImage: "plus")
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .accessibilityHint("Adds a custom exercise to your library")
    }

    private var accountCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: auth.session?.cloud == nil ? "iphone" : "person.crop.circle.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(GymTheme.primary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymLocalized(auth.session?.displayName ?? "GymApp athlete"))
                            .font(.headline)
                            .foregroundStyle(GymTheme.textPrimary)
                        Text(gymLocalized(accountSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    GymInfoPill(
                        auth.session?.cloud == nil ? "Local" : "Cloud",
                        systemImage: auth.session?.cloud == nil ? "internaldrive" : "icloud"
                    )
                }

                Button {
                    showsAccountSettings = true
                } label: {
                    Label("Account, privacy & deletion", systemImage: "gearshape")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens account settings, support, sign out, and account deletion")
            }
        }
    }

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

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            GymSectionTitle(
                eyebrow: "Library",
                title: "Your exercises",
                supporting: "Open history or assign any of the 15 supported muscle groups."
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search exercises", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .gymTextFieldChrome()

            exerciseFilters

            if filteredExercises.isEmpty {
                GymPanel {
                    ContentUnavailableView {
                        Label(
                            gymLocalized(store.exercises.isEmpty ? "No exercises yet" : "No matches"),
                            systemImage: store.exercises.isEmpty ? "dumbbell" : "magnifyingglass"
                        )
                    } description: {
                        Text(
                            gymLocalized(store.exercises.isEmpty
                                ? "Add an exercise now or import a backup."
                                : "Try another name or clear the search.")
                        )
                    } actions: {
                        if store.exercises.isEmpty {
                            Button("Add exercise") { presentedSheet = .addExercise }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Clear search") { searchText = "" }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(filteredExercises) { exercise in
                    exerciseCard(exercise)
                }
            }
        }
    }

    private var exerciseFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(BodyFilter.allCases) { filter in
                        Button(bodyFilterTitle(filter)) { bodyFilter = filter }
                            .buttonStyle(.bordered)
                            .tint(bodyFilter == filter ? GymTheme.primary : GymTheme.textSecondary)
                            .accessibilityAddTraits(bodyFilter == filter ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SortMode.allCases) { mode in
                        Button(sortModeTitle(mode)) { sortMode = mode }
                            .buttonStyle(.bordered)
                            .tint(sortMode == mode ? GymTheme.primary : GymTheme.textSecondary)
                            .accessibilityAddTraits(sortMode == mode ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button(gymLocalized("All muscles")) { muscleFilter = nil }
                        .buttonStyle(.bordered)
                        .tint(muscleFilter == nil ? GymTheme.primary : GymTheme.textSecondary)
                    ForEach(MuscleMappingEngine.muscleDefinitions) { muscle in
                        Button(gymText(muscle.titleEn, muscle.titleUk, languageCode: gymCurrentLanguageCode())) {
                            muscleFilter = muscleFilter == muscle.id ? nil : muscle.id
                        }
                        .buttonStyle(.bordered)
                        .tint(muscleFilter == muscle.id ? GymTheme.primary : GymTheme.textSecondary)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text(gymText(
                "\(filteredExercises.count) exercises",
                "Вправ: \(filteredExercises.count)",
                languageCode: gymCurrentLanguageCode()
            ))
            .font(.caption)
            .foregroundStyle(GymTheme.textSecondary)
        }
    }

    private func bodyFilterTitle(_ filter: BodyFilter) -> String {
        switch filter {
        case .all: gymLocalized("All")
        case .upper: gymText("Upper body", "Верх тіла", languageCode: gymCurrentLanguageCode())
        case .lower: gymText("Lower body", "Низ тіла", languageCode: gymCurrentLanguageCode())
        case .core: gymText("Core", "Кор", languageCode: gymCurrentLanguageCode())
        }
    }

    private func sortModeTitle(_ mode: SortMode) -> String {
        switch mode {
        case .name:
            gymText("By name", "За назвою", languageCode: gymCurrentLanguageCode())
        case .mostFrequent:
            gymText("Most frequent", "Найчастіші", languageCode: gymCurrentLanguageCode())
        case .leastFrequent:
            gymText("Least frequent", "Найрідші", languageCode: gymCurrentLanguageCode())
        }
    }

    private func exerciseCard(_ exercise: Exercise) -> some View {
        let stats = store.progressStats(exerciseID: exercise.id)
        let mappingCount = manualMuscleIDs(for: exercise).count
        let displayName = gymExerciseName(exercise)

        return GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(GymTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 4)

                    if catalogDefinition(for: exercise) != nil {
                        HStack(spacing: 6) {
                            GymInfoPill(
                                gymText("Built-in", "Вбудована", languageCode: gymCurrentLanguageCode()),
                                systemImage: "checkmark.seal"
                            )
                            Button(role: .destructive) {
                                activeAlert = .delete(exercise)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(
                                gymText(
                                    "Delete \(displayName)",
                                    "Видалити «\(displayName)»",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                        }
                    } else {
                        Menu {
                            Button {
                                presentedSheet = .editExercise(exercise)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                activeAlert = .delete(exercise)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(
                            gymText(
                                "More actions for \(displayName)",
                                "Більше дій для «\(displayName)»",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                    }
                }

                HStack(spacing: 8) {
                    GymInfoPill(
                        gymCount(
                            stats.sessionCount,
                            englishOne: "workout",
                            englishMany: "workouts",
                            ukrainianOne: "тренування",
                            ukrainianFew: "тренування",
                            ukrainianMany: "тренувань"
                        ),
                        systemImage: "calendar"
                    )
                    GymInfoPill(
                        mappingCount == 0
                            ? gymLocalized("Auto mapping")
                            : gymText(
                                "\(mappingCount) mapped",
                                "зіставлено: \(mappingCount)",
                                languageCode: gymCurrentLanguageCode()
                            ),
                        systemImage: "figure.strengthtraining.traditional",
                        accent: mappingCount == 0 ? GymTheme.secondary : GymTheme.primary
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        historyButton(exercise)
                        mappingButton(exercise)
                    }
                    VStack(spacing: 10) {
                        historyButton(exercise)
                        mappingButton(exercise)
                    }
                }
            }
        }
    }

    private func historyButton(_ exercise: Exercise) -> some View {
        let displayName = gymExerciseName(exercise)
        return Button {
            presentedSheet = .history(exercise)
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint(
            gymText(
                "Shows every saved set for \(displayName)",
                "Показує всі збережені підходи для «\(displayName)»",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }

    private func mappingButton(_ exercise: Exercise) -> some View {
        let displayName = gymExerciseName(exercise)
        return Button {
            presentedSheet = .muscles(exercise)
        } label: {
            Label("Muscle groups", systemImage: "figure.strengthtraining.traditional")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint(
            gymText(
                "Manually maps \(displayName) to muscle groups",
                "Дає змогу вручну зіставити «\(displayName)» із групами м’язів",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }

    private var filteredExercises: [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = store.exercises.filter { exercise in
            let definition = catalogDefinition(for: exercise)
            let names = [exercise.name, gymExerciseName(exercise)] +
                (definition.map { [$0.englishName, $0.ukrainianName] + $0.legacyAliases } ?? [])
            let exerciseMuscles = effectiveMuscleIDs(for: exercise)
            let matchesQuery = query.isEmpty || names.contains { name in
                name.localizedCaseInsensitiveContains(query)
            }
            let matchesBody = bodyFilter == .all || !exerciseMuscles.isDisjoint(with: bodyFilter.muscleIDs)
            let matchesMuscle = muscleFilter == nil || exerciseMuscles.contains(muscleFilter!)
            return matchesQuery && matchesBody && matchesMuscle
        }
        return matching.sorted { left, right in
            let nameOrder = gymExerciseName(left).localizedCaseInsensitiveCompare(gymExerciseName(right))
            let nameComesFirst = nameOrder == .orderedAscending || (
                nameOrder == .orderedSame && left.id.uuidString < right.id.uuidString
            )
            switch sortMode {
            case .name:
                return nameComesFirst
            case .mostFrequent:
                let leftCount = store.progressStats(exerciseID: left.id).sessionCount
                let rightCount = store.progressStats(exerciseID: right.id).sessionCount
                return leftCount == rightCount ? nameComesFirst : leftCount > rightCount
            case .leastFrequent:
                let leftCount = store.progressStats(exerciseID: left.id).sessionCount
                let rightCount = store.progressStats(exerciseID: right.id).sessionCount
                return leftCount == rightCount ? nameComesFirst : leftCount < rightCount
            }
        }
    }

    private func effectiveMuscleIDs(for exercise: Exercise) -> Set<String> {
        let manual = Set(manualMuscleIDs(for: exercise))
        if !manual.isEmpty { return manual }
        if let definition = catalogDefinition(for: exercise) {
            return Set(definition.muscleIDs)
        }
        return Set(MuscleMappingEngine.defaultContributions(for: exercise.name).map(\.muscleID))
    }

    private func catalogDefinition(for exercise: Exercise) -> BuiltInExerciseDefinition? {
        if let definition = BuiltInExerciseCatalog.definition(forKey: exercise.catalogKey) {
            return definition
        }
        guard let key = BuiltInExerciseCatalog.canonicalKey(forName: exercise.name) else {
            return nil
        }
        return BuiltInExerciseCatalog.definition(forKey: key)
    }

    private func manualMuscleIDs(for exercise: Exercise) -> [String] {
        let key = MuscleMappingEngine.normalizeExerciseName(exercise.name)
        return store.muscleMappings
            .filter { $0.exerciseNameKey == key }
            .map(\.muscleID)
    }

    @ViewBuilder
    private func presentedContent(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .addExercise:
            NavigationStack {
                ExerciseEditorSheet(title: "Add exercise", initialName: "") { name in
                    _ = try store.addExercise(name: name)
                    resultMessage = "Exercise added."
                }
            }

        case let .editExercise(exercise):
            NavigationStack {
                let displayName = gymExerciseName(exercise)
                ExerciseEditorSheet(title: "Rename exercise", initialName: displayName) { name in
                    let persistedName = name.gymTrimmed == displayName.gymTrimmed
                        ? exercise.name
                        : name
                    try store.renameExercise(id: exercise.id, to: persistedName)
                    resultMessage = "Exercise renamed."
                }
            }

        case let .history(exercise):
            NavigationStack {
                ExerciseHistorySheet(
                    exercise: exercise,
                    history: store.exerciseHistory(exerciseID: exercise.id),
                    stats: store.progressStats(exerciseID: exercise.id)
                )
            }

        case let .muscles(exercise):
            NavigationStack {
                ExerciseMuscleMappingSheet(
                    exercise: exercise,
                    initialSelection: Set(manualMuscleIDs(for: exercise))
                ) { selection in
                    try store.saveExerciseMuscleMapping(
                        exerciseName: exercise.name,
                        muscleIDs: Array(selection)
                    )
                    resultMessage = selection.isEmpty
                        ? "Automatic muscle mapping restored."
                        : "Muscle groups saved."
                }
            }
        }
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .delete(exercise):
            let displayName = gymExerciseName(exercise)
            return Alert(
                title: Text(
                    gymText(
                        "Delete \(displayName)?",
                        "Видалити «\(displayName)»?",
                        languageCode: gymCurrentLanguageCode()
                    )
                ),
                message: Text("This also removes the exercise from saved workouts. Empty workouts are removed. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    do {
                        try store.deleteExercise(id: exercise.id, cascadeFromWorkouts: true)
                        resultMessage = "Exercise and linked workout entries deleted."
                    } catch {
                        activeAlert = .error(errorMessage(error))
                    }
                },
                secondaryButton: .cancel()
            )

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
            exportDocument = GymExportDocument(data: data)
            exportContentType = .json
            exportFilename = includeDiagnostics ? "GymApp-diagnostics" : "GymApp-backup"
            showsExporter = true
        } catch {
            activeAlert = .error(errorMessage(error))
        }
    }

    private func prepareDiagnosticsPDF() {
        do {
            let dashboard = store.dashboardStats()
            let sync = store.syncProfileStats()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? gymLocalized("Unknown")
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? gymLocalized("Unknown")
            let accountMode = gymLocalized(auth.session?.cloud == nil ? "Local profile" : "Cloud account")
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
                        "\(gymLocalized("Total volume")): \(dashboard.totalVolume.formatted(.number.precision(.fractionLength(0...1))))",
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
            exportDocument = GymExportDocument(data: try Data(contentsOf: pdfURL))
            exportContentType = .pdf
            exportFilename = "GymApp-diagnostics"
            showsExporter = true
        } catch {
            activeAlert = .error(errorMessage(error))
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
            activeAlert = .error(errorMessage(error))
        }
    }

    private func performPendingImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let result = try appState.importBackup(data)
            resultMessage = importSummary(result)
        } catch {
            activeAlert = .error(errorMessage(error))
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            resultMessage = "Export saved."
        case let .failure(error):
            activeAlert = .error(errorMessage(error))
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

    private func errorMessage(_ error: Error) -> String {
        gymErrorMessage(error)
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

private struct GymExportDocument: FileDocument {
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

@MainActor
private struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let onSave: (String) throws -> Void

    @State private var name: String
    @State private var error: String?

    init(title: String, initialName: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GymSectionTitle(
                        eyebrow: "Exercise library",
                        title: title,
                        supporting: "Use a clear name you will recognize while logging workouts."
                    )

                    TextField("Exercise name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .gymTextFieldChrome()
                        .accessibilityLabel("Exercise name")

                    if let error {
                        GymStatusBanner(message: error, isError: true)
                    }

                    Button(action: save) {
                        Label(gymLocalized(initialName.isEmpty ? "Add exercise" : "Save name"), systemImage: "checkmark")
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)
            }
        }
        .navigationTitle(gymLocalized(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func save() {
        do {
            try onSave(name)
            dismiss()
        } catch {
            self.error = gymErrorMessage(error)
        }
    }
}

@MainActor
private struct ExerciseHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let history: [ExerciseHistoryEntry]
    let stats: ExerciseProgressStats

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GymSectionTitle(
                        eyebrow: "Exercise history",
                        title: gymExerciseName(exercise),
                        supporting: history.isEmpty
                            ? "No completed sets yet."
                            : "Every completed set, newest first."
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { metricTiles }
                        VStack(spacing: 10) { metricTiles }
                    }

                    if history.isEmpty {
                        GymPanel {
                            ContentUnavailableView(
                                "No history yet",
                                systemImage: "clock",
                                description: Text("Log this exercise in a workout to see progress here.")
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(history.sorted(by: historySort)) { entry in
                            GymPanel {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(gymFormattedDate(entry.sessionDate, date: .abbreviated, time: .omitted))
                                            .font(.headline)
                                        Text(
                                            gymText(
                                                "Set \(entry.setOrderIndex + 1)",
                                                "Підхід \(entry.setOrderIndex + 1)",
                                                languageCode: gymCurrentLanguageCode()
                                            )
                                        )
                                            .font(.caption)
                                            .foregroundStyle(GymTheme.textSecondary)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(
                                            "\(entry.weight.formatted(.number.precision(.fractionLength(0...2)))) " +
                                                "\(gymLocalized("kg")) × \(entry.reps)"
                                        )
                                            .font(.headline.monospacedDigit())
                                        Text(
                                            gymText(
                                                "Volume \(entry.volume.formatted(.number.precision(.fractionLength(0...1)))) kg",
                                                "Обсяг \(entry.volume.formatted(.number.precision(.fractionLength(0...1)))) кг",
                                                languageCode: gymCurrentLanguageCode()
                                            )
                                        )
                                            .font(.caption)
                                            .foregroundStyle(GymTheme.textSecondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    gymText(
                                        "\(gymFormattedDate(entry.sessionDate, date: .abbreviated, time: .omitted)), set \(entry.setOrderIndex + 1), \(entry.weight.formatted()) kilograms, \(entry.reps) repetitions",
                                        "\(gymFormattedDate(entry.sessionDate, date: .abbreviated, time: .omitted)), підхід \(entry.setOrderIndex + 1), \(entry.weight.formatted()) кілограмів, повторень: \(entry.reps)",
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                )
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var metricTiles: some View {
        GymMetricTile(label: "Sessions", value: stats.sessionCount.formatted())
        GymMetricTile(
            label: "Max weight",
            value: "\(stats.maxWeight.formatted(.number.precision(.fractionLength(0...2)))) \(gymLocalized("kg"))"
        )
        GymMetricTile(
            label: "Total volume",
            value: "\(stats.totalVolume.formatted(.number.precision(.fractionLength(0...1)))) \(gymLocalized("kg"))"
        )
    }

    private func historySort(_ lhs: ExerciseHistoryEntry, _ rhs: ExerciseHistoryEntry) -> Bool {
        if lhs.sessionDate == rhs.sessionDate {
            return lhs.setOrderIndex > rhs.setOrderIndex
        }
        return lhs.sessionDate > rhs.sessionDate
    }
}

@MainActor
private struct ExerciseMuscleMappingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let initialSelection: Set<String>
    let onSave: (Set<String>) throws -> Void

    @State private var selection: Set<String>
    @State private var error: String?

    init(
        exercise: Exercise,
        initialSelection: Set<String>,
        onSave: @escaping (Set<String>) throws -> Void
    ) {
        self.exercise = exercise
        self.initialSelection = initialSelection
        self.onSave = onSave
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GymSectionTitle(
                        eyebrow: "Manual mapping",
                        title: gymExerciseName(exercise),
                        supporting: "Select every muscle group this movement trains. An empty selection uses GymApp’s automatic name-based mapping."
                    )

                    GymPanel {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                suggestedButton
                                clearButton
                            }
                            VStack(spacing: 10) {
                                suggestedButton
                                clearButton
                            }
                        }
                    }

                    ForEach(MuscleMappingEngine.muscleDefinitions) { muscle in
                        GymPanel(
                            highlighted: selection.contains(muscle.id),
                            contentPadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                        ) {
                            Toggle(isOn: binding(for: muscle.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        gymText(muscle.titleEn, muscle.titleUk, languageCode: gymCurrentLanguageCode())
                                    )
                                        .font(.headline)
                                    Text(
                                        gymCurrentLanguageCode() == "uk" ? muscle.titleEn : muscle.titleUk
                                    )
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.textSecondary)
                                }
                            }
                            .tint(GymTheme.primary)
                            .accessibilityHint(
                                gymText(
                                    "Adds or removes \(muscle.titleEn) from the manual mapping",
                                    "Додає або видаляє «\(muscle.titleUk)» у ручному зіставленні",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                        }
                    }

                    if let error {
                        GymStatusBanner(message: error, isError: true)
                    }

                    Button(action: save) {
                        Label("Save muscle groups", systemImage: "checkmark")
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                }
                .padding(16)
                .padding(.bottom, 18)
            }
        }
        .navigationTitle("Muscle groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var suggestedButton: some View {
        Button {
            selection = Set(
                MuscleMappingEngine.defaultContributions(for: exercise.name).map(\.muscleID)
            )
        } label: {
            Label("Use suggestion", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
    }

    private var clearButton: some View {
        Button {
            selection.removeAll()
        } label: {
            Label("Use automatic", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }

    private func save() {
        do {
            try onSave(selection)
            dismiss()
        } catch {
            self.error = gymErrorMessage(error)
        }
    }
}
