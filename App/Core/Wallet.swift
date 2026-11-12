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
    var credited: Int { purchases.reduce(0) { $0 + $1.diamonds } }
    var balance: Int { credited - (districtUnlocks ?? [:]).values.reduce(0) { $0 + $1.diamonds } }

    func isUnlocked(_ district: CityDistrict) -> Bool {
        district == .central || districtUnlocks?[district.rawValue] != nil
    }
}

enum WalletError: LocalizedError {
    case invalidCatalog, productUnavailable, paymentsRestricted, unverified, accountChanged, invalidLedger, deliveryPending, insufficientDiamonds

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "The diamond catalog is unavailable."
        case .productUnavailable: return "This pack is no longer available. Pull down to check prices again."
        case .paymentsRestricted: return "In-app purchases are restricted on this iPhone."
        case .unverified: return "Apple could not verify this purchase."
        case .accountChanged: return "Log in to the original account to complete this purchase."
        case .invalidLedger: return "Your wallet could not be opened. Please try again."
        case .deliveryPending: return "Your purchase is awaiting delivery. Pull down to check your balance again."
        case .insufficientDiamonds: return "You do not have enough diamonds to unlock this district."
        }
    }
}

@MainActor
final class Wallet {
    static let didChange = Notification.Name("SeseWalletChanged")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sese", category: "InAppPurchase")
    private var account: UUID?
    private var observer: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var isPurchasing = false

