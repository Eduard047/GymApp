import Foundation
import StoreKit

/// The six optional "Support the developer" consumables. Product IDs mirror
/// `shared/support-tips-v1.json` (a test asserts equality, order included).
/// Nothing is unlocked or locked by a tip; there is no server validation and no
/// account binding, so no purchase data is stored by the app.
enum SupportTipProducts {
    struct Entry: Equatable {
        let key: String
        let productID: String
    }

    static let entries: [Entry] = [
        Entry(key: "tip_1", productID: "com.setforge.gymapp.ios.tip1"),
        Entry(key: "tip_2", productID: "com.setforge.gymapp.ios.tip2"),
        Entry(key: "tip_3", productID: "com.setforge.gymapp.ios.tip3"),
        Entry(key: "tip_5", productID: "com.setforge.gymapp.ios.tip5"),
        Entry(key: "tip_10", productID: "com.setforge.gymapp.ios.tip10"),
        Entry(key: "tip_20", productID: "com.setforge.gymapp.ios.tip20")
    ]

    static let all: [String] = entries.map(\.productID)

    /// The pre-selected chip: the third amount (about 3 USD).
    static let defaultProductID = "com.setforge.gymapp.ios.tip3"

    static func isTipProduct(_ productID: String) -> Bool {
        all.contains(productID)
    }

    /// The default chip among the products the store actually returned: the
    /// third amount when present, otherwise the first one available.
    static func defaultSelection(among productIDs: [String]) -> String? {
        productIDs.contains(defaultProductID) ? defaultProductID : productIDs.first
    }
}

/// One loaded tip amount with the store's localized price string.
struct SupportTipOption: Equatable, Identifiable {
    let id: String
    let displayPrice: String
}

/// What a purchase attempt (or a thrown error) means for the screen.
enum SupportTipOutcome: Equatable {
    case success
    case cancelled
    case pending
    case offline
    case unavailable
    case failed

    /// Pure, table-driven mapping of StoreKit and URL errors.
    init(error: Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled:
                self = .cancelled
            case .networkError:
                self = .offline
            case .notAvailableInStorefront, .unsupported:
                self = .unavailable
            default:
                self = .failed
            }
            return
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable, .purchaseNotAllowed:
                self = .unavailable
            default:
                self = .failed
            }
            return
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                self = .offline
            case .cancelled:
                self = .cancelled
            default:
                self = .failed
            }
            return
        }
        self = .failed
    }

    init(result: SupportTipPurchaseResult) {
        switch result {
        case .purchased: self = .success
        case .cancelled: self = .cancelled
        case .pending: self = .pending
        case .unverified: self = .failed
        }
    }
}

enum SupportTipPurchaseResult: Equatable {
    case purchased
    case cancelled
    case pending
    case unverified
}

/// A tip transaction finished outside a purchase call (Ask to Buy approval,
/// an interrupted purchase delivered on the next launch).
enum SupportTipUpdate: Equatable {
    case completed
}

/// The StoreKit surface the store needs, so tests can replace it.
@MainActor
protocol SupportTipsBackend: AnyObject {
    var canMakePayments: Bool { get }
    func loadOptions(productIDs: [String]) async throws -> [SupportTipOption]
    func purchase(productID: String) async throws -> SupportTipPurchaseResult
    func updates() -> AsyncStream<SupportTipUpdate>
}

/// StoreKit 2 implementation. Tips are consumables: every verified transaction is
/// finished right away so the same amount can be bought again.
@MainActor
final class StoreKitSupportTipsBackend: SupportTipsBackend {
    private var products: [String: Product] = [:]

    var canMakePayments: Bool { AppStore.canMakePayments }

    func loadOptions(productIDs: [String]) async throws -> [SupportTipOption] {
        let loaded = try await Product.products(for: productIDs)
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return productIDs.compactMap { id in
            products[id].map { SupportTipOption(id: id, displayPrice: $0.displayPrice) }
        }
    }

