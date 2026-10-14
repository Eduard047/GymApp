import Observation
import SwiftUI
import UIKit

// MARK: - Tokens

/// Drag-to-reorder tokens shared by the plan editor and the active workout
/// (cross-client contract: scale 1.02, snappy neighbours, momentum drop).
enum GymReorderMotion {
    /// Neighbours part to open the slot: damping 1.0, response 0.20.
    static let slot: Animation = .spring(response: 0.20, dampingFraction: 1.0)
    /// The dragged card settles into its slot: damping 0.8, response 0.35.
    static let drop: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let liftScale: CGFloat = 1.02
    static let handleSize: CGFloat = 44
    static let minimumDragDistance: CGFloat = 3
    /// Custom drags never start closer to the screen edge (system back gesture).
    static let screenEdgeInset: CGFloat = 16
    static let autoScrollZone: CGFloat = 64
    /// Points per frame at 60 fps at full depth.
    static let autoScrollMaxStep: CGFloat = 12
    static let slotTickMinInterval: TimeInterval = 0.1
    static let fallbackHeight: CGFloat = 120
}

// MARK: - Geometry (pure)

enum GymReorderGeometry {
    /// Slot the dragged card occupies once its centre has moved `offset` points
    /// from where it started: the slot changes when the centre crosses a
    /// neighbour's midpoint (neighbours measured in the undisturbed layout).
    static func slotIndex(
        origin: Int,
        offset: CGFloat,
        heights: [CGFloat],
        spacing: CGFloat
    ) -> Int {
        guard heights.indices.contains(origin) else { return origin }
        var slot = origin
        var threshold = heights[origin] / 2 + spacing
        if offset > 0 {
            var index = origin + 1
            while index < heights.count {
                if offset > threshold + heights[index] / 2 {
                    slot = index
                    threshold += heights[index] + spacing
                    index += 1
                } else {
                    break
                }
            }
        } else if offset < 0 {
            var index = origin - 1
            while index >= 0 {
                if -offset > threshold + heights[index] / 2 {
                    slot = index
                    threshold += heights[index] + spacing
                    index -= 1
                } else {
                    break
                }
            }
        }
        return slot
    }

    /// How far the dragged card's layout position moves when it is re-inserted
    /// at `target` (positive = down). Used to keep the card visually in place
    /// when the data reorders, before it springs into the slot.
    static func layoutDelta(
        origin: Int,
        target: Int,
        heights: [CGFloat],
        spacing: CGFloat
    ) -> CGFloat {
        guard origin != target, heights.indices.contains(origin), heights.indices.contains(target) else {
            return 0
        }
        if target > origin {
            return (origin + 1...target).reduce(0) { $0 + heights[$1] + spacing }
        }
        return -(target..<origin).reduce(0) { $0 + heights[$1] + spacing }
    }

    /// Vertical shift of a non-dragged card while the slot is open: cards the
    /// dragged card has passed move out of its way by its height plus spacing.
    static func neighbourShift(
        index: Int,
        origin: Int,
        slot: Int,
        draggedExtent: CGFloat
    ) -> CGFloat {
        if slot > origin, index > origin, index <= slot { return -draggedExtent }
        if slot < origin, index < origin, index >= slot { return draggedExtent }
        return 0
    }

    /// Scroll step per 60 fps frame for a finger at `fingerY`: negative scrolls
    /// up, positive down, proportional to how deep the finger is inside the
    /// edge zone, capped at `autoScrollMaxStep`.
    static func autoScrollStep(
        fingerY: CGFloat,
        visibleTop: CGFloat,
        visibleBottom: CGFloat,
        zone: CGFloat = GymReorderMotion.autoScrollZone,
        maxStep: CGFloat = GymReorderMotion.autoScrollMaxStep
    ) -> CGFloat {
        guard zone > 0 else { return 0 }
        if fingerY < visibleTop + zone {
            return -maxStep * min(1, (visibleTop + zone - fingerY) / zone)
        }
        if fingerY > visibleBottom - zone {
            return maxStep * min(1, (fingerY - (visibleBottom - zone)) / zone)
        }
        return 0
    }
}

// MARK: - Coordinator

