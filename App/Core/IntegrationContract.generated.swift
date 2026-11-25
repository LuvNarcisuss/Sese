// Generated B-stage runtime; use the paired ConfiguredEventDecoder template.
// Deployment mappings belong in Docs, never in App resources.
import Foundation

enum IntegrationContract {
    static let namespace: String = "sese"
    static let realtimeTransport: String = "webSocket"
    static let realtimeConnectionValuePath: [String] = ["data", "districtSession"]
    static let realtimeClientID: String = "app"
    static let serverClientIDs: [String] = ["serve"]
    static let allowsMissingSender: Bool = false
    static let acceptsSerializedExpiry: Bool = true
    static let realtimeURLField: String = "socketAddress"
    static let realtimeAttachField: String = "districtSubscription"
    static let realtimeAttachActionField: String = "joinAction"
    static let realtimeAttachChannelField: String = "districtChannel"
    static let realtimeExpiryField: String? = nil
    static let continuationMode: Int = 2
    static let apiMethod: String = "POST"
    static let entryPath: String = "/community/member/entry"
    static let authAppIDLocation: String = "none"
    static let authAppIDField: String? = nil
    static let pageSignal: String = "CommunityPageReady"
    static let pageDiscriminator: [String] = ["event"]
    static let purchaseSignal: String = "DistrictCheckout"
    static let purchaseDiscriminator: [String] = ["event"]
    static let expirySignal: String = "CommunitySessionEnded"
    static let expiryDiscriminator: [String] = ["event"]
    static let externalSignal: String = "CommunityLinkRequested"
    static let externalDiscriminator: [String] = ["event"]
    static let pageAddressPath: [String] = ["pageURL"]
    static let purchaseItemPath: [String] = ["diamondPack"]
    static let purchaseReferencePath: [String] = ["orderReference"]
    static let externalAddressPath: [String] = ["destination"]
}

enum ConfiguredWireFields {
    static let `cityEdition`: String = "cityEdition"
    static let `cityPushToken`: String = "cityPushToken"
    static let `code`: String = "code"
    static let `communityPage`: String = "communityPage"
    static let `data`: String = "data"
    static let `districtOrder`: String = "districtOrder"
    static let `districtSession`: String = "districtSession"
    static let `installationID`: String = "installationID"
    static let `message`: String = "message"
    static let `storeReceipt`: String = "storeReceipt"
    static let `storeTransaction`: String = "storeTransaction"
    static let `subscriptionMode`: String = "subscriptionMode"
}

enum ConfiguredAuthContinuation: Equatable {
    case plain, realtimeRequired

    // Validate the envelope first; plain requires HTTP/business success, while valid legacy continuation remains allowed.
    // nil is a malformed data object; key absence selects plain.
    static func parse(data: Any?) -> Self? {
        guard let fields = data as? [String: Any] else { return nil }
        return fields.keys.contains(ConfiguredWireFields.`communityPage`) ? .realtimeRequired : .plain
    }
}

enum SupabaseIntegrationContract {
    static let projectURLString: String = "https://ujclifehtfrxtrijlaia.supabase.co"
    static let bootstrapFunction: String = "community-entry"
    static let purchaseFunction: String = "diamond-settlement"
    static let backendOriginField: String = "communityOrigin"
    static let applicationIDField: String = "communityApp"
    static let purchaseSourceField: String = "orderSource"
    static let purchaseProductIDField: String = "catalogPack"
    static let purchaseQuantityField: String = "packQuantity"
}

// Routing context is frozen before purchase; this enum is not proof of a genuine Apple payment.
enum ConfiguredPurchaseSource: String, Codable {
    case local = "districtWallet"
    case socket = "communityOrder"
}

enum ConfiguredBootstrapContinuation: Equatable {
    case standalone
    case nativeSupabase(appID: String)
    case external(origin: URL, appID: String)

    // Call only after Supabase session and bootstrap HTTP/business success.
    // Empty configuration is intentional; partial or malformed configuration is an error.
    static func parse(data: Any?) -> Self? {
        guard let fields = data as? [String: Any] else { return nil }
        if fields.isEmpty { return .standalone }
        guard let raw = fields[SupabaseIntegrationContract.backendOriginField] as? String,
              let appID = fields[SupabaseIntegrationContract.applicationIDField] as? String,
              !raw.isEmpty, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !appID.isEmpty, appID == appID.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              raw.rangeOfCharacter(from: .controlCharacters) == nil,
              raw.rangeOfCharacter(from: CharacterSet(charactersIn: "<>{}*\"\\")) == nil,
              appID.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil,
              var parts = URLComponents(string: raw),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              !host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              parts.url != nil else { return nil }
        parts.scheme = "https"
        parts.path = ""
        guard let origin = parts.url else { return nil }
        guard let native = URLComponents(string: SupabaseIntegrationContract.projectURLString) else { return nil }
        if parts.scheme?.lowercased() == native.scheme?.lowercased(),
           parts.host?.lowercased() == native.host?.lowercased(),
           (parts.port ?? 443) == (native.port ?? 443) {
            return .nativeSupabase(appID: appID)
        }
        return .external(origin: origin, appID: appID)
    }
}
