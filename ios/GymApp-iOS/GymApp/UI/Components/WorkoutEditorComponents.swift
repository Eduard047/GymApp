import PhotosUI
import SwiftUI

struct WorkoutEditorSetDraft: Identifiable, Hashable {
    let id: UUID
    var weight: Double
    var reps: Int

    init(id: UUID = UUID(), weight: Double = 0, reps: Int = 10) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }

    var storeDraft: WorkoutSetDraft {
        WorkoutSetDraft(weight: weight, reps: reps)
    }
}

struct WorkoutEditorExerciseDraft: Identifiable, Hashable {
    let id: UUID
    let exerciseID: UUID
    var sets: [WorkoutEditorSetDraft]

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        sets: [WorkoutEditorSetDraft] = [WorkoutEditorSetDraft()]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
    }

    var storeDraft: WorkoutExerciseDraft {
        WorkoutExerciseDraft(exerciseID: exerciseID, sets: sets.map(\.storeDraft))
    }
}

enum WorkoutTemplatePreset: String, CaseIterable, Identifiable {
    case push
    case pull
    case legs
    case upper
    case lower
    case deload

    var id: Self { self }

    var title: String {
        switch self {
        case .push: gymLocalized("Push")
        case .pull: gymLocalized("Pull")
        case .legs: gymLocalized("Legs")
        case .upper: gymLocalized("Upper")
        case .lower: gymLocalized("Lower")
        case .deload: gymLocalized("Deload")
        }
    }

    var systemImage: String {
        switch self {
        case .push: "arrow.up.forward"
        case .pull: "arrow.down.backward"
        case .legs: "figure.strengthtraining.traditional"
        case .upper: "figure.arms.open"
        case .lower: "figure.walk"
        case .deload: "arrow.down.right.circle"
        }
    }

    var targetMuscles: Set<String> {
        switch self {
        case .push: ["chest", "shoulders", "triceps"]
        case .pull: ["lats", "upperBack", "biceps", "forearms"]
        case .legs, .lower: ["quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack", "abs"]
        case .upper: ["chest", "shoulders", "triceps", "lats", "upperBack", "biceps", "forearms"]
        case .deload: []
        }
    }
}

struct WorkoutSetDraftRow: View {
    @Binding var set: WorkoutEditorSetDraft

