#if DEBUG
import Foundation
import os

/// DEBUG-only launch seed (`-AWDebugSeed <name>`) for screenshots and paired-simulator
/// checks, and a debug log line. This file and every call site sit inside `#if DEBUG`,
/// so nothing of it is compiled into Release.
enum WatchDebugSeed {
    static var screen: String? { UserDefaults.standard.string(forKey: "AWDebugSeed") }

    static func isScreen(_ names: String...) -> Bool {
        guard let screen else { return false }
        return names.contains(screen)
    }

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    private static let logger = Logger(subsystem: "com.setforge.gymapp.ios.watchkitapp", category: "debug")
}
#endif
