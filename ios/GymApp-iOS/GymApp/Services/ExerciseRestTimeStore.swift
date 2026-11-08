import Foundation

/// A custom rest per exercise (device-local, never synced); shared/exercise-rest-v1.json.
enum ExerciseRestTime {
    static let minimumSeconds = 15
    static let maximumSeconds = 600
    static let stepSeconds = 15

    /// The custom rest kept for `raw`, or nil when there is none: non-positive means none, anything else is clamped.
    static func normalize(_ raw: Int?) -> Int? {
        guard let raw, raw > 0 else { return nil }
        return min(max(raw, minimumSeconds), maximumSeconds)
    }

    /// The rest to start after a set: the normalized custom value, else the unchanged default.
    static func effectiveSeconds(stored: Int?, defaultSeconds: Int) -> Int {
        normalize(stored) ?? defaultSeconds
    }
}

/// What `ExerciseRestTimeStore.setRestSeconds` did.
enum ExerciseRestSaveResult: Equatable {
    case stored(Int)
    /// No custom rest was given, so the exercise uses its default again.
    case removed
    /// A new custom rest was refused because the account already keeps `ExerciseRestTimeStore.maximumEntries`.
    case tooMany
    /// Unusable account or key, or the write failed.
    case failed
}

/// Custom rest per account (`accountStorageKey`) and exercise identity (`FriendGhosts.exerciseKey`), in
/// UserDefaults like `ExerciseCueStore`. Kept on sign-out; wiped by account deletion cleanup.
struct ExerciseRestTimeStore {
    static let maximumEntries = 1_000
    private static let keyPrefix = "gymapp.exercise-rest.v1."
    /// Room for `maximumEntries` worst-case entries, like Android (1000 entries, no byte cap): a key of up to
    /// 512 characters at up to 4 UTF-8 bytes each (the cue store's identity-key limit), a seconds value of up to
    /// 4 digits, plus quotes, colon and comma. 1000 max-length Cyrillic keys come to about 1 MB.
    private static let maximumBytes = maximumEntries * (512 * 4 + 4 + 8)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restSeconds(accountStorageKey: String, identityKey: String) -> Int? {
        guard Self.isUsableAccount(accountStorageKey), ExerciseCueStore.isUsableIdentityKey(identityKey) else { return nil }
        return ExerciseRestTime.normalize(load(accountStorageKey)[identityKey])
    }

    /// Every custom rest of the account by identity key, read once (the active workout keeps it in state).
    func restTimes(accountStorageKey: String) -> [String: Int] {
        guard Self.isUsableAccount(accountStorageKey) else { return [:] }
        return load(accountStorageKey).reduce(into: [:]) { result, entry in
            if ExerciseCueStore.isUsableIdentityKey(entry.key), let seconds = ExerciseRestTime.normalize(entry.value) {
                result[entry.key] = seconds
            }
        }
    }

    /// Stores the normalized `seconds` (nil or non-positive removes the custom rest).
    @discardableResult
    func setRestSeconds(_ seconds: Int?, accountStorageKey: String, identityKey: String) -> ExerciseRestSaveResult {
        guard Self.isUsableAccount(accountStorageKey), ExerciseCueStore.isUsableIdentityKey(identityKey) else { return .failed }
        var times = load(accountStorageKey)
        guard let normalized = ExerciseRestTime.normalize(seconds) else {
            if times.removeValue(forKey: identityKey) != nil, !save(times, accountStorageKey) { return .failed }
            return .removed
        }
        if times[identityKey] == nil, times.count >= Self.maximumEntries { return .tooMany }
        times[identityKey] = normalized
        return save(times, accountStorageKey) ? .stored(normalized) : .failed
    }

    func clear(accountStorageKey: String) {
        defaults.removeObject(forKey: Self.keyPrefix + accountStorageKey)
    }

    private static func isUsableAccount(_ key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && key.count <= 512
            && !key.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private func load(_ accountStorageKey: String) -> [String: Int] {
        guard let data = defaults.data(forKey: Self.keyPrefix + accountStorageKey),
              data.count <= Self.maximumBytes,
              let value = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return value
    }

    @discardableResult
    private func save(_ times: [String: Int], _ accountStorageKey: String) -> Bool {
        let key = Self.keyPrefix + accountStorageKey
        if times.isEmpty {
            defaults.removeObject(forKey: key)
            return true
        }
        guard let data = try? JSONEncoder().encode(times), data.count <= Self.maximumBytes else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }
}
