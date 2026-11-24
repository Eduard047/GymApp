import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum NativePushScrollBehavior: Equatable, Sendable {
    case animated
    case immediate
}

func nativePushScrollBehavior(reduceMotion: Bool) -> NativePushScrollBehavior {
    reduceMotion ? .immediate : .animated
}

@MainActor
struct ProfileView: View {
    private enum ActiveAlert: Identifiable {
        case importBackup

        var id: String {
            switch self {
            case .importBackup: "import-backup"
            }
        }
    }

    @ObservedObject private var appState: AppState
    @ObservedObject private var auth: AuthService
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var garminCloud: GarminCloudService
    @ObservedObject private var garminPhoneSync: GarminPhoneSyncService
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @AppStorage(GymHaptics.preferenceKey) private var hapticsEnabled = true
    @AppStorage(GymKeepAwake.preferenceKey) private var keepScreenOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedProfilePushTarget: NativePushProfileFocus?

    @State private var activeAlert: ActiveAlert?
    @State private var showsAccountSettings = false
    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var isPreparingWorkoutPDF = false
    @State private var pendingImportData: Data?
    @State private var exportDocument: ProfileExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "GymApp-backup"
    @State private var fulfilledNativePushRequestID: UUID?
    @State private var requestedNativePushAccessibilityTarget: NativePushProfileFocus?
    @State private var showsFriends = false
    @State private var showsHealthAppSheet = false
#if DEBUG
    @State private var qaShowsWatches = false
#endif
    @State private var backupExpanded = false
    @State private var trainingProfile: TrainingProfile
    private let canAcceptWorkoutInvites: Bool
    private let nativePushRequest: NativePushProfileRequest?
    private let onShowTutorial: () -> Void
    private let onCreateLiveWorkout: (SocialFriendSummary) -> Void
    private let onOpenLiveWorkout: () -> Void

    init(
        appState: AppState,
        auth: AuthService,
        store: WorkoutStore,
        canAcceptWorkoutInvites: Bool = true,
        liveWorkoutCoordinator: LiveWorkoutCoordinator,
        nativePushRequest: NativePushProfileRequest? = nil,
        onShowTutorial: @escaping () -> Void = {},
        onCreateLiveWorkout: @escaping (SocialFriendSummary) -> Void = { _ in },
        onOpenLiveWorkout: @escaping () -> Void
    ) {
        self.appState = appState
        self.auth = auth
        self.store = store
        self.garminCloud = appState.garminCloud
        self.garminPhoneSync = appState.garminPhoneSync
        self.canAcceptWorkoutInvites = canAcceptWorkoutInvites
        self.liveWorkoutCoordinator = liveWorkoutCoordinator
        self.nativePushRequest = nativePushRequest
        self.onShowTutorial = onShowTutorial
        self.onCreateLiveWorkout = onCreateLiveWorkout
        self.onOpenLiveWorkout = onOpenLiveWorkout
        _trainingProfile = State(initialValue: TrainingProfileStore().load(
            accountStorageKey: store.accountStorageKey
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            GymBackground {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                        header
                        settingsGroups
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
                .gymStatusBarScrollEdge()
            }
            .task(id: nativePushRequest?.id) {
                requestedNativePushAccessibilityTarget = nil
                focusedProfilePushTarget = nil
                // Friends & live is a pushed screen; a push route opens it and the
                // screen scrolls to the exact card.
                guard nativePushRequest != nil, isCloudAccount else { return }
                showsFriends = true
            }
#if DEBUG
            .onReceive(UIAuditRouter.shared.$pendingPresentation.compactMap { $0 }) { _ in
                presentUIAuditRouteIfRequested(proxy)
            }
            .task {
                guard QAAuditSeed.scroll == "devices" else { return }
                try? await Task.sleep(for: .milliseconds(1_500))
                proxy.scrollTo("qa-devices", anchor: .center)
            }
#endif
        }
        .navigationDestination(isPresented: $showsFriends) {
            ProfileFriendsScreen(
                appState: appState,
                auth: auth,
                canAcceptWorkoutInvites: canAcceptWorkoutInvites,
                liveWorkoutCoordinator: liveWorkoutCoordinator,
                nativePushRequest: nativePushRequest,
                fulfilledNativePushRequestID: $fulfilledNativePushRequestID,
                requestedNativePushAccessibilityTarget: $requestedNativePushAccessibilityTarget,
                focusedProfilePushTarget: $focusedProfilePushTarget,
                onOpenAccountSettings: { showsAccountSettings = true },
                onCreateLiveWorkout: onCreateLiveWorkout,
                onOpenLiveWorkout: onOpenLiveWorkout
            )
        }
        .sheet(isPresented: $showsAccountSettings) {
            NavigationStack {
                AccountSettingsView(
                    showsCloseButton: true,
                    hasBlockingLiveWorkout: liveWorkoutCoordinator.hasBlockingLiveWorkout
                )
            }
            .environmentObject(appState)
            .environmentObject(auth)
            .gymSheetPresentation(.full)
        }
        .sheet(isPresented: $showsHealthAppSheet) {
            HealthAppRecommendationSheet(languageCode: languageCode)
                .gymSheetPresentation(.standard)
        }
#if DEBUG
        // QA audit (`-qaOpen watches|healthapp`): opens the pushed Watches screen or the HealthApp sheet.
        .navigationDestination(isPresented: $qaShowsWatches) {
            WatchesScreen(
                garminCloud: garminCloud,
                garminPhoneSync: garminPhoneSync,
                appleWatch: appState.watchSync,
                healthImport: appState.healthImport
            )
            .gymTopBannerInset()
        }
        .task {
            guard let open = QAAuditSeed.open else { return }
            try? await Task.sleep(for: .milliseconds(900))
            if open == "watches" { qaShowsWatches = true }
            if open == "healthapp" { showsHealthAppSheet = true }
        }
#endif
        .alert(item: $activeAlert, content: makeAlert)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .task(id: auth.session?.storageKey) {
            guard isCloudAccount, !garminCloud.isWorking else { return }
            try? await garminCloud.refreshDevices()
        }
        .onChange(of: store.accountStorageKey) { _, key in
            trainingProfile = TrainingProfileStore().load(accountStorageKey: key)
        }
    }
#if DEBUG
    /// UI-audit: opens the Account sheet (`account-settings`), the same sheet with its
    /// first deletion alert (`account-delete-dialog`; `AccountSettingsView` consumes that
    /// route), or expands Backup & diagnostics (`backup-tools`). Nothing is confirmed.
    private func presentUIAuditRouteIfRequested(_ proxy: ScrollViewProxy) {
        switch UIAuditRouter.shared.pendingPresentation {
        case .accountDeleteDialog?:
            guard !showsAccountSettings else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                showsAccountSettings = true
            }
        case .accountSettings?, .backupTools?:
            guard let route = UIAuditRouter.shared.consume(anyOf: [.accountSettings, .backupTools]) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                if route == .accountSettings {
                    showsAccountSettings = true
                } else {
                    backupExpanded = true
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo("ui-audit-backup", anchor: .top)
                }
            }
        default:
            break
        }
    }
