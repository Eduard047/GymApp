import PhotosUI
import SwiftUI

struct WorkoutEditorSetDraft: Identifiable, Hashable, Codable {
    let id: UUID
    var weight: Double
    var reps: Int

    init(
        id: UUID = UUID(),
        weight: Double = 0,
        reps: Int = 10
    ) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }

    init(id: UUID = UUID(), recommendedSet: RecommendedWorkoutSet) {
        self.id = id
        weight = recommendedSet.weight ?? 0
        reps = recommendedSet.reps
    }

    var isReadyForSave: Bool {
        weight.isFinite && (0 ... 1_000_000).contains(weight)
    }

    var hasValidReps: Bool { (1 ... 10_000).contains(reps) }

    var storeDraft: WorkoutSetDraft {
        WorkoutSetDraft(weight: weight, reps: reps)
    }
}

struct WorkoutEditorExerciseDraft: Identifiable, Hashable, Codable {
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

/// Plan-editor caps; equal to Android `WorkoutDataLimits` and to what
/// `ActiveWorkoutStore` accepts when the plan is started.
enum WorkoutEditorLimits {
    static let maxExercises = 100
    static let maxSetsPerExercise = 100

    static func setLimitMessage() -> String {
        gymText(
            "This exercise has reached the set limit.",
            "Досягнуто ліміту підходів для вправи.",
            "Достигнут лимит подходов для упражнения.",
            languageCode: gymCurrentLanguageCode()
        )
    }

    static func exerciseLimitMessage() -> String {
        gymText(
            "This workout has reached the exercise limit.",
            "У цьому тренуванні досягнуто ліміту вправ.",
            "В этой тренировке достигнут лимит упражнений.",
            languageCode: gymCurrentLanguageCode()
        )
    }
}

extension WorkoutEditorExerciseDraft {
    /// Appends a set unless the per-exercise cap is reached; returns whether it did.
    @discardableResult
    mutating func appendSet(_ newSet: WorkoutEditorSetDraft) -> Bool {
        guard sets.count < WorkoutEditorLimits.maxSetsPerExercise else { return false }
        sets.append(newSet)
        return true
    }

    /// Inserts a copy right after `id`; false at the cap or for an unknown id.
    @discardableResult
    mutating func duplicateSet(id: UUID) -> Bool {
        guard sets.count < WorkoutEditorLimits.maxSetsPerExercise,
              let index = sets.firstIndex(where: { $0.id == id }) else { return false }
        let source = sets[index]
        sets.insert(WorkoutEditorSetDraft(weight: source.weight, reps: source.reps), at: index + 1)
        return true
    }

    /// Copies the weight and reps of set `id` onto every other set (ids and
    /// order stay); false for an unknown id or when there is nothing to apply to.
    @discardableResult
    mutating func applySetToAll(id: UUID) -> Bool {
        guard sets.count > 1, let source = sets.first(where: { $0.id == id }) else { return false }
        for index in sets.indices where sets[index].id != id {
            sets[index].weight = source.weight
            sets[index].reps = source.reps
        }
        return true
    }

    /// Removes a set; deleting the last remaining one resets it to a fresh default
    /// set (as Android does), so an exercise never ends up with zero sets.
    mutating func removeSet(id: UUID) {
        guard sets.contains(where: { $0.id == id }) else { return }
        sets.removeAll { $0.id == id }
        if sets.isEmpty { sets = [WorkoutEditorSetDraft()] }
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

/// Compact tonal pill ("Last", "Prev.", "Copy") for quick actions under a set
/// row: a 36pt fully rounded capsule (primary text on a faint primary wash) in
/// a 44pt tap target. Matches the active workout's "Log" pill.
struct GymChip: View {
    let title: Text
    let accessibilityLabel: Text
    var disabled = false
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.primary.opacity(disabled ? 0.38 : 1))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 36)
                .background(Capsule().fill(GymTheme.primary.opacity(disabled ? 0.06 : 0.12)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }
}

/// One planned set in the plan editor: number badge, the shared weight/reps
/// capsules with the trash button, and the Last / Prev. / Copy pills below.
/// Always editable. The card owns the divider and the vertical rhythm.
struct WorkoutSetDraftRow: View {
    @Binding var set: WorkoutEditorSetDraft

