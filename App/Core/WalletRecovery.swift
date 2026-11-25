import CryptoKit
import Foundation
import StoreKit
import UIKit

extension Wallet {
    static func appEvidence() async -> String? {
        guard let result = try? await AppTransaction.shared, case .verified = result else { return nil }
        return result.jwsRepresentation
    }

    private func verification(_ id: String) async throws -> VerificationResult<Transaction> {
        for await result in Transaction.unfinished {
            guard String(result.unsafePayloadValue.id) == id else { continue }
            guard case .verified = result else { throw WalletError.unverified }
            return result
        }
        throw WalletError.evidenceRequired
    }

    func recoverPurchased(_ transaction: SKPaymentTransaction, objectOwner: UUID?) async {
        guard let tid = transaction.transactionIdentifier, !tid.isEmpty else {
            if let id = objectOwner { endInteraction(id, result: .failure(WalletError.reconciliation)) }
            return
        }
        var original: WalletIntent?
        do {
            let verified = try await verification(tid)
            guard case .verified(let signed) = verified, signed.productType == .consumable, signed.revocationDate == nil,
                  signed.appBundleID == Bundle.main.bundleIdentifier, signed.productID == transaction.payment.productIdentifier,
                  signed.purchasedQuantity == transaction.payment.quantity, signed.purchasedQuantity > 0 else { throw WalletError.unverified }
            let environment = signed.environment.rawValue
            let scope = signed.environment == .xcode ? (signed.appAccountToken?.uuidString ?? "unknown") : environment
            let key = scope + "/" + tid
            guard settlingIDs.insert(key).inserted else { return }
            defer { settlingIDs.remove(key) }
            guard let intent = try await associate(tid, signed: signed, objectOwner: objectOwner) else {
                try markUnmatched(tid, product: signed.productID, environment: environment)
                if let id = objectOwner { endInteraction(id, result: .failure(WalletError.reconciliation)) }
                return
            }
            guard intent.member == account else { return }
            guard intent.contract == WalletIntent.currentContract, intent.quantity == signed.purchasedQuantity,
                  intent.product == signed.productID, intent.transaction == nil || intent.transaction == tid,
                  intent.environment == nil || intent.environment == environment else { throw WalletError.reconciliation }
            original = intent
            if let objectOwner, objectOwner != intent.id { endInteraction(objectOwner, result: .failure(WalletError.outcomeUnknown)) }
            try journal.update {
                $0.unmatched.removeValue(forKey: environment + "/" + tid)
                $0.unmatched.removeValue(forKey: "unknown/" + tid)
                guard var stored = $0.intents[intent.id] else { throw WalletError.invalidLedger }
                stored.transaction = tid
                stored.environment = environment
                switch stored.stage {
                case .completed, .confirmed, .finishing: break
                default: stored.stage = .paid
                }
                $0.intents[intent.id] = stored
            }
            let newlySubmitted = waiting?.id == intent.id
            if newlySubmitted {
                allowsReceiptPrompt.insert(intent.member)
                endInteraction(intent.id, result: .success("Apple confirmed your payment. Your order is awaiting delivery."))
            }
            submittedPayments.removeValue(forKey: intent.id)
            defer { if newlySubmitted { allowsReceiptPrompt.remove(intent.member) } }
            var current = try record(intent.id)
            #if DEBUG && targetEnvironment(simulator)
            if signed.environment == .xcode, intent.localTest == true, intent.source == .local,
               signed.appAccountToken == intent.id, !intent.legacy {
                localStoreKitSession = true
                try commitTestPurchase(current, transaction: signed)
                try finishPurchased(transaction, intent: try record(intent.id))
                return
            }
            #endif
            guard signed.environment == .production, intent.localTest != true else { throw WalletError.testEnvironment }
            switch current.stage {
            case .completed, .finishing:
                try finishPurchased(transaction, intent: current)
                return
            case .confirmed:
                try await serialize(intent.member) {
                    try self.commitDelivery(current, transaction: signed)
                }
                try finishPurchased(transaction, intent: current)
                return
            default: break
            }
            let interactive = newlySubmitted || allowsReceiptPrompt.contains(intent.member)
            if !interactive {
                if let date = current.retryAfter, date > Date() {
                    scheduleRetry(at: date, for: current.member)
                    return
                }
                if let issue = current.lastIssue, !["network", "processing", "identity", "receipt", "storage"].contains(issue) { return }
            }
            var receipt = try await obtainReceipt(current, transaction: tid, purchased: signed.purchaseDate, interactive: interactive)
            let appProof = await Self.appEvidence()
            var refreshedAfterRejection = false
            var attempts = 0
            while true {
                attempts += 1
                do {
                    try await serialize(intent.member) {
                        let latest = try self.record(intent.id)
                        guard latest.stage == .paid, latest.environment == environment, latest.transaction == tid else { return }
                        if latest.source == .local { try await self.migrate(latest.member) }
                        var body = self.context(latest)
                        body["storeEnvironment"] = environment
                        body["storeTransaction"] = tid
                        body["storeReceipt"] = receipt.base64EncodedString()
                        body["signedTransaction"] = verified.jwsRepresentation
                        if let appProof { body["signedAppTransaction"] = appProof }
                        let data = try await self.edge("diamond-settlement", body, latest.member)
                        let amount = try self.balance(data)
                        try self.journal.update {
                            $0.intents[intent.id]?.confirmedBalance = amount
                            $0.intents[intent.id]?.confirmedAt = Date()
                            $0.intents[intent.id]?.stage = .confirmed
                            $0.intents[intent.id]?.lastIssue = nil
                            $0.intents[intent.id]?.retryAfter = nil
                        }
                        try self.commitDelivery(try self.record(intent.id), transaction: signed)
                    }
                    current = try record(intent.id)
                    try finishPurchased(transaction, intent: current)
                    return
                } catch let error as EdgeCallError where error.reason == "receipt_missing_transaction" {
                    try journal.update { $0.intents[intent.id]?.rejectedDigest = Data(SHA256.hash(data: receipt)) }
                    guard !refreshedAfterRejection, interactive, attempts < 3 else { throw WalletError.evidenceRequired }
                    refreshedAfterRejection = true
                    receipt = try await obtainReceipt(try record(intent.id), transaction: tid, purchased: signed.purchaseDate, interactive: true)
                } catch {
                    guard Self.transient(error), attempts < 3, account == intent.member else { throw error }
                    let delay = attempts == 1 ? 2.0 : 5.0
                    try await Task.sleep(nanoseconds: UInt64((delay + Double.random(in: 0...0.5)) * 1_000_000_000))
                }
            }
        } catch {
            if let original {
                let transient = Self.transient(error)
                let next = transient ? Date().addingTimeInterval(65 + Double.random(in: 0...8)) : nil
                let reason: String
                switch error {
                case let edge as EdgeCallError:
                    if edge.status == 401 { reason = "identity" }
                    else { reason = transient ? "network" : (edge.reason ?? "unrecognized_response") }
                case WalletError.accountChanged: reason = "identity"
                case WalletError.testEnvironment: reason = "environment_mismatch"
                case WalletError.evidenceRequired: reason = "receipt"
                case WalletError.unverified: reason = "verification"
                default: reason = transient ? "network" : "storage"
                }
                try? journal.update {
                    $0.intents[original.id]?.lastIssue = reason
                    $0.intents[original.id]?.retryAfter = next
                }
                if let next { scheduleRetry(at: next, for: original.member) }
                notify(original.member)
            } else {
                try? markUnmatched(tid, product: transaction.payment.productIdentifier, environment: nil)
                if let id = objectOwner { endInteraction(id, result: .failure(WalletError.reconciliation)) }
            }
        }
    }

