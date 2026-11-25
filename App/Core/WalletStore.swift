import CoreFoundation
import CryptoKit
import Foundation

enum WalletJSON {
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)) else { return nil }
        return Int(number.stringValue)
    }
}

enum WalletFiles {
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CityCommunity/Wallet", isDirectory: true)
    }
}

protocol WalletStored: Codable { init() }

struct WalletStore<State: WalletStored> {
    let name: String
    private struct Snapshot: Codable {
        let schema: Int
        let generation: Int
        let bytes: Data
        let digest: Data
    }

    private func latest() throws -> (generation: Int, state: State) {
        let folder = try WalletFiles.directory()
        var found = false
        var best: (Int, State)?
        for suffix in [".current", ".backup"] {
            let bytes: Data
            do { bytes = try Data(contentsOf: folder.appendingPathComponent(name + suffix)) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { continue }
            found = true
            guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: bytes), snapshot.schema == 1,
                  snapshot.generation > 0, Data(SHA256.hash(data: snapshot.bytes)) == snapshot.digest,
                  let state = try? JSONDecoder().decode(State.self, from: snapshot.bytes) else { continue }
            if best == nil || snapshot.generation > best!.0 { best = (snapshot.generation, state) }
        }
        if let best { return best }
        guard !found else { throw WalletError.invalidLedger }
        return (0, State())
    }

    func read() throws -> State { try latest().state }

    func update(_ edit: (inout State) throws -> Void) throws {
        var (generation, state) = try latest()
        try edit(&state)
        let bytes = try JSONEncoder().encode(state)
        generation += 1
        let snapshot = Snapshot(schema: 1, generation: generation, bytes: bytes, digest: Data(SHA256.hash(data: bytes)))
        let encoded = try JSONEncoder().encode(snapshot)
        let folder = try WalletFiles.directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in [".backup", ".current"] {
            var file = folder.appendingPathComponent(name + suffix)
            try encoded.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        }
    }
}

enum WalletSpend: Codable {
    case build(BuiltDistrict)
    case unlock(String)
    var kind: String { if case .build = self { return "build" }; return "unlock" }
    var id: String {
        switch self {
        case .build(let district): return district.id.uuidString.lowercased()
        case .unlock(let id): return id
        }
    }
    var key: String { kind + "/" + id }
}

struct CloudWallet: WalletStored {
    var migrated = false
    var balance: Int?
    var balanceUpdatedAt: Date?
    var purchases: [WalletPurchase] = []
    var testDeliveries: Set<UUID>?
    var unlocks: [String: DistrictUnlock] = [:]
    var districts: [BuiltDistrict] = []
    var pending: [String: WalletSpend] = [:]
}

enum WalletSource: String, Codable { case local = "districtWallet", order = "communityOrder" }
enum WalletStage: String, Codable { case prepared, submitted, deferred, paid, confirmed, finishing, completed, failed }

struct WalletIntent: Codable {
    static let currentContract = "com.sese.citycommunit/32948410/diamond-settlement/community-wallet-confirm-order"
    let id: UUID
    let member: UUID
    let source: WalletSource
    let reference: String?
    let product: String
    let installation: String
    let edition: String
    let legacy: Bool
    var localTest: Bool?
    var quantity = 1
    var contract = currentContract
    var created = Date()
    var stage = WalletStage.prepared
    var transaction: String?
    var environment: String?
    var confirmedBalance: Int?
    var confirmedAt: Date?
    var receipt: Data?
    var evidenceVersion = 0
    var rejectedDigest: Data?
    var retryAfter: Date?
    var lastIssue: String?
}

struct WalletUnmatched: Codable {
    let transaction: String
    let environment: String?
    let product: String
    let observed: Date
}

struct WalletJournal: WalletStored {
    var intents: [UUID: WalletIntent] = [:]
    var unmatched: [String: WalletUnmatched] = [:]
}
