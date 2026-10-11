#if DEBUG
import CryptoKit
import Foundation

// DEBUG-only launch hooks for the local UI-audit capture scripts. Nothing in this
// file (or its call sites) is compiled into Release builds.
//
// Launch arguments (all optional; any `-uiAudit*` argument also skips the intro
// splash and suppresses the first-run tutorial overlay):
//   -uiAuditSeed <absolute path to GymApp backup JSON>
//   -uiAuditRoute <screen_id>            see `UIAuditRoute`
//   -uiAuditLanguage en|ru|uk
// Unknown values are logged once and ignored; the app launches normally.

/// Screen ids understood by `-uiAuditRoute`. Add cases here and handle them in
/// `MainTabShell.applyUIAuditRoute` to expose more screens.
enum UIAuditRoute: String, CaseIterable {
    case today
    case exercises
    case progressOverview = "progress-overview"
    case profile
    case settings
    case workoutDetail = "workout-detail"
    case workoutPlan = "workout-plan"
}

/// Hands the requested route from the launch bootstrap (which runs after the
/// optional seed import) to `MainTabShell`. `@Published` replays the current
/// value on subscription, so the shell may appear before or after it is set.
@MainActor
final class UIAuditRouter: ObservableObject {
    static let shared = UIAuditRouter()
    @Published var route: UIAuditRoute?
    private init() {}
}

enum UIAuditLaunch {
    static let seedFlag = "-uiAuditSeed"
    static let routeFlag = "-uiAuditRoute"
    static let languageFlag = "-uiAuditLanguage"
    static let documentsSeedFileName = "ui-audit-seed.json"
    static let profileName = "UI Audit"
    private static let seedHashKeyPrefix = "ui-audit.seed-sha256."

    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// True when any `-uiAudit*` launch argument is present.
    static var isActive: Bool {
        arguments.contains { $0.hasPrefix("-uiAudit") }
    }

    static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func log(_ message: String) {
        NSLog("[ui-audit] %@", message)
    }

    /// Runs from `GymAppIOS.init()`, before any view reads `@AppStorage`.
    /// The language override lives in the volatile argument domain, so it is
    /// never written to the persisted preferences and applies to this launch only.
    static func applyEarlyOverrides() {
        guard isActive else { return }
        guard arguments.contains(languageFlag) else { return }
        guard let raw = value(for: languageFlag),
              AppLanguage(rawValue: raw) != nil else {
            log("ignoring \(languageFlag): expected en|ru|uk")
            return
        }
        let defaults = UserDefaults.standard
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["app-language"] = raw
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    static func requestedRoute() -> UIAuditRoute? {
        guard arguments.contains(routeFlag) else { return nil }
        guard let raw = value(for: routeFlag), let route = UIAuditRoute(rawValue: raw) else {
            log("ignoring \(routeFlag): unknown screen id; supported: "
                + UIAuditRoute.allCases.map(\.rawValue).joined(separator: ", "))
            return nil
        }
        return route
    }

    static func seedHashKey(storageKey: String) -> String {
        seedHashKeyPrefix + storageKey
    }

    /// Reads the seed through the same bounded reader the Profile import uses.
    /// Falls back to `Documents/ui-audit-seed.json` when the path is unreadable.
    static func readSeed(path: String) -> Data? {
        let limit = BackupImportLimits.standard.maximumFileBytes
        var candidates = [URL(fileURLWithPath: path)]
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(documents.appendingPathComponent(documentsSeedFileName))
        }
        for url in candidates {
            if let data = try? BackupFileReader.read(from: url, maximumBytes: limit) {
                return data
            }
        }
        return nil
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppState {
    /// DEBUG-only: optional seed import into the local "UI Audit" profile, then
    /// publishes the requested route. Never touches a cloud account or Keychain.
    func bootstrapUIAuditIfRequested() async {
        guard UIAuditLaunch.isActive else { return }
        if UIAuditLaunch.arguments.contains(UIAuditLaunch.seedFlag) {
            await seedUIAuditProfile()
        }
        if let route = UIAuditLaunch.requestedRoute() {
            UIAuditRouter.shared.route = route
        }
    }

    private func seedUIAuditProfile() async {
        guard let path = UIAuditLaunch.value(for: UIAuditLaunch.seedFlag) else {
            UIAuditLaunch.log("ignoring \(UIAuditLaunch.seedFlag): missing path")
            return
        }
        guard let data = UIAuditLaunch.readSeed(path: path) else {
            UIAuditLaunch.log("seed unreadable at the given path and in Documents/\(UIAuditLaunch.documentsSeedFileName); launching normally")
            return
        }
        do {
            if auth.session == nil {
                if let saved = auth.savedLocalProfiles.first(where: {
                    $0.displayName == UIAuditLaunch.profileName
                }) {
                    try auth.continueOffline(profileID: saved.id)
                } else {
                    try auth.continueOffline(displayName: UIAuditLaunch.profileName)
                }
            }
            // Only the dedicated local audit profile may be seeded: never a cloud
            // account and never another local profile's data.
            guard let session = auth.session,
                  case .local(_, let name) = session,
                  name == UIAuditLaunch.profileName else {
                UIAuditLaunch.log("active session is not the local \"\(UIAuditLaunch.profileName)\" profile; seed skipped")
                return
            }
            await activate(session)
            guard isAccountReady else {
                UIAuditLaunch.log("account not ready; seed skipped")
                return
            }
            let hash = UIAuditLaunch.sha256Hex(data)
            let hashKey = UIAuditLaunch.seedHashKey(storageKey: session.storageKey)
            if UserDefaults.standard.string(forKey: hashKey) == hash,
               !workoutStore.workouts.isEmpty {
                return
            }
            // Same validation and bounds as Profile > backup > import; replacing
            // makes re-seeding with a regenerated file idempotent.
            _ = try workoutStore.restoreBackup(data: data, activeOwner: backupOwner)
            _ = try? workoutStore.seedBuiltInExercises()
            _ = try? workoutStore.seedDefaultMuscleMappings()
            UserDefaults.standard.set(hash, forKey: hashKey)
        } catch {
            UIAuditLaunch.log("seed import failed: \(gymErrorMessage(error)); launching normally")
        }
    }
}
#endif
