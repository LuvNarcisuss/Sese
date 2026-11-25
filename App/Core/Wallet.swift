import Foundation
import OSLog
import StoreKit
import UIKit

struct WalletOffer: Decodable {
    let productID: String
    let diamonds: Int
}

struct WalletPurchase: Codable {
    let transactionID: UInt64
    let productID: String
    let diamonds: Int
    let date: Date
}

enum CityDistrict: String, CaseIterable {
    case central = "city-center"
    case sahara = "district-sahara"
    case tundra = "district-tundra"
    case rainforest = "district-rainforest"

    var name: String {
        switch self {
        case .central: return "City Center"
        case .sahara: return "Sahara Square"
        case .tundra: return "Tundratown"
        case .rainforest: return "Rainforest District"
        }
    }

    var diamondCost: Int {
        switch self {
        case .central: return 0
        case .sahara: return 30
        case .tundra: return 45
        case .rainforest: return 60
        }
    }
}

struct DistrictUnlock: Codable {
    let diamonds: Int
    let date: Date
}

struct WalletLedger: Codable {
    var purchases: [WalletPurchase] = []
    var districtUnlocks: [String: DistrictUnlock]?
    var builtDistricts: [BuiltDistrict]?
    var credited: Int { purchases.reduce(0) { $0 + $1.diamonds } }
    var cloudBalance: Int?
    var balance: Int {
        if let cloudBalance { return cloudBalance }
        let unlocked = (districtUnlocks ?? [:]).values.reduce(0) { $0 + $1.diamonds }
        let built = (builtDistricts ?? []).reduce(0) { $0 + $1.diamonds }
        return credited - unlocked - built
    }

    func isUnlocked(_ district: CityDistrict) -> Bool {
        district == .central || districtUnlocks?[district.rawValue] != nil
    }
}

enum WalletError: LocalizedError {
    case invalidCatalog, productUnavailable, paymentsRestricted, unverified, accountChanged, invalidLedger, deliveryPending, insufficientDiamonds
    case invalidDistrictName, testCurrency, testEnvironment, busy, reconciliation, pendingApproval, outcomeUnknown, unavailable, evidenceRequired

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "The diamond catalog is unavailable."
        case .productUnavailable: return "This pack is no longer available. Pull down to check prices again."
        case .paymentsRestricted: return "In-app purchases are restricted on this iPhone."
        case .unverified: return "Apple could not verify this purchase."
        case .accountChanged: return "Log in to the original account to complete this purchase."
        case .invalidLedger: return "Your wallet could not be opened. Please try again."
        case .deliveryPending: return "Your purchase is awaiting delivery. Pull down to check your balance again."
        case .insufficientDiamonds: return "You do not have enough diamonds for this district."
        case .testEnvironment: return "This purchase is awaiting settlement in its original test environment."
        case .testCurrency: return "This local StoreKit wallet is available for purchase testing only."
        case .busy: return "Another purchase is open."
        case .reconciliation: return "A previous transaction needs review. Open your wallet to check its status."
        case .pendingApproval: return "Apple is waiting for approval."
        case .outcomeUnknown: return "Apple has not returned a new transaction. Check your wallet before trying again."
        case .unavailable: return "Connect to your account to update your wallet."
        case .evidenceRequired: return "The App Store receipt is unavailable. Pull down in Wallet to retry."
        case .invalidDistrictName: return "Enter a district name between 1 and 30 characters."
        }
    }
}

@MainActor
final class Wallet: NSObject {
    static let shared = Wallet()
    static let didChange = Notification.Name("SeseWalletChanged")
    weak var api: CommunityAPI?
    private(set) var account: UUID?
    #if DEBUG && targetEnvironment(simulator)
    var localStoreKitSession = ProcessInfo.processInfo.environment["SESE_LOCAL_STOREKIT"] == "1"
    #else
    var localStoreKitSession: Bool { false }
    #endif

    func identifyStoreKitSession() async {
        #if DEBUG && targetEnvironment(simulator)
        guard !localStoreKitSession else { return }
        if let result = try? await AppTransaction.shared, case .verified(let signed) = result,
           signed.bundleID == Bundle.main.bundleIdentifier, signed.environment == .xcode {
            localStoreKitSession = true
        }
        #endif
    }