    init() {
        observer = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self, let account = self.account else { continue }
                try? await self.deliver(update, to: account)
            }
        }
    }

    deinit {
        observer?.cancel()
        recovery?.cancel()
    }

    func bind(_ member: UUID?) {
        recovery?.cancel()
        account = member
        if let member { recover(for: member) }
    }

    func recover(for member: UUID) {
        guard member == account, recovery == nil || recovery?.isCancelled == true else { return }
        recovery = Task { [weak self] in
            for await transaction in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                guard let self, self.account == member else { return }
                try? await self.deliver(transaction, to: member)
            }
            if !Task.isCancelled { self?.recovery = nil }
        }
    }

    func offers() throws -> [WalletOffer] {
        try configuredOffers().values.sorted { $0.diamonds < $1.diamonds }
    }

    func catalog() async throws -> [String: Product] {
        let offers = try configuredOffers()
        guard !offers.isEmpty else { return [:] }
        let requested = offers.keys.sorted()
        logger.info("Requesting \(requested.count) diamond packs. Payments allowed: \(AppStore.canMakePayments).")
        do {
            let products = try await Product.products(for: requested)
            let catalog = products.reduce(into: [String: Product]()) { catalog, product in
                guard product.type == .consumable, offers[product.id] != nil else { return }
                catalog[product.id] = product
            }
            let missing = requested.filter { catalog[$0] == nil }.joined(separator: ", ")
            logger.info("Received \(catalog.count) diamond packs. Unavailable IDs: \(missing, privacy: .public)")
            return catalog
        } catch {
            logFailure(error, stage: "Catalog request")
            throw error
        }
    }

    func buy(_ product: Product, member: UUID, in scene: UIWindowScene) async throws -> String? {
        guard account == member else { throw WalletError.accountChanged }
        guard !isPurchasing else { return nil }
        guard AppStore.canMakePayments else { throw WalletError.paymentsRestricted }
        guard product.type == .consumable, try configuredOffers()[product.id] != nil else { throw WalletError.invalidCatalog }
        isPurchasing = true
        defer { isPurchasing = false }
        let options: Set<Product.PurchaseOption> = [.appAccountToken(member)]
        let purchase: Product.PurchaseResult
        do {
            if #available(iOS 17.0, *) {
                purchase = try await product.purchase(confirmIn: scene, options: options)
            } else {
                purchase = try await product.purchase(options: options)
            }
        } catch Product.PurchaseError.productUnavailable {
            logger.info("Pack \(product.id, privacy: .public) was unavailable at checkout.")
            throw WalletError.productUnavailable
        } catch Product.PurchaseError.purchaseNotAllowed {
            throw WalletError.paymentsRestricted
        } catch {
            logFailure(error, stage: "Purchase request")
            throw error
        }
        switch purchase {
        case .success(let result):
            do {
                try await deliver(result, to: member)
            } catch WalletError.accountChanged {
                throw WalletError.accountChanged
            } catch WalletError.unverified {
                throw WalletError.unverified
            } catch {
                logFailure(error, stage: "Diamond delivery")
                throw WalletError.deliveryPending
            }
            return "Diamonds added to your wallet."
        case .pending: return "Apple is waiting for approval. Your balance will update after confirmation."
        case .userCancelled: return nil
        @unknown default: return "Apple has not confirmed this purchase."
        }
    }

    private func logFailure(_ error: Error, stage: String) {
        let failure = error as NSError
        logger.error("\(stage, privacy: .public) failed with \(failure.domain, privacy: .public) code \(failure.code).")
    }

    func ledger(for member: UUID) throws -> WalletLedger {
        let file = try ledgerURL(member)
        do {
            let ledger = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: file))
            var transactionIDs = Set<UInt64>()
            var balance = 0
            for purchase in ledger.purchases {
                guard transactionIDs.insert(purchase.transactionID).inserted,
                      purchase.diamonds > 0, purchase.diamonds <= Int.max - balance else {
                    throw WalletError.invalidLedger
                }
                balance += purchase.diamonds
            }
            for (id, unlock) in ledger.districtUnlocks ?? [:] {
                guard let district = CityDistrict(rawValue: id), district != .central,
                      unlock.diamonds > 0, unlock.diamonds <= balance else {
                    throw WalletError.invalidLedger
                }
                balance -= unlock.diamonds
            }
            return ledger
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return WalletLedger()
        }
    }

    func unlock(_ district: CityDistrict, for member: UUID) throws {
        guard account == member else { throw WalletError.accountChanged }
        var ledger = try ledger(for: member)
        guard !ledger.isUnlocked(district) else { return }
        guard ledger.balance >= district.diamondCost else { throw WalletError.insufficientDiamonds }
        var unlocks = ledger.districtUnlocks ?? [:]
        unlocks[district.rawValue] = DistrictUnlock(diamonds: district.diamondCost, date: Date())
        ledger.districtUnlocks = unlocks
        try save(ledger, for: member)
    }

    private func save(_ ledger: WalletLedger, for member: UUID) throws {
        let file = try ledgerURL(member)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func configuredOffers() throws -> [String: WalletOffer] {
        let offers = try Resources.decode([WalletOffer].self, "Products.json")
        var unique: [String: WalletOffer] = [:]
        for offer in offers {
            guard !offer.productID.isEmpty, (1...1_000_000).contains(offer.diamonds),
                  unique.updateValue(offer, forKey: offer.productID) == nil else { throw WalletError.invalidCatalog }
        }
        return unique
    }

    private func deliver(_ result: VerificationResult<Transaction>, to member: UUID) async throws {
        guard case .verified(let transaction) = result else { throw WalletError.unverified }
        guard transaction.appAccountToken == member, account == member else { throw WalletError.accountChanged }
        guard transaction.productType == .consumable, transaction.revocationDate == nil,
              transaction.appBundleID == Bundle.main.bundleIdentifier,
              let offer = try configuredOffers()[transaction.productID] else { throw WalletError.invalidCatalog }
        var ledger = try ledger(for: member)
        if !ledger.purchases.contains(where: { $0.transactionID == transaction.id }) {
            let (diamonds, overflow) = offer.diamonds.multipliedReportingOverflow(by: transaction.purchasedQuantity)
            guard !overflow, diamonds > 0, diamonds <= Int.max - ledger.credited else {
                throw WalletError.invalidLedger
            }
            ledger.purchases.insert(WalletPurchase(transactionID: transaction.id, productID: offer.productID,
                                                   diamonds: diamonds, date: transaction.purchaseDate), at: 0)
            try save(ledger, for: member)
        }
        await transaction.finish()
        logger.info("Finished pack \(offer.productID, privacy: .public) in \(transaction.environment.rawValue, privacy: .public).")
    }

    private func ledgerURL(_ member: UUID) throws -> URL {
        // Keep the existing ledger directory when the display name changes.
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("CityCommunity/Wallet", isDirectory: true)
            .appendingPathComponent("\(member.uuidString).json")
    }
}