    let position: Int
    let exerciseName: String
    var allowedWeights: [Double] = []
    let lastWeight: Double?
    let canCopyPrevious: Bool
    let onCopyPrevious: () -> Void
    let onDuplicate: () -> Void
    /// nil hides the chip (an exercise with a single set has nothing to apply to).
    var onApplyToAll: (() -> Void)?
    let onDelete: () -> Void
    /// True after a failed start/save: invalid values then get an error border
    /// (and lose it as soon as they are corrected).
    var highlightsInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                GymSetNumberBadge(position: position)
                GymSetEditorCapsules(
                    position: position,
                    weight: $set.weight,
                    reps: $set.reps,
                    allowedWeights: allowedWeights,
                    deleteAccessibilityLabel: gymText(
                        "Delete set \(position + 1) for \(exerciseName)",
                        "Видалити підхід \(position + 1) для \(exerciseName)",
                        "Удалить подход \(position + 1) для \(exerciseName)",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    onDelete: onDelete,
                    weightInvalid: highlightsInvalid && !set.isReadyForSave,
                    repsInvalid: highlightsInvalid && !set.hasValidReps
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { quickActions }
            }
            // Start under the capsules: badge width (22) + row spacing (8).
            .padding(.leading, 30)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var quickActions: some View {
        chip(
            title: Text(
                gymText("Last", "Ост. вага", "Посл. вес", languageCode: gymCurrentLanguageCode())
            ),
            accessibilityLabel: Text(
                gymText(
                    "Last weight",
                    "Остання вага",
                    "Последний вес",
                    languageCode: gymCurrentLanguageCode()
                )
            ),
            disabled: lastWeight == nil,
            accessibilityHint: lastWeight.map {
                gymText(
                    "Uses the last logged weight, \($0.formatted(.number.locale(gymAppLocale())))",
                    "Використовує останню записану вагу: \($0.formatted(.number.locale(gymAppLocale())))",
                    "Использует последний записанный вес: \($0.formatted(.number.locale(gymAppLocale())))",
                    languageCode: gymCurrentLanguageCode()
                )
            } ?? gymLocalized("No prior weight")
        ) {
            if let lastWeight {
                set.weight = lastWeight
            }
        }

        chip(
            title: Text(
                gymText("Prev.", "Попер.", "Пред.", languageCode: gymCurrentLanguageCode())
            ),
            accessibilityLabel: Text("Previous"),
            disabled: !canCopyPrevious,
            action: onCopyPrevious
        )

        chip(
            title: Text(
                gymText("Copy", "Копія", "Копия", languageCode: gymCurrentLanguageCode())
            ),
            accessibilityLabel: Text("Copy set"),
            action: onDuplicate
        )

        if let onApplyToAll {
            let title = gymText(
                "Apply to all sets",
                "Застосувати до всіх підходів",
                "Применить ко всем подходам",
                languageCode: gymCurrentLanguageCode()
            )
            chip(
                title: Text(title),
                accessibilityLabel: Text(title),
                action: onApplyToAll
            )
        }
    }

    private func chip(
        title: Text,
        accessibilityLabel: Text,
        disabled: Bool = false,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        GymChip(
            title: title,
            accessibilityLabel: accessibilityLabel,
            disabled: disabled,
            accessibilityHint: accessibilityHint,
            action: action
        )
    }
}

struct OptionalAccessibilityHint: ViewModifier {
    let hint: String?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

@MainActor
struct WorkoutDraftExerciseCard: View {
    @Binding var draft: WorkoutEditorExerciseDraft

    let exerciseID: UUID
    let exerciseMediaOwnerKey: String
    let rawExerciseName: String
    let exerciseCatalogKey: String?
    let lastWeight: Double?
    /// The exercise's machine stops; empty means the default 2.5 kg step.
    var allowedWeights: [Double] = []
    let onShowSimilar: (() -> Void)?
    let onDeleteExercise: () -> Void
    /// Reorder handlers; nil = unavailable (first/last exercise).
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    /// Drag-to-reorder grip; nil = no handle.
    var reorderHandle: GymReorderHandleSource?
    var highlightsInvalid = false
    /// Reports a cap message (set limit) to the host's status banner.
    var onLimitReached: ((String) -> Void)?
    @State private var showingMedia = false
    @State private var mediaReloadToken = 0

