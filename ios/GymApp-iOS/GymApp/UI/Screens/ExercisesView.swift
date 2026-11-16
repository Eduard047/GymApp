import SwiftUI

func exerciseMuscleMappingSecondaryTitle(
    english: String,
    ukrainian: String,
    languageCode: String
) -> String {
    languageCode == AppLanguage.english.rawValue ? ukrainian : english
}

struct ExerciseLibraryDeletionTarget: Equatable, Identifiable {
    struct LinkedImpact: Equatable {
        let workoutSnapshot: WorkoutSession
        let matchingBlocks: [WorkoutExercise]

        var workoutID: UUID { workoutSnapshot.id }
        var workoutExerciseIDs: [UUID] { workoutSnapshot.exercises.map(\.id) }
    }

    let accountStorageKey: String
    let storeIdentifier: ObjectIdentifier
    let exerciseSnapshot: Exercise
    let displayName: String
    let muscleMappingSnapshot: [ExerciseMuscleMapping]
    let linkedImpact: [LinkedImpact]

    var exerciseID: UUID { exerciseSnapshot.id }
    var id: UUID { exerciseID }
    var linkedWorkoutCount: Int { linkedImpact.count }
    var linkedSetCount: Int {
        linkedImpact
            .flatMap(\.matchingBlocks)
            .reduce(0) { $0 + $1.sets.count }
    }
    var deletedWorkoutCount: Int {
        linkedImpact.filter { impact in
            Set(impact.workoutExerciseIDs) == Set(impact.matchingBlocks.map(\.id))
        }.count
    }
    var restTimerIDs: [String] {
        linkedImpact.flatMap { impact in
            impact.matchingBlocks.map { block in
                "workout-\(impact.workoutID.uuidString)-exercise-\(block.id.uuidString)"
            }
        }
    }

    @MainActor
    init(store: WorkoutStore, exercise: Exercise, displayName: String) {
        accountStorageKey = store.accountStorageKey
        storeIdentifier = ObjectIdentifier(store)
        exerciseSnapshot = exercise
        self.displayName = displayName
        muscleMappingSnapshot = Self.captureMuscleMappings(
            in: store,
            exerciseName: exercise.name
        )
        linkedImpact = Self.captureLinkedImpact(in: store, exerciseID: exercise.id)
    }

    @MainActor
    func isCurrent(in store: WorkoutStore) -> Bool {
        guard storeIdentifier == ObjectIdentifier(store),
              accountStorageKey == store.accountStorageKey,
              let current = store.exercise(id: exerciseID),
              current == exerciseSnapshot,
              Self.captureMuscleMappings(
                  in: store,
                  exerciseName: exerciseSnapshot.name
              ) == muscleMappingSnapshot else {
            return false
        }
        return Self.captureLinkedImpact(in: store, exerciseID: exerciseID) == linkedImpact
    }

    @MainActor
    func isCurrent(
        in store: WorkoutStore,
        activeStore: WorkoutStore,
        activeAccountStorageKey: String?,
        isAccountReady: Bool
    ) -> Bool {
        isAccountReady
            && activeStore === store
            && activeAccountStorageKey == accountStorageKey
            && isCurrent(in: store)
    }

    func confirmationMessage(languageCode: String) -> String {
        let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
        let undone = gymLocalized("This cannot be undone.", languageCode: languageCode)
        guard linkedWorkoutCount > 0 else {
            return String(
                format: gymLocalized(
                    "Not used in any workout, so no history is removed. %@",
                    languageCode: languageCode
                ),
                locale: locale,
                arguments: [undone]
            )
        }
        let workouts = gymPlural(
            linkedWorkoutCount,
            en: ("%d workout", "%d workouts"),
            uk: ("%d тренування", "%d тренувань", "%d тренувань"),
            ru: ("%d тренировки", "%d тренировок", "%d тренировок"),
            languageCode: languageCode
        )
        let sets = gymPlural(
            linkedSetCount,
            en: ("%d logged set", "%d logged sets"),
            uk: ("%d записаного підходу", "%d записаних підходів", "%d записаних підходів"),
            ru: ("%d записанного подхода", "%d записанных подходов", "%d записанных подходов"),
            languageCode: languageCode
        )
        var sentences = [
            String(
                format: gymLocalized(
                    "It will also be removed from %1$@ and %2$@.",
                    languageCode: languageCode
                ),
                locale: locale,
                arguments: [
                    String(format: workouts, locale: locale, linkedWorkoutCount),
                    String(format: sets, locale: locale, linkedSetCount)
                ]
            )
        ]
        if deletedWorkoutCount > 0 {
            let emptied = gymPlural(
                deletedWorkoutCount,
                en: ("%d workout left empty will be deleted.", "%d workouts left empty will be deleted."),
                uk: (
                    "%d порожнє тренування буде видалено.",
                    "%d порожні тренування будуть видалені.",
                    "%d порожніх тренувань буде видалено."
                ),
                ru: (
                    "%d опустевшая тренировка будет удалена.",
                    "%d опустевшие тренировки будут удалены.",
                    "%d опустевших тренировок будут удалены."
                ),
                languageCode: languageCode
            )
            sentences.append(String(format: emptied, locale: locale, deletedWorkoutCount))
        }
        sentences.append(undone)
        return sentences.joined(separator: " ")
    }

    @MainActor
    private static func captureMuscleMappings(
        in store: WorkoutStore,
        exerciseName: String
    ) -> [ExerciseMuscleMapping] {
        let exerciseNameKey = MuscleMappingEngine.normalizeExerciseName(exerciseName)
        return store.muscleMappings
            .filter { $0.exerciseNameKey == exerciseNameKey }
            .sorted { $0.id < $1.id }
    }

    @MainActor
    private static func captureLinkedImpact(
        in store: WorkoutStore,
        exerciseID: UUID
    ) -> [LinkedImpact] {
        store.workouts.compactMap { workout in
            let matching = workout.exercises
                .filter { $0.exerciseID == exerciseID }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            guard !matching.isEmpty else { return nil }
            return LinkedImpact(
                workoutSnapshot: workout,
                matchingBlocks: matching
            )
        }
        .sorted { $0.workoutID.uuidString < $1.workoutID.uuidString }
    }
}

