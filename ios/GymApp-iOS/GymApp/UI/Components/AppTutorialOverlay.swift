import SwiftUI
import UIKit

enum AppTutorialTarget: String, Hashable, Sendable {
    case todayFocus
    case todayPrimaryAction
    case exercises
    case progress
    case profile
}

private struct AppTutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [AppTutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AppTutorialTarget: Anchor<CGRect>],
        nextValue: () -> [AppTutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AppTutorialCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func appTutorialTarget(_ target: AppTutorialTarget) -> some View {
        anchorPreference(
            key: AppTutorialTargetPreferenceKey.self,
            value: .bounds,
            transform: { [target: $0] }
        )
    }

    /// Registers a concrete layout container instead of attaching the anchor to
    /// a conditional material/glass rendering node. The latter can disappear
    /// from the preference tree when SwiftUI swaps its platform-specific branch.
    func appTutorialPrimaryActionTarget() -> some View {
        ZStack { self }
            .appTutorialTarget(.todayPrimaryAction)
    }

    func appTutorialPrimaryActionFrame(
        isEnabled: Bool,
        _ onChange: @escaping @MainActor (CGRect?) -> Void
    ) -> some View {
        Group {
            if isEnabled {
                background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { onChange(proxy.frame(in: .global)) }
                            .onChange(of: proxy.frame(in: .global)) { frame in
                                onChange(frame)
                            }
                    }
                }
                .onDisappear { onChange(nil) }
            } else {
                self
            }
        }
    }

    func appTutorialOverlay(
        step: AppTutorialStep?,
        stepNumber: Int,
        stepCount: Int,
        languageCode: String,
        canGoBack: Bool,
        primaryActionGlobalFrame: CGRect?,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(AppTutorialTargetPreferenceKey.self) { anchors in
            if let step {
                AppTutorialOverlay(
                    anchors: anchors,
                    step: step,
                    stepNumber: stepNumber,
                    stepCount: stepCount,
                    languageCode: languageCode,
                    canGoBack: canGoBack,
                    primaryActionGlobalFrame: primaryActionGlobalFrame,
                    onBack: onBack,
                    onNext: onNext,
                    onSkip: onSkip
                )
            }
        }
    }
}

func appTutorialShouldMeasurePrimaryAction(target: AppTutorialTarget?) -> Bool {
    target == .todayPrimaryAction
}

enum AppTutorialFinishRoute: Equatable, Sendable {
    case keep(AppTutorialTarget)
    case yieldToExternalTarget
}

struct AppTutorialExternalInterruption: Equatable, Sendable {
    let stepIndex: Int?
    let isManualReplay: Bool
    let suppressAutomaticPresentationForSession: Bool
}

struct AppTutorialTabMeasurement: Equatable {
    let target: AppTutorialTarget
    let windowFrame: CGRect
}

func appTutorialTabMeasurement(
    itemCount: Int,
    selectedIndex: Int,
    windowFrame: CGRect,
    windowBounds: CGRect
) -> AppTutorialTabMeasurement? {
    guard itemCount == 4,
          appTutorialIsUsableRect(windowBounds),
          appTutorialIsUsableRect(windowFrame),
          windowFrame.width >= 24,
          windowFrame.height >= 24,
          windowBounds.insetBy(dx: -1, dy: -1).contains(windowFrame) else {
        return nil
    }

    let target: AppTutorialTarget
    switch selectedIndex {
    case 1: target = .exercises
    case 2: target = .progress
    case 3: target = .profile
    default: return nil
    }
    return AppTutorialTabMeasurement(target: target, windowFrame: windowFrame)
}

func appTutorialLocalTabTargetRect(
    measurement: AppTutorialTabMeasurement?,
    expectedTarget: AppTutorialTarget,
    overlayGlobalFrame: CGRect
) -> CGRect? {
    guard let measurement,
          measurement.target == expectedTarget,
          appTutorialIsUsableRect(measurement.windowFrame),
          appTutorialIsUsableRect(overlayGlobalFrame) else {
        return nil
    }
    return measurement.windowFrame.offsetBy(
        dx: -overlayGlobalFrame.minX,
        dy: -overlayGlobalFrame.minY
    )
}

