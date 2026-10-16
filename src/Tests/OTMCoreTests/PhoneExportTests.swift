import Foundation
import Testing
@testable import OTMCore

@Suite struct PhoneExportTests {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func config() -> AppConfig {
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "a", name: "Acme", site: "https://acme.atlassian.net", email: "me@x.io"),
                      JiraAccount(id: "b", name: "Other", site: "https://other.atlassian.net", email: "o@x.io")]
        c.presets = [JQLPreset(id: "p1", name: "Mine", jql: "assignee = currentUser()", accountId: "a"),
                     JQLPreset(id: "p2", name: "Theirs", jql: "project = O", accountId: "b")]
        c.activePresetId = "p1"
        return c
    }

    @Test func roundTripContainsOnlyTheChosenAccount() throws {
        let blob = try PhoneExport.seal(config: config(), accountId: "a", code: "ABCD-EFGH", now: now, iterations: 1000)
        let plain = try PhoneExport.open(blob, code: "abcdefgh", now: now, iterations: 1000)
        let text = String(decoding: plain, as: UTF8.self)
        #expect(text.contains("acme.atlassian.net"))
        #expect(!text.contains("other.atlassian.net"))
        #expect(!text.contains("project = O"))
        #expect(!text.lowercased().contains("token"))
        #expect(!blob.contains("acme"))   // not plaintext
    }

    @Test func wrongCodeAndExpiryAndGarbage() throws {
        let blob = try PhoneExport.seal(config: config(), accountId: "a", code: "ABCDEFGH", now: now, iterations: 1000)
        #expect(throws: PhoneExport.Failure.badCode) { try PhoneExport.open(blob, code: "ABCDEFGJ", now: now, iterations: 1000) }
        #expect(throws: PhoneExport.Failure.expired) { try PhoneExport.open(blob, code: "ABCDEFGH", now: now.addingTimeInterval(601), iterations: 1000) }
        #expect(throws: PhoneExport.Failure.malformed) { try PhoneExport.open("###", code: "ABCDEFGH", now: now) }
        #expect(throws: PhoneExport.Failure.noAccount) { try PhoneExport.seal(config: config(), accountId: "zzz", code: "ABCDEFGH", iterations: 1000) }
    }

    @Test func codes() throws {
        let c = try PhoneExport.makeCode()
        #expect(c.count == 8 && c.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) })
        #expect(PhoneExport.display("abcdefgh") == "ABCD-EFGH")
        #expect(try PhoneExport.makeCode() != PhoneExport.makeCode())
    }

    @Test func linkNeedsHttps() throws {
        #expect(PhoneExport.link(base: "http://glance.example", blob: "x") == nil)
        #expect(PhoneExport.link(base: "glance.example.workers.dev", blob: "abc")?.absoluteString == "https://glance.example.workers.dev#g1=abc")
        #expect(PhoneExport.link(base: "https://u:p@glance.example/app?x=1", blob: "abc")?.absoluteString == "https://glance.example/app#g1=abc")
        #expect(PhoneExport.link(base: "", blob: "abc") == nil)
    }

    /// A link produced by phone/src/crypto.js (fixtures/link-vector-js.json) opens here, and the reverse (…-swift.json) opens in JS.
    @Test func crossLanguageVectors() throws {
        let js = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtures.appendingPathComponent("link-vector-js.json"))) as! [String: Any]
        let plain = try PhoneExport.open(js["blob"] as! String, code: js["code"] as! String,
                                         now: Date(timeIntervalSince1970: js["now"] as! Double), iterations: js["iterations"] as! Int)
        let obj = try JSONSerialization.jsonObject(with: plain) as! [String: Any]
        #expect((obj["data"] as! [String: Any])["hello"] as? String == "world")

        let swiftPath = Self.fixtures.appendingPathComponent("link-vector-swift.json")
        if ProcessInfo.processInfo.environment["UPDATE_VECTOR"] == "1" {
            let blob = try PhoneExport.seal(config: config(), accountId: "a", code: "ABCDEFGH", now: now, iterations: 1000)
            let out: [String: Any] = ["blob": blob, "code": "ABCDEFGH", "now": 1_800_000_000, "iterations": 1000]
            try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted]).write(to: swiftPath)
        }
        #expect(FileManager.default.fileExists(atPath: swiftPath.path))
    }
}
