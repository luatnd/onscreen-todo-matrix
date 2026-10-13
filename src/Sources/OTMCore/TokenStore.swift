import Foundation
import Security

/// API tokens, one per Jira account. The legacy (v1.1) single item is read/deleted only by the migration.
public protocol TokenStore: AnyObject {
    func read(accountId: String) throws -> String?
    func write(_ token: String, accountId: String) throws
    func delete(accountId: String) throws
    func readLegacy() throws -> String?
    func deleteLegacy() throws
}

public enum TokenStoreError: Error, Equatable {
    case status(Int32)
}

public final class InMemoryTokenStore: TokenStore {
    public var tokens: [String: String]
    public var legacyToken: String?
    public var readError: Error?
    public var writeError: Error?
    /// Simulates a store that reports success but keeps nothing (used to test "copy verified").
    public var dropsWrites = false

    public init(tokens: [String: String] = [:], legacyToken: String? = nil) {
        self.tokens = tokens
        self.legacyToken = legacyToken
    }

    public func read(accountId: String) throws -> String? {
        if let readError { throw readError }
        return tokens[accountId]
    }

    public func write(_ token: String, accountId: String) throws {
        if let writeError { throw writeError }
        if !dropsWrites { tokens[accountId] = token }
    }

    public func delete(accountId: String) throws { tokens[accountId] = nil }

    public func readLegacy() throws -> String? {
        if let readError { throw readError }
        return legacyToken
    }

    public func deleteLegacy() throws { legacyToken = nil }
}

/// API tokens in the macOS Keychain (generic passwords, service `onscreen-todo-matrix`).
public final class KeychainTokenStore: TokenStore {
    public static let service = "onscreen-todo-matrix"
    /// v1.1 single-account item, kept until the migration has verified its copy.
    public static let legacyAccount = "jira-api-token"
    public static func keychainAccount(for accountId: String) -> String { "\(legacyAccount):\(accountId)" }

    public init() {}

    public func read(accountId: String) throws -> String? { try read(account: Self.keychainAccount(for: accountId)) }
    public func write(_ token: String, accountId: String) throws { try write(token, account: Self.keychainAccount(for: accountId)) }
    public func delete(accountId: String) throws { try delete(account: Self.keychainAccount(for: accountId)) }
    public func readLegacy() throws -> String? { try read(account: Self.legacyAccount) }
    public func deleteLegacy() throws { try delete(account: Self.legacyAccount) }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }

    private func read(account: String) throws -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw TokenStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.status(update) }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.status(status) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError.status(status) }
    }
}
