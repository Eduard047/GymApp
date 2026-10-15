import SwiftUI

/// Decision logic of a tracked page swipe (DESIGN.md "Motion"): the content
/// follows the finger 1:1, rubber-bands where there is no further page, and
/// commits on a flick or enough travel. Swiping right goes to the previous
/// (older) page, swiping left to the next one.
enum GymPageSwipe {
    enum Direction: Equatable {
        case previous
        case next
    }

    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    /// Movement before the gesture's axis is decided.
    static let lockSlop: CGFloat = 8
    /// Horizontal movement must exceed vertical by this factor to own the gesture.
    static let axisBias: CGFloat = 1.2
    /// Fraction of the page width that commits on release (sheet dismiss contract).
    static let commitTravelFraction: CGFloat = 0.4
    /// Release speed that commits, in points per second (0.5 pt/ms).
    static let commitVelocity: CGFloat = 500
    /// Rubber-band stiffness (UIScrollView uses 0.55).
    static let rubberBandResistance: CGFloat = 0.55
    /// Custom drags start at least this far from the screen edge, so the system
    /// back swipe is never overridden.
    static let minimumEdgeInset: CGFloat = 16

    static func lockAxis(translation: CGSize) -> Axis? {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard max(dx, dy) >= lockSlop else { return nil }
        return dx > dy * axisBias ? .horizontal : .vertical
    }

    static func direction(forTranslation translation: CGFloat) -> Direction? {
        if translation > 0 { return .previous }
        if translation < 0 { return .next }
        return nil
    }

    /// On-screen offset for a finger translation: 1:1 toward an available page,
    /// damped toward the end of the range.
    static func displacement(
        translation: CGFloat,
        width: CGFloat,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) -> CGFloat {
        guard width > 0, let direction = direction(forTranslation: translation) else { return 0 }
        let available = direction == .previous ? canGoPrevious : canGoNext
        let distance = abs(translation)
        let magnitude: CGFloat
        if available {
            magnitude = min(distance, width)
        } else {
            magnitude = (1 - 1 / (distance * rubberBandResistance / width + 1)) * width
        }
        return translation < 0 ? -magnitude : magnitude
    }

    /// The page change a release commits, or nil to spring back.
    static func commitDirection(
        translation: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) -> Direction? {
        guard width > 0, let direction = direction(forTranslation: translation) else { return nil }
        guard direction == .previous ? canGoPrevious : canGoNext else { return nil }
        let flickedWithDrag = abs(velocity) >= commitVelocity && (velocity > 0) == (translation > 0)
        let flickedAgainstDrag = abs(velocity) >= commitVelocity && !flickedWithDrag
        if flickedAgainstDrag { return nil }
        let traveled = abs(translation) / width >= commitTravelFraction
        return (traveled || flickedWithDrag) ? direction : nil
    }
}

private struct GymTrackedPageSwipe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isTracking = false
    @State private var width: CGFloat = 0
    @State private var dragX: CGFloat = 0
    @State private var fade: Double = 1
    @State private var axis: GymPageSwipe.Axis?
    /// A committed page change waiting for its exit animation to finish.
    @State private var pending: GymPageSwipe.Direction?

    let canGoPrevious: Bool
    let canGoNext: Bool
    let onCommit: (GymPageSwipe.Direction) -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .offset(x: dragX)
            .opacity(fade * (1 - 0.3 * min(1, abs(dragX) / max(width, 1))))
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .updating($isTracking) { _, state, _ in state = true }
                    .onChanged(changed)
                    .onEnded(ended)
            )
            .onChange(of: isTracking) { _, tracking in
                guard !tracking else { return }
                // A cancelled gesture never reports its end; let a normal end run first.
                Task { @MainActor in
                    guard axis == .horizontal else { return }
                    axis = nil
                    springBack()
                }
            }
    }

    private func changed(_ value: DragGesture.Value) {
        if axis == nil {
            guard let locked = GymPageSwipe.lockAxis(translation: value.translation) else { return }
            axis = value.startLocation.x < GymPageSwipe.minimumEdgeInset ? .vertical : locked
        }
        guard axis == .horizontal else { return }
        if pending != nil { finishPending() }
        guard !reduceMotion else { return }
        let displacement = GymPageSwipe.displacement(
            translation: value.translation.width,
            width: width,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        withTransaction(Transaction(animation: nil)) { dragX = displacement }
    }

    private func ended(_ value: DragGesture.Value) {
        let wasHorizontal = axis == .horizontal
        axis = nil
        guard wasHorizontal else { return }
        let direction = GymPageSwipe.commitDirection(
            translation: value.translation.width,
            velocity: value.velocity.width,
            width: width,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        guard let direction else {
            springBack()
            return
        }
        pending = direction
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.09)) { fade = 0 } completion: { finishPending() }
        } else {
            let exit = direction == .previous ? width : -width
            withAnimation(GymMotion.quick) { dragX = exit } completion: { finishPending() }
        }
    }

    private func springBack() {
        withAnimation(reduceMotion ? GymMotion.fade : GymMotion.momentum) { dragX = 0 }
    }

    /// Swaps the page and brings the new one in from the opposite side (or fades
    /// it in under Reduce Motion). Safe to call twice: only the first one acts.
    private func finishPending() {
        guard let direction = pending else { return }
        pending = nil
        withTransaction(Transaction(animation: nil)) {
            onCommit(direction)
            if !reduceMotion { dragX = direction == .previous ? -width : width }
        }
        withAnimation(reduceMotion ? GymMotion.fade : GymMotion.standard) {
            dragX = 0
            fade = 1
        }
    }
}

extension View {
    /// Makes this content swipeable between pages: it follows the finger,
    /// rubber-bands past the ends, and `onCommit` changes the page when a
    /// release commits. Reduce Motion replaces the slide with a cross-fade.
    /// Keep a button for each direction as the accessible alternative.
    func gymTrackedPageSwipe(
        canGoPrevious: Bool,
        canGoNext: Bool,
        onCommit: @escaping (GymPageSwipe.Direction) -> Void
    ) -> some View {
        modifier(GymTrackedPageSwipe(
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext,
            onCommit: onCommit
        ))
    }
}
