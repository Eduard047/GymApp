import AdServices
import Foundation

// MARK: - Model

/// Parsed, validated Apple Ads attribution for this install. Click/impression
/// dates and the organisation id are deliberately not kept.
struct AppleAdsAttribution: Codable, Equatable, Sendable {
    let attributed: Bool
    let campaignID: Int64?
    let adGroupID: Int64?
    let keywordID: Int64?
    let adID: Int64?
    let conversionType: String?
    let claimType: String?
    let countryOrRegion: String?
    let supplyPlacement: String?

    static let organic = AppleAdsAttribution(
        attributed: false,
        campaignID: nil,
        adGroupID: nil,
        keywordID: nil,
        adID: nil,
        conversionType: nil,
        claimType: nil,
        countryOrRegion: nil,
        supplyPlacement: nil
    )

    private static let conversionTypes: Set<String> = ["Download", "Redownload", "PreOrder"]
    private static let claimTypes: Set<String> = ["Click", "Impression"]
    private static let supplyPlacements: Set<String> = [
        "APPSTORE_SEARCH_RESULTS",
        "APPSTORE_SEARCH_TAB",
        "APPSTORE_TODAY_TAB",
        "APPSTORE_PRODUCT_PAGES"
    ]

    /// Mirrors the server constraints of `gymapp_private.ad_attributions`, so a
    /// value that passes here cannot be rejected by the RPC for its shape.
    var isValid: Bool {
        if attributed {
            guard let campaignID, campaignID > 0,
                  let adGroupID, adGroupID > 0 else { return false }
            if let keywordID, keywordID <= 0 { return false }
            if let adID, adID <= 0 { return false }
            if let conversionType, !Self.conversionTypes.contains(conversionType) { return false }
            if let claimType, !Self.claimTypes.contains(claimType) { return false }
            if let countryOrRegion, !Self.isRegionCode(countryOrRegion) { return false }
            if let supplyPlacement, !Self.supplyPlacements.contains(supplyPlacement) { return false }
            return true
        }
        return campaignID == nil && adGroupID == nil && keywordID == nil && adID == nil
            && conversionType == nil && claimType == nil && countryOrRegion == nil
            && supplyPlacement == nil
    }

    /// Builds a value from Apple's response. Required identifiers must be
    /// positive; optional descriptive fields Apple may extend in the future
    /// (unknown enum values, odd region codes) are dropped instead of blocking
    /// the whole upload.
    fileprivate init?(wire: AppleAdsAttributionWire) {
        guard wire.attribution else {
            self = .organic
            return
        }
        guard let campaignID = wire.campaignId, campaignID > 0,
              let adGroupID = wire.adGroupId, adGroupID > 0 else { return nil }
        self.attributed = true
        self.campaignID = campaignID
        self.adGroupID = adGroupID
        self.keywordID = wire.keywordId.flatMap { $0 > 0 ? $0 : nil }
        self.adID = wire.adId.flatMap { $0 > 0 ? $0 : nil }
        self.conversionType = wire.conversionType.flatMap { Self.conversionTypes.contains($0) ? $0 : nil }
        self.claimType = wire.claimType.flatMap { Self.claimTypes.contains($0) ? $0 : nil }
        self.countryOrRegion = wire.countryOrRegion.flatMap { Self.isRegionCode($0) ? $0 : nil }
        self.supplyPlacement = wire.supplyPlacement.flatMap {
            Self.supplyPlacements.contains($0) ? $0 : nil
        }
    }

    init(
        attributed: Bool,
        campaignID: Int64?,
        adGroupID: Int64?,
        keywordID: Int64?,
        adID: Int64?,
        conversionType: String?,
        claimType: String?,
        countryOrRegion: String?,
        supplyPlacement: String?
    ) {
        self.attributed = attributed
        self.campaignID = campaignID
        self.adGroupID = adGroupID
        self.keywordID = keywordID
        self.adID = adID
        self.conversionType = conversionType
        self.claimType = claimType
        self.countryOrRegion = countryOrRegion
        self.supplyPlacement = supplyPlacement
    }

    private static func isRegionCode(_ value: String) -> Bool {
        value.utf8.count == 2 && value.utf8.allSatisfy { (0x41...0x5a).contains($0) }
    }
}