func appTutorialOrderedTabFrames(
    _ frames: [CGRect],
    itemCount: Int,
    isRightToLeft: Bool
) -> [CGRect]? {
    guard itemCount > 0,
          frames.count == itemCount,
          frames.allSatisfy({
              appTutorialIsUsableRect($0) && $0.width >= 24 && $0.height >= 24
          }) else {
        return nil
    }

    let ordered = frames.sorted { $0.midX < $1.midX }
    return isRightToLeft ? ordered.reversed() : ordered
}

private func appTutorialIsUsableRect(_ rect: CGRect) -> Bool {
    !rect.isNull
        && !rect.isInfinite
        && rect.minX.isFinite
        && rect.minY.isFinite
        && rect.width.isFinite
        && rect.height.isFinite
        && rect.width > 0
        && rect.height > 0
}

private struct AppTutorialTabFrameProbe: UIViewRepresentable {
    let onMeasurement: (AppTutorialTabMeasurement?) -> Void

    func makeUIView(context: Context) -> AppTutorialTabFrameProbeView {
        let view = AppTutorialTabFrameProbeView()
        view.onMeasurement = onMeasurement
        return view
    }

    func updateUIView(_ uiView: AppTutorialTabFrameProbeView, context: Context) {
        uiView.onMeasurement = onMeasurement
        uiView.scheduleMeasurement()
    }
}

private final class AppTutorialTabFrameProbeView: UIView {
    var onMeasurement: ((AppTutorialTabMeasurement?) -> Void)?

    private var immediateMeasurement: DispatchWorkItem?
    private var settledMeasurement: DispatchWorkItem?
    private var lastMeasurement: AppTutorialTabMeasurement?
    private var hasPublishedMeasurement = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        immediateMeasurement?.cancel()
        settledMeasurement?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleMeasurement()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleMeasurement()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        immediateMeasurement?.cancel()
        let immediate = DispatchWorkItem { [weak self] in
            self?.publishMeasurement()
        }
        immediateMeasurement = immediate
        DispatchQueue.main.async(execute: immediate)

