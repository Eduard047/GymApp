import SwiftUI
import UIKit

/// Editing behavior of the active workout's weight field: when it gains focus the whole value is
/// selected, so typing replaces it ("0" then "60" gives "60", not "060"); typed leading zeros are
/// stripped as a safety net. Applies only while `isFocused` is true, so other text fields are untouched.
private struct GymWeightFieldEditing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                // The field becomes first responder after this update; select once it is.
                DispatchQueue.main.async {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { note in
                guard isFocused, let field = note.object as? UITextField, field.isFirstResponder,
                      let text = field.text else { return }
                let normalized = GymNumericInputNormalizer.normalize(text)
                guard normalized != text else { return }
                field.text = normalized
                field.sendActions(for: .editingChanged)
            }
    }
}

extension View {
    /// Selects the weight on focus and strips typed leading zeros while `isFocused`.
    func gymWeightFieldEditing(isFocused: Bool) -> some View {
        modifier(GymWeightFieldEditing(isFocused: isFocused))
    }
}