private struct AppleAdsAttributionWire: Decodable {
    let attribution: Bool
    let campaignId: Int64?
    let adGroupId: Int64?
    let keywordId: Int64?
    let adId: Int64?
    let conversionType: String?
    let claimType: String?
    let countryOrRegion: String?
    let supplyPlacement: String?
}

/// What the upload RPC receives: the attribution plus the install timestamp.
struct AppleAdsAttributionRecord: Equatable, Sendable {
    let attribution: AppleAdsAttribution
    let installSeenAt: Date
}

/// The deterministic server refusal of an upload (malformed values). Anything
/// else thrown by an uploader is treated as transient and retried later.
enum AppleAdsAttributionUploadError: Error, Equatable {
    case rejected
}

// MARK: - Persisted state

/// One small record per install. `pendingToken` exists only while the token
/// has not been exchanged and never longer than `AppleAdsAttributionService.tokenLifetime`.
struct AppleAdsInstallState: Codable, Equatable {
    enum Status: String, Codable {
        /// A token was obtained and still has to be exchanged with Apple.
        case pendingResolution
        /// Apple answered; waiting for the first cloud account to upload it.
        case resolved
        /// Uploaded once for this install. Terminal.
        case uploaded
        /// Token unavailable, expired, rejected, or refused by the server. Terminal.
        case unavailable
    }

    static let currentVersion = 1

    var version = Self.currentVersion
    var installSeenAt: Date
    var status: Status
    var pendingToken: String?
    var tokenObtainedAt: Date?
    var attribution: AppleAdsAttribution?

    static func unavailable(installSeenAt: Date) -> Self {
        Self(installSeenAt: installSeenAt, status: .unavailable)
    }

    static let maximumTokenBytes = 16 * 1_024

    static func isAcceptableToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= maximumTokenBytes
            && token.unicodeScalars.allSatisfy { (0x21...0x7e).contains($0.value) }
    }

    /// The file is untrusted input: status and payload must agree exactly.
    var isConsistent: Bool {
        guard version == Self.currentVersion else { return false }
        switch status {
        case .pendingResolution:
            return pendingToken.map(Self.isAcceptableToken) == true
                && tokenObtainedAt != nil && attribution == nil
        case .resolved:
            return pendingToken == nil && tokenObtainedAt == nil
                && attribution?.isValid == true
        case .uploaded, .unavailable:
            return pendingToken == nil && tokenObtainedAt == nil && attribution == nil
        }
    }
}

enum AppleAdsAttributionStoreError: Error {
    case corrupt
}

protocol AppleAdsAttributionStoring {
    /// `nil` means "no record": this is the first run of this install.
    func load() throws -> AppleAdsInstallState?
    func save(_ state: AppleAdsInstallState) throws
}

/// A single JSON file in Application Support, excluded from iCloud/device
/// backups, so a restore or reinstall is a new install with a fresh token.
struct FileAppleAdsAttributionStore: AppleAdsAttributionStoring {
    static let maximumFileBytes = 32 * 1_024

    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GymApp", isDirectory: true)
            .appendingPathComponent("apple-ads-attribution.json", isDirectory: false)
    }

    func load() throws -> AppleAdsInstallState? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try manager.attributesOfItem(atPath: fileURL.path)
        guard let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= Self.maximumFileBytes else {
            throw AppleAdsAttributionStoreError.corrupt
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(AppleAdsInstallState.self, from: data),
              state.isConsistent else {
            throw AppleAdsAttributionStoreError.corrupt
        }
        return state
    }

    func save(_ state: AppleAdsInstallState) throws {
        let manager = FileManager.default
        var directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        var target = fileURL
        try data.write(
            to: target,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        // The atomic replace creates a new inode, so the flag is set after every write.
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try target.setResourceValues(excluded)
        try? directory.setResourceValues(excluded)
    }
}

// MARK: - Apple resolver

enum AppleAdsAttributionResolution: Equatable {
    case resolved(AppleAdsAttribution)
    /// 404: the token is not ready yet (or already expired).
    case notReady
    /// 400: the token is invalid; it will never succeed.
    case invalidToken
    /// 5xx, other statuses, malformed or oversized bodies, and transport
    /// failures: keep the token and try again on a later launch/foreground.
    case retryLater
}

