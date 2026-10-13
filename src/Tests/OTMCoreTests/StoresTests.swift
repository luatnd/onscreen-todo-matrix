import Foundation
import Testing
@testable import OTMCore

@Suite struct ConfigStoreTests {
    @Test func missingFileReportsMissing() {
        #expect(ConfigStore(directory: makeTempDir()).load() == .missing)
    }

    @Test func roundTripsConfig() throws {
        let store = ConfigStore(directory: makeTempDir().appendingPathComponent("nested"))
        var axes = AxesConfig()
        axes.urgency.mapping = .option(fieldId: "priority", levels: ["High": 4])
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com", axes: axes)]
        c.presets.append(JQLPreset(id: "p2", name: "Company", jql: "project = C", accountId: "c1"))
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
    @Test func writeReadDeletePerAccount() throws {
        let s = InMemoryTokenStore()
        #expect(try s.read(accountId: "default") == nil)
        try s.write("abc", accountId: "default")
        try s.write("xyz", accountId: "c1")
        #expect(try s.read(accountId: "default") == "abc")
        #expect(try s.read(accountId: "c1") == "xyz")
        try s.delete(accountId: "default")
        #expect(try s.read(accountId: "default") == nil)
        #expect(try s.read(accountId: "c1") == "xyz")
    }

    @Test func legacyItemIsSeparateFromKeyedItems() throws {
        let s = InMemoryTokenStore(legacyToken: "old")
        #expect(try s.readLegacy() == "old")
        #expect(try s.read(accountId: "default") == nil)
        try s.delete(accountId: "default")
        #expect(try s.readLegacy() == "old")
        try s.deleteLegacy()
        #expect(try s.readLegacy() == nil)
    }

    @Test func readErrorIsThrown() {
        let s = InMemoryTokenStore()
        s.readError = TokenStoreError.status(-25293)
        #expect(throws: TokenStoreError.status(-25293)) { try s.read(accountId: "default") }
        #expect(throws: TokenStoreError.status(-25293)) { try s.readLegacy() }
    }

    @Test func keychainItemNamesKeepV11Identifiers() {
        #expect(KeychainTokenStore.service == "onscreen-todo-matrix")
        #expect(KeychainTokenStore.legacyAccount == "jira-api-token")
        #expect(KeychainTokenStore.keychainAccount(for: "default") == "jira-api-token:default")
        #expect(KeychainTokenStore.keychainAccount(for: "c1f") == "jira-api-token:c1f")
    }
}