    func purchase(productID: String) async throws -> SupportTipPurchaseResult {
        guard SupportTipProducts.isTipProduct(productID), let product = products[productID] else {
            throw Product.PurchaseError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return .purchased
        case .success(.unverified(let transaction, _)):
            // Clear the queue, but never treat an unverified receipt as a success.
            await transaction.finish()
            return .unverified
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .unverified
        }
    }

    nonisolated func updates() -> AsyncStream<SupportTipUpdate> {
        AsyncStream { continuation in
            let task = Task.detached {
                for await result in Transaction.updates {
                    switch result {
                    case .verified(let transaction):
                        guard SupportTipProducts.isTipProduct(transaction.productID) else { continue }
                        await transaction.finish()
                        continuation.yield(.completed)
                    case .unverified(let transaction, _):
                        if SupportTipProducts.isTipProduct(transaction.productID) {
                            await transaction.finish()
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Owner of the tip jar state. Created once at app launch (so the
/// `Transaction.updates` listener runs from the start) and shared with the
/// support screen through the environment.
@MainActor
final class SupportTipStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        /// Purchases are off, or the products are not configured in the store.
        case unavailable
        /// The products could not be loaded because there is no connection.
        case offline
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case thanks
    }

    enum Notice: Equatable {
        case pending
        case offline
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var options: [SupportTipOption] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var notice: Notice?
    /// Increments on every completed tip; drives the success haptic.
    @Published private(set) var successCount = 0

    private let backend: SupportTipsBackend
    private var isLoading = false
    private var listener: Task<Void, Never>?

    init(backend: SupportTipsBackend? = nil, listensForUpdates: Bool = true) {
        self.backend = backend ?? StoreKitSupportTipsBackend()
        if listensForUpdates { startListening() }
    }

    deinit {
        listener?.cancel()
    }

    private func startListening() {
        guard listener == nil else { return }
        let stream = backend.updates()
        listener = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                self.handle(update)
            }
        }
    }

    private func handle(_ update: SupportTipUpdate) {
        switch update {
        case .completed:
            // Only a waiting (Ask to Buy) purchase turns into a thank-you; a
            // flow that finished inside `purchase` already showed its own.
            guard notice == .pending else { return }
            notice = nil
            purchaseState = .thanks
            successCount += 1
        }
    }

    /// Called whenever the screen appears: drops a stale thank-you or error.
    func screenDidAppear() {
        if purchaseState == .thanks { purchaseState = .idle }
        if notice == .offline || notice == .failed { notice = nil }
    }

    func dismissThanks() {
        if purchaseState == .thanks { purchaseState = .idle }
    }

    /// Loads the products unless they are already loaded.
    func loadIfNeeded() async {
        if phase == .ready, !options.isEmpty { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        phase = .loading
        guard backend.canMakePayments else {
            options = []
            phase = .unavailable
            return
        }
        do {
            let loaded = try await backend.loadOptions(productIDs: SupportTipProducts.all)
            // Fixed order and tip products only, whatever order the store returned.
            options = SupportTipProducts.all.compactMap { id in loaded.first { $0.id == id } }
            phase = options.isEmpty ? .unavailable : .ready
        } catch {
            options = []
            phase = SupportTipOutcome(error: error) == .offline ? .offline : .unavailable
        }
    }

    func purchase(productID: String) async {
        guard phase == .ready,
              purchaseState == .idle,
              options.contains(where: { $0.id == productID }) else { return }
        notice = nil
        purchaseState = .purchasing
        let outcome: SupportTipOutcome
        do {
            outcome = SupportTipOutcome(result: try await backend.purchase(productID: productID))
        } catch {
            outcome = SupportTipOutcome(error: error)
        }
        apply(outcome)
    }

    private func apply(_ outcome: SupportTipOutcome) {
        switch outcome {
        case .success:
            purchaseState = .thanks
            successCount += 1
        case .cancelled:
            purchaseState = .idle
        case .pending:
            purchaseState = .idle
            notice = .pending
        case .offline:
            purchaseState = .idle
            notice = .offline
        case .unavailable:
            purchaseState = .idle
            options = []
            phase = .unavailable
        case .failed:
            purchaseState = .idle
            notice = .failed
        }
    }
}
