import Observation
import SwiftUI
import UIKit

// MARK: - Pure model

/// Durations and gesture thresholds for the persistent toast (DESIGN.md
/// "Components > Toasts and banners"): 4 s, 6 s with an action.
enum GymToastPolicy {
    static let plainDuration: TimeInterval = 4
    static let actionDuration: TimeInterval = 6
    /// Errors carry more to read than a confirmation, so they get the long duration.
    static let errorDuration: TimeInterval = 6
    static let maxWidth: CGFloat = 560
    /// Slide distance of the enter/exit motion.
    static let slideDistance: CGFloat = 14
    /// Drag distance (down or sideways) after which a release dismisses.
    static let dismissDistance: CGFloat = 36
    /// Predicted-end distance (a flick) after which a release dismisses.
    static let dismissPredictedDistance: CGFloat = 90

    static func duration(hasAction: Bool, isError: Bool) -> TimeInterval {
        if hasAction { return actionDuration }
        return isError ? errorDuration : plainDuration
    }
}

struct GymToast: Identifiable {
    enum Kind: Equatable {
        case info
        case error
    }

    struct Action {
        let title: String
        let perform: @MainActor () -> Void
    }

    let id: UUID
    let message: String
    let kind: Kind
    let action: Action?
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        message: String,
        kind: Kind = .info,
        action: Action? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.kind = kind
        self.action = action
        self.duration = duration
            ?? GymToastPolicy.duration(hasAction: action != nil, isError: kind == .error)
    }
}

/// Why the countdown is held. Any active reason pauses it.
enum GymToastPauseReason: Hashable {
    /// A finger is on the toast (press or drag).
    case interaction
    /// VoiceOver / Switch Control focus is on the toast.
    case assistiveFocus
}

/// Countdown that survives pauses, driven by explicit timestamps so it is
/// deterministic to test.
struct GymToastCountdown: Equatable {
    private(set) var remaining: TimeInterval
    private(set) var runningSince: Date?

    init(duration: TimeInterval, startedAt now: Date) {
        remaining = max(0, duration)
        runningSince = now
    }

    var isPaused: Bool { runningSince == nil }

    func remaining(at now: Date) -> TimeInterval {
        guard let runningSince else { return remaining }
        return max(0, remaining - now.timeIntervalSince(runningSince))
    }

    func isExpired(at now: Date) -> Bool { remaining(at: now) <= 0 }

    mutating func pause(at now: Date) {
        guard runningSince != nil else { return }
        remaining = remaining(at: now)
        runningSince = nil
    }

    mutating func resume(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }
}

/// One toast at a time: a new toast replaces the current one, never stacks.
struct GymToastQueue {
    private(set) var current: GymToast?
    private(set) var countdown: GymToastCountdown?
    private(set) var pauseReasons: Set<GymToastPauseReason> = []

    /// Shows `toast`, replacing the current one. Returns the replaced toast's id.
    @discardableResult
    mutating func show(_ toast: GymToast, at now: Date) -> UUID? {
        let replaced = current?.id
        current = toast
        pauseReasons = []
        countdown = GymToastCountdown(duration: toast.duration, startedAt: now)
        return replaced
    }

    /// Dismisses the toast with `id` (or whichever is showing when `id` is nil).
    /// A stale id never dismisses a newer toast.
    @discardableResult
    mutating func dismiss(id: UUID? = nil) -> Bool {
        guard let current, id == nil || id == current.id else { return false }
        self.current = nil
        countdown = nil
        pauseReasons = []
        return true
    }

    mutating func setPaused(_ reason: GymToastPauseReason, active: Bool, at now: Date) {
        guard current != nil else { return }
        if active { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        if pauseReasons.isEmpty {
            countdown?.resume(at: now)
        } else {
            countdown?.pause(at: now)
        }
    }

    var isPaused: Bool { !pauseReasons.isEmpty }

    /// Seconds until the current toast times out; nil when nothing is showing
    /// or the countdown is paused.
    func timeUntilExpiry(at now: Date) -> TimeInterval? {
        guard let countdown, !countdown.isPaused else { return nil }
        return countdown.remaining(at: now)
    }

    /// Removes the current toast when its countdown has run out. Returns whether it did.
    @discardableResult
    mutating func expireIfDue(at now: Date) -> Bool {
        guard let countdown, !countdown.isPaused, countdown.isExpired(at: now) else { return false }
        return dismiss()
    }
}

/// Which toast host draws the toast. The root host sits above the tab bar; a
/// sheet or full-screen cover is a separate presentation that covers it, so
/// each carries its own host and the topmost one wins.
enum GymToastHostID: Hashable {
    case root
    case presentation(UUID)
}

struct GymToastHostStack {
    private(set) var hosts: [GymToastHostID] = []

