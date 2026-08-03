import SwiftUI

enum GarminWorkoutDetailCopy {
    static func intervalsTitle(languageCode: String) -> String {
        localized(
            languageCode,
            en: "Chronological watch sets",
            uk: "Хронологічні підходи з годинника",
            ru: "Хронологические подходы с часов"
        )
    }

    static func intervalsSupporting(languageCode: String) -> String {
        localized(
            languageCode,
            en: "S# follows the watch timeline and may differ from exercise-grouped set order. Read from the workout note; imported or manually edited notes are not proof of watch origin. Calories and heart-rate-zone time are slices of the full workout.",
            uk: "S# відповідає хронології годинника й може відрізнятися від порядку підходів, згрупованих за вправами. Прочитано з нотатки тренування; імпортована або вручну змінена нотатка не підтверджує походження з годинника. Калорії та час у пульсових зонах — це відрізки від загального тренування.",
            ru: "S# соответствует хронологии часов и может отличаться от порядка подходов, сгруппированных по упражнениям. Прочитано из заметки тренировки; импортированная или изменённая вручную заметка не подтверждает происхождение с часов. Калории и время в пульсовых зонах — это отрезки от общей тренировки."
        )
    }

    static func originalPartial(
        completed: Int,
        planned: Int,
        languageCode: String
    ) -> String {
        localized(
            languageCode,
            en: "Original Garmin result: completed \(completed) of \(planned) planned sets.",
            uk: "Початковий результат Garmin: виконано \(completed) із \(planned) запланованих підходів.",
            ru: "Исходный результат Garmin: выполнено \(completed) из \(planned) запланированных подходов."
        )
    }

    static func intervalLabel(
        setIndex: Int,
        startSeconds: Int64,
        endSeconds: Int64,
        languageCode: String
    ) -> String {
        localized(
            languageCode,
            en: "Watch set S\(setIndex) · \(startSeconds)–\(endSeconds)s",
            uk: "Підхід з годинника S\(setIndex) · \(startSeconds)–\(endSeconds)с",
            ru: "Подход с часов S\(setIndex) · \(startSeconds)–\(endSeconds)с"
        )
    }

    static func omittedRows(_ count: Int, languageCode: String) -> String {
        localized(
            languageCode,
            en: "Set metric rows omitted from the bounded workout note: \(count).",
            uk: "Рядків показників підходів, що не вмістилися в обмежену нотатку тренування: \(count).",
            ru: "Строк показателей подходов, не вместившихся в ограниченную заметку тренировки: \(count)."
        )
    }

    static func noTimedHeartRateZone(languageCode: String) -> String {
        localized(
            languageCode,
            en: "No timed heart-rate zone",
            uk: "Немає зафіксованого часу в пульсових зонах",
            ru: "Нет зафиксированного времени в пульсовых зонах"
        )
    }

    static func calorieUnit(languageCode: String) -> String {
        normalized(languageCode) == "en" ? "kcal" : "ккал"
    }

    static func secondsUnit(languageCode: String) -> String {
        normalized(languageCode) == "en" ? "s" : "с"
    }

    private static func localized(
        _ languageCode: String,
        en: String,
        uk: String,
        ru: String
    ) -> String {
        switch normalized(languageCode) {
        case "uk": uk
        case "ru": ru
        default: en
        }
    }

    private static func normalized(_ languageCode: String) -> String {
        let value = languageCode.lowercased()
        if value.hasPrefix("uk") { return "uk" }
        if value.hasPrefix("ru") { return "ru" }
        return "en"
    }
}

struct WorkoutDetailWorkoutDeletionTarget: Equatable, Identifiable {
    let accountStorageKey: String
    let storeIdentifier: ObjectIdentifier
    let workoutSnapshot: WorkoutSession

    var id: UUID { workoutSnapshot.id }

    @MainActor
    init(store: WorkoutStore, workout: WorkoutSession) {
        accountStorageKey = store.accountStorageKey
        storeIdentifier = ObjectIdentifier(store)
        workoutSnapshot = workout
    }

