import Foundation

/// One Jira Cloud account (site + email; the API token lives in Keychain, keyed by `id`).
public struct JiraAccount: Codable, Equatable, Identifiable, Sendable {
    /// Id of the account created by the v1.1 → v1.2 migration (and of the first account added on a fresh install).
    public static let defaultId = "default"

    public var id: String
    public var name: String
    public var site: String
    public var email: String
    /// Axis mappings are per account: custom field ids differ per site.
    public var axes: AxesConfig

    public init(id: String, name: String, site: String = "", email: String = "", axes: AxesConfig = AxesConfig()) {
        self.id = id
        self.name = name
        self.site = site
        self.email = email
        self.axes = axes
    }

    public var siteURL: URL? { AppConfig.normalizeSite(site) }

    private enum CodingKeys: String, CodingKey { case id, name, site, email, axes }

    /// Tolerant: only `id` is required, so a partially written file never counts as corrupt.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        site = try c.decodeIfPresent(String.self, forKey: .site) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        axes = try c.decodeIfPresent(AxesConfig.self, forKey: .axes) ?? AxesConfig()
    }
}

/// Stable account colours, by account order (§11.6).
public enum AccountPalette {
    public static let colors = ["#3b82f6", "#f59e0b", "#10b981", "#ec4899", "#8b5cf6", "#06b6d4"]
    public static func color(at index: Int) -> String { colors[((index % colors.count) + colors.count) % colors.count] }
}

public struct JQLPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var jql: String
    /// The account this preset queries. "" = not assigned (legacy file before migration).
    public var accountId: String

    public init(id: String, name: String, jql: String, accountId: String = JiraAccount.defaultId) {
        self.id = id
        self.name = name
        self.jql = jql
        self.accountId = accountId
    }

    public static let myOpenWork = JQLPreset(
        id: "my-open-work",
        name: "My open work",
        jql: "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC"
    )

    private enum CodingKeys: String, CodingKey { case id, name, jql, accountId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        jql = try c.decodeIfPresent(String.self, forKey: .jql) ?? ""
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId) ?? ""
    }
}

/// JQL template chips of the New preset sheet (§11.7).
public struct JQLTemplate: Equatable, Sendable {
    public let title: String
    public let jql: String

    public static let all: [JQLTemplate] = [
        JQLTemplate(title: "My open work",
                    jql: "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC"),
        JQLTemplate(title: "Due this week",
                    jql: "assignee = currentUser() AND due <= endOfWeek() AND statusCategory != Done"),
        JQLTemplate(title: "Reported by me",
                    jql: "reporter = currentUser() AND statusCategory != Done"),
        JQLTemplate(title: "Unassigned in project…",
                    jql: "project = <KEY> AND assignee is EMPTY AND statusCategory != Done"),
    ]
}

public struct ViewDefaults: Codable, Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var zoom: Double
    public init(yaw: Double = -179.7, pitch: Double = 33.9, zoom: Double = 1) {
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
    }
}

public struct QuickSettings: Codable, Equatable, Sendable {
    public var labelMode = "smart"        // smart | all | key | off
    public var stemStyle = "dotted"       // solid | dotted | dashed | off
    public var stemOpacity: Double = 30   // 5…80
    public var colorMode = "rgb"          // rgb | u
    public var grid = true
    public var zoneNames = true
    public var rotation = "limited"       // limited | free
    public var panelOpacity: Double = 100 // 40…100
    public var alwaysOnTop = false
    public var refreshMinutes = 5         // 0 (off) | 1 | 5 | 15
    public init() {}