/// State of one reorderable exercise list. Owned by the screen as `@State`
/// (reference type, so the screen's body does not re-render per drag frame);
/// only the card modifiers and the container read the observed properties.
///
/// The data is never touched while dragging: the card follows the finger,
/// neighbours part visually, and exactly one `onMove` write happens on drop.
@MainActor
@Observable
final class GymReorderCoordinator {
    enum Phase { case idle, dragging, settling }

    private(set) var phase: Phase = .idle
    private(set) var activeID: UUID?
    private(set) var slotIndex = 0
    private(set) var originIndex = 0
    /// Vertical displacement of the dragged card from its layout position.
    private(set) var dragOffset: CGFloat = 0
    private(set) var order: [UUID] = []
    private(set) var pickupTick = 0
    private(set) var slotTick = 0

    @ObservationIgnored let spacing: CGFloat
    @ObservationIgnored var heights: [UUID: CGFloat] = [:]
    @ObservationIgnored var ids: [UUID] = []
    @ObservationIgnored var isEnabled = false
    @ObservationIgnored var reduceMotion = false
    /// Persists the move (`id`, `from`, `to` as indices into `ids`); false = refused.
    @ObservationIgnored var onMove: ((UUID, Int, Int) -> Bool)?

    @ObservationIgnored private var anchors: [UUID: WeakView] = [:]
    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private var startOffsetY: CGFloat = 0
    @ObservationIgnored private var translationY: CGFloat = 0
    @ObservationIgnored private var fingerY: CGFloat = 0
    @ObservationIgnored private var lastSlotTick: CFTimeInterval = 0
    @ObservationIgnored private var settleGeneration = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var displayLinkTarget: DisplayLinkTarget?

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    var isDragging: Bool { phase == .dragging }

    func registerAnchor(_ view: UIView, for id: UUID) {
        anchors[id] = WeakView(view)
    }

    /// Shift applied to a non-dragged card (0 for the dragged card and when idle).
    func neighbourShift(for id: UUID) -> CGFloat {
        guard phase != .idle, let activeID, id != activeID,
              let index = order.firstIndex(of: id) else { return 0 }
        return GymReorderGeometry.neighbourShift(
            index: index,
            origin: originIndex,
            slot: slotIndex,
            draggedExtent: height(of: activeID) + spacing
        )
    }

    // MARK: Gesture lifecycle

    @discardableResult
    func begin(id: UUID) -> Bool {
        guard phase == .idle, isEnabled, ids.count >= 2,
              let index = ids.firstIndex(of: id) else { return false }
        order = ids
        originIndex = index
        slotIndex = index
        activeID = id
        dragOffset = 0
        translationY = 0
        fingerY = 0
        scrollView = anchors[id]?.view.flatMap(Self.enclosingScrollView)
        startOffsetY = scrollView?.contentOffset.y ?? 0
        lastSlotTick = 0
        settleGeneration &+= 1
        phase = .dragging
        pickupTick &+= 1
        startAutoScroll()
        return true
    }

    func update(translationY: CGFloat, fingerY: CGFloat) {
        guard phase == .dragging else { return }
        self.translationY = translationY
        self.fingerY = fingerY
        recompute()
    }

