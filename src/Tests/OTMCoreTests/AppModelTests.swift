import Foundation
import Testing
@testable import OTMCore

@MainActor
@Suite struct AppModelTests {
    let dir = makeTempDir()
    let api = FakeJiraAPI()
    let tokens = InMemoryTokenStore(tokens: ["default": "tok"])
    var clockNow = Date(timeIntervalSince1970: 1_800_000_000)

    func configuredConfig() -> AppConfig {
        var axes = AxesConfig()
        axes.value.mapping = .number(fieldId: "cf_value", min: 0, max: 10, invert: false)
        axes.effort.mapping = .number(fieldId: "cf_sp", min: 0, max: 10, invert: false)
        axes.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com", axes: axes)]
        return c
    }

    func makeModel(config: AppConfig? = nil) -> AppModel {
        if let config { try? ConfigStore(directory: dir).save(config) }
        let t = clockNow
        return AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                        scheduler: RefreshScheduler(now: { t }), makeClient: { [api] _, _, _ in api }, now: { t })
    }

    func issue(_ key: String, value: Double, sp: Double, priority: String) -> JiraIssue {
        JiraIssue(key: key, fields: ["summary": .string("S \(key)"), "cf_value": .number(value),
                                     "cf_sp": .number(sp), "priority": .object(["name": .string(priority)])])
    }

    @Test func notConfiguredDoesNotCallJira() async {
        let m = makeModel()
        #expect(!m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.isEmpty)
        #expect(m.renderState.configured == false)
    }

    @Test func successfulRefreshRendersAndCaches() async {
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
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.count == 1)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.accountId == "default")
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

    @Test func unauthorizedKeepsDataShowsBannerAndPausesFocus() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed · Open settings")
        #expect(m.renderState.tasks.count == 1)
        let calls = api.searchCalls.count
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls)
    }

    @Test func offlineShowsCachedDataTime() async {
        api.searchResult = .failure(.network("offline"))
        var cfg = configuredConfig()
        cfg.quick.refreshMinutes = 5
        try? IssueCache(directory: dir).save(CachedFetch(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                         fetchedAt: clockNow.addingTimeInterval(-600), accountId: "default"),
                                             presetId: "my-open-work")
        let m = makeModel(config: cfg)
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
    }

    @Test func truncatedResultSetsNotice() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                 truncated: true, approximateTotal: 1240))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.truncated == "Showing 1 of 1240 · narrow your JQL")
    }

    @Test func zeroIssuesIsNotAnError() async {
        // Review Focus #3
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
    }

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

    @Test func configWithoutLastViewStillDecodes() throws {
        var obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig())) as? [String: Any])
        obj.removeValue(forKey: "lastView")
        let c = try JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(c.lastView == nil)
    }

    @Test func corruptConfigIsFlagged() throws {
        try Data("{oops".utf8).write(to: ConfigStore(directory: dir).url)
        let m = makeModel()
        #expect(m.configWasCorrupt)
        #expect(m.config == AppConfig())
    }

    @Test func selectPresetAndIssueURL() {
        var cfg = configuredConfig()
        cfg.presets.append(JQLPreset(id: "team", name: "Team", jql: "project = T"))
        let m = makeModel(config: cfg)
        m.selectPreset(id: "team")
        #expect(m.config.activePresetId == "team")
        #expect(m.issueURL(key: "T-1")?.absoluteString == "https://acme.atlassian.net/browse/T-1")
    }

    @Test func unmappedLabelsAreReported() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Blocker")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.unmappedLabels[.urgency] == ["Blocker"])
    }

    @Test func manualRefreshDuringInFlightRerunsWithNewPreset() async {
        let gated = GatedJiraAPI()
        var cfg = configuredConfig()
        cfg.presets.append(JQLPreset(id: "team", name: "Team", jql: "project = T"))
        try? ConfigStore(directory: dir).save(cfg)
        let t = clockNow
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(now: { t }), makeClient: { _, _, _ in gated }, now: { t })
        let a = Task { await m.refresh(.manual) }
        while gated.searchJQLs.isEmpty { await Task.yield() }
        m.selectPreset(id: "team")
        await m.refresh(.manual)               // dropped before the fix; must be remembered
        gated.release([issue("A-1", value: 1, sp: 1, priority: "Low")])
        await a.value
        #expect(gated.searchJQLs == [JQLPreset.myOpenWork.jql, "project = T"])
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }
}

/// First `search` suspends until `release`; later ones return the same issues immediately.
final class GatedJiraAPI: JiraAPI {
    var searchJQLs: [String] = []
    private var cont: CheckedContinuation<[JiraIssue], Never>?
    private var issues: [JiraIssue] = []
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { 0 }
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        searchJQLs.append(jql)
        if searchJQLs.count == 1 {
            return SearchResult(issues: await withCheckedContinuation { cont = $0 })
        }
        return SearchResult(issues: issues)
    }
    func release(_ result: [JiraIssue]) { issues = result; cont?.resume(returning: result); cont = nil }
}
