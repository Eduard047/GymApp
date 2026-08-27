import SwiftUI

enum PasswordUpdateMode: Equatable {
    case recovery
    case signedIn

    var requiresCurrentPassword: Bool { self == .signedIn }

    func title(languageCode: String) -> String {
        switch self {
        case .recovery:
            gymText(
                "Choose a new password",
                "Створи новий пароль",
                "Создай новый пароль",
                languageCode: languageCode
            )
        case .signedIn:
            gymText(
                "Change your password",
                "Зміни пароль",
                "Измени пароль",
                languageCode: languageCode
            )
        }
    }

    func supportingText(languageCode: String) -> String {
        switch self {
        case .recovery:
            gymText(
                "Your recovery link was verified. Set a new password for this account.",
                "Посилання для відновлення підтверджено. Встанови новий пароль для цього акаунта.",
                "Ссылка для восстановления подтверждена. Установи новый пароль для этого аккаунта.",
                languageCode: languageCode
            )
        case .signedIn:
            gymText(
                "Enter your current password, then choose a new password for this account.",
                "Введи поточний пароль, а потім вибери новий пароль для цього акаунта.",
                "Введи текущий пароль, а затем выбери новый пароль для этого аккаунта.",
                languageCode: languageCode
            )
        }
    }

    func navigationTitle(languageCode: String) -> String {
        switch self {
        case .recovery:
            gymText(
                "Password recovery",
                "Відновлення пароля",
                "Восстановление пароля",
                languageCode: languageCode
            )
        case .signedIn:
            gymText(
                "Change password",
                "Змінити пароль",
                "Изменить пароль",
                languageCode: languageCode
            )
        }
    }
}

struct PasswordUpdateCredentialDrafts: Equatable {
    var currentPassword = ""
    var verificationCode = ""
    var password = ""
    var repeatedPassword = ""

    mutating func clearSensitiveFields() {
        currentPassword = ""
        verificationCode = ""
        password = ""
        repeatedPassword = ""
    }
}

@MainActor
struct PasswordUpdateView: View {
    @ObservedObject var auth: AuthService
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    let mode: PasswordUpdateMode
    let onDone: () -> Void

    @State private var drafts = PasswordUpdateCredentialDrafts()
    @State private var reveal = false
    @State private var localError: String?

