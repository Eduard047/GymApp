import SwiftUI

@MainActor
struct WorkoutDetailView: View {
    private enum PendingDeletion: Equatable {
        case set(blockID: UUID, setID: UUID)
        case exercise(blockID: UUID)

        var message: String {
            switch self {
            case .set: "Set deleted"
            case .exercise: "Exercise deleted"
            }
        }
    }

    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var restTimers: RestTimerManager

    @State private var date: Date
    @State private var note: String
    @State private var showingExercisePicker = false
    @State private var showingDeleteWorkout = false
    @State private var statusMessage: String?
    @State private var pendingDeletion: PendingDeletion?
    @State private var deletionTask: Task<Void, Never>?

    private let workoutID: UUID
    private let onFinish: (UUID) -> Void
    private let onDeleted: () -> Void
    private let reportStatus: (String, Bool) -> Void

    init(
        appState: AppState,
        workoutID: UUID,
        onFinish: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.init(
            store: appState.workoutStore,
            restTimers: appState.restTimers,
            workoutID: workoutID,
            onFinish: onFinish,
            onDeleted: onDeleted,
            onStatus: { [weak appState] message, isError in
                appState?.show(message: message, isError: isError)
            }
        )
    }

    init(
        store: WorkoutStore,
        restTimers: RestTimerManager,
        workoutID: UUID,
        onFinish: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void = {},
        onStatus: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        _store = ObservedObject(wrappedValue: store)
        _restTimers = ObservedObject(wrappedValue: restTimers)
        self.workoutID = workoutID
        self.onFinish = onFinish
        self.onDeleted = onDeleted
        self.reportStatus = onStatus
        let workout = store.workout(id: workoutID)
        _date = State(initialValue: workout?.date ?? Date())
        _note = State(initialValue: workout?.note ?? "")
    }

