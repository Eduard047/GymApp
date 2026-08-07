import CryptoKit
import Foundation
import Security

enum GymAppConfiguration {
    private static let invalidURL = URL(fileURLWithPath: "/invalid-gymapp-configuration")

    static let supabaseURL = URL(string: "https://owrcbsrectdgaotndtxy.supabase.co") ?? invalidURL
    // A Supabase publishable key is intentionally public. Authorization is enforced by RLS.
    static let supabasePublishableKey = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
    static let authCallbackBase = "com.setforge.gymapp.ios://auth/callback"
    static let authWebCallbackURL = URL(string: "https://gymapptracker.com/confirmed.html") ?? invalidURL
    static let privacyPolicyURL = URL(string: "https://gymapptracker.com/privacy-policy.html") ?? invalidURL
    static let supportURL = URL(string: "https://gymapptracker.com/support.html") ?? invalidURL
}

enum AuthCallbackPurpose: String, Sendable {
    case signup
    case recovery
}

enum AuthCallbackRouting {
    private static let rawTokenKeys = [
        "access_token",
        "refresh_token",
        "id_token",
        "provider_token",
        "provider_refresh_token"
    ]

    static func webRedirectURL(state: String, purpose: AuthCallbackPurpose) -> String {
        var components = URLComponents(
            url: GymAppConfiguration.authWebCallbackURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "purpose", value: purpose.rawValue)
        ]
        return components?.url?.absoluteString ?? GymAppConfiguration.authWebCallbackURL.absoluteString
    }

    static func percentEncodedQueryValue(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func callbackValues(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach {
            result[$0.name] = $0.value
        }
        if let fragment = url.fragment {
            URLComponents(string: "?\(fragment)")?.queryItems?.forEach {
                result[$0.name] = $0.value
            }
        }
        return result
    }

    static func isAuthDestination(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "com.setforge.gymapp.ios", url.host?.lowercased() == "auth" {
            return true
        }
        return scheme == "https"
            && url.host?.lowercased() == "gymapptracker.com"
            && url.path == "/confirmed.html"
    }

    static func isExpectedCallback(
        _ url: URL,
        state: String,
        values: [String: String]
    ) -> Bool {
        guard !rawTokenKeys.contains(where: { values[$0]?.isEmpty == false }) else {
            return false
        }

        if url.scheme?.lowercased() == "com.setforge.gymapp.ios" {
            return url.host?.lowercased() == "auth"
                && url.pathComponents == ["/", "callback", state]
        }

        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "gymapptracker.com"
            && url.path == "/confirmed.html"
            && values["platform"] == "ios"
            && values["state"] == state
    }
}

struct CloudAccountSession: Codable, Equatable, Sendable {
    var userID: String
    var email: String
    var displayName: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

private struct PendingAuthTransaction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case signup
        case recovery
    }

    let state: String
    let codeVerifier: String
    let email: String
    let kind: Kind
    let createdAt: Date
    var confirmationEmailSentAt: Date?

    var redirectURL: String {
        AuthCallbackRouting.webRedirectURL(
            state: state,
            purpose: kind == .recovery ? .recovery : .signup
        )
    }

    var isFresh: Bool {
        createdAt.timeIntervalSinceNow > -(24 * 60 * 60)
    }

    var confirmationEmailWasSent: Bool {
        confirmationEmailSentAt != nil
    }
}

private struct PersistedAuthState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let session: AppAccountSession
    let requiresPasswordUpdate: Bool

    init(session: AppAccountSession, requiresPasswordUpdate: Bool) {
        self.version = Self.currentVersion
        self.session = session
        self.requiresPasswordUpdate = requiresPasswordUpdate
    }
}

enum AppAccountSession: Codable, Equatable, Sendable {
    case local(id: String, displayName: String)
    case cloud(CloudAccountSession)

    var storageKey: String {
        switch self {
        case .local(let id, _): return "local_\(id.safeStorageComponent)"
        case .cloud(let session): return "cloud_\(session.userID.safeStorageComponent)"
        }
    }

    var displayName: String {
        switch self {
        case .local(_, let displayName): return displayName
        case .cloud(let session): return session.displayName
        }
    }

    var cloud: CloudAccountSession? {
        guard case .cloud(let value) = self else { return nil }
        return value
    }
}

