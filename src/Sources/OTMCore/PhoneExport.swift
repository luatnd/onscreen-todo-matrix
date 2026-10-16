import CommonCrypto
import CryptoKit
import Foundation
import Security

/// "Send to phone": settings of ONE account (no secrets: the Jira token never leaves the Mac) sealed with a one-time code.
/// Layout (must match phone/src/crypto.js): base64url( 0x01 | salt(16) | nonce(12) | ciphertext | tag(16) ),
/// key = PBKDF2-HMAC-SHA256(code, salt, 600000), plaintext = {"exp": epochSeconds, "data": <payload>}.
public enum PhoneExport {
    public static let iterations = 600_000
    public static let ttl: TimeInterval = 600
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public enum Failure: Error, Equatable { case noAccount, badCode, malformed, expired, random, crypto }

    /// 8 characters from a 32-letter alphabet (no 0/O/1/I); 256 % 32 == 0 so the modulo is unbiased.
    public static func makeCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.random }
        return String(bytes.map { alphabet[Int($0) % 32] })
    }

    public static func normalize(_ code: String) -> String {
        String(code.uppercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    public static func display(_ code: String) -> String {
        let c = normalize(code)
        return c.count == 8 ? "\(c.prefix(4))-\(c.suffix(4))" : c
    }

    struct Payload: Codable {
        var accounts: [JiraAccount]
        var presets: [JQLPreset]
        var activePresetId: String
        var view: ViewDefaults
        var lastView: ViewDefaults?
        var quick: QuickSettings
    }
    struct Envelope: Codable { var exp: Int; var data: Payload }

    /// Only the chosen account and its presets; everything else stays on the Mac.
    static func payload(config: AppConfig, accountId: String) throws -> Payload {
        guard let account = config.account(id: accountId) else { throw Failure.noAccount }
        let presets = config.presets.filter { $0.accountId == accountId }
        guard !presets.isEmpty else { throw Failure.noAccount }
        let active = presets.first { $0.id == config.activePresetId } ?? presets[0]
        return Payload(accounts: [account], presets: presets, activePresetId: active.id, view: config.view,
                       lastView: config.lastView, quick: config.quick)
    }

    public static func seal(config: AppConfig, accountId: String, code: String, now: Date = Date(),
                            iterations: Int = PhoneExport.iterations) throws -> String {
        let env = Envelope(exp: Int(now.timeIntervalSince1970) + Int(ttl), data: try payload(config: config, accountId: accountId))
        return try seal(plaintext: JSONEncoder().encode(env), code: code, iterations: iterations)
    }

    static func seal(plaintext: Data, code: String, iterations: Int) throws -> String {
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else { throw Failure.random }
        let key = try derive(code: code, salt: Data(salt), iterations: iterations)
        guard let combined = try? AES.GCM.seal(plaintext, using: key).combined else { throw Failure.crypto }
        return base64url(Data([1]) + Data(salt) + combined)
    }

    /// Decrypts a link (used by tests and to verify what the phone will see).
    public static func open(_ blob: String, code: String, now: Date = Date(), iterations: Int = PhoneExport.iterations) throws -> Data {
        guard let raw = fromBase64url(blob), raw.count >= 1 + 16 + 12 + 16, raw[0] == 1 else { throw Failure.malformed }
        let key = try derive(code: code, salt: raw.subdata(in: 1..<17), iterations: iterations)
        guard let box = try? AES.GCM.SealedBox(combined: raw.subdata(in: 17..<raw.count)),
              let plain = try? AES.GCM.open(box, using: key) else { throw Failure.badCode }
        struct Head: Decodable { var exp: Int }
        guard let head = try? JSONDecoder().decode(Head.self, from: plain) else { throw Failure.malformed }
        guard Int(now.timeIntervalSince1970) <= head.exp else { throw Failure.expired }
        return plain
    }

    /// "https://host/path/" + "#g1=<blob>"; nil unless the base is an https URL.
    public static func link(base: String, blob: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard var c = URLComponents(string: s), c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty else { return nil }
        c.user = nil; c.password = nil; c.query = nil
        c.fragment = "g1=" + blob
        return c.url
    }

    // MARK: - helpers

    private static func derive(code: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pw = Array(normalize(code).utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
        }
        guard status == kCCSuccess else { throw Failure.crypto }
        return SymmetricKey(data: out)
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }
}
