import SwiftUI

/// Copy for the "Support the developer" screen, in one place so tests can check
/// that every string exists in all three languages.
enum SupportTipsCopy {
    static func title(_ code: String) -> String {
        gymText("Support the developer", "Підтримати розробника", "Поддержать разработчика", languageCode: code)
    }

    static func intro(_ code: String) -> String {
        gymText(
            "GymApp is free and will stay free. If it helps you, you can support its development. It doesn’t unlock or change anything.",
            "GymApp безкоштовний і залишиться безкоштовним. Якщо застосунок допомагає, можна підтримати розробку — це нічого не відкриває і нічого не змінює.",
            "GymApp бесплатный и останется бесплатным. Если приложение помогает, можно поддержать разработку — это ничего не открывает и ничего не меняет.",
            languageCode: code
        )
    }

    static func button(price: String, _ code: String) -> String {
        let label = gymText("Support", "Підтримати", "Поддержать", languageCode: code)
        return "\(label)\u{00A0}— \(price)"
    }

    static func thanks(_ code: String) -> String {
        gymText("Thank you for your support!", "Дякуємо за підтримку!", "Спасибо за поддержку!", languageCode: code)
    }

    static func retry(_ code: String) -> String {
        gymText("Try again", "Спробувати ще раз", "Повторить", languageCode: code)
    }

    static func offline(_ code: String) -> String {
        gymText(
            "No connection. Try again later.",
            "Немає з’єднання. Спробуйте пізніше.",
            "Нет соединения. Повторите позже.",
            languageCode: code
        )
    }

    static func unavailable(_ code: String) -> String {
        gymText(
            "Purchases are unavailable right now.",
            "Покупки зараз недоступні.",
            "Покупки сейчас недоступны.",
            languageCode: code
        )
    }

    static func pending(_ code: String) -> String {
        gymText(
            "Your payment is waiting for approval. Thank you!",
            "Платіж очікує підтвердження. Дякуємо!",
            "Платёж ожидает подтверждения. Спасибо!",
            languageCode: code
        )
    }

    static func failed(_ code: String) -> String {
        gymText(
            "Couldn’t complete the purchase. Try again later.",
            "Не вдалося завершити покупку. Спробуйте пізніше.",
            "Не удалось завершить покупку. Повторите позже.",
            languageCode: code
        )
    }

    static func notice(_ notice: SupportTipStore.Notice, _ code: String) -> String {
        switch notice {
        case .pending: pending(code)
        case .offline: offline(code)
        case .failed: failed(code)
        }
    }
}

/// Profile → Help → "Support the developer": six optional tip amounts bought
/// through StoreKit 2. Nothing is unlocked or changed by a tip.
@MainActor
struct SupportTipsView: View {
    @EnvironmentObject private var store: SupportTipStore
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedID: String?
    @State private var selectionTaps = 0

    private var selectedOption: SupportTipOption? {
        store.options.first { $0.id == selectedID }
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                    Text(SupportTipsCopy.intro(languageCode))
                        .font(.footnote)
                        .foregroundStyle(GymTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .fixedSize(horizontal: false, vertical: true)
                    panel
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
        .navigationTitle(SupportTipsCopy.title(languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.screenDidAppear()
            await store.loadIfNeeded()
            ensureSelection()
        }
        .onChange(of: store.options) { _, _ in ensureSelection() }
        .task(id: store.purchaseState == .thanks ? store.successCount : -1) {
            guard store.purchaseState == .thanks else { return }
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            dismissThanks()
        }
        .onChange(of: store.successCount) { _, _ in
            AccessibilityNotification.Announcement(SupportTipsCopy.thanks(languageCode)).post()
        }
        .gymSensoryFeedback(.success, trigger: store.successCount)
        .gymSensoryFeedback(.selection, trigger: selectionTaps)
        .environment(
            \.locale,
            AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en")
        )
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .accessibilityLabel(gymText("Loading", "Завантаження", "Загрузка", languageCode: languageCode))
            case .unavailable:
                message(SupportTipsCopy.unavailable(languageCode))
            case .offline:
                message(SupportTipsCopy.offline(languageCode))
                Button(SupportTipsCopy.retry(languageCode)) {
                    Task {
                        await store.reload()
                        ensureSelection()
                    }
                }
                .buttonStyle(GymSecondaryButtonStyle())
            case .ready:
                chips
                actionArea
                if let notice = store.notice {
                    Text(SupportTipsCopy.notice(notice, languageCode))
                        .font(.footnote)
                        .foregroundStyle(notice == .failed ? GymTheme.error : GymTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("support-tips-notice")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GymTheme.surface,
            in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
        )
        .animation(reduceMotion ? GymMotion.fade : GymMotion.momentum, value: store.purchaseState)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(GymTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.vertical, 24)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("support-tips-message")
    }

    // MARK: Chips

    private var chips: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
        )
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(store.options) { option in
                chip(option)
            }
        }
        .disabled(store.purchaseState != .idle)
    }

    private func chip(_ option: SupportTipOption) -> some View {
        let isSelected = option.id == selectedID
        return Button {
            guard selectedID != option.id else { return }
            selectionTaps += 1
            selectedID = option.id
        } label: {
            Text(option.displayPrice)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? GymTheme.onPrimary : GymTheme.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule().fill(
                        isSelected ? GymTheme.primaryAction : GymTheme.primaryAction.opacity(0.14)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : GymMotion.quick, value: selectedID)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Primary action / thank-you

    @ViewBuilder
    private var actionArea: some View {
        if store.purchaseState == .thanks {
            thanksView
                .gymTransition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            Button {
                guard let id = selectedID else { return }
                Task { await store.purchase(productID: id) }
            } label: {
                ZStack {
                    Text(SupportTipsCopy.button(price: selectedOption?.displayPrice ?? "", languageCode))
                        .opacity(store.purchaseState == .purchasing ? 0 : 1)
                    if store.purchaseState == .purchasing {
                        ProgressView().tint(GymTheme.onPrimary)
                    }
                }
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(selectedOption == nil || store.purchaseState != .idle)
            .gymTransition(.opacity)
        }
    }

    private var thanksView: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(GymTheme.primaryAction)
                .accessibilityHidden(true)
            Text(SupportTipsCopy.thanks(languageCode))
                .font(.headline)
                .foregroundStyle(GymTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .contentShape(Rectangle())
        .onTapGesture { dismissThanks() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("support-tips-thanks")
    }

    // MARK: Helpers

    private func dismissThanks() {
        withAnimation(reduceMotion ? GymMotion.fade : GymMotion.momentum) {
            store.dismissThanks()
        }
    }

    private func ensureSelection() {
        let ids = store.options.map(\.id)
        guard !ids.isEmpty else { return }
        if let selectedID, ids.contains(selectedID) { return }
        selectedID = SupportTipProducts.defaultSelection(among: ids)
    }
}
