import SwiftUI

@MainActor
struct AddWorkoutView: View {
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var garminCloud: GarminCloudService

    @State private var date = Date()
    @State private var note = ""
    @State private var profile = TrainingProfile()
    @State private var drafts: [WorkoutEditorExerciseDraft] = []
    @State private var queueForGarmin = false
    @State private var showingExercisePicker = false
    @State private var showingPreviousPicker = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isSaving = false

    private let isCloudAccount: Bool
    private let onSaved: (UUID) -> Void
    private let onCancel: () -> Void
    private let reportStatus: (String, Bool) -> Void

    init(
        appState: AppState,
        onSaved: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.init(
            store: appState.workoutStore,
            garminCloud: appState.garminCloud,
            isCloudAccount: appState.auth.session?.cloud != nil,
            onSaved: onSaved,
            onCancel: onCancel,
            onStatus: { [weak appState] message, isError in
                appState?.show(message: message, isError: isError)
            }
        )
    }

    init(
        store: WorkoutStore,
        garminCloud: GarminCloudService,
        isCloudAccount: Bool,
        onSaved: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void = {},
        onStatus: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        _store = ObservedObject(wrappedValue: store)
        _garminCloud = ObservedObject(wrappedValue: garminCloud)
        _profile = State(initialValue: Self.loadProfile(storageKey: store.accountStorageKey))
        self.isCloudAccount = isCloudAccount
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.reportStatus = onStatus
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero

                    if let statusMessage {
                        GymStatusBanner(message: statusMessage, isError: statusIsError)
                    }

                    sessionDetails
                    templatePanel
                    profilePanel
                    smartCoachPanel
                    editorSection

                    if isCloudAccount {
                        garminPanel
                    }

                    saveButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Add workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                exercises: store.exercises,
                selectedExerciseIDs: Set(drafts.map(\.exerciseID)),
                frequentExerciseIDs: frequentExerciseIDs,
                onSelect: addExercise,
                onCreate: { try store.addExercise(name: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPreviousPicker) {
            PreviousWorkoutPicker(
                workouts: store.workouts.sorted { $0.date > $1.date },
                exerciseName: exerciseName,
                onSelect: applyPreviousWorkout
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: profile) { newProfile in
            Self.saveProfile(newProfile, storageKey: store.accountStorageKey)
        }
    }

    private var hero: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Build today's session", systemImage: "dumbbell.fill")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Start from a split, ask Smart Coach, or build every set yourself.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    GymInfoPill(
                        gymCount(
                            drafts.count,
                            englishOne: "exercise",
                            englishMany: "exercises",
                            ukrainianOne: "вправа",
                            ukrainianFew: "вправи",
                            ukrainianMany: "вправ"
                        ),
                        systemImage: "figure.strengthtraining.traditional",
                        accent: .white
                    )
                    GymInfoPill(
                        gymCount(
                            drafts.reduce(0) { $0 + $1.sets.count },
                            englishOne: "set",
                            englishMany: "sets",
                            ukrainianOne: "підхід",
                            ukrainianFew: "підходи",
                            ukrainianMany: "підходів"
                        ),
                        systemImage: "list.number",
                        accent: .white
                    )
                }
            }
        }
    }

    private var sessionDetails: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    eyebrow: "Session",
                    title: "Date and notes",
                    supporting: "Notes are included in your local and cloud backup."
                )

                DatePicker("Workout date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)

                TextField("Notes (optional)", text: $note, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .gymTextFieldChrome()
                    .accessibilityHint("Add context such as energy, technique, or the training plan")
            }
        }
    }

    private var templatePanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    eyebrow: "Templates",
                    title: "Choose a training day",
                    supporting: "Templates use your exercise catalog and recent weights."
                )

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(WorkoutTemplatePreset.allCases) { preset in
                            Button {
                                applyTemplate(preset)
                            } label: {
                                Label(preset.title, systemImage: preset.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(GymTheme.primary.opacity(0.1), in: Capsule())
                            }
                            .accessibilityHint(
                                gymText(
                                    "Replaces the current editor with a \(preset.title) template",
                                    "Замінює вміст редактора шаблоном «\(preset.title)»",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { previousActions }
                    VStack(spacing: 10) { previousActions }
                }
            }
        }
    }

    @ViewBuilder
    private var previousActions: some View {
        Button {
            guard let latest = store.latestWorkoutTemplate else {
                show("No previous workout is available yet.", error: true)
                return
            }
            applyPreviousWorkout(latest)
        } label: {
            Label("Repeat latest", systemImage: "repeat")
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(store.latestWorkoutTemplate == nil)

        Button {
            showingPreviousPicker = true
        } label: {
            Label("Copy previous", systemImage: "doc.on.doc")
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(store.workouts.isEmpty)
    }

    private var profilePanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    eyebrow: "Profile",
                    title: "Coach settings",
                    supporting: "The recommendation engine adapts load, repetitions, and workout balance."
                )

                profilePicker("Split", selection: $profile.split) { $0.displayName }
                profilePicker("Goal", selection: $profile.goal) { $0.displayName }
                profilePicker("Calories", selection: $profile.calorieMode) { $0.displayName }

                Stepper(value: $profile.workoutsPerWeek, in: 2 ... 6) {
                    HStack {
                        Text("Workouts per week")
                        Spacer()
                        Text(profile.workoutsPerWeek.formatted())
                            .font(.body.monospacedDigit().weight(.bold))
                            .foregroundStyle(GymTheme.primary)
                    }
                }
                .accessibilityValue(
                    gymCount(
                        profile.workoutsPerWeek,
                        englishOne: "workout per week",
                        englishMany: "workouts per week",
                        ukrainianOne: "тренування на тиждень",
                        ukrainianFew: "тренування на тиждень",
                        ukrainianMany: "тренувань на тиждень"
                    )
                )
            }
        }
    }

    private func profilePicker<Value: Hashable & CaseIterable>(
        _ title: String,
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        HStack {
            Text(gymLocalized(title))
            Spacer()
            Picker(gymLocalized(title), selection: selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(gymLocalized(label(value))).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var smartCoachPanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Smart Coach",
                    title: "Generate the next workout",
                    supporting: "Uses your split, recent fatigue, neglected muscles, and progressive overload history."
                )
                Button(action: applySmartCoach) {
                    Label("Build smart workout", systemImage: "sparkles")
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(store.exercises.isEmpty)
                .accessibilityHint("Replaces the editor with the recommended exercises and sets")
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        HStack {
            GymSectionTitle(
                eyebrow: "Plan builder",
                title: "Planned exercises and sets",
                supporting: drafts.isEmpty
                    ? "Add an exercise to begin."
                    : "Planned rows are targets. They do not start rest timers or count as completed until you save them."
            )
            Spacer(minLength: 8)
            Button {
                showingExercisePicker = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add exercise")
        }
        .padding(.horizontal, 4)

        if drafts.isEmpty {
            GymPanel {
                GymContentUnavailableView {
                    Label("No exercises", systemImage: "dumbbell")
                } description: {
                    Text("Choose a template, ask Smart Coach, or add an exercise manually.")
                } actions: {
                    Button("Add exercise") { showingExercisePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ForEach(drafts) { item in
                if let exercise = store.exercise(id: item.exerciseID) {
                    WorkoutDraftExerciseCard(
                        draft: binding(for: item.id),
                        exerciseID: exercise.id,
                        exerciseMediaOwnerKey: store.accountStorageKey,
                        exerciseName: gymExerciseName(exercise),
                        lastWeight: store.lastWeight(exerciseID: exercise.id),
                        onDeleteExercise: { drafts.removeAll { $0.id == item.id } }
                    )
                }
            }
        }
    }

    private var garminPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $queueForGarmin) {
                    Label("Queue for Garmin", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.headline)
                }
                .disabled(garminCloud.selectedDevice == nil)
                Text(
                    garminCloud.selectedDevice == nil
                        ? gymLocalized("Select or pair a Garmin watch in Account settings before queueing a plan.")
                        : gymLocalized("Garmin plan mode: after saving, every planned row is sent to the selected watch as a target. The watch logs what you actually complete.")
                )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if garminCloud.isWorking {
                    ProgressView("Queueing plan…")
                }
            }
        }
    }

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Completed mode: saving immediately adds every planned row to workout history and summaries.")
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: save) {
                if isSaving {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Saving…")
                    }
                } else {
                    Label("Save as completed workout", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(isSaving || drafts.isEmpty)
            .accessibilityHint(
                gymLocalized(
                    queueForGarmin && isCloudAccount
                        ? "Adds every planned row to history as completed and also queues the rows as Garmin targets"
                        : "Adds every planned row to history and summaries as completed"
                )
            )
        }
    }

    private func binding(for id: UUID) -> Binding<WorkoutEditorExerciseDraft> {
        Binding(
            get: { drafts.first(where: { $0.id == id }) ?? WorkoutEditorExerciseDraft(exerciseID: UUID()) },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                drafts[index] = value
            }
        )
    }

    private func exerciseName(_ exerciseID: UUID) -> String {
        store.exercise(id: exerciseID).map { gymExerciseName($0) } ?? gymLocalized("Deleted exercise")
    }

    private var frequentExerciseIDs: [UUID] {
        Dictionary(grouping: store.allExerciseHistory(), by: \.exerciseID)
            .map { exerciseID, entries in
                (
                    exerciseID: exerciseID,
                    sessionCount: Set(entries.map(\.workoutID)).count,
                    lastUsedAt: entries.map(\.sessionDate).max() ?? .distantPast
                )
            }
            .sorted { left, right in
                if left.sessionCount != right.sessionCount {
                    return left.sessionCount > right.sessionCount
                }
                if left.lastUsedAt != right.lastUsedAt {
                    return left.lastUsedAt > right.lastUsedAt
                }
                return left.exerciseID.uuidString < right.exerciseID.uuidString
            }
            .prefix(12)
            .map(\.exerciseID)
    }

    private func addExercise(_ exercise: Exercise) {
        guard !drafts.contains(where: { $0.exerciseID == exercise.id }) else { return }
        drafts.insert(
            WorkoutEditorExerciseDraft(
                exerciseID: exercise.id,
                sets: [
                    WorkoutEditorSetDraft(
                        weight: store.lastWeight(exerciseID: exercise.id) ?? 0,
                        reps: 10
                    )
                ]
            ),
            at: 0
        )
    }

    private func applyPreviousWorkout(_ workout: WorkoutSession) {
        drafts = workout.exercises.map { block in
            WorkoutEditorExerciseDraft(
                exerciseID: block.exerciseID,
                sets: block.sets.map { WorkoutEditorSetDraft(weight: $0.weight, reps: $0.reps) }
            )
        }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note = workout.note ?? ""
        }
        show(gymLocalized("Previous workout copied. Adjust any set before saving."), error: false)
    }

    private func applyTemplate(_ preset: WorkoutTemplatePreset) {
        if preset == .deload {
            guard let latest = store.latestWorkoutTemplate else {
                show(gymLocalized("A deload template needs a previous workout."), error: true)
                return
            }
            drafts = latest.exercises.map { block in
                WorkoutEditorExerciseDraft(
                    exerciseID: block.exerciseID,
                    sets: block.sets.map {
                        WorkoutEditorSetDraft(
                            weight: (($0.weight * 0.9) * 2).rounded() / 2,
                            reps: min(10_000, $0.reps + 1)
                        )
                    }
                )
            }
            note = note.isEmpty ? gymLocalized("Deload") : note
            show(gymLocalized("Deload uses 90% of the latest weights with one extra repetition."), error: false)
            return
        }

        let candidates = store.exercises
            .map { exercise in
                (
                    exercise,
                    Set(MuscleMappingEngine.defaultContributions(for: exercise.name).map(\.muscleID))
                        .intersection(preset.targetMuscles).count,
                    store.exerciseHistory(exerciseID: exercise.id).first?.sessionDate ?? .distantPast
                )
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return gymExerciseName($0.0).localizedCaseInsensitiveCompare(gymExerciseName($1.0)) == .orderedAscending
            }
            .prefix(preset == .upper ? 6 : 5)

        guard !candidates.isEmpty else {
            show(gymLocalized("No matching exercises are in your catalog. Add exercises first."), error: true)
            return
        }
        let history = store.allExerciseHistory()
        drafts = candidates.map { exercise, _, _ in
            let recommendation = RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: history,
                exerciseCatalogKey: exercise.catalogKey,
                exerciseName: exercise.name,
                trainingProfile: profile
            )
            return WorkoutEditorExerciseDraft(
                exerciseID: exercise.id,
                sets: recommendation.sets.map {
                    WorkoutEditorSetDraft(
                        weight: $0.weight ?? store.lastWeight(exerciseID: exercise.id) ?? 0,
                        reps: $0.reps
                    )
                }
            )
        }
        show(
            gymText(
                "\(preset.title) template loaded from your exercise catalog.",
                "Шаблон «\(preset.title)» завантажено з каталогу вправ.",
                languageCode: gymCurrentLanguageCode()
            ),
            error: false
        )
    }

    private func applySmartCoach() {
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: store.exercises,
            history: store.allExerciseHistory(),
            trainingProfile: profile
        )
        guard !plan.exercises.isEmpty else {
            show(gymLocalized("Smart Coach needs exercises in your catalog."), error: true)
            return
        }
        drafts = plan.exercises.map { item in
            WorkoutEditorExerciseDraft(
                exerciseID: item.exercise.id,
                sets: item.recommendation.sets.map {
                    WorkoutEditorSetDraft(
                        weight: $0.weight ?? store.lastWeight(exerciseID: item.exercise.id) ?? 0,
                        reps: $0.reps
                    )
                }
            )
        }
        show(
            gymText(
                "Smart Coach built a \(plan.focus.displayName.lowercased()) workout.",
                "Розумний тренер створив тренування «\(plan.focus.displayName.lowercased())».",
                languageCode: gymCurrentLanguageCode()
            ),
            error: false
        )
    }

    private func validationMessage() -> String? {
        guard !drafts.isEmpty else { return gymLocalized("Add at least one exercise.") }
        if queueForGarmin && isCloudAccount && garminCloud.selectedDevice == nil {
            return gymLocalized("Select or pair a Garmin watch in Account settings before queueing a plan.")
        }
        for draft in drafts {
            guard store.exercise(id: draft.exerciseID) != nil else {
                return gymLocalized("One selected exercise no longer exists.")
            }
            guard !draft.sets.isEmpty else {
                return gymLocalized("Every exercise needs at least one set.")
            }
            for set in draft.sets {
                guard set.weight.isFinite, set.weight >= 0 else {
                    return gymLocalized("Weight must be a non-negative number.")
                }
                guard (1 ... 10_000).contains(set.reps) else {
                    return gymLocalized("Repetitions must be at least one.")
                }
            }
        }
        return nil
    }

    private func save() {
        if let message = validationMessage() {
            show(message, error: true)
            return
        }
        isSaving = true
        statusMessage = nil

        do {
            let workout = try store.createWorkout(
                date: date,
                note: note,
                exercises: drafts.map(\.storeDraft)
            )
            let shouldQueue = queueForGarmin && isCloudAccount
            Task { @MainActor in
                if shouldQueue {
                    do {
                        try await garminCloud.submit(
                            plan: garminPlan(for: workout),
                            clientRequestID: workout.id
                        )
                        let message = gymLocalized(
                            garminCloud.lastMessage ?? "Workout saved and queued for Garmin."
                        )
                        reportStatus(message, false)
                    } catch {
                        let message = gymErrorMessage(error)
                        reportStatus(
                            gymText(
                                "Workout saved, but Garmin queue failed: \(message)",
                                "Тренування збережено, але додати до черги Garmin не вдалося: \(message)",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            true
                        )
                    }
                } else {
                    reportStatus(gymLocalized("Workout saved."), false)
                }
                isSaving = false
                onSaved(workout.id)
            }
        } catch {
            isSaving = false
            show(gymErrorMessage(error), error: true)
        }
    }

    private func garminPlan(for workout: WorkoutSession) -> GarminWorkoutPlan {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return GarminWorkoutPlan(
            source: "gymapp-ios",
            version: 1,
            title: gymText(
                "Workout · \(gymFormattedDate(workout.date, date: .abbreviated, time: .omitted))",
                "Тренування · \(gymFormattedDate(workout.date, date: .abbreviated, time: .omitted))",
                languageCode: gymCurrentLanguageCode()
            ),
            createdAt: formatter.string(from: Date()),
            startedAt: formatter.string(from: workout.date),
            note: workout.note ?? "",
            exercises: workout.exercises.compactMap { block in
                guard let exercise = store.exercise(id: block.exerciseID) else { return nil }
                return GarminPlanExercise(
                    name: exercise.name,
                    sets: block.sets.enumerated().map { index, set in
                        GarminPlanSet(weight: set.weight, reps: set.reps, orderIndex: index)
                    }
                )
            }
        )
    }

    private func show(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }

    private static func profileDefaultsKey(storageKey: String) -> String {
        "gymapp.training-profile.v1.\(storageKey)"
    }

    private static func loadProfile(storageKey: String) -> TrainingProfile {
        guard let data = UserDefaults.standard.data(
            forKey: profileDefaultsKey(storageKey: storageKey)
        ), let profile = try? JSONDecoder().decode(TrainingProfile.self, from: data) else {
            return TrainingProfile()
        }
        return TrainingProfile(
            split: profile.split,
            workoutsPerWeek: profile.workoutsPerWeek,
            goal: profile.goal,
            calorieMode: profile.calorieMode
        )
    }

    private static func saveProfile(_ profile: TrainingProfile, storageKey: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileDefaultsKey(storageKey: storageKey))
    }
}

private struct PreviousWorkoutPicker: View {
    @Environment(\.dismiss) private var dismiss

    let workouts: [WorkoutSession]
    let exerciseName: (UUID) -> String
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                Button {
                    onSelect(workout)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(gymFormattedDate(workout.date, date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text(workout.exercises.map { exerciseName($0.exerciseID) }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(workoutCounts(workout))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityHint("Copies this workout into the editor")
            }
            .navigationTitle("Copy workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func workoutCounts(_ workout: WorkoutSession) -> String {
        let exercises = gymCount(
            workout.exercises.count,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправа",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ"
        )
        let sets = gymCount(
            workout.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        return "\(exercises) · \(sets)"
    }
}

private extension SmartWorkoutFocus {
    var displayName: String {
        switch self {
        case .upper: gymLocalized("Upper")
        case .lower: gymLocalized("Lower")
        case .push: gymLocalized("Push")
        case .pull: gymLocalized("Pull")
        case .legs: gymLocalized("Legs")
        case .fullBody: gymLocalized("Full body")
        }
    }
}