    var body: some View {
        // Same card as the active and saved screens, highlighted and always
        // open: no chevron, one "⋯" menu (Replace with similar + Delete).
        GymExerciseCard(
            name: displayName,
            highlighted: true,
            collapsible: false,
            contentSpacing: 12,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            reorderHandle: reorderHandle,
            media: {
                ExerciseMediaThumbnail(
                    rawExerciseName: rawExerciseName,
                    catalogKey: exerciseCatalogKey,
                    exerciseID: exerciseID,
                    ownerKey: exerciseMediaOwnerKey,
                    reloadToken: mediaReloadToken
                ) {
                    showingMedia = true
                }
            },
            info: {
                if let lastWeight {
                    Text(
                        gymText(
                            "Last logged: \(lastWeight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))) kg",
                            "Остання вага: \(lastWeight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))) кг",
                            "Последний вес: \(lastWeight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))) кг",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
            },
            overflow: {
                GymExerciseOverflowMenu(
                    removeTitle: gymLocalized("Delete"),
                    accessibilityLabelText: gymText(
                        "Exercise actions for \(displayName)",
                        "Дії для «\(displayName)»",
                        "Действия для «\(displayName)»",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    onRemove: onDeleteExercise
                ) {
                    GymExerciseMoveMenuItems(onMoveUp: onMoveUp, onMoveDown: onMoveDown)
                    if let onShowSimilar {
                        Button(action: onShowSimilar) {
                            Label {
                                Text("Replace with similar")
                            } icon: {
                                Image(systemName: "arrow.triangle.swap")
                            }
                        }
                    }
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    if let recommendation = draft.coachRecommendation {
                        // Informational for every kind (Deload and Comeback are
                        // advice, not errors), so never the error color.
                        Text(
                            "\(recommendation.kind.coachCompactDisplayName) · " +
                                "RIR \(recommendation.targetRIR.lowerBound)–\(recommendation.targetRIR.upperBound)"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            gymText(
                                "Smart Coach: \(recommendation.kind.coachCompactDisplayName), RIR \(recommendation.targetRIR.lowerBound) to \(recommendation.targetRIR.upperBound)",
                                "Smart Coach: \(recommendation.kind.coachCompactDisplayName), RIR від \(recommendation.targetRIR.lowerBound) до \(recommendation.targetRIR.upperBound)",
                                "Smart Coach: \(recommendation.kind.coachCompactDisplayName), RIR от \(recommendation.targetRIR.lowerBound) до \(recommendation.targetRIR.upperBound)",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                    }

                    // Tight inner stack, as on the active and saved screens: each
                    // row's own 10pt vertical padding is the only gap between a
                    // row and its divider (first row has no top padding).
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, item in
                            VStack(alignment: .leading, spacing: 0) {
                                if index > 0 {
                                    Divider().overlay(GymTheme.outlineSoft)
                                }
                                WorkoutSetDraftRow(
                                    set: binding(for: item.id),
                                    position: index,
                                    exerciseName: displayName,
                                    allowedWeights: allowedWeights,
                                    lastWeight: lastWeight,
                                    canCopyPrevious: index > 0,
                                    onCopyPrevious: { copyPrevious(into: item.id) },
                                    onDuplicate: { duplicate(item.id) },
                                    onApplyToAll: draft.sets.count > 1 ? { applyToAll(item.id) } : nil,
                                    onDelete: { delete(item.id) },
                                    highlightsInvalid: highlightsInvalid
                                )
                                .padding(.top, index > 0 ? 10 : 0)
                                .padding(.bottom, 10)
                            }
                        }
                    }

                    GymDashedAddButton(
                        title: gymLocalized("+ Set"),
                        accessibilityLabelText: gymLocalized("Add planned set"),
                        accessibilityHintText: gymLocalized("Copies the latest values into a planned set"),
                        action: addSet
                    )
                }
            }
        )
        .sheet(isPresented: $showingMedia) {
            ExerciseMediaSheet(
                rawExerciseName: rawExerciseName,
                catalogKey: exerciseCatalogKey,
                exerciseID: exerciseID,
                ownerKey: exerciseMediaOwnerKey,
                editable: ExerciseMediaPresentation.isEditable(on: .editor)
            )
            .gymSheetPresentation()
        }
        .onChange(of: showingMedia) { _, isShowing in
            if !isShowing { mediaReloadToken &+= 1 }
        }
    }

    private func addSet() {
        let source = draft.sets.last
        let added = draft.appendSet(
            WorkoutEditorSetDraft(
                weight: source?.weight ?? lastWeight ?? 0,
                reps: source?.reps ?? 10
            )
        )
        if !added { onLimitReached?(WorkoutEditorLimits.setLimitMessage()) }
    }

    private var displayName: String {
        gymExerciseName(rawExerciseName, catalogKey: exerciseCatalogKey)
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
        guard draft.sets.contains(where: { $0.id == id }) else { return }
        if !draft.duplicateSet(id: id) { onLimitReached?(WorkoutEditorLimits.setLimitMessage()) }
    }

    private func applyToAll(_ id: UUID) {
        draft.applySetToAll(id: id)
    }

    private func delete(_ id: UUID) {
        draft.removeSet(id: id)
    }
}

extension WorkoutRecommendationKind {
    var coachCompactDisplayName: String {
        coachCompactDisplayName(languageCode: gymCurrentLanguageCode())
    }

    func coachCompactDisplayName(languageCode: String) -> String {
        switch self {
        case .newExercise:
            gymText("New", "Нова", "Новое", languageCode: languageCode)
        case .progressiveOverload:
            gymText("Progress", "Прогрес", "Прогресс", languageCode: languageCode)
        case .holdAndBuild:
            gymText("Hold", "Утримати", "Удержать", languageCode: languageCode)
        case .deload:
            gymText("Deload", "Делоад", "Делоад", languageCode: languageCode)
        case .comeback:
            gymText("Comeback", "Повернення", "Возврат", languageCode: languageCode)
        case .plateauBreak:
            gymText("Plateau", "Плато", "Плато", languageCode: languageCode)
        }
    }
}

enum ExerciseMediaPresentation {
    enum Surface: Equatable {
        case library
        case editor
        case picker
        case activeWorkout
    }

    static let thumbnailWidth: CGFloat = 76
    static let thumbnailHeight: CGFloat = 64
    static let thumbnailCornerRadius: CGFloat = 13
    static let playOverlayDiameter: CGFloat = 28
    static let thumbnailMaximumPixelSize = 256

    static func showsPlayOverlay(
        hasCustomImage: Bool,
        bundledFrameCount: Int
    ) -> Bool {
        !hasCustomImage && bundledFrameCount > 1
    }

    static func isEditable(on surface: Surface) -> Bool {
        surface == .library || surface == .editor
    }

    static func emptyPreviewLabel(editable: Bool, languageCode: String) -> String {
        editable
            ? gymText("Add image", "Додати фото", "Добавить фото", languageCode: languageCode)
            : gymText("No preview", "Немає демонстрації", "Нет демонстрации", languageCode: languageCode)
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
                    .padding(GymTheme.screenHorizontalInset)
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
                        rawExerciseName: alternative.exercise.name,
                        catalogKey: alternative.exercise.catalogKey,
                        exerciseID: alternative.exercise.id,
                        ownerKey: exerciseMediaOwnerKey,
                        editable: ExerciseMediaPresentation.isEditable(on: .picker)
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
                .buttonStyle(GymSecondaryButtonStyle())
            }
        }
    }

    private func prescriptionText(_ recommendation: WorkoutRecommendation) -> String {
        guard let first = recommendation.sets.first else { return gymLocalized("No prescription") }
        let setCount = recommendation.sets.count
        let weight = first.weight.map { " · \(gymWeightText($0))" } ?? ""
        return "\(setCount) × \(first.reps)\(weight)"
    }
}

struct ExerciseMediaButton: View {
    let rawExerciseName: String
    let catalogKey: String?
    let exerciseID: UUID
    let ownerKey: String
    var editable = true
    var width: CGFloat = ExerciseMediaPresentation.thumbnailWidth
    var height: CGFloat = ExerciseMediaPresentation.thumbnailHeight
    var playOverlayDiameter: CGFloat = ExerciseMediaPresentation.playOverlayDiameter
    @State private var showingMedia = false
    @State private var mediaReloadToken = 0

    var body: some View {
        ExerciseMediaThumbnail(
            rawExerciseName: rawExerciseName,
            catalogKey: catalogKey,
            exerciseID: exerciseID,
            ownerKey: ownerKey,
            editable: editable,
            reloadToken: mediaReloadToken,
            width: width,
            height: height,
            playOverlayDiameter: playOverlayDiameter,
            action: { showingMedia = true }
        )
        .sheet(isPresented: $showingMedia) {
            ExerciseMediaSheet(
                rawExerciseName: rawExerciseName,
                catalogKey: catalogKey,
                exerciseID: exerciseID,
                ownerKey: ownerKey,
                editable: editable
            )
            .gymSheetPresentation()
        }
        .onChange(of: showingMedia) { _, isShowing in
            if !isShowing { mediaReloadToken &+= 1 }
        }
    }
}

struct ExerciseMediaThumbnail: View {
    let rawExerciseName: String
    let catalogKey: String?
    let exerciseID: UUID
    let ownerKey: String
    var editable = true
    var reloadToken = 0
    var width: CGFloat = ExerciseMediaPresentation.thumbnailWidth
    var height: CGFloat = ExerciseMediaPresentation.thumbnailHeight
    var playOverlayDiameter: CGFloat = ExerciseMediaPresentation.playOverlayDiameter
    let action: () -> Void
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @State private var loadedIdentity: LoadIdentity?
    @State private var thumbnailResult: ExerciseMediaThumbnailResult?

    private struct LoadIdentity: Hashable {
        let rawExerciseName: String
        let catalogKey: String?
        let exerciseID: UUID
        let ownerKey: String
        let reloadToken: Int
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            rawExerciseName: rawExerciseName,
            catalogKey: catalogKey,
            exerciseID: exerciseID,
            ownerKey: ownerKey,
            reloadToken: reloadToken
        )
    }

    var body: some View {
        let currentResult = loadedIdentity == loadIdentity ? thumbnailResult : nil
        let image = currentResult?.image
        let showsPlayOverlay = ExerciseMediaPresentation.showsPlayOverlay(
            hasCustomImage: currentResult?.hasCustomImage ?? false,
            bundledFrameCount: currentResult?.bundledFrameCount ?? 0
        )

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
                        let emptyLabel = ExerciseMediaPresentation.emptyPreviewLabel(
                            editable: editable,
                            languageCode: languageCode
                        )
                        if width < 72 {
                            Image(systemName: editable ? "photo.badge.plus" : "photo")
                                .font(.system(size: 22))
                                .foregroundStyle(GymTheme.textSecondary)
                                .accessibilityLabel(emptyLabel)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: editable ? "photo.badge.plus" : "photo")
                                Text(emptyLabel)
                                    .font(.caption2)
                            }
                            .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                }
                .frame(
                    width: width,
                    height: height
                )
                .clipped()