#endif

    private var header: some View {
        let friendCount = appState.socialDashboard?.friends.count ?? 0
        let pendingCount = (appState.socialDashboard?.incoming.count ?? 0)
            + (appState.socialWorkoutInbox?.pendingIncomingCount ?? 0)
            + liveWorkoutCoordinator.pendingInvitationCount
        return GymPanel(highlighted: true) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .gymScaledFont(size: 30, weight: .semibold, relativeTo: .title3, maxScale: 1.6)
                    .foregroundStyle(GymTheme.primary)
                    .gymScaledFrame(width: 48, height: 48, relativeTo: .title3, maxScale: 1.6)
                    .background(GymTheme.surfaceVariant, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.session?.displayName ?? gymText(
                        "GymApp athlete",
                        "Атлет GymApp",
                        "Атлет GymApp",
                        languageCode: languageCode
                    ))
                        .font(GymTheme.TypeScale.heroTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        isCloudAccount
                            ? gymText(
                                "Cloud protected · Friends: \(friendCount)",
                                "Захищено хмарою · Друзі: \(friendCount)",
                                "Защищено облаком · Друзья: \(friendCount)",
                                languageCode: languageCode
                            )
                            : gymText(
                                "Stored on this iPhone",
                                "Збережено на цьому iPhone",
                                "Сохранено на этом iPhone",
                                languageCode: languageCode
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)
                if pendingCount > 0 {
                    GymInfoPill(
                        "\(min(pendingCount, 99))",
                        accent: GymTheme.error
                    )
                    .accessibilityLabel(gymText(
                        "Needs attention: \(pendingCount)",
                        "Потребують уваги: \(pendingCount)",
                        "Требуют внимания: \(pendingCount)",
                        languageCode: languageCode
                    ))
                }
            }
        }
    }

    /// Inset-grouped Profile root: Our apps, Account, Workouts, Devices, App, Data, Help.
    /// Rows are 17pt regular titles with a status-only subtitle or a secondary
    /// value on the right; every feature keeps its destination.
    private var settingsGroups: some View {
        VStack(alignment: .leading, spacing: GymTheme.contentSpacing + 4) {
            ProfileGroup(title: gymText("Our apps", "Наші застосунки", "Наши приложения", languageCode: languageCode)) {
                healthAppRow
            }
            settingsGroup
            ProfileGroup(title: gymText("Workouts", "Тренування", "Тренировки", languageCode: languageCode)) {
                trainingSettingsRow
                settingsRowDivider
                keepScreenOnRow
                settingsRowDivider
                hapticsRow
            }
            ProfileGroup(title: gymText("Devices", "Пристрої", "Устройства", languageCode: languageCode)) {
                watchesRow
            }
#if DEBUG
            .id("qa-devices")
#endif
            ProfileGroup(title: gymText("App", "Застосунок", "Приложение", languageCode: languageCode)) {
                languageRow
            }
            ProfileGroup(title: gymText("Data", "Дані", "Данные", languageCode: languageCode)) {
                backupRow
#if DEBUG
                    .id("ui-audit-backup")
#endif
            }
            ProfileGroup(title: gymText("Help", "Допомога", "Помощь", languageCode: languageCode)) {
                helpRow
                settingsRowDivider
                supportRow
            }
        }
    }

    /// The "Account" group: Friends & live (or the cloud-upgrade prompt for a
    /// local profile) and Account.
    private var settingsGroup: some View {
        ProfileGroup(title: gymText("Account", "Акаунт", "Аккаунт", languageCode: languageCode)) {
            if isCloudAccount {
                friendsRow
            } else {
                friendsCloudUpgradeRow
            }
            settingsRowDivider
            accountRow
        }
    }

    private var settingsRowDivider: some View {
        Divider()
            .overlay(GymTheme.outlineSoft)
    }

    private var friendsTitle: String {
        gymText("Friends & live", "Друзі та live", "Друзья и live", languageCode: languageCode)
    }

    private var friendsPendingCount: Int {
        (appState.socialDashboard?.incoming.count ?? 0)
            + (appState.socialWorkoutInbox?.pendingIncomingCount ?? 0)
            + liveWorkoutCoordinator.pendingInvitationCount
    }

    private var friendsRow: some View {
        let pending = friendsPendingCount
        return Button {
            showsFriends = true
        } label: {
            ProfileRowLabel(
                title: friendsTitle,
                subtitle: pending > 0
                    ? gymText(
                        "Needs attention: \(pending)",
                        "Потребують уваги: \(pending)",
                        "Требуют внимания: \(pending)",
                        languageCode: languageCode
                    )
                    : nil
            )
        }
        .buttonStyle(.plain)
    }

    private var friendsCloudUpgradeRow: some View {
        Button {
            showsAccountSettings = true
        } label: {
            ProfileRowLabel(
                title: friendsTitle,
                subtitle: gymText(
                    "Requires a cloud account",
                    "Потрібен хмарний акаунт",
                    "Нужен облачный аккаунт",
                    languageCode: languageCode
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(gymText(
            "Open account settings",
            "Відкрити налаштування акаунта",
            "Открыть настройки аккаунта",
            languageCode: languageCode
        ))
    }

    private var accountRow: some View {
        Button {
            showsAccountSettings = true
        } label: {
            ProfileRowLabel(
                title: gymText("Account", "Акаунт", "Аккаунт", languageCode: languageCode),
                subtitle: accountRowSubtitle
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(gymText(
            "Opens identity, privacy, support, sign out, and account deletion.",
            "Відкриває профіль, приватність, підтримку, вихід і видалення акаунта.",
            "Открывает профиль, конфиденциальность, поддержку, выход и удаление аккаунта.",
            languageCode: languageCode
        ))
    }

    private var accountRowSubtitle: String {
        isCloudAccount
            ? accountSubtitle
            : gymText("Local profile", "Локальний профіль", "Локальный профиль", languageCode: languageCode)
    }

    private var languageRow: some View {
        let title = Text(gymText("Language", "Мова", "Язык", languageCode: languageCode))
            .font(.body)
            .foregroundStyle(GymTheme.textPrimary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The title keeps the full width (never "Lan-guage"); the menu sits on its own line.
                VStack(alignment: .leading, spacing: 4) {
                    title
                    AppLanguageMenu(style: .inline)
                }
            } else {
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 6)
                    AppLanguageMenu(style: .inline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    /// In-app Haptics switch (DESIGN.md "Feedback and haptics"): gates every
    /// haptic the app plays; stored on this device only.
    private var hapticsRow: some View {
        let label = Text(gymText("Haptics", "Тактильний відгук", "Тактильный отклик", languageCode: languageCode))
            .font(.body)
            .foregroundStyle(GymTheme.textPrimary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The label gets the full width; the switch sits on its own line.
                VStack(alignment: .leading, spacing: 8) {
                    label
                    Toggle(isOn: $hapticsEnabled) { label }
                        .labelsHidden()
                        .tint(GymTheme.primaryAction)
                        .accessibilityLabel(gymText("Haptics", "Тактильний відгук", "Тактильный отклик", languageCode: languageCode))
                }
            } else {
                HStack(spacing: 12) {
                    Toggle(isOn: $hapticsEnabled) { label }
                        .tint(GymTheme.primaryAction)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    /// In-app "Keep screen on in workouts" switch: holds the screen awake
    /// while the active workout is visible; stored on this device only.
    private var keepScreenOnRow: some View {
        let keepScreenOnTitle = gymText(
            "Keep screen on in workouts",
            "Не вимикати екран на тренуванні",
            "Не гасить экран на тренировке",
            languageCode: languageCode
        )
        let label = Text(keepScreenOnTitle)
            .font(.body)
            .foregroundStyle(GymTheme.textPrimary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The label gets the full width; the switch sits on its own line.
                VStack(alignment: .leading, spacing: 8) {
                    label
                    Toggle(isOn: $keepScreenOn) { label }
                        .labelsHidden()
                        .tint(GymTheme.primaryAction)
                        .accessibilityLabel(keepScreenOnTitle)
                }
            } else {
                HStack(spacing: 12) {
                    Toggle(isOn: $keepScreenOn) { label }
                        .tint(GymTheme.primaryAction)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    /// The owner's other app, always visible right under the profile header. Opens the
    /// explainer sheet; the App Store opens only from that sheet's primary button.
    private var healthAppRow: some View {
        Button {
            showsHealthAppSheet = true
        } label: {
            ProfileRowLabel(
                title: "HealthApp",
                subtitle: gymText(
                    "Sleep, HRV and recovery from your watch — by the same developer",
                    "Сон, HRV і відновлення з вашого годинника — від того ж розробника",
                    "Сон, HRV и восстановление с ваших часов — от того же разработчика",
                    languageCode: languageCode
                ),
                subtitleLineLimit: 2
            )
        }
        .buttonStyle(.plain)
        // The tap opens an in-app sheet (the App Store only from its button): a chevron, not an arrow.
        .accessibilityLabel(gymText(
            "HealthApp, details",
            "HealthApp, докладніше",
            "HealthApp, подробнее",
            languageCode: languageCode
        ))
        .accessibilityHint(gymText(
            "Shows a short description first",
            "Спочатку показує короткий опис",
            "Сначала показывает краткое описание",
            languageCode: languageCode
        ))
    }

    /// The help row's one action (replay the tutorial).
    private var helpRow: some View {
        Button(action: onShowTutorial) {
            ProfileRowLabel(
                title: gymText("Help", "Допомога", "Помощь", languageCode: languageCode),
                subtitle: gymText(
                    "Quick tour of the app",
                    "Короткий огляд застосунку",
                    "Короткий обзор приложения",
                    languageCode: languageCode
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Optional tip jar: a pushed screen, never a popup or a prompt.
    private var supportRow: some View {
        NavigationLink {
            SupportTipsView()
                .gymTopBannerInset()
        } label: {
            ProfileRowLabel(title: SupportTipsCopy.title(languageCode))
        }
        .buttonStyle(.plain)
    }

    private var trainingSettingsRow: some View {
        NavigationLink {
            TrainingSettingsView(profile: $trainingProfile) { newValue in
                TrainingProfileStore().save(newValue, accountStorageKey: store.accountStorageKey)
            }
            .gymTopBannerInset()
        } label: {
            ProfileRowLabel(
                title: gymText(
                    "Training settings", "Налаштування тренувань", "Настройки тренировок",
                    languageCode: languageCode
                ),
                subtitle: trainingSettingsSummaryText
            )
        }
        .buttonStyle(.plain)
    }

    /// One row for every watch connection (Garmin, health data): the connected
    /// sources as a one-line status. The cards live on the pushed Watches screen.
    /// Always shown, also for local/offline profiles: Garmin and Health both work offline.
    private var watchesRow: some View {
        NavigationLink {
            WatchesScreen(
                garminCloud: garminCloud,
                garminPhoneSync: garminPhoneSync,
                appleWatch: appState.watchSync,
                healthImport: appState.healthImport
            )
                .gymTopBannerInset()
        } label: {
            WatchesRowLabel(
                garminPaired: garminPaired,
                appleWatch: appState.watchSync,
                healthImport: appState.healthImport,
                languageCode: languageCode
            )
        }
        .buttonStyle(.plain)
    }

    /// A Garmin watch is paired for the active account: a confirmed Bluetooth
    /// binding, or the legacy cloud-linked watch when no phone watch is listed.
    private var garminPaired: Bool {
        if garminPhoneSync.devices.isEmpty {
            return garminSelectedCloudDevice(garminCloud) != nil
        }
        return garminPhoneSync.devices.contains { $0.paired }
    }

    private var trainingSettingsSummaryText: String {
        [
            trainingProfile.goal.gymDisplayName,
            trainingProfile.calorieMode.gymDisplayName,
            gymCount(
                trainingProfile.workoutsPerWeek,
                englishOne: "workout",
                englishMany: "workouts",
                ukrainianOne: "тренування",
                ukrainianFew: "тренування",
                ukrainianMany: "тренувань",
                languageCode: languageCode
            ).gymBindingFirstSpace + " " + gymText("a week", "на тиждень", "в неделю", languageCode: languageCode)
        ].joined(separator: "\u{00A0}· ")
    }

    private var isCloudAccount: Bool { auth.session?.cloud != nil }

    private var accountSubtitle: String {
        if auth.session?.cloud != nil {
            return gymText(
                "Workout sync is active.",
                "Синхронізація тренувань активна.",
                "Синхронизация тренировок активна.",
                languageCode: languageCode
            )
        }
        return gymText(
            "Workout data stays on this device.",
            "Дані тренувань залишаються на цьому пристрої.",
            "Данные тренировок остаются на этом устройстве.",
            languageCode: languageCode
        )
    }

    /// Backup & diagnostics keeps its expand/collapse behavior (it holds
    /// several actions, not one navigation target), but its collapsed label
    /// now matches the other settings rows: a regular 17pt title. Its chevron is
    /// drawn by `ProfileDisclosureRowStyle`, so it is the same glyph, weight and
    /// colour as the navigation rows and turns down while the group is open.
    private var backupRow: some View {
        DisclosureGroup(isExpanded: $backupExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        exportBackupButton
                        importBackupButton
                    }
                    VStack(spacing: 10) {
                        exportBackupButton
                        importBackupButton
                    }
                }

                Button {
                    prepareWorkoutPDF()
                } label: {
                    Label(
                        gymText("Share PDF report", "Поділитися PDF звітом", "Поделиться PDF отчетом", languageCode: languageCode),
                        systemImage: "doc.richtext"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(isPreparingWorkoutPDF)
                .accessibilityHint(gymText(
                    "Saves a readable PDF of your newest workouts using the Files picker. It contains private workout details.",
                    "Зберігає читабельний PDF найновіших тренувань через вибір файлу. Містить приватні деталі тренувань.",
                    "Сохраняет читаемый PDF последних тренировок через выбор файла. Содержит личные детали тренировок.",
                    languageCode: languageCode
                ))

                Menu {
                    Button {
                        prepareDiagnosticsJSON()
                    } label: {
                        Label(
                            gymText("Diagnostics JSON", "Діагностика JSON", "Диагностика JSON", languageCode: languageCode),
                            systemImage: "curlybraces"
                        )
                    }

                    Button {
                        prepareDiagnosticsPDF()
                    } label: {
                        Label(
                            gymText("Diagnostics PDF", "Діагностика PDF", "Диагностика PDF", languageCode: languageCode),
                            systemImage: "doc.richtext"
                        )
                    }
                } label: {
                    Label(
                        gymText(
                            "Export diagnostics",
                            "Експортувати діагностику",
                            "Экспортировать диагностику",
                            languageCode: languageCode
                        ),
                        systemImage: "stethoscope"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint(gymText(
                    "Diagnostics contain app metadata and aggregate counts only. They exclude authentication tokens and workout details.",
                    "Діагностика містить лише метадані застосунку та загальні підсумки, без токенів і деталей тренувань.",
                    "Диагностика содержит только метаданные приложения и общие итоги, без токенов и деталей тренировок.",
                    languageCode: languageCode
                ))

                Text(gymText(
                    "Backups contain private workout details. Diagnostics contain only app metadata and aggregate counts.",
                    "Резервні копії містять приватні деталі тренувань. Діагностика — лише метадані та загальні підсумки.",
                    "Резервные копии содержат личные детали тренировок. Диагностика — только метаданные и общие итоги.",
                    languageCode: languageCode
                ))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
        } label: {
            ProfileRowLabel(
                title: gymText(
                    "Backups & diagnostics",
                    "Резервні копії та діагностика",
                    "Резервные копии и диагностика",
                    languageCode: languageCode
                ),
                showsChevron: false
            )
        }
        .disclosureGroupStyle(ProfileDisclosureRowStyle(
            expandedValue: gymText("Expanded", "Розгорнуто", "Развёрнуто", languageCode: languageCode),
            collapsedValue: gymText("Collapsed", "Згорнуто", "Свёрнуто", languageCode: languageCode)
        ))
    }

    private var exportBackupButton: some View {
        Button {
            prepareBackupJSON()
        } label: {
            Label(
                gymText("Export backup", "Експортувати копію", "Экспортировать копию", languageCode: languageCode),
                systemImage: "square.and.arrow.up"
            )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint(gymText(
            "Saves a GymApp JSON backup using the Files picker.",
            "Зберігає резервну копію GymApp JSON через вибір файлу.",
            "Сохраняет резервную копию GymApp JSON через выбор файла.",
            languageCode: languageCode
        ))
    }

    private var importBackupButton: some View {
        Button {
            showsImporter = true
        } label: {
            Label(
                gymText("Import backup", "Імпортувати копію", "Импортировать копию", languageCode: languageCode),
                systemImage: "square.and.arrow.down"
            )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityHint(gymText(
            "Selects a GymApp JSON backup to merge into this profile.",
            "Вибирає резервну копію GymApp JSON для об'єднання з цим профілем.",
            "Выбирает резервную копию GymApp JSON для объединения с этим профилем.",
            languageCode: languageCode
        ))
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case .importBackup:
            return Alert(
                title: Text("Merge this backup?"),
                message: Text("New exercises and sessions will be added to this profile. Matching sessions are skipped; existing data is kept."),
                primaryButton: .default(Text("Merge")) {
                    performPendingImport()
                },
                secondaryButton: .cancel {
                    pendingImportData = nil
                }
            )
        }
    }

    private var diagnosticsContext: ExportService.DiagnosticsContext {
        ExportService.DiagnosticsContext(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? gymLocalized("Unknown"),
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? gymLocalized("Unknown"),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            localeIdentifier: Locale.current.identifier,
            cloudSyncEnabled: isCloudAccount,
            hasSuccessfulSync: appState.cloudSync.lastSyncedAt != nil,
            hasError: appState.cloudSync.lastError != nil
        )
    }

    private func currentDiagnosticsSnapshot() throws -> WorkoutDiagnosticsSnapshot {
        guard appState.isAccountReady,
              store.accountStorageKey == appState.activeAccountStorageKey else {
            throw WorkoutStoreError.storageAccountMismatch
        }
        return store.diagnosticsSnapshot()
    }

    private func prepareBackupJSON() {
        do {
            let data = try appState.exportBackup()
            exportDocument = ProfileExportDocument(data: data)
            exportContentType = .json
            exportFilename = "GymApp-backup"
            showsExporter = true
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func prepareWorkoutPDF() {
        guard !isPreparingWorkoutPDF else { return }
        let lines: [String]
        do {
            guard appState.isAccountReady,
                  store.accountStorageKey == appState.activeAccountStorageKey else {
                throw WorkoutStoreError.storageAccountMismatch
            }
            lines = WorkoutReport.lines(
                exercises: store.exercises,
                sessions: store.workouts,
                languageCode: languageCode
            )
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
            return
        }
        isPreparingWorkoutPDF = true
        let accountKey = store.accountStorageKey
        Task {
            defer { isPreparingWorkoutPDF = false }
            do {
                // Rendering and reading the file stay off the main thread.
                let data = try await Task.detached(priority: .userInitiated) {
                    let pdfURL = try ExportService.writeWorkoutPDF(lines: lines)
                    defer { try? FileManager.default.removeItem(at: pdfURL) }
                    return try Data(contentsOf: pdfURL)
                }.value
                guard appState.isAccountReady,
                      store.accountStorageKey == accountKey,
                      store.accountStorageKey == appState.activeAccountStorageKey else {
                    throw WorkoutStoreError.storageAccountMismatch
                }
                exportDocument = ProfileExportDocument(data: data)
                exportContentType = .pdf
                exportFilename = "GymApp-workouts"
                showsExporter = true
            } catch {
                appState.show(message: gymErrorMessage(error), isError: true)
            }
        }
    }

    private func prepareDiagnosticsJSON() {
        do {
            let data = try ExportService.diagnosticsJSON(
                snapshot: try currentDiagnosticsSnapshot(),
                context: diagnosticsContext
            )
            exportDocument = ProfileExportDocument(data: data)
            exportContentType = .json
            exportFilename = "GymApp-diagnostics"
            showsExporter = true
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func prepareDiagnosticsPDF() {
        do {
            let snapshot = try currentDiagnosticsSnapshot()
            let context = diagnosticsContext
            let accountMode = gymLocalized(isCloudAccount ? "Cloud account" : "Local profile")
            let pdfURL = try ExportService.writeDiagnosticsPDF(sections: [
                (
                    heading: gymLocalized("Application"),
                    lines: [
                        "\(gymLocalized("Version")): \(context.version) (\(context.build))",
                        "\(gymLocalized("System")): \(context.operatingSystemVersion)",
                        "\(gymLocalized("Locale")): \(context.localeIdentifier)",
                        "\(gymLocalized("Account mode")): \(accountMode)"
                    ]
                ),
                (
                    heading: gymLocalized("Workout data"),
                    lines: [
                        "\(gymLocalized("Exercises")): \(snapshot.exerciseCount)",
                        "\(gymLocalized("Workouts")): \(snapshot.workoutCount)",
                        "\(gymLocalized("Sets")): \(snapshot.setCount)",
                        "\(gymLocalized("Manual muscle mappings")): \(snapshot.manualMuscleMappingCount)"
                    ]
                ),
                (
                    heading: gymLocalized("Privacy"),
                    lines: [
                        gymLocalized("No passwords, access tokens, refresh tokens, or Keychain values are included."),
                        gymLocalized("Generated only after an explicit user action.")
                    ]
                )
            ])
            defer { try? FileManager.default.removeItem(at: pdfURL) }
            exportDocument = ProfileExportDocument(data: try Data(contentsOf: pdfURL))
            exportContentType = .pdf
            exportFilename = "GymApp-diagnostics"
            showsExporter = true
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= BackupImportLimits.standard.maximumFileBytes else {
                throw WorkoutStoreError.importLimitExceeded("file size")
            }
            pendingImportData = try BackupFileReader.read(
                from: url,
                maximumBytes: BackupImportLimits.standard.maximumFileBytes
            )
            activeAlert = .importBackup
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func performPendingImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let result = try appState.importBackup(data)
            appState.show(message: importSummary(result), isError: false)
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            appState.show(message: "Export saved.", isError: false)
        case let .failure(error):
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func importSummary(_ result: BackupImportResult) -> String {
        let sessions = gymCount(
            result.importedSessions,
            englishOne: "session",
            englishMany: "sessions",
            ukrainianOne: "тренування",
            ukrainianFew: "тренування",
            ukrainianMany: "тренувань"
        )
        let exercises = gymCount(
            result.addedExercises,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправу",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ"
        )
        let duplicates = gymCount(
            result.skippedDuplicateSessions,
            englishOne: "duplicate",
            englishMany: "duplicates",
            ukrainianOne: "дублікат",
            ukrainianFew: "дублікати",
            ukrainianMany: "дублікатів"
        )
        let invalidSets = gymCount(
            result.ignoredInvalidSets,
            englishOne: "invalid set",
            englishMany: "invalid sets",
            ukrainianOne: "некоректний підхід",
            ukrainianFew: "некоректні підходи",
            ukrainianMany: "некоректних підходів"
        )
        return gymText(
            "\(sessions) imported · \(exercises) added · \(duplicates) skipped · \(invalidSets) ignored",
            "Імпортовано: \(sessions) · додано: \(exercises) · пропущено: \(duplicates) · проігноровано: \(invalidSets)",
            "Импортировано: \(sessions) · добавлено: \(exercises) · пропущено: \(duplicates) · проигнорировано: \(invalidSets)",
            languageCode: gymCurrentLanguageCode()
        )
    }
}

enum BackupFileReader {
    static func read(from url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var result = Data()
        result.reserveCapacity(min(maximumBytes, 256 * 1_024))
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            guard chunk.count <= maximumBytes - result.count else {
                throw WorkoutStoreError.importLimitExceeded("file size")
            }
            result.append(chunk)
        }
        return result
    }
}

/// The Profile "Watches" row label. Observes the Apple Watch and health services
/// itself so the status line follows pairing and import changes live.
private struct WatchesRowLabel: View {
    let garminPaired: Bool
    @ObservedObject var appleWatch: WatchConnectivityService
    @ObservedObject var healthImport: HealthKitImportService
    let languageCode: String

    var body: some View {
        ProfileRowLabel(
            title: gymText("Watches", "Годинники", "Часы", languageCode: languageCode),
            subtitle: WatchesStatus.summary(
                garminPaired: garminPaired,
                appleWatchLinked: appleWatchLinked(appleWatch),
                healthConnected: healthImport.isConnected,
                languageCode: languageCode
            )
        )
    }
}

/// An Apple Watch is paired with this iPhone and has GymApp installed.
@MainActor
private func appleWatchLinked(_ appleWatch: WatchConnectivityService) -> Bool {
    appleWatch.isPaired && appleWatch.isWatchAppInstalled
}

/// Every watch connection on one screen. Order (parity with Android's
/// Garmin · Wear OS · Health data): Garmin, Apple Watch, Health data.
private struct WatchesScreen: View {
    @ObservedObject var garminCloud: GarminCloudService
    @ObservedObject var garminPhoneSync: GarminPhoneSyncService
    @ObservedObject var appleWatch: WatchConnectivityService
    @ObservedObject var healthImport: HealthKitImportService
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    private let garminStoreURL = URL(
        string: "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f"
    )!
    private let connectIQSchemeURL = URL(string: "connectiq://")!
    private let connectIQAppStoreURL = URL(
        string: "https://apps.apple.com/app/connect-iq-store/id1317652970"
    )!
    /// The Garmin watch whose relink (erases its workout data) awaits confirmation.
    @State private var pendingGarminRelinkDeviceID: String?

    var body: some View {
        ScrollViewReader { qaProxy in
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                    garminCard
                    // Hidden when no Apple Watch is paired (like Wear OS on Android
                    // without the Wearable API).
                    if appleWatch.isPaired {
                        appleWatchCard
                    }
                    HealthDataCard(service: healthImport)
                        .id("qa-health")
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
#if DEBUG
        // QA audit (`-qaScroll health|bottom|garmin`): scroll positions for screenshots.
        .task {
            guard let target = QAAuditSeed.scroll else { return }
            try? await Task.sleep(for: .milliseconds(1_500))
            switch target {
            case "health": qaProxy.scrollTo("qa-health", anchor: .top)
            case "bottom": qaProxy.scrollTo("qa-health", anchor: .bottom)
            case "garmin": qaProxy.scrollTo("qa-health", anchor: UnitPoint(x: 0.5, y: 2.2))
            default: break
            }
        }
#endif
        }
        .navigationTitle(gymText("Watches", "Годинники", "Часы", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var garminCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("Garmin", "Garmin", "Garmin", languageCode: languageCode),
                    supporting: gymText(
                        "Plan on the watch, sets and heart rate",
                        "План на годиннику, підходи й пульс",
                        "План на часах, подходы и пульс",
                        languageCode: languageCode
                    )
                )

                if garminPhoneSync.devices.isEmpty && selectedCloudDevice == nil {
                    GymInlineState(
                        gymText(
                            "Connect your Garmin watch to send workouts and keep your results together.",
                            "Підключіть годинник Garmin, щоб надсилати тренування та зберігати результати разом.",
                            "Подключите часы Garmin, чтобы отправлять тренировки и хранить результаты вместе.",
                            languageCode: languageCode
                        ),
                        systemImage: "applewatch"
                    )
                } else {
                    ForEach(garminPhoneSync.devices) { device in
                        garminDeviceRow(
                            name: device.name,
                            detail: device.model,
                            status: device.connected
                                ? gymText("Connected now", "Зараз підключено", "Сейчас подключено", languageCode: languageCode)
                                : gymText("Not connected now", "Зараз не підключено", "Сейчас не подключено", languageCode: languageCode),
                            connected: device.connected,
                            paired: device.paired,
                            note: device.linkedToAnotherAccount
                                ? garminLinkedToAnotherAccountTitle
                                : device.lite
                                ? GarminPhoneSyncProtocol.liteWatchMessage(languageCode: languageCode)
                                : nil,
                            noteIsWarning: device.linkedToAnotherAccount
                        )
                        if device.linkedToAnotherAccount {
                            // The only path to a watch reset: an explicit, confirmed action.
                            Button(role: .destructive) {
                                pendingGarminRelinkDeviceID = device.id
                            } label: {
                                Text(garminRelinkActionTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GymSecondaryButtonStyle(destructive: true))
                        }
                    }
                    if garminPhoneSync.devices.isEmpty, let device = selectedCloudDevice {
                        garminDeviceRow(
                            name: device.displayName,
                            detail: gymText("Garmin cloud watch", "Хмарний годинник Garmin", "Облачные часы Garmin", languageCode: languageCode),
                            status: device.lastSeenAt == nil
                                ? gymText("Waiting for first watch sync", "Очікуємо першу синхронізацію годинника", "Ожидаем первую синхронизацию часов", languageCode: languageCode)
                                : gymText("Recently synchronized with GymApp cloud", "Нещодавно синхронізовано з хмарою GymApp", "Недавно синхронизировано с облаком GymApp", languageCode: languageCode),
                            connected: device.lastSeenAt != nil,
                            paired: false
                        )
                    }
                }

                connectButton

                if let message = garminPhoneSync.statusMessage {
                    GymStatusBanner(message: message, isError: garminPhoneSync.statusIsError)
                }

                Button(action: openGarminStore) {
                    Text(gymText(
                        "Open Gym Workout Tracker in Garmin",
                        "Відкрити Gym Workout Tracker у Garmin",
                        "Открыть Gym Workout Tracker в Garmin",
                        languageCode: languageCode
                    ))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
            }
        }
        .confirmationDialog(
            garminLinkedToAnotherAccountTitle,
            isPresented: Binding(
                get: { pendingGarminRelinkDeviceID != nil },
                set: { if !$0 { pendingGarminRelinkDeviceID = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingGarminRelinkDeviceID
        ) { deviceID in
            Button(garminRelinkActionTitle, role: .destructive) {
                garminPhoneSync.confirmReset(deviceID: deviceID)
            }
            Button(
                gymText("Cancel", "Скасувати", "Отменить", languageCode: languageCode),
                role: .cancel
            ) {}
        } message: { _ in
            Text(gymText(
                "Relinking erases the workout data stored on the watch for that account. Finish and sync any workout on the watch first.",
                "Повторне прив’язування зітре дані тренувань, збережені на годиннику для того акаунта. Спершу завершіть і синхронізуйте тренування на годиннику.",
                "Повторная привязка сотрёт данные тренировок, сохранённые на часах для того аккаунта. Сначала завершите и синхронизируйте тренировку на часах.",
                languageCode: languageCode
            ))
        }
    }

    /// Apple Watch card (parity with Android's Wear OS card). Shown only while a watch
    /// is paired. Pairing belongs to the system, so there is no unlink action here.
    private var appleWatchCard: some View {
        let installed = appleWatchLinked(appleWatch)
        return GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    GymSectionTitle(
                        title: "Apple Watch",
                        supporting: gymText(
                            "Plan on the watch, sets and heart rate",
                            "План на годиннику, підходи та пульс",
                            "План на часах, подходы и пульс",
                            languageCode: languageCode
                        )
                    )
                    Spacer(minLength: 4)
                    if installed {
                        Text(gymText("Paired", "Прив’язано", "Привязано", languageCode: languageCode))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.primary)
                    }
                }
                .accessibilityElement(children: .combine)

                if !installed {
                    GymInlineState(
                        gymText(
                            "Install GymApp on your Apple Watch from the Watch app.",
                            "Встановіть GymApp на Apple Watch у застосунку Watch.",
                            "Установите GymApp на Apple Watch в приложении Watch.",
                            languageCode: languageCode
                        ),
                        systemImage: "applewatch"
                    )
                }
            }
        }
        .id("qa-apple-watch")
    }

    private var garminLinkedToAnotherAccountTitle: String {
        gymText(
            "Watch linked to another account",
            "Годинник прив’язано до іншого акаунта",
            "Часы привязаны к другому аккаунту",
            languageCode: languageCode
        )
    }

    private var garminRelinkActionTitle: String {
        gymText("Relink watch", "Прив’язати заново", "Привязать заново", languageCode: languageCode)
    }

    /// The single connect action: Garmin Connect opens for watch selection and,
    /// on return, the pairing sync is sent right away.
    @ViewBuilder
    private var connectButton: some View {
        let hasWatches = !garminPhoneSync.devices.isEmpty || selectedCloudDevice != nil
        let button = Button {
            garminPhoneSync.selectDevices()
        } label: {
            if garminPhoneSync.isConnecting {
                HStack(spacing: 9) {
                    ProgressView()
                    Text(gymText("Connecting…", "Підключення…", "Подключение…", languageCode: languageCode))
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(gymText("Connect Garmin", "Підключити Garmin", "Подключить Garmin", languageCode: languageCode))
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(garminPhoneSync.isConnecting)
        if hasWatches {
            button.buttonStyle(GymSecondaryButtonStyle())
        } else {
            button.buttonStyle(GymPrimaryButtonStyle())
        }
    }

    private func openGarminStore() {
        let application = UIApplication.shared
        let destination = application.canOpenURL(connectIQSchemeURL)
            ? garminStoreURL
            : connectIQAppStoreURL
        application.open(destination)
    }

    private var selectedCloudDevice: GarminDeviceSummary? { garminSelectedCloudDevice(garminCloud) }

    private func garminDeviceRow(
        name: String,
        detail: String,
        status: String,
        connected: Bool,
        paired: Bool,
        note: String? = nil,
        noteIsWarning: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(connected ? GymTheme.primary : GymTheme.textSecondary)
                .gymScaledFrame(width: 30, relativeTo: .title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(GymTheme.textPrimary)
                // The model line repeats nothing: hidden when it equals the device name.
                if !detail.isEmpty && detail.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) != .orderedSame {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connected ? GymTheme.primary : GymTheme.textSecondary)
                if let note {
                    Text(note)
                        .font(noteIsWarning ? .caption.weight(.semibold) : .caption)
                        .foregroundStyle(noteIsWarning ? GymTheme.error : GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if paired {
                Text(gymText("Paired", "Прив’язано", "Привязано", languageCode: languageCode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.primary)
            }
        }
        // Flat inside the panel: no nested tonal card (card-in-card).
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private func garminSelectedCloudDevice(_ garminCloud: GarminCloudService) -> GarminDeviceSummary? {
    guard let selectedID = garminCloud.selectedDevice?.deviceID else { return nil }
    return garminCloud.availableDevices.first { $0.id == selectedID }
}

/// Friends & live as a pushed screen of Profile. Owns the scroll-to-card
/// handling for notification routes (friend request, workout invite, live room).
private struct ProfileFriendsScreen: View {
    @ObservedObject var appState: AppState
    @ObservedObject var auth: AuthService
    @ObservedObject var liveWorkoutCoordinator: LiveWorkoutCoordinator
    let canAcceptWorkoutInvites: Bool
    let nativePushRequest: NativePushProfileRequest?
    @Binding var fulfilledNativePushRequestID: UUID?
    @Binding var requestedNativePushAccessibilityTarget: NativePushProfileFocus?
    var focusedProfilePushTarget: AccessibilityFocusState<NativePushProfileFocus?>.Binding
    let onOpenAccountSettings: () -> Void
    let onCreateLiveWorkout: (SocialFriendSummary) -> Void
    let onOpenLiveWorkout: () -> Void

    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        appState: AppState,
        auth: AuthService,
        canAcceptWorkoutInvites: Bool,
        liveWorkoutCoordinator: LiveWorkoutCoordinator,
        nativePushRequest: NativePushProfileRequest?,
        fulfilledNativePushRequestID: Binding<UUID?>,
        requestedNativePushAccessibilityTarget: Binding<NativePushProfileFocus?>,
        focusedProfilePushTarget: AccessibilityFocusState<NativePushProfileFocus?>.Binding,
        onOpenAccountSettings: @escaping () -> Void,
        onCreateLiveWorkout: @escaping (SocialFriendSummary) -> Void,
        onOpenLiveWorkout: @escaping () -> Void
    ) {
        self.appState = appState
        self.auth = auth
        self.canAcceptWorkoutInvites = canAcceptWorkoutInvites
        self.liveWorkoutCoordinator = liveWorkoutCoordinator
        self.nativePushRequest = nativePushRequest
        self._fulfilledNativePushRequestID = fulfilledNativePushRequestID
        self._requestedNativePushAccessibilityTarget = requestedNativePushAccessibilityTarget
        self.focusedProfilePushTarget = focusedProfilePushTarget
        self.onOpenAccountSettings = onOpenAccountSettings
        self.onCreateLiveWorkout = onCreateLiveWorkout
        self.onOpenLiveWorkout = onOpenLiveWorkout
    }

    var body: some View {
        ScrollViewReader { proxy in
            GymBackground {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                        FriendsView(
                            appState: appState,
                            auth: auth,
                            canAcceptWorkoutInvites: canAcceptWorkoutInvites,
                            liveWorkoutCoordinator: liveWorkoutCoordinator,
                            nativePushAccessibilityTarget: requestedNativePushAccessibilityTarget,
                            onOpenAccountSettings: onOpenAccountSettings,
                            onCreateLiveWorkout: onCreateLiveWorkout,
                            onOpenLiveWorkout: onOpenLiveWorkout
                        )
                        .id(NativePushProfileFocus.friends)
                        .accessibilityFocused(
                            focusedProfilePushTarget,
                            equals: .friends
                        )
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .task(id: nativePushRequest?.id) {
                guard let nativePushRequest else { return }
                await scrollToNativePushRequest(
                    nativePushRequest,
                    using: proxy,
                    allowFallback: true
                )
            }
            .onChange(of: appState.socialDashboard != nil) { _, _ in
                retryPendingNativePushScroll(using: proxy, allowFallback: true)
            }
            .onChange(of: liveWorkoutCoordinator.inbox) { _, _ in
                retryPendingNativePushScroll(using: proxy, allowFallback: false)
            }
        }
        .navigationTitle(gymText("Friends & live", "Друзі та live", "Друзья и live", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .gymTopBannerInset()
    }

    private func retryPendingNativePushScroll(
        using proxy: ScrollViewProxy,
        allowFallback: Bool
    ) {
        guard let request = nativePushRequest,
              fulfilledNativePushRequestID != request.id else {
            return
        }
        Task { @MainActor in
            await scrollToNativePushRequest(
                request,
                using: proxy,
                allowFallback: allowFallback
            )
        }
    }

    private func scrollToNativePushRequest(
        _ request: NativePushProfileRequest,
        using proxy: ScrollViewProxy,
        allowFallback: Bool
    ) async {
        guard nativePushRequest?.id == request.id,
              fulfilledNativePushRequestID != request.id else {
            return
        }
        await Task.yield()

        let exactAnchor: NativePushProfileFocus?
        switch request.focus {
        case .friends:
            exactAnchor = .friends
        case let .friendRequest(friendshipID):
            exactAnchor = socialFriendshipIsVisible(friendshipID) ? .friendRequest(friendshipID) : nil
        case let .workoutInvite(inviteID):
            exactAnchor = socialWorkoutInviteIsVisible(inviteID) ? .workoutInvite(inviteID) : nil
        case .liveWorkouts:
            exactAnchor = appState.socialDashboard == nil ? nil : .liveWorkouts
        case let .liveRoom(roomID):
            let invitations = liveWorkoutCoordinator.inbox?.invitations ?? []
            let rooms = liveWorkoutCoordinator.inbox?.rooms ?? []
            let roomIsVisible = invitations.contains { $0.roomID == roomID }
                || rooms.contains { $0.roomID == roomID }
            exactAnchor = roomIsVisible ? .liveRoom(roomID) : nil
        }

        if let exactAnchor {
            scroll(proxy, to: exactAnchor)
            requestedNativePushAccessibilityTarget = exactAnchor
            focusedProfilePushTarget.wrappedValue = exactAnchor == .friends ? .friends : nil
            // Let the exact card appear and accept VoiceOver focus before this
            // route is considered fulfilled.
            await Task.yield()
            fulfilledNativePushRequestID = request.id
        } else if allowFallback {
            let fallback: NativePushProfileFocus = appState.socialDashboard == nil
                ? .friends
                : .liveWorkouts
            scroll(proxy, to: fallback)
            requestedNativePushAccessibilityTarget = fallback
            focusedProfilePushTarget.wrappedValue = fallback == .friends ? .friends : nil
            // The parent creates this request only after its bounded authoritative
            // fetch/open attempt finishes. A missing exact object therefore resolves
            // once to the nearest safe surface instead of repeatedly pulling the user
            // back on every later dashboard or inbox refresh.
            await Task.yield()
            fulfilledNativePushRequestID = request.id
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to target: NativePushProfileFocus) {
        switch nativePushScrollBehavior(reduceMotion: reduceMotion) {
        case .animated:
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        case .immediate:
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func socialFriendshipIsVisible(_ friendshipID: String) -> Bool {
        guard let dashboard = appState.socialDashboard else { return false }
        return dashboard.incoming.contains { $0.friendshipID == friendshipID }
            || dashboard.outgoing.contains { $0.friendshipID == friendshipID }
            || dashboard.friends.contains { $0.friendshipID == friendshipID }
    }

    private func socialWorkoutInviteIsVisible(_ inviteID: String) -> Bool {
        guard let inbox = appState.socialWorkoutInbox else { return false }
        return inbox.incoming.contains { $0.inviteID == inviteID }
            || inbox.outgoing.contains { $0.inviteID == inviteID }
    }
}

/// One inset-grouped section of the Profile root: a quiet title over a rounded
/// neutral surface holding the rows.
private struct ProfileGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)
                .padding(.leading, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GymTheme.surface,
                in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
            )
        }
    }
}

/// A Profile row: 17pt regular title, optional one-line status subtitle,
/// optional secondary value on the right, optional chevron.
private struct ProfileRowLabel: View {
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron = true
    var subtitleLineLimit = 1
    var trailingSymbol = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .gymLineLimit(subtitleLineLimit)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(GymTheme.textSecondary)
                    .gymLineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if showsChevron {
                Image(systemName: trailingSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}


private struct ProfileExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Disclosure row of the settings list. The system indicator was drawn larger and in the
/// label colour, so this style draws the chevron the navigation rows use and turns it down
/// while the group is open. The whole label row is the button; VoiceOver reads the state
/// as its value.
private struct ProfileDisclosureRowStyle: DisclosureGroupStyle {
    let expandedValue: String
    let collapsedValue: String

    func makeBody(configuration: Configuration) -> some View {
        ProfileDisclosureRow(
            configuration: configuration,
            expandedValue: expandedValue,
            collapsedValue: collapsedValue
        )
    }
}

private struct ProfileDisclosureRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: DisclosureGroupStyleConfiguration
    let expandedValue: String
    let collapsedValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? expandedValue : collapsedValue)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

/// The verified HealthApp App Store listing ("HealthApp: Recovery & Sleep").
private let healthAppStoreURL = URL(string: "https://apps.apple.com/app/id6831768175")!

/// Short explainer for the owner's other app. The store opens only from the primary
/// button; "Not now" and a swipe-down just close the sheet. A device that cannot open
/// the store fails silently.
private struct HealthAppRecommendationSheet: View {
    let languageCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("HealthApp: Recovery & Sleep")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(gymText(
                    "Your training is only half the story. HealthApp shows how well you recover, so you know when to push and when to rest.",
                    "Тренування — це лише половина справи. HealthApp показує, як ви відновлюєтеся, щоб ви знали, коли навантажувати себе, а коли відпочити.",
                    "Тренировки — это только половина дела. HealthApp показывает, как вы восстанавливаетесь, чтобы вы знали, когда нагружать себя, а когда отдохнуть.",
                    languageCode: languageCode
                ))
                .font(.body)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    benefit("bed.double", gymText(
                        "Sleep and recovery every morning",
                        "Сон і відновлення щоранку",
                        "Сон и восстановление каждое утро",
                        languageCode: languageCode
                    ))
                    benefit("waveform.path.ecg", gymText(
                        "HRV, resting heart rate and readiness",
                        "HRV, пульс спокою та готовність",
                        "HRV, пульс покоя и готовность",
                        languageCode: languageCode
                    ))
                    benefit("chart.line.uptrend.xyaxis", gymText(
                        "Garmin, Oura and Apple Health",
                        "Дані з Garmin, Oura та Apple Health",
                        "Данные из Garmin, Oura и Apple Health",
                        languageCode: languageCode
                    ))
                }
                Text(gymText(
                    "Free · From the developer of GymApp",
                    "Безкоштовно · Від розробника GymApp",
                    "Бесплатно · От разработчика GymApp",
                    languageCode: languageCode
                ))
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)
                VStack(spacing: 10) {
                    Button {
                        UIApplication.shared.open(healthAppStoreURL)
                        dismiss()
                    } label: {
                        Text(gymText(
                            "Open in App Store",
                            "Відкрити в App Store",
                            "Открыть в App Store",
                            languageCode: languageCode
                        ))
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                    Button {
                        dismiss()
                    } label: {
                        Text(gymText("Not now", "Не зараз", "Не сейчас", languageCode: languageCode))
                            .font(.body)
                            .foregroundStyle(GymTheme.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, GymTheme.screenHorizontalInset)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GymTheme.primary)
                .frame(width: 30)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(GymTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
