import Foundation

public struct CachedFetch: Codable, Equatable, Sendable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    /// Account the issues came from; a cache whose account differs from the preset's is ignored.
    public var accountId: String

    public init(issues: [JiraIssue], fetchedAt: Date, accountId: String) {
        self.issues = issues
        self.fetchedAt = fetchedAt
        self.accountId = accountId
    }

    private enum CodingKeys: String, CodingKey { case issues, fetchedAt, accountId }

    /// v1.1 `last-fetch.json` has no `accountId`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issues = try c.decode([JiraIssue].self, forKey: .issues)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId) ?? ""
    }
}

/// Last successful fetch per preset: `<app support>/cache/<presetId>.json` (§11.5).
public final class IssueCache {
    public let directory: URL
    /// v1.1 single cache file, moved by `migrateLegacy`.
    public let legacyURL: URL

    public init(directory: URL) {
        self.directory = directory.appendingPathComponent("cache")
        legacyURL = directory.appendingPathComponent("last-fetch.json")
    }

    /// Percent-encodes everything but letters, digits, "-" and "_" so a hand-edited id can't leave the cache folder.
    public func url(presetId: String) -> URL {
        let safe = presetId.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? "invalid"
        return directory.appendingPathComponent(safe + ".json")
    }

    private static let fileNameCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    public func save(_ fetch: CachedFetch, presetId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(fetch).write(to: url(presetId: presetId), options: .atomic)
    }

    public func load(presetId: String) -> CachedFetch? {
        Self.decode(at: url(presetId: presetId))
    }

    public func delete(presetId: String) {
        try? FileManager.default.removeItem(at: url(presetId: presetId))
    }

    /// Moves v1.1 `last-fetch.json` to `cache/<presetId>.json`, tagged with `accountId`.
    /// No-op when there is no readable legacy file or the destination already exists.
    public func migrateLegacy(toPresetId presetId: String, accountId: String) {
        guard var legacy = Self.decode(at: legacyURL),
              !FileManager.default.fileExists(atPath: url(presetId: presetId).path) else { return }
        legacy.accountId = accountId
        guard (try? save(legacy, presetId: presetId)) != nil else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private static func decode(at url: URL) -> CachedFetch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CachedFetch.self, from: data)
    }
}
