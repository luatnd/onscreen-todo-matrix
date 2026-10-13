import Foundation

public struct JiraIssue: Codable, Equatable, Sendable {
    public var key: String
    public var fields: [String: JSONValue]
    public init(key: String, fields: [String: JSONValue]) {
        self.key = key
        self.fields = fields
    }
}

public struct JiraUser: Codable, Equatable, Sendable {
    public var displayName: String
    public var accountId: String
    public init(displayName: String, accountId: String) {
        self.displayName = displayName
        self.accountId = accountId
    }
}

public struct JiraField: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var custom: Bool
    public var schemaType: String?
    public var schemaItems: String?

    public init(id: String, name: String, custom: Bool, schemaType: String?, schemaItems: String? = nil) {
        self.id = id
        self.name = name
        self.custom = custom
        self.schemaType = schemaType
        self.schemaItems = schemaItems
    }

    private enum CodingKeys: String, CodingKey { case id, name, custom, schema }
    private struct Schema: Codable { var type: String?; var items: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? false
        let schema = try c.decodeIfPresent(Schema.self, forKey: .schema)
        schemaType = schema?.type
        schemaItems = schema?.items
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(custom, forKey: .custom)
        try c.encode(Schema(type: schemaType, items: schemaItems), forKey: .schema)
    }
}

public enum Axis: String, Codable, CaseIterable, Sendable {
    case value, effort, urgency
}

public enum AxisMapping: Codable, Equatable, Sendable {
    /// levels: option label → level 0…5
    case option(fieldId: String, levels: [String: Double])
    /// min/max nil = auto range from current issues
    case number(fieldId: String, min: Double?, max: Double?, invert: Bool)
    case date(fieldId: String, horizonDays: Int, invert: Bool)

    public var fieldId: String {
        switch self {
        case .option(let id, _), .number(let id, _, _, _), .date(let id, _, _): return id
        }
    }
}

/// How derived effort is displayed (D29): hours or days. 1 day = 8 h (Jira's default).
public enum EffortUnit: String, Codable, CaseIterable, Sendable {
    case hours, days
}

/// Effort fallback (D29), used only when Effort is mapped to Original estimate and the issue has none:
/// logged time first, then the working days between a start field and an end field.
/// Absent in older configs (decodes as nil = off).
public struct TimelineFallback: Codable, Equatable, Sendable {
    public var startFieldId: String
    public var endFieldId: String
    public var unit: EffortUnit
    public init(startFieldId: String, endFieldId: String = "duedate", unit: EffortUnit = .hours) {
        self.startFieldId = startFieldId
        self.endFieldId = endFieldId
        self.unit = unit
    }
}

/// Where an issue's effort came from when it is not its own Original estimate. `unit` is "h" or "d".
public struct DerivedEffort: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case timeline, logged }
    public var kind: Kind
    public var amount: Double
    public var unit: String
    public var from: String?
    public var to: String?
    public var clamped: Bool
    public init(kind: Kind, amount: Double, unit: String, from: String? = nil, to: String? = nil, clamped: Bool = false) {
        self.kind = kind
        self.amount = amount
        self.unit = unit
        self.from = from
        self.to = to
        self.clamped = clamped
    }
}

public struct AxisConfig: Codable, Equatable, Sendable {
    public var mapping: AxisMapping?
    public var missingDefault: Double
    /// Display name of the mapped Jira field (JiraField.name), saved with the mapping so the chart's axis
    /// label works offline (§11.8.1). nil → the label falls back to the field id. Optional: older files decode.
    public var fieldName: String?
    /// Effort fallback (D29); only meaningful on the Effort axis. nil = off; absent in older files.
    public var timeline: TimelineFallback?
    public init(mapping: AxisMapping? = nil, missingDefault: Double = 0.5, fieldName: String? = nil,
                timeline: TimelineFallback? = nil) {
        self.mapping = mapping
        self.missingDefault = missingDefault
        self.fieldName = fieldName
        self.timeline = timeline
    }

    /// Axis-label name: the saved field name, else the field id; nil when unmapped.
    public var labelName: String? { mapping.map { fieldName ?? $0.fieldId } }
}

public struct AxesConfig: Codable, Equatable, Sendable {
    public var value = AxisConfig()
    public var effort = AxisConfig()
    public var urgency = AxisConfig()
    public init() {}

    public subscript(axis: Axis) -> AxisConfig {
        get {
            switch axis {
            case .value: return value
            case .effort: return effort
            case .urgency: return urgency
            }
        }
        set {
            switch axis {
            case .value: value = newValue
            case .effort: effort = newValue
            case .urgency: urgency = newValue
            }
        }
    }

    public var isComplete: Bool { Axis.allCases.allSatisfy { self[$0].mapping != nil } }
}

public struct MissingFlags: Codable, Equatable, Sendable {
    public var value: Bool
    public var effort: Bool
    public var urgency: Bool
    public init(value: Bool = false, effort: Bool = false, urgency: Bool = false) {
        self.value = value
        self.effort = effort
        self.urgency = urgency
    }
    public subscript(axis: Axis) -> Bool {
        get { axis == .value ? value : axis == .effort ? effort : urgency }
        set {
            switch axis {
            case .value: value = newValue
            case .effort: effort = newValue
            case .urgency: urgency = newValue
            }
        }
    }
}

public struct MappedTask: Codable, Equatable, Sendable {
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

    public init(key: String, summary: String, status: String, priority: String?, due: String?, url: String,
                value: Double, effort: Double, urgency: Double, missing: MissingFlags = MissingFlags(),
                derived: DerivedEffort? = nil) {
        self.key = key
        self.summary = summary
        self.status = status
        self.priority = priority
        self.due = due
        self.url = url
        self.value = value
        self.effort = effort
        self.urgency = urgency
        self.missing = missing
        self.derived = derived
    }
}
