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
                    header

                    if let message = appState.statusMessage {
                        GymStatusBanner(message: message, isError: appState.statusIsError)
                    }

                    accountDetailsCard
                    syncCard
                    if isCloudAccount {
                        notificationsCard
                    }
                    if isCloudAccount {
                        GarminSettingsCard(
                            garminCloud: appState.garminCloud,
                            garminPhoneSync: appState.garminPhoneSync
                        )
                    }
                    privacyAndSupportCard
                    sessionCard
                    dangerZone
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
        .navigationTitle("Account settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert(item: $prompt, content: makePrompt)
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
        }
    }

    private var header: some View {
        GymScreenHeader(
            title: "Account & privacy"
        )
    }

    private var accountDetailsCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isCloudAccount ? "person.crop.circle.badge.checkmark" : "iphone")
                        .font(.title2)
                        .foregroundStyle(GymTheme.primary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.session?.displayName ?? gymLocalized("GymApp athlete"))
                            .font(.title3.bold())
                            .foregroundStyle(GymTheme.textPrimary)
                        Text(gymLocalized(isCloudAccount ? "Supabase cloud account" : "Local-only profile"))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                    }

                    Spacer(minLength: 4)
                    GymInfoPill(
                        isCloudAccount ? "Cloud" : "On device",
                        systemImage: isCloudAccount ? "icloud" : "internaldrive"
                    )
                }

                Divider()

                if let cloud = auth.session?.cloud {
                    detailRow(label: "Email", value: cloud.email)
                    detailRow(label: "User ID", value: cloud.userID, monospaced: true)
                    detailRow(label: "Storage", value: "Encrypted local cache + Supabase cloud")
                } else if case let .local(id, _) = auth.session {
                    detailRow(label: "Profile ID", value: id, monospaced: true)
                    detailRow(label: "Storage", value: "This device only")
                } else {
                    detailRow(label: "Status", value: "Signed out")
                }
            }
        }
    }

    private var syncCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: isCloudAccount ? "Cloud sync" : "Local storage",
                    supporting: isCloudAccount
                        ? "Workout changes sync automatically while you are signed in."
                        : "This profile keeps workouts on this device and does not synchronize protected progress."
                )

                if isCloudAccount {
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
                } else {
                    GymInlineState(
                        gymText(
                            "Use Export backup on the Profile screen before replacing or resetting this device.",
                            "Перед заміною або скиданням пристрою скористайтеся експортом резервної копії на екрані профілю.",
                            "Перед заменой или сбросом устройства воспользуйтесь экспортом резервной копии на экране профиля.",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "externaldrive"
                    )
                }
            }
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
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Privacy and support"
                )

                Link(destination: GymAppConfiguration.privacyPolicyURL) {
                    Label("Privacy policy", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens the GymApp privacy policy in your browser")

                Link(destination: GymAppConfiguration.supportURL) {
                    Label("Support", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens GymApp support in your browser")

                Label("GymApp has no advertising, cross-app tracking, or sale of personal data.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: isCloudAccount ? "Sign out" : "Leave local profile",
                    supporting: signOutSupportingText
                )

                if isCloudAccount {
                    Button {
                        showsPasswordChange = true
                    } label: {
                        Label(gymLocalized("Change password"), systemImage: "key")
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .accessibilityHint("Opens a form that requires the current password")
                }

                Button {
                    prompt = .signOut
                } label: {
                    Label(
                        gymLocalized(isCloudAccount ? "Sign out" : "Return to sign in"),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Asks for confirmation before ending this session")
                .disabled(hasBlockingLiveWorkout)

                if hasBlockingLiveWorkout {
                    Label(
                        gymText(
                            "Finish, leave, or cancel the live workout before signing out so queued partner updates are not abandoned.",
                            "Заверши, покинь або скасуй живе тренування перед виходом, щоб не залишити оновлення для партнера в черзі.",
                            "Заверши, покинь или отмени живую тренировку перед выходом, чтобы не оставить обновления для партнёра в очереди.",
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

    private var dangerZone: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    title: isCloudAccount ? "Delete account" : "Delete local profile"
                )

                Button(role: .destructive) {
                    guard let session = auth.session else { return }
                    prompt = .beginDeletion(
                        AccountDeletionConfirmationTarget(session: session)
                    )
                } label: {
                    Label(
                        gymLocalized(isCloudAccount ? "Delete account and data" : "Delete local profile and data"),
                        systemImage: "trash"
                    )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                            .fill(GymTheme.error)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts a two-step permanent deletion confirmation")

            }
        }
    }

    private var isCloudAccount: Bool {
        auth.session?.cloud != nil
    }

    private var signOutSupportingText: String {
        if isCloudAccount {
            return gymText(
                "Ends this session without deleting your account or cloud data. Your selected Garmin watch remains paired until you explicitly revoke it.",
                "Завершує цей сеанс без видалення акаунта чи хмарних даних. Вибраний годинник Garmin залишиться прив’язаним, доки ти не відкличеш його вручну.",
                "Завершает этот сеанс без удаления аккаунта или облачных данных. Выбранные часы Garmin останутся привязанными, пока ты не отзовёшь их вручную.",
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

        case .beginDeletion(let target):
            return Alert(
                title: Text(gymLocalized(target.isCloudAccount ? "Permanently delete this account?" : "Permanently delete this local profile?")),
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

private struct GarminTokenPresentation: Identifiable {
    let credential: GarminPairingCredential
    let canRevoke: Bool

    var id: String { credential.id }
}

@MainActor
private struct GarminSettingsCard: View {
    @ObservedObject var garminCloud: GarminCloudService
    @ObservedObject var garminPhoneSync: GarminPhoneSyncService

    @State private var displayName = gymLocalized("Garmin watch")
    @State private var errorMessage: String?
    @State private var tokenPresentation: GarminTokenPresentation?
    private let garminStoreURL = URL(
        string: "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f"
    )!
    private let connectIQSchemeURL = URL(string: "connectiq://")!
    private let connectIQAppStoreURL = URL(
        string: "https://apps.apple.com/app/connect-iq-store/id1317652970"
    )!
    @State private var showsRevokeConfirmation = false

    var body: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Paired watches",
                    supporting: "Choose exactly which active watch receives iOS workout plans. The selected device is stored securely for this Supabase account."
                )

                Button(action: openGarminStore) {
                    Label("Open Gym Workout Tracker in Garmin", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens this app in Connect IQ, or opens the App Store if Connect IQ is not installed")

                Button {
                    garminPhoneSync.selectDevices()
                } label: {
                    Label("Connect this iPhone to Garmin", systemImage: "iphone.and.arrow.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .accessibilityHint("Opens Garmin Connect so you can choose which paired watches may send completed workouts to this iPhone")

                if let message = garminPhoneSync.statusMessage {
                    GymStatusBanner(message: message, isError: garminPhoneSync.statusIsError)
                }

                if !garminPhoneSync.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Direct iPhone connection")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                        ForEach(garminPhoneSync.devices) { device in
                            HStack(spacing: 9) {
                                Image(systemName: device.connected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        device.connected ? GymTheme.primary : GymTheme.textSecondary
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(device.model)
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.textSecondary)
                                }
                                Spacer()
                                Text(device.connected ? "Connected" : "Offline")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        device.connected ? GymTheme.primary : GymTheme.textSecondary
                                    )
                            }
                            .padding(11)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: GymTheme.controlCornerRadius,
                                    style: .continuous
                                )
                                .fill(GymTheme.surfaceVariant)
                            )
                        }
                    }
                }

                if let errorMessage {
                    GymStatusBanner(message: errorMessage, isError: true)
                }

                if garminCloud.availableDevices.isEmpty {
                    Label(
                        garminCloud.isWorking ? "Loading Garmin watches…" : "No active Garmin watches found.",
                        systemImage: "applewatch"
                    )
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(garminCloud.availableDevices) { device in
                            deviceButton(device)
                        }
                    }
                }

                Button {
                    Task { await refreshDevices() }
                } label: {
                    Label("Refresh watches", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(garminCloud.isWorking)

                Divider()

                if garminCloud.selectedDevice != nil {
                    Button {
                        Task { await rotateToken() }
                    } label: {
                        Label("Rotate token for selected watch", systemImage: "key.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .disabled(garminCloud.isWorking)

                    Text("Use token rotation to reconnect the same watch. It preserves the device ID already pinned by the Garmin app.")
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive) {
                        showsRevokeConfirmation = true
                    } label: {
                        Label("Revoke selected watch", systemImage: "applewatch")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .disabled(garminCloud.isWorking)
                }

                Divider()

                TextField("Watch name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .gymTextFieldChrome()
                    .accessibilityHint("A label up to 80 characters for a new Garmin watch")

                Button {
                    Task { await createNewDevice() }
                } label: {
                    if garminCloud.isWorking {
                        HStack(spacing: 9) {
                            ProgressView().tint(.white)
                            Text("Pairing…")
                        }
                    } else {
                        Label("Pair a brand-new watch", systemImage: "plus.circle")
                    }
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(garminCloud.isWorking || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Create a new device ID only for a watch that has never used GymApp cloud sync. For an existing watch, select it above or rotate its token.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await refreshDevices() }
        .sheet(item: $tokenPresentation, onDismiss: { tokenPresentation = nil }) { presentation in
            NavigationStack {
                GarminTokenView(
                    presentation: presentation,
                    selectedDeviceID: garminCloud.selectedDevice?.deviceID,
                    revoke: { try await garminCloud.revokeSelectedDevice() },
                    onClose: { tokenPresentation = nil }
                )
            }
        }
        .alert("Revoke selected Garmin watch?", isPresented: $showsRevokeConfirmation) {
            Button("Revoke", role: .destructive) {
                Task { await revokeSelectedDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This invalidates the watch token and quarantines its pending plans. Reusing this watch with a new device ID requires resetting GymApp on the watch. Use token rotation instead when reconnecting the same watch.")
        }
    }

    private func openGarminStore() {
        let application = UIApplication.shared
        let destination = application.canOpenURL(connectIQSchemeURL)
            ? garminStoreURL
            : connectIQAppStoreURL
        application.open(destination)
    }

    private func deviceButton(_ device: GarminDeviceSummary) -> some View {
        let selected = garminCloud.selectedDevice?.deviceID == device.id
        let identifierSuffix = String(device.id.suffix(8))
        let identifierLabel: String
        let deviceAccessibilityLabel: String
        switch gymCurrentLanguageCode() {
        case AppLanguage.ukrainian.rawValue:
            identifierLabel = "Пристрій …\(identifierSuffix)"
            deviceAccessibilityLabel = "\(device.displayName), останні символи ідентифікатора пристрою: \(identifierSuffix)"
        case AppLanguage.russian.rawValue:
            identifierLabel = "Устройство …\(identifierSuffix)"
            deviceAccessibilityLabel = "\(device.displayName), последние символы идентификатора устройства: \(identifierSuffix)"
        default:
            identifierLabel = "Device …\(identifierSuffix)"
            deviceAccessibilityLabel = "\(device.displayName), device ending \(identifierSuffix)"
        }
        return Button {
            do {
                try garminCloud.selectDevice(device)
                errorMessage = nil
            } catch {
                errorMessage = gymErrorMessage(error)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? GymTheme.primary : GymTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textPrimary)
                    Text(identifierLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(GymTheme.textSecondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(selected ? GymTheme.primary.opacity(0.1) : GymTheme.surfaceVariant)
        )
        .disabled(garminCloud.isWorking)
        .accessibilityLabel(deviceAccessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func refreshDevices() async {
        guard !garminCloud.isWorking else { return }
        do {
            try await garminCloud.refreshDevices()
            errorMessage = nil
        } catch {
            errorMessage = gymErrorMessage(error)
        }
    }

    private func createNewDevice() async {
        do {
            let credential = try await garminCloud.createDevice(displayName: displayName)
            tokenPresentation = GarminTokenPresentation(
                credential: credential,
                canRevoke: true
            )
            errorMessage = nil
        } catch {
            errorMessage = gymErrorMessage(error)
        }
    }

    private func rotateToken() async {
        do {
            let credential = try await garminCloud.rotateSelectedDeviceToken()
            tokenPresentation = GarminTokenPresentation(
                credential: credential,
                canRevoke: false
            )
            errorMessage = nil
        } catch {
            errorMessage = gymErrorMessage(error)
        }
    }

    private func revokeSelectedDevice() async {
        do {
            try await garminCloud.revokeSelectedDevice()
            errorMessage = nil
        } catch {
            errorMessage = gymErrorMessage(error)
        }
    }
}

@MainActor
private struct GarminTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let presentation: GarminTokenPresentation
    let selectedDeviceID: String?
    let revoke: () async throws -> Void
    let onClose: () -> Void

    @State private var showsCopyWarning = false
    @State private var copied = false
    @State private var isRevoking = false
    @State private var errorMessage: String?

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GymSectionTitle(
                        eyebrow: "One-time secret",
                        title: "Save the Garmin token now",
                        supporting: "Paste this token only into GymApp settings in Garmin Connect IQ. It will not be stored or shown again."
                    )

                    if let errorMessage {
                        GymStatusBanner(message: errorMessage, isError: true)
                    }

                    GymPanel(highlighted: true) {
                        Text(presentation.credential.deviceToken)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(GymTheme.textPrimary)
                            .privacySensitive()
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("One-time Garmin pairing token")
                    }

                    Button {
                        showsCopyWarning = true
                    } label: {
                        Label(copied ? "Copied for 5 minutes" : "Copy token", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                    .disabled(isRevoking)

                    Text("Copying is optional and requires confirmation. The clipboard item stays on this device and expires after five minutes, but another app opened during that time may be able to read it.")
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("I saved the token") { close() }
                        .buttonStyle(GymSecondaryButtonStyle())
                        .disabled(isRevoking)

                    if presentation.canRevoke {
                        Button(role: .destructive) {
                            revokeAndClose()
                        } label: {
                            if isRevoking {
                                ProgressView("Revoking…")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Cancel and revoke this new watch", systemImage: "xmark.shield")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(GymSecondaryButtonStyle())
                        .disabled(isRevoking)
                    } else {
                        Button("Close without saving") { close() }
                            .buttonStyle(GymSecondaryButtonStyle())
                            .disabled(isRevoking)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Garmin pairing")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .alert("Copy this secret token?", isPresented: $showsCopyWarning) {
            Button("Copy for 5 minutes") { copyToken() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only continue if you will paste it directly into this watch’s Garmin Connect IQ settings. Do not send or save it elsewhere.")
        }
        .onChange(of: selectedDeviceID) { currentID in
            if currentID != presentation.credential.id { close() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { close() }
        }
    }

    private func copyToken() {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: presentation.credential.deviceToken]],
            options: [
                UIPasteboard.OptionsKey.localOnly: true,
                UIPasteboard.OptionsKey.expirationDate: Date().addingTimeInterval(5 * 60)
            ]
        )
        copied = true
    }

    private func revokeAndClose() {
        guard !isRevoking else { return }
        isRevoking = true
        Task {
            do {
                try await revoke()
                clearMatchingClipboard()
                close()
            } catch {
                errorMessage = gymErrorMessage(error)
                isRevoking = false
            }
        }
    }

    private func clearMatchingClipboard() {
        if UIPasteboard.general.string == presentation.credential.deviceToken {
            UIPasteboard.general.items = []
        }
    }

    private func close() {
        onClose()
        dismiss()
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

    var body: some View {
        GymBackground {
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
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash")
                                    .accessibilityHidden(true)
                            }
                            Text(gymLocalized(isDeleting ? "Deleting…" : finalButtonTitle))
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                                .fill(GymTheme.error)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!deletionInputIsValid || isDeleting)
                    .opacity(deletionInputIsValid && !isDeleting ? 1 : 0.46)
                    .accessibilityHint("Permanently deletes the current profile and its data")

                    Text("Deletion starts only after you press the red button. Closing this screen leaves your account unchanged.")
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
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