    /// Finger lifted: persist the move once (unless dropped at the origin) and
    /// settle the card into its slot.
    func end() {
        guard phase == .dragging, let id = activeID else { return }
        stopAutoScroll()
        let from = originIndex
        let to = slotIndex
        guard from != to else {
            settle()
            return
        }
        let delta = GymReorderGeometry.layoutDelta(
            origin: from, target: to, heights: orderedHeights(), spacing: spacing
        )
        var committed = false
        // The data reorders and the layout jumps in one frame; compensate the
        // offsets so nothing visibly moves, then spring the card home.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committed = onMove?(id, from, to) ?? false
            if committed {
                dragOffset -= delta
                slotIndex = originIndex
            }
        }
        settle()
    }

    /// Pointer cancel, lost capture, backgrounding, changed data, live freeze:
    /// snap back without writing anything.
    func cancel() {
        guard phase == .dragging else { return }
        stopAutoScroll()
        settle()
    }

    func gestureTerminated(for id: UUID) {
        if activeID == id, phase == .dragging { cancel() }
    }

    // MARK: Internals

    private func settle() {
        settleGeneration &+= 1
        let generation = settleGeneration
        if reduceMotion {
            dragOffset = 0
            slotIndex = originIndex
            finishSettle(generation)
            return
        }
        withAnimation(GymReorderMotion.drop, completionCriteria: .logicallyComplete) {
            phase = .settling
            dragOffset = 0
            slotIndex = originIndex
        } completion: { [weak self] in
            self?.finishSettle(generation)
        }
        // Safety net if the completion never fires.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.finishSettle(generation)
        }
    }

    private func finishSettle(_ generation: Int) {
        guard generation == settleGeneration, phase != .idle else { return }
        phase = .idle
        activeID = nil
        order = []
    }

    private func height(of id: UUID) -> CGFloat {
        if let known = heights[id] { return known }
        let measured = heights.values
        guard !measured.isEmpty else { return GymReorderMotion.fallbackHeight }
        return measured.reduce(0, +) / CGFloat(measured.count)
    }

    private func orderedHeights() -> [CGFloat] {
        order.map { height(of: $0) }
    }

    private func recompute() {
        guard phase == .dragging else { return }
        let heights = orderedHeights()
        let scrollDelta = (scrollView?.contentOffset.y ?? startOffsetY) - startOffsetY
        let above = (0..<originIndex).reduce(CGFloat(0)) { $0 + heights[$1] + spacing }
        let below = ((originIndex + 1)..<heights.count).reduce(CGFloat(0)) { $0 + heights[$1] + spacing }
        dragOffset = min(max(translationY + scrollDelta, -above), below)
        let newSlot = GymReorderGeometry.slotIndex(
            origin: originIndex, offset: dragOffset, heights: heights, spacing: spacing
        )
        if newSlot != slotIndex {
            slotIndex = newSlot
            let now = CACurrentMediaTime()
            if now - lastSlotTick >= GymReorderMotion.slotTickMinInterval {
                lastSlotTick = now
                slotTick &+= 1
            }
        }
    }

    // MARK: Auto-scroll

    private func startAutoScroll() {
        guard scrollView != nil, displayLink == nil else { return }
        let target = DisplayLinkTarget { [weak self] link in
            self?.autoScrollTick(frameDuration: link.targetTimestamp - link.timestamp)
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLinkTarget = target
        displayLink = link
    }

    private func stopAutoScroll() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }

    private func autoScrollTick(frameDuration: CFTimeInterval) {
        guard phase == .dragging, let scrollView else { return }
        let frame = scrollView.convert(scrollView.bounds, to: nil)
        let insets = scrollView.adjustedContentInset
        let step = GymReorderGeometry.autoScrollStep(
            fingerY: fingerY,
            visibleTop: frame.minY + insets.top,
            visibleBottom: frame.maxY - insets.bottom
        ) * CGFloat(max(frameDuration, 1.0 / 120.0) * 60)
        guard step != 0 else { return }
        let minimumY = -insets.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height - scrollView.bounds.height + insets.bottom
        )
        let newY = min(max(scrollView.contentOffset.y + step, minimumY), maximumY)
        guard newY != scrollView.contentOffset.y else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newY), animated: false)
        recompute()
    }

    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var candidate: UIView? = view.superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView { return scrollView }
            candidate = current.superview
        }
        return nil
    }
}

private final class WeakView {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
}

private final class DisplayLinkTarget: NSObject {
    private let handler: (CADisplayLink) -> Void
    init(handler: @escaping (CADisplayLink) -> Void) { self.handler = handler }
    @objc func tick(_ link: CADisplayLink) { handler(link) }
}

// MARK: - Views

/// Identifies one card to the coordinator so the card header can show the handle.
struct GymReorderHandleSource {
    let coordinator: GymReorderCoordinator
    let id: UUID
}

/// Grip handle at the leading edge of an exercise header. Pressing it and moving
/// starts the drag at once; the rest of the card keeps scrolling. Not a screen
/// reader stop: VoiceOver uses the Move up / Move down actions.
struct GymExerciseDragHandle: View {
    let source: GymReorderHandleSource
    @GestureState private var isTracking = false
    @State private var didBegin = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .frame(width: GymReorderMotion.handleSize, height: GymReorderMotion.handleSize)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
            .gesture(dragGesture)
            .onChange(of: isTracking) { _, tracking in
                guard !tracking else { return }
                didBegin = false
                // A gesture that ends without `onEnded` was cancelled.
                source.coordinator.gestureTerminated(for: source.id)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: GymReorderMotion.minimumDragDistance, coordinateSpace: .global)
            .updating($isTracking) { _, state, _ in state = true }
            .onChanged { value in
                if !didBegin {
                    guard value.startLocation.x >= GymReorderMotion.screenEdgeInset,
                          source.coordinator.begin(id: source.id) else { return }
                    didBegin = true
                }
                source.coordinator.update(
                    translationY: value.translation.height,
                    fingerY: value.location.y
                )
            }
            .onEnded { value in
                if didBegin {
                    source.coordinator.update(
                        translationY: value.translation.height,
                        fingerY: value.location.y
                    )
                    source.coordinator.end()
                }
                didBegin = false
            }
    }
}

