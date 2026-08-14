import Foundation

enum AppTutorialCompletion: String, Codable, Equatable, Sendable {
    case completed
    case skipped
}

struct AppTutorialProgress: Codable, Equatable, Sendable {
    let version: Int
    let completion: AppTutorialCompletion
}

struct AppTutorialStore {
    static let currentVersion = 1
    private static let keyPrefix = "gymapp.app-tutorial.v1."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func progress(accountStorageKey: String) -> AppTutorialProgress? {
        guard let data = defaults.data(forKey: key(for: accountStorageKey)),
              data.count <= 256,
              let value = try? JSONDecoder().decode(AppTutorialProgress.self, from: data),
              value.version == Self.currentVersion else {
            return nil
        }
        return value
    }

    func needsAutomaticPresentation(accountStorageKey: String) -> Bool {
        progress(accountStorageKey: accountStorageKey) == nil
    }

    @discardableResult
    func record(
        _ completion: AppTutorialCompletion,
        accountStorageKey: String
    ) -> Bool {
        let value = AppTutorialProgress(
            version: Self.currentVersion,
            completion: completion
        )
        guard let data = try? JSONEncoder().encode(value), data.count <= 256 else {
            return false
        }
        let key = key(for: accountStorageKey)
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    func clear(accountStorageKey: String) {
        defaults.removeObject(forKey: key(for: accountStorageKey))
    }

    private func key(for accountStorageKey: String) -> String {
        Self.keyPrefix + accountStorageKey
    }
}