        // The selected Liquid Glass pill finishes moving after the SwiftUI tab
        // selection changes. Re-read once settled so the spotlight follows the
        // final public accessibility geometry instead of an animation frame.
        settledMeasurement?.cancel()
        let settled = DispatchWorkItem { [weak self] in
            self?.publishMeasurement()
        }
        settledMeasurement = settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: settled)
    }

    private func publishMeasurement() {
        let measurement = currentMeasurement()
        guard !hasPublishedMeasurement || measurement != lastMeasurement else { return }
        hasPublishedMeasurement = true
        lastMeasurement = measurement
        onMeasurement?(measurement)
    }

    private func currentMeasurement() -> AppTutorialTabMeasurement? {
        guard let window,
              let controller = owningTabBarController(in: window),
              let items = controller.tabBar.items,
              let selectedItem = controller.tabBar.selectedItem,
              let selectedIndex = items.firstIndex(where: { $0 === selectedItem }),
              (1 ... 3).contains(selectedIndex) else {
            return nil
        }

        let windowFrame: CGRect
        if let measuredFrame = selectedTabControlWindowFrame(
            in: controller.tabBar,
            selectedIndex: selectedIndex,
            itemCount: items.count,
            window: window
        ) {
            windowFrame = measuredFrame
        } else if appTutorialIsUsableRect(selectedItem.accessibilityFrame) {
            windowFrame = window.coordinateSpace.convert(
                selectedItem.accessibilityFrame,
                from: window.screen.coordinateSpace
            )
        } else {
            return nil
        }
        return appTutorialTabMeasurement(
            itemCount: items.count,
            selectedIndex: selectedIndex,
            windowFrame: windowFrame,
            windowBounds: window.bounds
        )
    }

    private func selectedTabControlWindowFrame(
        in tabBar: UITabBar,
        selectedIndex: Int,
        itemCount: Int,
        window: UIWindow
    ) -> CGRect? {
        guard itemCount > 0,
              tabBar.bounds.width > 0,
              tabBar.bounds.height > tabBar.safeAreaInsets.bottom else {
            return nil
        }

        let visibleHeight = tabBar.bounds.height - tabBar.safeAreaInsets.bottom
        let sampleRows = [visibleHeight * 0.25, visibleHeight * 0.5, visibleHeight * 0.75]
        let sampleSpacing: CGFloat = 4
        let horizontalSamples = max(1, Int(ceil(tabBar.bounds.width / sampleSpacing)))
        let tabBarWindowFrame = tabBar.convert(tabBar.bounds, to: window)
        var framesByControl: [ObjectIdentifier: CGRect] = [:]

        for y in sampleRows {
            for sample in 0 ... horizontalSamples {
                let x = min(
                    tabBar.bounds.maxX - 1,
                    tabBar.bounds.minX + CGFloat(sample) * sampleSpacing + 1
                )
                guard let hitView = tabBar.hitTest(CGPoint(x: x, y: y), with: nil),
                      let control = nearestControl(from: hitView, within: tabBar) else {
                    continue
                }
                let frame = control.convert(control.bounds, to: window)
                guard appTutorialIsUsableRect(frame),
                      frame.width >= 24,
                      frame.height >= 24,
                      tabBarWindowFrame.intersects(frame) else {
                    continue
                }
                framesByControl[ObjectIdentifier(control)] = frame
            }
        }

        guard let frames = appTutorialOrderedTabFrames(
            Array(framesByControl.values),
            itemCount: itemCount,
            isRightToLeft: tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        ) else { return nil }
        guard frames.indices.contains(selectedIndex) else { return nil }
        return frames[selectedIndex]
    }

    private func nearestControl(from view: UIView, within tabBar: UITabBar) -> UIControl? {
        var current: UIView? = view
        while let candidate = current, candidate !== tabBar {
            if let control = candidate as? UIControl { return control }
            current = candidate.superview
        }
        return nil
    }

    private func owningTabBarController(in window: UIWindow) -> UITabBarController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UITabBarController {
                return controller
            }
            if let controller = current as? UIViewController,
               let tabBarController = controller.tabBarController {
                return tabBarController
            }
            responder = current.next
        }

        guard let rootViewController = window.rootViewController else { return nil }
        return visibleTabBarController(from: rootViewController, in: window)
    }

    private func visibleTabBarController(
        from controller: UIViewController,
        in window: UIWindow
    ) -> UITabBarController? {
        if let presented = controller.presentedViewController,
           let found = visibleTabBarController(from: presented, in: window) {
            return found
        }
        if let tabBarController = controller as? UITabBarController,
           tabBarController.viewIfLoaded?.window === window,
           !tabBarController.tabBar.isHidden {
            return tabBarController
        }
        for child in controller.children.reversed() {
            if let found = visibleTabBarController(from: child, in: window) {
                return found
            }
        }
        return nil
    }
}

enum AppTutorialPinnedAction: String, Hashable, Sendable {
    case skip
    case back
    case advance
}

func appTutorialPinnedActions(canGoBack: Bool) -> [AppTutorialPinnedAction] {
    canGoBack ? [.skip, .back, .advance] : [.skip, .advance]
}

func appTutorialShouldRecordCompletion(
    isManualReplay: Bool,
    needsAutomaticPresentation: Bool
) -> Bool {
    !isManualReplay || needsAutomaticPresentation
}

/// External navigation always owns the screen. An interrupted tutorial is
/// dismissed only in memory: its durable completion remains untouched so the
/// automatic first-run walkthrough can be offered on a later stable launch.
func appTutorialExternalInterruption(
    currentStepIndex: Int?,
    isManualReplay: Bool
) -> AppTutorialExternalInterruption {
    return AppTutorialExternalInterruption(
        stepIndex: nil,
        isManualReplay: false,
        suppressAutomaticPresentationForSession: true
    )
}

func appTutorialFinishRoute(
    currentTarget: AppTutorialTarget,
    externalTargetOwnsNavigation: Bool
) -> AppTutorialFinishRoute {
    externalTargetOwnsNavigation
        ? .yieldToExternalTarget
        : .keep(currentTarget)
}

func appTutorialScreenshotStepIndex(arguments: [String]) -> Int? {
    guard let rawValue = arguments
        .first(where: { $0.hasPrefix("--screenshot-tutorial-step=") })?
        .split(separator: "=", maxSplits: 1)
        .last,
        let step = Int(rawValue),
        (1 ... 5).contains(step) else {
        return nil
    }
    return step - 1
}

