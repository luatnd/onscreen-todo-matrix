import Foundation
@testable import OTMCore

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("otm-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// SRC directory, derived from this file's location (Tests/OTMCoreTests/TestSupport.swift).
let srcDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Intercepts URLSession requests. Use only from `.serialized` suites (static state).
final class StubURLProtocol: URLProtocol {
    struct Response { var status: Int; var headers: [String: String] = [:]; var body: String }
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> Response)?
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data?)] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        Self.requests.append((request, body))
        let r = Self.handler?(request, body) ?? Response(status: 500, body: "{}")
        let http = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(r.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FakeJiraAPI: JiraAPI {
    var searchResult: Result<SearchResult, JiraError> = .success(SearchResult(issues: []))
    var searchCalls: [(jql: String, fields: [String], cap: Int)] = []
    var countResult: Result<Int, JiraError> = .success(0)
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    var fieldsResult: [JiraField] = []
    var fieldsCalls = 0
    func fields() async throws -> [JiraField] { fieldsCalls += 1; return fieldsResult }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { try countResult.get() }
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        searchCalls.append((jql, fields, cap))
        return try searchResult.get()
    }
}
