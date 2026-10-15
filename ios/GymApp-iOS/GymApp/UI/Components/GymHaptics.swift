import SwiftUI

/// The one place that decides whether the app plays a haptic. Every
/// `.sensoryFeedback` in the app goes through `gymSensoryFeedback`, so the
/// Settings "Haptics" switch (default on, stored on this device only) gates all
/// of them. System haptics (keyboard, pickers, switches) stay under the OS setting.
enum GymHaptics {
    static let preferenceKey = "app-haptics-enabled"

    /// Defaults to on when the preference was never written.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// `feedback` while haptics are on, otherwise nil (no feedback is played).
    static func resolved(_ feedback: SensoryFeedback, enabled: Bool) -> SensoryFeedback? {
        enabled ? feedback : nil
    }
}

private struct GymSensoryFeedbackModifier<Trigger: Equatable>: ViewModifier {
    @AppStorage(GymHaptics.preferenceKey) private var hapticsEnabled = true

    let feedback: SensoryFeedback
    let trigger: Trigger

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, _ in
            GymHaptics.resolved(feedback, enabled: hapticsEnabled)
        }
    }
}

extension View {
    /// `sensoryFeedback` that respects the in-app Haptics switch.
    func gymSensoryFeedback<Trigger: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: Trigger
    ) -> some View {
        modifier(GymSensoryFeedbackModifier(feedback: feedback, trigger: trigger))
    }
}
