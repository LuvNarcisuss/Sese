import Foundation
import StoreKit
import UIKit

extension SKProduct {
    var walletPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)
    }
}

@MainActor
final class WalletStoreRequest: NSObject, SKProductsRequestDelegate {
    let id = UUID()
    enum Output { case products([SKProduct]), receipt }
    private var continuation: CheckedContinuation<Output, Error>?
    private var request: SKRequest?
    private var timeout: Task<Void, Never>?

    func run(_ request: SKRequest) async throws -> Output {
        try await withCheckedThrowingContinuation { waiting in
            self.continuation = waiting
            self.request = request
            request.delegate = self
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.complete(.failure(URLError(.timedOut)), cancel: true)
            }
            request.start()
        }
    }

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in self.complete(.success(.products(response.products))) }
    }
    nonisolated func requestDidFinish(_ request: SKRequest) {
        guard request is SKReceiptRefreshRequest else { return }
        Task { @MainActor in self.complete(.success(.receipt)) }
    }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in self.complete(.failure(error)) }
    }

    private func complete(_ result: Result<Output, Error>, cancel: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        request?.delegate = nil
        if cancel { request?.cancel() }
        request = nil
        continuation.resume(with: result)
    }
}

extension Wallet {
    func request(_ request: SKRequest) async throws -> WalletStoreRequest.Output {
        let client = WalletStoreRequest()
        requestClients[client.id] = client
        defer { requestClients.removeValue(forKey: client.id) }
        return try await client.run(request)
    }

    private func products(_ ids: Set<String>) async throws -> [String: SKProduct] {
        guard case .products(let products) = try await request(SKProductsRequest(productIdentifiers: ids)) else {
            throw WalletError.productUnavailable
        }
        return products.reduce(into: [:]) { catalog, product in
            if ids.contains(product.productIdentifier), product.walletPrice != nil { catalog[product.productIdentifier] = product }
        }
    }

    func catalog() async throws -> [String: SKProduct] {
        try await products(Set(offers().map(\.productID)))
    }

    func buy(_ product: SKProduct, member: UUID, in scene: UIWindowScene) async throws -> String? {
        guard try offers().contains(where: { $0.productID == product.productIdentifier }) else { throw WalletError.invalidCatalog }
        return try await submit(product, reference: nil, source: .local, member: member, in: scene)
    }