@MainActor
struct ExercisesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        case delete(ExerciseLibraryDeletionTarget)

        var id: String {
            switch self {
            case let .delete(target):
                return "delete-\(target.id.uuidString)"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: WorkoutStore

    @State private var searchText = ""
    @State private var bodyFilter: ExerciseBodyFilter = .all
    @State private var muscleFilter: String?
    @State private var favoritesOnly = false
    @State private var sortMode: ExerciseSortMode = .name
    @State private var presentedSheet: PresentedSheet?
    @State private var activeAlert: ActiveAlert?

    var body: some View {
        GymBackground {
            exerciseList
                .gymStatusBarScrollEdge()
        }
        .navigationDestination(for: UUID.self) { exerciseID in
            ExerciseDetailView(exerciseID: exerciseID, perform: performDetailAction)
        }
        .sheet(item: $presentedSheet, content: presentedContent)
        .alert(item: $activeAlert, content: makeAlert)
#if DEBUG
        .onReceive(UIAuditRouter.shared.$pendingPresentation.compactMap { $0 }) { _ in
            presentUIAuditRouteIfRequested()
        }
#endif
    }

#if DEBUG
    /// UI-audit: presents the add-exercise sheet, history, muscle mapping, or delete
    /// confirmation once for the matching `-uiAuditRoute`. History/mapping/delete use
    /// the first listed exercise that has logged sessions. Nothing is saved or confirmed.
    private func presentUIAuditRouteIfRequested() {
        guard let route = UIAuditRouter.shared.consume(
            anyOf: [.exerciseEditor, .exerciseHistory, .exerciseMuscleMapping, .exerciseDeleteDialog]
        ) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if route == .exerciseEditor {
                presentedSheet = .addExercise
                return
            }
            let exercises = filteredExercises
            guard let exercise = exercises.first(where: {
                store.progressStats(exerciseID: $0.id).sessionCount > 0
            }) ?? exercises.first else {
                UIAuditLaunch.log("\(route.rawValue): no exercises in the active profile")
                return
            }
            switch route {
            case .exerciseHistory:
                presentedSheet = .history(exercise)
            case .exerciseMuscleMapping:
                presentedSheet = .muscles(exercise)
            case .exerciseDeleteDialog:
                activeAlert = .delete(
                    ExerciseLibraryDeletionTarget(
                        store: store,
                        exercise: exercise,
                        displayName: gymExerciseName(exercise)
                    )
                )
            default:
                break
            }
        }
    }
#endif

    private var header: some View {
        GymScreenHeader(
            title: "Exercises"
        ) {
            addExerciseButton
        }
    }

    private var addExerciseButton: some View {
        Button {
            presentedSheet = .addExercise
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(GymTheme.brandFill, in: Circle())
        }
        .accessibilityLabel(gymLocalized("Add exercise"))
        .accessibilityHint(gymLocalized("Adds a custom exercise to your library"))
    }

    private var exerciseList: some View {
        let manualMuscles = MuscleMappingEngine.manualContributionMap(from: store.muscleMappings)
        let exercises = filteredExercises
        return List {
            Section {
                header
                searchRow
                if let token = activeFilterTitle {
                    filterToken(token)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: GymTheme.Spacing.small, trailing: 0))

            if exercises.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            } else {
                Section {
                    ForEach(exercises) { exercise in
                        exerciseRow(exercise, manualMuscles: manualMuscles)
                    }
                }
                .listRowBackground(GymTheme.surface)
                .listRowSeparatorTint(GymTheme.outline.opacity(0.4))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.top, GymTheme.screenVerticalInset, for: .scrollContent)
        .contentMargins(.bottom, GymTheme.screenBottomInset, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    private var emptyState: some View {
        GymPanel {
            GymContentUnavailableView {
                Label(
                    gymLocalized(store.exercises.isEmpty ? "No exercises yet" : "No matches"),
                    systemImage: store.exercises.isEmpty ? "dumbbell" : "magnifyingglass"
                )
            } description: {
                Text(
                    store.exercises.isEmpty
                        ? gymText(
                            "Add a custom exercise to start building your library.",
                            "Додайте власну вправу, щоб почати формувати бібліотеку.",
                            "Добавьте своё упражнение, чтобы начать формировать библиотеку.",
                            languageCode: gymCurrentLanguageCode()
                        )
                        : gymText(
                            "Try another name, body area, or muscle group.",
                            "Спробуйте іншу назву, частину тіла або групу м’язів.",
                            "Попробуйте другое название, часть тела или группу мышц.",
                            languageCode: gymCurrentLanguageCode()
                        )
                )
            } actions: {
                if store.exercises.isEmpty {
                    Button("Add exercise") { presentedSheet = .addExercise }
                        .buttonStyle(GymPrimaryButtonStyle())
                } else {
                    Button("Clear filters", action: clearFilters)
                        .buttonStyle(GymSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// One search field (36pt, radius 10 fill) and the single filter button.
    private var searchRow: some View {
        HStack(spacing: 6) {
            searchField
            filterMenuButton
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
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
                        .frame(minWidth: 28, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(GymTheme.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var isFilterCustomized: Bool {
        favoritesOnly || bodyFilter != .all || muscleFilter != nil || sortMode != .name
    }

    private var filterMenuButton: some View {
        Menu {
            Toggle(isOn: $favoritesOnly) {
                Label(gymLocalized("Favorites"), systemImage: "heart")
            }

            Menu {
                Picker(gymText("Muscle group", "Група м’язів", "Группа мышц", languageCode: gymCurrentLanguageCode()), selection: $muscleFilter) {
                    Text(gymLocalized("All muscles")).tag(String?.none)
                    ForEach(MuscleMappingEngine.muscleDefinitions) { muscle in
                        Text(muscleTitle(muscle)).tag(Optional(muscle.id))
                    }
                }
            } label: {
                Label(
                    gymText("Muscle group", "Група м’язів", "Группа мышц", languageCode: gymCurrentLanguageCode()),
                    systemImage: "figure.strengthtraining.traditional"
                )
            }

            Picker(gymLocalized("Category"), selection: $bodyFilter) {
                ForEach(ExerciseBodyFilter.allCases) { filter in
                    Text(filter.localizedTitle).tag(filter)
                }
            }

            Picker(gymLocalized("Sort"), selection: $sortMode) {
                ForEach(ExerciseSortMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
        } label: {
            Image(
                systemName: isFilterCustomized
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .font(.title3)
            .foregroundStyle(isFilterCustomized ? GymTheme.primary : GymTheme.textSecondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(gymLocalized("Filters"))
        .accessibilityAddTraits(isFilterCustomized ? .isSelected : [])
    }

    private func muscleTitle(_ muscle: MuscleDefinition) -> String {
        gymText(muscle.titleEn, muscle.titleUk, muscle.titleRu, languageCode: gymCurrentLanguageCode())
    }

    /// Text of the one removable filter token, or nil when no filter is active.
    private var activeFilterTitle: String? {
        var parts: [String] = []
        if favoritesOnly { parts.append(gymLocalized("Favorites")) }
        if bodyFilter != .all { parts.append(bodyFilter.localizedTitle) }
        if let muscleFilter,
           let muscle = MuscleMappingEngine.muscleDefinitions.first(where: { $0.id == muscleFilter }) {
            parts.append(muscleTitle(muscle))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func filterToken(_ title: String) -> some View {
        HStack {
            Button {
                withAnimation(GymMotion.quick) {
                    favoritesOnly = false
                    bodyFilter = .all
                    muscleFilter = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .gymLineLimit(1)
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(GymTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(GymTheme.primary.opacity(0.14), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                gymText(
                    "Remove filter: \(title)",
                    "Прибрати фільтр: \(title)",
                    "Убрать фильтр: \(title)",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            Spacer(minLength: 0)
        }
    }

    private func clearFilters() {
        searchText = ""
        bodyFilter = .all
        muscleFilter = nil
        favoritesOnly = false
    }

    private func exerciseRow(
        _ exercise: Exercise,
        manualMuscles: [String: [MuscleContribution]]
    ) -> some View {
        let displayName = gymExerciseName(exercise)
        let info = ExerciseInfo(exercise: exercise, manualMuscles: manualMuscles)
        let isCustom = catalogDefinition(for: exercise) == nil
        let thumbnail = ExerciseMediaThumbnail(
            rawExerciseName: exercise.name,
            catalogKey: exercise.catalogKey,
            exerciseID: exercise.id,
            ownerKey: store.accountStorageKey,
            editable: false,
            width: 44,
            height: 44,
            playOverlayDiameter: 14,
            cornerRadius: 10,
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        var title = Text(gymExerciseDisplayName(displayName))
        if exercise.isFavorite {
            title = title
                + Text("\u{00A0}")
                + Text(Image(systemName: "heart.fill"))
                    .font(.caption)
                    .foregroundColor(GymTheme.primary)
        }

        return NavigationLink(value: exercise.id) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.body)
                        .foregroundStyle(GymTheme.textPrimary)
                        .gymLineLimit(2, accessibility: nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = info.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .gymLineLimit(1, accessibility: 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityValue(exercise.isFavorite ? favoriteAccessibilityValue(exercise) : "")
        .alignmentGuide(.listRowSeparatorLeading) { _ in 72 }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleFavorite(exercise)
            } label: {
                Label(
                    exercise.isFavorite
                        ? gymText("Unfavorite", "Прибрати", "Убрать", languageCode: gymCurrentLanguageCode())
                        : gymText("Favorite", "В обране", "В избранное", languageCode: gymCurrentLanguageCode()),
                    systemImage: exercise.isFavorite ? "heart.slash" : "heart"
                )
            }
            .tint(GymTheme.primaryAction)
        }
        .contextMenu {
            Button {
                presentedSheet = .history(exercise)
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Button {
                presentedSheet = .muscles(exercise)
            } label: {
                Label("Muscle groups", systemImage: "figure.strengthtraining.traditional")
            }

            Button {
                presentedSheet = .editExercise(exercise)
            } label: {
                Label(gymLocalized("Weight steps"), systemImage: "scalemass")
            }

            if isCustom {
                Button {
                    presentedSheet = .editExercise(exercise)
                } label: {
                    Label(gymText("Edit", "Змінити", "Изменить", languageCode: gymCurrentLanguageCode()), systemImage: "pencil")
                }
            }

            Divider()

            Button(role: .destructive) {
                requestDelete(exercise)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func requestDelete(_ exercise: Exercise) {
        activeAlert = .delete(
            ExerciseLibraryDeletionTarget(
                store: store,
                exercise: exercise,
                displayName: gymExerciseName(exercise)
            )
        )
    }

    private func toggleFavorite(_ exercise: Exercise) {
        do {
            _ = try store.toggleExerciseFavorite(id: exercise.id)
        } catch {
            appState.show(message: errorMessage(error), isError: true)
        }
    }

    private func performDetailAction(_ action: ExerciseDetailAction, _ exercise: Exercise) {
        switch action {
        case .history: presentedSheet = .history(exercise)
        case .muscles: presentedSheet = .muscles(exercise)
        case .edit: presentedSheet = .editExercise(exercise)
        case .toggleFavorite: toggleFavorite(exercise)
        case .delete: requestDelete(exercise)
        }
    }

    private func favoriteAccessibilityLabel(_ exercise: Exercise, displayName: String) -> String {
        switch gymCurrentLanguageCode() {
        case AppLanguage.ukrainian.rawValue:
            exercise.isFavorite
                ? "Видалити «\(displayName)» з улюблених"
                : "Додати «\(displayName)» до улюблених"
        case AppLanguage.russian.rawValue:
            exercise.isFavorite
                ? "Удалить «\(displayName)» из избранного"
                : "Добавить «\(displayName)» в избранное"
        default:
            exercise.isFavorite
                ? "Remove \(displayName) from favorites"
                : "Add \(displayName) to favorites"
        }
    }

    private func favoriteAccessibilityValue(_ exercise: Exercise) -> String {
        switch gymCurrentLanguageCode() {
        case AppLanguage.ukrainian.rawValue: exercise.isFavorite ? "Улюблена" : "Не улюблена"
        case AppLanguage.russian.rawValue: exercise.isFavorite ? "В избранном" : "Не в избранном"
        default: exercise.isFavorite ? "Favorite" : "Not favorite"
        }
    }

    private var filteredExercises: [Exercise] {
        ExerciseFilterEngine.filtered(
            exercises: store.exercises,
            query: searchText,
            bodyFilter: bodyFilter,
            muscleFilter: muscleFilter,
            favoritesOnly: favoritesOnly,
            sortMode: sortMode,
            muscleMappings: store.muscleMappings,
            sessionCounts: {
                let stats = store.progressStatsByExercise()
                return Dictionary(
                    uniqueKeysWithValues: store.exercises.map { exercise in
                        (exercise.id, stats[exercise.id]?.sessionCount ?? 0)
                    }
                )
            }()
        )
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

    private func defaultLoadDirection(for exercise: Exercise) -> MachineLoadDirection {
        let key = BuiltInExerciseCatalog.resolvedKey(
            catalogKey: exercise.catalogKey,
            name: exercise.name
        )
        return key == "assisted_dip" || key == "assisted_pull_up"
            ? .lowerIsHarder
            : .higherIsHarder
    }

    @ViewBuilder
    private func presentedContent(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .addExercise:
            NavigationStack {
                ExerciseEditorSheet(
                    title: "Add exercise",
                    initialName: "",
                    initialMachineLoadProfile: nil,
                    defaultLoadDirection: .higherIsHarder,
                    allowsRenaming: true
                ) { draft in
                    _ = try store.addExercise(
                        name: draft.name,
                        machineLoadProfile: draft.machineLoadProfile
                    )
                    appState.show(message: "Exercise added.", isError: false)
                }
            }
            .gymSheetPresentation(.full)

        case let .editExercise(exercise):
            NavigationStack {
                let displayName = gymExerciseName(exercise)
                ExerciseEditorSheet(
                    title: catalogDefinition(for: exercise) == nil ? "Edit exercise" : "Weight steps",
                    initialName: displayName,
                    initialMachineLoadProfile: exercise.machineLoadProfile,
                    defaultLoadDirection: defaultLoadDirection(for: exercise),
                    allowsRenaming: catalogDefinition(for: exercise) == nil
                ) { draft in
                    let persistedName = draft.name.gymTrimmed == displayName.gymTrimmed
                        ? exercise.name
                        : draft.name
                    if persistedName != exercise.name {
                        try store.renameExercise(id: exercise.id, to: persistedName)
                    }
                    try store.updateExerciseMachineLoadProfile(
                        id: exercise.id,
                        machineLoadProfile: draft.machineLoadProfile
                    )
                    appState.show(message: "Exercise updated.", isError: false)
                }
            }
            .gymSheetPresentation(.full)

        case let .history(exercise):
            NavigationStack {
                ExerciseHistorySheet(
                    exercise: exercise,
                    history: store.exerciseHistory(exerciseID: exercise.id),
                    stats: store.progressStats(exerciseID: exercise.id)
                )
            }
            .gymSheetPresentation(.standard)

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
                    appState.show(
                        message: selection.isEmpty
                            ? "Automatic muscle mapping restored."
                            : "Muscle groups saved.",
                        isError: false
                    )
                }
            }
            .gymSheetPresentation(.standard)
        }
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .delete(target):
            let languageCode = gymCurrentLanguageCode()
            return Alert(
                title: Text(
                    gymText(
                        "Delete \(target.displayName)?",
                        "Видалити «\(target.displayName)»?",
                        "Удалить «\(target.displayName)»?",
                        languageCode: languageCode
                    )
                ),
                message: Text(target.confirmationMessage(languageCode: languageCode)),
                primaryButton: .destructive(Text(gymLocalized("Delete", languageCode: languageCode))) {
                    guard target.isCurrent(
                        in: store,
                        activeStore: appState.workoutStore,
                        activeAccountStorageKey: appState.activeAccountStorageKey,
                        isAccountReady: appState.isAccountReady
                    ) else {
                        appState.show(
                            message: gymLocalized(
                                "The exercise or its linked workout data changed before deletion. Review it and try again.",
                                languageCode: languageCode
                            ),
                            isError: true
                        )
                        return
                    }
                    do {
                        try store.deleteExercise(id: target.exerciseID, cascadeFromWorkouts: true)
                        // Best effort: a leftover private photo must never fail the delete.
                        try? ExerciseMediaStore.deleteCustomImage(
                            ownerKey: store.accountStorageKey,
                            exerciseID: target.exerciseID
                        )
                        target.restTimerIDs.forEach { appState.restTimers.cancel(id: $0) }
                        appState.show(
                            message: gymLocalized(
                                "Exercise and linked workout entries deleted.",
                                languageCode: languageCode
                            ),
                            isError: false
                        )
                    } catch {
                        appState.show(message: errorMessage(error), isError: true)
                    }
                },
                secondaryButton: .cancel(Text(gymLocalized("Cancel", languageCode: languageCode)))
            )
        }
    }

    private func errorMessage(_ error: Error) -> String {
        gymErrorMessage(error)
    }
}

@MainActor
private struct ExerciseEditorDraft {
    let name: String
    let machineLoadProfile: MachineLoadProfile?
}

private enum ExerciseEditorValidationError: LocalizedError {
    case invalidWeights

    var errorDescription: String? { message(languageCode: gymCurrentLanguageCode()) }

    func message(languageCode: String) -> String {
        switch self {
        case .invalidWeights:
            gymText(
                "Enter 1–128 valid machine weights between 0 and 1,000,000 kg.",
                "Вкажіть від 1 до 128 допустимих ваг тренажера в діапазоні від 0 до 1 000 000 кг.",
                "Укажите от 1 до 128 допустимых весов тренажёра в диапазоне от 0 до 1 000 000 кг.",
                languageCode: languageCode
            )
        }
    }
}

/// One allowed machine weight as editable text in the app language's decimal separator
/// (ru/uk comma, en dot), at most 2 decimals so step arithmetic noise like 0.30000000000000004
/// never shows. No digit grouping. `MachineWeightsText.parse` reads it back: a bare comma between
/// digits is a decimal separator, so entries are separated by newlines or spaces, never a bare comma.
func gymMachineWeightEditText(
    _ weight: Double,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    weight.formatted(
        .number
            .precision(.fractionLength(0 ... 2))
            .grouping(.never)
            .locale(gymAppLocale(languageCode: languageCode))
    )
}

@MainActor
private struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let initialMachineLoadProfile: MachineLoadProfile?
    let allowsRenaming: Bool
    let onSave: (ExerciseEditorDraft) throws -> Void

    @State private var name: String
    @State private var usesExactMachineWeights: Bool
    @State private var loadDirection: MachineLoadDirection
    @State private var allowedWeightsText: String
    @State private var error: String?
    @State private var showingDiscardConfirmation = false
    private let initialLoadDirection: MachineLoadDirection
    private let initialAllowedWeightsText: String

    init(
        title: String,
        initialName: String,
        initialMachineLoadProfile: MachineLoadProfile?,
        defaultLoadDirection: MachineLoadDirection,
        allowsRenaming: Bool,
        onSave: @escaping (ExerciseEditorDraft) throws -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialMachineLoadProfile = initialMachineLoadProfile
        self.allowsRenaming = allowsRenaming
        self.onSave = onSave
        let startingDirection = initialMachineLoadProfile?.direction ?? defaultLoadDirection
        let startingWeightsText = initialMachineLoadProfile?.allowedWeightsKg
            .map(Self.displayWeight)
            .joined(separator: "\n") ?? ""
        self.initialLoadDirection = startingDirection
        self.initialAllowedWeightsText = startingWeightsText
        _name = State(initialValue: initialName)
        _usesExactMachineWeights = State(initialValue: initialMachineLoadProfile != nil)
        _loadDirection = State(initialValue: startingDirection)
        _allowedWeightsText = State(initialValue: startingWeightsText)
    }

    /// True when any field differs from what the sheet opened with; a swipe-down or
    /// Cancel would then silently drop the typed name or the allowed-weights list.
    static func hasUnsavedChanges(
        name: String,
        initialName: String,
        usesExactMachineWeights: Bool,
        initiallyUsedExactMachineWeights: Bool,
        loadDirection: MachineLoadDirection,
        initialLoadDirection: MachineLoadDirection,
        allowedWeightsText: String,
        initialAllowedWeightsText: String
    ) -> Bool {
        name != initialName
            || usesExactMachineWeights != initiallyUsedExactMachineWeights
            || (usesExactMachineWeights
                && (loadDirection != initialLoadDirection
                    || allowedWeightsText != initialAllowedWeightsText))
    }

    private var hasUnsavedChanges: Bool {
        Self.hasUnsavedChanges(
            name: name,
            initialName: initialName,
            usesExactMachineWeights: usesExactMachineWeights,
            initiallyUsedExactMachineWeights: initialMachineLoadProfile != nil,
            loadDirection: loadDirection,
            initialLoadDirection: initialLoadDirection,
            allowedWeightsText: allowedWeightsText,
            initialAllowedWeightsText: initialAllowedWeightsText
        )
    }

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Exercise name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .gymTextFieldChrome()
                        .accessibilityLabel("Exercise name")
                        .disabled(!allowsRenaming)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use exact machine weights", isOn: $usesExactMachineWeights)

                        if usesExactMachineWeights {
                            Picker("Load direction", selection: $loadDirection) {
                                Text("Higher weight is harder")
                                    .tag(MachineLoadDirection.higherIsHarder)
                                Text("Lower weight is harder (assistance)")
                                    .tag(MachineLoadDirection.lowerIsHarder)
                            }
                            .pickerStyle(.menu)

                            Text("Quick machine-stack presets")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("2.5 kg") { applyPreset(step: 2.5, maximum: 200) }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                Button("5 kg") { applyPreset(step: 5, maximum: 300) }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }

                            Text("Available weights (kg), one per line")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $allowedWeightsText)
                                .frame(minHeight: 150)
                                .scrollContentBackground(.hidden)
                                .gymTextFieldChrome()

                            Text("Example: 45 47.5 50 52.5. The coach will only choose a listed value.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error {
                        GymStatusBanner(message: error, isError: true)
                    }

                    Button(action: save) {
                        Label(
                            gymLocalized(
                                initialName.isEmpty
                                    ? "Add exercise"
                                    : allowsRenaming ? "Save changes" : "Save machine weights"
                            ),
                            systemImage: "checkmark"
                        )
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
                Button("Cancel") {
                    if hasUnsavedChanges {
                        showingDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .confirmationDialog(
            gymText(
                "Discard exercise changes?",
                "Відкинути зміни вправи?",
                "Отменить изменения упражнения?",
                languageCode: gymCurrentLanguageCode()
            ),
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                gymText(
                    "Discard changes",
                    "Відкинути зміни",
                    "Отменить изменения",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .destructive
            ) { dismiss() }
            Button(
                gymText(
                    "Keep editing",
                    "Продовжити редагування",
                    "Продолжить редактирование",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .cancel
            ) {}
        } message: {
            Text(gymText(
                "Your edits will be lost.",
                "Зміни буде втрачено.",
                "Изменения будут потеряны.",
                languageCode: gymCurrentLanguageCode()
            ))
        }
    }

    private func save() {
        do {
            let machineLoadProfile: MachineLoadProfile?
            if usesExactMachineWeights {
                guard let normalized = MachineWeightsText.parse(allowedWeightsText) else {
                    throw ExerciseEditorValidationError.invalidWeights
                }
                do {
                    machineLoadProfile = try MachineLoadProfile(
                        direction: loadDirection,
                        allowedWeightsKg: normalized
                    )
                } catch {
                    throw ExerciseEditorValidationError.invalidWeights
                }
            } else {
                machineLoadProfile = nil
            }
            try onSave(
                ExerciseEditorDraft(
                    name: name,
                    machineLoadProfile: machineLoadProfile
                )
            )
            dismiss()
        } catch let validationError as ExerciseEditorValidationError {
            self.error = validationError.message(languageCode: gymCurrentLanguageCode())
        } catch {
            self.error = gymErrorMessage(error)
        }
    }

    private static func displayWeight(_ weight: Double) -> String {
        gymMachineWeightEditText(weight)
    }

    private func applyPreset(step: Double, maximum: Double) {
        let weights = MachineWeightsText.presetWeights(step: step, maximum: maximum)
        guard !weights.isEmpty else { return }
        allowedWeightsText = weights.map(Self.displayWeight).joined(separator: "\n")
        error = nil
    }
}

/// Pure grouping of per-set history rows into month -> session -> ascending sets,
/// matching the Android history sheet (one card per workout, newest first).
enum ExerciseHistoryGrouping {
    struct Session: Identifiable, Equatable {
        let id: UUID
        let date: Date
        /// Ascending by `setOrderIndex`.
        let sets: [ExerciseHistoryEntry]

        var setCount: Int { sets.count }
        var maxWeight: Double { sets.map(\.weight).max() ?? 0 }
        var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    }

    struct Month: Identifiable, Equatable {
        let id: Int
        let monthStart: Date
        /// Newest first.
        let sessions: [Session]
    }

    static func months(
        from entries: [ExerciseHistoryEntry],
        calendar: Calendar = .current
    ) -> [Month] {
        let sessions = Dictionary(grouping: entries, by: \.workoutID)
            .map { workoutID, rows -> Session in
                let sets = rows.sorted {
                    $0.setOrderIndex != $1.setOrderIndex
                        ? $0.setOrderIndex < $1.setOrderIndex
                        : $0.setID.uuidString < $1.setID.uuidString
                }
                return Session(id: workoutID, date: sets[0].sessionDate, sets: sets)
            }
            .sorted {
                $0.date != $1.date
                    ? $0.date > $1.date
                    : $0.id.uuidString < $1.id.uuidString
            }
        var months: [Month] = []
        var currentKey: Int?
        var currentStart = Date()
        var bucket: [Session] = []
        func flush() {
            if let key = currentKey {
                months.append(Month(id: key, monthStart: currentStart, sessions: bucket))
            }
        }
        for session in sessions {
            let parts = calendar.dateComponents([.year, .month], from: session.date)
            let key = (parts.year ?? 0) * 100 + (parts.month ?? 0)
            if key != currentKey {
                flush()
                currentKey = key
                currentStart = calendar.date(from: parts) ?? session.date
                bucket = []
            }
            bucket.append(session)
        }
        flush()
        return months
    }
}

@MainActor
private struct ExerciseHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let history: [ExerciseHistoryEntry]
    let stats: ExerciseProgressStats
    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GymSectionTitle(
                        title: gymExerciseName(exercise)
                    )

                    ExerciseMediaButton(
                        rawExerciseName: exercise.name,
                        catalogKey: exercise.catalogKey,
                        exerciseID: exercise.id,
                        ownerKey: store.accountStorageKey
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { metricTiles }
                        VStack(spacing: 10) { metricTiles }
                    }

                    if history.isEmpty {
                        GymPanel {
                            GymContentUnavailableView(
                                "No history yet",
                                systemImage: "clock",
                                description: Text("Log this exercise in a workout to see progress here.")
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(ExerciseHistoryGrouping.months(from: history)) { month in
                            Text(Self.monthTitle(month.monthStart))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(GymTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(month.sessions) { session in
                                sessionCard(session)
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
        GymMetricTile(
            label: gymText("Times done", "Виконано разів", "Выполнено раз", languageCode: gymCurrentLanguageCode()),
            value: stats.sessionCount.formatted(.number.locale(gymAppLocale())),
            singleLineLabel: true
        )
        GymMetricTile(
            label: "Max weight",
            value: "\(stats.maxWeight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0...2)))) \(gymLocalized("kg"))",
            singleLineLabel: true
        )
        GymMetricTile(
            label: "Total volume",
            value: "\(stats.totalVolume.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0...1)))) \(gymLocalized("kg"))",
            singleLineLabel: true
        )
    }

    private static func monthTitle(_ date: Date) -> String {
        let locale = gymAppLocale()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let text = formatter.string(from: date)
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    private func weightText(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0...2)))
    }

    private func volumeText(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0...1)))
    }

    private func sessionCard(_ session: ExerciseHistoryGrouping.Session) -> some View {
        let language = gymCurrentLanguageCode()
        let dateText = gymShortDateTime(session.date)
        let maxText = weightText(session.maxWeight)
        let volume = volumeText(session.volume)
        let count = session.setCount
        let kg = gymLocalized("kg")
        let summary = gymText(
            "Max \(maxText) \(kg) · Sets \(count) · Volume \(volume) \(kg)",
            "Макс. \(maxText) \(kg) · Підходи \(count) · Обсяг \(volume) \(kg)",
            "Макс. \(maxText) \(kg) · Подходы \(count) · Объём \(volume) \(kg)",
            languageCode: language
        )
        let spokenSummary = gymText(
            "maximum weight \(maxText) kilograms, \(count) sets, volume \(volume) kilograms",
            "максимальна вага \(maxText) кілограмів, підходів: \(count), обсяг \(volume) кілограмів",
            "максимальный вес \(maxText) кг, подходов: \(count), объём \(volume) кг",
            languageCode: language
        )
        return GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateText)
                        .font(.headline)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(dateText), \(spokenSummary)")

                ForEach(Array(session.sets.enumerated()), id: \.element.setID) { offset, entry in
                    Divider()
                    setRow(entry, number: offset + 1)
                }
            }
        }
    }

    private func setRow(_ entry: ExerciseHistoryEntry, number: Int) -> some View {
        let language = gymCurrentLanguageCode()
        let weight = weightText(entry.weight)
        let label = gymText("Set \(number)", "Підхід \(number)", "Подход \(number)", languageCode: language)
        let value = "\(weight) \(gymLocalized("kg")) × \(entry.reps)"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            gymText(
                "Set \(number), \(weight) kilograms, \(entry.reps) repetitions",
                "Підхід \(number), \(weight) кілограмів, повторень: \(entry.reps)",
                "Подход \(number), вес: \(weight) кг, повторений: \(entry.reps)",
                languageCode: language
            )
        )
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
                        let languageCode = gymCurrentLanguageCode()
                        let localizedMuscleTitle = gymText(
                            muscle.titleEn,
                            muscle.titleUk,
                            muscle.titleRu,
                            languageCode: languageCode
                        )
                        GymPanel(
                            highlighted: selection.contains(muscle.id),
                            contentPadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                        ) {
                            Toggle(isOn: binding(for: muscle.id)) {
                                Text(localizedMuscleTitle)
                                    .font(.headline)
                            }
                            .tint(GymTheme.primaryAction)
                            .accessibilityHint(
                                gymText(
                                    "Adds or removes \(localizedMuscleTitle) from the manual mapping",
                                    "Додає або видаляє «\(localizedMuscleTitle)» у ручному зіставленні",
                                    "Добавляет или удаляет «\(localizedMuscleTitle)» в ручном сопоставлении",
                                    languageCode: languageCode
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

// MARK: - Exercise detail

fileprivate enum ExerciseDetailAction {
    case history
    case muscles
    case edit
    case toggleFavorite
    case delete
}

/// Primary and secondary muscles plus equipment of one exercise, from the same sources the rest of
/// the app uses: a saved manual mapping, else the built-in catalog, else the name guess. The
/// strongest muscles (weight 0.95 and up) are primary; a catalog exercise's first muscle always is.
fileprivate struct ExerciseInfo {
    let primaryMuscleIDs: [String]
    let secondaryMuscleIDs: [String]
    let equipmentID: String?

    init(exercise: Exercise, manualMuscles: [String: [MuscleContribution]]) {
        let contributions = MuscleMappingEngine.contributions(
            for: exercise.name,
            manualMappings: manualMuscles
        )
        let sorted = contributions.enumerated()
            .sorted {
                $0.element.weight != $1.element.weight
                    ? $0.element.weight > $1.element.weight
                    : $0.offset < $1.offset
            }
            .map(\.element)
        let strong = sorted.filter { $0.weight >= 0.95 }.map(\.muscleID)
        let primary = strong.isEmpty ? sorted.prefix(1).map(\.muscleID) : strong
        primaryMuscleIDs = primary
        secondaryMuscleIDs = sorted.map(\.muscleID).filter { !primary.contains($0) }

        let key = exercise.catalogKey ?? BuiltInExerciseCatalog.canonicalKey(forName: exercise.name)
        let equipment = key.flatMap { ExerciseSearchVocabulary.equipmentIdsByKey[$0] } ?? []
        equipmentID = equipment.first(where: { $0 != "bodyweight" }) ?? equipment.first
    }

    static func muscleTitle(_ id: String) -> String? {
        MuscleMappingEngine.muscleDefinitions.first(where: { $0.id == id }).map {
            gymText($0.titleEn, $0.titleUk, $0.titleRu, languageCode: gymCurrentLanguageCode())
        }
    }

    static func equipmentTitle(_ id: String) -> String? {
        let language = gymCurrentLanguageCode()
        switch id {
        case "band": return gymText("Band", "Гумка", "Резинка", languageCode: language)
        case "barbell": return gymText("Barbell", "Штанга", "Штанга", languageCode: language)
        case "bodyweight": return gymText("Bodyweight", "Власна вага", "Свой вес", languageCode: language)
        case "cable": return gymText("Cable", "Блок", "Блок", languageCode: language)
        case "dumbbell": return gymText("Dumbbells", "Гантелі", "Гантели", languageCode: language)
        case "machine": return gymText("Machine", "Тренажер", "Тренажёр", languageCode: language)
        case "plate": return gymText("Plate", "Диск", "Блин", languageCode: language)
        default: return nil
        }
    }

    var primaryMuscleTitles: [String] { primaryMuscleIDs.compactMap(Self.muscleTitle) }
    var secondaryMuscleTitles: [String] { secondaryMuscleIDs.compactMap(Self.muscleTitle) }
    var equipmentTitle: String? { equipmentID.flatMap(Self.equipmentTitle) }

    /// "Грудь · Гантели": first primary muscle, then equipment when known.
    var subtitle: String? {
        let parts = [primaryMuscleTitles.first, equipmentTitle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One row of a detail group: title (and optional subtitle) on the left, an optional value and
/// chevron on the right. Rows with an action are buttons; the rest are plain text.
private struct ExerciseDetailRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron = false
    var isDestructive = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? GymTheme.error : GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(GymTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// The pushed screen behind an exercise row: preview and name, best result, recent history,
/// muscles, and the actions that used to hide in the row's overflow menu.
@MainActor
private struct ExerciseDetailView: View {
    private static let recentSessionLimit = 5

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStore

    let exerciseID: UUID
    let perform: (ExerciseDetailAction, Exercise) -> Void

    var body: some View {
        GymBackground {
            if let exercise = store.exercise(id: exerciseID) {
                content(exercise)
            } else {
                // Deleted from this screen (or elsewhere): leave instead of showing a stale page.
                Color.clear.onAppear { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .gymTopBannerInset()
    }

    private func content(_ exercise: Exercise) -> some View {
        let language = gymCurrentLanguageCode()
        let displayName = gymExerciseName(exercise)
        let history = store.exerciseHistory(exerciseID: exercise.id)
        let stats = store.progressStats(exerciseID: exercise.id)
        let sessions = ExerciseHistoryGrouping.months(from: history).flatMap(\.sessions)
        let info = ExerciseInfo(
            exercise: exercise,
            manualMuscles: MuscleMappingEngine.manualContributionMap(from: store.muscleMappings)
        )
        let isCustom = BuiltInExerciseCatalog.canonicalKey(forName: exercise.name) == nil
            && BuiltInExerciseCatalog.definition(forKey: exercise.catalogKey) == nil

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(exercise, displayName: displayName, info: info)

                if !sessions.isEmpty {
                    bestGroup(stats: stats, history: history, sessions: sessions)
                }

                historyGroup(exercise, sessions: sessions, language: language)

                musclesGroup(exercise, info: info, language: language)

                actionsGroup(exercise, isCustom: isCustom, language: language)
            }
            .padding(.horizontal, GymTheme.screenHorizontalInset)
            .padding(.top, GymTheme.screenVerticalInset)
            .padding(.bottom, GymTheme.screenBottomInset)
        }
    }

    // MARK: Header

    private func header(_ exercise: Exercise, displayName: String, info: ExerciseInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseMediaButton(
                rawExerciseName: exercise.name,
                catalogKey: exercise.catalogKey,
                exerciseID: exercise.id,
                ownerKey: store.accountStorageKey,
                width: 200,
                height: 136,
                playOverlayDiameter: 32,
                cornerRadius: 14
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(gymExerciseDisplayName(displayName))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = info.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Best result

    private func bestGroup(
        stats: ExerciseProgressStats,
        history: [ExerciseHistoryEntry],
        sessions: [ExerciseHistoryGrouping.Session]
    ) -> some View {
        let language = gymCurrentLanguageCode()
        let best = history.max {
            $0.weight != $1.weight ? $0.weight < $1.weight : $0.reps < $1.reps
        }
        let locale = gymAppLocale()
        return ProgressGroup(
            title: gymText("Best result", "Найкращий результат", "Лучший результат", languageCode: language)
        ) {
            if let best {
                ExerciseDetailRow(
                    title: gymText("Best set", "Найкращий підхід", "Лучший подход", languageCode: language),
                    value: Self.setText(best.weight, best.reps)
                )
            }
            if stats.bestEstimatedOneRepMax > 0 {
                ProgressRowDivider()
                ExerciseDetailRow(
                    title: gymText("Estimated 1RM", "Оцінка 1ПМ", "Оценка 1ПМ", languageCode: language),
                    value: "\(stats.bestEstimatedOneRepMax.formatted(.number.locale(locale).precision(.fractionLength(0 ... 1))))\u{00A0}\(gymLocalized("kg"))"
                )
            }
            if let last = sessions.first {
                ProgressRowDivider()
                ExerciseDetailRow(
                    title: gymText("Last performed", "Останнє виконання", "Последний раз", languageCode: language),
                    value: gymShortDate(last.date)
                )
            }
            ProgressRowDivider()
            ExerciseDetailRow(
                title: gymText("Times done", "Виконано разів", "Выполнено раз", languageCode: language),
                value: stats.sessionCount.formatted(.number.locale(locale))
            )
        }
    }

    // MARK: History

    private func historyGroup(
        _ exercise: Exercise,
        sessions: [ExerciseHistoryGrouping.Session],
        language: String
    ) -> some View {
        let recent = Array(sessions.prefix(Self.recentSessionLimit))
        return ProgressGroup(title: gymText("History", "Історія", "История", languageCode: language)) {
            if recent.isEmpty {
                ExerciseDetailRow(
                    title: gymText("No history yet", "Історії ще немає", "Истории пока нет", languageCode: language)
                )
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { offset, session in
                    if offset > 0 { ProgressRowDivider() }
                    sessionRow(session, language: language)
                }
                if sessions.count > recent.count {
                    ProgressRowDivider()
                    ExerciseDetailRow(
                        title: gymText("All history", "Уся історія", "Вся история", languageCode: language),
                        showsChevron: true
                    ) {
                        perform(.history, exercise)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: ExerciseHistoryGrouping.Session, language: String) -> some View {
        let sets = gymPlural(
            session.setCount,
            en: ("set", "sets"),
            uk: ("підхід", "підходи", "підходів"),
            ru: ("подход", "подхода", "подходов"),
            languageCode: language
        )
        let best = session.sets.max {
            $0.weight != $1.weight ? $0.weight < $1.weight : $0.reps < $1.reps
        }
        return ExerciseDetailRow(
            title: gymShortDate(session.date),
            subtitle: "\(session.setCount)\u{00A0}\(sets)",
            value: best.map { Self.setText($0.weight, $0.reps) }
        )
    }

    private static func setText(_ weight: Double, _ reps: Int) -> String {
        let weightText = weight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))
        return "\(weightText)\u{00A0}\(gymLocalized("kg")) × \(reps)"
    }

    // MARK: Muscles

    private func musclesGroup(_ exercise: Exercise, info: ExerciseInfo, language: String) -> some View {
        ProgressGroup(title: gymText("Muscles", "М’язи", "Мышцы", languageCode: language)) {
            ExerciseDetailRow(
                title: gymText("Primary", "Основні", "Основные", languageCode: language),
                value: info.primaryMuscleTitles.isEmpty
                    ? "—"
                    : info.primaryMuscleTitles.joined(separator: ", ")
            )
            if !info.secondaryMuscleTitles.isEmpty {
                ProgressRowDivider()
                ExerciseDetailRow(
                    title: gymText("Secondary", "Додаткові", "Дополнительные", languageCode: language),
                    value: info.secondaryMuscleTitles.joined(separator: ", ")
                )
            }
            ProgressRowDivider()
            ExerciseDetailRow(
                title: gymText("Edit muscles", "Змінити м’язи", "Изменить мышцы", languageCode: language),
                showsChevron: true
            ) {
                perform(.muscles, exercise)
            }
        }
    }

    // MARK: Actions

    private func actionsGroup(_ exercise: Exercise, isCustom: Bool, language: String) -> some View {
        ProgressGroup {
            ExerciseDetailRow(
                title: exercise.isFavorite
                    ? gymText("Remove from favorites", "Прибрати з обраного", "Убрать из избранного", languageCode: language)
                    : gymText("Add to favorites", "Додати в обране", "В избранное", languageCode: language)
            ) {
                perform(.toggleFavorite, exercise)
            }
            ProgressRowDivider()
            ExerciseDetailRow(title: gymLocalized("Weight steps"), showsChevron: true) {
                perform(.edit, exercise)
            }
            if isCustom {
                ProgressRowDivider()
                ExerciseDetailRow(
                    title: gymText("Edit", "Змінити", "Изменить", languageCode: language),
                    showsChevron: true
                ) {
                    perform(.edit, exercise)
                }
            }
            ProgressRowDivider()
            ExerciseDetailRow(title: gymLocalized("Delete", languageCode: language), isDestructive: true) {
                perform(.delete, exercise)
            }
        }
    }
}
