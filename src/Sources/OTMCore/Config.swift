import Foundation

public struct JQLPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var jql: String
    public init(id: String, name: String, jql: String) {
        self.id = id
        self.name = name
        self.jql = jql
    }
    public static let myOpenWork = JQLPreset(
        id: "my-open-work",
        name: "My open work",
        jql: "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC"
    )
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
    public var site = ""
    public var email = ""
    public var presets: [JQLPreset] = [JQLPreset.myOpenWork]
    public var activePresetId = JQLPreset.myOpenWork.id
    public var axes = AxesConfig()
    public var view = ViewDefaults()
    /// Last camera view, restored on launch. Optional so config files written before this key still decode.
    public var lastView: ViewDefaults? = nil
    public var quick = QuickSettings()
    public var launchAtLogin = false
    public init() {}

    public var activePreset: JQLPreset {
        presets.first { $0.id == activePresetId } ?? presets.first ?? JQLPreset.myOpenWork
    }

    public var siteURL: URL? { Self.normalizeSite(site) }

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
