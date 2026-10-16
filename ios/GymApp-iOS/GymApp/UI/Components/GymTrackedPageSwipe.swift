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

/// Horizontal-only pan recognizer. It begins only when the first movement is
/// mostly horizontal, so a vertical drag that starts on the content still
/// scrolls the enclosing `ScrollView` (a SwiftUI `DragGesture` would take the
/// touch and block the scroll). Translations are in window space, so the view
/// moving under the finger does not feed back into them.
private struct GymHorizontalPanRecognizer: UIGestureRecognizerRepresentable {
    let onBegan: (_ startX: CGFloat) -> Void
    let onChanged: (_ translationX: CGFloat) -> Void
    let onEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void
    let onCancelled: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y) * GymPageSwipe.axisBias
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: nil).x
        switch recognizer.state {
        case .began:
            onBegan(recognizer.location(in: nil).x - translation)
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: nil).x)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }
}

private struct GymTrackedPageSwipe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var dragX: CGFloat = 0
    @State private var fade: Double = 1
    /// True while a horizontal drag owns the gesture.
    @State private var isDragging = false
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
            .gesture(
                GymHorizontalPanRecognizer(
                    onBegan: began,
                    onChanged: changed,
                    onEnded: ended,
                    onCancelled: cancelled
                )
            )
    }

    private func began(startX: CGFloat) {
        // Never override the system back swipe at the screen edge.
        isDragging = startX >= GymPageSwipe.minimumEdgeInset
        if isDragging, pending != nil { finishPending() }
    }

    private func changed(translationX: CGFloat) {
        guard isDragging, !reduceMotion else { return }
        let displacement = GymPageSwipe.displacement(
            translation: translationX,
            width: width,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        withTransaction(Transaction(animation: nil)) { dragX = displacement }
    }

    private func ended(translationX: CGFloat, velocityX: CGFloat) {
        guard isDragging else { return }
        isDragging = false
        let direction = GymPageSwipe.commitDirection(
            translation: translationX,
            velocity: velocityX,
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

    private func cancelled() {
        guard isDragging else { return }
        isDragging = false
        springBack()
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