    @MainActor
    func isCurrent(in store: WorkoutStore, expectedWorkoutID: UUID) -> Bool {
        storeIdentifier == ObjectIdentifier(store)
            && accountStorageKey == store.accountStorageKey
            && workoutSnapshot.id == expectedWorkoutID
            && store.workout(id: expectedWorkoutID) == workoutSnapshot
    }
}

enum WorkoutDetailDeletionTarget: Equatable, Identifiable {
    struct Context: Equatable {
        let accountStorageKey: String
        let storeIdentifier: ObjectIdentifier
        let workoutSnapshot: WorkoutSession

        var workoutID: UUID { workoutSnapshot.id }
        var workoutExerciseIDs: [UUID] { workoutSnapshot.exercises.map(\.id) }
    }

    enum Impact: Equatable {
        case setOnly
        case setAndExercise
        case setExerciseAndWorkout
        case exerciseOnly
        case exerciseAndWorkout
    }

    case set(
        context: Context,
        block: WorkoutExercise,
        set: WorkoutSet,
        position: Int,
        exerciseName: String
    )
    case exercise(
        context: Context,
        block: WorkoutExercise,
        exerciseName: String
    )

    var id: String {
        switch self {
        case let .set(context, block, set, _, _):
            "set-\(context.workoutID.uuidString)-\(block.id.uuidString)-\(set.id.uuidString)"
        case let .exercise(context, block, _):
            "exercise-\(context.workoutID.uuidString)-\(block.id.uuidString)"
        }
    }

    var workoutID: UUID { context.workoutID }
    var blockID: UUID { expectedBlock.id }

    var setID: UUID? {
        guard case let .set(_, _, set, _, _) = self else { return nil }
        return set.id
    }

    var undoMessage: String {
        switch self {
        case .set: "Set deleted"
        case .exercise: "Exercise deleted"
        }
    }

    var impact: Impact {
        switch self {
        case let .set(context, block, _, _, _):
            if block.sets.count > 1 { return .setOnly }
            return context.workoutExerciseIDs.count > 1
                ? .setAndExercise
                : .setExerciseAndWorkout
        case let .exercise(context, _, _):
            return context.workoutExerciseIDs.count > 1
                ? .exerciseOnly
                : .exerciseAndWorkout
        }
    }

    @MainActor
    static func set(
        store: WorkoutStore,
        workout: WorkoutSession,
        block: WorkoutExercise,
        set: WorkoutSet,
        position: Int,
        exerciseName: String
    ) -> Self {
        .set(
            context: context(store: store, workout: workout),
            block: block,
            set: set,
            position: position,
            exerciseName: exerciseName
        )
    }

    @MainActor
    static func exercise(
        store: WorkoutStore,
        workout: WorkoutSession,
        block: WorkoutExercise,
        exerciseName: String
    ) -> Self {
        .exercise(
            context: context(store: store, workout: workout),
            block: block,
            exerciseName: exerciseName
        )
    }

    @MainActor
    func isCurrent(in store: WorkoutStore, expectedWorkoutID: UUID) -> Bool {
        guard context.storeIdentifier == ObjectIdentifier(store),
              context.accountStorageKey == store.accountStorageKey,
              context.workoutID == expectedWorkoutID,
              let workout = store.workout(id: context.workoutID),
              workout == context.workoutSnapshot,
              let currentBlock = workout.exercises.first(where: { $0.id == expectedBlock.id }),
              currentBlock == expectedBlock else {
            return false
        }

        switch self {
        case let .set(_, _, expectedSet, _, _):
            return currentBlock.sets.contains(expectedSet)
        case .exercise:
            return true
        }
    }

    func confirmationTitle(languageCode: String) -> String {
        switch self {
        case let .set(_, _, _, position, exerciseName):
            return localizedFormat(
                "Delete set %1$lld from “%2$@”?",
                languageCode: languageCode,
                arguments: [Int64(position + 1), exerciseName]
            )
        case let .exercise(_, _, exerciseName):
            return localizedFormat(
                "Delete “%@” from this workout?",
                languageCode: languageCode,
                arguments: [exerciseName]
            )
        }
    }

