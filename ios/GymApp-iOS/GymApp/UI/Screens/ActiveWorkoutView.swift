import SwiftUI

@MainActor
struct ActiveWorkoutView: View {
    @ObservedObject private var workoutStore: WorkoutStore
    @ObservedObject private var activeWorkoutStore: ActiveWorkoutStore
    @ObservedObject private var restTimers: RestTimerManager

    private let draftID: UUID
    private let onFinished: (UUID) -> Void
    private let onClose: () -> Void
    private let onDiscarded: () -> Void
    private let reportStatus: (String, Bool) -> Void

    @State private var statusMessage: String?
    @State private var showingDiscardConfirmation = false

    init(
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        restTimers: RestTimerManager,
        draftID: UUID,
        onFinished: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void,
        onDiscarded: @escaping () -> Void,
        onStatus: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        _workoutStore = ObservedObject(wrappedValue: workoutStore)
        _activeWorkoutStore = ObservedObject(wrappedValue: activeWorkoutStore)
        _restTimers = ObservedObject(wrappedValue: restTimers)
        self.draftID = draftID
        self.onFinished = onFinished
        self.onClose = onClose
        self.onDiscarded = onDiscarded
        self.reportStatus = onStatus
    }

    var body: some View {
        GymBackground {
            if let draft = currentDraft {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        progressPanel(draft)

                        if let statusMessage {
                            GymStatusBanner(message: statusMessage, isError: true)
                        }

                        ForEach(draft.exercises) { exercise in
                            exercisePanel(exercise, draft: draft)
                        }

                        finishPanel(draft)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                GymContentUnavailableView {
                    Label(
                        gymText(
                            "Workout unavailable",
                            "Тренування недоступне",
                            "Тренировка недоступна",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(
                        gymText(
                            "The active workout changed or was already completed.",
                            "Активне тренування змінилося або вже завершене.",
                            "Активная тренировка изменилась или уже завершена.",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }
            }
        }
        .navigationTitle(
            gymText(
                "Active workout",
                "Активне тренування",
                "Активная тренировка",
                languageCode: gymCurrentLanguageCode()
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    gymText(
                        "Back",
                        "Назад",
                        "Назад",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    action: onClose
                )
                .accessibilityHint(
                    gymText(
                        "Closes the screen; all changes are already saved",
                        "Закриває екран; усі зміни вже збережено",
                        "Закрывает экран; все изменения уже сохранены",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDiscardConfirmation = true
                } label: {
                    Label(
                        gymText(
                            "Discard",
                            "Відкинути",
                            "Удалить",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "trash"
                    )
                }
                .disabled(currentDraft?.commitIntent != nil)
            }
        }
        .interactiveDismissDisabled(false)
        .alert(
            gymText(
                "Discard active workout?",
                "Відкинути активне тренування?",
                "Удалить активную тренировку?",
                languageCode: gymCurrentLanguageCode()
            ),
            isPresented: $showingDiscardConfirmation
        ) {
            Button(
                gymText(
                    "Discard",
                    "Відкинути",
                    "Удалить",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .destructive,
                action: discard
            )
            Button(
                gymText(
                    "Cancel",
                    "Скасувати",
                    "Отмена",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                gymText(
                    "Recorded and planned sets in this active draft will be removed. Saved workout history is not affected.",
                    "Записані й заплановані підходи цього чернеткового тренування буде видалено. Збережена історія не зміниться.",
                    "Записанные и запланированные подходы этого черновика будут удалены. Сохранённая история не изменится.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
    }

    private var currentDraft: ActiveWorkoutDraft? {
        guard let draft = activeWorkoutStore.draft, draft.id == draftID else { return nil }
        return draft
    }

    private func progressPanel(_ draft: ActiveWorkoutDraft) -> some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    gymText(
                        "Workout in progress",
                        "Тренування триває",
                        "Тренировка идёт",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.title2.bold())

                Text(
                    draft.commitIntent == nil
                        ? gymText(
                            "Record a set only after you complete it. Progress is saved on this device immediately.",
                            "Записуй підхід лише після виконання. Прогрес одразу зберігається на цьому пристрої.",
                            "Записывай подход только после выполнения. Прогресс сразу сохраняется на этом устройстве.",
                            languageCode: gymCurrentLanguageCode()
                        )
                        : gymText(
                            "Completion is safely locked. Retry Finish to confirm history and clear this screen.",
                            "Завершення безпечно зафіксовано. Повтори завершення, щоб підтвердити історію й закрити цей екран.",
                            "Завершение безопасно зафиксировано. Повтори завершение, чтобы подтвердить историю и закрыть этот экран.",
                            languageCode: gymCurrentLanguageCode()
                        )
                )
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.84))

                HStack(spacing: 12) {
                    GymInfoPill(
                        "\(draft.completedSetCount) / \(draft.plannedSetCount)",
                        systemImage: "checkmark.circle.fill",
                        accent: .white
                    )
                    GymInfoPill(
                        gymFormattedDate(draft.startedAt, date: .omitted, time: .shortened),
                        systemImage: "clock.fill",
                        accent: .white
                    )
                }

                ProgressView(
                    value: Double(draft.completedSetCount),
                    total: Double(max(1, draft.plannedSetCount))
                )
                .tint(.white)
                .accessibilityValue("\(draft.completedSetCount) / \(draft.plannedSetCount)")
            }
        }
    }

    private func exercisePanel(
        _ exercise: ActiveWorkoutExercise,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let storedExercise = workoutStore.exercise(id: exercise.exerciseID)
        let exerciseName = storedExercise.map { gymExerciseName($0) } ?? gymText(
            "Unavailable exercise",
            "Недоступна вправа",
            "Недоступное упражнение",
            languageCode: gymCurrentLanguageCode()
        )
        let timerID = timerKey(draftID: draft.id, exerciseBlockID: exercise.id)

        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let storedExercise {
                        ExerciseMediaButton(
                            exerciseName: storedExercise.name,
                            exerciseID: storedExercise.id,
                            ownerKey: workoutStore.accountStorageKey
                        )
                    }
                    Text(exerciseName)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("\(exercise.sets.lazy.filter(\.isCompleted).count) / \(exercise.sets.count)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                }

                WorkoutRestTimerControls(
                    manager: restTimers,
                    timerID: timerID,
                    exerciseName: exerciseName
                )

                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    setRow(
                        set,
                        position: index,
                        exercise: exercise,
                        exerciseName: exerciseName,
                        draft: draft
                    )
                }

                Button {
                    appendSet(to: exercise)
                } label: {
                    Label(
                        gymText(
                            "Add planned set",
                            "Додати запланований підхід",
                            "Добавить запланированный подход",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(storedExercise == nil || draft.commitIntent != nil)
            }
        }
    }

    private func setRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        "Подход \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .font(.subheadline.bold())
                Spacer(minLength: 8)
                if set.isCompleted {
                    Label(
                        gymText(
                            "Recorded",
                            "Записано",
                            "Записано",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(GymTheme.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    setEditors(set: set, draft: draft)
                }
                VStack(spacing: 10) {
                    setEditors(set: set, draft: draft)
                }
            }

            if !set.isCompleted {
                Button {
                    recordSet(
                        set,
                        exercise: exercise,
                        exerciseName: exerciseName,
                        draft: draft
                    )
                } label: {
                    Label(
                        gymText(
                            "Record set · start 90 sec rest",
                            "Записати підхід · відпочинок 90 с",
                            "Записать подход · отдых 90 с",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(draft.commitIntent != nil)
            }
        }
        .padding(12)
        .background(
            set.isCompleted ? GymTheme.secondary.opacity(0.08) : GymTheme.surfaceVariant.opacity(0.48),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    @ViewBuilder
    private func setEditors(
        set: ActiveWorkoutSet,
        draft: ActiveWorkoutDraft
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                gymText(
                    "Weight",
                    "Вага",
                    "Вес",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            TextField(
                "0",
                value: weightBinding(setID: set.id),
                format: .number.precision(.fractionLength(0 ... 2))
            )
            .keyboardType(.decimalPad)
            .gymTextFieldChrome()
            .disabled(set.isCompleted || draft.commitIntent != nil)
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 5) {
            Text(
                gymText(
                    "Repetitions",
                    "Повторення",
                    "Повторения",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            Stepper(value: repsBinding(setID: set.id), in: 1 ... 10_000) {
                Text(set.reps.formatted())
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GymTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .disabled(set.isCompleted || draft.commitIntent != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func finishPanel(_ draft: ActiveWorkoutDraft) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    eyebrow: gymText(
                        "Finish",
                        "Завершення",
                        "Завершение",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    title: gymText(
                        "Complete this workout",
                        "Завершити тренування",
                        "Завершить тренировку",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    supporting: gymText(
                        "Only recorded sets will be added to workout history. Unrecorded plan rows will be left out.",
                        "До історії потраплять лише записані підходи. Невиконані рядки плану не буде додано.",
                        "В историю попадут только записанные подходы. Невыполненные строки плана не будут добавлены.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                Button {
                    finish(draft)
                } label: {
                    Label(
                        draft.commitIntent == nil
                            ? gymText(
                                "Finish and view summary",
                                "Завершити й переглянути підсумок",
                                "Завершить и посмотреть итог",
                                languageCode: gymCurrentLanguageCode()
                            )
                            : gymText(
                                "Retry finish",
                                "Повторити завершення",
                                "Повторить завершение",
                                languageCode: gymCurrentLanguageCode()
                            ),
                        systemImage: "checkmark.seal.fill"
                    )
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(draft.completedSetCount == 0)
            }
        }
    }

    private func weightBinding(setID: UUID) -> Binding<Double> {
        Binding(
            get: { activeSet(id: setID)?.weight ?? 0 },
            set: { newWeight in
                guard let draft = currentDraft,
                      let set = activeSet(id: setID),
                      !set.isCompleted else { return }
                updateSet(
                    draft: draft,
                    setID: setID,
                    weight: newWeight,
                    reps: set.reps
                )
            }
        )
    }

    private func repsBinding(setID: UUID) -> Binding<Int> {
        Binding(
            get: { activeSet(id: setID)?.reps ?? 1 },
            set: { newReps in
                guard let draft = currentDraft,
                      let set = activeSet(id: setID),
                      !set.isCompleted else { return }
                updateSet(
                    draft: draft,
                    setID: setID,
                    weight: set.weight,
                    reps: newReps
                )
            }
        )
    }

    private func activeSet(id: UUID) -> ActiveWorkoutSet? {
        currentDraft?.exercises.lazy.flatMap(\.sets).first { $0.id == id }
    }

    private func updateSet(
        draft: ActiveWorkoutDraft,
        setID: UUID,
        weight: Double,
        reps: Int
    ) {
        do {
            try activeWorkoutStore.updateSet(
                draftID: draft.id,
                setID: setID,
                weight: weight,
                reps: reps,
                expectedRevision: draft.revision
            )
            statusMessage = nil
        } catch {
            show(error)
        }
    }

    private func recordSet(
        _ set: ActiveWorkoutSet,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) {
        do {
            try activeWorkoutStore.recordSet(
                draftID: draft.id,
                setID: set.id,
                expectedRevision: draft.revision
            )
            // The atomic active-draft write above must succeed before rest begins.
            restTimers.start(
                id: timerKey(draftID: draft.id, exerciseBlockID: exercise.id),
                seconds: 90,
                title: exerciseName
            )
            statusMessage = nil
        } catch {
            show(error)
        }
    }

    private func appendSet(to exercise: ActiveWorkoutExercise) {
        guard let draft = currentDraft else { return }
        let source = exercise.sets.last
        do {
            try activeWorkoutStore.appendSet(
                draftID: draft.id,
                exerciseBlockID: exercise.id,
                weight: source?.weight ?? workoutStore.lastWeight(exerciseID: exercise.exerciseID) ?? 0,
                reps: source?.reps ?? 10,
                expectedRevision: draft.revision
            )
            statusMessage = nil
        } catch {
            show(error)
        }
    }

    private func finish(_ draft: ActiveWorkoutDraft) {
        do {
            let timerIDs = draft.exercises.map {
                timerKey(draftID: draft.id, exerciseBlockID: $0.id)
            }
            let workout = try activeWorkoutStore.finish(
                draftID: draft.id,
                expectedRevision: draft.revision,
                into: workoutStore
            )
            timerIDs.forEach { restTimers.cancel(id: $0) }
            reportStatus(
                gymText(
                    "Workout finished. Only recorded sets were saved.",
                    "Тренування завершено. Збережено лише записані підходи.",
                    "Тренировка завершена. Сохранены только записанные подходы.",
                    languageCode: gymCurrentLanguageCode()
                ),
                false
            )
            onFinished(workout.id)
        } catch {
            show(error)
        }
    }

    private func discard() {
        guard let draft = currentDraft else {
            onDiscarded()
            return
        }
        do {
            let timerIDs = draft.exercises.map {
                timerKey(draftID: draft.id, exerciseBlockID: $0.id)
            }
            try activeWorkoutStore.discard(
                draftID: draft.id,
                expectedRevision: draft.revision
            )
            timerIDs.forEach { restTimers.cancel(id: $0) }
            reportStatus(
                gymText(
                    "Active workout discarded.",
                    "Активне тренування відкинуто.",
                    "Активная тренировка удалена.",
                    languageCode: gymCurrentLanguageCode()
                ),
                false
            )
            onDiscarded()
        } catch {
            show(error)
        }
    }

    private func timerKey(draftID: UUID, exerciseBlockID: UUID) -> String {
        "active-workout-\(draftID.uuidString)-exercise-\(exerciseBlockID.uuidString)"
    }

    private func show(_ error: Error) {
        statusMessage = gymErrorMessage(error)
    }
}