    func purchaseOrder(productID: String, reference: String?, member: UUID, in scene: UIWindowScene) async throws {
        guard account == member, scene.activationState == .foregroundActive else { throw WalletError.accountChanged }
        guard !productID.isEmpty, productID.count <= 255, reference.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 256 }) ?? true else { throw WalletError.invalidCatalog }
        let key = member.uuidString + "/" + (reference ?? productID)
        guard pendingCheckouts.insert(key).inserted else { throw WalletError.busy }
        defer { pendingCheckouts.remove(key) }
        if let reference, try journal.read().intents.values.contains(where: {
            $0.member == member && $0.source == .order && $0.reference == reference && ![.failed, .prepared].contains($0.stage)
        }) {
            recover(for: member)
            throw WalletError.reconciliation
        }
        guard let product = try await products([productID])[productID], let price = product.walletPrice else { throw WalletError.productUnavailable }
        guard account == member, scene.activationState == .foregroundActive,
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw WalletError.accountChanged }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed, !(presenter is ThemedDialog) else { throw WalletError.busy }
        let name = product.localizedTitle.isEmpty ? productID : product.localizedTitle
        var details = [price]
        if let reference { details.append("Order " + reference) }
        details.append("To confirm this order, Sese sends your App Store receipt, transaction ID, installation ID and any order reference through Supabase to sese.huisgdd.top.")
        let confirmation = ThemedDialog(title: "Buy \(name)?", message: details.joined(separator: "\n\n"), preferredStyle: .alert)
        let accepted: Bool = await withCheckedContinuation { continuation in
            var result: CheckedContinuation<Bool, Never>? = continuation
            func finish(_ choice: Bool) { result?.resume(returning: choice); result = nil }
            confirmation.addChoice("Cancel", style: .cancel) { finish(false) }
            confirmation.addChoice("Buy", style: .default) { finish(true) }
            presenter.present(confirmation, animated: true)
            Task { @MainActor [weak confirmation] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard result != nil else { return }
                confirmation?.dismiss(animated: false)
                finish(false)
            }
        }
        guard accepted else { return }
        let message = try await submit(product, reference: reference, source: .order, member: member, in: scene)
        if let message, account == member, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil {
            let status = ThemedDialog(title: "Order status", message: message, preferredStyle: .alert)
            status.addChoice("OK", style: .default)
            presenter.present(status, animated: true)
        }
    }

    private func submit(_ product: SKProduct, reference: String?, source: WalletSource, member: UUID, in scene: UIWindowScene) async throws -> String? {
        guard SKPaymentQueue.canMakePayments() else { throw WalletError.paymentsRestricted }
        guard account == member, scene.activationState == .foregroundActive else { throw WalletError.accountChanged }
        guard checkouts.isEmpty, waiting == nil else { throw WalletError.busy }
        let stored = try journal.read().intents.values
        let matching = stored.filter {
            $0.member == member && $0.source == source && $0.product == product.productIdentifier && $0.reference == reference
        }
        // Keep a referenced order bound to its original intent after a definitive cancellation.
        let prepared = matching.first {
            let reusable = $0.stage == .prepared || (reference != nil && $0.stage == .failed && $0.transaction == nil)
            return reusable && $0.contract == WalletIntent.currentContract
        }
        let id = prepared?.id ?? UUID()
        checkouts.insert(id)
        defer { checkouts.remove(id) }
        let active = Set(SKPaymentQueue.default().transactions.compactMap { transaction -> UUID? in
            guard [.purchasing, .deferred].contains(transaction.transactionState) else { return nil }
            return transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:))
        })
        if matching.contains(where: { $0.stage == .deferred || ($0.stage == .submitted &&
            (reference != nil || active.contains($0.id) || Date().timeIntervalSince($0.created) < 90)) }) {
            throw WalletError.outcomeUnknown
        }
        guard let edition = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !edition.isEmpty else {
            throw WalletError.invalidCatalog
        }
        await identifyStoreKitSession()
        if localStoreKitSession, source == .order { throw WalletError.testCurrency }
        let intent = try prepared ?? WalletIntent(id: id, member: member, source: source, reference: reference, product: product.productIdentifier,
                                  installation: DeviceCredential.installationID(), edition: edition, legacy: false, localTest: localStoreKitSession)
        try journal.update { $0.intents[id] = intent }
        var body = context(intent)
        body["action"] = "prepare"
        guard (intent.localTest == true) == localStoreKitSession else { throw WalletError.testEnvironment }
        if !localStoreKitSession {
            if source == .local, try !overlay(member).read().migrated {
                try await serialize(member) { try await self.migrate(member) }
            }
            _ = try await edge("district-wallet", body, member)
        }
        guard account == member, scene.activationState == .foregroundActive else { throw WalletError.accountChanged }
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = id.uuidString.lowercased()
        payment.quantity = 1
        try journal.update { $0.intents[id]?.stage = .submitted }
        submittedPayments[id] = payment
        return try await withCheckedThrowingContinuation { continuation in
            waiting = (id, continuation)
            SKPaymentQueue.default().add(payment)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                self?.endInteraction(id, result: .failure(WalletError.outcomeUnknown))
            }
        }
    }

    func context(_ intent: WalletIntent) -> [String: Any] {
        var body: [String: Any] = ["orderSource": intent.source.rawValue, "catalogPack": intent.product, "packQuantity": intent.quantity,
                                   "cityEdition": intent.edition, "installationID": intent.installation]
        if !intent.legacy { body["intentID"] = intent.id.uuidString.lowercased() }
        if let reference = intent.reference { body["districtOrder"] = reference }
        return body
    }

    func endInteraction(_ id: UUID, result: Result<String?, Error>) {
        guard let current = waiting, current.id == id else { return }
        waiting = nil
        checkouts.remove(id)
        current.continuation.resume(with: result)
    }
}

extension Wallet: SKPaymentTransactionObserver {
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in for transaction in transactions { self.handle(transaction) } }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions {
                self.finishRequested.remove(ObjectIdentifier(transaction))
                guard let tid = transaction.transactionIdentifier else { continue }
                try? self.journal.update { state in
                    guard let id = state.intents.first(where: {
                        $0.value.transaction == tid && $0.value.product == transaction.payment.productIdentifier && $0.value.stage == .finishing
                    })?.key else { return }
                    state.intents[id]?.stage = .completed
                }
            }
        }
    }

    func handle(_ transaction: SKPaymentTransaction) {
        let payment = transaction.payment
        let token = payment.applicationUsername.flatMap(UUID.init(uuidString:))
        let objectOwner = submittedPayments.first(where: { $0.value === payment })?.key
        switch transaction.transactionState {
        case .purchased:
            let key = ObjectIdentifier(transaction)
            guard transactionsInProgress.insert(key).inserted else { return }
            transactionTasks[key] = Task {
                defer { transactionsInProgress.remove(key); transactionTasks.removeValue(forKey: key) }
                await recoverPurchased(transaction, objectOwner: objectOwner)
            }
        case .failed, .deferred:
            do {
                let state = try journal.read()
                if let id = objectOwner ?? token, let intent = state.intents[id],
                   intent.transaction == nil, intent.product == payment.productIdentifier {
                    let deferred = transaction.transactionState == .deferred
                    try journal.update { $0.intents[id]?.stage = deferred ? .deferred : .failed }
                    let cancelled = (transaction.error as? SKError)?.code == .paymentCancelled
                    let outcome: Result<String?, Error> = deferred ? .success(WalletError.pendingApproval.localizedDescription) :
                        (cancelled ? .success(nil) : .failure(WalletError.productUnavailable))
                    endInteraction(id, result: outcome)
                    if !deferred { submittedPayments.removeValue(forKey: id) }
                }
                if transaction.transactionState == .failed { SKPaymentQueue.default().finishTransaction(transaction) }
            } catch {
                if let id = objectOwner ?? token { endInteraction(id, result: .failure(error)) }
            }
        case .purchasing, .restored: break
        @unknown default: break
        }
    }
}
