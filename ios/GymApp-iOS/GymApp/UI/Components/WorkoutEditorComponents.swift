import PhotosUI
import SwiftUI

struct WorkoutEditorSetDraft: Identifiable, Hashable {
    let id: UUID
    var weight: Double
    var reps: Int
    var requiresWeightSelection: Bool

    init(
        id: UUID = UUID(),
        weight: Double = 0,
        reps: Int = 10,
        requiresWeightSelection: Bool = false
    ) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.requiresWeightSelection = requiresWeightSelection
    }

    init(id: UUID = UUID(), recommendedSet: RecommendedWorkoutSet) {
        self.id = id
        weight = recommendedSet.weight ?? 0
        reps = recommendedSet.reps
        requiresWeightSelection = recommendedSet.weight == nil
    }

    var isReadyForSave: Bool {
        !requiresWeightSelection && weight.isFinite && weight >= 0
    }

    var storeDraft: WorkoutSetDraft {
        WorkoutSetDraft(weight: weight, reps: reps)
    }
}

struct WorkoutEditorExerciseDraft: Identifiable, Hashable {
    let id: UUID
    var exerciseID: UUID
    var sets: [WorkoutEditorSetDraft]
    var coachRecommendation: WorkoutRecommendation?

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        sets: [WorkoutEditorSetDraft] = [WorkoutEditorSetDraft()],
        coachRecommendation: WorkoutRecommendation? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.coachRecommendation = coachRecommendation
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
                value: weightBinding,
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
            if set.requiresWeightSelection {
                Text("Choose a working weight before saving.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.error)
            }
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
            if let lastWeight {
                set.weight = lastWeight
                set.requiresWeightSelection = false
            }
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
            set.requiresWeightSelection = false
        } label: {
            Label("+2.5", systemImage: "plus")
        }

        Button(action: onDuplicate) {
            Label("Copy set", systemImage: "doc.on.doc")
        }
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { set.weight },
            set: { value in
                set.weight = value
                set.requiresWeightSelection = false
            }
        )
    }
}

@MainActor
struct WorkoutDraftExerciseCard: View {
    @Binding var draft: WorkoutEditorExerciseDraft

    let exerciseID: UUID
    let exerciseMediaOwnerKey: String
    let exerciseName: String
    let lastWeight: Double?
    let onShowSimilar: (() -> Void)?
    let onDeleteExercise: () -> Void
    @State private var showingMedia = false

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