                if showsPlayOverlay {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(
                            width: playOverlayDiameter,
                            height: playOverlayDiameter
                        )
                        .background(GymTheme.brandFill, in: Circle())
                        .padding(5)
                }
            }
            .background(GymTheme.surfaceVariant)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ExerciseMediaPresentation.thumbnailCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            gymText(
                "Open exercise preview",
                "Відкрити демонстрацію вправи",
                "Открыть демонстрацию упражнения",
                languageCode: languageCode
            )
        )
        .task(id: loadIdentity) {
            let requestedIdentity = loadIdentity
            loadedIdentity = nil
            thumbnailResult = nil
            let result = await ExerciseMediaStore.thumbnail(
                ownerKey: ownerKey,
                exerciseID: exerciseID,
                catalogKey: catalogKey,
                rawExerciseName: rawExerciseName,
                maximumPixelSize: ExerciseMediaPresentation.thumbnailMaximumPixelSize
            )
            guard !Task.isCancelled, requestedIdentity == loadIdentity else { return }
            thumbnailResult = result
            loadedIdentity = requestedIdentity
        }
    }
}

struct ExerciseMediaSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let rawExerciseName: String
    let catalogKey: String?
    let exerciseID: UUID
    let ownerKey: String
    let editable: Bool

    @State private var selectedItem: PhotosPickerItem?
    @State private var customImage: UIImage?
    @State private var frameIndex = 0
    @State private var errorMessage: String?

