import Foundation
import Testing
@testable import OTMCore

@Suite(.serialized) struct JiraClientTests {
    let site = URL(string: "https://acme.atlassian.net")!

    func client() -> JiraClient {
        StubURLProtocol.reset()
        return JiraClient(site: site, email: "me@x.com", token: "tok", session: StubURLProtocol.session())
    }

    func bodyJSON(_ i: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: StubURLProtocol.requests[i].body ?? Data())) as? [String: Any] ?? [:]
    }

    @Test func myselfSendsBasicAuth() async throws {
        let c = client()
        StubURLProtocol.handler = { _, _ in .init(status: 200, body: #"{"accountId":"1","displayName":"Neo","emailAddress":"x"}"#) }
        let me = try await c.myself()
        #expect(me == JiraUser(displayName: "Neo", accountId: "1"))
        let req = StubURLProtocol.requests[0].request
        #expect(req.url?.absoluteString == "https://acme.atlassian.net/rest/api/3/myself")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("me@x.com:tok".utf8).base64EncodedString())
        #expect(req.httpMethod == "GET")
    }

    @Test func fieldsAndPriorities() async throws {
        let c = client()
        StubURLProtocol.handler = { req, _ in
            if req.url!.path.hasSuffix("/field") {
                return .init(status: 200, body: #"[{"id":"priority","name":"Priority","custom":false,"schema":{"type":"priority"}}]"#)
            }
            return .init(status: 200, body: #"{"values":[{"id":"1","name":"Highest"},{"id":"2","name":"Low"}],"isLast":true}"#)
        }
        #expect(try await c.fields().map(\.id) == ["priority"])
        #expect(try await c.priorities() == ["Highest", "Low"])
        #expect(StubURLProtocol.requests[1].request.url?.absoluteString
                == "https://acme.atlassian.net/rest/api/3/priority/search?maxResults=100")
    }

    @Test func searchPaginatesWithNextPageToken() async throws {
        let c = client()
        StubURLProtocol.handler = { _, body in
            let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
            if json["nextPageToken"] == nil {
                return .init(status: 200, body: #"{"issues":[{"id":"1","key":"A-1","fields":{"summary":"one"}}],"nextPageToken":"p2","isLast":false}"#)
            }
            return .init(status: 200, body: #"{"issues":[{"id":"2","key":"A-2","fields":{"summary":"two"}}],"isLast":true}"#)
        }
        let r = try await c.search(jql: "project = A", fields: ["summary", "priority"], cap: 500)
        #expect(r.issues.map(\.key) == ["A-1", "A-2"])
        #expect(!r.truncated)
        #expect(r.approximateTotal == nil)
        let first = bodyJSON(0)
        #expect(first["jql"] as? String == "project = A")
        #expect(first["fields"] as? [String] == ["summary", "priority"])
        #expect(first["maxResults"] as? Int == 100)
        #expect(bodyJSON(1)["nextPageToken"] as? String == "p2")
        #expect(StubURLProtocol.requests[0].request.httpMethod == "POST")
        #expect(StubURLProtocol.requests[0].request.url?.path == "/rest/api/3/search/jql")
    }

    @Test func searchStopsAtCapAndAsksApproximateCount() async throws {
        let c = client()
        StubURLProtocol.handler = { req, _ in
            if req.url!.path.hasSuffix("approximate-count") { return .init(status: 200, body: #"{"count":1240}"#) }
            return .init(status: 200, body: #"{"issues":[{"key":"A-1","fields":{}},{"key":"A-2","fields":{}}],"nextPageToken":"more"}"#)
        }
        let r = try await c.search(jql: "x", fields: [], cap: 2)
        #expect(r.issues.count == 2)
        #expect(r.truncated)
        #expect(r.approximateTotal == 1240)
        #expect(bodyJSON(0)["maxResults"] as? Int == 2)
    }

    @Test func mapsHttpErrors() async {
        let c = client()
        let cases: [(StubURLProtocol.Response, JiraError)] = [
            (.init(status: 401, body: ""), .unauthorized),
            (.init(status: 403, body: ""), .unauthorized),
            (.init(status: 429, headers: ["Retry-After": "12"], body: ""), .rateLimited(retryAfter: 12)),
            (.init(status: 429, body: ""), .rateLimited(retryAfter: nil)),   // Review Focus #5
            (.init(status: 400, body: #"{"errorMessages":["Field 'x' does not exist."],"errors":{}}"#),
             .badRequest("Field 'x' does not exist.")),
            (.init(status: 500, body: ""), .http(500)),
        ]
        for (response, expected) in cases {
            StubURLProtocol.handler = { _, _ in response }
            await #expect(throws: expected) { _ = try await c.myself() }
        }
    }

    @Test func undecodableBodyIsDecodingError() async {
        let c = client()
        StubURLProtocol.handler = { _, _ in .init(status: 200, body: "<html>") }
        do {
            _ = try await c.fields()
            Issue.record("expected error")
        } catch let e as JiraError {
            if case .decoding = e {} else { Issue.record("wrong error \(e)") }
        } catch {
            Issue.record("wrong error type \(error)")
        }
    }
}