    /// The host that should draw the toast: the most recently registered one.
    var activeHost: GymToastHostID? { hosts.last }

    mutating func register(_ host: GymToastHostID) {
        hosts.removeAll { $0 == host }
        hosts.append(host)
    }

    mutating func unregister(_ host: GymToastHostID) {
        hosts.removeAll { $0 == host }
    }
}

// MARK: - Center

/// App-level controller for the persistent toast. Owned by `AppState` and injected
/// into the environment at the app root (`GymAppIOS`).
@MainActor
@Observable
final class GymToastCenter {
    private(set) var current: GymToast?
    private(set) var activeHost: GymToastHostID?

    @ObservationIgnored private var queue = GymToastQueue()
    @ObservationIgnored private var hostStack = GymToastHostStack()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let announcer: (String) -> Void

    init(
        clock: @escaping () -> Date = Date.init,
        announcer: @escaping (String) -> Void = GymToastCenter.postAnnouncement
    ) {
        self.clock = clock
        self.announcer = announcer
    }

    /// Shows a one-line message, replacing any toast already on screen.
    /// `message` may be an English catalog key; it is localized for display and
    /// for the VoiceOver announcement.
    func show(
        _ message: String,
        kind: GymToast.Kind = .info,
        action: GymToast.Action? = nil,
        duration: TimeInterval? = nil
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let toast = GymToast(message: trimmed, kind: kind, action: action, duration: duration)
        queue.show(toast, at: clock())
        sync()
        announcer(gymLocalized(trimmed))
    }

    func dismiss(id: UUID? = nil) {
        guard queue.dismiss(id: id) else { return }
        sync()
    }

    /// Runs the action, then dismisses the toast.
    func performAction(of toast: GymToast) {
        guard current?.id == toast.id else { return }
        toast.action?.perform()
        dismiss(id: toast.id)
    }

    func setPaused(_ reason: GymToastPauseReason, active: Bool, for id: UUID) {
        guard current?.id == id else { return }
        queue.setPaused(reason, active: active, at: clock())
        sync()
    }

    func registerHost(_ host: GymToastHostID) {
        hostStack.register(host)
        activeHost = hostStack.activeHost
    }

    func unregisterHost(_ host: GymToastHostID) {
        hostStack.unregister(host)
        activeHost = hostStack.activeHost
    }

    private func sync() {
        current = queue.current
        timer?.cancel()
        timer = nil
        guard let id = queue.current?.id,
              let delay = queue.timeUntilExpiry(at: clock()) else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            self.expireCurrent()
        }
    }

    /// Removes the toast when due; if the timer woke slightly early, `sync()`
    /// re-arms it for the remainder.
    private func expireCurrent() {
        queue.expireIfDue(at: clock())
        sync()
    }

    nonisolated static func postAnnouncement(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

// MARK: - Layout helpers

/// Bottom safe-area inset of a tab's content, which already excludes the tab bar.
/// The root host compares it with its own inset to sit just above the tab bar.
struct GymToastContentInsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Reports this content's bottom safe-area inset (tab bar included) so the root
    /// toast host can sit above the tab bar.
    func gymToastReportsBottomInset() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GymToastContentInsetKey.self,
                    value: proxy.safeAreaInsets.bottom
                )
            }
        }
    }
}

// MARK: - Host view

