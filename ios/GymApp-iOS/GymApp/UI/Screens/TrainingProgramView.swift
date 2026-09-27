import SwiftUI

struct TrainingProgramView: View {
    @ObservedObject var workouts: WorkoutStore
    @StateObject private var store: TrainingProgramStore
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedSlot: TrainingProgramSlot?
    @State private var showsCreateProgram = false
    @State private var showsFinish = false
    @State private var expandedWeeks: Set<Int> = [1]

    let onPrepare: () -> Void

    init(workouts: WorkoutStore, onPrepare: @escaping () -> Void) {
        self.workouts = workouts
        self.onPrepare = onPrepare
        _store = StateObject(wrappedValue: TrainingProgramStore(
            owner: workouts.accountStorageKey,
            workoutStorageURL: workouts.storageURL
        ))
    }

    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }

    private var profile: TrainingProfile {
        TrainingProfileStore().load(accountStorageKey: workouts.accountStorageKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.Spacing.large) {
                if let program = store.program {
                    programView(program)
                } else {
                    emptyProgramView
                }
            }
            .padding(.horizontal, GymTheme.screenHorizontalInset)
            .padding(.vertical, GymTheme.Spacing.large)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.bottom, GymTheme.screenBottomInset + 72)
        .sheet(isPresented: $showsCreateProgram) {
            ProgramScheduleEditor(
                profile: profile,
                accountStorageKey: workouts.accountStorageKey,
                selectedWeekdays: $selectedWeekdays,
                onCancel: { showsCreateProgram = false },
                onSave: {
                    if store.create(
                        profile: profile,
                        selectedWeekdays: Array(selectedWeekdays).sorted()
                    ) {
                        showsCreateProgram = false
                    }
                }
            )
        }
        .sheet(item: $selectedSlot) { slot in
            ProgramSlotDetailView(
                slot: slot,
                workouts: workouts,
                store: store,
                onPrepareNow: onPrepare
            )
        }
        .alert(t("Finish this program?", "Завершити програму?", "Завершить программу?"), isPresented: $showsFinish) {
            Button(t("Finish program", "Завершити програму", "Завершить программу")) {
                store.status("completed")
            }
            Button(t("Cancel", "Скасувати", "Отмена"), role: .cancel) {}
        }
        .onChange(of: workouts.accountStorageKey) { _, _ in
            selectedSlot = nil
            showsCreateProgram = false
        }
    }

    private var emptyProgramView: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("Create your training program", "Створи свою програму", "Создайте свою программу"))
                    .font(GymTheme.TypeScale.sectionTitle)
                Text(t(
                    "Choose the days you train, then prepare a workout for each day in advance.",
                    "Обери дні тренувань і заздалегідь підготуй тренування для кожного дня.",
                    "Выберите дни тренировок и заранее подготовьте тренировку для каждого дня."
                ))
                .foregroundStyle(GymTheme.textSecondary)
                Button(t("Choose training days", "Обрати дні тренувань", "Выбрать дни тренировок")) {
                    selectedWeekdays = defaultWeekdays
                    showsCreateProgram = true
                }
                .buttonStyle(GymPrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func programView(_ program: TrainingProgram) -> some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Training program", "Програма тренувань", "Программа тренировок"))
                    .font(GymTheme.TypeScale.sectionTitle)
                Text(t(
                    "Tap a day to view or prepare its workout.",
                    "Натисни на день, щоб переглянути або підготувати тренування.",
                    "Нажмите на день, чтобы посмотреть или подготовить тренировку."
                ))
                .foregroundStyle(GymTheme.textSecondary)
                Text(t(
                    "Completed: \(program.slots.filter { $0.workoutID != nil }.count) of \(program.slots.count)",
                    "Виконано: \(program.slots.filter { $0.workoutID != nil }.count) із \(program.slots.count)",
                    "Выполнено: \(program.slots.filter { $0.workoutID != nil }.count) из \(program.slots.count)"
                ))
                SwiftUI.ProgressView(
                    value: Double(program.slots.filter { $0.workoutID != nil }.count),
                    total: Double(max(program.slots.count, 1))
                )
                if program.status != "completed" {
                    Button(t("Finish program", "Завершити програму", "Завершить программу")) {
                        showsFinish = true
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                }
            }
        }

        ForEach(1...4, id: \.self) { week in
            let slots = program.slots.dropFirst((week - 1) * program.days).prefix(program.days)
            GymPanel {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedWeeks.contains(week) },
                        set: { isExpanded in
                            if isExpanded { expandedWeeks.insert(week) }
                            else { expandedWeeks.remove(week) }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(slots)) { slot in
                            Button {
                                selectedSlot = slot
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: icon(for: slot))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(gymFormattedDate(slot.date, date: .abbreviated, time: .omitted))
                                        Text(status(for: slot))
                                            .font(.subheadline)
                                            .foregroundStyle(GymTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(GymTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text(t("Week \(week)", "Тиждень \(week)", "Неделя \(week)"))
                        .font(.headline)
                }
            }
        }
    }

    private func icon(for slot: TrainingProgramSlot) -> String {
        slot.workoutID != nil ? "checkmark.circle.fill" : slot.workoutPlan != nil ? "doc.text.fill" : "calendar"
    }

    private func status(for slot: TrainingProgramSlot) -> String {
        if slot.workoutID != nil { return t("Completed", "Виконано", "Выполнено") }
        if slot.workoutPlan != nil { return t("Workout prepared", "Тренування підготовлено", "Тренировка подготовлена") }
        return t("No workout prepared yet", "Тренування ще не підготовлено", "Тренировка ещё не подготовлена")
    }

    private var defaultWeekdays: Set<Int> {
        let count = profile.workoutsPerWeek
        let defaults = [2, 4, 6, 1, 3, 5]
        return Set(defaults.prefix(count))
    }
}

