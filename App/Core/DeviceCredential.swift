import CryptoKit
import Foundation
import Security

struct DeviceCredential {
    let password: String

    var email: String {
        let digest = SHA256.hash(data: Data(password.utf8))
        let alias = digest.prefix(24).map { String(format: "%02x", $0) }.joined()
        return "\(alias)@device.citycommunity.invalid"
    }

    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "com.sese.citycommunit").device-sign-in",
         kSecAttrAccount as String: "device-credential"]
    }

    static func loadOrCreate() throws -> Self {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let lookup = SecItemCopyMatching(query as CFDictionary, &value)
        if lookup == errSecSuccess {
            guard let data = value as? Data, data.count == 32 else { throw CommunityError.credentialStorage }
            return credential(from: data)
        }
        guard lookup == errSecItemNotFound else { throw CommunityError.credentialStorage }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard randomStatus == errSecSuccess else { throw CommunityError.credentialStorage }

        var insertion = item
        insertion[kSecValueData as String] = bytes
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(insertion as CFDictionary, nil)
        if added == errSecDuplicateItem { return try loadOrCreate() }
        guard added == errSecSuccess else { throw CommunityError.credentialStorage }
        return credential(from: bytes)
    }

    static func remove() {
        SecItemDelete(item as CFDictionary)
    }

    private static func credential(from data: Data) -> Self {
        DeviceCredential(password: data.map { String(format: "%02x", $0) }.joined())
    }
}
