import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct AccountSettingsView: View {
    private enum Prompt: Hashable, Identifiable {
        case signOut
        case beginDeletion

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService

    @State private var prompt: Prompt?
    @State private var showsDeletionConfirmation = false
    @State private var isSyncing = false

    private let showsCloseButton: Bool

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header

                    if let message = appState.statusMessage {
                        GymStatusBanner(message: message, isError: appState.statusIsError)
                    }

                    accountDetailsCard
                    syncCard
                    if isCloudAccount {
                        GarminSettingsCard(garminCloud: appState.garminCloud)
                    }
                    privacyAndSupportCard
                    sessionCard
                    dangerZone
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 30)
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
        .sheet(isPresented: $showsDeletionConfirmation) {
            NavigationStack {
                AccountDeletionConfirmationView(
                    isCloudAccount: isCloudAccount,
                    accountName: auth.session?.displayName ?? "this profile"
                ) {
                    showsDeletionConfirmation = false
                }
            }
            .environmentObject(appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Account & privacy")
                .font(.largeTitle.bold())
                .foregroundStyle(GymTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Manage sync, support, your session, and permanent data deletion.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    eyebrow: "Data",
                    title: isCloudAccount ? "Cloud sync" : "Local storage",
                    supporting: isCloudAccount
                        ? "Workout changes sync automatically while you are signed in."
                        : "This profile keeps workouts on this device and does not synchronize protected progress."
                )

                if isCloudAccount {
                    detailRow(
                        label: "Last synced",
                        value: appState.cloudSync.lastSyncedAt.map {
                            gymFormattedDate($0, date: .abbreviated, time: .shortened)
                        } ?? "Not yet"
                    )

                    if let lastError = appState.cloudSync.lastError {
                        GymStatusBanner(message: lastError, isError: true)
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
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                    .disabled(isSyncing || appState.cloudSync.isSyncing)
                    .accessibilityHint("Uploads the current workout backup and profile statistics")
                } else {
                    Label("Use Export backup on the Exercises screen before replacing or resetting this device.", systemImage: "externaldrive")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacyAndSupportCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    eyebrow: "Help & legal",
                    title: "Privacy and support",
                    supporting: "Review what GymApp stores or open troubleshooting and contact information."
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
                    eyebrow: "Session",
                    title: isCloudAccount ? "Sign out" : "Leave local profile",
                    supporting: signOutSupportingText
                )

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
            }
        }
    }

    private var dangerZone: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    eyebrow: "Danger zone",
                    title: isCloudAccount ? "Delete account" : "Delete local profile",
                    supporting: deletionSupportingText
                )

                Button(role: .destructive) {
                    prompt = .beginDeletion
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

                Text("You will first confirm the warning, then type DELETE before anything is removed.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isCloudAccount: Bool {
        auth.session?.cloud != nil
    }

    private var signOutSupportingText: String {
        if isCloudAccount {
            return "Ends this session without deleting your account or cloud data. Your selected Garmin watch remains paired until you explicitly revoke it."
        }
        return "Local profiles cannot be selected again after leaving. Export a backup first if you want to keep this data."
    }

    private var deletionSupportingText: String {
        if isCloudAccount {
            return "Permanently removes this Supabase account, cloud workout state, protected-progress profile, Garmin connection data, and this profile’s local workout store."
        }
        return "Permanently removes this profile’s exercises, workouts, notes, mappings, and local timers from this device."
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
                        appState.restTimers.cancelAll()
                        await auth.signOut()
                        dismiss()
                    }
                },
                secondaryButton: .cancel()
            )

        case .beginDeletion:
            return Alert(
                title: Text(gymLocalized(isCloudAccount ? "Permanently delete this account?" : "Permanently delete this local profile?")),
                message: Text("This cannot be undone. Export a backup first if you want to retain your workout history."),
                primaryButton: .destructive(Text("Continue")) {
                    Task { @MainActor in
                        showsDeletionConfirmation = true
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
                    eyebrow: "Garmin",
                    title: "Paired watches",
                    supporting: "Choose exactly which active watch receives iOS workout plans. The selected device is stored securely for this Supabase account."
                )

                Button(action: openGarminStore) {
                    Label("Open Gym Workout Tracker in Garmin", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .accessibilityHint("Opens this app in Connect IQ, or opens the App Store if Connect IQ is not installed")

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
        .onChange(of: selectedDeviceID) { _, currentID in
            if currentID != presentation.credential.id { close() }
        }
        .onChange(of: scenePhase) { _, phase in
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

    let isCloudAccount: Bool
    let accountName: String
    let onDeleted: () -> Void

    @State private var confirmation = ""
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
                        title: isCloudAccount ? "Delete account and data" : "Delete local profile and data",
                        supporting: confirmationExplanation
                    )

                    GymPanel(highlighted: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(gymLocalized(accountName))
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
                    .disabled(!confirmationMatches || isDeleting)
                    .opacity(confirmationMatches && !isDeleting ? 1 : 0.46)
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
    }

    private var confirmationMatches: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == "DELETE"
    }

    private var finalButtonTitle: String {
        isCloudAccount ? "Permanently delete account" : "Permanently delete local profile"
    }

    private var confirmationExplanation: String {
        if isCloudAccount {
            return "GymApp will ask the authenticated delete-account service to remove your Supabase user, cascade-delete related cloud rows, clear this profile’s local data, and sign you out."
        }
        return "GymApp will erase this profile’s local workout data and sign you out. This action cannot be undone."
    }

    private func deleteAccount() {
        guard confirmationMatches, !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await appState.deleteCurrentAccountAndData()
                isDeleting = false
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
