import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct AccountDeletionConfirmationTarget: Hashable, Identifiable {
    let storageKey: String
    let cloudUserID: String?
    let accountName: String

    init(session: AppAccountSession) {
        storageKey = session.storageKey
        cloudUserID = session.cloud?.userID
        accountName = session.displayName
    }

    var id: String { "\(storageKey)|\(cloudUserID ?? "local")" }
    var isCloudAccount: Bool { cloudUserID != nil }
}

@MainActor
struct AccountSettingsView: View {
    private enum Prompt: Hashable, Identifiable {
        case signOut
        case beginDeletion(AccountDeletionConfirmationTarget)

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var nativePush: NativePushManager

    @State private var prompt: Prompt?
    @State private var deletionConfirmationTarget: AccountDeletionConfirmationTarget?
    @State private var showsPasswordChange = false
    @State private var isSyncing = false
    @State private var isChangingPushSetting = false
    @State private var showsBackupExporter = false
    @State private var backupExportDocument: AccountBackupExportDocument?

    private let showsCloseButton: Bool
    private let hasBlockingLiveWorkout: Bool

    init(
        showsCloseButton: Bool = false,
        hasBlockingLiveWorkout: Bool = false
    ) {
        self.showsCloseButton = showsCloseButton
        self.hasBlockingLiveWorkout = hasBlockingLiveWorkout
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                    accountDetailsCard
                    if isCloudAccount {
                        syncCard
                    } else {
                        backupHintRow
                    }
                    if isCloudAccount {
                        notificationsCard
                    }
                    GarminLegacyCloudSection(
                        garminCloud: appState.garminCloud,
                        isCloudAccount: isCloudAccount
                    )
                    privacyAndSupportCard
                    sessionCard
                    dangerZone
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
        .navigationTitle(
            gymText("Account", "Акаунт", "Аккаунт", languageCode: gymCurrentLanguageCode())
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert(item: $prompt, content: makePrompt)
        .task {
            // The cloud-linked watch card appears only when the account already owns one.
            guard isCloudAccount, !appState.garminCloud.isWorking else { return }
            try? await appState.garminCloud.refreshDevices()
        }
#if DEBUG
        .task {
            // UI-audit: presents the first deletion alert once; "Continue" is never tapped.
            guard UIAuditRouter.shared.consume(.accountDeleteDialog) else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard let session = auth.session else { return }
            prompt = .beginDeletion(AccountDeletionConfirmationTarget(session: session))
        }
#endif
        .sheet(isPresented: $showsPasswordChange) {
            PasswordUpdateView(auth: auth, mode: .signedIn) {
                showsPasswordChange = false
            }
        }
        .sheet(item: $deletionConfirmationTarget) { target in
            NavigationStack {
                AccountDeletionConfirmationView(
                    target: target
                ) {
                    deletionConfirmationTarget = nil
                }
            }
            .environmentObject(appState)
            .gymSheetPresentation(.full)
        }
        .fileExporter(
            isPresented: $showsBackupExporter,
            document: backupExportDocument,
            contentType: .json,
            defaultFilename: "GymApp-backup",
            onCompletion: handleBackupExportCompletion
        )
    }

    /// Icon column width shared by every compact row on this screen, so
    /// titles line up regardless of which SF Symbol a row uses. Mirrors
    /// `ProfileView.settingsRowIconWidth`.
    @ScaledMetric(relativeTo: .title3) private var rowIconWidth: CGFloat = 28
    /// Divider leading inset = icon width + the row's icon/text spacing, so
    /// the divider starts under the title, not under the icon.
    private var rowDividerInset: CGFloat { rowIconWidth + 12 }

    private var rowDivider: some View {
        Divider()
            .overlay(GymTheme.outlineSoft)
            .padding(.leading, rowDividerInset)
    }

    private var accountDetailsCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isCloudAccount ? "person.crop.circle.badge.checkmark" : "iphone")
                        .font(.title2)
                        .foregroundStyle(GymTheme.primary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.session?.displayName ?? gymLocalized("GymApp athlete"))
                            .font(.title3.bold())
                            .foregroundStyle(GymTheme.textPrimary)
                        // Wraps to a second line instead of cutting "… на этом iPho…"; only an email may still scale down.
                        Text(accountSubtitleText)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .gymLineLimit(2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                if let cloud = auth.session?.cloud {
                    CopyableIDRow(label: "User ID", value: cloud.userID)
                } else if case let .local(id, _) = auth.session {
                    CopyableIDRow(label: "Profile ID", value: id)
                }
            }
        }
    }

    private var accountSubtitleText: String {
        if let cloud = auth.session?.cloud {
            return cloud.email
        }
        if case .local = auth.session {
            return gymText(
                "Local profile · this iPhone only",
                "Локальний профіль · лише на цьому iPhone",
                "Локальный профиль · только на этом iPhone",
                languageCode: gymCurrentLanguageCode()
            )
        }
        return gymLocalized("Signed out")
    }

    private var syncCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Cloud sync",
                    supporting: "Workout changes sync automatically while you are signed in."
                )

                detailRow(label: "Status", value: cloudSyncStatusText)
                detailRow(
                    label: "Last synced",
                    value: appState.cloudLastSuccessfulSyncAt.map {
                        gymFormattedTimestamp($0, date: .abbreviated, time: .shortened)
                    } ?? "Not yet"
                )

                if case .failed(let message) = appState.cloudSyncStatus {
                    GymStatusBanner(message: message, isError: true)
                } else if case .conflict = appState.cloudSyncStatus {
                    GymStatusBanner(
                        message: "Workout history changed on more than one device. Choose which complete version to keep.",
                        isError: true
                    )
                }

                Button {
                    syncNow()
                } label: {
                    if isSyncing || appState.cloudSync.isSyncing {
                        HStack(spacing: 9) {
                            ProgressView()
                                .tint(.white)
                            Text("Syncing…")
                        }
                    } else {
                        Label(
                            isRetryableCloudState ? "Retry sync" : "Sync now",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(isSyncing || appState.cloudSync.isSyncing)
                .accessibilityHint(
                    gymText(
                        "Reloads the cloud revision, reconciles changes, and uploads only when safe",
                        "Повторно завантажує хмарну версію, узгоджує зміни й надсилає їх лише тоді, коли це безпечно",
                        "Повторно загружает облачную версию, согласует изменения и отправляет их только тогда, когда это безопасно",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        }
    }

    /// Local-only replacement for the old "Local storage" explanation card:
    /// a single tappable hint row that opens the same backup export action
    /// `ProfileView.prepareBackupJSON()` uses (`appState.exportBackup()`),
    /// via this screen's own `fileExporter`.
    private var backupHintRow: some View {
        GymPanel(contentPadding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)) {
            Button(action: prepareBackupExport) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.title3)
                        .foregroundStyle(GymTheme.primary)
                        .frame(width: rowIconWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            gymText(
                                "Backup",
                                "Резервна копія",
                                "Резервная копия",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GymTheme.textPrimary)
                        Text(
                            gymText(
                                "Make one before switching phones",
                                "Перед зміною телефона",
                                "Перед сменой телефона",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .gymLineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                gymText(
                    "Exports a JSON backup of this profile's workouts using the Files picker",
                    "Експортує JSON-копію тренувань цього профілю через засіб вибору файлів",
                    "Экспортирует JSON-копию тренировок этого профиля через выбор файлов",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
    }

    private func prepareBackupExport() {
        do {
            let data = try appState.exportBackup()
            backupExportDocument = AccountBackupExportDocument(data: data)
            showsBackupExporter = true
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func handleBackupExportCompletion(_ result: Result<URL, Error>) {
        backupExportDocument = nil
        switch result {
        case .success:
            appState.show(
                message: gymText(
                    "Backup saved.",
                    "Резервну копію збережено.",
                    "Резервная копия сохранена.",
                    languageCode: gymCurrentLanguageCode()
                ),
                isError: false
            )
        case .failure(let error):
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private var cloudSyncStatusText: String {
        switch appState.cloudSyncStatus {
        case .idle: "Idle"
        case .checking: "Checking cloud…"
        case .pending: "Changes pending"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .conflict: "Choice required"
        case .failed: "Sync failed"
        }
    }

    private var notificationsCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Friend notifications",
                    supporting: "Receive account-bound friend, workout, and live-workout updates on this device. GymApp validates the current account before showing each notification."
                )

                detailRow(label: "Status", value: pushStatusText)

                if nativePush.permissionState == .denied {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Open notification settings", systemImage: "gear")
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                } else {
                    Button {
                        isChangingPushSetting = true
                        Task {
                            if nativePush.isEnabled {
                                await nativePush.disable()
                            } else {
                                await nativePush.enable()
                            }
                            isChangingPushSetting = false
                        }
                    } label: {
                        if isChangingPushSetting || pushStatusIsWorking {
                            HStack(spacing: 9) {
                                ProgressView()
                                    .tint(nativePush.isEnabled ? GymTheme.primary : .white)
                                Text("Updating…")
                            }
                        } else {
                            Label(
                                nativePush.isEnabled
                                    ? "Turn off notifications"
                                    : "Turn on notifications",
                                systemImage: nativePush.isEnabled ? "bell.slash" : "bell.badge"
                            )
                        }
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .disabled(isChangingPushSetting || pushStatusIsWorking)
                }

                Label(
                    "Notification payloads contain opaque IDs only. Names, workout details, and credentials are not sent through APNs.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pushStatusText: String {
        switch nativePush.status {
        case .disabled: "Off"
        case .requestingPermission: "Requesting permission…"
        case .waitingForDeviceToken: "Waiting for Apple Push Notification service…"
        case .registering: "Securing this device…"
        case .active: "On"
        case .denied: "Blocked in iOS Settings"
        case .unavailable: "Secure device storage unavailable"
        case .revocationPending: "Off — server cleanup will retry"
        case .failed: "Could not register — try again"
        }
    }

    private var pushStatusIsWorking: Bool {
        switch nativePush.status {
        case .requestingPermission, .registering: true
        default: false
        }
    }

    private var isRetryableCloudState: Bool {
        if case .failed = appState.cloudSyncStatus { return true }
        return false
    }

    private var privacyAndSupportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GymPanel(contentPadding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)) {
                VStack(spacing: 0) {
                    linkRow(
                        title: "Privacy policy",
                        systemImage: "hand.raised",
                        destination: GymAppConfiguration.privacyPolicyURL,
                        accessibilityHint: "Opens the GymApp privacy policy in your browser"
                    )
                    rowDivider
                    linkRow(
                        title: "Support",
                        systemImage: "questionmark.circle",
                        destination: GymAppConfiguration.supportURL,
                        accessibilityHint: "Opens GymApp support in your browser"
                    )
                }
            }

            Label("GymApp has no advertising, cross-app tracking, or sale of personal data.", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkRow(
        title: String,
        systemImage: String,
        destination: URL,
        accessibilityHint: String
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(GymTheme.primary)
                    .frame(width: rowIconWidth)
                    .accessibilityHidden(true)
                Text(gymLocalized(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GymTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .gymLineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .accessibilityHint(accessibilityHint)
    }

    private var sessionCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                if isCloudAccount {
                    Button {
                        showsPasswordChange = true
                    } label: {
                        Label(gymLocalized("Change password"), systemImage: "key")
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .accessibilityHint("Opens a form that requires the current password")
                }

                signOutRow

                if hasBlockingLiveWorkout {
                    Label(
                        gymText(
                            "Finish, leave, or cancel the live workout before signing out so queued partner updates are not abandoned.",
                            "Завершіть, покиньте або скасуйте спільне тренування перед виходом, щоб не залишити оновлення для партнера в черзі.",
                            "Завершите, покиньте или отмените совместную тренировку перед выходом, чтобы не оставить обновления для партнёра в очереди.",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Compact row replacing the old "Leave local profile" card's button
    /// (and, for cloud accounts, the old "Sign out" button). Same
    /// confirmation flow (`prompt = .signOut`) and disabled state.
    private var signOutRow: some View {
        Button {
            prompt = .signOut
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                    .foregroundStyle(GymTheme.primary)
                    .frame(width: rowIconWidth)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gymLocalized(signOutRowTitle))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GymTheme.textPrimary)
                    Text(gymLocalized(signOutRowSubtitle))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Asks for confirmation before ending this session")
        .disabled(hasBlockingLiveWorkout)
    }

    private var signOutRowTitle: String {
        isCloudAccount
            ? gymLocalized("Sign out")
            : gymText(
                "Sign out of profile",
                "Вийти з профілю",
                "Выйти из профиля",
                languageCode: gymCurrentLanguageCode()
            )
    }

    /// Cloud keeps its own explanatory copy (`signOutSupportingText`, used
    /// verbatim by the confirmation alert too). Local gets the short row
    /// subtitle called for by design.
    private var signOutRowSubtitle: String {
        if isCloudAccount {
            return signOutSupportingText
        }
        return gymText(
            "Workouts stay on this iPhone",
            "Тренування залишаться на цьому iPhone",
            "Тренировки останутся на этом iPhone",
            languageCode: gymCurrentLanguageCode()
        )
    }

    /// Destructive text row replacing the old filled red button. Same
    /// two-step deletion confirmation flow, unchanged.
    private var dangerZone: some View {
        Button(role: .destructive) {
            guard let session = auth.session else { return }
            prompt = .beginDeletion(
                AccountDeletionConfirmationTarget(session: session)
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text(gymLocalized(isCloudAccount ? "Delete account and data" : "Delete local profile and data"))
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(GymTheme.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts a two-step permanent deletion confirmation")
    }

    private var isCloudAccount: Bool {
        auth.session?.cloud != nil
    }

    private var signOutSupportingText: String {
        if isCloudAccount {
            return gymText(
                "Ends this session without deleting your account or cloud data. Your selected Garmin watch remains paired until you explicitly revoke it.",
                "Завершує цей сеанс без видалення акаунта чи хмарних даних. Вибраний годинник Garmin залишиться прив’язаним, доки доступ не відкликано вручну.",
                "Завершает этот сеанс без удаления аккаунта или облачных данных. Выбранные часы Garmin останутся привязанными, пока доступ не отозван вручную.",
                languageCode: gymCurrentLanguageCode()
            )
        }
        return gymText(
            "Leaves this profile signed out. Its workouts remain on this device and the saved profile can be opened again.",
            "Виходить із цього профілю. Його тренування залишаться на пристрої, а збережений профіль можна буде відкрити знову.",
            "Выходит из этого профиля. Его тренировки останутся на устройстве, а сохранённый профиль можно будет открыть снова.",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(gymLocalized(label))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                Spacer(minLength: 8)
                detailValue(value, monospaced: monospaced)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(gymLocalized(label))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                detailValue(value, monospaced: monospaced)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(gymLocalized(label))
        .accessibilityValue(gymLocalized(value))
    }

    private func detailValue(_ value: String, monospaced: Bool) -> some View {
        Text(gymLocalized(value))
            .font(monospaced ? .caption.monospaced() : .subheadline)
            .foregroundStyle(GymTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func makePrompt(_ prompt: Prompt) -> Alert {
        switch prompt {
        case .signOut:
            return Alert(
                title: Text(gymLocalized(isCloudAccount ? "Sign out of GymApp?" : "Leave this local profile?")),
                message: Text(gymLocalized(signOutSupportingText)),
                primaryButton: .default(Text(gymLocalized(isCloudAccount ? "Sign out" : "Leave profile"))) {
                    Task {
                        if await appState.signOut() {
                            dismiss()
                        }
                    }
                },
                secondaryButton: .cancel()
            )

        case .beginDeletion(let target) where !target.isCloudAccount:
            let languageCode = gymCurrentLanguageCode()
            let name = target.accountName
            return Alert(
                title: Text(gymText(
                    "Delete local profile?",
                    "Видалити локальний профіль?",
                    "Удалить локальный профиль?",
                    languageCode: languageCode
                )),
                message: Text(gymText(
                    "Profile \u{201C}\(name)\u{201D} and its workouts will be removed from this device. This cannot be undone.",
                    "Профіль «\(name)» і його тренування буде видалено з цього пристрою. Цю дію не можна скасувати.",
                    "Профиль «\(name)» и его тренировки будут удалены с этого устройства. Это действие нельзя отменить.",
                    languageCode: languageCode
                )),
                primaryButton: .destructive(Text(gymText(
                    "Delete local profile",
                    "Видалити локальний профіль",
                    "Удалить локальный профиль",
                    languageCode: languageCode
                ))) {
                    Task { @MainActor in
                        deletionConfirmationTarget = target
                    }
                },
                secondaryButton: .cancel(Text(gymText(
                    "Cancel",
                    "Скасувати",
                    "Отмена",
                    languageCode: languageCode
                )))
            )

        case .beginDeletion(let target):
            return Alert(
                title: Text(gymLocalized("Permanently delete this account?")),
                message: Text("This cannot be undone. Export a backup first if you want to retain your workout history."),
                primaryButton: .destructive(Text("Continue")) {
                    Task { @MainActor in
                        deletionConfirmationTarget = target
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func syncNow() {
        guard isCloudAccount, !isSyncing else { return }
        isSyncing = true
        Task {
            await appState.forceCloudSync()
            isSyncing = false
        }
    }
}

/// Backup JSON produced by `appState.exportBackup()`, exported through this
/// screen's own `fileExporter`. Mirrors `ProfileExportDocument` in
/// `ProfileView.swift`, which is `private` to that file and not reusable here.
private struct AccountBackupExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

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

/// Compact "ID + copy" row used by `accountDetailsCard` for the local
/// profile ID and the cloud user ID. Copying briefly confirms in place
/// instead of via a separate alert or toast.
private struct CopyableIDRow: View {
    let label: String
    let value: String

    @State private var copied = false

    var body: some View {
        // At large text the button drops under the identifier so neither label breaks inside a word.
        GymAdaptiveStack(stacksFromLargeText: true, rowAlignment: .firstTextBaseline, spacing: 10, columnSpacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gymLocalized(label))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(gymLocalized(label))
            .accessibilityValue(value)

            GymAdaptiveSpacer(minLength: 8, stacksFromLargeText: true)

            Button(action: copy) {
                Text(
                    copied
                        ? gymText("Copied", "Скопійовано", "Скопировано", languageCode: gymCurrentLanguageCode())
                        : gymText("Copy", "Копіювати", "Скопировать", languageCode: gymCurrentLanguageCode())
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.primary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(GymTheme.primary.opacity(0.12)))
                // The capsule is about 26 pt tall; the tap area reaches 44 pt.
                .gymExpandedTapArea(vertical: 9)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                gymText(
                    "Copies the identifier to the clipboard",
                    "Копіює ідентифікатор у буфер обміну",
                    "Копирует идентификатор в буфер обмена",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
    }

    private func copy() {
        UIPasteboard.general.string = value
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }
}

/// Cloud-linked watches exist only for accounts that registered one before
/// watches connected over Bluetooth. This card is a removal-only legacy surface:
/// it renders only while the signed-in account still has at least one.
enum GarminLegacyCloudCardPolicy {
    static func isVisible(isCloudAccount: Bool, cloudDeviceCount: Int) -> Bool {
        isCloudAccount && cloudDeviceCount > 0
    }
}

@MainActor
private struct GarminLegacyCloudSection: View {
    @ObservedObject var garminCloud: GarminCloudService
    let isCloudAccount: Bool

    var body: some View {
        if GarminLegacyCloudCardPolicy.isVisible(
            isCloudAccount: isCloudAccount,
            cloudDeviceCount: garminCloud.availableDevices.count
        ) {
            GarminLegacyCloudCard(garminCloud: garminCloud)
        }
    }
}

@MainActor
private struct GarminLegacyCloudCard: View {
    @ObservedObject var garminCloud: GarminCloudService

    @State private var errorMessage: String?
    @State private var pendingRemoval: GarminDeviceSummary?

    private var languageCode: String { gymCurrentLanguageCode() }

    var body: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: gymText(
                        "Cloud-linked watches",
                        "Годинники з хмарною прив’язкою",
                        "Часы с облачной привязкой",
                        languageCode: languageCode
                    ),
                    supporting: gymText(
                        "New watches connect over Bluetooth.",
                        "Нові годинники підключаються через Bluetooth.",
                        "Новые часы подключаются по Bluetooth.",
                        languageCode: languageCode
                    )
                )

                if let errorMessage {
                    GymStatusBanner(message: errorMessage, isError: true)
                }

                VStack(spacing: 8) {
                    ForEach(garminCloud.availableDevices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
        .alert(
            gymText(
                "Remove cloud link?",
                "Прибрати хмарну прив’язку?",
                "Убрать облачную привязку?",
                languageCode: languageCode
            ),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { device in
            Button(
                gymText("Remove", "Прибрати", "Убрать", languageCode: languageCode),
                role: .destructive
            ) {
                Task { await remove(device) }
            }
            Button(
                gymText("Cancel", "Скасувати", "Отменить", languageCode: languageCode),
                role: .cancel
            ) {}
        } message: { _ in
            Text(gymText(
                "This removes the watch’s cloud link and discards its pending cloud plans. Connect the watch over Bluetooth in Profile → Watches.",
                "Це прибирає хмарну прив’язку годинника й відхиляє його плани, що очікують у хмарі. Підключіть годинник через Bluetooth: Профіль → Годинники.",
                "Это убирает облачную привязку часов и отклоняет их ожидающие облачные планы. Подключите часы по Bluetooth: Профиль → Часы.",
                languageCode: languageCode
            ))
        }
    }

    private func deviceRow(_ device: GarminDeviceSummary) -> some View {
        let suffix = String(device.id.suffix(8))
        let identifierLabel = gymText(
            "Device …\(suffix)",
            "Пристрій …\(suffix)",
            "Устройство …\(suffix)",
            languageCode: languageCode
        )
        return HStack(spacing: 11) {
            Image(systemName: "applewatch")
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textPrimary)
                Text(identifierLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(GymTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                pendingRemoval = device
            } label: {
                Text(gymText("Remove", "Прибрати", "Убрать", languageCode: languageCode))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GymTheme.error)
            .disabled(garminCloud.isWorking)
            .accessibilityLabel(gymText(
                "Remove cloud link from \(device.displayName)",
                "Прибрати хмарну прив’язку з \(device.displayName)",
                "Убрать облачную привязку у \(device.displayName)",
                languageCode: languageCode
            ))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(GymTheme.surfaceVariant)
        )
    }

    private func remove(_ device: GarminDeviceSummary) async {
        do {
            try await garminCloud.revokeDevice(device)
            errorMessage = nil
        } catch {
            errorMessage = gymErrorMessage(error)
        }
    }
}

@MainActor
private struct AccountDeletionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @FocusState private var confirmationFocused: Bool

    let target: AccountDeletionConfirmationTarget
    let onDeleted: () -> Void

    @State private var confirmation = ""
    @State private var currentPassword = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private static let confirmButtonID = "account-deletion-confirm-button"

    var body: some View {
        GymBackground {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(GymTheme.error)
                        .accessibilityHidden(true)

                    GymSectionTitle(
                        eyebrow: "Final confirmation",
                        title: target.isCloudAccount ? "Delete account and data" : "Delete local profile and data",
                        supporting: confirmationExplanation
                    )

                    GymPanel(highlighted: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(gymLocalized(target.accountName))
                                .font(.headline)
                            Text("Type DELETE exactly to enable permanent deletion.")
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    TextField("DELETE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($confirmationFocused)
                        .gymTextFieldChrome()
                        .accessibilityLabel("Deletion confirmation")
                        .accessibilityHint("Enter the word DELETE in capital letters")

                    if target.isCloudAccount {
                        SecureField("Current password", text: boundedCurrentPassword)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .gymTextFieldChrome()
                            .accessibilityLabel("Current password")
                            .accessibilityHint("Re-enter your current password before permanent deletion")
                    }

                    if let errorMessage {
                        GymStatusBanner(message: errorMessage, isError: true)
                    }

                    Button(role: .destructive) {
                        deleteAccount()
                    } label: {
                        HStack(spacing: 9) {
                            if isDeleting {
                                ProgressView()
                                    .tint(GymTheme.onError)
                            } else {
                                Image(systemName: "trash")
                                    .accessibilityHidden(true)
                            }
                            Text(gymLocalized(isDeleting ? "Deleting…" : finalButtonTitle))
                        }
                        .font(.headline)
                        .foregroundStyle(GymTheme.onError)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(GymTheme.error))
                    }
                    .buttonStyle(.plain)
                    .disabled(!deletionInputIsValid || isDeleting)
                    .opacity(deletionInputIsValid && !isDeleting ? 1 : 0.46)
                    .accessibilityHint("Permanently deletes the current profile and its data")
                    .id(Self.confirmButtonID)

                    Text("Deletion starts only after you press the red button. Closing this screen leaves your account unchanged.")
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            // Keep the red button reachable above the keyboard once the typed
            // word matches; scrolling never submits or deletes anything.
            .onChange(of: deletionInputIsValid) { _, isValid in
                guard isValid else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.confirmButtonID, anchor: .bottom)
                }
            }
            }
        }
        .navigationTitle("Confirm deletion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isDeleting)
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .onAppear { confirmationFocused = true }
        .onDisappear { currentPassword = "" }
    }

    private var boundedCurrentPassword: Binding<String> {
        Binding(
            get: { currentPassword },
            set: { currentPassword = GymLoginPasswordPolicy.boundedDraft($0) }
        )
    }

    private var confirmationMatches: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == "DELETE"
    }

    private var deletionInputIsValid: Bool {
        confirmationMatches && (
            !target.isCloudAccount || (
                !currentPassword.isEmpty && GymLoginPasswordPolicy.accepts(currentPassword)
            )
        )
    }

    private var finalButtonTitle: String {
        target.isCloudAccount ? "Permanently delete account" : "Permanently delete local profile"
    }

    private var confirmationExplanation: String {
        if target.isCloudAccount {
            return "GymApp will ask the authenticated delete-account service to remove your Supabase user, cascade-delete related cloud rows, clear this profile’s local data, and sign you out."
        }
        return "GymApp will erase this profile’s local workout data and sign you out. This action cannot be undone."
    }

    private func deleteAccount() {
        guard deletionInputIsValid, !isDeleting else { return }
        let submittedCurrentPassword = target.isCloudAccount ? currentPassword : nil
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await appState.deleteCurrentAccountAndData(
                    expectedStorageKey: target.storageKey,
                    expectedCloudUserID: target.cloudUserID,
                    currentPassword: submittedCurrentPassword
                )
                isDeleting = false
                currentPassword = ""
                onDeleted()
                dismiss()
            } catch {
                let message = gymErrorMessage(error)
                errorMessage = message
                appState.show(message: message, isError: true)
                isDeleting = false
            }
        }
    }
}
