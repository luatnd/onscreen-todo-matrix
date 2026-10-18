import Foundation

public struct RenderTask: Codable, Equatable, Sendable {
    public var key: String
    public var summary: String
    public var status: String
    public var priority: String?
    public var due: String?
    public var url: String
    public var value: Double
    public var effort: Double
    public var urgency: Double
    public var missing: MissingFlags
    public var derived: DerivedEffort?
    public var parent: TaskParent?
    public var score: Double
    public var rank: Int?
    public var fire: Bool
    public var changed: Bool
}

public struct RenderStatus: Codable, Equatable, Sendable {
    public var syncedAt: Date?
    public var banner: String?
    public var truncated: String?
    /// Settings tab a click on the banner opens: "accounts" | "presets" | "axes" (nil = default tab).
    public var bannerTab: String?
    public init(syncedAt: Date? = nil, banner: String? = nil, truncated: String? = nil, bannerTab: String? = nil) {
        self.syncedAt = syncedAt
        self.banner = banner
        self.truncated = truncated
        self.bannerTab = bannerTab
    }
}

public struct RenderAccount: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    /// Sign-in (401/403) or Keychain error: ⚠ next to this account's presets in the menu.
    public var error: Bool
    public init(id: String, name: String, color: String, error: Bool) {
        self.id = id
        self.name = name
        self.color = color
        self.error = error
    }
}

public struct RenderPreset: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var accountId: String
    public init(id: String, name: String, accountId: String) {
        self.id = id
        self.name = name
        self.accountId = accountId
    }
}

/// Field display names shown on the chart's axis labels, e.g. "↑ Urgency (Priority)" (§11.8.1).
/// A nil (omitted) key means the axis is not mapped.
public struct RenderAxisLabels: Codable, Equatable, Sendable {
    public var value: String?
    public var effort: String?
    public var urgency: String?
    public init(value: String? = nil, effort: String? = nil, urgency: String? = nil) {
        self.value = value
        self.effort = effort
        self.urgency = urgency
    }
    public init(axes: AxesConfig?) {
        self.init(value: axes?.value.labelName, effort: axes?.effort.labelName, urgency: axes?.urgency.labelName)
    }
}

/// Overlay shown instead of the chart while `configured` is false.
public struct RenderSetup: Codable, Equatable, Sendable {
    public var message: String
    /// Settings tab the overlay's "Open settings" button opens.
    public var tab: String
    public init(message: String, tab: String) {
        self.message = message
        self.tab = tab
    }
}

public struct RenderState: Codable, Equatable, Sendable {
    public var tasks: [RenderTask]
    public var view: ViewDefaults
    public var lastView: ViewDefaults?
    public var settings: QuickSettings
    public var status: RenderStatus
    public var accounts: [RenderAccount]
    /// In menu order (= ⌘1…⌘9 order).
    public var presets: [RenderPreset]
    public var activePresetId: String
    public var configured: Bool
    public var setup: RenderSetup?
    /// The active account's mapped field names.
    public var axisLabels: RenderAxisLabels

    public static let empty = RenderState(tasks: [], view: ViewDefaults(), lastView: nil, settings: QuickSettings(),
                                          status: RenderStatus(), accounts: [], presets: [], activePresetId: "",
                                          configured: false, setup: nil, axisLabels: RenderAxisLabels())
}

public enum RenderStateBuilder {
    public static func build(tasks: [MappedTask], previous: [String: MappedTask]?, config: AppConfig,
                             status: RenderStatus, configured: Bool,
                             accountErrors: Set<String> = [], setup: RenderSetup? = nil) -> RenderState {
        let rendered = Scorer.rank(tasks).map { s -> RenderTask in
            let t = s.task
            var changed = false
            if let prev = previous?[t.key] {
                changed = abs(prev.value - t.value) > 1e-9 || abs(prev.effort - t.effort) > 1e-9
                    || abs(prev.urgency - t.urgency) > 1e-9
            }
            return RenderTask(key: t.key, summary: t.summary, status: t.status, priority: t.priority, due: t.due,
                              url: t.url, value: t.value, effort: t.effort, urgency: t.urgency, missing: t.missing,
                              derived: t.derived, parent: t.parent, score: s.score, rank: s.rank, fire: s.fire, changed: changed)
        }
        let accounts = config.accounts.enumerated().map { i, a in
            RenderAccount(id: a.id, name: a.name, color: AccountPalette.color(at: i), error: accountErrors.contains(a.id))
        }
        return RenderState(tasks: rendered, view: config.view, lastView: config.lastView, settings: config.quick,
                           status: status, accounts: accounts,
                           presets: config.menuOrderedPresets.map { RenderPreset(id: $0.id, name: $0.name, accountId: $0.accountId) },
                           activePresetId: config.activePreset?.id ?? "", configured: configured, setup: setup,
                           axisLabels: RenderAxisLabels(axes: config.activeAccount?.axes))
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
