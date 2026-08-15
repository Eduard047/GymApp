import SwiftUI

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
        _ onChange: @escaping @MainActor (CGRect?) -> Void
    ) -> some View {
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

enum AppTutorialFinishRoute: Equatable, Sendable {
    case keep(AppTutorialTarget)
    case yieldToExternalTarget
}

struct AppTutorialExternalInterruption: Equatable, Sendable {
    let stepIndex: Int?
    let isManualReplay: Bool
    let suppressAutomaticPresentationForSession: Bool
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
        let tabIndex: CGFloat
        switch step.target {
        case .exercises: tabIndex = 1
        case .progress: tabIndex = 2
        case .profile: tabIndex = 3
        case .todayFocus, .todayPrimaryAction: return nil
        }
        let width = proxy.size.width / 4
        return CGRect(
            x: width * tabIndex,
            y: max(0, proxy.size.height - 64),
            width: width,
            height: 58
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
