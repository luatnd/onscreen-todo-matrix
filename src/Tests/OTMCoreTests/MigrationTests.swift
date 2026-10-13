import Foundation
import Testing
@testable import OTMCore

/// v1.1 → v1.2 migration (§11.4). The fixture has the exact shape of a real v1.1 config (fake site/email).
@MainActor
@Suite struct MigrationTests {
    let dir = makeTempDir()

    func fixture() throws -> Data {
        try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/config-v1.1.json"))
    }

    /// Writes the v1.1 fixture as config.json (and optionally a v1.1 last-fetch.json).
    func legacyStore(withCache: Bool = false) throws -> ConfigStore {
        let store = ConfigStore(directory: dir)
        try fixture().write(to: store.url)
        if withCache {
            try Data(#"{"issues":[{"key":"A-1","fields":{}}],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8)
                .write(to: IssueCache(directory: dir).legacyURL)
        }
        return store
    }

    func legacyConfig(_ store: ConfigStore) throws -> AppConfig {
        guard case .legacy(let c) = store.load() else { throw MigrationTestError.notLegacy }
        return c
    }

    @Test func realShapeV11IsLegacyNotCorruptAndLossless() throws {
        // Review Focus #1
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let c = try legacyConfig(store)
        #expect(try Data(contentsOf: store.url) == original) // load() never writes
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.bak").path))

        #expect(c.accounts.count == 1)
        let a = c.accounts[0]
        #expect(a.id == "default")
        #expect(a.name == "Personal")
        #expect(a.site == "https://example-personal.atlassian.net")
        #expect(a.siteURL?.absoluteString == "https://example-personal.atlassian.net")
        #expect(a.email == "me@example.com")
        #expect(a.axes.value == AxisConfig(mapping: .option(fieldId: "customfield_10110",
                                                            levels: ["2 Low": 2, "3 Medium": 3, "4 High": 4, "5 Highest": 5]),
                                           missingDefault: 0))
        #expect(a.axes.effort == AxisConfig(mapping: .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false),
                                            missingDefault: 0))
        #expect(a.axes.urgency == AxisConfig(mapping: .option(fieldId: "priority", levels: DefaultMappings.priorityLevels),
                                             missingDefault: 0))
        #expect(c.presets == [JQLPreset(id: "my-open-work", name: "My open work",
                                        jql: "statusCategory != Done ORDER BY priority DESC", accountId: "default")])
        #expect(c.activePresetId == "my-open-work")
        #expect(c.activeAccount?.id == "default")
        #expect(c.view == ViewDefaults())
        #expect(c.lastView == ViewDefaults(yaw: -179.7, pitch: 33.9, zoom: 0.6575736466253159))
        var quick = QuickSettings()
        quick.refreshMinutes = 15
        quick.rotation = "free"
        #expect(c.quick == quick)
        #expect(c.launchAtLogin)
    }

    @Test func finishBacksUpCopiesTokenMovesCacheAndSaves() throws {
        let store = try legacyStore(withCache: true)
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let cache = IssueCache(directory: dir)
        let c = try legacyConfig(store)

        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache))

        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
        #expect(try tokens.read(accountId: "default") == "legacy-tok")
        #expect(tokens.legacyToken == nil)
        #expect(cache.load(presetId: "my-open-work")?.issues.map(\.key) == ["A-1"])
        #expect(cache.load(presetId: "my-open-work")?.accountId == "default")
        #expect(!FileManager.default.fileExists(atPath: cache.legacyURL.path))
        #expect(store.load() == .loaded(c))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        #expect(raw["site"] == nil)
        #expect(raw["email"] == nil)
        #expect(raw["axes"] == nil)
        #expect(raw["accounts"] != nil)
    }

    @Test func migrationIsIdempotent() throws {
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let cache = IssueCache(directory: dir)
        let c = try legacyConfig(store)
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache))
        let saved = try Data(contentsOf: store.url)

        #expect(store.load() == .loaded(c))                                       // second load: no migration
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache)) // re-running changes nothing
        #expect(try Data(contentsOf: store.url) == saved)
        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
        #expect(try tokens.read(accountId: "default") == "legacy-tok")
    }

    @Test func emptySiteCreatesNoAccountAndKeepsLegacyToken() throws {
        let store = ConfigStore(directory: dir)
        try Data(#"{"site":"","email":"","presets":[{"id":"my-open-work","name":"My open work","jql":"x"}],"activePresetId":"my-open-work"}"#.utf8)
            .write(to: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "t")
        let c = try legacyConfig(store)
        #expect(c.accounts.isEmpty)
        #expect(c.presets.map(\.accountId) == ["default"])
        #expect(c.quick == QuickSettings())
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.tokens.isEmpty)
        #expect(tokens.legacyToken == "t")
    }

    @Test func keychainWriteFailureKeepsLegacyItemAndOldFile() throws {
        // Review Focus #2
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let c = try legacyConfig(store)
        #expect(!ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.legacyToken == "legacy-tok")
        #expect(try Data(contentsOf: store.url) == original)            // still v1.1 → retried next launch
        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
    }

    @Test func unverifiedCopyKeepsLegacyItem() throws {
        // Review Focus #2: the write "succeeds" but nothing can be read back.
        let store = try legacyStore()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.dropsWrites = true
        let c = try legacyConfig(store)
        #expect(!ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.legacyToken == "legacy-tok")
    }

    @Test func appModelMigratesOnLaunch() throws {
        _ = try legacyStore(withCache: true)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(!m.configWasCorrupt)
        #expect(!m.migrationFailed)
        #expect(m.config.accounts.map(\.id) == ["default"])
        #expect(m.storedToken(accountId: "default") == "legacy-tok")
        #expect(m.isConfigured)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }

    @Test func keychainFailureStillMovesCacheForActivePreset() throws {
        _ = try legacyStore(withCache: true)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(m.migrationFailed)
        let active = try #require(m.config.activePreset)
        #expect(IssueCache(directory: dir).load(presetId: active.id)?.issues.map(\.key) == ["A-1"])
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }

    func v12Store() throws -> ConfigStore {
        let store = ConfigStore(directory: dir)
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com")]
        try store.save(c)
        return store
    }

    @Test func loadedConfigRetriesVerifiedTokenCopy() throws {
        _ = try v12Store()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(!m.migrationFailed)
        #expect(tokens.tokens["default"] == "legacy-tok")
        #expect(tokens.legacyToken == nil)
    }

    @Test func loadedConfigTokenRetryFailureKeepsLegacyAndFallback() async throws {
        _ = try v12Store()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let log = ClientLog()
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { s, e, t in log.calls.append((s.absoluteString, e, t)); return FakeJiraAPI() })
        #expect(m.migrationFailed)
        #expect(tokens.legacyToken == "legacy-tok")
        #expect(m.storedToken(accountId: "default") == "legacy-tok")
        #expect((try? m.makeAPI(accountId: "default")) != nil)
        #expect(log.calls.last?.token == "legacy-tok")
        // A healthy v1.2 install must still save settings.
        m.setQuickSetting(key: "labelMode", value: .string("key"))
        m.saveLastView(yaw: 10, pitch: 10, zoom: 1)
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(saved.quick.labelMode == "key")
        #expect(saved.lastView?.yaw == 10)
    }

    @Test func v11ConfigIsNeverOverwrittenWithoutBackup() throws {
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        // A dangling symlink at the backup path: it "does not exist" yet the copy cannot be made.
        try FileManager.default.createSymbolicLink(at: store.legacyBackupURL, withDestinationURL: dir.appendingPathComponent("nowhere/x"))
        let m = AppModel(configStore: store, cache: IssueCache(directory: dir), tokenStore: InMemoryTokenStore(legacyToken: "t"),
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(m.migrationFailed)
        m.setQuickSetting(key: "labelMode", value: .string("key"))
        m.saveLastView(yaw: 10, pitch: 10, zoom: 1)
        #expect(m.config.quick.labelMode == "key") // in memory
        #expect(try Data(contentsOf: store.url) == original)
    }

    func unbackedModel(_ store: ConfigStore) throws -> AppModel {
        try FileManager.default.createSymbolicLink(at: store.legacyBackupURL, withDestinationURL: dir.appendingPathComponent("nowhere/x"))
        return AppModel(configStore: store, cache: IssueCache(directory: dir), tokenStore: InMemoryTokenStore(legacyToken: "t"),
                        scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
    }

    @Test func unbackedV11RetriesBackupAndThenSaves() throws {
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let m = try unbackedModel(store)
        #expect(m.migrationFailed)
        try FileManager.default.removeItem(at: store.legacyBackupURL) // backup path becomes writable
        m.setQuickSetting(key: "labelMode", value: .string("key"))
        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
        guard case .loaded(let saved) = store.load() else { Issue.record("not saved"); return }
        #expect(saved.quick.labelMode == "key")
    }

    @Test func saveAccountWhileBackupStillFailsKeepsBannerAndFile() throws {
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let m = try unbackedModel(store)
        try m.saveAccount(JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com"), token: "n")
        #expect(m.renderState.status.banner == AppModel.migrationBanner)
        #expect(try Data(contentsOf: store.url) == original)
    }

    @Test func appModelReportsMigrationFailure() throws {
        _ = try legacyStore()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(m.migrationFailed)
        #expect(!m.configWasCorrupt)
        #expect(m.config.accounts.map(\.id) == ["default"]) // the user still sees their setup
    }
}

enum MigrationTestError: Error { case notLegacy }
