import Foundation
import Security

/// Where sessions are kept: one Keychain entry per server (the debug build keeps a separate sign-in for each).
protocol SecureStore: Sendable {
    func read(_ account: String) -> Data?
    func write(_ data: Data, account: String)
    func delete(_ account: String)
}

/// Generic-password items in the app's Keychain, readable after the first unlock (so a refresh in the background works).
struct KeychainStore: SecureStore {
    let service: String

    init(service: String = "com.darsequran.academy.session") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func write(_ data: Data, account: String) {
        let q = query(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(q as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(q.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Keychain items outlive the app: after it is deleted and installed again, the last sign-in would come straight back.
/// Like Android (where uninstalling wipes the app's data), a fresh install starts signed out on every server. The mark
/// lives in UserDefaults, which an uninstall does remove.
func forgetSessionsFromAnEarlierInstall(_ store: SecureStore, defaults: UserDefaults) {
    let key = "installed"
    guard !defaults.bool(forKey: key) else { return }
    AppEnvironment.allCases.forEach { store.delete($0.key) }
    defaults.set(true, forKey: key)
}

/// In-memory store for tests.
final class MemoryStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    init() {}

    func read(_ account: String) -> Data? { lock.withLock { items[account] } }
    func write(_ data: Data, account: String) { lock.withLock { items[account] = data } }
    func delete(_ account: String) { _ = lock.withLock { items.removeValue(forKey: account) } }
}
