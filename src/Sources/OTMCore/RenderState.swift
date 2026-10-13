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
    public var score: Double
    public var rank: Int?
    public var fire: Bool
    public var changed: Bool
}

public struct RenderStatus: Codable, Equatable, Sendable {
    public var syncedAt: Date?
    public var banner: String?
    public var truncated: String?
    public init(syncedAt: Date? = nil, banner: String? = nil, truncated: String? = nil) {
        self.syncedAt = syncedAt
        self.banner = banner
        self.truncated = truncated
    }
}

public struct RenderPreset: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
}

public struct RenderState: Codable, Equatable, Sendable {
    public var tasks: [RenderTask]
    public var view: ViewDefaults
    public var lastView: ViewDefaults?
    public var settings: QuickSettings
    public var status: RenderStatus
    public var presets: [RenderPreset]
    public var activePresetId: String
    public var configured: Bool

    public static let empty = RenderState(tasks: [], view: ViewDefaults(), lastView: nil, settings: QuickSettings(),
                                          status: RenderStatus(), presets: [], activePresetId: "", configured: false)
}

public enum RenderStateBuilder {
    public static func build(tasks: [MappedTask], previous: [String: MappedTask]?, config: AppConfig,
                             status: RenderStatus, configured: Bool) -> RenderState {
        let rendered = Scorer.rank(tasks).map { s -> RenderTask in
            let t = s.task
            var changed = false
            if let prev = previous?[t.key] {
                changed = abs(prev.value - t.value) > 1e-9 || abs(prev.effort - t.effort) > 1e-9
                    || abs(prev.urgency - t.urgency) > 1e-9
            }
            return RenderTask(key: t.key, summary: t.summary, status: t.status, priority: t.priority, due: t.due,
                              url: t.url, value: t.value, effort: t.effort, urgency: t.urgency, missing: t.missing,
                              score: s.score, rank: s.rank, fire: s.fire, changed: changed)
        }
        return RenderState(tasks: rendered, view: config.view, lastView: config.lastView, settings: config.quick, status: status,
                           presets: config.presets.map { RenderPreset(id: $0.id, name: $0.name) },
                           activePresetId: config.activePreset.id, configured: configured)
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
