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

    @Test func nonObjectJSONIsCorrupt() throws {
        let store = ConfigStore(directory: makeTempDir())
        try Data("[]".utf8).write(to: store.url)
        guard case .corrupt = store.load() else { Issue.record("expected .corrupt"); return }
    }

    @Test func wrongTypeInV12FileIsCorrupt() throws {
        let store = ConfigStore(directory: makeTempDir())
        try Data(#"{"accounts":[],"presets":5}"#.utf8).write(to: store.url)
        guard case .corrupt = store.load() else { Issue.record("expected .corrupt"); return }
    }
}

@Suite struct IssueCacheTests {
    let fetch = CachedFetch(issues: [JiraIssue(key: "SEC-5", fields: ["summary": .string("Rotate key")])],
                            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), accountId: "default")

    @Test func emptyCacheLoadsNil() {
        #expect(IssueCache(directory: makeTempDir()).load(presetId: "my-open-work") == nil)
    }

    @Test func roundTripsPerPreset() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        var other = fetch
        other.issues = []
        other.accountId = "c1"
        try cache.save(fetch, presetId: "my-open-work")
        try cache.save(other, presetId: "p2")
        #expect(cache.load(presetId: "my-open-work") == fetch)
        #expect(cache.load(presetId: "p2") == other)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cache/my-open-work.json").path))
        cache.delete(presetId: "p2")
        #expect(cache.load(presetId: "p2") == nil)
    }

    @Test func presetIdCannotEscapeTheCacheFolder() throws {
        // Review Focus #4
        let cache = IssueCache(directory: makeTempDir())
        for id in ["../config", "a/b", "..", "x.json"] {
            let url = cache.url(presetId: id)
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == cache.directory.standardizedFileURL.path)
            #expect(!url.lastPathComponent.hasPrefix("."))
        }
        try cache.save(fetch, presetId: "../config")
        #expect(cache.load(presetId: "../config") == fetch)
    }

    @Test func legacyFileMovesToActivePresetOnce() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        try Data(#"{"issues":[{"key":"A-1","fields":{}}],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8).write(to: cache.legacyURL)
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default")
        let moved = cache.load(presetId: "my-open-work")
        #expect(moved?.issues.map(\.key) == ["A-1"])
        #expect(moved?.accountId == "default")
        #expect(!FileManager.default.fileExists(atPath: cache.legacyURL.path))
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default") // no legacy file: no-op
        #expect(cache.load(presetId: "my-open-work") == moved)
    }

    @Test func legacyMoveNeverOverwritesAnExistingPresetCache() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        try cache.save(fetch, presetId: "my-open-work")
        try Data(#"{"issues":[],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8).write(to: cache.legacyURL)
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default")
        #expect(cache.load(presetId: "my-open-work") == fetch)
        #expect(FileManager.default.fileExists(atPath: cache.legacyURL.path))
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
