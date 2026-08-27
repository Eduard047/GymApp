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
        let workouts = gymCount(
            linkedWorkoutCount,
            englishOne: "workout",
            englishMany: "workouts",
            ukrainianOne: "тренування",
            ukrainianFew: "тренування",
            ukrainianMany: "тренувань",
            languageCode: languageCode
        )
        let sets = gymCount(
            linkedSetCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів",
            languageCode: languageCode
        )
        let deletedWorkouts = gymCount(
            deletedWorkoutCount,
            englishOne: "workout",
            englishMany: "workouts",
            ukrainianOne: "тренування",
            ukrainianFew: "тренування",
            ukrainianMany: "тренувань",
            languageCode: languageCode
        )
        return String(
            format: gymLocalized(
                "The exercise will be permanently deleted. Linked impact: %1$@; %2$@; empty workouts deleted: %3$@. This cannot be undone.",
                languageCode: languageCode
            ),
            locale: AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale,
            arguments: [workouts, sets, deletedWorkouts]
        )
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
        case error(String)

        var id: String {
            switch self {
            case let .delete(target):
                return "delete-\(target.id.uuidString)"
            case let .error(message):
                return "error-\(message)"
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
    @State private var resultMessage: String?
    @State private var resultIsError = false

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: GymTheme.contentSpacing) {
                    header

                    if let resultMessage {
                        GymStatusBanner(message: resultMessage, isError: resultIsError)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    exerciseLibrary
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $presentedSheet, content: presentedContent)
        .alert(item: $activeAlert, content: makeAlert)
    }

    private var header: some View {
        GymScreenHeader(
            title: "Exercises"
        ) {
            addExerciseButton
                .fixedSize(horizontal: true, vertical: false)
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

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                    "Додай власну вправу, щоб почати формувати бібліотеку.",
                                    "Добавь свое упражнение, чтобы начать формировать библиотеку.",
                                    languageCode: gymCurrentLanguageCode()
                                )
                                : gymText(
                                    "Try another name, body area, or muscle group.",
                                    "Спробуйте іншу назву, частину тіла або групу м’язів.",
                                    "Попробуй другое название, часть тела или группу мышц.",
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
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Label(
                            gymLocalized("Favorites"),
                            systemImage: favoritesOnly ? "heart.fill" : "heart"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(favoritesOnly ? GymTheme.primary : GymTheme.textSecondary)
                    .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                    .accessibilityHint(gymLocalized("Shows only favorite exercises"))

                    ForEach(ExerciseBodyFilter.allCases) { filter in
                        Button(filter.localizedTitle) { bodyFilter = filter }
                            .buttonStyle(.bordered)
                            .tint(bodyFilter == filter ? GymTheme.primary : GymTheme.textSecondary)
                            .accessibilityAddTraits(bodyFilter == filter ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ExerciseSortMode.allCases) { mode in
                        Button(mode.localizedTitle) { sortMode = mode }
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
                        .accessibilityAddTraits(muscleFilter == nil ? .isSelected : [])
                    ForEach(MuscleMappingEngine.muscleDefinitions) { muscle in
                        Button(gymText(muscle.titleEn, muscle.titleUk, languageCode: gymCurrentLanguageCode())) {
                            muscleFilter = muscleFilter == muscle.id ? nil : muscle.id
                        }
                        .buttonStyle(.bordered)
                        .tint(muscleFilter == muscle.id ? GymTheme.primary : GymTheme.textSecondary)
                        .accessibilityAddTraits(muscleFilter == muscle.id ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

        }
    }

    private func clearFilters() {
        searchText = ""
        bodyFilter = .all
        muscleFilter = nil
        favoritesOnly = false
    }

    private func exerciseCard(_ exercise: Exercise) -> some View {
        let displayName = gymExerciseName(exercise)

        return GymPanel {
            HStack(alignment: .center, spacing: 10) {
                ExerciseMediaButton(
                    rawExerciseName: exercise.name,
                    catalogKey: exercise.catalogKey,
                    exerciseID: exercise.id,
                    ownerKey: store.accountStorageKey
                )
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 4)

                favoriteButton(exercise, displayName: displayName)

                Menu {
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
                        Label("Machine weights", systemImage: "scalemass")
                    }

                    if catalogDefinition(for: exercise) == nil {
                        Button {
                            presentedSheet = .editExercise(exercise)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        activeAlert = .delete(
                            ExerciseLibraryDeletionTarget(
                                store: store,
                                exercise: exercise,
                                displayName: displayName
                            )
                        )
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
    }

    private func favoriteButton(_ exercise: Exercise, displayName: String) -> some View {
        Button {
            do {
                _ = try store.toggleExerciseFavorite(id: exercise.id)
            } catch {
                activeAlert = .error(errorMessage(error))
            }
        } label: {
            Image(systemName: exercise.isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(exercise.isFavorite ? GymTheme.primary : GymTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(favoriteAccessibilityLabel(exercise, displayName: displayName))
        .accessibilityValue(favoriteAccessibilityValue(exercise))
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
            sessionCounts: Dictionary(
                uniqueKeysWithValues: store.exercises.map { exercise in
                    (exercise.id, store.progressStats(exerciseID: exercise.id).sessionCount)
                }
            )
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
                    resultMessage = "Exercise added."
                    resultIsError = false
                }
            }

        case let .editExercise(exercise):
            NavigationStack {
                let displayName = gymExerciseName(exercise)
                ExerciseEditorSheet(
                    title: catalogDefinition(for: exercise) == nil ? "Edit exercise" : "Machine weights",
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
                    resultMessage = "Exercise updated."
                    resultIsError = false
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
                    resultIsError = false
                }
            }
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
                        resultMessage = gymLocalized(
                            "The exercise or its linked workout data changed before deletion. Review it and try again.",
                            languageCode: languageCode
                        )
                        resultIsError = true
                        return
                    }
                    do {
                        try store.deleteExercise(id: target.exerciseID, cascadeFromWorkouts: true)
                        target.restTimerIDs.forEach { appState.restTimers.cancel(id: $0) }
                        resultMessage = "Exercise and linked workout entries deleted."
                        resultIsError = false
                    } catch {
                        activeAlert = .error(errorMessage(error))
                    }
                },
                secondaryButton: .cancel(Text(gymLocalized("Cancel", languageCode: languageCode)))
            )

        case let .error(message):
            return Alert(
                title: Text("Couldn’t complete the action"),
                message: Text(gymLocalized(message)),
                dismissButton: .default(Text("OK"))
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

    var errorDescription: String? {
        switch self {
        case .invalidWeights:
            return "Enter 1–128 valid machine weights between 0 and 1,000,000 kg."
        }
    }
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
        _name = State(initialValue: initialName)
        _usesExactMachineWeights = State(initialValue: initialMachineLoadProfile != nil)
        _loadDirection = State(initialValue: initialMachineLoadProfile?.direction ?? defaultLoadDirection)
        _allowedWeightsText = State(
            initialValue: initialMachineLoadProfile?.allowedWeightsKg
                .map(Self.displayWeight)
                .joined(separator: "\n") ?? ""
        )
    }

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GymSectionTitle(
                        title: title
                    )

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
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("2.5 kg") { applyPreset(step: 2.5, maximum: 200) }
                                    .buttonStyle(.bordered)
                                Button("5 kg") { applyPreset(step: 5, maximum: 300) }
                                    .buttonStyle(.bordered)
                            }

                            Text("Available weights (kg), one per line")
                                .font(.caption.weight(.semibold))
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
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func save() {
        do {
            let machineLoadProfile: MachineLoadProfile?
            if usesExactMachineWeights {
                guard allowedWeightsText.utf8.count <= 2_048 else {
                    throw ExerciseEditorValidationError.invalidWeights
                }
                let tokens = allowedWeightsText.components(
                    separatedBy: CharacterSet.whitespacesAndNewlines.union(
                        CharacterSet(charactersIn: ";")
                    )
                ).filter { !$0.isEmpty }
                let parsed = tokens.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                guard parsed.count == tokens.count,
                      !parsed.isEmpty,
                      parsed.count <= MachineLoadProfile.maximumAllowedWeightCount else {
                    throw ExerciseEditorValidationError.invalidWeights
                }
                let normalized = Array(Set(parsed)).sorted()
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
        } catch {
            self.error = gymErrorMessage(error)
        }
    }

    private static func displayWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(weight)
    }

    private func applyPreset(step: Double, maximum: Double) {
        let count = min(
            MachineLoadProfile.maximumAllowedWeightCount,
            Int(floor(maximum / step))
        )
        allowedWeightsText = (1 ... count)
            .map { Self.displayWeight(Double($0) * step) }
            .joined(separator: "\n")
        error = nil
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
                            languageCode: languageCode
                        )
                        GymPanel(
                            highlighted: selection.contains(muscle.id),
                            contentPadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                        ) {
                            Toggle(isOn: binding(for: muscle.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizedMuscleTitle)
                                        .font(.headline)
                                    Text(exerciseMuscleMappingSecondaryTitle(
                                        english: muscle.titleEn,
                                        ukrainian: muscle.titleUk,
                                        languageCode: languageCode
                                    ))
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.textSecondary)
                                }
                            }
                            .tint(GymTheme.primary)
                            .accessibilityHint(
                                gymText(
                                    "Adds or removes \(localizedMuscleTitle) from the manual mapping",
                                    "Додає або видаляє «\(localizedMuscleTitle)» у ручному зіставленні",
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
