import Foundation

public enum JiraError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: Double?)
    case badRequest(String)
    case http(Int)
    case network(String)
    case decoding(String)
}

public struct SearchResult: Equatable, Sendable {
    public var issues: [JiraIssue]
    public var truncated: Bool
    public var approximateTotal: Int?
    public init(issues: [JiraIssue], truncated: Bool = false, approximateTotal: Int? = nil) {
        self.issues = issues
        self.truncated = truncated
        self.approximateTotal = approximateTotal
    }
}

/// Read-only Jira Cloud API surface used by the app.
public protocol JiraAPI: AnyObject {
    func myself() async throws -> JiraUser
    func fields() async throws -> [JiraField]
    func priorities() async throws -> [String]
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult
    func approximateCount(jql: String) async throws -> Int
}

public final class JiraClient: JiraAPI {
    private let base: URL
    private let authorization: String
    private let session: URLSession

    public init(site: URL, email: String, token: String, session: URLSession = .shared) {
        base = site
        authorization = "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
        self.session = session
    }

    public func myself() async throws -> JiraUser {
        try decode(JiraUser.self, from: await send("rest/api/3/myself"))
    }

    public func fields() async throws -> [JiraField] {
        try decode([JiraField].self, from: await send("rest/api/3/field"))
    }

    public func priorities() async throws -> [String] {
        struct Page: Decodable { struct P: Decodable { var name: String }; var values: [P] }
        let data = try await send("rest/api/3/priority/search", query: [URLQueryItem(name: "maxResults", value: "100")])
        return try decode(Page.self, from: data).values.map(\.name)
    }

    public func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        struct Page: Decodable { var issues: [JiraIssue]; var nextPageToken: String?; var isLast: Bool? }
        var issues: [JiraIssue] = []
        var token: String?
        var more = false
        repeat {
            var body: [String: Any] = ["jql": jql, "fields": fields, "maxResults": min(100, cap - issues.count)]
            if let token { body["nextPageToken"] = token }
            let data = try await send("rest/api/3/search/jql", method: "POST",
                                      body: try JSONSerialization.data(withJSONObject: body))
            let page = try decode(Page.self, from: data)
            issues.append(contentsOf: page.issues)
            token = page.nextPageToken
            more = token != nil && page.isLast != true && !page.issues.isEmpty
        } while more && issues.count < cap
        let truncated = more && issues.count >= cap
        let total: Int? = truncated ? (try? await approximateCount(jql: jql)) : nil
        return SearchResult(issues: Array(issues.prefix(cap)), truncated: truncated, approximateTotal: total)
    }

    public func approximateCount(jql: String) async throws -> Int {
        struct Count: Decodable { var count: Int }
        let data = try await send("rest/api/3/search/approximate-count", method: "POST",
                                  body: try JSONSerialization.data(withJSONObject: ["jql": jql]))
        return try decode(Count.self, from: data).count
    }

    // MARK: - Transport

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw JiraError.network("No HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw JiraError.unauthorized
        case 429: throw JiraError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        case 400: throw JiraError.badRequest(Self.errorMessage(data) ?? "Bad request")
        default: throw JiraError.http(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw JiraError.decoding(String(describing: error)) }
    }

    static func errorMessage(_ data: Data) -> String? {
        struct Body: Decodable { var errorMessages: [String]?; var errors: [String: String]? }
        guard let b = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        let all = (b.errorMessages ?? []) + (b.errors ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return all.isEmpty ? nil : all.joined(separator: "; ")
    }
}
