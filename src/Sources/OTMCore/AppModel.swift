import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var renderState: RenderState = .empty
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue] = []
    @Published public private(set) var unmappedLabels: [Axis: [String]] = [:]
    public private(set) var configWasCorrupt = false

    private let configStore: ConfigStore
    private let cache: IssueCache
    private let tokenStore: TokenStore
    private let scheduler: RefreshScheduler
    private let makeClient: (URL, String, String) -> JiraAPI
    private let now: () -> Date
    private let calendar: Calendar

    private var token: String?
    private var tokenError = false
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
        case .missing: config = AppConfig()
        case .corrupt: config = AppConfig(); configWasCorrupt = true
        }
        do { token = try tokenStore.read() } catch { tokenError = true }
        if let cached = cache.load() {
            issues = cached.issues
            syncedAt = cached.fetchedAt
        }
        if tokenError { banner = "Keychain access denied · re-enter your API token in settings" }
        rebuild(previous: nil)
    }

    public var storedToken: String? { token }

    public var isConfigured: Bool {
        config.siteURL != nil && !config.email.isEmpty && !(token ?? "").isEmpty && config.axes.isComplete
    }

    public func makeAPI() throws -> JiraAPI {
        guard let site = config.siteURL, !config.email.isEmpty, let token, !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, config.email, token)
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        if isRefreshing {
            if trigger == .manual { rerunRequested = true }
            return
        }
        guard isConfigured,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI() else { return }
        isRefreshing = true
        await fetch(api)
        isRefreshing = false
        if rerunRequested {
            rerunRequested = false
            await refresh(.manual)
        }
    }

    private func fetch(_ api: JiraAPI) async {
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            let result = try await api.search(jql: config.activePreset.jql, fields: fetchFields(), cap: Self.issueCap)
            scheduler.recordSuccess()
            issues = result.issues
            let fetchedAt = now()
            syncedAt = fetchedAt
            banner = nil
            truncated = result.truncated
                ? "Showing \(result.issues.count) of \(result.approximateTotal.map(String.init) ?? "\(result.issues.count)+") · narrow your JQL"
                : nil
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt))
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

    public func setToken(_ newToken: String) throws {
        try tokenStore.write(newToken)
        token = newToken
        tokenError = false
        banner = nil
        scheduler.resume()
        rebuild(previous: nil)
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

    public func selectPreset(id: String) {
        guard config.presets.contains(where: { $0.id == id }) else { return }
        var c = config
        c.activePresetId = id
        updateConfig(c)
    }

    public func issueURL(key: String) -> URL? {
        config.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
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

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = config.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func rebuild(previous: [String: MappedTask]?) {
        if let site = config.siteURL {
            lastMapped = AxisMapper.map(issues: issues, axes: config.axes, site: site, now: now(), calendar: calendar)
        } else {
            lastMapped = []
        }
        var unmapped: [Axis: [String]] = [:]
        var axisBanner: String?
        for axis in Axis.allCases {
            guard let mapping = config.axes[axis].mapping else { continue }
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