    func confirmationMessage(languageCode: String) -> String {
        let key: String
        switch impact {
        case .setOnly:
            key = "Only this set will be deleted. Undo is available briefly while you stay on this screen."
        case .setAndExercise:
            key = "This is the final set for the exercise, so the exercise will also be deleted from the workout. Undo is available briefly while you stay on this screen."
        case .setExerciseAndWorkout:
            key = "This is the final set in the workout, so the exercise and the entire workout will also be deleted. Undo is available briefly while you stay on this screen."
        case .exerciseOnly:
            key = "This exercise and all of its sets will be deleted from the workout. Undo is available briefly while you stay on this screen."
        case .exerciseAndWorkout:
            key = "This is the last exercise, so deleting it will also delete the entire workout. Undo is available briefly while you stay on this screen."
        }
        return gymLocalized(key, languageCode: languageCode)
    }

    private var context: Context {
        switch self {
        case let .set(context, _, _, _, _), let .exercise(context, _, _): context
        }
    }

    private var expectedBlock: WorkoutExercise {
        switch self {
        case let .set(_, block, _, _, _), let .exercise(_, block, _): block
        }
    }

    @MainActor
    private static func context(store: WorkoutStore, workout: WorkoutSession) -> Context {
        Context(
            accountStorageKey: store.accountStorageKey,
            storeIdentifier: ObjectIdentifier(store),
            workoutSnapshot: workout
        )
    }

    private func localizedFormat(
        _ key: String,
        languageCode: String,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: gymLocalized(key, languageCode: languageCode),
            locale: AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale,
            arguments: arguments
        )
    }
}

@MainActor
struct WorkoutDetailView: View {
    private enum ActiveAlert: Identifiable {
        case deleteWorkout(WorkoutDetailWorkoutDeletionTarget)
        case deleteItem(WorkoutDetailDeletionTarget)

        var id: String {
            switch self {
            case let .deleteWorkout(target): "delete-workout-\(target.id.uuidString)"
            case let .deleteItem(target): "delete-\(target.id)"
            }
        }
    }

    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var restTimers: RestTimerManager

    @State private var date: Date
    @State private var note: String
    @State private var showingExercisePicker = false
    @State private var activeAlert: ActiveAlert?
    @State private var statusMessage: String?
    @State private var pendingDeletion: WorkoutDetailDeletionTarget?
    @State private var deletionTask: Task<Void, Never>?