    var body: some View {
        GymBackground {
            if let workout = store.workout(id: workoutID) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        hero(workout)

                        if let statusMessage {
                            GymStatusBanner(message: statusMessage, isError: true)
                        }

                        metadataPanel
                        exerciseSection(workout)
                        finishPanel(workout)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                ContentUnavailableView(
                    "Workout unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("It may have been deleted on another screen.")
                )
            }
        }
        .navigationTitle("Workout detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteWorkout = true
                } label: {
                    Label("Delete workout", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                exercises: store.exercises,
                selectedExerciseIDs: Set(store.workout(id: workoutID)?.exercises.map(\.exerciseID) ?? []),
                onSelect: addExercise,
                onCreate: { try store.addExercise(name: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Delete workout?", isPresented: $showingDeleteWorkout) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deleteWorkout)
        } message: {
            Text("This removes the workout and every set. This action cannot be undone.")
        }
        .safeAreaInset(edge: .bottom) {
            if let pendingDeletion {
                undoBar(pendingDeletion)
            }
        }
        .onDisappear {
            commitPendingDeletion()
        }
    }

    private func hero(_ workout: WorkoutSession) -> some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(gymFormattedDate(workout.date, date: .long, time: .shortened))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(workout.note?.isEmpty == false ? workout.note! : gymLocalized("Saved workout"))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    GymMetricTile(label: "Exercises", value: workout.exercises.count.formatted(), onHero: true)
                    GymMetricTile(label: "Sets", value: workout.setCount.formatted(), onHero: true)
                    GymMetricTile(
                        label: "Volume",
                        value: workout.totalVolume.formatted(.number.precision(.fractionLength(0 ... 1))),
                        onHero: true
                    )
                }
            }
        }
    }

    private var metadataPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    eyebrow: "Session",
                    title: "Date and note",
                    supporting: "Save changes before finishing the workout."
                )
                DatePicker("Workout date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Notes (optional)", text: $note, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .gymTextFieldChrome()
                Button(action: saveMetadata) {
                    Label("Save session details", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GymSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ workout: WorkoutSession) -> some View {
        HStack {
            GymSectionTitle(
                eyebrow: "Log",
                title: "Exercises and sets",
                supporting: "Add Set starts a 90 second rest timer."
            )
            Spacer(minLength: 8)
            Button {
                showingExercisePicker = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add exercise to workout")
        }
        .padding(.horizontal, 4)

        ForEach(visibleExercises(workout)) { block in
            storedExerciseCard(workout: workout, block: block)
        }
    }

    private func storedExerciseCard(
        workout: WorkoutSession,
        block: WorkoutExercise
    ) -> some View {
        let exercise = store.exercise(id: block.exerciseID)
        let name = exercise.map { gymExerciseName($0) } ?? gymLocalized("Deleted exercise")
        let priorHistory = store.exerciseHistory(exerciseID: block.exerciseID)
            .filter { $0.workoutID != workout.id }
        let priorMaxWeight = priorHistory.map(\.weight).max()
        let priorEstimatedMax = priorHistory.map(\.estimatedOneRepMax).max()
        let timerID = timerKey(blockID: block.id)

        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(priorMaxWeight.map {
                            gymText(
                                "Previous best: \($0.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                "Попередній рекорд: \($0.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                languageCode: gymCurrentLanguageCode()
                            )
                        } ?? gymLocalized("First logged workout"))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        stageDeletion(.exercise(blockID: block.id))
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        gymText(
                            "Delete \(name) from workout",
                            "Видалити «\(name)» із тренування",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }

                WorkoutRestTimerControls(
                    manager: restTimers,
                    timerID: timerID,
                    exerciseName: name
                )

                ForEach(Array(visibleSets(block).enumerated()), id: \.element.id) { index, set in
                    StoredWorkoutSetEditorRow(
                        set: set,
                        position: index,
                        prLabels: prLabels(
                            set: set,
                            previousMaxWeight: priorMaxWeight,
                            previousEstimatedMax: priorEstimatedMax
                        ),
                        lastWeight: store.lastWeight(exerciseID: block.exerciseID, before: workout.date),
                        onSave: { weight, reps in
                            do {
                                try store.updateSet(
                                    workoutID: workout.id,
                                    workoutExerciseID: block.id,
                                    setID: set.id,
                                    weight: weight,
                                    reps: reps
                                )
                            } catch {
                                show(error)
                            }
                        },
                        onDelete: {
                            stageDeletion(.set(blockID: block.id, setID: set.id))
                        }
                    )
                }

                Button {
                    addSet(to: block, workout: workout, exerciseName: name)
                } label: {
                    Label("Add set · start 90 sec rest", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Adds a set using the latest values and starts the rest timer")
            }
        }
    }

    private func finishPanel(_ workout: WorkoutSession) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Finish",
                    title: "Complete this workout",
                    supporting: "See XP, personal records, trained muscles, missions, and badges."
                )
                Button {
                    finish(workout)
                } label: {
                    Label("Finish and view summary", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(GymPrimaryButtonStyle())
            }
        }
    }

    private func undoBar(_ pending: PendingDeletion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(GymTheme.error)
                .accessibilityHidden(true)
            Text(gymLocalized(pending.message))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("Undo", action: undoDeletion)
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private func visibleExercises(_ workout: WorkoutSession) -> [WorkoutExercise] {
        workout.exercises.filter { block in
            guard case .exercise(let hiddenID) = pendingDeletion else { return true }
            return block.id != hiddenID
        }
    }

    private func visibleSets(_ block: WorkoutExercise) -> [WorkoutSet] {
        block.sets.filter { set in
            guard case .set(let pendingBlockID, let hiddenSetID) = pendingDeletion,
                  pendingBlockID == block.id else { return true }
            return set.id != hiddenSetID
        }
    }

    private func prLabels(
        set: WorkoutSet,
        previousMaxWeight: Double?,
        previousEstimatedMax: Double?
    ) -> [String] {
        var labels: [String] = []
        if set.weight > (previousMaxWeight ?? -1) { labels.append("Weight PR") }
        if set.estimatedOneRepMax > (previousEstimatedMax ?? -1) { labels.append("Estimated 1RM PR") }
        return labels
    }

    private func addExercise(_ exercise: Exercise) {
        do {
            _ = try store.addExercise(
                toWorkout: workoutID,
                exerciseID: exercise.id,
                initialSet: WorkoutSetDraft(
                    weight: store.lastWeight(exerciseID: exercise.id) ?? 0,
                    reps: 10
                )
            )
        } catch {
            show(error)
        }
    }

    private func addSet(
        to block: WorkoutExercise,
        workout: WorkoutSession,
        exerciseName: String
    ) {
        let source = block.sets.last
        do {
            _ = try store.addSet(
                workoutID: workout.id,
                workoutExerciseID: block.id,
                weight: source?.weight ?? store.lastWeight(exerciseID: block.exerciseID) ?? 0,
                reps: source?.reps ?? 10
            )
            Task {
                await restTimers.start(
                    id: timerKey(blockID: block.id),
                    seconds: 90,
                    title: exerciseName
                )
            }
        } catch {
            show(error)
        }
    }

    private func saveMetadata() {
        do {
            try store.updateWorkout(id: workoutID, date: date, note: note)
            statusMessage = nil
            reportStatus("Workout details updated.", false)
        } catch {
            show(error)
        }
    }

    private func finish(_ workout: WorkoutSession) {
        commitPendingDeletion()
        guard store.workout(id: workout.id) != nil else {
            onDeleted()
            return
        }
        do {
            try store.updateWorkout(id: workout.id, date: date, note: note)
            onFinish(workout.id)
        } catch {
            show(error)
        }
    }

    private func deleteWorkout() {
        deletionTask?.cancel()
        pendingDeletion = nil
        do {
            if let workout = store.workout(id: workoutID) {
                workout.exercises.forEach { restTimers.cancel(id: timerKey(blockID: $0.id)) }
            }
            try store.deleteWorkout(id: workoutID)
            reportStatus("Workout deleted.", false)
            onDeleted()
        } catch {
            show(error)
        }
    }

    private func stageDeletion(_ deletion: PendingDeletion) {
        if pendingDeletion != nil { commitPendingDeletion() }
        pendingDeletion = deletion
        deletionTask?.cancel()
        deletionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, pendingDeletion == deletion else { return }
                commitPendingDeletion()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func undoDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
        pendingDeletion = nil
    }

    private func commitPendingDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            switch deletion {
            case .set(let blockID, let setID):
                try store.deleteSet(
                    workoutID: workoutID,
                    workoutExerciseID: blockID,
                    setID: setID
                )
                if store.workout(id: workoutID)?.exercises.contains(where: { $0.id == blockID }) != true {
                    restTimers.cancel(id: timerKey(blockID: blockID))
                }
            case .exercise(let blockID):
                restTimers.cancel(id: timerKey(blockID: blockID))
                try store.removeExercise(fromWorkout: workoutID, workoutExerciseID: blockID)
            }
            if store.workout(id: workoutID) == nil { onDeleted() }
        } catch {
            show(error)
        }
    }

    private func timerKey(blockID: UUID) -> String {
        "workout-\(workoutID.uuidString)-exercise-\(blockID.uuidString)"
    }

    private func show(_ error: Error) {
        statusMessage = gymErrorMessage(error)
    }
}

