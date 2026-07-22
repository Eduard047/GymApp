import SwiftUI

enum PasswordUpdateMode: Equatable {
    case recovery
    case signedIn

    var requiresCurrentPassword: Bool { self == .signedIn }

    var title: String {
        switch self {
        case .recovery: "Choose a new password"
        case .signedIn: "Change your password"
        }
    }

    var supportingText: String {
        switch self {
        case .recovery: "Your recovery link was verified. Set a new password for this account."
        case .signedIn: "Enter your current password, then choose a new password for this account."
        }
    }

    var navigationTitle: String {
        switch self {
        case .recovery: "Password recovery"
        case .signedIn: "Change password"
        }
    }
}

@MainActor
struct PasswordUpdateView: View {
    @ObservedObject var auth: AuthService
    let mode: PasswordUpdateMode
    let onDone: () -> Void

    @State private var currentPassword = ""
    @State private var password = ""
    @State private var repeatedPassword = ""
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
                                Label(mode.title, systemImage: "key.fill")
                                    .font(.title2.bold())
                                Text(mode.supportingText)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.84))
                            }
                        }

                        GymPanel(highlighted: true) {
                            VStack(alignment: .leading, spacing: 14) {
                                if mode.requiresCurrentPassword {
                                    Group {
                                        if reveal {
                                            TextField("Current password", text: $currentPassword)
                                        } else {
                                            SecureField("Current password", text: $currentPassword)
                                        }
                                    }
                                    .textContentType(.password)
                                    .gymTextFieldChrome()
                                }

                                Group {
                                    if reveal {
                                        TextField("New password", text: $password)
                                        TextField("Repeat password", text: $repeatedPassword)
                                    } else {
                                        SecureField("New password", text: $password)
                                        SecureField("Repeat password", text: $repeatedPassword)
                                    }
                                }
                                .textContentType(.newPassword)
                                .gymTextFieldChrome()

                                Toggle("Show passwords", isOn: $reveal)

                                Text("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.")
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.textSecondary)

                                if let message = localError ?? auth.message {
                                    GymStatusBanner(message: message, isError: localError != nil || auth.messageIsError)
                                }

                                Button {
                                    updatePassword()
                                } label: {
                                    if auth.isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(mode == .recovery ? "Update password" : "Change password")
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
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(auth.needsPasswordUpdate)
    }

    private func updatePassword() {
        localError = nil
        if mode.requiresCurrentPassword && currentPassword.isEmpty {
            localError = "Enter your current password."
            return
        }
        guard password == repeatedPassword else {
            localError = "Passwords do not match."
            return
        }
        guard GymPasswordPolicy.accepts(password) else {
            localError = GymPasswordPolicy.errorMessage
            return
        }
        Task {
            let updated = await auth.updatePassword(
                password,
                currentPassword: mode.requiresCurrentPassword ? currentPassword : nil
            )
            if updated { onDone() }
        }
    }
}