struct AppleAdsAttributionResolver {
    static let endpoint = URL(string: "https://api-adservices.apple.com/api/v1/")!
    static let maximumResponseBytes = 4 * 1_024
    private static let maximumErrorResponseBytes = 1_024

    let urlSession: URLSession

    func resolve(token: String) async throws -> AppleAdsAttributionResolution {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: Self.maximumResponseBytes,
                errorLimit: Self.maximumErrorResponseBytes
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return .retryLater
        }

        switch response.statusCode {
        case 200:
            guard let wire = try? JSONDecoder().decode(AppleAdsAttributionWire.self, from: data),
                  let attribution = AppleAdsAttribution(wire: wire),
                  attribution.isValid else { return .retryLater }
            return .resolved(attribution)
        case 400:
            return .invalidToken
        case 404:
            return .notReady
        default:
            return .retryLater
        }
    }
}

// MARK: - Token

enum AppleAdsAttributionTokenSource {
    /// `AAAttribution.attributionToken()` can block on the network, so it runs
    /// off the main actor. It needs no ATT prompt and exposes no IDFA.
    @concurrent
    static func attributionToken() async throws -> String {
        try AAAttribution.attributionToken()
    }
}

// MARK: - Service

/// Resolves, once per install, whether the download came from an Apple Ads
/// campaign (AdServices), then uploads that result once for the first cloud
/// account that signs in. Nothing is uploaded for local-only profiles.
///
/// State machine (persisted in `AppleAdsInstallState`):
///
///     (no record) --token--> pendingResolution --200--> resolved --upload ok/false--> uploaded
///          |                      |  |  |                   |
///          | token throws         |  |  +-- >24 h --------->+-- server 400/422 --> unavailable
///          v                      |  +-- 400 -----------------> unavailable
///      unavailable                +-- 404/5xx/offline: stay, retry on launch/foreground
///
/// The token is stored only while pending (at most 24 h) and is erased as soon
/// as Apple answers or the attempt is abandoned. Tokens and payloads are never logged.
@MainActor
final class AppleAdsAttributionService {
    static let tokenLifetime: TimeInterval = 24 * 60 * 60
    static let notReadyRetryDelay: Duration = .seconds(5)
    static let maximumNotReadyRetries = 3
    private static let clockSkewTolerance: TimeInterval = 5 * 60

    typealias TokenProvider = @Sendable () async throws -> String
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Uploader = @MainActor (AppleAdsAttributionRecord, String) async throws -> Bool

    private let storage: any AppleAdsAttributionStoring
    private let tokenProvider: TokenProvider
    private let resolver: AppleAdsAttributionResolver
    private let now: @Sendable () -> Date
    private let sleep: Sleeper
    private let currentCloudUserID: @MainActor () -> String?
    private let upload: Uploader

    private var resolutionTask: Task<Void, Never>?
    private var uploadDeferredUntilResolution = false
    private var uploadInFlight = false
    private var uploadRerunRequested = false

