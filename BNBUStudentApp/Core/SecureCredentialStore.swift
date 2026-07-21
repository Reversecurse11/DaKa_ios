import Foundation
import Security

protocol SecureCredentialStoring: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeData(forKey key: String) throws
}

enum SecureCredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        "无法安全保存登录状态，请重新启动 App 后再试。"
    }
}

/// Stores short-lived server credentials in the device-only Keychain.
///
/// `WhenUnlockedThisDeviceOnly` keeps credentials out of backups and prevents
/// access while the device is locked. Keychain Services is thread-safe, so the
/// value type can be shared with the repository actor.
struct KeychainCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let service: String

    init(service: String = "edu.bnbu.student.mvp.credentials.v1") {
        self.service = service
    }

    func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureCredentialStoreError.keychain(status)
        }
    }

    func set(_ data: Data, forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureCredentialStoreError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureCredentialStoreError.keychain(addStatus)
        }
    }

    func removeData(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