private struct ProgramScheduleEditor: View {
    let profile: TrainingProfile
    let accountStorageKey: String
    @Binding var selectedWeekdays: Set<Int>
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var editableProfile: TrainingProfile
    @State private var showsWeeklyTargetEditor = false
    private let calendar = Calendar.current

    init(
        profile: TrainingProfile,
        accountStorageKey: String,
        selectedWeekdays: Binding<Set<Int>>,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.profile = profile
        self.accountStorageKey = accountStorageKey
        self._selectedWeekdays = selectedWeekdays
        self.onCancel = onCancel
        self.onSave = onSave
        self._editableProfile = State(initialValue: profile)
    }

    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(t(
                        "Choose exactly \(editableProfile.workoutsPerWeek) training days.",
                        "Обери рівно \(editableProfile.workoutsPerWeek) дні тренувань.",
                        "Выберите ровно \(editableProfile.workoutsPerWeek) дня тренировок."
                    ))
                    .foregroundStyle(GymTheme.textSecondary)
                    Button {
                        showsWeeklyTargetEditor = true
                    } label: {
                        Text(t("change target", "змінити ціль", "изменить цель"))
                            .foregroundStyle(GymTheme.brandFill)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Section(t("Training days", "Дні тренувань", "Дни тренировок")) {
                    ForEach(weekdayValues, id: \.self) { weekday in
                        Button {
                            if selectedWeekdays.contains(weekday) {
                                selectedWeekdays.remove(weekday)
                            } else if selectedWeekdays.count < editableProfile.workoutsPerWeek {
                                selectedWeekdays.insert(weekday)
                            }
                        } label: {
                            HStack {
                                Text(weekdayLabel(weekday))
                                Spacer()
                                Image(systemName: selectedWeekdays.contains(weekday) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(t("Program schedule", "Розклад програми", "Расписание программы"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "Скасувати", "Отмена"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Save", "Зберегти", "Сохранить"), action: onSave)
                        .disabled(selectedWeekdays.count != editableProfile.workoutsPerWeek)
                }
            }
        }
        .sheet(isPresented: $showsWeeklyTargetEditor) {
            TrainingSettingsSheet(profile: $editableProfile) { newValue in
                TrainingProfileStore().save(newValue, accountStorageKey: accountStorageKey)
            }
        }
    }

    private var weekdayValues: [Int] { [2, 3, 4, 5, 6, 7, 1] }

    private func weekdayLabel(_ weekday: Int) -> String {
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? Date()
        return date.formatted(.dateTime.weekday(.wide))
    }
}

private struct ProgramSlotDetailView: View {
    let slot: TrainingProgramSlot
    let workouts: WorkoutStore
    @ObservedObject var store: TrainingProgramStore
    let onPrepareNow: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsWorkoutEditor = false

    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(gymFormattedDate(slot.date, date: .long, time: .omitted))
                    .font(GymTheme.TypeScale.sectionTitle)
                if slot.workoutID != nil {
                    Label(t("Workout completed", "Тренування виконано", "Тренировка выполнена"), systemImage: "checkmark.circle.fill")
                } else if slot.workoutPlan != nil {
                    Label(t("Workout prepared for this day", "Тренування підготовлено на цей день", "Тренировка подготовлена на этот день"), systemImage: "doc.text.fill")
                    if let title = slot.workoutPlan?.title, !title.isEmpty {
                        Text(title).font(.headline)
                    }
                } else {
                    Text(t(
                        "Nothing is prepared for this day yet.",
                        "На цей день ще нічого не підготовлено.",
                        "На этот день ещё ничего не подготовлено."
                    ))
                    .foregroundStyle(GymTheme.textSecondary)
                }
                Spacer()
                Button(t("Prepare workout for this day", "Підготувати тренування на цей день", "Подготовить тренировку на этот день")) {
                    showsWorkoutEditor = true
                }
                .buttonStyle(GymPrimaryButtonStyle())
                Button(t("Start workout now", "Почати тренування зараз", "Начать тренировку сейчас"), action: onPrepareNow)
                    .buttonStyle(GymSecondaryButtonStyle())
            }
            .padding(GymTheme.screenHorizontalInset)
            .navigationTitle(t("Workout", "Тренування", "Тренировка"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Done", "Готово", "Готово")) { dismiss() }
                }
            }
            .sheet(isPresented: $showsWorkoutEditor) {
                ProgramWorkoutEditorView(
                    workouts: workouts,
                    onSave: { plan in
                        _ = store.assignWorkoutPlan(plan, to: slot.id)
                        showsWorkoutEditor = false
                        dismiss()
                    }
                )
            }
        }
    }
}

private struct ProgramWorkoutEditorView: View {
    let workouts: WorkoutStore
    let onSave: (TrainingProgramWorkoutPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedIDs: [UUID] = []
    @State private var approvedAlternatives: [UUID: Set<UUID>] = [:]

    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }

