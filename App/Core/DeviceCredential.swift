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

    static func installationID() throws -> String {
        var key = item
        key[kSecAttrAccount as String] = "installation-id"
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        func read() throws -> String? {
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = value as? Data,
                  let text = String(data: data, encoding: .utf8), UUID(uuidString: text) != nil else {
                throw CommunityError.credentialStorage
            }
            return text
        }
        if let existing = try read() { return existing }
        let id = UUID().uuidString.lowercased()
        key[kSecValueData as String] = Data(id.utf8)
        key[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(key as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem,
              let stored = try read(), status == errSecDuplicateItem || id == stored else {
            throw CommunityError.credentialStorage
        }
        return stored
    }

    static func remove() {
        SecItemDelete(item as CFDictionary)
    }

    private static func credential(from data: Data) -> Self {
        DeviceCredential(password: data.map { String(format: "%02x", $0) }.joined())
    }
}