    /// Returns a copy with one setting changed; invalid keys/values are ignored.
    public func applying(key: String, value: JSONValue) -> QuickSettings {
        var q = self
        func pick(_ allowed: [String]) -> String? { value.stringValue.flatMap { allowed.contains($0) ? $0 : nil } }
        switch key {
        case "labelMode": if let s = pick(["smart", "all", "key", "off"]) { q.labelMode = s }
        case "stemStyle": if let s = pick(["solid", "dotted", "dashed", "off"]) { q.stemStyle = s }
        case "stemOpacity": if let n = value.numberValue { q.stemOpacity = min(80, max(5, n)) }
        case "colorMode": if let s = pick(["rgb", "u"]) { q.colorMode = s }
        case "grid": if let b = value.boolValue { q.grid = b }
        case "zoneNames": if let b = value.boolValue { q.zoneNames = b }
        case "rotation": if let s = pick(["limited", "free"]) { q.rotation = s }
        case "panelOpacity": if let n = value.numberValue { q.panelOpacity = min(100, max(40, n)) }
        case "alwaysOnTop": if let b = value.boolValue { q.alwaysOnTop = b }
        case "refreshMinutes":
            if let n = value.numberValue, let m = Int(exactly: n), [0, 1, 5, 15].contains(m) { q.refreshMinutes = m }
        default: break
        }
        return q
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var accounts: [JiraAccount] = []
    public var presets: [JQLPreset] = [JQLPreset.myOpenWork]
    /// Last chosen preset; restored on launch.
    public var activePresetId = JQLPreset.myOpenWork.id
    public var view = ViewDefaults()
    /// Last camera view, restored on launch.
    public var lastView: ViewDefaults? = nil
    public var quick = QuickSettings()
    public var launchAtLogin = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case accounts, presets, activePresetId, view, lastView, quick, launchAtLogin
    }

    /// Tolerant: every key is optional so a partially written (or older) file never counts as corrupt.
    /// Legacy v1.1 keys (`site`, `email`, `axes`) are read separately by `ConfigMigration`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        accounts = try c.decodeIfPresent([JiraAccount].self, forKey: .accounts) ?? d.accounts
        presets = try c.decodeIfPresent([JQLPreset].self, forKey: .presets) ?? d.presets
        activePresetId = try c.decodeIfPresent(String.self, forKey: .activePresetId) ?? d.activePresetId
        view = try c.decodeIfPresent(ViewDefaults.self, forKey: .view) ?? d.view
        lastView = try c.decodeIfPresent(ViewDefaults.self, forKey: .lastView)
        quick = try c.decodeIfPresent(QuickSettings.self, forKey: .quick) ?? d.quick
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    public var activePreset: JQLPreset? {
        presets.first { $0.id == activePresetId } ?? presets.first
    }

    public func account(id: String?) -> JiraAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    /// The active account is always the account of the active preset (D22).
    public var activeAccount: JiraAccount? { account(id: activePreset?.accountId) }

    /// Menu order (= ⌘1…⌘9 order): grouped by account order, presets whose account is missing last.
    public var menuOrderedPresets: [JQLPreset] {
        let known = Set(accounts.map(\.id))
        return accounts.flatMap { a in presets.filter { $0.accountId == a.id } }
            + presets.filter { !known.contains($0.accountId) }
    }

    public mutating func upsertAccount(_ account: JiraAccount) {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i] = account } else { accounts.append(account) }
    }

    /// Reorders the presets of one account (drag in the Presets tab); other presets keep their slots.
    /// `source`/`destination` are offsets within that account's presets, as SwiftUI `onMove` reports them.
    public func movingPresets(accountId: String, fromOffsets source: IndexSet, toOffset destination: Int) -> [JQLPreset] {
        let group = presets.filter { $0.accountId == accountId }
        let valid = source.filter { $0 < group.count }
        guard !valid.isEmpty, (0...group.count).contains(destination) else { return presets }
        let moving = valid.map { group[$0] }
        var rest = group.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - valid.filter { $0 < destination }.count)
        var it = rest.makeIterator()
        return presets.map { $0.accountId == accountId ? it.next()! : $0 }
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Account names must be non-empty and unique (case-insensitive).
    public func isAccountNameValid(_ name: String, excludingId: String? = nil) -> Bool {
        let k = Self.key(name)
        return !k.isEmpty && !accounts.contains { $0.id != excludingId && Self.key($0.name) == k }
    }

    /// Preset names must be non-empty and unique within their account (case-insensitive).
    public func isPresetNameValid(_ name: String, accountId: String, excludingId: String? = nil) -> Bool {
        let k = Self.key(name)
        return !k.isEmpty && !presets.contains { $0.accountId == accountId && $0.id != excludingId && Self.key($0.name) == k }
    }

    /// Accepts "acme.atlassian.net", "https://acme.atlassian.net/…"; returns "https://host".
    public static func normalizeSite(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "https://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        c.scheme = "https"
        c.path = ""
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        return c.url
    }
}
