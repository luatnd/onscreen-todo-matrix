import Foundation
import Testing
@testable import OTMCore

/// Records the (site, email, token) of every client the model creates.
final class ClientLog {
    var calls: [(site: String, email: String, token: String)] = []
}

@MainActor
@Suite struct AppModelTests {
    let dir = makeTempDir()
    let api = FakeJiraAPI()
    let tokens = InMemoryTokenStore(tokens: ["default": "tok", "c1": "ctok"])
    let clients = ClientLog()
    let clockNow = Date(timeIntervalSince1970: 1_800_000_000)
    let scheduler: RefreshScheduler

    init() {
        let t = clockNow
        scheduler = RefreshScheduler(now: { t })
    }

    static func axes(value: String, effort: String) -> AxesConfig {
        var a = AxesConfig()
        a.value.mapping = .number(fieldId: value, min: 0, max: 10, invert: false)
        a.effort.mapping = .number(fieldId: effort, min: 0, max: 10, invert: false)
        a.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        return a
    }

    /// Personal (default, acme) with "My open work"; Company (c1, corp) with "My company work" (p2).
    func configuredConfig() -> AppConfig {
        var c = AppConfig()
        c.accounts = [
            JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com",
                        axes: Self.axes(value: "cf_value", effort: "cf_sp")),
            JiraAccount(id: "c1", name: "Company", site: "corp.atlassian.net", email: "me@corp.com",
                        axes: Self.axes(value: "customfield_200", effort: "customfield_201")),
        ]
        c.presets.append(JQLPreset(id: "p2", name: "My company work", jql: "project = CORP", accountId: "c1"))
        return c
    }

    func makeModel(config: AppConfig? = nil) -> AppModel {
        if let config { try? ConfigStore(directory: dir).save(config) }
        let t = clockNow
        return AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                        scheduler: scheduler,
                        makeClient: { [api, clients] site, email, token in
                            clients.calls.append((site.absoluteString, email, token))
                            return api
                        },
                        now: { t })
    }

    func issue(_ key: String, value: Double, sp: Double, priority: String) -> JiraIssue {
        JiraIssue(key: key, fields: ["summary": .string("S \(key)"), "cf_value": .number(value),
                                     "cf_sp": .number(sp), "priority": .object(["name": .string(priority)])])
    }

    func cache(_ presetId: String, _ keys: [String], account: String, age: TimeInterval = 600) {
        let issues = keys.map { issue($0, value: 5, sp: 5, priority: "Low") }
        try? IssueCache(directory: dir).save(CachedFetch(issues: issues, fetchedAt: clockNow.addingTimeInterval(-age),
                                                         accountId: account), presetId: presetId)
    }

    // MARK: - Configured / setup

    @Test func notConfiguredDoesNotCallJira() async {
        let m = makeModel()
        #expect(!m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.isEmpty)
        #expect(m.renderState.configured == false)
        #expect(m.renderState.setup == RenderSetup(message: "Finish setup to see your Jira issues.", tab: "accounts"))
    }

    @Test func incompleteAxesAskToMapAxesForThatAccount() {
        var cfg = configuredConfig()
        cfg.accounts[1].axes.value.mapping = nil
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(!m.isConfigured)
        #expect(m.renderState.setup == RenderSetup(message: "Map axes for Company to see this preset", tab: "axes"))
        #expect(m.isAccountConfigured(m.config.accounts[0]))
    }

    @Test func accountWithoutTokenNeedsSetup() {
        tokens.tokens["c1"] = nil
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(!m.isConfigured)
        #expect(m.renderState.setup?.tab == "accounts")
    }

    // MARK: - Refresh uses the active preset's account

    @Test func successfulRefreshRendersAndCachesPerPreset() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 10, sp: 0, priority: "Highest")]))
        let m = makeModel(config: configuredConfig())
        #expect(m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.count == 1)
        #expect(api.searchCalls[0].jql == JQLPreset.myOpenWork.jql)
        #expect(api.searchCalls[0].fields == ["summary", "status", "priority", "duedate", "cf_value", "cf_sp"])
        #expect(api.searchCalls[0].cap == 500)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
        #expect(m.renderState.tasks[0].rank == 1)
        #expect(m.renderState.status.syncedAt == clockNow)
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.configured)
        #expect(m.renderState.setup == nil)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.count == 1)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.accountId == "default")
    }

    @Test func refreshUsesActivePresetsAccountSiteTokenAndAxes() async {
        api.searchResult = .success(SearchResult(issues: [JiraIssue(key: "C-1", fields: ["customfield_200": .number(5)])]))
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        await m.refresh(.manual)
        #expect(clients.calls.last?.site == "https://corp.atlassian.net")
        #expect(clients.calls.last?.email == "me@corp.com")
        #expect(clients.calls.last?.token == "ctok")
        #expect(api.searchCalls[0].jql == "project = CORP")
        #expect(api.searchCalls[0].fields == ["summary", "status", "priority", "duedate", "customfield_200", "customfield_201"])
        #expect(m.renderState.tasks[0].url == "https://corp.atlassian.net/browse/C-1")
        #expect(m.renderState.tasks[0].value == 0.5)
        #expect(m.issueURL(key: "C-1")?.absoluteString == "https://corp.atlassian.net/browse/C-1")
    }

    @Test func secondRefreshFlagsChangedTasks() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low"),
                                                          issue("B-1", value: 5, sp: 5, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 9, sp: 2, priority: "Low"),
                                                          issue("B-1", value: 5, sp: 5, priority: "Low")]))
        await m.refresh(.manual)
        let changed = Dictionary(uniqueKeysWithValues: m.renderState.tasks.map { ($0.key, $0.changed) })
        #expect(changed == ["A-1": true, "B-1": false])
        m.setQuickSetting(key: "grid", value: .bool(false))
        #expect(m.renderState.tasks.allSatisfy { !$0.changed })
    }

    // MARK: - Backfill axis field names

    @Test func refreshBackfillsAxisFieldNamesOncePerAccount() async {
        api.fieldsResult = [JiraField(id: "cf_value", name: "Business Value", custom: true, schemaType: "number", schemaItems: nil),
                            JiraField(id: "cf_sp", name: "Story Points", custom: true, schemaType: "number", schemaItems: nil),
                            JiraField(id: "priority", name: "Priority", custom: false, schemaType: "priority", schemaItems: nil)]
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 1, sp: 1, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.axisLabels.value == "cf_value")
        await m.refresh(.manual)
        #expect(api.fieldsCalls == 1)
        #expect(m.renderState.axisLabels == RenderAxisLabels(value: "Business Value", effort: "Story Points", urgency: "Priority"))
        #expect(m.config.accounts[0].axes.value.fieldName == "Business Value")
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(saved.accounts[0].axes.urgency.fieldName == "Priority")
        #expect(api.searchCalls.count == 1) // no extra refresh
        await m.refresh(.manual)
        #expect(api.fieldsCalls == 1)
    }

    static let namedFields = [JiraField(id: "cf_value", name: "Business Value", custom: true, schemaType: "number"),
                              JiraField(id: "cf_sp", name: "Story Points", custom: true, schemaType: "number"),
                              JiraField(id: "priority", name: "Priority", custom: false, schemaType: "priority")]

    @Test func backfillKeepsChangedFlagsOnThatRunAndLater() async {
        api.fieldsResult = Self.namedFields
        cache("my-open-work", ["A-1"], account: "default") // value 5, sp 5, Low
        let m = makeModel(config: configuredConfig())
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 9, sp: 5, priority: "Low")]))
        await m.refresh(.manual)
        #expect(m.config.accounts[0].axes.value.fieldName == "Business Value") // backfill ran
        #expect(m.renderState.tasks.map(\.changed) == [true])
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 5, priority: "Low")]))
        await m.refresh(.manual)
        #expect(api.fieldsCalls == 1)
        #expect(m.renderState.tasks.map(\.changed) == [true])
    }

    @Test func backfillFailureIsNotRetriedAndLabelsStayIds() async {
        api.fieldsError = .network("offline")
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 1, sp: 1, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        await m.refresh(.manual)
        #expect(api.fieldsCalls == 1)
        #expect(m.renderState.axisLabels == RenderAxisLabels(value: "cf_value", effort: "cf_sp", urgency: "priority"))
    }

    // MARK: - Switching presets

    @Test func switchingPresetShowsItsCacheInstantlyThenRefetches() async {
        cache("my-open-work", ["A-1"], account: "default", age: 60)
        cache("p2", ["C-1", "C-2"], account: "c1", age: 300)
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
        #expect(m.selectPreset(id: "p2") == .selected)
        #expect(Set(m.renderState.tasks.map(\.key)) == ["C-1", "C-2"])
        #expect(m.renderState.status.syncedAt == clockNow.addingTimeInterval(-300))
        #expect(m.renderState.activePresetId == "p2")
        #expect(api.searchCalls.isEmpty)
        api.searchResult = .success(SearchResult(issues: [issue("C-3", value: 1, sp: 1, priority: "Low")]))
        await m.refresh(.manual)
        #expect(api.searchCalls.map(\.jql) == ["project = CORP"])
        #expect(m.renderState.tasks.map(\.key) == ["C-3"])
    }

    @Test func presetWithoutCacheShowsNothingRatherThanTheOldPresetsIssues() {
        cache("my-open-work", ["A-1"], account: "default")
        let m = makeModel(config: configuredConfig())
        m.selectPreset(id: "p2")
        #expect(m.renderState.tasks.isEmpty)
        #expect(m.renderState.status.syncedAt == nil)
    }

    @Test func cacheWrittenForAnotherAccountIsIgnored() {
        cache("p2", ["X-1"], account: "default") // the preset was reassigned to c1 since
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(m.renderState.tasks.isEmpty)
    }

    @Test func activePresetIsPersistedAndRestoredOnLaunch() {
        let m = makeModel(config: configuredConfig())
        m.selectPreset(id: "p2")
        let relaunched = makeModel()
        #expect(relaunched.config.activePresetId == "p2")
        #expect(relaunched.renderState.activePresetId == "p2")
        #expect(relaunched.activeAccount?.id == "c1")
    }

    @Test func presetWhoseAccountIsMissingCannotBeActivated() {
        var cfg = configuredConfig()
        cfg.presets.append(JQLPreset(id: "orphan", name: "Old", jql: "x", accountId: "gone"))
        let m = makeModel(config: cfg)
        #expect(m.selectPreset(id: "orphan") == .accountMissing)
        #expect(m.selectPreset(id: "nope") == .notFound)
        #expect(m.config.activePresetId == "my-open-work")
        #expect(m.renderState.presets.last == RenderPreset(id: "orphan", name: "Old", accountId: "gone"))
    }

    // MARK: - Errors per account

    @Test func unauthorizedNamesTheAccountAndDoesNotBlockAnotherAccount() async {
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed (Company) · Open settings")
        #expect(m.renderState.status.bannerTab == "accounts")
        #expect(m.renderState.accounts.map(\.error) == [false, true])
        #expect(m.hasError(accountId: "c1"))
        let calls = api.searchCalls.count
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls) // paused for Company
        m.selectPreset(id: "my-open-work")
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 1, sp: 1, priority: "Low")]))
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls + 1) // Personal is not blocked
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.accounts.map(\.error) == [false, true]) // ⚠ stays on Company's presets
    }

    @Test func unauthorizedKeepsDataOnScreen() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed (Personal) · Open settings")
        #expect(m.renderState.tasks.count == 1)
    }

    @Test func offlineShowsCachedDataTime() async {
        api.searchResult = .failure(.network("offline"))
        cache("my-open-work", ["A-1"], account: "default")
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.tasks.count == 1)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner?.hasPrefix("Offline · showing data from ") == true)
        #expect(m.renderState.tasks.count == 1)
    }

    @Test func badJqlShowsJiraMessage() async {
        api.searchResult = .failure(.badRequest("Field 'x' does not exist."))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "JQL error: Field 'x' does not exist.")
        #expect(m.renderState.status.bannerTab == nil)
    }

    @Test func truncatedResultSetsNotice() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                 truncated: true, approximateTotal: 1240))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.truncated == "Showing 1 of 1240 · narrow your JQL")
    }

    @Test func zeroIssuesIsNotAnError() async {
        api.searchResult = .success(SearchResult(issues: []))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.tasks.isEmpty)
        #expect(m.renderState.status.banner == nil)
    }

    @Test func axisWithNoDataGetsBanner() async {
        api.searchResult = .success(SearchResult(issues: [JiraIssue(key: "A-1", fields: ["cf_sp": .number(1),
                                                                                       "priority": .object(["name": .string("Low")])])]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "No data for value field · check mapping in settings")
        #expect(m.renderState.status.bannerTab == "axes")
    }

    @Test func keychainReadErrorFlagsTheAccount() {
        tokens.readError = TokenStoreError.status(-25293)
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.status.banner == "Keychain access denied · re-enter your API token in settings")
        #expect(m.renderState.accounts.map(\.error) == [true, true])
        #expect(!m.isConfigured)
    }

    // MARK: - In-flight fetch vs preset switch (Review Focus #3)

    @Test func inFlightResultOfPreviousPresetIsCachedButNotShown() async {
        let gated = GatedJiraAPI()
        gated.later = [JiraIssue(key: "C-9", fields: [:])]
        try? ConfigStore(directory: dir).save(configuredConfig())
        let t = clockNow
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(now: { t }), makeClient: { _, _, _ in gated }, now: { t })
        let a = Task { await m.refresh(.manual) }
        while gated.searchJQLs.isEmpty { await Task.yield() }
        m.selectPreset(id: "p2")
        await m.refresh(.manual)               // coalesced: re-runs for p2 after the in-flight fetch
        gated.release(.success([issue("A-1", value: 1, sp: 1, priority: "Low")]))
        await a.value
        #expect(gated.searchJQLs == [JQLPreset.myOpenWork.jql, "project = CORP"])
        #expect(m.renderState.tasks.map(\.key) == ["C-9"])
        #expect(m.renderState.activePresetId == "p2")
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.map(\.key) == ["A-1"])
        #expect(IssueCache(directory: dir).load(presetId: "p2")?.issues.map(\.key) == ["C-9"])
    }

    @Test func inFlightFailureOfPreviousPresetDoesNotPauseOrBannerTheNewOne() async {
        let gated = GatedJiraAPI()
        try? ConfigStore(directory: dir).save(configuredConfig())
        let t = clockNow
        let sched = RefreshScheduler(now: { t })
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: sched, makeClient: { _, _, _ in gated }, now: { t })
        let a = Task { await m.refresh(.timer) }
        while gated.searchJQLs.isEmpty { await Task.yield() }
        m.selectPreset(id: "p2")
        gated.release(.failure(.unauthorized))
        await a.value
        #expect(!sched.isPaused)
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.accounts.map(\.error) == [true, false]) // ⚠ on Personal's presets only
    }

    // MARK: - Accounts and presets management

    @Test func newAccountIdIsDefaultFirstThenUnique() throws {
        let m = makeModel()
        #expect(m.newAccountId() == "default")
        try m.saveAccount(JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com"),
                          token: "t1")
        let next = m.newAccountId()
        #expect(next != "default")
        #expect(UUID(uuidString: next) != nil)
    }

    @Test func saveAccountWritesKeyedTokenAndUpserts() throws {
        let m = makeModel(config: configuredConfig())
        var company = m.config.accounts[1]
        company.name = "Work"
        try m.saveAccount(company, token: "new")
        #expect(tokens.tokens["c1"] == "new")
        #expect(m.storedToken(accountId: "c1") == "new")
        #expect(m.config.accounts.map(\.name) == ["Personal", "Work"])
        tokens.writeError = TokenStoreError.status(-25308)
        company.name = "Ignored"
        #expect(throws: TokenStoreError.status(-25308)) { try m.saveAccount(company, token: "x") }
        #expect(m.config.accounts[1].name == "Work")
    }

    @Test func removeAccountDeletesItsPresetsCachesAndTokenAndPicksNextPreset() {
        cache("p2", ["C-1"], account: "c1")
        cache("my-open-work", ["A-1"], account: "default")
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        m.removeAccount(id: "c1")
        #expect(m.config.accounts.map(\.id) == ["default"])
        #expect(m.config.presets.map(\.id) == ["my-open-work"])
        #expect(m.config.activePresetId == "my-open-work")
        #expect(tokens.tokens["c1"] == nil)
        #expect(IssueCache(directory: dir).load(presetId: "p2") == nil)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }

    @Test func addPresetActivatesAndDeletePresetFallsBack() {
        let m = makeModel(config: configuredConfig())
        m.addPreset(JQLPreset(id: "due", name: "Due this week", jql: "due <= endOfWeek()", accountId: "default"), activate: true)
        #expect(m.config.activePresetId == "due")
        #expect(m.renderState.presets.map(\.id) == ["my-open-work", "due", "p2"])
        m.deletePreset(id: "due")
        #expect(m.config.activePresetId == "my-open-work")
        #expect(!m.config.presets.contains { $0.id == "due" })
    }

    @Test func testJQLMapsJiraErrors() async {
        let m = makeModel(config: configuredConfig())
        api.countResult = .success(42)
        #expect(await m.testJQL("project = A", accountId: "default") == .count(42))
        api.countResult = .failure(.badRequest("Field 'x' does not exist."))
        #expect(await m.testJQL("x = 1", accountId: "default") == .jqlError("Field 'x' does not exist."))
        api.countResult = .failure(.network("offline"))
        #expect(await m.testJQL("x", accountId: "default") == .failed("Offline · no cached data"))
        #expect(await m.testJQL("x", accountId: "gone") == .failed("Not configured · Open settings"))
        #expect(JQLTestResult.count(3).text == "3 issues match")
    }

    @Test func canCreatePresetRules() {
        let c = configuredConfig()
        #expect(c.canCreatePreset(name: "Due this week", accountId: "default", lastTest: nil))
        #expect(c.canCreatePreset(name: "Due this week", accountId: "default", lastTest: .failed("Offline · no cached data")))
        #expect(!c.canCreatePreset(name: " ", accountId: "default", lastTest: nil))
        #expect(!c.canCreatePreset(name: "my open work", accountId: "default", lastTest: nil))
        #expect(c.canCreatePreset(name: "My open work", accountId: "c1", lastTest: .count(3)))
        #expect(!c.canCreatePreset(name: "New", accountId: "default", lastTest: .jqlError("bad")))
        #expect(!c.canCreatePreset(name: "New", accountId: "gone", lastTest: nil))
    }

    // MARK: - Migration failure (§11.10)

    @Test func migrationFailureShowsBannerAndKeepsWorkingWithLegacyToken() async throws {
        try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/config-v1.1.json"))
            .write(to: ConfigStore(directory: dir).url)
        let legacyOnly = InMemoryTokenStore(legacyToken: "legacy-tok")
        legacyOnly.writeError = TokenStoreError.status(-25308)
        let t = clockNow
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: legacyOnly,
                         scheduler: RefreshScheduler(now: { t }),
                         makeClient: { [api, clients] site, email, token in
                             clients.calls.append((site.absoluteString, email, token)); return api
                         }, now: { t })
        #expect(m.migrationFailed)
        #expect(m.renderState.status.banner == "Could not migrate settings · Open settings")
        #expect(m.renderState.status.bannerTab == "accounts")
        #expect(m.isConfigured)
        await m.refresh(.manual)
        #expect(clients.calls.last?.token == "legacy-tok")
        #expect(clients.calls.last?.site == "https://example-personal.atlassian.net")
        #expect(legacyOnly.legacyToken == "legacy-tok")
    }

    // MARK: - Unchanged behaviour

    @Test func quickSettingAndDefaultViewPersist() {
        let m = makeModel(config: configuredConfig())
        m.setQuickSetting(key: "labelMode", value: .string("key"))
        m.saveDefaultView(yaw: -539.7, pitch: 95, zoom: 9)
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(saved.quick.labelMode == "key")
        #expect(abs(saved.view.yaw - -179.7) < 1e-9)
        #expect(saved.view.pitch == 80)
        #expect(saved.view.zoom == 3)
        #expect(m.renderState.settings.labelMode == "key")
    }

    @Test func lastViewPersistsNormalizedWithoutRerender() {
        let m = makeModel(config: configuredConfig())
        let before = m.renderState
        m.saveLastView(yaw: -539.7, pitch: 95, zoom: 9)
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(abs(saved.lastView!.yaw - -179.7) < 1e-9)
        #expect(saved.lastView!.pitch == 89)
        #expect(saved.lastView!.zoom == 3)
        #expect(saved.view == ViewDefaults())
        #expect(m.renderState == before)
        m.saveLastView(yaw: .nan, pitch: 0, zoom: 1)
        m.saveLastView(yaw: 0, pitch: .infinity, zoom: 1)
        #expect(m.config.lastView == saved.lastView)
    }

    @Test func corruptConfigIsFlagged() throws {
        try Data("{oops".utf8).write(to: ConfigStore(directory: dir).url)
        let m = makeModel()
        #expect(m.configWasCorrupt)
        #expect(m.config == AppConfig())
    }

    @Test func unmappedLabelsAreReported() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Blocker")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.unmappedLabels[.urgency] == ["Blocker"])
    }
}

/// First `search` suspends until `release`; later ones return `later` immediately.
final class GatedJiraAPI: JiraAPI {
    var searchJQLs: [String] = []
    var later: [JiraIssue] = []
    private var cont: CheckedContinuation<Result<[JiraIssue], JiraError>, Never>?
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { 0 }
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        searchJQLs.append(jql)
        if searchJQLs.count == 1 {
            return SearchResult(issues: try await withCheckedContinuation { cont = $0 }.get())
        }
        return SearchResult(issues: later)
    }
    func release(_ result: Result<[JiraIssue], JiraError>) { cont?.resume(returning: result); cont = nil }
}
