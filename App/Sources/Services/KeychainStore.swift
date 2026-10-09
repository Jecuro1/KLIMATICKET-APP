import Foundation
import Security
import KlimaCloud

/// Generic-password items of the app in the Keychain.
enum Keychain {
    static let service = "com.knitelarlberg.klimabilanz"

    /// Writes (`SecItemUpdate`, else `SecItemAdd` – never delete-then-add, so a failed write keeps the old item) or
    /// deletes (`nil`). Returns false when the keychain refused (e.g. still locked).
    @discardableResult
    static func set(_ data: Data?, for key: String, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: accessibility]
        var add = query
        for (name, value) in attributes { add[name] = value }
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(add as CFDictionary, nil)
        } else if status != errSecSuccess && status != errSecInteractionNotAllowed {
            // The stored item cannot be updated in place (e.g. its attributes are incompatible): replace it. Not done
            // while locked – then the old item stays and the caller retries once protected data is available.
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func read(_ key: String) -> SecureReadResult {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data { return .found(data) }
            return .notFound
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            return .locked
        default:
            return .failed
        }
    }

    static func data(for key: String) -> Data? {
        if case .found(let data) = read(key) { return data }
        return nil
    }
}

/// The Keychain as the `SecureStore` of `KlimaCloud.SessionCoordinator`. Items are readable after the first unlock
/// (background sync); `thisDeviceOnly` items never travel to another device via backups.
struct KeychainStore: SecureStore {
    func read(_ key: String) -> SecureReadResult { Keychain.read(key) }

    @discardableResult
    func write(_ data: Data, key: String, thisDeviceOnly: Bool) -> Bool {
        Keychain.set(data, for: key, accessibility: thisDeviceOnly ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                                                                   : kSecAttrAccessibleAfterFirstUnlock)
    }

    @discardableResult
    func delete(_ key: String) -> Bool { Keychain.set(nil, for: key) }
}
