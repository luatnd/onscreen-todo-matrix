import Foundation
import Testing
@testable import OTMCore

@Suite struct ConfigStoreTests {
    @Test func missingFileReportsMissing() {
        #expect(ConfigStore(directory: makeTempDir()).load() == .missing)
    }

    @Test func roundTripsConfig() throws {
        let store = ConfigStore(directory: makeTempDir().appendingPathComponent("nested"))
        var c = AppConfig()
        c.site = "acme.atlassian.net"
        c.axes.urgency.mapping = .option(fieldId: "priority", levels: ["High": 4])
        try store.save(c)
        #expect(store.load() == .loaded(c))
    }

    @Test func corruptFileIsBackedUpNotLost() throws {
        let dir = makeTempDir()
        let store = ConfigStore(directory: dir)
        try Data("{not json".utf8).write(to: store.url)
        let result = store.load()
        let bak = dir.appendingPathComponent("config.json.bak")
        #expect(result == .corrupt(backup: bak))
        #expect(String(decoding: try Data(contentsOf: bak), as: UTF8.self) == "{not json")
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

@Suite struct IssueCacheTests {
    @Test func emptyCacheLoadsNil() {
        #expect(IssueCache(directory: makeTempDir()).load() == nil)
    }

    @Test func roundTripsIssuesAndTimestamp() throws {
        let cache = IssueCache(directory: makeTempDir())
        let fetch = CachedFetch(
            issues: [JiraIssue(key: "SEC-5", fields: ["summary": .string("Rotate key")])],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try cache.save(fetch)
        #expect(cache.load() == fetch)
    }
}

@Suite struct InMemoryTokenStoreTests {
    @Test func writeReadDelete() throws {
        let s = InMemoryTokenStore()
        #expect(try s.read() == nil)
        try s.write("abc")
        #expect(try s.read() == "abc")
        try s.delete()
        #expect(try s.read() == nil)
    }

    @Test func readErrorIsThrown() {
        let s = InMemoryTokenStore()
        s.readError = TokenStoreError.status(-25293)
        #expect(throws: TokenStoreError.status(-25293)) { try s.read() }
    }
}
