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
    var onStart: ((Int) -> Void)? = nil
    var onAdjust: ((Int) -> Void)? = nil
    var onStop: (() -> Void)? = nil

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
                if let onAdjust { onAdjust(-15) }
                else { manager.adjust(id: timerID, by: -15, title: exerciseName) }
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
                if let onAdjust { onAdjust(15) }
                else { manager.adjust(id: timerID, by: 15, title: exerciseName) }
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
                if let onStop { onStop() }
                else { manager.cancel(id: timerID) }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            ForEach([60, 90, 120, 180], id: \.self) { seconds in
                Button(gymText("\(seconds)s", "\(seconds) с", languageCode: gymCurrentLanguageCode())) {
                    if let onStart { onStart(seconds) }
                    else { manager.start(id: timerID, seconds: seconds, title: exerciseName) }
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
    private static let maximumSearchQueryCharacters = 256
    private static let maximumSearchCandidateCharacters = 128
    private static let maximumSearchQueryTokens = 16
    private static let minimumFuzzyTokenCharacters = 6
    private static let transliteratedConnectorTokens = Set(
        ExerciseSearchVocabulary.connectorTokens.map(transliterated)
    )

    private enum PreparedSearchQuery {
        case empty
        case invalid
        case value(SearchQuery)
    }

    private struct SearchQuery {
        let tokens: [String]
        let phrase: String
        let compactPhrase: String
    }

    private enum SearchSource: Int {
        case equipment
        case muscle
        case alias
        case canonical

        var isCategory: Bool {
            self == .muscle || self == .equipment
        }
    }

    private enum SearchMatchQuality: Int {
        case fuzzy = 1
        case transliterated = 2
        case direct = 3
    }

    private struct SearchTerm {
        let text: String
        let tokens: [String]
        let phrase: String
        let compactPhrase: String
        let source: SearchSource
        let categoryID: String?
    }

    private struct TokenMatch {
        let source: SearchSource
        let quality: SearchMatchQuality
        let termText: String
        let categoryID: String?
    }

    private enum MatchReason {
        case alias(String)
        case alternateSpelling(String)
        case categories(muscle: [String], equipment: [String])
    }

    private struct SearchEvaluation {
        let relevance: Int
        let reason: MatchReason?
    }

    private struct ScoredExercise {
        let exercise: Exercise
        let relevance: Int
    }

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
        let preparedQuery = preparedSearchQuery(query)
        let manualMuscles = Dictionary(grouping: muscleMappings, by: \.exerciseNameKey)
            .mapValues { Set($0.map(\.muscleID)) }

        let matching = exercises.compactMap { exercise -> ScoredExercise? in
            let definition = catalogDefinition(for: exercise)
            let muscles = effectiveMuscleIDs(
                for: exercise,
                definition: definition,
                manualMuscles: manualMuscles
            )
            let matchesBody = bodyFilter == .all ||
                !muscles.isDisjoint(with: bodyFilter.muscleIDs)
            let matchesMuscle = muscleFilter == nil || muscles.contains(muscleFilter!)
            let matchesFavorite = !favoritesOnly || exercise.isFavorite
            guard matchesBody && matchesMuscle && matchesFavorite else { return nil }

            switch preparedQuery {
            case .empty:
                return ScoredExercise(exercise: exercise, relevance: 0)
            case .invalid:
                return nil
            case let .value(searchQuery):
                guard let evaluation = searchEvaluation(
                    for: exercise,
                    definition: definition,
                    muscleIDs: muscles,
                    query: searchQuery
                ) else {
                    return nil
                }
                return ScoredExercise(exercise: exercise, relevance: evaluation.relevance)
            }
        }

        return matching.sorted { left, right in
            if left.relevance != right.relevance {
                return left.relevance > right.relevance
            }

            let nameOrder = gymExerciseName(left.exercise)
                .localizedCaseInsensitiveCompare(gymExerciseName(right.exercise))
            let nameComesFirst = nameOrder == .orderedAscending ||
                (nameOrder == .orderedSame &&
                    left.exercise.id.uuidString < right.exercise.id.uuidString)
            switch sortMode {
            case .name:
                return nameComesFirst
            case .mostFrequent:
                let leftCount = max(0, sessionCounts[left.exercise.id] ?? 0)
                let rightCount = max(0, sessionCounts[right.exercise.id] ?? 0)
                return leftCount == rightCount ? nameComesFirst : leftCount > rightCount
            case .leastFrequent:
                let leftCount = max(0, sessionCounts[left.exercise.id] ?? 0)
                let rightCount = max(0, sessionCounts[right.exercise.id] ?? 0)
                return leftCount == rightCount ? nameComesFirst : leftCount < rightCount
            }
        }.map(\.exercise)
    }

    static func localizedMatchReason(
        for exercise: Exercise,
        query: String,
        muscleMappings: [ExerciseMuscleMapping],
        languageCode: String
    ) -> String? {
        guard case let .value(searchQuery) = preparedSearchQuery(query) else { return nil }
        let manualMuscles = Dictionary(grouping: muscleMappings, by: \.exerciseNameKey)
            .mapValues { Set($0.map(\.muscleID)) }
        let definition = catalogDefinition(for: exercise)
        let muscles = effectiveMuscleIDs(
            for: exercise,
            definition: definition,
            manualMuscles: manualMuscles
        )
        guard let reason = searchEvaluation(
            for: exercise,
            definition: definition,
            muscleIDs: muscles,
            query: searchQuery
        )?.reason else {
            return nil
        }
        return localizedText(for: reason, languageCode: languageCode)
    }

    private static func searchEvaluation(
        for exercise: Exercise,
        definition: BuiltInExerciseDefinition?,
        muscleIDs: Set<String>,
        query: SearchQuery
    ) -> SearchEvaluation? {
        let canonicalTerms = makeSearchTerms(
            canonicalSearchNames(for: exercise, definition: definition),
            source: .canonical
        )
        let aliasTerms = makeSearchTerms(
            searchAliases(for: definition),
            source: .alias
        )

        if canonicalTerms.contains(where: { $0.phrase == query.phrase }) {
            return SearchEvaluation(relevance: 5_000, reason: nil)
        }
        if let exactAlias = aliasTerms.first(where: { $0.phrase == query.phrase }) {
            return SearchEvaluation(relevance: 4_000, reason: .alias(exactAlias.text))
        }

        let muscleTerms = muscleIDs.sorted().flatMap { muscleID in
            makeSearchTerms(
                ExerciseSearchVocabulary.muscleTermsById[muscleID] ?? [],
                source: .muscle,
                categoryID: muscleID
            )
        }
        let equipmentTerms = (definition.flatMap {
            ExerciseSearchVocabulary.equipmentIdsByKey[$0.key]
        } ?? []).sorted().flatMap { equipmentID in
            makeSearchTerms(
                ExerciseSearchVocabulary.equipmentTermsById[equipmentID] ?? [],
                source: .equipment,
                categoryID: equipmentID
            )
        }
        let terms = canonicalTerms + aliasTerms + muscleTerms + equipmentTerms

        var tokenMatches: [TokenMatch] = []
        tokenMatches.reserveCapacity(query.tokens.count)
        var needsCompactFallback = false
        for queryToken in query.tokens {
            guard let match = bestMatch(for: queryToken, in: terms) else {
                needsCompactFallback = true
                break
            }
            tokenMatches.append(match)
        }
        if needsCompactFallback {
            guard let compactMatch = bestCompactMatch(
                for: query.compactPhrase,
                in: canonicalTerms + aliasTerms
            ) else {
                return nil
            }
            tokenMatches = [compactMatch]
        }

        // Choose one muscle concept for all muscle-backed tokens instead of keeping
        // greedy per-token choices. Shared words such as "back" / "спины" exist in
        // several concepts, so "upper back" / "верх спины" must be assigned wholly
        // to upperBack rather than split between upperBack and lats.
        guard let coherentTokenMatches = coherentMuscleTokenMatches(
            queryTokens: query.tokens,
            tokenMatches: tokenMatches,
            availableMuscleIDs: muscleIDs
        ) else {
            return nil
        }
        tokenMatches = coherentTokenMatches

        // A category query describes one muscle and/or one equipment concept. Do not
        // accidentally assemble a phrase from unrelated semantic buckets, such as
        // hamstrings "задняя" plus shoulders "дельта" on a full-body warm-up.
        let matchedMuscleIDs = Set(tokenMatches.compactMap { match in
            match.source == .muscle ? match.categoryID : nil
        })
        let matchedEquipmentIDs = Set(tokenMatches.compactMap { match in
            match.source == .equipment ? match.categoryID : nil
        })
        guard matchedMuscleIDs.count <= 1, matchedEquipmentIDs.count <= 1 else {
            return nil
        }

        let usesCategory = tokenMatches.contains { $0.source.isCategory }
        if !usesCategory {
            // Do not build a name-only result from unrelated phrases belonging to the
            // same exercise (for example "верх" from "верхній блок" plus "груди"
            // from another pulldown alias). A real colloquial query must fit one name
            // or alias; category-backed combinations are handled separately above.
            let hasCoherentNameOrAlias = (canonicalTerms + aliasTerms).contains { term in
                query.tokens.allSatisfy { queryToken in
                    bestMatch(for: queryToken, in: [term]) != nil
                }
            }
            guard hasCoherentNameOrAlias else { return nil }
        }
        let qualityBonus = tokenMatches.reduce(0) { $0 + $1.quality.rawValue }
        let directNameBonus = tokenMatches.reduce(0) { partial, match in
            partial + (match.source == .canonical ? 20 : match.source == .alias ? 10 : 0)
        }
        let relevance = (usesCategory ? 2_000 : 3_000) + directNameBonus + qualityBonus

        if usesCategory {
            let paired = Array(zip(query.tokens, tokenMatches))
            let muscleTokens = uniqueValues(
                paired.compactMap { token, match in match.source == .muscle ? token : nil }
            )
            let equipmentTokens = uniqueValues(
                paired.compactMap { token, match in match.source == .equipment ? token : nil }
            )
            return SearchEvaluation(
                relevance: relevance,
                reason: .categories(muscle: muscleTokens, equipment: equipmentTokens)
            )
        }

        if let aliasMatch = tokenMatches.first(where: { $0.source == .alias }) {
            return SearchEvaluation(relevance: relevance, reason: .alias(aliasMatch.termText))
        }
        if let alternateMatch = tokenMatches.first(where: {
            $0.source == .canonical && $0.quality != .direct
        }) {
            return SearchEvaluation(
                relevance: relevance,
                reason: .alternateSpelling(alternateMatch.termText)
            )
        }
        return SearchEvaluation(relevance: relevance, reason: nil)
    }

    private static func coherentMuscleTokenMatches(
        queryTokens: [String],
        tokenMatches: [TokenMatch],
        availableMuscleIDs: Set<String>
    ) -> [TokenMatch]? {
        let muscleMatchIndices = tokenMatches.indices.filter {
            tokenMatches[$0].source == .muscle
        }
        let greedyMuscleIDs = Set(muscleMatchIndices.compactMap {
            tokenMatches[$0].categoryID
        })
        guard greedyMuscleIDs.count > 1 else { return tokenMatches }

        var bestAssignment: (matches: [TokenMatch], score: Int, muscleID: String)?
        for muscleID in availableMuscleIDs.sorted() {
            let terms = makeSearchTerms(
                ExerciseSearchVocabulary.muscleTermsById[muscleID] ?? [],
                source: .muscle,
                categoryID: muscleID
            )
            guard !terms.isEmpty else { continue }

            var assignment = tokenMatches
            var qualityScore = 0
            var isComplete = true
            for index in muscleMatchIndices {
                guard index < queryTokens.count,
                      let match = bestMatch(for: queryTokens[index], in: terms) else {
                    isComplete = false
                    break
                }
                assignment[index] = match
                qualityScore += match.quality.rawValue
            }
            guard isComplete else { continue }

            // Prefer a vocabulary phrase that expresses the complete concept, while
            // still allowing bounded free-order tokens within one muscle category.
            let matchedQueryTokens = muscleMatchIndices.compactMap { index in
                index < queryTokens.count ? queryTokens[index] : nil
            }
            let hasSingleTermCoverage = terms.contains { term in
                matchedQueryTokens.allSatisfy { queryToken in
                    bestMatch(for: queryToken, in: [term]) != nil
                }
            }
            let score = qualityScore + (hasSingleTermCoverage ? 100 : 0)
            if let bestAssignment,
               score < bestAssignment.score ||
                (score == bestAssignment.score && muscleID >= bestAssignment.muscleID) {
                continue
            }
            bestAssignment = (assignment, score, muscleID)
        }
        return bestAssignment?.matches
    }

    private static func canonicalSearchNames(
        for exercise: Exercise,
        definition: BuiltInExerciseDefinition?
    ) -> [String] {
        guard let definition else { return [exercise.name] }
        return [
            definition.englishName,
            definition.ukrainianName,
            gymExerciseName(exercise, languageCode: "ru")
        ]
    }

    private static func searchAliases(
        for definition: BuiltInExerciseDefinition?
    ) -> [String] {
        guard let definition else { return [] }
        let searchableLegacyAliases = definition.legacyAliases.filter { alias in
            !(definition.key == "upright_row" &&
                normalizeExerciseIdentityName(alias) == "вертикальна тяга")
        }
        return searchableLegacyAliases + definition.searchAliases
    }

    private static func makeSearchTerms(
        _ values: [String],
        source: SearchSource,
        categoryID: String? = nil
    ) -> [SearchTerm] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let tokens = boundedSearchTokens(
                value,
                maximumCharacters: maximumSearchCandidateCharacters
            ), !tokens.isEmpty else { return nil }
            let phrase = tokens.joined(separator: " ")
            guard seen.insert(phrase).inserted else { return nil }
            return SearchTerm(
                text: value,
                tokens: tokens,
                phrase: phrase,
                compactPhrase: tokens.joined(),
                source: source,
                categoryID: categoryID
            )
        }
    }

    private static func bestMatch(
        for queryToken: String,
        in terms: [SearchTerm]
    ) -> TokenMatch? {
        var best: TokenMatch?
        for term in terms {
            var bestQualityForTerm: SearchMatchQuality?
            for candidateToken in term.tokens {
                if let quality = matchQuality(candidateToken: candidateToken, queryToken: queryToken),
                   bestQualityForTerm == nil ||
                    quality.rawValue > bestQualityForTerm!.rawValue {
                    bestQualityForTerm = quality
                }
            }
            if let compactQuality = matchQuality(
                candidateToken: term.compactPhrase,
                queryToken: queryToken
            ), bestQualityForTerm == nil ||
                compactQuality.rawValue > bestQualityForTerm!.rawValue {
                bestQualityForTerm = compactQuality
            }
            guard let quality = bestQualityForTerm else { continue }

            let candidate = TokenMatch(
                source: term.source,
                quality: quality,
                termText: term.text,
                categoryID: term.categoryID
            )
            if let best {
                let candidatePriority = candidate.source.rawValue
                let bestPriority = best.source.rawValue
                if candidatePriority < bestPriority ||
                    (candidatePriority == bestPriority &&
                        candidate.quality.rawValue < best.quality.rawValue) {
                    continue
                }
                if candidatePriority == bestPriority &&
                    candidate.quality == best.quality &&
                    candidate.termText.count >= best.termText.count {
                    continue
                }
            }
            best = candidate
        }
        return best
    }

    private static func bestCompactMatch(
        for queryCompactPhrase: String,
        in terms: [SearchTerm]
    ) -> TokenMatch? {
        var best: TokenMatch?
        for term in terms {
            let candidate = term.compactPhrase
            let transliteratedCandidate = transliterated(candidate)
            let transliteratedQuery = transliterated(queryCompactPhrase)
            let quality: SearchMatchQuality?
            if candidate == queryCompactPhrase {
                quality = .direct
            } else if (transliteratedCandidate != candidate ||
                        transliteratedQuery != queryCompactPhrase) &&
                        transliteratedCandidate == transliteratedQuery {
                quality = .transliterated
            } else if isWithinOneDamerauEdit(candidate, queryCompactPhrase) ||
                        isWithinOneDamerauEdit(transliteratedCandidate, transliteratedQuery) {
                quality = .fuzzy
            } else {
                quality = nil
            }
            guard let quality else { continue }

            let match = TokenMatch(
                source: term.source,
                quality: quality,
                termText: term.text,
                categoryID: term.categoryID
            )
            if let best,
               match.source.rawValue < best.source.rawValue ||
                (match.source == best.source &&
                    match.quality.rawValue <= best.quality.rawValue) {
                continue
            }
            best = match
        }
        return best
    }

    private static func preparedSearchQuery(_ value: String) -> PreparedSearchQuery {
        let prefix = value.prefix(maximumSearchQueryCharacters + 1)
        guard prefix.count <= maximumSearchQueryCharacters else { return .invalid }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let tokens = boundedSearchTokens(
            trimmed,
            maximumCharacters: maximumSearchQueryCharacters,
            allowTransliteratedConnectors: true
        ), !tokens.isEmpty else { return .invalid }
        // Standalone two-letter equipment abbreviations such as DB/BB are too broad.
        // They remain useful when paired with an exercise term (for example "DB curl").
        let distinctTokens = Set(tokens)
        guard !(distinctTokens.count == 1 && distinctTokens.first!.count < 3) else {
            return .invalid
        }
        return .value(
            SearchQuery(
                tokens: tokens,
                phrase: tokens.joined(separator: " "),
                compactPhrase: tokens.joined()
            )
        )
    }

    /// Produces a small Unicode-aware token list before matching any user-controlled query,
    /// generated vocabulary term, or custom exercise name.
    private static func boundedSearchTokens(
        _ value: String,
        maximumCharacters: Int,
        allowTransliteratedConnectors: Bool = false
    ) -> [String]? {
        let prefix = value.prefix(maximumCharacters + 1)
        guard prefix.count <= maximumCharacters else { return nil }

        let folded = String(prefix)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ё", with: "е")
        var separated = ""
        var pendingSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator && !separated.isEmpty {
                    separated.append(" ")
                }
                separated.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if !separated.isEmpty {
                pendingSeparator = true
            }
        }

        let rawTokens = separated
            .split(separator: " ")
            .map(String.init)
        let canDropTransliteratedConnectors =
            allowTransliteratedConnectors && rawTokens.count >= 3
        let tokens = rawTokens.filter { token in
            !ExerciseSearchVocabulary.connectorTokens.contains(token) &&
                !(canDropTransliteratedConnectors &&
                    transliteratedConnectorTokens.contains(token))
        }
        guard tokens.count <= maximumSearchQueryTokens else { return nil }
        return tokens
    }

    private static func matchQuality(
        candidateToken: String,
        queryToken: String
    ) -> SearchMatchQuality? {
        if directlyMatches(candidateToken, queryToken) {
            return .direct
        }

        let transliteratedCandidate = transliterated(candidateToken)
        let transliteratedQuery = transliterated(queryToken)
        if (transliteratedCandidate != candidateToken || transliteratedQuery != queryToken) &&
            directlyMatches(transliteratedCandidate, transliteratedQuery) {
            return .transliterated
        }

        if isWithinOneDamerauEdit(candidateToken, queryToken) ||
            isWithinOneDamerauEdit(transliteratedCandidate, transliteratedQuery) {
            return .fuzzy
        }
        return nil
    }

    private static func directlyMatches(_ candidateToken: String, _ queryToken: String) -> Bool {
        if candidateToken.contains(queryToken) {
            return true
        }
        // Keep reverse substring matching useful for inflections without letting a compound
        // query such as "pecdek" match every multi-word alias containing the short token "pec".
        if candidateToken.count >= 4 && queryToken.contains(candidateToken) { return true }

        var commonPrefixLength = 0
        for (candidateCharacter, queryCharacter) in zip(candidateToken, queryToken) {
            guard candidateCharacter == queryCharacter else { break }
            commonPrefixLength += 1
            if commonPrefixLength >= 5 { return true }
        }
        let shortestLength = min(candidateToken.count, queryToken.count)
        return commonPrefixLength >= 4 &&
            shortestLength >= minimumFuzzyTokenCharacters &&
            candidateToken.count - commonPrefixLength <= 3 &&
            queryToken.count - commonPrefixLength <= 3
    }

    /// Damerau-Levenshtein distance <= 1, restricted to long tokens to avoid broad short-query
    /// matches. This covers one insertion, deletion, substitution, or adjacent transposition.
    private static func isWithinOneDamerauEdit(_ left: String, _ right: String) -> Bool {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        guard min(leftCharacters.count, rightCharacters.count) >= minimumFuzzyTokenCharacters,
              abs(leftCharacters.count - rightCharacters.count) <= 1,
              leftCharacters != rightCharacters else {
            return false
        }

        if leftCharacters.count == rightCharacters.count {
            let mismatches = leftCharacters.indices.filter {
                leftCharacters[$0] != rightCharacters[$0]
            }
            if mismatches.count == 1 { return true }
            guard mismatches.count == 2,
                  mismatches[1] == mismatches[0] + 1 else {
                return false
            }
            let first = mismatches[0]
            let second = mismatches[1]
            return leftCharacters[first] == rightCharacters[second] &&
                leftCharacters[second] == rightCharacters[first]
        }

        let longer = leftCharacters.count > rightCharacters.count
            ? leftCharacters
            : rightCharacters
        let shorter = leftCharacters.count > rightCharacters.count
            ? rightCharacters
            : leftCharacters
        var longerIndex = 0
        var shorterIndex = 0
        var skipped = false
        while longerIndex < longer.count && shorterIndex < shorter.count {
            if longer[longerIndex] == shorter[shorterIndex] {
                longerIndex += 1
                shorterIndex += 1
            } else {
                if skipped { return false }
                skipped = true
                longerIndex += 1
            }
        }
        return true
    }

    private static func transliterated(_ value: String) -> String {
        var result = ""
        for character in value {
            let replacement: String
            switch character {
            case "а": replacement = "a"
            case "б": replacement = "b"
            case "в": replacement = "v"
            case "г", "ґ": replacement = "g"
            case "д": replacement = "d"
            case "е", "є", "э": replacement = "e"
            case "ж": replacement = "zh"
            case "з": replacement = "z"
            case "и", "і", "ї", "й", "ы": replacement = "i"
            case "к": replacement = "k"
            case "л": replacement = "l"
            case "м": replacement = "m"
            case "н": replacement = "n"
            case "о": replacement = "o"
            case "п": replacement = "p"
            case "р": replacement = "r"
            case "с": replacement = "s"
            case "т": replacement = "t"
            case "у": replacement = "u"
            case "ф": replacement = "f"
            case "х": replacement = "h"
            case "ц": replacement = "ts"
            case "ч": replacement = "ch"
            case "ш": replacement = "sh"
            case "щ": replacement = "shch"
            case "ю": replacement = "yu"
            case "я": replacement = "ya"
            case "ъ", "ь": replacement = ""
            default:
                result.append(character)
                continue
            }
            result.append(contentsOf: replacement)
        }
        return result
    }

    private static func localizedText(
        for reason: MatchReason,
        languageCode: String
    ) -> String {
        let language = languageCode.lowercased()
        switch reason {
        case let .alias(alias):
            if language.hasPrefix("uk") { return "Також шукають як «\(alias)»" }
            if language.hasPrefix("ru") { return "Также ищут как «\(alias)»" }
            return "Also known as “\(alias)”"

        case let .alternateSpelling(name):
            if language.hasPrefix("uk") { return "Збіг за іншим написанням «\(name)»" }
            if language.hasPrefix("ru") { return "Совпадение по другому написанию «\(name)»" }
            return "Matched alternate spelling of “\(name)”"

        case let .categories(muscleTokens, equipmentTokens):
            let muscle = muscleTokens.joined(separator: " · ")
            let equipment = equipmentTokens.joined(separator: " · ")
            if !muscle.isEmpty && !equipment.isEmpty {
                let values = muscle + " · " + equipment
                if language.hasPrefix("uk") { return "Збіг за м’язом і обладнанням: \(values)" }
                if language.hasPrefix("ru") { return "Совпадение по мышце и оборудованию: \(values)" }
                return "Matched muscle and equipment: \(values)"
            }
            if !muscle.isEmpty {
                if language.hasPrefix("uk") { return "Збіг за м’язом: \(muscle)" }
                if language.hasPrefix("ru") { return "Совпадение по мышце: \(muscle)" }
                return "Matched muscle: \(muscle)"
            }
            if language.hasPrefix("uk") { return "Збіг за обладнанням: \(equipment)" }
            if language.hasPrefix("ru") { return "Совпадение по оборудованию: \(equipment)" }
            return "Matched equipment: \(equipment)"
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
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
    let exerciseMediaOwnerKey: String
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
                            HStack(spacing: 12) {
                                ExerciseMediaButton(
                                    exerciseName: exercise.name,
                                    exerciseID: exercise.id,
                                    ownerKey: exerciseMediaOwnerKey
                                )
                                Button {
                                    onSelect(exercise)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(gymExerciseName(exercise))
                                                .multilineTextAlignment(.leading)
                                            if let matchReason = ExerciseFilterEngine.localizedMatchReason(
                                                for: exercise,
                                                query: search,
                                                muscleMappings: muscleMappings,
                                                languageCode: gymCurrentLanguageCode()
                                            ) {
                                                Text(matchReason)
                                                    .font(.caption)
                                                    .foregroundStyle(GymTheme.textSecondary)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        Spacer()
                                        if selectedExerciseIDs.contains(exercise.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(GymTheme.primary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
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
