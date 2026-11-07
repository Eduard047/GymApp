import Foundation

/// A short pinned note per exercise ("seat 4, narrow grip"), device-local and never synced.
enum ExerciseCue {
    /// Counted in Unicode scalars, like Android code points (shared/exercise-cue-v1.json).
    static let maximumCodePoints = 80

    /// The stored text for `raw`, or nil when it is empty (the cue is removed): line breaks become
    /// single spaces, trimmed, cut to `maximumCodePoints`, trimmed again.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lineBreaks: Set<UInt32> = [0x0A, 0x0D, 0x85, 0x2028, 0x2029]
        var singleLine = String.UnicodeScalarView()
        for scalar in raw.replacingOccurrences(of: "\r\n", with: " ").unicodeScalars {
            singleLine.append(lineBreaks.contains(scalar.value) ? " " : scalar)
        }
        let trimmed = String(singleLine).trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(maximumCodePoints)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }
}

/// Cues per account (`accountStorageKey`) and exercise identity (`FriendGhosts.exerciseKey`), in
/// UserDefaults like `AppTutorialStore`. Kept on sign-out; wiped by account deletion cleanup.
struct ExerciseCueStore {
    static let maximumEntries = 1_000
    private static let keyPrefix = "gymapp.exercise-cues.v1."
    private static let maximumKeyCharacters = 512
    private static let maximumBytes = 512 * 1_024

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cue(accountStorageKey: String, identityKey: String) -> String? {
        guard Self.isUsable(accountStorageKey), Self.isUsable(identityKey) else { return nil }
        return ExerciseCue.normalize(load(accountStorageKey)[identityKey])
    }

    /// Stores the normalized `raw` (an empty result removes the cue) and returns what is now stored.
    @discardableResult
    func setCue(_ raw: String?, accountStorageKey: String, identityKey: String) -> String? {
        guard Self.isUsable(accountStorageKey), Self.isUsable(identityKey) else { return nil }
        var cues = load(accountStorageKey)
        guard let normalized = ExerciseCue.normalize(raw) else {
            if cues.removeValue(forKey: identityKey) != nil { save(cues, accountStorageKey) }
            return nil
        }
        if cues[identityKey] == nil, cues.count >= Self.maximumEntries { return nil }
        cues[identityKey] = normalized
        return save(cues, accountStorageKey) ? normalized : self.cue(accountStorageKey: accountStorageKey, identityKey: identityKey)
    }

    func clear(accountStorageKey: String) {
        defaults.removeObject(forKey: Self.keyPrefix + accountStorageKey)
    }

    private static func isUsable(_ key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && key.count <= maximumKeyCharacters
            && !key.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private func load(_ accountStorageKey: String) -> [String: String] {
        guard let data = defaults.data(forKey: Self.keyPrefix + accountStorageKey),
              data.count <= Self.maximumBytes,
              let value = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return value
    }

    @discardableResult
    private func save(_ cues: [String: String], _ accountStorageKey: String) -> Bool {
        let key = Self.keyPrefix + accountStorageKey
        if cues.isEmpty {
            defaults.removeObject(forKey: key)
            return true
        }
        guard let data = try? JSONEncoder().encode(cues), data.count <= Self.maximumBytes else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }
}
