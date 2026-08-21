import Foundation

struct WorkoutPlanEditorDraftStore {
    private static let keyPrefix = "gymapp.workout-plan-draft.v1."
    private static let maximumBytes = 256 * 1_024
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(accountStorageKey: String) -> WorkoutPlanEditorDraftState? {
        guard !accountStorageKey.isEmpty,
              let data = defaults.data(forKey: Self.keyPrefix + accountStorageKey),
              !data.isEmpty,
              data.count <= Self.maximumBytes,
              let draft = try? JSONDecoder().decode(WorkoutPlanEditorDraftState.self, from: data),
              draft.belongs(to: accountStorageKey),
              draft.note.count <= 4_000,
              draft.drafts.count <= 100,
              draft.drafts.allSatisfy({ !$0.sets.isEmpty && $0.sets.count <= 100 }) else {
            clear(accountStorageKey: accountStorageKey)
            return nil
        }
        return draft
    }

    func save(_ draft: WorkoutPlanEditorDraftState?, accountStorageKey: String) {
        guard !accountStorageKey.isEmpty else { return }
        guard let draft else {
            clear(accountStorageKey: accountStorageKey)
            return
        }
        guard draft.belongs(to: accountStorageKey),
              let data = try? JSONEncoder().encode(draft),
              data.count <= Self.maximumBytes else {
            return
        }
        defaults.set(data, forKey: Self.keyPrefix + accountStorageKey)
    }

    func clear(accountStorageKey: String) {
        guard !accountStorageKey.isEmpty else { return }
        defaults.removeObject(forKey: Self.keyPrefix + accountStorageKey)
    }
}