/// Draws the current toast when this host is the active one. Mount exactly one
/// `.root` host at the app root; sheets and covers get theirs from
/// `gymSheetPresentation` / `gymToastHost()`.
struct GymToastHost: View {
    @Environment(GymToastCenter.self) private var center: GymToastCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hostID: GymToastHostID
    /// Bottom safe-area inset of the content this host floats over (root host only).
    var contentBottomInset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let extra = max(0, contentBottomInset - proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottom) {
                if let center, center.activeHost == hostID, let toast = center.current {
                    GymToastChip(toast: toast, center: center)
                        .id(toast.id)
                        .frame(maxWidth: GymToastPolicy.maxWidth)
                        .padding(.horizontal, GymTheme.screenHorizontalInset)
                        .padding(.bottom, 8 + extra)
                        .transition(transition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(animation, value: center?.current?.id)
        }
        .onAppear { center?.registerHost(hostID) }
        .onDisappear { center?.unregisterHost(hostID) }
    }

    private var isShowing: Bool { center?.current != nil }

    /// Enter: spring-standard slide + fade. Exit: ~80% of the enter time, 90 ms fade.
    private var animation: Animation {
        if isShowing {
            return GymMotion.animation(reduceMotion: reduceMotion)
        }
        return .easeOut(duration: 0.09)
    }

    private var transition: AnyTransition {
        GymMotion.transition(
            .offset(y: GymToastPolicy.slideDistance).combined(with: .opacity),
            reduceMotion: reduceMotion
        )
    }
}

private struct GymToastChip: View {
    let toast: GymToast
    let center: GymToastCenter

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var voiceOverFocused: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        let message = gymLocalized(toast.message, locale: locale)
        HStack(spacing: 0) {
            Button {
                center.dismiss(id: toast.id)
            } label: {
                HStack(spacing: 8) {
                    if toast.kind == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(GymTheme.error)
                            .accessibilityHidden(true)
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 16)
                .padding(.trailing, toast.action == nil ? 16 : 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                toast.kind == .error
                    ? "\(gymLocalized("Error", locale: locale)): \(message)"
                    : message
            )
            .accessibilityHint(gymLocalized("Double tap to dismiss", locale: locale))
            .accessibilityFocused($voiceOverFocused)

            if let action = toast.action {
                Button {
                    center.performAction(of: toast)
                } label: {
                    Text(gymLocalized(action.title, locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.primary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        .background { chipBackground }
        .overlay { chipEdge }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 4)
        .offset(dragOffset)
        .opacity(dragOpacity)
        .simultaneousGesture(dragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { center.dismiss(id: toast.id) }
        .onChange(of: voiceOverFocused) { _, focused in
            center.setPaused(.assistiveFocus, active: focused, for: toast.id)
        }
    }

    /// `chip` material: system material, or solid `surface` with Reduce Transparency.
    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule().fill(GymTheme.surface)
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    private var chipEdge: some View {
        Capsule().strokeBorder(
            contrast == .increased ? GymTheme.outline : GymTheme.outlineSoft,
            lineWidth: contrast == .increased ? 1.5 : GymTheme.hairlineWidth
        )
    }

    private var dragOpacity: Double {
        guard isDragging else { return 1 }
        let travel = max(abs(dragOffset.width), max(dragOffset.height, 0))
        return max(0.4, 1 - Double(travel / 240))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    center.setPaused(.interaction, active: true, for: toast.id)
                }
                // Tracks the finger down and sideways; upward drags resist.
                let up = min(value.translation.height, 0)
                let y = value.translation.height > 0 ? value.translation.height : up / 6
                dragOffset = CGSize(width: value.translation.width, height: y)
            }
            .onEnded { value in
                isDragging = false
                let down = value.translation.height
                let side = abs(value.translation.width)
                let predictedDown = value.predictedEndTranslation.height
                let predictedSide = abs(value.predictedEndTranslation.width)
                let dismisses = down > GymToastPolicy.dismissDistance
                    || side > GymToastPolicy.dismissDistance
                    || predictedDown > GymToastPolicy.dismissPredictedDistance
                    || predictedSide > GymToastPolicy.dismissPredictedDistance
                if dismisses {
                    center.dismiss(id: toast.id)
                } else {
                    withAnimation(GymMotion.animation(reduceMotion: reduceMotion)) {
                        dragOffset = .zero
                    }
                    center.setPaused(.interaction, active: false, for: toast.id)
                }
            }
    }
}

// MARK: - Presentation attachment

private struct GymToastPresentationHost: ViewModifier {
    @State private var hostID = GymToastHostID.presentation(UUID())

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            GymToastHost(hostID: hostID)
        }
    }
}

extension View {
    /// Attaches a toast host inside a separate presentation (sheet or full-screen
    /// cover). A root overlay cannot draw above a presented sheet, so the topmost
    /// presentation's host draws the toast instead and the root host steps aside.
    /// `gymSheetPresentation` applies this to every sheet.
    func gymToastHost() -> some View {
        modifier(GymToastPresentationHost())
    }
}