enum AuthServiceError: LocalizedError {
    case invalidEmail
    case invalidPassword
    case invalidPasswordReauthenticationNonce
    case passwordReauthenticationRequired
    case invalidDisplayName
    case malformedResponse
    case callbackMissingSession
    case callbackNotExpected
    case notCloudAccount
    case sessionChanged
    case sessionExpired
    case requestFailed(status: Int, message: String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a valid email address."
        case .invalidPassword: return GymPasswordPolicy.errorMessage
        case .invalidPasswordReauthenticationNonce:
            return PasswordReauthenticationNoncePolicy.errorMessage
        case .passwordReauthenticationRequired:
            return "A verification code is required to change this password."
        case .invalidDisplayName: return "Display name must be 2–32 characters and use letters, numbers, spaces, dot, dash or underscore."
        case .malformedResponse: return "The cloud returned an invalid response. Try again."
        case .callbackMissingSession: return "The confirmation link did not contain a valid session."
        case .callbackNotExpected: return "This sign-in link was not requested on this device or has expired. Start the flow again."
        case .notCloudAccount: return "This action requires a cloud account."
        case .sessionChanged: return "The account changed while the request was running. Try again."
        case .sessionExpired: return "Your session expired. Sign in again."
        case .requestFailed(_, let message): return message
        case .server(let message): return message
        }
    }
}

enum AccountDeletionRequestDisposition: Equatable {
    case notDispatched
    case outcomeUnknown
    case definitivelyRejected
}

enum GymPasswordPolicy {
    static let errorMessage = "Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol."

    private static let supportedSymbols = CharacterSet(
        charactersIn: "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~"
    )

    static func accepts(_ password: String) -> Bool {
        let scalars = password.unicodeScalars
        return scalars.count >= 12
            && password.utf8.count <= 72
            && scalars.contains(where: { (97...122).contains($0.value) })
            && scalars.contains(where: { (65...90).contains($0.value) })
            && scalars.contains(where: { (48...57).contains($0.value) })
            && scalars.contains(where: { supportedSymbols.contains($0) })
    }
}