    init(
        auth: AuthService,
        mode: PasswordUpdateMode = .recovery,
        onDone: @escaping () -> Void
    ) {
        self.auth = auth
        self.mode = mode
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        GymHeroPanel {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(mode.title(languageCode: languageCode), systemImage: "key.fill")
                                    .font(.title2.bold())
                                Text(supportingText)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.84))
                            }
                        }

                        GymPanel(highlighted: true) {
                            VStack(alignment: .leading, spacing: 14) {
                                if mode.requiresCurrentPassword {
                                    Group {
                                        if reveal {
                                            TextField(
                                                "Current password",
                                                text: boundedPasswordBinding($drafts.currentPassword)
                                            )
                                        } else {
                                            SecureField(
                                                "Current password",
                                                text: boundedPasswordBinding($drafts.currentPassword)
                                            )
                                        }
                                    }
                                    .textContentType(.password)
                                    .gymTextFieldChrome()
                                }

                                if showsVerificationCode {
                                    TextField("Verification code", text: $drafts.verificationCode)
                                        .textContentType(.oneTimeCode)
                                        .keyboardType(.numberPad)
                                        .gymTextFieldChrome()
                                        .onChange(of: drafts.verificationCode) { value in
                                            let bounded = String(value.prefix(8))
                                            if bounded != value {
                                                drafts.verificationCode = bounded
                                            }
                                        }
                                }

                                Group {
                                    if reveal {
                                        TextField(
                                            "New password",
                                            text: boundedPasswordBinding($drafts.password)
                                        )
                                        TextField(
                                            "Repeat password",
                                            text: boundedPasswordBinding($drafts.repeatedPassword)
                                        )
                                    } else {
                                        SecureField(
                                            "New password",
                                            text: boundedPasswordBinding($drafts.password)
                                        )
                                        SecureField(
                                            "Repeat password",
                                            text: boundedPasswordBinding($drafts.repeatedPassword)
                                        )
                                    }
                                }
                                .textContentType(.newPassword)
                                .gymTextFieldChrome()

                                Toggle("Show passwords", isOn: $reveal)

                                Text("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.")
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.textSecondary)

                                if let message = localError ?? auth.message {
                                    GymStatusBanner(
                                        message: gymLocalized(message, languageCode: languageCode),
                                        isError: localError != nil || auth.messageIsError
                                    )
                                }

                                Button {
                                    updatePassword()
                                } label: {
                                    if auth.isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(gymText(
                                            mode == .recovery ? "Update password" : "Change password",
                                            mode == .recovery ? "Оновити пароль" : "Змінити пароль",
                                            mode == .recovery ? "Обновить пароль" : "Изменить пароль",
                                            languageCode: languageCode
                                        ))
                                    }
                                }
                                .buttonStyle(GymPrimaryButtonStyle())
                                .disabled(auth.isLoading)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(mode.navigationTitle(languageCode: languageCode))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(auth.needsPasswordUpdate)
        .onDisappear(perform: clearSensitiveDrafts)
    }

    private func boundedPasswordBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = GymLoginPasswordPolicy.boundedDraft($0) }
        )
    }

    private var showsVerificationCode: Bool {
        mode == .signedIn && auth.passwordChangeRequiresNonce
    }

    private var supportingText: String {
        if showsVerificationCode {
            return gymText(
                "A verification code was sent to your email. Enter it together with the new password.",
                "Код підтвердження надіслано на твою електронну пошту. Введи його разом із новим паролем.",
                "Код подтверждения отправлен на твою электронную почту. Введи его вместе с новым паролем.",
                languageCode: languageCode
            )
        }
        return mode.supportingText(languageCode: languageCode)
    }

    private func updatePassword() {
        localError = nil
        if mode.requiresCurrentPassword && drafts.currentPassword.isEmpty {
            localError = gymText(
                "Enter your current password.",
                "Введи поточний пароль.",
                "Введи текущий пароль.",
                languageCode: languageCode
            )
            return
        }
        if mode.requiresCurrentPassword,
           !GymLoginPasswordPolicy.accepts(drafts.currentPassword) {
            localError = gymLocalized(
                GymLoginPasswordPolicy.currentPasswordErrorMessage,
                languageCode: languageCode
            )
            return
        }
        guard drafts.password == drafts.repeatedPassword else {
            localError = gymLocalized(
                "Passwords do not match.",
                languageCode: languageCode
            )
            return
        }
        guard GymPasswordPolicy.accepts(drafts.password) else {
            localError = gymLocalized(
                GymPasswordPolicy.errorMessage,
                languageCode: languageCode
            )
            return
        }
        let nonce: String?
        if showsVerificationCode {
            guard let normalized = PasswordReauthenticationNoncePolicy.normalized(
                drafts.verificationCode
            ) else {
                localError = gymLocalized(
                    PasswordReauthenticationNoncePolicy.errorMessage,
                    languageCode: languageCode
                )
                return
            }
            nonce = normalized
        } else {
            nonce = nil
        }
        let submittedPassword = drafts.password
        let submittedCurrentPassword = mode.requiresCurrentPassword
            ? drafts.currentPassword
            : nil
        Task {
            let updated = await auth.updatePassword(
                submittedPassword,
                currentPassword: submittedCurrentPassword,
                nonce: nonce
            )
            if updated {
                clearSensitiveDrafts()
                onDone()
            }
        }
    }

    private func clearSensitiveDrafts() {
        drafts.clearSensitiveFields()
        reveal = false
    }
}
