import SwiftUI

@MainActor
struct PasswordUpdateView: View {
    @ObservedObject var auth: AuthService
    let onDone: () -> Void

    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var reveal = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        GymHeroPanel {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("Choose a new password", systemImage: "key.fill")
                                    .font(.title2.bold())
                                Text("Your recovery link was verified. Set a new password for this account.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.84))
                            }
                        }

                        GymPanel(highlighted: true) {
                            VStack(alignment: .leading, spacing: 14) {
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

                                Text("Use 8–72 characters with at least one letter and one number.")
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
                                        Text("Update password")
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
            .navigationTitle("Password recovery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(auth.needsPasswordUpdate)
    }

    private func updatePassword() {
        localError = nil
        guard password == repeatedPassword else {
            localError = "Passwords do not match."
            return
        }
        guard (8...72).contains(password.count),
              password.contains(where: \.isLetter),
              password.contains(where: \.isNumber) else {
            localError = "Password must be 8–72 characters and include letters and numbers."
            return
        }
        Task {
            await auth.updatePassword(password)
            if !auth.needsPasswordUpdate { onDone() }
        }
    }
}