    private let workoutID: UUID
    private let onFinish: (UUID) -> Void
    private let onDeleted: () -> Void
    private let reportStatus: (String, Bool) -> Void
    private let isStoreContextCurrent: () -> Bool

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
            },
            isStoreContextCurrent: { [weak appState, weak store = appState.workoutStore] in
                guard let appState, let store else { return false }
                return appState.isAccountReady
                    && appState.workoutStore === store
                    && appState.activeAccountStorageKey == store.accountStorageKey
            }
        )
    }

    init(
        store: WorkoutStore,
        restTimers: RestTimerManager,
        workoutID: UUID,
        onFinish: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void = {},
        onStatus: @escaping (String, Bool) -> Void = { _, _ in },
        isStoreContextCurrent: @escaping () -> Bool = { true }
    ) {
        _store = ObservedObject(wrappedValue: store)
        _restTimers = ObservedObject(wrappedValue: restTimers)
        self.workoutID = workoutID
        self.onFinish = onFinish
        self.onDeleted = onDeleted
        self.reportStatus = onStatus
        self.isStoreContextCurrent = isStoreContextCurrent
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

                        if let summary = GarminWorkoutNoteParser.parse(workout.note),
                           !summary.intervals.isEmpty || summary.omittedMetricRows != nil ||
                            (summary.completedSetCount != nil &&
                                (summary.plannedSetCount ?? 0) >
                                    (summary.completedSetCount ?? Int.max)) {
                            garminSetIntervalsPanel(summary)
                        }

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
                GymContentUnavailableView(
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
                    presentWorkoutDeletionConfirmation()
                } label: {
                    Label("Delete workout", systemImage: "trash")
                }
                .disabled(pendingDeletion != nil)
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
        .alert(item: $activeAlert, content: makeAlert)
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

    private func garminSetIntervalsPanel(_ summary: GarminWorkoutNoteSummary) -> some View {
        let languageCode = gymCurrentLanguageCode()
        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: "Garmin",
                    title: GarminWorkoutDetailCopy.intervalsTitle(languageCode: languageCode),
                    supporting: GarminWorkoutDetailCopy.intervalsSupporting(
                        languageCode: languageCode
                    )
                )
                if let completedSetCount = summary.completedSetCount,
                   let plannedSetCount = summary.plannedSetCount,
                   plannedSetCount > completedSetCount {
                    Text(
                        GarminWorkoutDetailCopy.originalPartial(
                            completed: completedSetCount,
                            planned: plannedSetCount,
                            languageCode: languageCode
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                }
                ForEach(summary.intervals) { interval in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            GarminWorkoutDetailCopy.intervalLabel(
                                setIndex: interval.setIndex,
                                startSeconds: interval.startSeconds,
                                endSeconds: interval.endSeconds,
                                languageCode: languageCode
                            )
                        )
                        .font(.subheadline.weight(.bold))
                        Text(intervalCalorieText(interval, languageCode: languageCode))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        Text(intervalZoneText(interval, languageCode: languageCode))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let omittedMetricRows = summary.omittedMetricRows {
                    Text(
                        GarminWorkoutDetailCopy.omittedRows(
                            omittedMetricRows,
                            languageCode: languageCode
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private func intervalCalorieText(
        _ interval: GarminWorkoutNoteInterval,
        languageCode: String
    ) -> String {
        let gym = interval.gymCalories.formatted(.number.precision(.fractionLength(0 ... 2)))
        let unit = GarminWorkoutDetailCopy.calorieUnit(languageCode: languageCode)
        guard let garminCalories = interval.garminCalories else {
            return "Gym \(gym) \(unit)"
        }
        return "Gym \(gym) \(unit) · Garmin \(garminCalories) \(unit)"
    }

    private func intervalZoneText(
        _ interval: GarminWorkoutNoteInterval,
        languageCode: String
    ) -> String {
        let secondsUnit = GarminWorkoutDetailCopy.secondsUnit(languageCode: languageCode)
        let zones = interval.heartRateZoneSeconds.enumerated().compactMap { zone, seconds in
            seconds > 0 ? "Z\(zone) \(seconds)\(secondsUnit)" : nil
        }
        return zones.isEmpty
            ? GarminWorkoutDetailCopy.noTimedHeartRateZone(languageCode: languageCode)
            : zones.joined(separator: " · ")
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
                    if let exercise {
                        ExerciseMediaButton(
                            exerciseName: exercise.name,
                            exerciseID: exercise.id,
                            ownerKey: store.accountStorageKey
                        )
                    }
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
                        presentDeletionConfirmation(
                            .exercise(
                                store: store,
                                workout: workout,
                                block: block,
                                exerciseName: name
                            )
                        )
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
                    .disabled(pendingDeletion != nil)
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
                            presentDeletionConfirmation(
                                .set(
                                    store: store,
                                    workout: workout,
                                    block: block,
                                    set: set,
                                    position: index,
                                    exerciseName: name
                                )
                            )
                        }
                    )
                    .disabled(pendingDeletion != nil)
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

    private func undoBar(_ pending: WorkoutDetailDeletionTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(GymTheme.error)
                .accessibilityHidden(true)
            Text(gymLocalized(pending.undoMessage))
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
            guard case let .exercise(_, hiddenBlock, _) = pendingDeletion else { return true }
            return block.id != hiddenBlock.id
        }
    }

    private func visibleSets(_ block: WorkoutExercise) -> [WorkoutSet] {
        block.sets.filter { set in
            guard case let .set(_, pendingBlock, hiddenSet, _, _) = pendingDeletion,
                  pendingBlock.id == block.id else { return true }
            return set.id != hiddenSet.id
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
            restTimers.start(
                id: timerKey(blockID: block.id),
                seconds: 90,
                title: exerciseName
            )
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

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .deleteWorkout(target):
            return Alert(
                title: Text("Delete workout?"),
                message: Text("This removes the workout and every set. This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteWorkout(target)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        case let .deleteItem(target):
            let languageCode = gymCurrentLanguageCode()
            return Alert(
                title: Text(target.confirmationTitle(languageCode: languageCode)),
                message: Text(target.confirmationMessage(languageCode: languageCode)),
                primaryButton: .destructive(Text(gymLocalized("Delete", languageCode: languageCode))) {
                    confirmDeletion(target)
                },
                secondaryButton: .cancel(Text(gymLocalized("Cancel", languageCode: languageCode)))
            )
        }
    }

    private func presentWorkoutDeletionConfirmation() {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              let workout = store.workout(id: workoutID) else {
            showStaleDeletion()
            return
        }
        activeAlert = .deleteWorkout(
            WorkoutDetailWorkoutDeletionTarget(store: store, workout: workout)
        )
    }

    private func presentDeletionConfirmation(_ target: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        activeAlert = .deleteItem(target)
    }

    private func confirmDeletion(_ target: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        stageDeletion(target)
    }

    private func finish(_ workout: WorkoutSession) {
        guard isStoreContextCurrent() else {
            showStaleDeletion()
            return
        }
        if commitPendingDeletion() { return }
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

    private func deleteWorkout(_ target: WorkoutDetailWorkoutDeletionTarget) {
        guard pendingDeletion == nil,
              isStoreContextCurrent(),
              target.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return
        }
        do {
            let timerIDs = target.workoutSnapshot.exercises.map { timerKey(blockID: $0.id) }
            try store.deleteWorkout(id: workoutID)
            deletionTask?.cancel()
            pendingDeletion = nil
            timerIDs.forEach { restTimers.cancel(id: $0) }
            reportStatus("Workout deleted.", false)
            onDeleted()
        } catch {
            show(error)
        }
    }

    private func stageDeletion(_ deletion: WorkoutDetailDeletionTarget) {
        guard pendingDeletion == nil else { return }
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

    @discardableResult
    private func commitPendingDeletion() -> Bool {
        deletionTask?.cancel()
        deletionTask = nil
        guard let deletion = pendingDeletion else { return false }
        pendingDeletion = nil
        guard isStoreContextCurrent(),
              deletion.isCurrent(in: store, expectedWorkoutID: workoutID) else {
            showStaleDeletion()
            return false
        }
        do {
            switch deletion {
            case let .set(_, block, set, _, _):
                try store.deleteSet(
                    workoutID: workoutID,
                    workoutExerciseID: block.id,
                    setID: set.id
                )
                if store.workout(id: workoutID)?.exercises.contains(where: { $0.id == block.id }) != true {
                    restTimers.cancel(id: timerKey(blockID: block.id))
                }
            case let .exercise(_, block, _):
                try store.removeExercise(fromWorkout: workoutID, workoutExerciseID: block.id)
                restTimers.cancel(id: timerKey(blockID: block.id))
            }
            if store.workout(id: workoutID) == nil {
                onDeleted()
                return true
            }
        } catch {
            show(error)
        }
        return false
    }

    private func timerKey(blockID: UUID) -> String {
        "workout-\(workoutID.uuidString)-exercise-\(blockID.uuidString)"
    }

    private func show(_ error: Error) {
        statusMessage = gymErrorMessage(error)
    }

    private func showStaleDeletion() {
        statusMessage = gymLocalized(
            "The workout changed before deletion. Review it and try again."
        )
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
        .onChange(of: set.weight) { newValue in weight = newValue }
        .onChange(of: set.reps) { newValue in reps = newValue }
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