    private var bundledImages: [UIImage] {
        ExerciseMediaStore.bundledImages(
            catalogKey: catalogKey,
            rawExerciseName: rawExerciseName
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(gymExerciseName(rawExerciseName, catalogKey: catalogKey))
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
                .animation(reduceMotion ? nil : GymMotion.gentle, value: frameIndex)
                .accessibilityLabel(
                    gymText(
                        "Exercise preview",
                        "Демонстрація вправи",
                        "Демонстрация упражнения",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .accessibilityHint(
                    gymText(
                        "Shows the start and finish positions.",
                        "Показує початкове та кінцеве положення.",
                        "Показывает начальное и конечное положение.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(GymTheme.error)
                }

                if editable {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(
                            gymText(
                                "Choose your image",
                                "Обрати своє фото",
                                "Выбрать своё фото",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GymPrimaryButtonStyle())

                    if ExerciseMediaStore.shouldShowRemovePhoto(hasCustomImage: customImage != nil) {
                        Button {
                            do {
                                try ExerciseMediaStore.deleteCustomImage(
                                    ownerKey: ownerKey,
                                    exerciseID: exerciseID
                                )
                                customImage = nil
                                errorMessage = nil
                            } catch {
                                errorMessage = gymText(
                                    "Couldn’t remove this image. Try again.",
                                    "Не вдалося видалити фото. Спробуй ще раз.",
                                    "Не удалось удалить фото. Попробуй ещё раз.",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            }
                        } label: {
                            Label(
                                bundledImages.isEmpty
                                    ? gymText(
                                        "Remove photo",
                                        "Видалити фото",
                                        "Удалить фото",
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                    : gymText(
                                        "Restore built-in preview",
                                        "Повернути вбудовану демонстрацію",
                                        "Вернуть встроенную демонстрацию",
                                        languageCode: gymCurrentLanguageCode()
                                    ),
                                systemImage: "arrow.uturn.backward"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GymSecondaryButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle(
                gymText(
                    "Exercise preview",
                    "Демонстрація вправи",
                    "Демонстрация упражнения",
                    languageCode: gymCurrentLanguageCode()
                )
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
        .onChange(of: selectedItem) { _, item in
            guard editable, let item else { return }
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
                        "Не вдалося використати фото. Обери зображення до 8 МБ.",
                        "Не удалось использовать фото. Выбери изображение до 8 МБ.",
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
                                "\(remaining) \(remaining == 1 ? "second" : "seconds") remaining",
                                "Залишилося \(remaining) с",
                                "Осталось \(remaining) с",
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
                    "Уменьшить отдых на 15 секунд",
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
                    "Добавить 15 секунд отдыха",
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
                Button(gymText("\(seconds)s", "\(seconds)\u{00A0}с", "\(seconds)\u{00A0}с", languageCode: gymCurrentLanguageCode())) {
                    if let onStart { onStart(seconds) }
                    else { manager.start(id: timerID, seconds: seconds, title: exerciseName) }
                }
                .accessibilityLabel(
                    gymText(
                        "Start \(seconds) second rest timer for \(exerciseName)",
                        "Запустити таймер відпочинку на \(seconds) с для «\(exerciseName)»",
                        "Запустить таймер отдыха на \(seconds) с для «\(exerciseName)»",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        }
    }

    static func clock(_ seconds: Int) -> String {
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
        case .upper: gymText("Upper body", "Верх тіла", "Верх тела", languageCode: gymCurrentLanguageCode())
        case .lower: gymText("Lower body", "Низ тіла", "Низ тела", languageCode: gymCurrentLanguageCode())
        case .core: gymText("Core", "Кор", "Кор", languageCode: gymCurrentLanguageCode())
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
            gymText("By name", "За назвою", "По названию", languageCode: gymCurrentLanguageCode())
        case .mostFrequent:
            gymText("Most frequent", "Найчастіші", "Самые частые", languageCode: gymCurrentLanguageCode())
        case .leastFrequent:
            gymText("Least frequent", "Найрідші", "Реже всего", languageCode: gymCurrentLanguageCode())
        }
    }
}

/// "Frequent" shortlist of the exercise picker. Mirrors Android `frequentExerciseIds`:
/// the top exercises by number of distinct workouts they appear in, ties broken by the
/// most recent session date, then by a stable id order. Exercises never used are excluded.
enum ExercisePickerFrequent {
    static let defaultLimit = 12

    static func topIDs(
        sessionCounts: [UUID: Int],
        latestSessionDates: [UUID: Date] = [:],
        limit: Int = defaultLimit
    ) -> [UUID] {
        guard limit > 0 else { return [] }
        return sessionCounts
            .filter { $0.value > 0 }
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                let leftDate = latestSessionDates[left.key] ?? .distantPast
                let rightDate = latestSessionDates[right.key] ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.key.uuidString < right.key.uuidString
            }
            .prefix(limit)
            .map(\.key)
    }

    /// Latest workout date per exercise from the history snapshot.
    static func latestSessionDates(from history: [ExerciseHistoryEntry]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for entry in history where entry.sessionDate > (result[entry.exerciseID] ?? .distantPast) {
            result[entry.exerciseID] = entry.sessionDate
        }
        return result
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

    /// Higher raw values rank higher. A word-prefix hit always outranks a mid-word
    /// containment hit of the same kind (direct or transliterated).
    private enum SearchMatchQuality: Int {
        case fuzzy = 1
        case transliterated = 2
        case transliteratedPrefix = 3
        case direct = 4
        case directPrefix = 5

        var isDirect: Bool {
            self == .direct || self == .directPrefix
        }
    }

    private enum DirectMatchKind {
        case wordPrefix
        case contained
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
            $0.source == .canonical && !$0.quality.isDirect
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
        // One- and two-letter tokens only match name sources (canonical names and
        // aliases), never muscle or equipment vocabulary.
        let nameSourcesOnly = queryToken.count < 3
        for term in terms {
            if nameSourcesOnly && term.source.isCategory { continue }
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
            maximumCharacters: maximumSearchQueryCharacters
        ), !tokens.isEmpty else { return .invalid }
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
    static func boundedSearchTokens(
        _ value: String,
        maximumCharacters: Int
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
        // Same rule as Android exerciseSearchTokens: connector words and their transliterations
        // are always dropped, whatever the token count (shared/exercise-search-v1.json).
        var tokens = rawTokens.filter { token in
            !ExerciseSearchVocabulary.connectorTokens.contains(token) &&
                !transliteratedConnectorTokens.contains(transliterated(token))
        }
        // Text made only of connector words ("a", "в", a custom exercise named "V") keeps its raw
        // tokens, for queries and name terms alike, so it stays searchable.
        if tokens.isEmpty {
            tokens = rawTokens
        }
        guard tokens.count <= maximumSearchQueryTokens else { return nil }
        return tokens
    }

    private static func matchQuality(
        candidateToken: String,
        queryToken: String
    ) -> SearchMatchQuality? {
        if let kind = directMatchKind(candidateToken, queryToken) {
            return kind == .wordPrefix ? .directPrefix : .direct
        }

        let transliteratedCandidate = transliterated(candidateToken)
        let transliteratedQuery = transliterated(queryToken)
        if transliteratedCandidate != candidateToken || transliteratedQuery != queryToken,
           let kind = directMatchKind(transliteratedCandidate, transliteratedQuery) {
            return kind == .wordPrefix ? .transliteratedPrefix : .transliterated
        }

        if isWithinOneDamerauEdit(candidateToken, queryToken) ||
            isWithinOneDamerauEdit(transliteratedCandidate, transliteratedQuery) {
            return .fuzzy
        }
        return nil
    }

    /// Classifies a direct token hit: `.wordPrefix` when the match starts at the beginning
    /// of the candidate word, `.contained` for a mid-word hit.
    private static func directMatchKind(
        _ candidateToken: String,
        _ queryToken: String
    ) -> DirectMatchKind? {
        // One- and two-letter query tokens only match as a word prefix.
        if queryToken.count < 3 {
            return candidateToken.hasPrefix(queryToken) ? .wordPrefix : nil
        }
        if candidateToken.hasPrefix(queryToken) { return .wordPrefix }
        if candidateToken.contains(queryToken) { return .contained }
        // Keep reverse substring matching useful for inflections without letting a compound
        // query such as "pecdek" match every multi-word alias containing the short token "pec".
        if candidateToken.count >= 4 && queryToken.contains(candidateToken) {
            return queryToken.hasPrefix(candidateToken) ? .wordPrefix : .contained
        }

        var commonPrefixLength = 0
        for (candidateCharacter, queryCharacter) in zip(candidateToken, queryToken) {
            guard candidateCharacter == queryCharacter else { break }
            commonPrefixLength += 1
            if commonPrefixLength >= 5 { return .wordPrefix }
        }
        let shortestLength = min(candidateToken.count, queryToken.count)
        let sharesInflectedStem = commonPrefixLength >= 4 &&
            shortestLength >= minimumFuzzyTokenCharacters &&
            candidateToken.count - commonPrefixLength <= 3 &&
            queryToken.count - commonPrefixLength <= 3
        return sharesInflectedStem ? .wordPrefix : nil
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

    static func transliterated(_ value: String) -> String {
        var result = ""
        for character in value {
            let replacement: String
            switch character {
            case "а": replacement = "a"
            case "б": replacement = "b"
            case "в": replacement = "v"
            case "г", "ґ": replacement = "g"
            case "д": replacement = "d"
            case "е", "ё", "э": replacement = "e"
            case "є": replacement = "ye"
            case "ж": replacement = "zh"
            case "з": replacement = "z"
            case "и", "і": replacement = "i"
            case "ї": replacement = "yi"
            case "й", "ы": replacement = "y"
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

/// History-derived inputs of the exercise picker. Scanning the whole history is not free, so the
/// picker builds this once per presentation (`ExercisePickerHistoryCache`), not on every parent re-render.
struct ExercisePickerHistorySnapshot {
    var latestSessionDates: [UUID: Date] = [:]
    /// Last distinct exercises logged, newest first (`GymRecentExercises`), already limited to the exercises
    /// the picker offers (not those already in the workout).
    var recentExerciseIDs: [UUID] = []
}

private final class ExercisePickerHistoryCache {
    private var value: ExercisePickerHistorySnapshot?

    func snapshot(_ make: () -> ExercisePickerHistorySnapshot) -> ExercisePickerHistorySnapshot {
        if let value { return value }
        let made = make()
        value = made
        return made
    }
}

struct ExercisePickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    /// Lives as long as this presentation of the sheet; fills itself on first read.
    @State private var historyCache = ExercisePickerHistoryCache()
    @State private var search = ""
    @State private var newExerciseName = ""
    @State private var errorMessage: String?
    @State private var bodyFilter: ExerciseBodyFilter = .all
    @State private var muscleFilter: String?
    @State private var favoritesOnly = false
    @State private var sortMode: ExerciseSortMode = .name
    @State private var frequentOnly = false

    let exercises: [Exercise]
    let selectedExerciseIDs: Set<UUID>
    let exerciseMediaOwnerKey: String
    let muscleMappings: [ExerciseMuscleMapping]
    let sessionCounts: [UUID: Int]
    /// Evaluated at most once per presentation of the sheet.
    var historySnapshot: () -> ExercisePickerHistorySnapshot = { ExercisePickerHistorySnapshot() }
    /// Overrides the default "Add exercise" navigation title (e.g. "Replace exercise").
    var title: String?
    let onSelect: (Exercise) -> Void
    let onCreate: (String) throws -> Exercise

    private var frequentIDs: [UUID] {
        ExercisePickerFrequent.topIDs(
            sessionCounts: sessionCounts,
            latestSessionDates: history.latestSessionDates
        )
    }

    private var history: ExercisePickerHistorySnapshot {
        historyCache.snapshot(historySnapshot)
    }

    /// Like Android, the shortlist is applied after search, filters and sort.
    private var filteredExercises: [Exercise] {
        let result = ExerciseFilterEngine.filtered(
            exercises: exercises,
            query: search,
            bodyFilter: bodyFilter,
            muscleFilter: muscleFilter,
            favoritesOnly: favoritesOnly,
            sortMode: sortMode,
            muscleMappings: muscleMappings,
            sessionCounts: sessionCounts
        )
        guard frequentOnly else { return result }
        let frequent = Set(frequentIDs)
        return result.filter { frequent.contains($0.id) }
    }

    /// "Recent" shows only while the search field is empty and no filter chip narrows the list.
    private var recentExercises: [Exercise] {
        guard search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !frequentOnly, !favoritesOnly, bodyFilter == .all, muscleFilter == nil,
              !history.recentExerciseIDs.isEmpty else { return [] }
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Exercises already in the workout never show in Recent (they would only be disabled rows).
        return Array(
            history.recentExerciseIDs
                .filter { !selectedExerciseIDs.contains($0) }
                .compactMap { byID[$0] }
                .prefix(GymRecentExercises.maxCount)
        )
    }

    /// Section label shared by "Recent" and "All exercises": subheadline semibold secondary, sentence case,
    /// so both read the same as the Android picker's section titles.
    private func pickerSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// One exercise row, shared by the "Recent" section and the normal list.
    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            ExerciseMediaButton(
                rawExerciseName: exercise.name,
                catalogKey: exercise.catalogKey,
                exerciseID: exercise.id,
                ownerKey: exerciseMediaOwnerKey,
                editable: ExerciseMediaPresentation.isEditable(on: .picker)
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

    /// One horizontally scrolling chip row that bleeds to the sheet edges (no list inset or
    /// separator), so a chip is never cut by the row's own padding.
    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var body: some View {
        NavigationStack {
            List {
                let recent = recentExercises
                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { exercise in
                            exerciseRow(exercise)
                                .id("recent-\(exercise.id.uuidString)")
                        }
                    } header: {
                        pickerSectionTitle(gymText("Recent", "Нещодавні", "Недавние", languageCode: gymCurrentLanguageCode()))
                    }
                }

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
                    chipRow {
                        Button(gymText("All", "Усі", "Все", languageCode: gymCurrentLanguageCode())) {
                            frequentOnly = false
                        }
                        .buttonStyle(.bordered)
                        .tint(!frequentOnly ? GymTheme.primary : GymTheme.textSecondary)
                        .accessibilityAddTraits(!frequentOnly ? .isSelected : [])

                        Button {
                            frequentOnly = true
                            sortMode = .mostFrequent
                        } label: {
                            Label(
                                gymText("Frequent", "Часті", "Частые", languageCode: gymCurrentLanguageCode()),
                                systemImage: "star.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(frequentOnly ? GymTheme.primary : GymTheme.textSecondary)
                        .accessibilityAddTraits(frequentOnly ? .isSelected : [])
                    }

                    chipRow {
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

                    chipRow {
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

                    chipRow {
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
                                    muscle.titleRu,
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

                    if filteredExercises.isEmpty {
                        if frequentOnly && frequentIDs.isEmpty {
                            GymInlineState(
                                gymText(
                                    "Your frequently used exercises will appear here after you save some workouts.",
                                    "Часто використовувані вправи з\u{2019}являться тут після збереження тренувань.",
                                    "Часто используемые упражнения появятся здесь после сохранения тренировок.",
                                    languageCode: gymCurrentLanguageCode()
                                ),
                                systemImage: "star"
                            )
                        } else {
                            GymContentUnavailableView.search(text: search)
                        }
                    } else {
                        if !recent.isEmpty {
                            pickerSectionTitle(gymText("All exercises", "Усі вправи", "Все упражнения", languageCode: gymCurrentLanguageCode()))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                        }
                        ForEach(filteredExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle(title.map { Text($0) } ?? Text("Add exercise"))
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