    init(
        storage: any AppleAdsAttributionStoring = FileAppleAdsAttributionStore(),
        tokenProvider: @escaping TokenProvider = { try await AppleAdsAttributionTokenSource.attributionToken() },
        urlSession: URLSession = AppleAdsAttributionService.makeURLSession(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        currentCloudUserID: @escaping @MainActor () -> String?,
        upload: @escaping Uploader
    ) {
        self.storage = storage
        self.tokenProvider = tokenProvider
        self.resolver = AppleAdsAttributionResolver(urlSession: urlSession)
        self.now = now
        self.sleep = sleep
        self.currentCloudUserID = currentCloudUserID
        self.upload = upload
    }

    nonisolated static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// Launch / foreground entry point: finish resolution if still needed, then
    /// upload if a cloud account is signed in.
    func refresh() async {
        await resolveIfNeeded()
        await uploadIfReady()
    }

    // MARK: Resolution

    func resolveIfNeeded() async {
        if let resolutionTask {
            await resolutionTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performResolution()
        }
        resolutionTask = task
        await task.value
        resolutionTask = nil
        // A sign-in that happened while the token was still being resolved.
        if uploadDeferredUntilResolution {
            uploadDeferredUntilResolution = false
            await uploadIfReady()
        }
    }

    private func performResolution() async {
        var state: AppleAdsInstallState
        do {
            if let stored = try storage.load() {
                state = stored
            } else {
                guard let created = await createInstallState() else { return }
                state = created
            }
        } catch is AppleAdsAttributionStoreError {
            // An unreadable record must not trigger endless token requests.
            try? storage.save(.unavailable(installSeenAt: now()))
            return
        } catch {
            return // Transient I/O failure: try again on the next launch/foreground.
        }

        guard state.status == .pendingResolution,
              let token = state.pendingToken,
              var obtainedAt = state.tokenObtainedAt else { return }
        let current = now()
        if obtainedAt > current.addingTimeInterval(Self.clockSkewTolerance) {
            obtainedAt = current // The clock moved back; never extend the 24 h window.
            state.tokenObtainedAt = obtainedAt
            guard persist(state) else { return }
        }

        var notReadyRetries = 0
        while true {
            guard now().timeIntervalSince(obtainedAt) <= Self.tokenLifetime else {
                abandon(&state)
                return
            }
            let resolution: AppleAdsAttributionResolution
            do {
                resolution = try await resolver.resolve(token: token)
            } catch {
                return // Cancelled.
            }
            switch resolution {
            case .resolved(let attribution):
                state.status = .resolved
                state.attribution = attribution
                state.pendingToken = nil
                state.tokenObtainedAt = nil
                _ = persist(state)
                return
            case .invalidToken:
                abandon(&state)
                return
            case .retryLater:
                return
            case .notReady:
                guard notReadyRetries < Self.maximumNotReadyRetries else { return }
                notReadyRetries += 1
                do {
                    try await sleep(Self.notReadyRetryDelay)
                } catch {
                    return // Cancelled.
                }
            }
        }
    }

    private func createInstallState() async -> AppleAdsInstallState? {
        let seenAt = now()
        let token: String
        do {
            token = try await tokenProvider()
        } catch is CancellationError {
            return nil
        } catch {
            // AdServices unavailable (simulator, restricted device): nothing to attribute.
            let state = AppleAdsInstallState.unavailable(installSeenAt: seenAt)
            return persist(state) ? state : nil
        }
        guard AppleAdsInstallState.isAcceptableToken(token) else {
            let state = AppleAdsInstallState.unavailable(installSeenAt: seenAt)
            return persist(state) ? state : nil
        }
        let state = AppleAdsInstallState(
            installSeenAt: seenAt,
            status: .pendingResolution,
            pendingToken: token,
            tokenObtainedAt: now(),
            attribution: nil
        )
        return persist(state) ? state : nil
    }

    private func abandon(_ state: inout AppleAdsInstallState) {
        state = .unavailable(installSeenAt: state.installSeenAt)
        _ = persist(state)
    }

    private func persist(_ state: AppleAdsInstallState) -> Bool {
        do {
            try storage.save(state)
            return true
        } catch {
            return false
        }
    }

    // MARK: Upload

    /// Uploads the resolved attribution for the signed-in cloud account. Calls
    /// that arrive while an upload is running are coalesced into one re-check.
    func uploadIfReady() async {
        guard resolutionTask == nil else {
            uploadDeferredUntilResolution = true
            return
        }
        guard !uploadInFlight else {
            uploadRerunRequested = true
            return
        }
        uploadInFlight = true
        defer { uploadInFlight = false }
        repeat {
            uploadRerunRequested = false
            await performUpload()
        } while uploadRerunRequested && !Task.isCancelled
    }

    private func performUpload() async {
        guard let userID = currentCloudUserID(),
              let state = try? storage.load(),
              state.status == .resolved,
              let attribution = state.attribution else { return }
        let record = AppleAdsAttributionRecord(
            attribution: attribution,
            installSeenAt: state.installSeenAt
        )
        do {
            // `true` = recorded now, `false` = already recorded: both are done.
            _ = try await upload(record, userID)
        } catch is CancellationError {
            return
        } catch AppleAdsAttributionUploadError.rejected {
            // Deterministic refusal; retrying cannot succeed.
            _ = persist(.unavailable(installSeenAt: state.installSeenAt))
            return
        } catch {
            // Offline, server error, or the account changed before the request
            // completed (the uploader is bound to `userID`): keep the result and
            // retry for whichever cloud account is signed in next.
            return
        }
        var finished = state
        finished.status = .uploaded
        finished.attribution = nil
        _ = persist(finished)
    }
}
