import Foundation

struct TrainingProfileStore {
    private static let profileKeyPrefix = "gymapp.training-profile.v1."
    private static let activationDismissedKeyPrefix =
        "gymapp.training-activation-dismissed.v1."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(accountStorageKey: String) -> TrainingProfile {
        guard let data = defaults.data(forKey: Self.profileKeyPrefix + accountStorageKey),
              let profile = try? JSONDecoder().decode(TrainingProfile.self, from: data) else {
            return TrainingProfile()
        }
        return TrainingProfile(
            split: profile.split,
            workoutsPerWeek: profile.workoutsPerWeek,
            goal: profile.goal,
            calorieMode: profile.calorieMode
        )
    }

    @discardableResult
    func save(_ profile: TrainingProfile, accountStorageKey: String) -> Bool {
        guard let data = try? JSONEncoder().encode(profile) else { return false }
        defaults.set(data, forKey: Self.profileKeyPrefix + accountStorageKey)
        return defaults.data(forKey: Self.profileKeyPrefix + accountStorageKey) == data
    }

    func activationDismissed(accountStorageKey: String) -> Bool {
        defaults.bool(forKey: Self.activationDismissedKeyPrefix + accountStorageKey)
    }

    @discardableResult
    func setActivationDismissed(_ dismissed: Bool, accountStorageKey: String) -> Bool {
        let key = Self.activationDismissedKeyPrefix + accountStorageKey
        if dismissed {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return dismissed
            ? (defaults.object(forKey: key) as? Bool) == true
            : defaults.object(forKey: key) == nil
    }

    /// Commits the first-workout profile and dismissal as one observable operation.
    /// If either write or the synchronous launch handoff fails, both previous values
    /// are restored so a partial activation cannot leak into the next attempt.
    func withCommittedActivation(
        _ profile: TrainingProfile,
        accountStorageKey: String,
        launch: () -> Bool
    ) -> Bool {
        let profileKey = Self.profileKeyPrefix + accountStorageKey
        let dismissedKey = Self.activationDismissedKeyPrefix + accountStorageKey
        let previousProfile = defaults.object(forKey: profileKey)
        let previousDismissed = defaults.object(forKey: dismissedKey)
        guard let encodedProfile = try? JSONEncoder().encode(profile) else { return false }

        defaults.set(encodedProfile, forKey: profileKey)
        defaults.set(true, forKey: dismissedKey)
        guard defaults.data(forKey: profileKey) == encodedProfile,
              (defaults.object(forKey: dismissedKey) as? Bool) == true,
              launch() else {
            restore(previousProfile, forKey: profileKey)
            restore(previousDismissed, forKey: dismissedKey)
            return false
        }
        return true
    }

    func clear(accountStorageKey: String) {
        defaults.removeObject(forKey: Self.profileKeyPrefix + accountStorageKey)
        defaults.removeObject(
            forKey: Self.activationDismissedKeyPrefix + accountStorageKey
        )
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
