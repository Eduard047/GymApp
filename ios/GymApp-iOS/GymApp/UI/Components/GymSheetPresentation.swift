import SwiftUI

/// Size policy for a bottom sheet (DESIGN.md "Components > Sheets").
enum GymSheetSize: Equatable {
    /// Opens at the medium detent and can be pulled to large (default).
    case standard
    /// Long forms and pickers with text input: large only.
    case full
    /// Short info or confirm sheets: medium only.
    case compact
    /// Short sheets that size to a known content height.
    case height(CGFloat)

    var detents: Set<PresentationDetent> {
        switch self {
        case .standard: [.medium, .large]
        case .full: [.large]
        case .compact: [.medium]
        case let .height(value): [.height(value)]
        }
    }
}

enum GymSheetStyle {
    /// `radii.sheet-top` in DESIGN.md (matches the iOS system detent radius).
    static let topCornerRadius: CGFloat = 32
}

private struct GymSheetPresentationModifier: ViewModifier {
    let size: GymSheetSize

    func body(content: Content) -> some View {
        content
            .presentationDetents(size.detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(GymSheetStyle.topCornerRadius)
    }
}

extension View {
    /// Applies the shared bottom-sheet contract to the root of a sheet's content:
    /// detents, visible drag handle and 32pt top radius. The background stays the
    /// system sheet material (DESIGN.md: system sheets keep their own), which
    /// already honours Reduce Transparency. Alerts and confirmation dialogs are
    /// not sheets and do not use this.
    func gymSheetPresentation(_ size: GymSheetSize = .standard) -> some View {
        modifier(GymSheetPresentationModifier(size: size))
    }
}
