import Combine
import Foundation

/// Result of `AppModel.selectPreset(id:)`.
public enum PresetSelection: Equatable, Sendable {
    case selected
    /// The preset's account no longer exists: it cannot be activated until reassigned (§11.2).
    case accountMissing
    case notFound
}

/// Result of a JQL Test in Settings.
public enum JQLTestResult: Equatable, Sendable {
    case count(Int)
    /// Jira rejected the JQL (400); blocks "Create & show".
    case jqlError(String)
    /// Anything else (network, sign-in…); does not block saving.
    case failed(String)

    public var text: String {
        switch self {
        case .count(let n): return "\(n) issues match"
        case .jqlError(let m): return "JQL error: \(m)"
        case .failed(let m): return m
        }
    }
}

extension AppConfig {
    /// New preset sheet: Save is disabled while the name is empty/duplicate (within the account),
    /// the account is unknown, or the last Test failed with a JQL error (§11.7).
    public func canCreatePreset(name: String, accountId: String, lastTest: JQLTestResult?) -> Bool {
        guard account(id: accountId) != nil, isPresetNameValid(name, accountId: accountId) else { return false }
        if case .jqlError = lastTest { return false }
        return true
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var renderState: RenderState = .empty
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue] = []
    @Published public private(set) var unmappedLabels: [Axis: [String]] = [:]
    /// Accounts whose last fetch failed with 401/403 (⚠ in the preset menu, error in the Accounts tab).
    @Published public private(set) var authFailedAccounts: Set<String> = []
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
    private var bannerTab: String?
    private var truncated: String?
    private var lastMapped: [MappedTask] = []
    private var isRefreshing = false
    private var rerunRequested = false
    /// The on-disk config.json is still v1.1 and its backup could not be made: never overwrite it.
    private var protectUnbackedLegacyFile = false
    private var fieldNamesTried: Set<String> = []