    private var baseExercises: [Exercise] {
        Array(workouts.exercises.prefix(6))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("Workout name", "Назва тренування", "Название тренировки"), text: $title)
                }
                Section(t("Exercises and approved alternatives", "Вправи та дозволені варіанти", "Упражнения и разрешённые варианты")) {
                    ForEach(Array(baseExercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseSection(exercise, position: index)
                    }
                }
            }
            .navigationTitle(t("Prepare", "Підготовка", "Подготовка"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "Скасувати", "Отмена"), action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Save", "Зберегти", "Сохранить")) {
                        let exercises = selectedIDs.enumerated().map { position, exerciseID in
                            TrainingProgramExercisePlan(
                                position: position,
                                exerciseID: exerciseID,
                                approvedAlternativeExerciseIDs: Array(approvedAlternatives[exerciseID] ?? []).sorted { $0.uuidString < $1.uuidString }
                            )
                        }
                        onSave(TrainingProgramWorkoutPlan(title: title.isEmpty ? nil : title, exercises: exercises))
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .onAppear {
                if selectedIDs.isEmpty { selectedIDs = baseExercises.map(\.id).prefix(4).map { $0 } }
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: Exercise, position: Int) -> some View {
        let isSelected = selectedIDs.contains(exercise.id)
        Button {
            if isSelected { selectedIDs.removeAll { $0 == exercise.id } }
            else { selectedIDs.append(exercise.id) }
        } label: {
            HStack {
                Text(gymExerciseName(exercise))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            }
        }
        .buttonStyle(.plain)
        if isSelected {
            let alternatives = RecommendationEngine.findAlternatives(
                currentExercise: exercise,
                selectedExerciseIDs: Set(selectedIDs),
                exercises: workouts.exercises,
                history: workouts.allExerciseHistory(),
                muscleMappings: workouts.muscleMappings,
                trainingProfile: TrainingProfileStore().load(accountStorageKey: workouts.accountStorageKey),
                effort: .standard
            )
            if !alternatives.isEmpty {
                Text(t("Allowed rotation", "Дозволена ротація", "Разрешённая ротация"))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                ForEach(alternatives, id: \.exercise.id) { alternative in
                    Toggle(gymExerciseName(alternative.exercise), isOn: Binding(
                        get: { approvedAlternatives[exercise.id]?.contains(alternative.exercise.id) == true },
                        set: { enabled in
                            var values = approvedAlternatives[exercise.id] ?? []
                            if enabled { values.insert(alternative.exercise.id) } else { values.remove(alternative.exercise.id) }
                            approvedAlternatives[exercise.id] = values
                        }
                    ))
                    .font(.subheadline)
                }
            }
        }
    }
}
