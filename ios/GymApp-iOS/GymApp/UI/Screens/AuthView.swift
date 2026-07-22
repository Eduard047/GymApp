import SwiftUI

@MainActor
public struct AuthView: View {
    @ObservedObject private var authService: AuthService

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var repeatedEmail = ""
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var displayName = ""
    @State private var passwordVisible = false
    @State private var repeatedPasswordVisible = false
    @State private var localMessage: String?
    @State private var showOfflineSheet = false
    @State private var offlineDisplayName = ""
    @State private var offlineMessage: String?

    @FocusState private var focusedField: AuthField?

    init(authService: AuthService) {
        self.authService = authService
    }

    public var body: some View {
        GymBackground {
            ScrollView {
                VStack(spacing: 16) {
                    brandHeader
                    authPanel
                    legalLinks
                }
                .frame(maxWidth: 580)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showOfflineSheet) {
            offlineSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .topTrailing) {
            AppLanguageMenu()
                .padding(.top, 8)
                .padding(.trailing, 16)
                .accessibilitySortPriority(2)
        }
        .onChange(of: mode) { _, _ in
            localMessage = nil
            authService.message = nil
            focusedField = .email
        }
    }

    private var brandHeader: some View {
        GymHeroPanel {
            HStack(alignment: .center, spacing: 16) {
                GymBrandMark(size: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("GymApp")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Build strength with focus and consistency.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var authPanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 16) {
                GymSectionTitle(
                    eyebrow: "Secure account",
                    title: authService.pendingConfirmationEmail == nil
                        ? (mode == .signIn ? "Welcome back" : "Create account")
                        : (authService.pendingConfirmationEmailWasSent
                            ? "Check your email"
                            : "Confirm your email first, then sign in."),
                    supporting: authService.pendingConfirmationEmail == nil
                        ? (mode == .signIn
                            ? "Sign in to keep workouts synchronized across your devices."
                            : "Create a cloud account, then confirm your email to start syncing.")
                        : (authService.pendingConfirmationEmailWasSent
                            ? "We sent a confirmation link to the address below. Open the newest email from GymApp and tap “Confirm email”. Then return to GymApp and sign in."
                            : "Confirm your email first, then sign in.")
                )

                if let pendingEmail = authService.pendingConfirmationEmail {
                    emailConfirmationCard(email: pendingEmail)
                } else {
                Picker("Account action", selection: $mode) {
                    ForEach(AuthMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Switch between signing in and creating an account")

                VStack(alignment: .leading, spacing: 13) {
                    emailField

                    if mode == .signUp {
                        repeatedEmailField
                        displayNameField
                    }

                    passwordField(
                        title: "Password",
                        text: $password,
                        isVisible: $passwordVisible,
                        field: .password,
                        contentType: mode == .signIn ? .password : .newPassword,
                        submitLabel: mode == .signIn ? .go : .next
                    )

                    if mode == .signUp {
                        passwordField(
                            title: "Repeat password",
                            text: $repeatedPassword,
                            isVisible: $repeatedPasswordVisible,
                            field: .repeatedPassword,
                            contentType: .newPassword,
                            submitLabel: .go
                        )
                    }

                    if mode == .signUp {
                        Text("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.")
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let localMessage {
                    GymStatusBanner(message: localMessage, isError: true)
                } else if let message = authService.message {
                    GymStatusBanner(message: message, isError: authService.messageIsError)
                }

                Button(action: submit) {
                    HStack(spacing: 9) {
                        if authService.isLoading {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        }
                        Text(authService.isLoading ? gymLocalized("Please wait…") : mode.submitTitle)
                    }
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(authService.isLoading)
                .accessibilityHint(
                    gymLocalized(
                        mode == .signIn
                            ? "Signs in to your cloud account"
                            : "Creates a cloud account"
                    )
                )

                secondaryAccountActions
                }

                Divider()
                    .overlay(GymTheme.outline.opacity(0.5))

                Button {
                    localMessage = nil
                    offlineMessage = nil
                    showOfflineSheet = true
                } label: {
                    Label("Continue offline", systemImage: "iphone")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(authService.isLoading)

                Text("Offline workouts stay on this device until you export them. You can switch to a cloud account later.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Email")
            TextField("you@example.com", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit {
                    focusedField = mode == .signUp ? .repeatedEmail : .password
                }
                .gymTextFieldChrome()
                .accessibilityLabel("Email")
        }
    }

    private var repeatedEmailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Repeat email")
            TextField("you@example.com", text: $repeatedEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .repeatedEmail)
                .onSubmit { focusedField = .displayName }
                .gymTextFieldChrome()
                .accessibilityLabel("Repeat email")
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Display name")
            TextField("Athlete", text: $displayName)
                .textContentType(.nickname)
                .submitLabel(.next)
                .focused($focusedField, equals: .displayName)
                .onSubmit { focusedField = .password }
                .gymTextFieldChrome()
                .accessibilityLabel("Display name")
            Text("2–32 characters: letters, numbers, spaces, dot, dash or underscore.")
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
        }
    }

    private func passwordField(
        title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        field: AuthField,
        contentType: UITextContentType,
        submitLabel: SubmitLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title)
            HStack(spacing: 8) {
                Group {
                    if isVisible.wrappedValue {
                        TextField(gymLocalized(title), text: text)
                    } else {
                        SecureField(gymLocalized(title), text: text)
                    }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focusedField, equals: field)
                .onSubmit {
                    if field == .password, mode == .signUp {
                        focusedField = .repeatedPassword
                    } else {
                        submit()
                    }
                }

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityLabel(
                    gymText(
                        isVisible.wrappedValue ? "Hide \(title.lowercased())" : "Show \(title.lowercased())",
                        isVisible.wrappedValue
                            ? "Сховати поле «\(gymLocalized(title).lowercased())»"
                            : "Показати поле «\(gymLocalized(title).lowercased())»",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
            .gymTextFieldChrome()
        }
    }

    @ViewBuilder
    private var secondaryAccountActions: some View {
        if mode == .signIn {
            Button("Forgot password?") {
                requestPasswordReset()
            }
            .font(.subheadline.weight(.semibold))
            .disabled(authService.isLoading)
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("After creating the account, we will show where the confirmation email was sent.")
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func emailConfirmationCard(email pendingEmail: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GymTheme.primary)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(authService.pendingConfirmationEmailWasSent ? "Confirmation link sent to" : "Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                    Text(pendingEmail)
                        .font(.headline)
                        .foregroundStyle(GymTheme.textPrimary)
                        .textSelection(.enabled)
                }
            }

            if authService.pendingConfirmationEmailWasSent {
                Text("If you cannot find it, check your Spam folder.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
            }

            if let localMessage {
                GymStatusBanner(message: localMessage, isError: true)
            } else if let message = authService.message {
                GymStatusBanner(message: message, isError: authService.messageIsError)
            }

            Button(authService.pendingConfirmationEmailWasSent ? "Send email again" : "Send confirmation email") {
                localMessage = nil
                focusedField = nil
                Task { await authService.resendConfirmation(email: pendingEmail) }
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(authService.isLoading)

            Button("Use a different address") {
                email = pendingEmail
                repeatedEmail = ""
                password = ""
                repeatedPassword = ""
                localMessage = nil
                mode = .signUp
                authService.dismissEmailConfirmation(clearPendingRequest: true)
                focusedField = .email
            }
            .buttonStyle(GymSecondaryButtonStyle())
            .disabled(authService.isLoading)

            Button("Back to sign in") {
                email = pendingEmail
                password = ""
                localMessage = nil
                mode = .signIn
                authService.dismissEmailConfirmation(clearPendingRequest: false)
                focusedField = .email
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .disabled(authService.isLoading)
        }
        .padding(16)
        .background(GymTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(GymTheme.primary.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var legalLinks: some View {
        GymPanel(contentPadding: EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)) {
            VStack(spacing: 9) {
                Text("By using GymApp, you agree that workout data is handled as described in the privacy policy.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 22) {
                        privacyLink
                        supportLink
                    }
                    VStack(spacing: 10) {
                        privacyLink
                        supportLink
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var privacyLink: some View {
        Link(destination: GymAppConfiguration.privacyPolicyURL) {
            Label("Privacy Policy", systemImage: "hand.raised")
        }
        .accessibilityHint("Opens the privacy policy in your browser")
    }

    private var supportLink: some View {
        Link(destination: GymAppConfiguration.supportURL) {
            Label("Support", systemImage: "questionmark.circle")
        }
        .accessibilityHint("Opens GymApp support in your browser")
    }

    private var offlineSheet: some View {
        GymBackground {
            ScrollView {
                VStack(spacing: 16) {
                    GymHeroPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Offline mode", systemImage: "iphone")
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text("Create a local profile without signing in. Protected cloud progress and multi-device sync will remain unavailable.")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GymPanel(highlighted: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            fieldLabel("Display name")
                            TextField("Local Athlete", text: $offlineDisplayName)
                                .textContentType(.nickname)
                                .submitLabel(.done)
                                .gymTextFieldChrome()
                                .onSubmit(continueOffline)

                            if let offlineMessage {
                                GymStatusBanner(message: offlineMessage, isError: true)
                            }

                            Button(action: continueOffline) {
                                Text("Start offline")
                            }
                            .buttonStyle(GymPrimaryButtonStyle())

                            Button("Cancel") {
                                showOfflineSheet = false
                            }
                            .buttonStyle(GymSecondaryButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(gymLocalized(title))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GymTheme.textPrimary)
    }

    private func submit() {
        guard !authService.isLoading else { return }
        localMessage = validationMessage()
        guard localMessage == nil else { return }

        focusedField = nil
        authService.message = nil
        Task {
            switch mode {
            case .signIn:
                await authService.signIn(email: email, password: password)
            case .signUp:
                _ = await authService.signUp(email: email, password: password, displayName: displayName)
            }
        }
    }

    private func requestPasswordReset() {
        localMessage = validEmail(email) ? nil : gymLocalized("Enter a valid email address first.")
        guard localMessage == nil else { return }
        focusedField = nil
        Task { await authService.requestPasswordReset(email: email) }
    }

    private func resendConfirmation() {
        localMessage = validEmail(email) ? nil : gymLocalized("Enter a valid email address first.")
        guard localMessage == nil else { return }
        focusedField = nil
        Task { await authService.resendConfirmation(email: email) }
    }

    private func continueOffline() {
        do {
            try authService.continueOffline(displayName: offlineDisplayName)
            offlineMessage = nil
            showOfflineSheet = false
        } catch {
            offlineMessage = gymErrorMessage(error)
        }
    }

    private func validationMessage() -> String? {
        guard validEmail(email) else { return gymLocalized("Enter a valid email address.") }
        guard !password.isEmpty else { return gymLocalized("Enter your password.") }

        if mode == .signUp {
            let cleanEmail = normalizedEmail(email)
            guard cleanEmail == normalizedEmail(repeatedEmail) else { return gymLocalized("Email addresses do not match.") }
            guard validPassword(password) else {
                return gymLocalized(GymPasswordPolicy.errorMessage)
            }
            guard password == repeatedPassword else { return gymLocalized("Passwords do not match.") }

            let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...32).contains(cleanName.count) else { return gymLocalized("Display name must be 2–32 characters.") }
        }
        return nil
    }

    private func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validEmail(_ value: String) -> Bool {
        let clean = normalizedEmail(value)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return clean.count <= 254 && clean.range(of: pattern, options: .regularExpression) != nil
    }

    private func validPassword(_ value: String) -> Bool {
        GymPasswordPolicy.accepts(value)
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: Self { self }
    var title: String { gymLocalized(self == .signIn ? "Sign in" : "Sign up") }
    var submitTitle: String { gymLocalized(self == .signIn ? "Sign in" : "Create account") }
}

private enum AuthField: Hashable {
    case email
    case repeatedEmail
    case displayName
    case password
    case repeatedPassword
}