    func testStore(_ member: UUID) -> WalletStore<CloudWallet> {
        WalletStore(name: "xcode-diamonds-" + member.uuidString)
    }
    let journal = WalletStore<WalletJournal>(name: "payment-journal")
    var waiting: (id: UUID, continuation: CheckedContinuation<String?, Error>)?
    var submittedPayments: [UUID: SKPayment] = [:]
    var checkouts: Set<UUID> = []
    var pendingCheckouts: Set<String> = []
    var transactionsInProgress = Set<ObjectIdentifier>()
    var settlingIDs = Set<String>()
    var finishRequested = Set<ObjectIdentifier>()
    var requestClients: [UUID: WalletStoreRequest] = [:]
    var receiptRefresh: (started: Date, task: Task<Data, Error>)?
    var retryTask: Task<Void, Never>?
    var retryDeadline: Date?
    var allowsReceiptPrompt = Set<UUID>()
    private var operations: [UUID: (id: UUID, tail: Task<Void, Never>)] = [:]
    private var recovery: (member: UUID, id: UUID, task: Task<Void, Error>)?

    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }

    func bind(_ member: UUID?) {
        let previous = account
        account = member
        if previous != member {
            if let id = waiting?.id { endInteraction(id, result: .failure(WalletError.accountChanged)) }
            allowsReceiptPrompt.removeAll()
            retryTask?.cancel()
            retryTask = nil
            retryDeadline = nil
        }
        if let member { recover(for: member) }
    }

    func recover(for member: UUID) {
        guard account == member else { return }
        Task { try? await recoverAndWait(for: member) }
    }

    func recoverAndWait(for member: UUID, userInitiated: Bool = false) async throws {
        guard account == member else { throw WalletError.accountChanged }
        if userInitiated { allowsReceiptPrompt.insert(member) }
        if let recovery, recovery.member == member { return try await recovery.task.value }
        let id = UUID()
        let task = Task { @MainActor in
            defer {
                if recovery?.id == id { recovery = nil }
                allowsReceiptPrompt.remove(member)
            }
            // Recover Apple transactions even when migration or one district spend needs attention.
            for transaction in SKPaymentQueue.default().transactions { handle(transaction) }
            try await refreshBalance(for: member)
            if localStoreKitSession { await waitForCurrentTransactions(); return }
            let state = try overlay(member).read()
            for spend in state.pending.values { try await settleSpend(spend, member: member) }
            await waitForCurrentTransactions()
        }
        recovery = (member, id, task)
        try await task.value
    }

    var transactionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private func waitForCurrentTransactions() async {
        for task in Array(transactionTasks.values) { await task.value }
    }

    func offers() throws -> [WalletOffer] {
        let offers = try Resources.decode([WalletOffer].self, "Products.json")
        guard !offers.isEmpty, Set(offers.map(\.productID)).count == offers.count,
              offers.allSatisfy({ !$0.productID.isEmpty && (1...1_000_000).contains($0.diamonds) }) else {
            throw WalletError.invalidCatalog
        }
        return offers.sorted { $0.diamonds < $1.diamonds }
    }

    func ledger(for member: UUID) throws -> WalletLedger {
        #if DEBUG && targetEnvironment(simulator)
        if localStoreKitSession {
            let state = try testStore(member).read()
            return WalletLedger(purchases: state.purchases, districtUnlocks: state.unlocks, builtDistricts: state.districts, cloudBalance: state.balance ?? 0)
        }
        #endif
        var ledger = try legacyLedger(member)
        let current = try overlay(member).read()
        ledger.cloudBalance = current.balance
        ledger.purchases = current.purchases + ledger.purchases
        ledger.districtUnlocks = (ledger.districtUnlocks ?? [:]).merging(current.unlocks) { old, _ in old }
        ledger.builtDistricts = current.districts + (ledger.builtDistricts ?? [])
        return ledger
    }

    private func legacyLedger(_ member: UUID) throws -> WalletLedger {
        let file = try WalletFiles.directory().appendingPathComponent("\(member.uuidString).json")
        let ledger: WalletLedger
        do { ledger = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return WalletLedger()
        }
        var remaining = 0
        var purchases = Set<UInt64>()
        for purchase in ledger.purchases {
            guard purchases.insert(purchase.transactionID).inserted, !purchase.productID.isEmpty,
                  purchase.diamonds > 0, purchase.diamonds <= Int.max - remaining else { throw WalletError.invalidLedger }
            remaining += purchase.diamonds
        }
        for (id, unlock) in ledger.districtUnlocks ?? [:] {
            guard let district = CityDistrict(rawValue: id), district != .central,
                  unlock.diamonds > 0, unlock.diamonds <= remaining else { throw WalletError.invalidLedger }
            remaining -= unlock.diamonds
        }
        var districts = Set<UUID>()
        for district in ledger.builtDistricts ?? [] {
            guard districts.insert(district.id).inserted, BuiltDistrict.validName(district.name) == district.name,
                  district.diamonds > 0, district.diamonds <= remaining else { throw WalletError.invalidLedger }
            remaining -= district.diamonds
        }
        return ledger
    }

    func overlay(_ member: UUID) -> WalletStore<CloudWallet> {
        WalletStore(name: "cloud-wallet-\(member.uuidString)")
    }

    func notify(_ member: UUID) {
        if account == member { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    // Serialize cloud operations and their local commits so an older response cannot replace a newer balance.
    func serialize<T>(_ member: UUID, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = operations[member]?.tail
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard self.account == member else { throw WalletError.accountChanged }
            return try await operation()
        }
        operations[member] = (id, Task { _ = await task.result })
        defer { if operations[member]?.id == id { operations[member] = nil } }
        return try await task.value
    }

    func edge(_ name: String, _ body: [String: Any], _ member: UUID) async throws -> [String: Any] {
        guard account == member, let api else { throw WalletError.accountChanged }
        let response = try await api.callEdge(name, body: body, account: member)
        guard WalletJSON.integer(response["code"]) == 0, let data = response["data"] as? [String: Any] else {
            throw CommunityError.invalidResponse
        }
        return data
    }

    func balance(_ data: [String: Any]) throws -> Int {
        guard let amount = WalletJSON.integer(data["balance"]), amount >= 0 else { throw CommunityError.invalidResponse }
        return amount
    }

    func migrate(_ member: UUID) async throws {
        let store = overlay(member)
        guard try !store.read().migrated else { return }
        let old = try legacyLedger(member)
        var evidence: [UInt64: String] = [:]
        if !old.purchases.isEmpty {
            let purchases = Dictionary(uniqueKeysWithValues: old.purchases.map { ($0.transactionID, $0) })
            for await result in Transaction.all {
                guard case .verified(let transaction) = result, let purchase = purchases[transaction.id],
                      transaction.appAccountToken == member, transaction.appBundleID == Bundle.main.bundleIdentifier,
                      transaction.productType == .consumable, transaction.revocationDate == nil,
                      purchase.productID == transaction.productID else { continue }
                evidence[transaction.id] = result.jwsRepresentation
            }
        }
        let purchases: [[String: Any]] = old.purchases.map {
            var row: [String: Any] = ["transactionID": String($0.transactionID), "productID": $0.productID, "diamonds": $0.diamonds]
            if let jws = evidence[$0.transactionID] { row["signedTransaction"] = jws }
            return row
        }
        let unlocks: [[String: Any]] = (old.districtUnlocks ?? [:]).map { ["id": $0.key, "diamonds": $0.value.diamonds] }
        let districts: [[String: Any]] = (old.builtDistricts ?? []).map { ["id": $0.id.uuidString.lowercased(), "diamonds": $0.diamonds] }
        var body: [String: Any] = ["action": "migrate", "purchases": purchases, "unlocks": unlocks, "districts": districts]
        if !purchases.isEmpty, let proof = await Self.appEvidence() { body["signedAppTransaction"] = proof }
        let result = try await edge("district-wallet", body, member)
        let amount = try balance(result)
        try store.update { $0.migrated = true; $0.balance = amount; $0.balanceUpdatedAt = Date() }
        notify(member)
    }

    func refreshBalance(for member: UUID) async throws {
        await identifyStoreKitSession()
        if localStoreKitSession { notify(member); return }
        try await serialize(member) {
            try await self.migrate(member)
            let result = try await self.edge("district-wallet", ["action": "balance"], member)
            let amount = try self.balance(result)
            try self.overlay(member).update { $0.balance = amount; $0.balanceUpdatedAt = Date() }
            self.notify(member)
        }
    }

    func unlock(_ district: CityDistrict, for member: UUID) async throws {
        guard district != .central, try !ledger(for: member).isUnlocked(district) else { return }
        try await settleSpend(.unlock(district.rawValue), member: member)
    }

    func buildDistrict(id: UUID, name: String, style: DistrictStyle, plan: DistrictPlan, for member: UUID) async throws -> BuiltDistrict {
        guard let name = BuiltDistrict.validName(name) else { throw WalletError.invalidDistrictName }
        let district = BuiltDistrict(id: id, name: name, style: style, plan: plan, diamonds: BuiltDistrict.price, date: Date())
        try await settleSpend(.build(district), member: member)
        guard let saved = try ledger(for: member).builtDistricts?.first(where: { $0.id == id }) else { throw WalletError.invalidLedger }
        return saved
    }

    private func settleSpend(_ requested: WalletSpend, member: UUID) async throws {
        guard !localStoreKitSession else { throw WalletError.testCurrency }
        try await serialize(member) {
            try await self.migrate(member)
            let store = self.overlay(member)
            let state = try store.read()
            let spend = state.pending[requested.key] ?? requested
            let ledger = try self.ledger(for: member)
            switch spend {
            case .build(let district) where ledger.builtDistricts?.contains(where: { $0.id == district.id }) == true: return
            case .unlock(let id) where ledger.districtUnlocks?[id] != nil: return
            default: break
            }
            // Preserve the member's design before the debit. Replay uses exactly the same server idempotency key.
            try store.update { $0.pending[spend.key] = spend }
            do {
                let response = try await self.edge("district-wallet", ["action": "spend", "kind": spend.kind, "id": spend.id], member)
                let amount = try self.balance(response)
                try store.update { state in
                    switch spend {
                    case .build(let district): state.districts.insert(district, at: 0)
                    case .unlock(let id):
                        guard let district = CityDistrict(rawValue: id) else { throw WalletError.invalidLedger }
                        state.unlocks[id] = DistrictUnlock(diamonds: district.diamondCost, date: Date())
                    }
                    state.balance = amount
                    state.balanceUpdatedAt = Date()
                    state.pending.removeValue(forKey: spend.key)
                }
                self.notify(member)
            } catch let error as EdgeCallError where error.reason == "insufficient_balance" {
                try store.update { $0.pending.removeValue(forKey: spend.key) }
                throw WalletError.insufficientDiamonds
            }
        }
    }
}
