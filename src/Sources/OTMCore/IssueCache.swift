import Foundation

public struct CachedFetch: Codable, Equatable, Sendable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    public init(issues: [JiraIssue], fetchedAt: Date) {
        self.issues = issues
        self.fetchedAt = fetchedAt
    }
}

public final class IssueCache {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("last-fetch.json")
    }

    public func save(_ fetch: CachedFetch) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(fetch).write(to: url, options: .atomic)
    }

    public func load() -> CachedFetch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CachedFetch.self, from: data)
    }
}