    private static func transient(_ error: Error) -> Bool {
        if let edge = error as? EdgeCallError {
            return ["processing", "service_unavailable"].contains(edge.reason ?? "") || edge.status == 429 ||
                ([502, 503, 504].contains(edge.status) && edge.reason == nil)
        }
        if let url = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(url.code)
        }
        return false
    }

    func scheduleRetry(at date: Date, for member: UUID) {
        guard member == account, UIApplication.shared.applicationState == .active else { return }
        if let retryDeadline, retryTask != nil, retryDeadline <= date { return }
        retryTask?.cancel()
        retryDeadline = date
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, date.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            retryTask = nil
            retryDeadline = nil
            if UIApplication.shared.applicationState == .active { recover(for: member) }
        }
    }

    private func record(_ id: UUID) throws -> WalletIntent {
        guard let record = try journal.read().intents[id] else { throw WalletError.invalidLedger }
        return record
    }

    private func markUnmatched(_ tid: String, product: String, environment: String?) throws {
        let key = (environment ?? "unknown") + "/" + tid
        try journal.update {
            if $0.unmatched[key] == nil {
                $0.unmatched[key] = WalletUnmatched(transaction: tid, environment: environment, product: product, observed: Date())
            }
        }
    }

    private func associate(_ tid: String, signed: Transaction, objectOwner: UUID?) async throws -> WalletIntent? {
        let journalState = try journal.read()
        let environment = signed.environment.rawValue
        if let bound = journalState.intents.values.first(where: {
            $0.transaction == tid && $0.environment == environment && (signed.environment != .xcode || $0.id == signed.appAccountToken)
        }) {
            guard signed.appAccountToken == nil || signed.appAccountToken == (bound.legacy ? bound.member : bound.id) else {
                throw WalletError.reconciliation
            }
            return bound
        }
        if let token = signed.appAccountToken, let saved = journalState.intents[token] { return saved }
        if let objectOwner, let saved = journalState.intents[objectOwner], signed.appAccountToken == nil { return saved }
        guard let member = account, let token = signed.appAccountToken else { return nil }
        let recovered: WalletIntent
        if token == member {
            // Earlier Sese versions offered only local packs and used the member UUID as the signed app account token.
            guard try offers().contains(where: { $0.productID == signed.productID }),
                  let edition = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
            recovered = WalletIntent(id: UUID(), member: member, source: .local, reference: nil, product: signed.productID,
                                     installation: try DeviceCredential.installationID(), edition: edition, legacy: true,
                                     quantity: signed.purchasedQuantity)
        } else {
            let data = try await edge("district-wallet", ["action": "intent", "intentID": token.uuidString.lowercased()], member)
            guard let id = (data["intentID"] as? String).flatMap(UUID.init(uuidString:)), id == token,
                  let rawSource = data["orderSource"] as? String, let source = WalletSource(rawValue: rawSource),
                  data["catalogPack"] as? String == signed.productID, WalletJSON.integer(data["packQuantity"]) == signed.purchasedQuantity,
                  let installation = data["installationID"] as? String, !installation.isEmpty,
                  let edition = data["cityEdition"] as? String, !edition.isEmpty else { throw WalletError.reconciliation }
            let reference = data["districtOrder"] as? String
            if let raw = data["districtOrder"], !(raw is NSNull), reference == nil { throw WalletError.reconciliation }
            recovered = WalletIntent(id: id, member: member, source: source, reference: reference, product: signed.productID,
                                     installation: installation, edition: edition, legacy: false, quantity: signed.purchasedQuantity)
        }
        try journal.update { $0.intents[recovered.id] = recovered }
        return recovered
    }

    #if DEBUG && targetEnvironment(simulator)
    private func commitTestPurchase(_ intent: WalletIntent, transaction: Transaction) throws {
        guard intent.member == account, intent.localTest == true, intent.source == .local,
              transaction.environment == .xcode, transaction.appAccountToken == intent.id,
              let offer = try offers().first(where: { $0.productID == intent.product }) else { throw WalletError.unverified }
        let (diamonds, overflow) = offer.diamonds.multipliedReportingOverflow(by: intent.quantity)
        guard !overflow else { throw WalletError.invalidLedger }
        try testStore(intent.member).update { state in
            var delivered = state.testDeliveries ?? []
            guard delivered.insert(intent.id).inserted else { return }
            let (updated, balanceOverflow) = (state.balance ?? 0).addingReportingOverflow(diamonds)
            guard !balanceOverflow else { throw WalletError.invalidLedger }
            state.purchases.insert(WalletPurchase(transactionID: transaction.id, productID: intent.product, diamonds: diamonds,
                                                  date: transaction.purchaseDate), at: 0)
            state.balance = updated
            state.testDeliveries = delivered
        }
        try journal.update { $0.intents[intent.id]?.stage = .confirmed }
        notify(intent.member)
    }
    #endif

    private func commitDelivery(_ intent: WalletIntent, transaction: Transaction) throws {
        guard let confirmedBalance = intent.confirmedBalance else { throw WalletError.invalidLedger }
        let store = overlay(intent.member)
        let existing = try ledger(for: intent.member).purchases.contains { $0.transactionID == transaction.id }
        var purchase: WalletPurchase?
        if intent.source == .local, !existing {
            guard let offer = try offers().first(where: { $0.productID == intent.product }) else { throw WalletError.invalidCatalog }
            let (diamonds, overflow) = offer.diamonds.multipliedReportingOverflow(by: intent.quantity)
            guard !overflow else { throw WalletError.invalidLedger }
            purchase = WalletPurchase(transactionID: transaction.id, productID: intent.product, diamonds: diamonds, date: transaction.purchaseDate)
        }
        try store.update {
            if let purchase { $0.purchases.insert(purchase, at: 0) }
            // A recovered older confirmation must not replace a later cloud read.
            if $0.balanceUpdatedAt == nil || ($0.balanceUpdatedAt ?? .distantPast) <= (intent.confirmedAt ?? .distantPast) {
                $0.balance = confirmedBalance
                $0.balanceUpdatedAt = intent.confirmedAt
            }
        }
        notify(intent.member)
    }

    private func finishPurchased(_ transaction: SKPaymentTransaction, intent: WalletIntent) throws {
        guard [.confirmed, .completed, .finishing].contains(intent.stage), intent.transaction == transaction.transactionIdentifier,
              transaction.transactionState == .purchased else { throw WalletError.deliveryPending }
        let key = ObjectIdentifier(transaction)
        guard !finishRequested.contains(key) else { return }
        try journal.update {
            $0.intents[intent.id]?.stage = .finishing
            $0.intents[intent.id]?.receipt = nil
        }
        finishRequested.insert(key)
        SKPaymentQueue.default().finishTransaction(transaction)
        notify(intent.member)
    }

    private func obtainReceipt(_ intent: WalletIntent, transaction: String, purchased: Date, interactive: Bool) async throws -> Data {
        func eligible(_ data: Data) -> Bool {
            Data(SHA256.hash(data: data)) != intent.rejectedDigest && WalletReceipt.contains(transaction, in: data)
        }
        if let saved = intent.receipt, eligible(saved) { return saved }
        let data: Data
        if let current = try? Self.readReceipt(), eligible(current) { data = current }
        else {
            guard interactive, UIApplication.shared.applicationState == .active else { throw WalletError.evidenceRequired }
            if let previous = receiptRefresh, previous.started < purchased { _ = await previous.task.result }
            if let current = receiptRefresh, current.started >= purchased { data = try await current.task.value }
            else {
                let started = Date()
                let refresh = Task { @MainActor in
                    defer { if receiptRefresh?.started == started { receiptRefresh = nil } }
                    _ = try await request(SKReceiptRefreshRequest())
                    return try Self.readReceipt()
                }
                receiptRefresh = (started, refresh)
                data = try await refresh.value
            }
            guard eligible(data) else { throw WalletError.evidenceRequired }
        }
        try journal.update {
            guard $0.intents[intent.id]?.stage == .paid else { throw WalletError.deliveryPending }
            $0.intents[intent.id]?.receipt = data
            $0.intents[intent.id]?.evidenceVersion += 1
        }
        return data
    }

    private static func readReceipt() throws -> Data {
        guard let url = Bundle.main.appStoreReceiptURL else { throw WalletError.evidenceRequired }
        let bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty, bytes.count <= 8_388_608 else { throw WalletError.evidenceRequired }
        return bytes
    }

    func message(for error: Error) -> String {
        guard let error = error as? EdgeCallError else { return error.localizedDescription }
        switch error.reason {
        case "migration_review", "historical_evidence_required":
            return "Your previous wallet is available on this iPhone. Its history needs verification before you can spend online."
        case "insufficient_balance": return WalletError.insufficientDiamonds.localizedDescription
        case "environment_mismatch": return "This purchase belongs to a test environment."
        case "auth_required": return WalletError.accountChanged.localizedDescription
        default: return error.localizedDescription
        }
    }

    func hasUncertainNativePurchase(_ product: String, member: UUID) -> Bool {
        (try? journal.read().intents.values.contains {
            $0.source == .local && $0.member == member && $0.product == product && $0.stage == .submitted
        }) ?? false
    }

    func pendingStatus(for member: UUID) throws -> String? {
        let state = try journal.read()
        let intents = state.intents.values.filter { $0.member == member }
        if intents.contains(where: { $0.lastIssue == "environment_mismatch" }) {
            return "A sandbox purchase is awaiting settlement in its test environment. Your production balance is unchanged."
        }
        if intents.contains(where: { ["transaction_review", "reconciliation", "migration_review", "ownership_conflict", "upstream_declined", "verification", "historical_evidence_required"].contains($0.lastIssue ?? "") }) {
            return "A purchase needs review. Keep your App Store transaction details for support."
        }
        if intents.contains(where: { $0.stage == .paid || $0.stage == .confirmed }) { return WalletError.deliveryPending.localizedDescription }
        if intents.contains(where: { $0.stage == .deferred }) { return WalletError.pendingApproval.localizedDescription }
        if !state.unmatched.isEmpty { return "An App Store transaction on this iPhone needs its original account or order details." }
        return nil
    }
}
