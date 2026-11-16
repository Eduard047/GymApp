import Foundation
import StoreKit
import XCTest
@testable import GymApp

@MainActor
final class SupportTipsTests: XCTestCase {
    // MARK: Shared contract

    func testProductConstantsMatchSharedFixtureInOrder() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/support-tips-v1.json")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["version"] as? Int, 1)
        let tips = try XCTUnwrap(root["tips"] as? [[String: String]])
        XCTAssertEqual(tips.count, 6)
        XCTAssertEqual(tips.compactMap { $0["ios"] }, SupportTipProducts.all)
        XCTAssertEqual(tips.compactMap { $0["key"] }, SupportTipProducts.entries.map(\.key))
        XCTAssertEqual(Set(SupportTipProducts.all).count, 6)
        XCTAssertTrue(SupportTipProducts.all.allSatisfy { $0.hasPrefix("com.setforge.gymapp.ios.") })
    }

    // MARK: Error and result mapping (same cases on Android)

    func testErrorMappingTable() {
        let cases: [(String, Error, SupportTipOutcome)] = [
            ("user_cancelled", StoreKitError.userCancelled, .cancelled),
            ("task_cancelled", CancellationError(), .cancelled),
            ("store_network", StoreKitError.networkError(URLError(.notConnectedToInternet)), .offline),
            ("url_offline", URLError(.notConnectedToInternet), .offline),
            ("url_timeout", URLError(.timedOut), .offline),
            ("not_in_storefront", StoreKitError.notAvailableInStorefront, .unavailable),
            ("product_unavailable", Product.PurchaseError.productUnavailable, .unavailable),
            ("purchase_not_allowed", Product.PurchaseError.purchaseNotAllowed, .unavailable),
            ("unknown", StoreKitError.unknown, .failed),
            ("system_error", StoreKitError.systemError(URLError(.badServerResponse)), .failed),
            ("url_other", URLError(.badServerResponse), .failed),
            ("invalid_quantity", Product.PurchaseError.invalidQuantity, .failed),
            ("foreign_error", NSError(domain: "x", code: 1), .failed)
        ]
        for (name, error, expected) in cases {
            XCTAssertEqual(SupportTipOutcome(error: error), expected, name)
        }
    }

    func testPurchaseResultMappingTable() {
        XCTAssertEqual(SupportTipOutcome(result: .purchased), .success)
        XCTAssertEqual(SupportTipOutcome(result: .cancelled), .cancelled)
        XCTAssertEqual(SupportTipOutcome(result: .pending), .pending)
        XCTAssertEqual(SupportTipOutcome(result: .unverified), .failed)
    }

    // MARK: Default chip

    func testDefaultSelectionIsTheThirdAmount() {
        XCTAssertEqual(SupportTipProducts.defaultProductID, SupportTipProducts.all[2])
        XCTAssertEqual(SupportTipProducts.defaultSelection(among: SupportTipProducts.all), SupportTipProducts.all[2])
        let withoutThird = SupportTipProducts.all.filter { $0 != SupportTipProducts.all[2] }
        XCTAssertEqual(SupportTipProducts.defaultSelection(among: withoutThird), SupportTipProducts.all[0])
        XCTAssertNil(SupportTipProducts.defaultSelection(among: []))
    }

    // MARK: Store state

    func testLoadOrdersOptionsAndBecomesReady() async {
        let backend = FakeBackend()
        let store = SupportTipStore(backend: backend, listensForUpdates: false)
        XCTAssertEqual(store.phase, .loading)
        await store.loadIfNeeded()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.options.map(\.id), SupportTipProducts.all)
    }

    func testPaymentsDisabledOrNoProductsIsUnavailable() async {
        let disabled = FakeBackend()
        disabled.canMakePayments = false
        let first = SupportTipStore(backend: disabled, listensForUpdates: false)
        await first.loadIfNeeded()
        XCTAssertEqual(first.phase, .unavailable)

        let empty = FakeBackend()
        empty.options = []
        let second = SupportTipStore(backend: empty, listensForUpdates: false)
        await second.loadIfNeeded()
        XCTAssertEqual(second.phase, .unavailable)
    }

    func testLoadFailureMapsOfflineAndOtherErrors() async {
        let offline = FakeBackend()
        offline.loadError = URLError(.notConnectedToInternet)
        let first = SupportTipStore(backend: offline, listensForUpdates: false)
        await first.loadIfNeeded()
        XCTAssertEqual(first.phase, .offline)

        let broken = FakeBackend()
        broken.loadError = StoreKitError.unknown
        let second = SupportTipStore(backend: broken, listensForUpdates: false)
        await second.loadIfNeeded()
        XCTAssertEqual(second.phase, .unavailable)
    }

    func testPurchaseStateMapping() async {
        let table: [(String, Result<SupportTipPurchaseResult, Error>, SupportTipStore.PurchaseState, SupportTipStore.Notice?, SupportTipStore.Phase)] = [
            ("success", .success(.purchased), .thanks, nil, .ready),
            ("cancelled", .success(.cancelled), .idle, nil, .ready),
            ("pending", .success(.pending), .idle, .pending, .ready),
            ("unverified", .success(.unverified), .idle, .failed, .ready),
            ("offline", .failure(URLError(.notConnectedToInternet)), .idle, .offline, .ready),
            ("unavailable", .failure(Product.PurchaseError.productUnavailable), .idle, nil, .unavailable),
            ("generic", .failure(StoreKitError.unknown), .idle, .failed, .ready)
        ]
        for (name, result, state, notice, phase) in table {
            let backend = FakeBackend()
            backend.purchaseResult = result
            let store = SupportTipStore(backend: backend, listensForUpdates: false)
            await store.loadIfNeeded()
            await store.purchase(productID: SupportTipProducts.defaultProductID)
            XCTAssertEqual(store.purchaseState, state, name)
            XCTAssertEqual(store.notice, notice, name)
            XCTAssertEqual(store.phase, phase, name)
            XCTAssertEqual(store.successCount, state == .thanks ? 1 : 0, name)
        }
    }

    func testPurchaseIgnoresUnknownProductAndDoubleTap() async {
        let backend = FakeBackend()
        let store = SupportTipStore(backend: backend, listensForUpdates: false)
        await store.loadIfNeeded()
        await store.purchase(productID: "com.example.other")
        XCTAssertEqual(backend.purchaseCalls, 0)
        await store.purchase(productID: SupportTipProducts.defaultProductID)
        XCTAssertEqual(store.purchaseState, .thanks)
        // The thank-you blocks a second purchase until it is dismissed.
        await store.purchase(productID: SupportTipProducts.defaultProductID)
        XCTAssertEqual(backend.purchaseCalls, 1)
        store.dismissThanks()
        await store.purchase(productID: SupportTipProducts.defaultProductID)
        XCTAssertEqual(backend.purchaseCalls, 2)
    }

    func testPendingPurchaseBecomesThanksWhenTheTransactionCompletes() async {
        let backend = FakeBackend()
        backend.purchaseResult = .success(.pending)
        let store = SupportTipStore(backend: backend, listensForUpdates: true)
        await store.loadIfNeeded()
        await store.purchase(productID: SupportTipProducts.defaultProductID)
        XCTAssertEqual(store.notice, .pending)
        backend.updateContinuation?.yield(.completed)
        for _ in 0..<50 where store.purchaseState != .thanks {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.purchaseState, .thanks)
        XCTAssertNil(store.notice)
        XCTAssertEqual(store.successCount, 1)
    }

    func testScreenAppearanceClearsStaleThanksAndTransientErrors() async {
        let backend = FakeBackend()
        let store = SupportTipStore(backend: backend, listensForUpdates: false)
        await store.loadIfNeeded()
        await store.purchase(productID: SupportTipProducts.defaultProductID)
        XCTAssertEqual(store.purchaseState, .thanks)
        store.screenDidAppear()
        XCTAssertEqual(store.purchaseState, .idle)
    }

    // MARK: Copy

    func testEveryStringExistsInAllLanguages() {
        for code in ["en", "uk", "ru"] {
            let strings = [
                SupportTipsCopy.title(code), SupportTipsCopy.intro(code),
                SupportTipsCopy.button(price: "$2.99", code), SupportTipsCopy.thanks(code),
                SupportTipsCopy.retry(code), SupportTipsCopy.offline(code),
                SupportTipsCopy.unavailable(code), SupportTipsCopy.pending(code),
                SupportTipsCopy.failed(code)
            ]
            XCTAssertTrue(strings.allSatisfy { !$0.isEmpty }, code)
        }
        XCTAssertEqual(SupportTipsCopy.title("ru"), "Поддержать разработчика")
        XCTAssertEqual(SupportTipsCopy.title("uk"), "Підтримати розробника")
        XCTAssertEqual(SupportTipsCopy.title("en"), "Support the developer")
        XCTAssertTrue(SupportTipsCopy.button(price: "$2.99", "ru").hasSuffix("— $2.99"))
    }
}

@MainActor
private final class FakeBackend: SupportTipsBackend {
    var canMakePayments = true
    var loadError: Error?
    var options: [SupportTipOption] = SupportTipProducts.all.reversed().enumerated().map {
        SupportTipOption(id: $0.element, displayPrice: "$\($0.offset)")
    }
    var purchaseResult: Result<SupportTipPurchaseResult, Error> = .success(.purchased)
    private(set) var purchaseCalls = 0
    var updateContinuation: AsyncStream<SupportTipUpdate>.Continuation?

    func loadOptions(productIDs: [String]) async throws -> [SupportTipOption] {
        if let loadError { throw loadError }
        // Return the products in an arbitrary order, as StoreKit does.
        return options.filter { productIDs.contains($0.id) }
    }

    func purchase(productID: String) async throws -> SupportTipPurchaseResult {
        purchaseCalls += 1
        return try purchaseResult.get()
    }

    func updates() -> AsyncStream<SupportTipUpdate> {
        AsyncStream { updateContinuation = $0 }
    }
}
