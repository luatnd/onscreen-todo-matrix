import Foundation

public enum FieldKind: Equatable, Sendable {
    case option, number, date, unsupported
}

public enum FieldClassifier {
    public static func kind(of field: JiraField) -> FieldKind {
        switch field.schemaType {
        case "priority", "option", "status", "issuetype", "resolution", "string": return .option
        case "number": return .number
        case "date", "datetime": return .date
        case "array":
            switch field.schemaItems {
            case "option", "string", "component", "version": return .option
            default: return .unsupported
            }
        default: return .unsupported
        }
    }
}

public enum AxisMapper {
    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    /// Display label of an option-like value: name → value → string; arrays use the first label.
    public static func optionLabel(_ raw: JSONValue?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case .string(let s): return s.isEmpty ? nil : s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .object(let o): return o["name"]?.stringValue ?? o["value"]?.stringValue
        case .array(let a): return a.lazy.compactMap { optionLabel($0) }.first
        case .null: return nil
        }
    }

    /// Calendar date from "yyyy-MM-dd" or an ISO datetime (first 10 chars; time zone ignored on purpose).
    public static func dateValue(_ raw: JSONValue?, calendar: Calendar) -> Date? {
        guard let s = raw?.stringValue, s.count >= 10 else { return nil }
        let parts = s.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    public static func autoRange(fieldId: String, issues: [JiraIssue]) -> ClosedRange<Double>? {
        let values = issues.compactMap { $0.fields[fieldId]?.numberValue }
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return lo...hi
    }

    /// 0…1, or nil when the issue has no usable value.
    public static func normalize(_ raw: JSONValue?, mapping: AxisMapping, autoRange: ClosedRange<Double>?,
                                 now: Date, calendar: Calendar) -> Double? {
        switch mapping {
        case .option(_, let levels):
            guard let label = optionLabel(raw) else { return nil }
            return clamp01((levels[label] ?? 2.5) / 5)
        case .number(_, let fixedMin, let fixedMax, let invert):
            guard let n = raw?.numberValue else { return nil }
            let lo = fixedMin ?? autoRange?.lowerBound ?? n
            let hi = fixedMax ?? autoRange?.upperBound ?? n
            let t = hi > lo ? clamp01((n - lo) / (hi - lo)) : 0.5
            return invert ? 1 - t : t
        case .date(_, let horizon, let invert):
            guard let date = dateValue(raw, calendar: calendar) else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: date)).day ?? 0
            let t: Double = days <= 0 ? 1 : (horizon <= 0 ? 0 : clamp01(1 - Double(days) / Double(horizon)))
            return invert ? 1 - t : t
        }
    }

    public static func observedLabels(fieldId: String, issues: [JiraIssue]) -> [String] {
        Array(Set(issues.compactMap { optionLabel($0.fields[fieldId]) })).sorted()
    }

    public static func unmappedLabels(issues: [JiraIssue], mapping: AxisMapping) -> [String] {
        guard case .option(let fieldId, let levels) = mapping else { return [] }
        return observedLabels(fieldId: fieldId, issues: issues).filter { levels[$0] == nil }
    }

    public static func map(issues: [JiraIssue], axes: AxesConfig, site: URL, now: Date,
                           calendar: Calendar = .current) -> [MappedTask] {
        var ranges: [Axis: ClosedRange<Double>] = [:]
        for axis in Axis.allCases {
            if case .number(let id, _, _, _)? = axes[axis].mapping { ranges[axis] = autoRange(fieldId: id, issues: issues) }
        }
        return issues.map { issue in
            var values: [Axis: Double] = [:]
            var missing = MissingFlags()
            for axis in Axis.allCases {
                let cfg = axes[axis]
                let n = cfg.mapping.flatMap {
                    normalize(issue.fields[$0.fieldId], mapping: $0, autoRange: ranges[axis], now: now, calendar: calendar)
                }
                values[axis] = n ?? cfg.missingDefault
                missing[axis] = n == nil
            }
            return MappedTask(
                key: issue.key,
                summary: issue.fields["summary"]?.stringValue ?? issue.key,
                status: optionLabel(issue.fields["status"]) ?? "",
                priority: optionLabel(issue.fields["priority"]),
                due: issue.fields["duedate"]?.stringValue,
                url: site.appendingPathComponent("browse").appendingPathComponent(issue.key).absoluteString,
                value: values[.value]!, effort: values[.effort]!, urgency: values[.urgency]!,
                missing: missing
            )
        }
    }
}

public enum DefaultMappings {
    public static let priorityLevels: [String: Double] = ["Highest": 5, "High": 3.75, "Medium": 2.5, "Low": 1.25, "Lowest": 0]

    public static func mapping(for field: JiraField) -> AxisMapping? {
        switch FieldClassifier.kind(of: field) {
        case .option: return .option(fieldId: field.id, levels: field.id == "priority" ? priorityLevels : [:])
        case .number: return .number(fieldId: field.id, min: nil, max: nil, invert: false)
        case .date: return .date(fieldId: field.id, horizonDays: 14, invert: false)
        case .unsupported: return nil
        }
    }

    /// Pre-fills empty axes: urgency ← Priority, effort ← Story Points / Story point estimate / Original estimate.
    public static func suggest(fields: [JiraField], current: AxesConfig) -> AxesConfig {
        var a = current
        if a.urgency.mapping == nil, fields.contains(where: { $0.id == "priority" }) {
            a.urgency.mapping = .option(fieldId: "priority", levels: priorityLevels)
        }
        if a.effort.mapping == nil {
            let names = ["story points", "story point estimate"]
            if let sp = fields.first(where: { names.contains($0.name.lowercased()) && FieldClassifier.kind(of: $0) == .number }) {
                a.effort.mapping = .number(fieldId: sp.id, min: nil, max: nil, invert: false)
            } else if fields.contains(where: { $0.id == "timeoriginalestimate" }) {
                a.effort.mapping = .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false)
            }
        }
        return a
    }
}