struct AppTutorialStep: Identifiable, Equatable, Sendable {
    let id: String
    let target: AppTutorialTarget
    let title: String
    let body: String

    static func all(languageCode: String) -> [Self] {
        [
            Self(
                id: "todayFocus",
                target: .todayFocus,
                title: gymText(
                    "Your next workout",
                    "Твоє наступне тренування",
                    "Твоя следующая тренировка",
                    languageCode: languageCode
                ),
                body: gymText(
                    "Start, continue, or adjust today’s plan here.",
                    "Тут можна почати, продовжити або змінити план на сьогодні.",
                    "Здесь можно начать, продолжить или изменить план на сегодня.",
                    languageCode: languageCode
                )
            ),
            Self(
                id: "todayPrimaryAction",
                target: .todayPrimaryAction,
                title: gymText(
                    "One clear next step",
                    "Один зрозумілий наступний крок",
                    "Один понятный следующий шаг",
                    languageCode: languageCode
                ),
                body: gymText(
                    "GymApp keeps the current workout action within easy reach.",
                    "GymApp тримає поточну дію тренування під рукою.",
                    "GymApp держит текущее действие тренировки под рукой.",
                    languageCode: languageCode
                )
            ),
            Self(
                id: "exercises",
                target: .exercises,
                title: gymText("Exercises", "Вправи", "Упражнения", languageCode: languageCode),
                body: gymText(
                    "Find movements and open their technique guide.",
                    "Знаходь вправи та відкривай підказки з техніки.",
                    "Находи упражнения и открывай подсказки по технике.",
                    languageCode: languageCode
                )
            ),
            Self(
                id: "progress",
                target: .progress,
                title: gymText(
                    "Progress and goals",
                    "Прогрес і цілі",
                    "Прогресс и цели",
                    languageCode: languageCode
                ),
                body: gymText(
                    "Review your trend, muscle load, records, and missions.",
                    "Переглядай динаміку, навантаження м’язів, рекорди та місії.",
                    "Смотри динамику, нагрузку мышц, рекорды и миссии.",
                    languageCode: languageCode
                )
            ),
            Self(
                id: "profile",
                target: .profile,
                title: gymText(
                    "Profile and help",
                    "Профіль і допомога",
                    "Профиль и помощь",
                    languageCode: languageCode
                ),
                body: gymText(
                    "Friends, live workouts, account, devices, and help are here.",
                    "Тут є друзі, спільні тренування, акаунт, пристрої та допомога.",
                    "Здесь находятся друзья, совместные тренировки, аккаунт, устройства и помощь.",
                    languageCode: languageCode
                )
            )
        ]
    }
}

struct AppTutorialOverlay: View {
    let anchors: [AppTutorialTarget: Anchor<CGRect>]
    let step: AppTutorialStep
    let stepNumber: Int
    let stepCount: Int
    let languageCode: String
    let canGoBack: Bool
    let primaryActionGlobalFrame: CGRect?
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var dialogFocused: Bool
    @State private var measuredCardHeight: CGFloat = 0
    @State private var measuredTabTarget: AppTutorialTabMeasurement?

