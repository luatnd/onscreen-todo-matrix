import Foundation
import Security

public protocol TokenStore: AnyObject {
    func read() throws -> String?
    func write(_ token: String) throws
    func delete() throws
}

public enum TokenStoreError: Error, Equatable {
    case status(Int32)
}

public final class InMemoryTokenStore: TokenStore {
    public var token: String?
    public var readError: Error?
    public init(token: String? = nil) { self.token = token }
    public func read() throws -> String? {
        if let readError { throw readError }
        return token
    }
    public func write(_ token: String) throws { self.token = token }
    public func delete() throws { token = nil }
}

/// API token in the macOS Keychain (generic password).
public final class KeychainTokenStore: TokenStore {
    private let service = "onscreen-todo-matrix"
    private let account = "jira-api-token"
    public init() {}

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() throws -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw TokenStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.status(update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.status(status) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError.status(status) }
    }
}