private struct GymReorderAnchor: UIViewRepresentable {
    let coordinator: GymReorderCoordinator
    let id: UUID

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        coordinator.registerAnchor(view, for: id)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        coordinator.registerAnchor(uiView, for: id)
    }
}

private struct GymReorderItemModifier: ViewModifier {
    let coordinator: GymReorderCoordinator
    let id: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isActive = coordinator.activeID == id
        let lifted = isActive && coordinator.phase == .dragging
        let shift = coordinator.neighbourShift(for: id)
        let followOffset = isActive ? coordinator.dragOffset : 0
        let shadowColor = colorScheme == .dark
            ? Color.black.opacity(0.40)
            : Color(red: 16 / 255, green: 35 / 255, blue: 63 / 255).opacity(0.16)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                coordinator.heights[id] = height
            }
            .background(GymReorderAnchor(coordinator: coordinator, id: id))
            .scaleEffect(lifted && !reduceMotion ? GymReorderMotion.liftScale : 1)
            .shadow(
                color: lifted ? shadowColor : .clear,
                radius: lifted ? 10 : 0,
                x: 0,
                y: lifted ? 8 : 0
            )
            .animation(
                reduceMotion ? nil : (lifted ? GymReorderMotion.slot : GymReorderMotion.drop),
                value: lifted
            )
            // The dragged card follows the finger 1:1 (no implicit animation on
            // `followOffset`); neighbours spring to their shift.
            .offset(y: followOffset + shift)
            .animation(reduceMotion ? nil : GymReorderMotion.slot, value: shift)
            .zIndex(isActive ? 1 : 0)
    }
}

private struct GymReorderContainerModifier: ViewModifier {
    let coordinator: GymReorderCoordinator
    let ids: [UUID]
    let isEnabled: Bool
    let revision: UInt64
    let onMove: (UUID, Int, Int) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scrollDisabled(coordinator.isDragging)
            .onChange(of: ids, initial: true) { _, newIDs in
                // Anything that reorders the list under a live drag cancels it
                // (our own commit has already moved to `.settling`).
                coordinator.cancel()
                coordinator.ids = newIDs
                coordinator.onMove = onMove
            }
            .onChange(of: isEnabled, initial: true) { _, enabled in
                coordinator.isEnabled = enabled
                if !enabled { coordinator.cancel() }
            }
            .onChange(of: revision) { _, _ in coordinator.cancel() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { coordinator.cancel() }
            }
            .onChange(of: reduceMotion, initial: true) { _, value in
                coordinator.reduceMotion = value
            }
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: coordinator.pickupTick)
            .sensoryFeedback(.selection, trigger: coordinator.slotTick)
    }
}

extension View {
    /// Apply to the `ScrollView` that holds the reorderable cards. `ids` is the
    /// visible order; `onMove` persists a move (indices into `ids`) and returns
    /// false when it was refused. `revision` cancels a drag when the data changes.
    func gymExerciseReorderContainer(
        _ coordinator: GymReorderCoordinator,
        ids: [UUID],
        isEnabled: Bool,
        revision: UInt64 = 0,
        onMove: @escaping (UUID, Int, Int) -> Bool
    ) -> some View {
        modifier(GymReorderContainerModifier(
            coordinator: coordinator,
            ids: ids,
            isEnabled: isEnabled,
            revision: revision,
            onMove: onMove
        ))
    }

    /// Apply to each reorderable card: lift, follow, part and drop animation.
    func gymReorderable(_ coordinator: GymReorderCoordinator, id: UUID) -> some View {
        modifier(GymReorderItemModifier(coordinator: coordinator, id: id))
    }
}
