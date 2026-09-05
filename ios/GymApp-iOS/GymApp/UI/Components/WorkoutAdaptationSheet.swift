import SwiftUI

struct WorkoutAdaptationRequest: Identifiable {
    let id = UUID()
    let source: ActiveWorkoutDraft
    let reason: String
    let catalog: [Exercise]
    let history: [ExerciseHistoryEntry]
    let mappings: [ExerciseMuscleMapping]
    let profile: TrainingProfile
    @MainActor init(source: ActiveWorkoutDraft, reason: String, store: WorkoutStore) {
        self.source = source; self.reason = reason
        catalog = store.exercises; history = store.allExerciseHistory(); mappings = store.muscleMappings
        profile = TrainingProfileStore().load(accountStorageKey: store.accountStorageKey)
    }
    static func title(_ reason: String) -> String {
        switch reason {
        case "equipmentUnavailable": gymText("Equipment busy", "Тренажер зайнятий", "Тренажёр занят", languageCode: gymCurrentLanguageCode())
        case "timeCut": gymText("Short on time", "Мало часу", "Мало времени", languageCode: gymCurrentLanguageCode())
        default: gymText("Too hard today", "Сьогодні надто важко", "Сегодня слишком тяжело", languageCode: gymCurrentLanguageCode())
        }
    }
}

struct WorkoutAdaptationSheet: View {
    let request: WorkoutAdaptationRequest
    @ObservedObject var workoutStore: WorkoutStore
    @ObservedObject var activeStore: ActiveWorkoutStore
    @ObservedObject var coordinator: LiveWorkoutCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: ActiveWorkoutDraft?
    @State private var error: String?
    private func t(_ en: String, _ uk: String, _ ru: String) -> String { gymText(en, uk, ru, languageCode: gymCurrentLanguageCode()) }
    private var alternatives: [SmartWorkoutAlternative] {
        guard let block = request.source.exercises.first(where: { $0.sets.contains(where: { !$0.isCompleted }) }),
              let current = request.catalog.first(where: { $0.id == block.exerciseID }) else { return [] }
        return RecommendationEngine.findAlternatives(currentExercise: current,
            selectedExerciseIDs: Set(request.source.exercises.filter { $0.id != block.id }.map(\.exerciseID)),
            exercises: request.catalog, history: request.history, muscleMappings: request.mappings,
            trainingProfile: request.profile, effort: .standard, allowsHardSetBoost: false, limit: 6)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let candidate {
                        Text("\(request.source.plannedSetCount - request.source.completedSetCount) → \(candidate.plannedSetCount - candidate.completedSetCount) " + t("remaining sets", "підходів залишилось", "оставшихся подходов")).font(.headline)
                        if request.reason == "timeCut" {
                            Text(t("Duration is an estimate, including rest between sets.", "Тривалість приблизна, з відпочинком між підходами.", "Длительность приблизительная, с отдыхом между подходами."))
                        }
                        ForEach(candidate.exercises) { block in
                            let pending = block.sets.filter { !$0.isCompleted }
                            if !pending.isEmpty {
                                let old = request.source.exercises.first { $0.sets.contains { $0.id == pending[0].id } }
                                VStack(alignment: .leading, spacing: 8) {
                                    if let old, old.exerciseID != block.exerciseID { Text(gymExerciseName(old.exerciseName ?? "") + " →").font(.subheadline) }
                                    Text(gymExerciseName(block.exerciseName ?? "")).font(.headline)
                                    ForEach(pending) { set in
                                        let before = old?.sets.first { $0.id == set.id }
                                        Text((before.map { "\($0.weight.formatted()) kg × \($0.reps) → " } ?? "") + "\(set.weight.formatted()) kg × \(set.reps)")
                                    }
                                }
                            }
                        }
                        Button(t("Apply changes", "Застосувати зміни", "Применить изменения")) { apply(candidate) }
                            .buttonStyle(GymPrimaryButtonStyle())
                    } else if request.reason == "timeCut" {
                        Text(t("Minutes remaining", "Залишилось хвилин", "Осталось минут"))
                        HStack { ForEach([10, 20, 30], id: \.self) { minutes in
                            Button("\(minutes)") { candidate = WorkoutAdaptation.build(request.source, reason: request.reason, minutes: minutes, catalog: request.catalog) }
                                .buttonStyle(GymSecondaryButtonStyle())
                        } }
                    } else if request.reason == "equipmentUnavailable" {
                        ForEach(alternatives, id: \.exercise.id) { alternative in
                            Button(gymExerciseName(alternative.exercise)) {
                                candidate = WorkoutAdaptation.build(request.source, reason: request.reason, catalog: request.catalog, replacement: alternative)
                            }.buttonStyle(GymSecondaryButtonStyle())
                        }
                        if alternatives.isEmpty { Text(t("No similar exercise available.", "Схожої вправи немає.", "Нет доступного похожего упражнения.")) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }.navigationTitle(WorkoutAdaptationRequest.title(request.reason))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "Скасувати", "Отмена")) { dismiss() } } }
                .onAppear { if request.reason == "tooHard" { candidate = WorkoutAdaptation.build(request.source, reason: request.reason, catalog: request.catalog) } }
        }
    }
    private func apply(_ candidate: ActiveWorkoutDraft) {
        do {
            guard request.catalog == workoutStore.exercises, request.history == workoutStore.allExerciseHistory(),
                  request.mappings == workoutStore.muscleMappings,
                  request.profile == TrainingProfileStore().load(accountStorageKey: workoutStore.accountStorageKey) else { throw ActiveWorkoutStoreError.staleDraft }
            try activeStore.applyAdaptation(source: request.source, candidate: candidate, isSolo: { !coordinator.planIsFrozenForCurrentDraft })
            dismiss()
        } catch {
            self.error = t("Workout changed or could not be saved. Close and try again.", "Тренування змінилося або не збереглося. Закрий і повтори.", "Тренировка изменилась или не сохранилась. Закройте и повторите.")
        }
    }
}