    let position: Int
    let lastWeight: Double?
    let canCopyPrevious: Bool
    let onCopyPrevious: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.textPrimary)
                Spacer(minLength: 8)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
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
                HStack(spacing: 8) { quickActions }
                VStack(alignment: .leading, spacing: 8) { quickActions }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(GymTheme.surfaceVariant.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var editors: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
            TextField(
                "0",
                value: $set.weight,
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
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 5) {
            Text("Repetitions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
            Stepper(value: $set.reps, in: 1 ... 10_000) {
                Text(set.reps.formatted())
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GymTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(
                gymText(
                    "Repetitions for set \(position + 1)",
                    "Повторення для підходу \(position + 1)",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .accessibilityValue(set.reps.formatted())
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var quickActions: some View {
        Button {
            if let lastWeight { set.weight = lastWeight }
        } label: {
            Label("Last", systemImage: "clock.arrow.circlepath")
        }
        .disabled(lastWeight == nil)
        .accessibilityHint(
            lastWeight.map {
                gymText(
                    "Uses the last logged weight, \($0.formatted())",
                    "Використовує останню записану вагу: \($0.formatted())",
                    languageCode: gymCurrentLanguageCode()
                )
            } ?? gymLocalized("No prior weight")
        )

        Button(action: onCopyPrevious) {
            Label("Previous", systemImage: "arrow.up.doc")
        }
        .disabled(!canCopyPrevious)

        Button {
            set.weight += 2.5
        } label: {
            Label("+2.5", systemImage: "plus")
        }

        Button(action: onDuplicate) {
            Label("Copy set", systemImage: "doc.on.doc")
        }
    }
}

@MainActor
struct WorkoutDraftExerciseCard: View {
    @Binding var draft: WorkoutEditorExerciseDraft
    @ObservedObject var restTimers: RestTimerManager

    let exerciseID: UUID
    let exerciseMediaOwnerKey: String
    let exerciseName: String
    let lastWeight: Double?
    let onDeleteExercise: () -> Void
    @State private var showingMedia = false

    private var timerID: String { "draft-exercise-\(draft.id.uuidString)" }

    var body: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    ExerciseMediaThumbnail(
                        exerciseName: exerciseName,
                        exerciseID: exerciseID,
                        ownerKey: exerciseMediaOwnerKey
                    ) {
                        showingMedia = true
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exerciseName)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        if let lastWeight {
                            Text(
                                gymText(
                                    "Last logged: \(lastWeight.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                    "Остання вага: \(lastWeight.formatted(.number.precision(.fractionLength(0 ... 2))))",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                        } else {
                            Text("No history yet")
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive, action: onDeleteExercise) {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        gymText(
                            "Remove \(exerciseName)",
                            "Видалити «\(exerciseName)»",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }

                WorkoutRestTimerControls(
                    manager: restTimers,
                    timerID: timerID,
                    exerciseName: exerciseName
                )

                ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, item in
                    WorkoutSetDraftRow(
                        set: binding(for: item.id),
                        position: index,
                        lastWeight: lastWeight,
                        canCopyPrevious: index > 0,
                        onCopyPrevious: { copyPrevious(into: item.id) },
                        onDuplicate: { duplicate(item.id) },
                        onDelete: { delete(item.id) }
                    )
                }

                Button {
                    let source = draft.sets.last
                    draft.sets.append(
                        WorkoutEditorSetDraft(
                            weight: source?.weight ?? lastWeight ?? 0,
                            reps: source?.reps ?? 10
                        )
                    )
                    restTimers.start(id: timerID, seconds: 90, title: exerciseName)
                } label: {
                    Label("Add set · start 90 sec rest", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Copies the latest values and starts a ninety second rest timer")
            }
        }
        .sheet(isPresented: $showingMedia) {
            ExerciseMediaSheet(
                exerciseName: exerciseName,
                exerciseID: exerciseID,
                ownerKey: exerciseMediaOwnerKey
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func binding(for id: UUID) -> Binding<WorkoutEditorSetDraft> {
        Binding(
            get: { draft.sets.first(where: { $0.id == id }) ?? WorkoutEditorSetDraft() },
            set: { value in
                guard let index = draft.sets.firstIndex(where: { $0.id == id }) else { return }
                draft.sets[index] = value
            }
        )
    }

    private func copyPrevious(into id: UUID) {
        guard let index = draft.sets.firstIndex(where: { $0.id == id }), index > 0 else { return }
        draft.sets[index].weight = draft.sets[index - 1].weight
        draft.sets[index].reps = draft.sets[index - 1].reps
    }

    private func duplicate(_ id: UUID) {
        guard let index = draft.sets.firstIndex(where: { $0.id == id }) else { return }
        let source = draft.sets[index]
        draft.sets.insert(
            WorkoutEditorSetDraft(weight: source.weight, reps: source.reps),
            at: index + 1
        )
    }

    private func delete(_ id: UUID) {
        draft.sets.removeAll { $0.id == id }
    }
}

private struct ExerciseMediaThumbnail: View {
    let exerciseName: String
    let exerciseID: UUID
    let ownerKey: String
    let action: () -> Void

    private var image: UIImage? {
        ExerciseMediaStore.customImage(ownerKey: ownerKey, exerciseID: exerciseID)
            ?? ExerciseMediaStore.bundledImages(exerciseName: exerciseName).first
    }

    var body: some View {
        Button {
            action()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "photo.badge.plus")
                            Text(gymText("Add image", "Додати фото", languageCode: gymCurrentLanguageCode()))
                                .font(.caption2)
                        }
                        .foregroundStyle(GymTheme.textSecondary)
                    }
                }
                .frame(width: 76, height: 64)
                .clipped()

                if image != nil {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(GymTheme.primary, in: Circle())
                        .padding(5)
                }
            }
            .background(GymTheme.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            gymText(
                "Open exercise preview",
                "Відкрити демонстрацію вправи",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }
}

private struct ExerciseMediaSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let exerciseName: String
    let exerciseID: UUID
    let ownerKey: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var customImage: UIImage?
    @State private var frameIndex = 0
    @State private var errorMessage: String?

    private var bundledImages: [UIImage] {
        ExerciseMediaStore.bundledImages(exerciseName: exerciseName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(exerciseName)
                    .font(.title2.bold())

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(GymTheme.surfaceVariant)
                    if let image = customImage ?? bundledImages[safe: frameIndex] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .id(customImage == nil ? frameIndex : -1)
                            .transition(.opacity)
                            .padding(8)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 52))
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: frameIndex)

                Text(
                    gymText(
                        "The preview alternates between the start and finish positions.",
                        "Демонстрація почергово показує початкове та кінцеве положення.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        gymText(
                            "Choose your image",
                            "Обрати своє фото",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymPrimaryButtonStyle())

                if customImage != nil, !bundledImages.isEmpty {
                    Button {
                        ExerciseMediaStore.deleteCustomImage(ownerKey: ownerKey, exerciseID: exerciseID)
                        customImage = nil
                    } label: {
                        Label(
                            gymText(
                                "Restore built-in preview",
                                "Повернути вбудовану демонстрацію",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            systemImage: "arrow.uturn.backward"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle(
                gymText("Exercise preview", "Демонстрація вправи", languageCode: gymCurrentLanguageCode())
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            customImage = ExerciseMediaStore.customImage(ownerKey: ownerKey, exerciseID: exerciseID)
        }
        .task(id: customImage == nil) {
            guard customImage == nil, bundledImages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 2_500 : 1_150))
                guard !Task.isCancelled else { return }
                frameIndex = (frameIndex + 1) % bundledImages.count
            }
        }
        .onChange(of: selectedItem) { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ExerciseMediaStore.MediaError.invalidImage
                    }
                    try ExerciseMediaStore.saveCustomImage(data, ownerKey: ownerKey, exerciseID: exerciseID)
                    customImage = ExerciseMediaStore.customImage(ownerKey: ownerKey, exerciseID: exerciseID)
                    errorMessage = nil
                } catch {
                    errorMessage = gymText(
                        "Couldn’t use this image. Choose a photo up to 8 MB.",
                        "Не вдалося використати фото. Оберіть зображення до 8 МБ.",
                        languageCode: gymCurrentLanguageCode()
                    )
                }
                selectedItem = nil
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
struct WorkoutRestTimerControls: View {
    @ObservedObject var manager: RestTimerManager
    let timerID: String
    let exerciseName: String

    private var remaining: Int { manager.remaining(for: timerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Rest timer", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                if remaining > 0 {
                    Text(Self.clock(remaining))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(GymTheme.primary)
                        .accessibilityLabel(
                            gymText(
                                "\(remaining) seconds remaining",
                                "Залишилося \(remaining) с",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { timerButtons }
                VStack(alignment: .leading, spacing: 8) { timerButtons }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(11)
        .background(GymTheme.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    @ViewBuilder
    private var timerButtons: some View {
        ForEach([60, 90, 180], id: \.self) { seconds in
            Button(gymText("\(seconds)s", "\(seconds) с", languageCode: gymCurrentLanguageCode())) {
                manager.start(id: timerID, seconds: seconds, title: exerciseName)
            }
            .accessibilityLabel(
                gymText(
                    "Start \(seconds) second rest timer for \(exerciseName)",
                    "Запустити таймер відпочинку на \(seconds) с для «\(exerciseName)»",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
        if remaining > 0 {
            Button(role: .destructive) {
                manager.cancel(id: timerID)
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ExercisePickerSheet: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all
        case frequent

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var newExerciseName = ""
    @State private var errorMessage: String?
    @State private var scope: Scope = .all

    let exercises: [Exercise]
    let selectedExerciseIDs: Set<UUID>
    var frequentExerciseIDs: [UUID] = []
    let onSelect: (Exercise) -> Void
    let onCreate: (String) throws -> Exercise

    private var filteredExercises: [Exercise] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let frequentRank = Dictionary(
            uniqueKeysWithValues: frequentExerciseIDs.enumerated().map { ($0.element, $0.offset) }
        )
        return exercises
            .filter { exercise in
                let matchesScope = scope == .all || frequentRank[exercise.id] != nil
                let matchesSearch = query.isEmpty ||
                    exercise.name.localizedCaseInsensitiveContains(query) ||
                    gymExerciseName(exercise).localizedCaseInsensitiveContains(query) ||
                    BuiltInExerciseCatalog.definition(forKey: exercise.catalogKey ?? "")?
                        .englishName.localizedCaseInsensitiveContains(query) == true ||
                    BuiltInExerciseCatalog.definition(forKey: exercise.catalogKey ?? "")?
                        .ukrainianName.localizedCaseInsensitiveContains(query) == true
                return matchesScope && matchesSearch
            }
            .sorted { left, right in
                if scope == .frequent {
                    return (frequentRank[left.id] ?? .max) < (frequentRank[right.id] ?? .max)
                }
                return gymExerciseName(left)
                    .localizedCaseInsensitiveCompare(gymExerciseName(right)) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Create exercise") {
                    TextField("Exercise name", text: $newExerciseName)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("New exercise name")
                    Button {
                        do {
                            let exercise = try onCreate(newExerciseName)
                            onSelect(exercise)
                            dismiss()
                        } catch {
                            errorMessage = gymErrorMessage(error)
                        }
                    } label: {
                        Label("Create and add", systemImage: "plus.circle")
                    }
                    .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Exercises") {
                    Picker("Exercise filter", selection: $scope) {
                        Text(gymLocalized("All")).tag(Scope.all)
                        Text(gymLocalized("Frequent")).tag(Scope.frequent)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(gymLocalized("Exercise filter"))

                    if filteredExercises.isEmpty {
                        if scope == .frequent && frequentExerciseIDs.isEmpty && search.isEmpty {
                            GymContentUnavailableView {
                                Label(gymLocalized("No frequent exercises yet"), systemImage: "star")
                            } description: {
                                Text(gymLocalized(
                                    "Frequently used exercises appear after you save workouts."
                                ))
                            }
                        } else {
                            GymContentUnavailableView.search(text: search)
                        }
                    } else {
                        ForEach(filteredExercises) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(gymExerciseName(exercise))
                                    Spacer()
                                    if selectedExerciseIDs.contains(exercise.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(GymTheme.primary)
                                    }
                                }
                            }
                            .disabled(selectedExerciseIDs.contains(exercise.id))
                            .accessibilityHint(
                                gymLocalized(
                                    selectedExerciseIDs.contains(exercise.id)
                                        ? "Already in this workout"
                                        : "Adds exercise to the workout"
                                )
                            )
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Could not add exercise", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(gymLocalized(errorMessage ?? "Unknown error"))
            }
        }
    }
}

extension TrainingSplit {
    var displayName: String {
        switch self {
        case .upperLower: gymLocalized("Upper / Lower")
        case .fullBody: gymLocalized("Full body")
        case .pushPullLegs: gymLocalized("Push / Pull / Legs")
        case .custom: gymLocalized("Custom")
        }
    }
}

extension TrainingGoal {
    var displayName: String {
        switch self {
        case .aestheticFatLoss: gymLocalized("Aesthetic fat loss")
        case .muscleGain: gymLocalized("Muscle gain")
        case .strength: gymLocalized("Strength")
        case .balanced: gymLocalized("Balanced")
        }
    }
}

extension CalorieMode {
    var displayName: String {
        switch self {
        case .deficit: gymLocalized("Deficit")
        case .maintenance: gymLocalized("Maintenance")
        case .surplus: gymLocalized("Surplus")
        }
    }
}