    public static let issueCap = 500
    public static let migrationBanner = "Could not migrate settings · Open settings"
    public static let setupMessage = "Finish setup to see your Jira issues."

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
        case .loaded(let c):
            config = c
            // Retry a token copy that failed on a previous launch (the legacy item is still there).
            if c.account(id: JiraAccount.defaultId) != nil, (try? tokenStore.read(accountId: JiraAccount.defaultId)) == nil,
               (try? tokenStore.readLegacy()) != nil {
                migrationFailed = !ConfigMigration.copyLegacyToken(tokens: tokenStore)
            }
        case .legacy(let c):
            config = c
            migrationFailed = !ConfigMigration.finish(c, store: configStore, tokens: tokenStore, cache: cache)
            protectUnbackedLegacyFile = migrationFailed && !FileManager.default.fileExists(atPath: configStore.legacyBackupURL.path)
        case .missing: config = AppConfig()
        case .corrupt: config = AppConfig(); configWasCorrupt = true
        }
        for account in config.accounts { loadToken(account.id) }
        loadActiveCache()
        if let id = activeAccount?.id, tokenErrorAccounts.contains(id) {
            banner = "Keychain access denied · re-enter your API token in settings"
            bannerTab = "accounts"
        }
        rebuild(previous: nil)
    }

    // MARK: - Accounts

    public var activeAccount: JiraAccount? { config.activeAccount }

    public func storedToken(accountId: String) -> String? { tokens[accountId] }

    /// Site, email and token present (the account can talk to Jira).
    public func hasCredentials(_ account: JiraAccount) -> Bool {
        account.siteURL != nil && !account.email.isEmpty && !(tokens[account.id] ?? "").isEmpty
    }

    /// Credentials and all three axes mapped.
    public func isAccountConfigured(_ account: JiraAccount) -> Bool {
        hasCredentials(account) && account.axes.isComplete
    }

    /// The active preset's account is configured (§11.7).
    public var isConfigured: Bool { activeAccount.map(isAccountConfigured) ?? false }

    /// Sign-in (401/403) or Keychain error for this account.
    public func hasError(accountId: String) -> Bool { accountErrors.contains(accountId) }

    /// Keychain read failed for this account (not a Jira sign-in problem).
    public func hasTokenError(accountId: String) -> Bool { tokenErrorAccounts.contains(accountId) }

    /// "default" for the first account (so the pre-filled "My open work" preset belongs to it), a UUID afterwards.
    public func newAccountId() -> String {
        config.account(id: JiraAccount.defaultId) == nil ? JiraAccount.defaultId : UUID().uuidString
    }

    public func makeAPI(accountId: String) throws -> JiraAPI {
        guard let account = config.account(id: accountId), let site = account.siteURL, !account.email.isEmpty,
              let token = tokens[accountId], !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, account.email, token)
    }

    /// Inserts or updates the account and stores its token in Keychain (token first: a Keychain error changes nothing).
    public func saveAccount(_ account: JiraAccount, token: String) throws {
        try tokenStore.write(token, accountId: account.id)
        tokens[account.id] = token
        tokenErrorAccounts.remove(account.id)
        authFailedAccounts.remove(account.id)
        migrationFailed = false
        var c = config
        c.upsertAccount(account)
        updateConfig(c)
    }

    /// Removes the account, its presets (and their caches) and its Keychain item (§11.3, §11.7).
    public func removeAccount(id: String) {
        try? tokenStore.delete(accountId: id)
        if id == JiraAccount.defaultId { try? tokenStore.deleteLegacy() }
        tokens[id] = nil
        tokenErrorAccounts.remove(id)
        authFailedAccounts.remove(id)
        var c = config
        for p in c.presets where p.accountId == id { cache.delete(presetId: p.id) }
        c.accounts.removeAll { $0.id == id }
        c.presets.removeAll { $0.accountId == id }
        if !c.presets.contains(where: { $0.id == c.activePresetId }) {
            c.activePresetId = c.menuOrderedPresets.first?.id ?? ""
        }
        updateConfig(c)
    }

    public func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void) {
        var c = config
        guard let i = c.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        change(&c.accounts[i].axes)
        updateConfig(c)
    }

    // MARK: - Presets

    /// Activates a preset and shows its cached issues instantly; the caller then runs `refresh(.manual)`.
    /// The choice is persisted immediately, so it is restored on launch.
    @discardableResult
    public func selectPreset(id: String) -> PresetSelection {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return .notFound }
        guard config.account(id: preset.accountId) != nil else { return .accountMissing }
        var c = config
        c.activePresetId = id
        updateConfig(c)
        return .selected
    }

    public func addPreset(_ preset: JQLPreset, activate: Bool) {
        var c = config
        c.presets.append(preset)
        updateConfig(c)
        if activate { selectPreset(id: preset.id) }
    }

    public func deletePreset(id: String) {
        var c = config
        c.presets.removeAll { $0.id == id }
        cache.delete(presetId: id)
        if !c.presets.contains(where: { $0.id == c.activePresetId }) {
            c.activePresetId = c.menuOrderedPresets.first?.id ?? ""
        }
        updateConfig(c)
    }

    /// JQL Test for Settings: approximate match count on that account's site.
    public func testJQL(_ jql: String, accountId: String) async -> JQLTestResult {
        do {
            return .count(try await makeAPI(accountId: accountId).approximateCount(jql: jql))
        } catch JiraError.badRequest(let message) {
            return .jqlError(message)
        } catch let error as JiraError {
            return .failed(Self.bannerText(error, syncedAt: nil))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Refresh

    /// Fetches only the active preset: its account's site + token, its JQL, its account's axes (§11.5).
    public func refresh(_ trigger: RefreshTrigger) async {
        if isRefreshing {
            if trigger == .manual { rerunRequested = true }
            return
        }
        guard isConfigured, let preset = config.activePreset,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI(accountId: preset.accountId) else { return }
        isRefreshing = true
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        if await fetch(api, preset: preset, previous: previous) {
            await backfillFieldNames(api, preset: preset, previous: previous)
        }
        isRefreshing = false
        if rerunRequested {
            rerunRequested = false
            await refresh(.manual)
        }
    }

    /// Once per account per run: saves display names for mapped axes that have none (labels fall back to ids on failure).
    private func backfillFieldNames(_ api: JiraAPI, preset: JQLPreset, previous: [String: MappedTask]) async {
        let accountId = preset.accountId
        let missing = { (a: JiraAccount) in Axis.allCases.contains { a.axes[$0].mapping != nil && a.axes[$0].fieldName == nil } }
        guard !fieldNamesTried.contains(accountId), let account = config.account(id: accountId), missing(account) else { return }
        fieldNamesTried.insert(accountId)
        guard let fields = try? await api.fields() else { return }
        var c = config
        guard let i = c.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        c.accounts[i].axes = DefaultMappings.withFieldNames(c.accounts[i].axes, fields: fields)
        guard c != config else { return }
        config = c
        saveConfig(c)
        rebuild(previous: isActive(preset) ? previous : nil)
    }

    @discardableResult
    private func fetch(_ api: JiraAPI, preset: JQLPreset, previous: [String: MappedTask]) async -> Bool {
        do {
            let result = try await api.search(jql: preset.jql, fields: fetchFields(), cap: Self.issueCap)
            let fetchedAt = now()
            authFailedAccounts.remove(preset.accountId)
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt, accountId: preset.accountId),
                            presetId: preset.id)
            // The user switched presets while this was in flight: cached for later, never shown under another preset.
            guard isActive(preset) else { rebuild(previous: nil); return true }
            scheduler.recordSuccess()
            issues = result.issues
            syncedAt = fetchedAt
            banner = nil
            bannerTab = nil
            truncated = result.truncated
                ? "Showing \(result.issues.count) of \(result.approximateTotal.map(String.init) ?? "\(result.issues.count)+") · narrow your JQL"
                : nil
            rebuild(previous: previous)
            return true
        } catch let error as JiraError {
            if error == .unauthorized { authFailedAccounts.insert(preset.accountId) }
            // A stale failure must neither pause nor banner the preset the user switched to.
            guard isActive(preset) else { rebuild(previous: nil); return false }
            scheduler.recordFailure(error)
            banner = Self.bannerText(error, syncedAt: syncedAt, accountName: config.account(id: preset.accountId)?.name)
            bannerTab = error == .unauthorized ? "accounts" : nil
            rebuild(previous: nil)
            return false
        } catch {
            guard isActive(preset) else { return false }
            banner = "Refresh failed: \(error.localizedDescription)"
            bannerTab = nil
            rebuild(previous: nil)
            return false
        }
    }

    // MARK: - Config

    /// Saves settings changes. Clears a stale banner and resumes the scheduler (a 401 pause on one account must not
    /// block another). When the active preset or its account changes, that preset's cache is shown instantly.
    public func updateConfig(_ newConfig: AppConfig) {
        let before = config.activePreset
        banner = nil
        bannerTab = nil
        config = newConfig
        saveConfig(newConfig)
        scheduler.resume()
        let after = newConfig.activePreset
        if before?.id != after?.id || before?.accountId != after?.accountId { loadActiveCache() }
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

    /// Persists the live camera view (restored on launch). Deliberately no rebuild: the chart already shows it.
    public func saveLastView(yaw: Double, pitch: Double, zoom: Double) {
        guard yaw.isFinite, pitch.isFinite, zoom.isFinite else { return }
        let normalizedYaw = (((yaw + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        var c = config
        c.lastView = ViewDefaults(yaw: normalizedYaw, pitch: min(89, max(-89, pitch)), zoom: min(3, max(0.5, zoom)))
        config = c
        saveConfig(c)
    }

    /// Issue URLs use the active preset's account site.
    public func issueURL(key: String) -> URL? {
        activeAccount?.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
    }

    public static func bannerText(_ error: JiraError, syncedAt: Date?, accountName: String? = nil) -> String {
        switch error {
        case .network:
            guard let syncedAt else { return "Offline · no cached data" }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Offline · showing data from \(f.string(from: syncedAt))"
        case .unauthorized:
            return accountName.map { "Jira sign-in failed (\($0)) · Open settings" } ?? "Jira sign-in failed · Open settings"
        case .rateLimited: return "Jira rate limit · retrying later"
        case .badRequest(let m): return "JQL error: \(m)"
        case .http(let code): return "Jira error \(code)"
        case .decoding: return "Unexpected response from Jira"
        case .notConfigured: return "Not configured · Open settings"
        }
    }

    // MARK: - Private

    private var accountErrors: Set<String> { authFailedAccounts.union(tokenErrorAccounts) }

    private func isActive(_ preset: JQLPreset) -> Bool {
        config.activePreset?.id == preset.id && config.activePreset?.accountId == preset.accountId
    }

    private func loadToken(_ accountId: String) {
        do {
            var token = try tokenStore.read(accountId: accountId)
            // Migration fallback (§11.10): until the keyed copy exists, the v1.1 item still works.
            if token == nil, accountId == JiraAccount.defaultId { token = try tokenStore.readLegacy() }
            tokens[accountId] = token
            tokenErrorAccounts.remove(accountId)
        } catch {
            tokens[accountId] = nil
            tokenErrorAccounts.insert(accountId)
        }
    }

    /// Shows the active preset's cache (its own issues and "synced" time), or nothing.
    private func loadActiveCache() {
        issues = []
        syncedAt = nil
        truncated = nil
        lastMapped = []
        guard let preset = config.activePreset, let cached = cache.load(presetId: preset.id),
              cached.accountId == preset.accountId else { return }
        issues = cached.issues
        syncedAt = cached.fetchedAt
    }

    /// Never overwrite a v1.1 config.json whose backup could not be made: keep changes in memory only.
    private func saveConfig(_ c: AppConfig) {
        if protectUnbackedLegacyFile {
            // Retry the backup (never overwriting an existing one); only then may the v1.1 file be replaced.
            let fm = FileManager.default
            if fm.fileExists(atPath: configStore.legacyBackupURL.path)
                || (try? fm.copyItem(at: configStore.url, to: configStore.legacyBackupURL)) != nil {
                protectUnbackedLegacyFile = false
            } else { return }
        }
        try? configStore.save(c)
    }

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        saveConfig(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = activeAccount?.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        // D29: effort fallback fields (start / end / logged time / issue type) of the active account
        if let effort = activeAccount?.axes.effort {
            for id in AxisMapper.timelineFieldIds(for: effort) where !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func setup() -> RenderSetup? {
        if isConfigured { return nil }
        guard let preset = config.activePreset, let account = config.account(id: preset.accountId) else {
            if config.accounts.isEmpty { return RenderSetup(message: Self.setupMessage, tab: "accounts") }
            return config.activePreset == nil
                ? RenderSetup(message: "Create a preset to see your Jira issues.", tab: "presets")
                : RenderSetup(message: "This preset's account is missing · reassign it in settings", tab: "presets")
        }
        if !hasCredentials(account) { return RenderSetup(message: Self.setupMessage, tab: "accounts") }
        return RenderSetup(message: "Map axes for \(account.name) to see this preset", tab: "axes")
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
        let status: RenderStatus
        if let banner {
            status = RenderStatus(syncedAt: syncedAt, banner: banner, truncated: truncated, bannerTab: bannerTab)
        } else if migrationFailed || protectUnbackedLegacyFile {
            status = RenderStatus(syncedAt: syncedAt, banner: Self.migrationBanner, truncated: truncated, bannerTab: "accounts")
        } else {
            status = RenderStatus(syncedAt: syncedAt, banner: axisBanner, truncated: truncated,
                                  bannerTab: axisBanner == nil ? nil : "axes")
        }
        renderState = RenderStateBuilder.build(tasks: lastMapped, previous: previous, config: config, status: status,
                                               configured: isConfigured, accountErrors: accountErrors, setup: setup())
    }
}