    var body: some View {
        GeometryReader { proxy in
            let targetRect = resolvedTargetRect(in: proxy)
            ZStack {
                spotlightShade(targetRect: targetRect)

                if let targetRect {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white, lineWidth: 3)
                        .padding(-8)
                        .frame(width: targetRect.width, height: targetRect.height)
                        .position(x: targetRect.midX, y: targetRect.midY)
                        .shadow(color: GymTheme.primary.opacity(0.9), radius: reduceMotion ? 8 : 18)
                        .accessibilityHidden(true)
                }

                tutorialCard(in: proxy.size, targetRect: targetRect)
            }
            .background(alignment: .topLeading) {
                AppTutorialTabFrameProbe { measurement in
                    guard measurement != measuredTabTarget else { return }
                    measuredTabTarget = measurement
                }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .onAppear { dialogFocused = true }
        .onChange(of: step.id) { _ in
            measuredCardHeight = 0
            dialogFocused = true
        }
        .accessibilityAction(.escape, onSkip)
    }

    private func spotlightShade(targetRect: CGRect?) -> some View {
        Color.black.opacity(0.66)
            .ignoresSafeArea()
            .mask {
                ZStack {
                    Rectangle().fill(Color.white)
                    if let targetRect {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .frame(width: targetRect.width + 16, height: targetRect.height + 16)
                            .position(x: targetRect.midX, y: targetRect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .accessibilityHidden(true)
    }

    private func resolvedTargetRect(in proxy: GeometryProxy) -> CGRect? {
        if step.target == .todayPrimaryAction,
           let primaryActionGlobalFrame,
           primaryActionGlobalFrame.width > 0,
           primaryActionGlobalFrame.height > 0 {
            let overlayGlobalFrame = proxy.frame(in: .global)
            return primaryActionGlobalFrame.offsetBy(
                dx: -overlayGlobalFrame.minX,
                dy: -overlayGlobalFrame.minY
            )
        }
        if let anchor = anchors[step.target] { return proxy[anchor] }
        return appTutorialLocalTabTargetRect(
            measurement: measuredTabTarget,
            expectedTarget: step.target,
            overlayGlobalFrame: proxy.frame(in: .global)
        )
    }

    private func tutorialCard(in size: CGSize, targetRect: CGRect?) -> some View {
        let maximumCardHeight = appTutorialMaximumCardHeight(in: size)
        let maximumCardWidth = min(440, max(280, size.width - 32))
        let usesBoundedScroll = appTutorialUsesBoundedScroll(
            dynamicTypeSizeIsAccessibility: dynamicTypeSize.isAccessibilitySize,
            maximumCardHeight: maximumCardHeight
        )
        let estimatedHalfHeight = usesBoundedScroll
            ? maximumCardHeight / 2
            : measuredCardHeight > 0
            ? min(maximumCardHeight, measuredCardHeight) / 2
            : appTutorialInitialCardHalfHeight(maximumCardHeight: maximumCardHeight)
        return tutorialCardContent(
            maximumHeight: max(120, maximumCardHeight - 36),
            usesBoundedScroll: usesBoundedScroll
        )
        .padding(18)
        // Standard text keeps a compact coach mark. Accessibility text and
        // short viewports use an explicitly bounded card so every action can
        // be reached by scrolling without extending below the screen.
        .frame(
            width: maximumCardWidth,
            height: usesBoundedScroll ? maximumCardHeight : nil,
            alignment: .topLeading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(GymTheme.outline.opacity(0.55), lineWidth: 1)
        }
        .background {
            GeometryReader { cardProxy in
                Color.clear.preference(
                    key: AppTutorialCardHeightPreferenceKey.self,
                    value: cardProxy.size.height
                )
            }
        }
        .onPreferenceChange(AppTutorialCardHeightPreferenceKey.self) { height in
            guard height.isFinite,
                  height > 0,
                  abs(height - measuredCardHeight) > 0.5 else { return }
            measuredCardHeight = height
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityFocused($dialogFocused)
        .accessibilityLabel(
            gymText(
                "Tutorial. Step \(stepNumber) of \(stepCount). \(step.title). \(step.body)",
                "Навчання. Крок \(stepNumber) із \(stepCount). \(step.title). \(step.body)",
                "Обучение. Шаг \(stepNumber) из \(stepCount). \(step.title). \(step.body)",
                languageCode: languageCode
            )
        )
        .position(
            x: size.width / 2,
            y: usesBoundedScroll ? size.height / 2 : appTutorialCardCenterY(
                in: size,
                targetRect: targetRect,
                estimatedHalfHeight: estimatedHalfHeight
            )
        )
    }

    @ViewBuilder
    private func tutorialCardContent(
        maximumHeight: CGFloat,
        usesBoundedScroll: Bool
    ) -> some View {
        if usesBoundedScroll {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.vertical) {
                    tutorialCopy
                        .padding(.bottom, 2)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Keep all navigation actions outside the scrolling copy. A
                // bounded card alone is not sufficient: at accessibility XXXL
                // the scroll view can otherwise open at the top with Skip and
                // Back below the fold, leaving no obvious way out.
                tutorialActionsVertical
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .frame(height: maximumHeight)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                tutorialCopy
                tutorialActions
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tutorialCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            tutorialStepLabel
            Text(step.title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(step.body)
                .font(.body)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tutorialActions: some View {
        ViewThatFits(in: .horizontal) {
            tutorialActionsHorizontal
            tutorialActionsVertical
        }
    }

    private var tutorialStepLabel: some View {
        Text(
            gymText(
                "Step \(stepNumber) of \(stepCount)",
                "Крок \(stepNumber) із \(stepCount)",
                "Шаг \(stepNumber) из \(stepCount)",
                languageCode: languageCode
            )
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(GymTheme.primary)
    }

    private var tutorialActionsHorizontal: some View {
        HStack(spacing: 8) {
            tutorialSkipButton
            Spacer(minLength: 4)
            if canGoBack { tutorialBackButton }
            tutorialNextButton
        }
    }

    private var tutorialActionsVertical: some View {
        VStack(spacing: 8) {
            ForEach(appTutorialPinnedActions(canGoBack: canGoBack), id: \.self) { action in
                tutorialVerticalButton(action)
            }
        }
    }

    @ViewBuilder
    private func tutorialVerticalButton(_ action: AppTutorialPinnedAction) -> some View {
        switch action {
        case .skip:
            Button(action: onSkip) {
                Text(gymText(
                    "Skip",
                    "Пропустити",
                    "Пропустить",
                    languageCode: languageCode
                ))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .back:
            Button(action: onBack) {
                Text(gymText("Back", "Назад", "Назад", languageCode: languageCode))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .advance:
            Button(action: onNext) {
                Text(stepNumber == stepCount
                    ? gymText("Done", "Готово", "Готово", languageCode: languageCode)
                    : gymText("Next", "Далі", "Далее", languageCode: languageCode))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var tutorialSkipButton: some View {
        Button(
            gymText("Skip", "Пропустити", "Пропустить", languageCode: languageCode),
            action: onSkip
        )
        .buttonStyle(.bordered)
    }

    private var tutorialBackButton: some View {
        Button(
            gymText("Back", "Назад", "Назад", languageCode: languageCode),
            action: onBack
        )
        .buttonStyle(.bordered)
    }

    private var tutorialNextButton: some View {
        Button(
            stepNumber == stepCount
                ? gymText("Done", "Готово", "Готово", languageCode: languageCode)
                : gymText("Next", "Далі", "Далее", languageCode: languageCode),
            action: onNext
        )
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
}

func appTutorialMaximumCardHeight(in size: CGSize, edgeInset: CGFloat = 16) -> CGFloat {
    max(180, size.height - (edgeInset * 2))
}

func appTutorialInitialCardHalfHeight(maximumCardHeight: CGFloat) -> CGFloat {
    min(108, max(90, maximumCardHeight / 2))
}

func appTutorialUsesBoundedScroll(
    dynamicTypeSizeIsAccessibility: Bool,
    maximumCardHeight: CGFloat
) -> Bool {
    dynamicTypeSizeIsAccessibility || maximumCardHeight <= 360
}

func appTutorialCardCenterY(
    in size: CGSize,
    targetRect: CGRect?,
    estimatedHalfHeight: CGFloat = 150,
    spotlightClearance: CGFloat = 22,
    edgeInset: CGFloat = 16
) -> CGFloat {
    let minimumCenter = estimatedHalfHeight + edgeInset
    let maximumCenter = max(minimumCenter, size.height - estimatedHalfHeight - edgeInset)
    guard let targetRect,
          targetRect.width > 0,
          targetRect.height > 0 else {
        return min(maximumCenter, max(minimumCenter, size.height / 2))
    }

    let below = targetRect.maxY + spotlightClearance + estimatedHalfHeight
    if below <= maximumCenter { return below }
    let above = targetRect.minY - spotlightClearance - estimatedHalfHeight
    if above >= minimumCenter { return above }

    // Very large Dynamic Type or a short viewport can make neither side fit the
    // estimated card. Choose the side with more room and clamp only to the edge;
    // never center the dialog on top of the highlighted action.
    let spaceAbove = targetRect.minY - edgeInset
    let spaceBelow = size.height - edgeInset - targetRect.maxY
    return spaceBelow >= spaceAbove ? maximumCenter : minimumCenter
}