                if let recommendation = draft.coachRecommendation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Label(
                                recommendation.kind.coachDisplayName,
                                systemImage: "sparkles"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(Int((recommendation.confidence * 100).rounded()))%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        Text(
                            gymText(
                                "Target RIR \(recommendation.targetRIR.lowerBound)–\(recommendation.targetRIR.upperBound)",
                                "Цільовий RIR \(recommendation.targetRIR.lowerBound)–\(recommendation.targetRIR.upperBound)",
                                "Целевой RIR \(recommendation.targetRIR.lowerBound)–\(recommendation.targetRIR.upperBound)",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        if !recommendation.reasons.isEmpty {
                            Text(recommendation.reasons.map(\.coachDisplayName).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(
                        GymTheme.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Smart Coach: \(recommendation.kind.coachDisplayName), " +
                            "\(Int((recommendation.confidence * 100).rounded())) percent confidence, " +
                            "RIR \(recommendation.targetRIR.lowerBound) to \(recommendation.targetRIR.upperBound)"
                    )
                }

                if let onShowSimilar {
                    Button(action: onShowSimilar) {
                        Label("Similar exercises", systemImage: "arrow.triangle.swap")
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .accessibilityHint(
                        gymLocalized("Shows safe replacements with a newly calculated prescription")
                    )
                }

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
                            reps: source?.reps ?? 10,
                            requiresWeightSelection: source?.requiresWeightSelection ?? false
                        )
                    )
                } label: {
                    Label("Add planned set", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Copies the latest values into a planned set")
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
        draft.sets[index].requiresWeightSelection = draft.sets[index - 1].requiresWeightSelection
    }

    private func duplicate(_ id: UUID) {
        guard let index = draft.sets.firstIndex(where: { $0.id == id }) else { return }
        let source = draft.sets[index]
        draft.sets.insert(
            WorkoutEditorSetDraft(
                weight: source.weight,
                reps: source.reps,
                requiresWeightSelection: source.requiresWeightSelection
            ),
            at: index + 1
        )
    }

    private func delete(_ id: UUID) {
        draft.sets.removeAll { $0.id == id }
    }
}

private extension WorkoutRecommendationKind {
    var coachDisplayName: String {
        switch self {
        case .newExercise: "New exercise"
        case .progressiveOverload: "Progressive overload"
        case .holdAndBuild: "Hold and build"
        case .deload: "Deload"
        case .comeback: "Comeback"
        case .plateauBreak: "Plateau break"
        }
    }
}

private extension WorkoutRecommendationReason {
    var coachDisplayName: String {
        switch self {
        case .noHistory: "No history"
        case .lastSessionStrong: "Last session strong"
        case .lastSessionUnstable: "Recent performance unstable"
        case .recentBreak: "Returning after a break"
        case .volumeTrendingUp: "Volume trending up"
        case .volumeDropped: "Volume dropped"
        case .plateauDetected: "Plateau detected"
        case .nearPersonalBest: "Near personal best"
        case .conservativeIncrease: "Conservative increase"
        case .loadBoundaryReached: "Machine load limit"
        case .harderBodyweightVariation: "Harder variation needed"
        case .recoverySession: "Recovery session"
        case .hardSession: "Hard session"
        case .aestheticGoal: "Fat-loss goal"
        case .calorieDeficit: "Calorie deficit"
        case .fourDayUpperLower: "Four-day upper/lower"
        }
    }
}

struct SmartExerciseAlternativesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let alternatives: [SmartWorkoutAlternative]
    let exerciseMediaOwnerKey: String
    let onSelect: (SmartWorkoutAlternative) -> Void

    var body: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if alternatives.isEmpty {
                            GymPanel {
                                GymContentUnavailableView {
                                    Label("No similar exercises", systemImage: "dumbbell")
                                } description: {
                                    Text("No safe replacement is available in your exercise catalog.")
                                }
                            }
                        } else {
                            ForEach(alternatives) { alternative in
                                alternativeCard(alternative)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("Similar exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func alternativeCard(_ alternative: SmartWorkoutAlternative) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ExerciseMediaButton(
                        exerciseName: gymExerciseName(alternative.exercise),
                        exerciseID: alternative.exercise.id,
                        ownerKey: exerciseMediaOwnerKey
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymExerciseName(alternative.exercise))
                            .font(.headline)
                        Text(prescriptionText(alternative.recommendation))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    onSelect(alternative)
                    dismiss()
                } label: {
                    Label("Use this exercise", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(GymPrimaryButtonStyle())
            }
        }
    }

    private func prescriptionText(_ recommendation: WorkoutRecommendation) -> String {
        guard let first = recommendation.sets.first else { return gymLocalized("No prescription") }
        let setCount = recommendation.sets.count
        let weight = first.weight.map {
            " · \($0.formatted(.number.precision(.fractionLength(0 ... 2)))) kg"
        } ?? ""
        return "\(setCount) × \(first.reps)\(weight)"
    }
}

struct ExerciseMediaButton: View {
    let exerciseName: String
    let exerciseID: UUID
    let ownerKey: String
    @State private var showingMedia = false

    var body: some View {
        ExerciseMediaThumbnail(
            exerciseName: exerciseName,
            exerciseID: exerciseID,
            ownerKey: ownerKey,
            action: { showingMedia = true }
        )
        .sheet(isPresented: $showingMedia) {
            ExerciseMediaSheet(
                exerciseName: exerciseName,
                exerciseID: exerciseID,
                ownerKey: ownerKey
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct ExerciseMediaThumbnail: View {
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

struct ExerciseMediaSheet: View {
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
        if remaining > 0 {
            Button {
                manager.adjust(id: timerID, by: -15, title: exerciseName)
            } label: {
                Label("−15s", systemImage: "minus.circle")
            }
            .accessibilityLabel(
                gymText(
                    "Reduce rest by 15 seconds",
                    "Зменшити відпочинок на 15 секунд",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            Button {
                manager.adjust(id: timerID, by: 15, title: exerciseName)
            } label: {
                Label("+15s", systemImage: "plus.circle")
            }
            .accessibilityLabel(
                gymText(
                    "Add 15 seconds of rest",
                    "Додати 15 секунд відпочинку",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            Button(role: .destructive) {
                manager.cancel(id: timerID)
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            ForEach([60, 90, 120, 180], id: \.self) { seconds in
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
        }
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum ExerciseBodyFilter: String, CaseIterable, Identifiable {
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

    var localizedTitle: String {
        switch self {
        case .all: gymLocalized("All")
        case .upper: gymText("Upper body", "Верх тіла", languageCode: gymCurrentLanguageCode())
        case .lower: gymText("Lower body", "Низ тіла", languageCode: gymCurrentLanguageCode())
        case .core: gymText("Core", "Кор", languageCode: gymCurrentLanguageCode())
        }
    }
}

enum ExerciseSortMode: String, CaseIterable, Identifiable {
    case name
    case mostFrequent
    case leastFrequent

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .name:
            gymText("By name", "За назвою", languageCode: gymCurrentLanguageCode())
        case .mostFrequent:
            gymText("Most frequent", "Найчастіші", languageCode: gymCurrentLanguageCode())
        case .leastFrequent:
            gymText("Least frequent", "Найрідші", languageCode: gymCurrentLanguageCode())
        }
    }
}

enum ExerciseFilterEngine {
    static func filtered(
        exercises: [Exercise],
        query: String,
        bodyFilter: ExerciseBodyFilter,
        muscleFilter: String?,
        favoritesOnly: Bool,
        sortMode: ExerciseSortMode,
        muscleMappings: [ExerciseMuscleMapping],
        sessionCounts: [UUID: Int]
    ) -> [Exercise] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualMuscles = Dictionary(grouping: muscleMappings, by: \.exerciseNameKey)
            .mapValues { Set($0.map(\.muscleID)) }
        let matching = exercises.filter { exercise in
            let definition = catalogDefinition(for: exercise)
            let names = [exercise.name, gymExerciseName(exercise)] +
                (definition.map { [$0.englishName, $0.ukrainianName] + $0.legacyAliases } ?? [])
            let muscles = effectiveMuscleIDs(
                for: exercise,
                definition: definition,
                manualMuscles: manualMuscles
            )
            let matchesQuery = trimmedQuery.isEmpty || names.contains { name in
                name.localizedCaseInsensitiveContains(trimmedQuery)
            }
            let matchesBody = bodyFilter == .all ||
                !muscles.isDisjoint(with: bodyFilter.muscleIDs)
            let matchesMuscle = muscleFilter == nil || muscles.contains(muscleFilter!)
            let matchesFavorite = !favoritesOnly || exercise.isFavorite
            return matchesQuery && matchesBody && matchesMuscle && matchesFavorite
        }
        return matching.sorted { left, right in
            let nameOrder = gymExerciseName(left)
                .localizedCaseInsensitiveCompare(gymExerciseName(right))
            let nameComesFirst = nameOrder == .orderedAscending ||
                (nameOrder == .orderedSame && left.id.uuidString < right.id.uuidString)
            switch sortMode {
            case .name:
                return nameComesFirst
            case .mostFrequent:
                let leftCount = max(0, sessionCounts[left.id] ?? 0)
                let rightCount = max(0, sessionCounts[right.id] ?? 0)
                return leftCount == rightCount ? nameComesFirst : leftCount > rightCount
            case .leastFrequent:
                let leftCount = max(0, sessionCounts[left.id] ?? 0)
                let rightCount = max(0, sessionCounts[right.id] ?? 0)
                return leftCount == rightCount ? nameComesFirst : leftCount < rightCount
            }
        }
    }

    private static func effectiveMuscleIDs(
        for exercise: Exercise,
        definition: BuiltInExerciseDefinition?,
        manualMuscles: [String: Set<String>]
    ) -> Set<String> {
        let key = MuscleMappingEngine.normalizeExerciseName(exercise.name)
        if let manual = manualMuscles[key], !manual.isEmpty { return manual }
        if let definition { return Set(definition.muscleIDs) }
        return Set(MuscleMappingEngine.defaultContributions(for: exercise.name).map(\.muscleID))
    }

    private static func catalogDefinition(for exercise: Exercise) -> BuiltInExerciseDefinition? {
        if let definition = BuiltInExerciseCatalog.definition(forKey: exercise.catalogKey) {
            return definition
        }
        guard let key = BuiltInExerciseCatalog.canonicalKey(forName: exercise.name) else {
            return nil
        }
        return BuiltInExerciseCatalog.definition(forKey: key)
    }
}

struct ExercisePickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var newExerciseName = ""
    @State private var errorMessage: String?
    @State private var bodyFilter: ExerciseBodyFilter = .all
    @State private var muscleFilter: String?
    @State private var favoritesOnly = false
    @State private var sortMode: ExerciseSortMode = .name

    let exercises: [Exercise]
    let selectedExerciseIDs: Set<UUID>
    let muscleMappings: [ExerciseMuscleMapping]
    let sessionCounts: [UUID: Int]
    let onSelect: (Exercise) -> Void
    let onCreate: (String) throws -> Exercise

    private var filteredExercises: [Exercise] {
        ExerciseFilterEngine.filtered(
            exercises: exercises,
            query: search,
            bodyFilter: bodyFilter,
            muscleFilter: muscleFilter,
            favoritesOnly: favoritesOnly,
            sortMode: sortMode,
            muscleMappings: muscleMappings,
            sessionCounts: sessionCounts
        )
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
                    ScrollView(.horizontal, showsIndicators: false) {
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

                            ForEach(ExerciseBodyFilter.allCases) { filter in
                                Button(filter.localizedTitle) { bodyFilter = filter }
                                    .buttonStyle(.bordered)
                                    .tint(
                                        bodyFilter == filter
                                            ? GymTheme.primary
                                            : GymTheme.textSecondary
                                    )
                                    .accessibilityAddTraits(
                                        bodyFilter == filter ? .isSelected : []
                                    )
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ExerciseSortMode.allCases) { mode in
                                Button(mode.localizedTitle) { sortMode = mode }
                                    .buttonStyle(.bordered)
                                    .tint(
                                        sortMode == mode
                                            ? GymTheme.primary
                                            : GymTheme.textSecondary
                                    )
                                    .accessibilityAddTraits(sortMode == mode ? .isSelected : [])
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button(gymLocalized("All muscles")) { muscleFilter = nil }
                                .buttonStyle(.bordered)
                                .tint(
                                    muscleFilter == nil
                                        ? GymTheme.primary
                                        : GymTheme.textSecondary
                                )
                            ForEach(MuscleMappingEngine.muscleDefinitions) { muscle in
                                Button(
                                    gymText(
                                        muscle.titleEn,
                                        muscle.titleUk,
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                ) {
                                    muscleFilter = muscleFilter == muscle.id ? nil : muscle.id
                                }
                                .buttonStyle(.bordered)
                                .tint(
                                    muscleFilter == muscle.id
                                        ? GymTheme.primary
                                        : GymTheme.textSecondary
                                )
                            }
                        }
                    }

                    if filteredExercises.isEmpty {
                        GymContentUnavailableView.search(text: search)
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