enum PasswordReauthenticationNoncePolicy {
    static let errorMessage = "Enter the 6–8 digit verification code from your email."

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6 ... 8).contains(trimmed.utf8.count),
              trimmed.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AppAccountSession?
    @Published private(set) var isLoading = false
    @Published var message: String?
    @Published private(set) var messageIsError = true
    @Published private(set) var pendingConfirmationEmail: String?
    @Published private(set) var pendingConfirmationEmailWasSent = false
    @Published private(set) var needsPasswordUpdate = false
    @Published private(set) var passwordChangeRequiresNonce = false

    private let keychain: any KeychainStoring
    private let urlSession: URLSession
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let sessionAccount = "current-session"
    private let authTransactionAccount = "pending-auth-transaction"
    private var sessionRevision: UInt64 = 0
    private var cloudRefreshTask: Task<CloudAccountSession, Error>?
    private var cloudRefreshIdentity: CloudRefreshIdentity?
    private var cloudRefreshGeneration: UInt64 = 0

    private struct CloudRefreshIdentity: Equatable {
        let sessionRevision: UInt64
        let userID: String
        let refreshToken: String
    }

    private static let pendingSecureDeletionKey = "gymapp.auth.pending-secure-session-deletion"
    private static let maximumAuthResponseBytes = 64 * 1_024
    private static let maximumAuthErrorResponseBytes = 8 * 1_024
    private static let maximumAuthRequestBytes = 64 * 1_024
    private static let maximumAuthCallbackURLBytes = 8 * 1_024
    private static let maximumTokenBytes = 16 * 1_024
    private static let maximumAuthorizationCodeBytes = 4 * 1_024

    init(
        keychain: any KeychainStoring = KeychainStore(),
        urlSession: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.urlSession = urlSession
        self.defaults = defaults

        if defaults.bool(forKey: Self.pendingSecureDeletionKey) {
            var cleanupFailed = false
            do {
                try keychain.delete(account: sessionAccount)
            } catch {
                cleanupFailed = true
            }
            do {
                try keychain.delete(account: authTransactionAccount)
            } catch {
                cleanupFailed = true
            }
            if cleanupFailed {
                self.session = nil
                self.message = "Secure sign-out cleanup is incomplete. Retry sign-in or restart after unlocking this device."
            } else {
                defaults.removeObject(forKey: Self.pendingSecureDeletionKey)
                self.session = nil
            }
        } else if let data = try? keychain.read(account: sessionAccount) {
            if let persisted = try? decoder.decode(PersistedAuthState.self, from: data),
               persisted.version == PersistedAuthState.currentVersion {
                self.session = persisted.session
                self.needsPasswordUpdate = persisted.requiresPasswordUpdate
                    && persisted.session.cloud != nil
            } else if let legacySession = try? decoder.decode(AppAccountSession.self, from: data) {
                // Released builds stored the raw session. Restore it safely and
                // migrate on the next successful persistence operation.
                self.session = legacySession
                self.needsPasswordUpdate = false
            }
        }

        if session == nil, !defaults.bool(forKey: Self.pendingSecureDeletionKey) {
            restorePendingSignupTransaction()
        }
    }

    func signIn(email: String, password: String) async {
        var submittedEmail: String?
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            submittedEmail = cleanEmail
            guard !password.isEmpty else { throw AuthServiceError.invalidPassword }
            let object = try await self.requestJSON(
                path: "/auth/v1/token?grant_type=password",
                method: "POST",
                body: ["email": cleanEmail, "password": password]
            )
            let cloud = try self.parseCloudSession(object)
            try self.persist(.cloud(cloud), requiresPasswordUpdate: false)
            self.message = nil
        }
        if session == nil,
           message == "Confirm your email first, then sign in.",
           let submittedEmail {
            do {
                // Do not automatically request another email here. Supabase limits
                // confirmation sends, and a matching link may already be in flight.
                // Preserve its verifier so that opening that link still completes PKCE.
                let transaction = try reusableSignupTransaction(for: submittedEmail)
                pendingConfirmationEmail = submittedEmail
                pendingConfirmationEmailWasSent = transaction.confirmationEmailWasSent
                messageIsError = false
                message = nil
            } catch {
                messageIsError = true
                message = friendlyMessage(error)
            }
        }
    }

    /// Returns true when Supabase immediately created a session; false means email confirmation is pending.
    @discardableResult
    func signUp(email: String, password: String, displayName: String) async -> Bool {
        var signedIn = false
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            try self.validatePassword(password)
            let cleanName = try self.validatedDisplayName(displayName, fallbackEmail: cleanEmail)
            let transaction = try self.reusableAuthTransaction(
                for: cleanEmail,
                kind: .signup
            )
            do {
                let redirect = AuthCallbackRouting.percentEncodedQueryValue(transaction.redirectURL)
                let object = try await self.requestJSON(
                    path: "/auth/v1/signup?redirect_to=\(redirect)",
                    method: "POST",
                    body: [
                        "email": cleanEmail,
                        "password": password,
                        "data": ["display_name": cleanName],
                        "code_challenge": Self.codeChallenge(for: transaction.codeVerifier),
                        "code_challenge_method": "s256"
                    ]
                )
                if let token = object["access_token"] as? String, !token.isEmpty {
                    let cloud = try self.parseCloudSession(object)
                    try self.persist(.cloud(cloud), requiresPasswordUpdate: false)
                    try self.clearPendingAuthTransaction()
                    signedIn = true
                    self.message = nil
                } else {
                    let sentTransaction = try self.markConfirmationEmailSent(transaction)
                    self.pendingConfirmationEmail = cleanEmail
                    self.pendingConfirmationEmailWasSent = sentTransaction.confirmationEmailWasSent
                    self.messageIsError = false
                    self.message = "Account created. Check your email, then return to GymApp."
                }
            } catch {
                if Self.authDeliveryOutcomeMayBeUnknown(error) {
                    // A timeout, lost response or malformed success can happen after
                    // Supabase sent the email. Keep the matching PKCE verifier so
                    // that link remains usable and an explicit resend reuses it.
                    self.pendingConfirmationEmail = cleanEmail
                    self.pendingConfirmationEmailWasSent = transaction.confirmationEmailWasSent
                } else {
                    try? self.clearPendingAuthTransaction()
                }
                throw error
            }
        }
        return signedIn
    }

    func resendConfirmation(email: String) async {
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            guard let transaction = try self.pendingAuthTransaction(),
                  transaction.kind == .signup,
                  transaction.email == cleanEmail,
                  transaction.isFresh else {
                throw AuthServiceError.callbackNotExpected
            }
            let redirect = AuthCallbackRouting.percentEncodedQueryValue(transaction.redirectURL)
            _ = try await self.requestJSON(
                path: "/auth/v1/resend?redirect_to=\(redirect)",
                method: "POST",
                body: [
                    "type": "signup",
                    "email": cleanEmail,
                    "code_challenge": Self.codeChallenge(for: transaction.codeVerifier),
                    "code_challenge_method": "s256"
                ]
            )
            _ = try self.markConfirmationEmailSent(transaction)
            self.pendingConfirmationEmailWasSent = true
            self.messageIsError = false
            self.message = "Confirmation email sent. Check inbox and spam."
        }
    }

    func dismissEmailConfirmation(clearPendingRequest: Bool) {
        if clearPendingRequest {
            try? clearPendingAuthTransaction()
        }
        pendingConfirmationEmail = nil
        pendingConfirmationEmailWasSent = false
        message = nil
        messageIsError = false
    }

    func requestPasswordReset(email: String) async {
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            let transaction = try self.reusableAuthTransaction(
                for: cleanEmail,
                kind: .recovery
            )
            do {
                let redirect = AuthCallbackRouting.percentEncodedQueryValue(transaction.redirectURL)
                _ = try await self.requestJSON(
                    path: "/auth/v1/recover?redirect_to=\(redirect)",
                    method: "POST",
                    body: [
                        "email": cleanEmail,
                        "code_challenge": Self.codeChallenge(for: transaction.codeVerifier),
                        "code_challenge_method": "s256"
                    ]
                )
                self.messageIsError = false
                self.message = "Password reset email sent. Open the newest email on this iPhone, then tap Open GymApp to choose a new password."
            } catch {
                if !Self.authDeliveryOutcomeMayBeUnknown(error) {
                    try? self.clearPendingAuthTransaction()
                }
                throw error
            }
        }
    }

    @discardableResult
    func updatePassword(
        _ password: String,
        currentPassword: String? = nil,
        nonce: String? = nil
    ) async -> Bool {
        var updated = false
        await perform {
            try self.validatePassword(password)
            let cloud = try await self.validCloudSession()
            var body: [String: Any] = ["password": password]
            let isSignedInChange = currentPassword != nil
            if let currentPassword {
                guard !currentPassword.isEmpty else { throw AuthServiceError.invalidPassword }
                body["current_password"] = currentPassword
            }

            let cleanNonce: String?
            if let nonce {
                guard isSignedInChange,
                      let normalized = PasswordReauthenticationNoncePolicy.normalized(nonce) else {
                    throw AuthServiceError.invalidPasswordReauthenticationNonce
                }
                cleanNonce = normalized
                body["nonce"] = normalized
            } else {
                cleanNonce = nil
            }
            if isSignedInChange,
               self.passwordChangeRequiresNonce,
               cleanNonce == nil {
                throw AuthServiceError.invalidPasswordReauthenticationNonce
            }

            do {
                _ = try await self.requestAuthenticatedJSON(
                    path: "/auth/v1/user",
                    method: "PUT",
                    initialSession: cloud,
                    body: body
                )
            } catch AuthServiceError.passwordReauthenticationRequired
                        where isSignedInChange && cleanNonce == nil {
                guard let reauthenticationSession = self.session?.cloud,
                      reauthenticationSession.userID == cloud.userID else {
                    throw AuthServiceError.sessionChanged
                }
                _ = try await self.requestAuthenticatedJSON(
                    path: "/auth/v1/reauthenticate",
                    method: "GET",
                    initialSession: reauthenticationSession
                )
                self.passwordChangeRequiresNonce = true
                self.messageIsError = false
                self.message = "Verification code sent. Re-enter the new password with the code."
                return
            } catch AuthServiceError.passwordReauthenticationRequired
                        where isSignedInChange && cleanNonce != nil {
                throw AuthServiceError.invalidPasswordReauthenticationNonce
            }
            guard let currentSession = self.session,
                  currentSession.cloud?.userID == cloud.userID else {
                throw AuthServiceError.sessionChanged
            }
            try self.persist(currentSession, requiresPasswordUpdate: false)
            self.messageIsError = false
            self.message = "Password updated."
            updated = true
        }
        return updated
    }

    func continueOffline(displayName: String) throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = try validatedDisplayName(trimmed.isEmpty ? "Local Athlete" : trimmed, fallbackEmail: "local@gym.app")
        let local = AppAccountSession.local(id: UUID().uuidString.lowercased(), displayName: cleanName)
        try persist(local, requiresPasswordUpdate: false)
        message = nil
    }

    func handleOpenURL(_ url: URL) async {
        guard AuthCallbackRouting.isAuthDestination(url) else { return }
        await perform {
            guard url.absoluteString.utf8
                    .prefix(Self.maximumAuthCallbackURLBytes + 1).count
                    <= Self.maximumAuthCallbackURLBytes else {
                throw AuthServiceError.malformedResponse
            }
            let values = AuthCallbackRouting.callbackValues(url)
            guard self.session == nil,
                  let transaction = try self.pendingAuthTransaction(),
                  transaction.isFresh,
                  AuthCallbackRouting.isExpectedCallback(
                    url,
                    state: transaction.state,
                    values: values
                  ) else {
                throw AuthServiceError.callbackNotExpected
            }
            if let error = values["error_description"] ?? values["error"] {
                throw AuthServiceError.server(error.replacingOccurrences(of: "+", with: " "))
            }

            guard let authCode = values["code"], !authCode.isEmpty else {
                throw AuthServiceError.callbackMissingSession
            }
            guard authCode.utf8.prefix(Self.maximumAuthorizationCodeBytes + 1).count
                    <= Self.maximumAuthorizationCodeBytes else {
                throw AuthServiceError.malformedResponse
            }
            let object = try await self.requestJSON(
                path: "/auth/v1/token?grant_type=pkce",
                method: "POST",
                body: [
                    "auth_code": authCode,
                    "code_verifier": transaction.codeVerifier
                ]
            )
            let cloud = try self.parseCloudSession(object)
            let requiresPasswordUpdate = transaction.kind == .recovery
            try self.persist(
                .cloud(cloud),
                requiresPasswordUpdate: requiresPasswordUpdate
            )
            try self.clearPendingAuthTransaction()
            self.messageIsError = false
            self.message = self.needsPasswordUpdate ? "Choose a new password." : "Email confirmed. You're signed in."
        }
    }

    func validCloudSession(
        expectedUserID: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> CloudAccountSession {
        guard let cloud = session?.cloud else { throw AuthServiceError.notCloudAccount }
        guard expectedUserID == nil || expectedUserID == cloud.userID else {
            throw AuthServiceError.sessionChanged
        }
        guard Self.isValidAccessToken(cloud.accessToken),
              cloud.refreshToken.map(Self.isValidOptionalToken) ?? true else {
            throw AuthServiceError.malformedResponse
        }
        let expectedRevision = sessionRevision
        if !forceRefresh,
           let expiresAt = cloud.expiresAt,
           expiresAt.timeIntervalSinceNow > 60 {
            return cloud
        }
        guard let refreshToken = cloud.refreshToken, !refreshToken.isEmpty else { return cloud }

        let refreshIdentity = CloudRefreshIdentity(
            sessionRevision: expectedRevision,
            userID: cloud.userID,
            refreshToken: refreshToken
        )
        let task: Task<CloudAccountSession, Error>
        let generation: UInt64
        if let activeTask = cloudRefreshTask,
           cloudRefreshIdentity == refreshIdentity {
            task = activeTask
            generation = cloudRefreshGeneration
        } else {
            cloudRefreshGeneration &+= 1
            generation = cloudRefreshGeneration
            task = Task { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.refreshCloudSession(
                    cloud,
                    expectedRevision: expectedRevision,
                    refreshToken: refreshToken
                )
            }
            cloudRefreshIdentity = refreshIdentity
            cloudRefreshTask = task
        }

        do {
            let refreshed = try await task.value
            finishCloudRefresh(generation: generation)
            guard expectedUserID == nil || expectedUserID == refreshed.userID else {
                throw AuthServiceError.sessionChanged
            }
            return refreshed
        } catch {
            finishCloudRefresh(generation: generation)
            throw error
        }
    }

    private func refreshCloudSession(
        _ cloud: CloudAccountSession,
        expectedRevision: UInt64,
        refreshToken: String
    ) async throws -> CloudAccountSession {
        let object: [String: Any]
        do {
            object = try await requestJSON(
                path: "/auth/v1/token?grant_type=refresh_token",
                method: "POST",
                body: ["refresh_token": refreshToken]
            )
        } catch AuthServiceError.requestFailed(let status, _)
                    where status == 400 || status == 401 {
            // A rejected refresh token is terminal for this exact session. Check
            // revision and owner before clearing so a late response cannot remove
            // a replacement account that signed in while refresh was in flight.
            guard sessionRevision == expectedRevision,
                  session?.cloud == cloud else {
                throw AuthServiceError.sessionChanged
            }
            try clearSession()
            messageIsError = true
            message = AuthServiceError.sessionExpired.errorDescription
            throw AuthServiceError.sessionExpired
        }
        let refreshed = try parseCloudSession(object, fallback: cloud)
        guard sessionRevision == expectedRevision,
              session?.cloud?.userID == cloud.userID,
              refreshed.userID == cloud.userID else {
            throw AuthServiceError.sessionChanged
        }
        try persist(
            .cloud(refreshed),
            requiresPasswordUpdate: needsPasswordUpdate,
            preservePasswordChangeNonce: true
        )
        return refreshed
    }

    private func finishCloudRefresh(generation: UInt64) {
        guard cloudRefreshGeneration == generation else { return }
        cloudRefreshTask = nil
        cloudRefreshIdentity = nil
    }

    func signOut() async {
        isLoading = true
        let token = session?.cloud?.accessToken
        do {
            try clearSession()
        } catch {
            messageIsError = true
            message = friendlyMessage(error)
        }
        if let token {
            _ = try? await requestJSON(
                path: "/auth/v1/logout?scope=local",
                method: "POST",
                token: token,
                body: [:]
            )
        }
        isLoading = false
    }

    /// Server function deletes auth user and rows cascading from auth.users.
    /// The caller must erase the matching local store after this returns.
    func deleteCloudAccountOnServer(
        expectedUserID: String,
        onRequestDispositionChange: ((AccountDeletionRequestDisposition) -> Void)? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        let cloud = try await validCloudSession(expectedUserID: expectedUserID)
        let object = try await requestAuthenticatedJSON(
            path: "/functions/v1/delete-account",
            method: "POST",
            initialSession: cloud,
            headers: ["X-GymApp-Delete": "confirmed"],
            body: ["confirmation": "DELETE"],
            onRequestDispositionChange: onRequestDispositionChange
        )
        guard object.count == 1, object["deleted"] as? Bool == true else {
            throw AuthServiceError.malformedResponse
        }
    }

    func clearSession() throws {
        defaults.set(true, forKey: Self.pendingSecureDeletionKey)
        _ = defaults.synchronize()
        sessionRevision &+= 1
        session = nil
        message = nil
        pendingConfirmationEmail = nil
        pendingConfirmationEmailWasSent = false
        needsPasswordUpdate = false
        passwordChangeRequiresNonce = false

        var deletionError: Error?
        do {
            try keychain.delete(account: sessionAccount)
        } catch {
            deletionError = deletionError ?? error
        }
        do {
            try clearPendingAuthTransaction()
        } catch {
            deletionError = deletionError ?? error
        }
        if deletionError == nil {
            defaults.removeObject(forKey: Self.pendingSecureDeletionKey)
        }
        if let deletionError { throw deletionError }
    }

#if DEBUG
    /// Test-only seam for deterministic account-transition races. Release builds do
    /// not expose a way to install an arbitrary authenticated session.
    func installSessionForTesting(_ value: AppAccountSession) throws {
        try persist(value, requiresPasswordUpdate: false)
    }
#endif

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
        isLoading = true
        message = nil
        do {
            try await operation()
        } catch {
            messageIsError = true
            message = friendlyMessage(error)
        }
        isLoading = false
    }

    private func persist(
        _ value: AppAccountSession,
        requiresPasswordUpdate: Bool,
        preservePasswordChangeNonce: Bool = false
    ) throws {
        let protectedState = requiresPasswordUpdate && value.cloud != nil
        let persisted = PersistedAuthState(
            session: value,
            requiresPasswordUpdate: protectedState
        )
        try keychain.save(encoder.encode(persisted), account: sessionAccount)
        sessionRevision &+= 1
        session = value
        pendingConfirmationEmail = nil
        pendingConfirmationEmailWasSent = false
        needsPasswordUpdate = protectedState
        if !preservePasswordChangeNonce {
            passwordChangeRequiresNonce = false
        }
        defaults.removeObject(forKey: Self.pendingSecureDeletionKey)
    }

    private func beginAuthTransaction(
        email: String,
        kind: PendingAuthTransaction.Kind
    ) throws -> PendingAuthTransaction {
        let transaction = PendingAuthTransaction(
            state: try Self.randomURLSafeString(byteCount: 24),
            codeVerifier: try Self.randomURLSafeString(byteCount: 64),
            email: email,
            kind: kind,
            createdAt: Date(),
            confirmationEmailSentAt: nil
        )
        try keychain.save(encoder.encode(transaction), account: authTransactionAccount)
        return transaction
    }

    private func reusableAuthTransaction(
        for email: String,
        kind: PendingAuthTransaction.Kind
    ) throws -> PendingAuthTransaction {
        if let transaction = try pendingAuthTransaction(),
           transaction.kind == kind,
           transaction.email == email,
           transaction.isFresh {
            return transaction
        }
        return try beginAuthTransaction(email: email, kind: kind)
    }

    private func reusableSignupTransaction(for email: String) throws -> PendingAuthTransaction {
        try reusableAuthTransaction(for: email, kind: .signup)
    }

    private static func authDeliveryOutcomeMayBeUnknown(_ error: Error) -> Bool {
        switch error {
        case AuthServiceError.requestFailed(let status, _):
            return status == 408 || (500 ... 599).contains(status)
        case AuthServiceError.invalidEmail,
             AuthServiceError.invalidPassword,
             AuthServiceError.invalidPasswordReauthenticationNonce,
             AuthServiceError.passwordReauthenticationRequired,
             AuthServiceError.invalidDisplayName,
             AuthServiceError.callbackMissingSession,
             AuthServiceError.callbackNotExpected,
             AuthServiceError.notCloudAccount,
             AuthServiceError.sessionChanged,
             AuthServiceError.sessionExpired:
            return false
        default:
            // Transport cancellation/loss and bounded or malformed responses do
            // not prove that the provider failed before sending the email.
            return true
        }
    }

    private func markConfirmationEmailSent(
        _ transaction: PendingAuthTransaction
    ) throws -> PendingAuthTransaction {
        var updated = transaction
        updated.confirmationEmailSentAt = Date()
        try keychain.save(encoder.encode(updated), account: authTransactionAccount)
        return updated
    }

    private func restorePendingSignupTransaction() {
        guard let transaction = try? pendingAuthTransaction(),
              transaction.kind == .signup else {
            return
        }
        guard transaction.isFresh else {
            try? clearPendingAuthTransaction()
            return
        }
        pendingConfirmationEmail = transaction.email
        pendingConfirmationEmailWasSent = transaction.confirmationEmailWasSent
        messageIsError = false
    }

    private func pendingAuthTransaction() throws -> PendingAuthTransaction? {
        try keychain.read(account: authTransactionAccount).flatMap {
            try decoder.decode(PendingAuthTransaction.self, from: $0)
        }
    }

    private func clearPendingAuthTransaction() throws {
        try keychain.delete(account: authTransactionAccount)
    }

    private func parseCloudSession(_ object: [String: Any], fallback: CloudAccountSession? = nil) throws -> CloudAccountSession {
        guard let accessToken = object["access_token"] as? String,
              Self.isValidAccessToken(accessToken) else {
            throw AuthServiceError.malformedResponse
        }
        let user = object["user"] as? [String: Any] ?? [:]
        let userID = (user["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback?.userID
        guard let userID, !userID.isEmpty else { throw AuthServiceError.malformedResponse }
        let email = (user["email"] as? String) ?? fallback?.email ?? ""
        let metadata = user["user_metadata"] as? [String: Any]
        let displayName = (metadata?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallback?.displayName
            ?? email.split(separator: "@").first.map(String.init)
            ?? "GymApp user"
        let refreshToken = (object["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallback?.refreshToken
        guard refreshToken.map(Self.isValidOptionalToken) ?? true else {
            throw AuthServiceError.malformedResponse
        }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return CloudAccountSession(
            userID: userID,
            email: email,
            displayName: displayName,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func requestJSON(
        path: String,
        method: String,
        token: String? = nil,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        onRequestDispositionChange: ((AccountDeletionRequestDisposition) -> Void)? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL) else {
            throw AuthServiceError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            guard Self.isValidAccessToken(token) else { throw AuthServiceError.malformedResponse }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            let encoded = try JSONSerialization.data(withJSONObject: body)
            guard encoded.count <= Self.maximumAuthRequestBytes else {
                throw AuthServiceError.malformedResponse
            }
            request.httpBody = encoded
        }

        onRequestDispositionChange?(.outcomeUnknown)

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: Self.maximumAuthResponseBytes,
                errorLimit: Self.maximumAuthErrorResponseBytes
            )
        } catch BoundedURLSessionError.responseTooLarge(let status?)
                    where !(200 ..< 300).contains(status) {
            if (400 ..< 500).contains(status) {
                onRequestDispositionChange?(.definitivelyRejected)
            }
            throw AuthServiceError.requestFailed(
                status: status,
                message: "Authentication failed (HTTP \(status))."
            )
        } catch is BoundedURLSessionError {
            throw AuthServiceError.malformedResponse
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            if (400 ..< 500).contains(http.statusCode) {
                onRequestDispositionChange?(.definitivelyRejected)
            }
            if let typedError = Self.typedAuthError(
                status: http.statusCode,
                object: object
            ) {
                throw typedError
            }
            throw AuthServiceError.requestFailed(
                status: http.statusCode,
                message: Self.errorMessage(status: http.statusCode, object: object)
            )
        }
        return object
    }

    private func requestAuthenticatedJSON(
        path: String,
        method: String,
        initialSession: CloudAccountSession,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        onRequestDispositionChange: ((AccountDeletionRequestDisposition) -> Void)? = nil
    ) async throws -> [String: Any] {
        let expectedUserID = initialSession.userID
        let firstRevision = sessionRevision
        guard session?.cloud == initialSession else {
            throw AuthServiceError.sessionChanged
        }

        do {
            let object = try await requestJSON(
                path: path,
                method: method,
                token: initialSession.accessToken,
                headers: headers,
                body: body,
                onRequestDispositionChange: onRequestDispositionChange
            )
            guard sessionRevision == firstRevision,
                  session?.cloud == initialSession else {
                throw AuthServiceError.sessionChanged
            }
            return object
        } catch AuthServiceError.requestFailed(let status, _)
                    where status == 401 || status == 403 {
            // The access JWT can be revoked before its local expiry. Refresh once,
            // then retry once. The direct 401/403 never clears the local session;
            // only validCloudSession's terminal refresh response can do that.
            guard sessionRevision == firstRevision,
                  session?.cloud == initialSession else {
                throw AuthServiceError.sessionChanged
            }
            let refreshed = try await validCloudSession(
                expectedUserID: expectedUserID,
                forceRefresh: true
            )
            let retryRevision = sessionRevision
            let object: [String: Any]
            do {
                object = try await requestJSON(
                    path: path,
                    method: method,
                    token: refreshed.accessToken,
                    headers: headers,
                    body: body,
                    onRequestDispositionChange: onRequestDispositionChange
                )
            } catch {
                guard sessionRevision == retryRevision,
                      session?.cloud == refreshed else {
                    throw AuthServiceError.sessionChanged
                }
                throw error
            }
            guard sessionRevision == retryRevision,
                  session?.cloud == refreshed else {
                throw AuthServiceError.sessionChanged
            }
            return object
        } catch {
            guard sessionRevision == firstRevision,
                  session?.cloud == initialSession else {
                throw AuthServiceError.sessionChanged
            }
            throw error
        }
    }

    private func validatedEmail(_ email: String) throws -> String {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$"
        guard value.count <= 254, value.range(of: pattern, options: .regularExpression) != nil else {
            throw AuthServiceError.invalidEmail
        }
        return value
    }

    private func validatePassword(_ password: String) throws {
        guard GymPasswordPolicy.accepts(password) else {
            throw AuthServiceError.invalidPassword
        }
    }

    private func validatedDisplayName(_ value: String, fallbackEmail: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if trimmed.isEmpty {
            candidate = String(fallbackEmail.split(separator: "@").first ?? "Athlete")
        } else {
            candidate = trimmed
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .-_") )
        guard (2...32).contains(candidate.count),
              candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AuthServiceError.invalidDisplayName
        }
        return candidate
    }

    private func friendlyMessage(_ error: Error) -> String {
        gymSafeEnglishErrorMessage(error)
    }

    private static func errorMessage(status: Int, object: [String: Any]) -> String {
        let raw = (object["msg"] as? String)
            ?? (object["message"] as? String)
            ?? (object["error_description"] as? String)
            ?? (object["error"] as? String)
        if status >= 500 { return "Cloud service is temporarily unavailable. Try again later." }
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? raw!
            : "Cloud request failed. Check your connection and try again."
    }

    private static func typedAuthError(
        status: Int,
        object: [String: Any]
    ) -> AuthServiceError? {
        guard (400 ..< 500).contains(status),
              let rawCode = (object["code"] as? String)
                ?? (object["error_code"] as? String),
              rawCode.utf8.count <= 128 else {
            return nil
        }
        switch rawCode.lowercased() {
        case "reauthentication_needed":
            return .passwordReauthenticationRequired
        case "reauthentication_not_valid":
            return .invalidPasswordReauthenticationNonce
        default:
            return nil
        }
    }

    private static func isValidAccessToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.prefix(maximumTokenBytes + 1).count <= maximumTokenBytes
            && value.unicodeScalars.allSatisfy { (0x21...0x7e).contains($0.value) }
    }

    private static func isValidOptionalToken(_ value: String) -> Bool {
        value.utf8.prefix(maximumTokenBytes + 1).count <= maximumTokenBytes
            && value.unicodeScalars.allSatisfy { (0x21...0x7e).contains($0.value) }
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        return Data(bytes).base64URLEncodedString()
    }

}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var safeStorageComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        let mapped = unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(mapped)
        return result.isEmpty ? "default" : result
    }
}
