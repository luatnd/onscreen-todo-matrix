import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var renderState: RenderState = .empty
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue] = []
    @Published public private(set) var unmappedLabels: [Axis: [String]] = [:]
    public private(set) var configWasCorrupt = false
    /// The v1.1 → v1.2 migration could not finish; the old setup is kept (§11.10).
    public private(set) var migrationFailed = false

    private let configStore: ConfigStore
    private let cache: IssueCache
    private let tokenStore: TokenStore
    private let scheduler: RefreshScheduler
    private let makeClient: (URL, String, String) -> JiraAPI
    private let now: () -> Date
    private let calendar: Calendar

    private var tokens: [String: String] = [:]
    private var tokenErrorAccounts: Set<String> = []
    private var syncedAt: Date?
    private var banner: String?
    private var truncated: String?
    private var lastMapped: [MappedTask] = []
    private var isRefreshing = false
    private var rerunRequested = false

    public static let issueCap = 500

    public init(configStore: ConfigStore, cache: IssueCache, tokenStore: TokenStore, scheduler: RefreshScheduler,
                makeClient: @escaping (URL, String, String) -> JiraAPI,
                now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.configStore = configStore
        self.cache = cache
        self.tokenStore = tokenStore
        self.scheduler = scheduler
        self.makeClient = makeClient
        self.now = now
        self.calendar = calendar
        switch configStore.load() {
        case .loaded(let c): config = c
        case .legacy(let c):
            config = c
            migrationFailed = !ConfigMigration.finish(c, store: configStore, tokens: tokenStore, cache: cache)
        case .missing: config = AppConfig()
        case .corrupt: config = AppConfig(); configWasCorrupt = true
        }
        for account in config.accounts { loadToken(account.id) }
        if let preset = config.activePreset, let cached = cache.load(presetId: preset.id), cached.accountId == preset.accountId {
            issues = cached.issues
            syncedAt = cached.fetchedAt
        }
        if let id = activeAccount?.id, tokenErrorAccounts.contains(id) {
            banner = "Keychain access denied · re-enter your API token in settings"
        }
        rebuild(previous: nil)
    }

    public var activeAccount: JiraAccount? { config.activeAccount }

    public func storedToken(accountId: String) -> String? { tokens[accountId] }

    /// Site, email, token and all three axes mapped.
    public func isAccountConfigured(_ account: JiraAccount) -> Bool {
        account.siteURL != nil && !account.email.isEmpty && !(tokens[account.id] ?? "").isEmpty && account.axes.isComplete
    }

    /// The active preset's account is configured (§11.7).
    public var isConfigured: Bool { activeAccount.map(isAccountConfigured) ?? false }

    /// "default" for the first account (so the pre-filled "My open work" preset belongs to it), a UUID afterwards.
    public func newAccountId() -> String {
        config.account(id: JiraAccount.defaultId) == nil ? JiraAccount.defaultId : UUID().uuidString
    }

    public func makeAPI(accountId: String) throws -> JiraAPI {
        guard let account = config.account(id: accountId), let site = account.siteURL, !account.email.isEmpty,
              let token = tokens[accountId], !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, account.email, token)
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        if isRefreshing {
            if trigger == .manual { rerunRequested = true }
            return
        }
        guard isConfigured, let preset = config.activePreset,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI(accountId: preset.accountId) else { return }
        isRefreshing = true
        await fetch(api, preset: preset)
        isRefreshing = false
        if rerunRequested {
            rerunRequested = false
            await refresh(.manual)
        }
    }

    private func fetch(_ api: JiraAPI, preset: JQLPreset) async {
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            let result = try await api.search(jql: preset.jql, fields: fetchFields(), cap: Self.issueCap)
            scheduler.recordSuccess()
            issues = result.issues
            let fetchedAt = now()
            syncedAt = fetchedAt
            banner = nil
            truncated = result.truncated
                ? "Showing \(result.issues.count) of \(result.approximateTotal.map(String.init) ?? "\(result.issues.count)+") · narrow your JQL"
                : nil
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt, accountId: preset.accountId), presetId: preset.id)
            rebuild(previous: previous)
        } catch let error as JiraError {
            scheduler.recordFailure(error)
            banner = Self.bannerText(error, syncedAt: syncedAt)
            rebuild(previous: nil)
        } catch {
            banner = "Refresh failed: \(error.localizedDescription)"
            rebuild(previous: nil)
        }
    }

    public func updateConfig(_ newConfig: AppConfig) {
        banner = nil // stale error; the next refresh re-sets it if still failing
        persist(newConfig)
        scheduler.resume()
    }

    /// Inserts or updates the account and stores its token in Keychain (token first: a Keychain error changes nothing).
    public func saveAccount(_ account: JiraAccount, token: String) throws {
        try tokenStore.write(token, accountId: account.id)
        tokens[account.id] = token
        tokenErrorAccounts.remove(account.id)
        var c = config
        c.upsertAccount(account)
        updateConfig(c)
    }

    public func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void) {
        var c = config
        guard let i = c.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        change(&c.accounts[i].axes)
        updateConfig(c)
    }

    public func setQuickSetting(key: String, value: JSONValue) {
        var c = config
        c.quick = c.quick.applying(key: key, value: value)
        persist(c)
    }

    public func saveDefaultView(yaw: Double, pitch: Double, zoom: Double) {
        var c = config
        let normalizedYaw = (((yaw + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        c.view = ViewDefaults(yaw: normalizedYaw, pitch: min(80, max(-80, pitch)), zoom: min(3, max(0.5, zoom)))
        persist(c)
    }

    /// Persists the live camera view (restored on launch). Deliberately no rebuild: the chart already shows it.
    public func saveLastView(yaw: Double, pitch: Double, zoom: Double) {
        guard yaw.isFinite, pitch.isFinite, zoom.isFinite else { return }
        let normalizedYaw = (((yaw + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        var c = config
        c.lastView = ViewDefaults(yaw: normalizedYaw, pitch: min(89, max(-89, pitch)), zoom: min(3, max(0.5, zoom)))
        config = c
        try? configStore.save(c)
    }

    public func selectPreset(id: String) {
        guard config.presets.contains(where: { $0.id == id }) else { return }
        var c = config
        c.activePresetId = id
        updateConfig(c)
    }

    public func issueURL(key: String) -> URL? {
        activeAccount?.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
    }

    public static func bannerText(_ error: JiraError, syncedAt: Date?) -> String {
        switch error {
        case .network:
            guard let syncedAt else { return "Offline · no cached data" }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Offline · showing data from \(f.string(from: syncedAt))"
        case .unauthorized: return "Jira sign-in failed · Open settings"
        case .rateLimited: return "Jira rate limit · retrying later"
        case .badRequest(let m): return "JQL error: \(m)"
        case .http(let code): return "Jira error \(code)"
        case .decoding: return "Unexpected response from Jira"
        case .notConfigured: return "Not configured · Open settings"
        }
    }

    // MARK: - Private

    private func loadToken(_ accountId: String) {
        do {
            tokens[accountId] = try tokenStore.read(accountId: accountId)
            tokenErrorAccounts.remove(accountId)
        } catch {
            tokens[accountId] = nil
            tokenErrorAccounts.insert(accountId)
        }
    }

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = activeAccount?.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func rebuild(previous: [String: MappedTask]?) {
        let account = activeAccount
        if let account, let site = account.siteURL {
            lastMapped = AxisMapper.map(issues: issues, axes: account.axes, site: site, now: now(), calendar: calendar)
        } else {
            lastMapped = []
        }
        var unmapped: [Axis: [String]] = [:]
        var axisBanner: String?
        for axis in Axis.allCases {
            guard let mapping = account?.axes[axis].mapping else { continue }
            let labels = AxisMapper.unmappedLabels(issues: issues, mapping: mapping)
            if !labels.isEmpty { unmapped[axis] = labels }
            if axisBanner == nil, !lastMapped.isEmpty, lastMapped.allSatisfy({ $0.missing[axis] }) {
                axisBanner = "No data for \(axis.rawValue) field · check mapping in settings"
            }
        }
        unmappedLabels = unmapped
        let status = RenderStatus(syncedAt: syncedAt, banner: banner ?? axisBanner, truncated: truncated)
        renderState = RenderStateBuilder.build(tasks: lastMapped, previous: previous, config: config,
                                               status: status, configured: isConfigured)
    }
}