private struct StoredWorkoutSetEditorRow: View {
    @State private var weight: Double
    @State private var reps: Int

    let set: WorkoutSet
    let position: Int
    let prLabels: [String]
    let lastWeight: Double?
    let onSave: (Double, Int) -> Void
    let onDelete: () -> Void

    init(
        set: WorkoutSet,
        position: Int,
        prLabels: [String],
        lastWeight: Double?,
        onSave: @escaping (Double, Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.position = position
        self.prLabels = prLabels
        self.lastWeight = lastWeight
        self.onSave = onSave
        self.onDelete = onDelete
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                    .font(.subheadline.weight(.bold))
                ForEach(prLabels, id: \.self) { label in
                    GymInfoPill(label, systemImage: "trophy.fill", accent: GymTheme.tertiary)
                }
                Spacer(minLength: 4)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    gymText(
                        "Delete set \(position + 1)",
                        "Видалити підхід \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { editors }
                VStack(spacing: 10) { editors }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(GymTheme.surfaceVariant.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: set.weight) { _, newValue in weight = newValue }
        .onChange(of: set.reps) { _, newValue in reps = newValue }
    }

    @ViewBuilder
    private var editors: some View {
        TextField(
            "Weight",
            value: $weight,
            format: .number.precision(.fractionLength(0 ... 2))
        )
        .keyboardType(.decimalPad)
        .gymTextFieldChrome()
        .accessibilityLabel(
            gymText(
                "Weight for set \(position + 1)",
                "Вага для підходу \(position + 1)",
                languageCode: gymCurrentLanguageCode()
            )
        )

        Stepper(value: $reps, in: 1 ... 10_000) {
            Text(
                gymText(
                    "\(reps) reps",
                    "\(reps) повт.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GymTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            if let lastWeight { weight = lastWeight }
        } label: {
            Label("Last", systemImage: "clock.arrow.circlepath")
        }
        .disabled(lastWeight == nil)

        Button {
            weight += 2.5
        } label: {
            Label("+2.5", systemImage: "plus")
        }

        Button {
            onSave(weight, reps)
        } label: {
            Label("Save set", systemImage: "checkmark")
        }
        .disabled(!weight.isFinite || weight < 0 || reps < 1)
    }
}
