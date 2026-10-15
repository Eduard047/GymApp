import SwiftUI

/// App-owned glass layers (`Materials (glass)` in DESIGN.md). Each role names the
/// solid colour it falls back to when Reduce Transparency is on, so layout never
/// depends on the blur.
enum GymGlassRole {
    /// Full-width bars docked to a screen edge: solid `background` + hairline.
    case bar
    /// Sheet-like panels: solid `surface`.
    case sheet
    /// Floating pills: solid `surface`.
    case chip
    /// Full-screen blur that blocks the content behind it: solid `background`.
    case scrim

    var solidFill: Color {
        switch self {
        case .bar, .scrim: GymTheme.background
        case .sheet, .chip: GymTheme.surface
        }
    }
}

private struct GymGlassBackgroundModifier: ViewModifier {
    let role: GymGlassRole
    let material: Material
    let edge: VerticalEdge?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if edge != nil {
                    Rectangle()
                        .fill(contrast == .increased ? GymTheme.outline : GymTheme.outlineSoft)
                        .frame(height: contrast == .increased ? 1.5 : GymTheme.hairlineWidth)
                        .accessibilityHidden(true)
                }
            }
    }

    private var fill: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(role.solidFill) : AnyShapeStyle(material)
    }
}

extension View {
    /// Draws `material` behind the view, or the role's solid colour when Reduce
    /// Transparency is on. `edge` adds the 1 px hairline on the side facing content.
    /// Never place one glass layer on top of another.
    func gymGlassBackground(
        _ role: GymGlassRole,
        material: Material,
        edge: VerticalEdge? = nil
    ) -> some View {
        modifier(GymGlassBackgroundModifier(role: role, material: material, edge: edge))
    }
}
