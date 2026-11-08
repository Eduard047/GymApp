import Foundation

/// A dictionary loaded for one account (`ownerKey` is its `accountStorageKey`). Reading it for another
/// account yields nothing, so state kept across an account switch never shows the old account's entries
/// (Android tags its loaded maps with the owner key the same way).
struct AccountScopedMap<Value> {
    let ownerKey: String
    let entries: [String: Value]

    /// Nothing loaded yet; matches no real account.
    static var empty: AccountScopedMap { AccountScopedMap(ownerKey: "", entries: [:]) }

    /// The entries when they belong to `ownerKey`, else an empty map.
    func entries(forOwner ownerKey: String) -> [String: Value] {
        self.ownerKey == ownerKey ? entries : [:]
    }

    /// The map after `key` was stored (`value`) or removed (nil) for `ownerKey`, or nil when this map was
    /// loaded for another account, so the caller reloads instead of mixing accounts.
    func applying(key: String, value: Value?, forOwner ownerKey: String) -> AccountScopedMap? {
        guard self.ownerKey == ownerKey else { return nil }
        var next = entries
        next[key] = value
        return AccountScopedMap(ownerKey: ownerKey, entries: next)
    }
}

/// The custom rests of the signed-in account for the Live Activity "log set" path, decoded once per account
/// instead of on every rest start. Call `invalidate()` after anything writes or clears the rest store.
final class ExerciseRestTimesCache: @unchecked Sendable {
    static let shared = ExerciseRestTimesCache()

    private let lock = NSLock()
    private let makeStore: () -> ExerciseRestTimeStore
    private var cached: AccountScopedMap<Int>?

    init(makeStore: @escaping () -> ExerciseRestTimeStore = { ExerciseRestTimeStore() }) {
        self.makeStore = makeStore
    }

    /// Same answer as `ExerciseRestTimeStore.restSeconds`, served from the cache.
    func restSeconds(accountStorageKey: String, identityKey: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        if cached?.ownerKey != accountStorageKey {
            cached = AccountScopedMap(
                ownerKey: accountStorageKey,
                entries: makeStore().restTimes(accountStorageKey: accountStorageKey)
            )
        }
        return cached?.entries[identityKey]
    }

    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}
