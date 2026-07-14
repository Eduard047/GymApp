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

    var redirectURL: String {
        AuthCallbackRouting.webRedirectURL(
            state: state,
            purpose: kind == .recovery ? .recovery : .signup
        )
    }

    var isFresh: Bool {
        createdAt.timeIntervalSinceNow > -(24 * 60 * 60)
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
    case invalidDisplayName
    case malformedResponse
    case callbackMissingSession
    case callbackNotExpected
    case notCloudAccount
    case sessionChanged
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a valid email address."
        case .invalidPassword: return "Password must be 8–72 characters and include letters and numbers."
        case .invalidDisplayName: return "Display name must be 2–32 characters and use letters, numbers, spaces, dot, dash or underscore."
        case .malformedResponse: return "The cloud returned an invalid response. Try again."
        case .callbackMissingSession: return "The confirmation link did not contain a valid session."
        case .callbackNotExpected: return "This sign-in link was not requested on this device or has expired. Start the flow again."
        case .notCloudAccount: return "This action requires a cloud account."
        case .sessionChanged: return "The account changed while the request was running. Try again."
        case .server(let message): return message
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AppAccountSession?
    @Published private(set) var isLoading = false
    @Published var message: String?
    @Published private(set) var messageIsError = true
    @Published var needsPasswordUpdate = false

    private let keychain: any KeychainStoring
    private let urlSession: URLSession
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let sessionAccount = "current-session"
    private let authTransactionAccount = "pending-auth-transaction"
    private var sessionRevision: UInt64 = 0

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
        } else {
            self.session = try? keychain.read(account: sessionAccount).flatMap {
                try decoder.decode(AppAccountSession.self, from: $0)
            }
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            try self.validatePassword(password)
            let object = try await self.requestJSON(
                path: "/auth/v1/token?grant_type=password",
                method: "POST",
                body: ["email": cleanEmail, "password": password]
            )
            let cloud = try self.parseCloudSession(object)
            try self.persist(.cloud(cloud))
            self.message = nil
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
            let transaction = try self.beginAuthTransaction(email: cleanEmail, kind: .signup)
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
                    try self.persist(.cloud(cloud))
                    try self.clearPendingAuthTransaction()
                    signedIn = true
                    self.message = nil
                } else {
                    self.messageIsError = false
                    self.message = "Account created. Check your email, then return to GymApp."
                }
            } catch {
                try? self.clearPendingAuthTransaction()
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
                body: ["type": "signup", "email": cleanEmail]
            )
            self.messageIsError = false
            self.message = "Confirmation email sent. Check inbox and spam."
        }
    }

    func requestPasswordReset(email: String) async {
        await perform {
            let cleanEmail = try self.validatedEmail(email)
            let transaction = try self.beginAuthTransaction(email: cleanEmail, kind: .recovery)
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
                try? self.clearPendingAuthTransaction()
                throw error
            }
        }
    }

    func updatePassword(_ password: String) async {
        await perform {
            try self.validatePassword(password)
            let token = try await self.validCloudSession().accessToken
            _ = try await self.requestJSON(
                path: "/auth/v1/user",
                method: "PUT",
                token: token,
                body: ["password": password]
            )
            self.needsPasswordUpdate = false
            self.messageIsError = false
            self.message = "Password updated."
        }
    }

    func continueOffline(displayName: String) throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = try validatedDisplayName(trimmed.isEmpty ? "Local Athlete" : trimmed, fallbackEmail: "local@gym.app")
        let local = AppAccountSession.local(id: UUID().uuidString.lowercased(), displayName: cleanName)
        try persist(local)
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
            try self.persist(.cloud(cloud))
            try self.clearPendingAuthTransaction()
            self.needsPasswordUpdate = transaction.kind == .recovery
            self.messageIsError = false
            self.message = self.needsPasswordUpdate ? "Choose a new password." : "Email confirmed. You're signed in."
        }
    }

    func validCloudSession(expectedUserID: String? = nil) async throws -> CloudAccountSession {
        guard var cloud = session?.cloud else { throw AuthServiceError.notCloudAccount }
        guard expectedUserID == nil || expectedUserID == cloud.userID else {
            throw AuthServiceError.sessionChanged
        }
        guard Self.isValidAccessToken(cloud.accessToken),
              cloud.refreshToken.map(Self.isValidOptionalToken) ?? true else {
            throw AuthServiceError.malformedResponse
        }
        let expectedRevision = sessionRevision
        if let expiresAt = cloud.expiresAt,
           expiresAt.timeIntervalSinceNow > 60 {
            return cloud
        }
        guard let refreshToken = cloud.refreshToken, !refreshToken.isEmpty else { return cloud }

        let object = try await requestJSON(
            path: "/auth/v1/token?grant_type=refresh_token",
            method: "POST",
            body: ["refresh_token": refreshToken]
        )
        let refreshed = try parseCloudSession(object, fallback: cloud)
        guard sessionRevision == expectedRevision,
              session?.cloud?.userID == cloud.userID,
              refreshed.userID == cloud.userID,
              expectedUserID == nil || expectedUserID == refreshed.userID else {
            throw AuthServiceError.sessionChanged
        }
        cloud = refreshed
        try persist(.cloud(cloud))
        return cloud
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
                path: "/auth/v1/logout?scope=global",
                method: "POST",
                token: token,
                body: [:]
            )
        }
        isLoading = false
    }

    /// Server function deletes auth user and rows cascading from auth.users.
    /// The caller must erase the matching local store after this returns.
    func deleteCloudAccountOnServer(expectedUserID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let cloud = try await validCloudSession(expectedUserID: expectedUserID)
        _ = try await requestJSON(
            path: "/functions/v1/delete-account",
            method: "POST",
            token: cloud.accessToken,
            headers: ["X-GymApp-Delete": "confirmed"],
            body: ["confirmation": "DELETE"]
        )
    }

    func clearSession() throws {
        defaults.set(true, forKey: Self.pendingSecureDeletionKey)
        _ = defaults.synchronize()
        sessionRevision &+= 1
        session = nil
        message = nil
        needsPasswordUpdate = false

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
        try persist(value)
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

    private func persist(_ value: AppAccountSession) throws {
        try keychain.save(encoder.encode(value), account: sessionAccount)
        sessionRevision &+= 1
        session = value
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
            createdAt: Date()
        )
        try keychain.save(encoder.encode(transaction), account: authTransactionAccount)
        return transaction
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
        body: [String: Any]? = nil
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

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: Self.maximumAuthResponseBytes,
                errorLimit: Self.maximumAuthErrorResponseBytes
            )
        } catch is BoundedURLSessionError {
            throw AuthServiceError.malformedResponse
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw AuthServiceError.server(Self.errorMessage(status: http.statusCode, object: object))
        }
        return object
    }

    private func validatedEmail(_ email: String) throws -> String {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        guard value.count <= 254, value.range(of: pattern, options: .regularExpression) != nil else {
            throw AuthServiceError.invalidEmail
        }
        return value
    }

    private func validatePassword(_ password: String) throws {
        guard (8...72).contains(password.count),
              password.contains(where: { $0.isLetter }),
              password.contains(where: { $0.isNumber }) else {
            throw AuthServiceError.invalidPassword
        }
    }

    private func validatedDisplayName(_ value: String, fallbackEmail: String) throws -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(fallbackEmail.split(separator: "@").first ?? "Athlete")
            : value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .-_") )
        guard (2...32).contains(candidate.count),
              candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AuthServiceError.invalidDisplayName
        }
        return candidate
    }

    private func friendlyMessage(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("invalid login") || lower.contains("invalid credentials") { return "Email or password is incorrect." }
        if lower.contains("email not confirmed") { return "Confirm your email first, then sign in." }
        if lower.contains("rate limit") || lower.contains("over_email_send_rate_limit") { return "Too many emails were requested. Try again later." }
        if lower.contains("already registered") || lower.contains("user_already_exists") { return "An account with this email already exists." }
        return raw
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
