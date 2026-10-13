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
        case .number(let n): return Int(exactly: n).map(String.init) ?? String(n)
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

    // MARK: Effort fallback (D29)

    /// 1 working day = 8 h (Jira's default; the site's own hours/day cannot be read through the read-only API).
    static let workdaySeconds: Double = 8 * 3600

    /// Mon–Fri days between two dates, both ends included, at least 1; nil when `to` is before `from`.
    public static func workingDays(from: Date, to: Date, calendar: Calendar) -> Int? {
        let a = calendar.startOfDay(for: from), b = calendar.startOfDay(for: to)
        guard b >= a, let span = calendar.dateComponents([.day], from: a, to: b).day else { return nil }
        let total = span + 1
        var n = (total / 7) * 5
        // the remaining 0…6 days start on the same weekday as `a`
        for i in 0..<(total % 7) {
            guard let d = calendar.date(byAdding: .day, value: i, to: a) else { break }
            let wd = calendar.component(.weekday, from: d)   // 1 = Sunday … 7 = Saturday
            if wd != 1 && wd != 7 { n += 1 }
        }
        return max(1, n)
    }

    /// The fallback config when it applies: Effort is mapped to Original estimate and the toggle is on.
    public static func timelineFallback(for effort: AxisConfig) -> TimelineFallback? {
        guard let tl = effort.timeline, case .number(let id, _, _, _)? = effort.mapping, id == "timeoriginalestimate" else { return nil }
        return tl
    }

    /// Extra Jira fields to request for the fallback.
    public static func timelineFieldIds(for effort: AxisConfig) -> [String] {
        guard let tl = timelineFallback(for: effort) else { return [] }
        return [tl.startFieldId, tl.endFieldId, "timespent", "timeestimate", "issuetype"].filter { !$0.isEmpty }
    }

    struct DerivedSeconds {
        var seconds: Double
        var kind: DerivedEffort.Kind
        var from: String?
        var to: String?
    }

    /// Logged time (spent + remaining) when > 0, else the Start → End window in working days × 8 h.
    /// Epics are skipped for the window (it covers their children). nil = no usable signal.
    static func derivedSeconds(for issue: JiraIssue, timeline: TimelineFallback, calendar: Calendar) -> DerivedSeconds? {
        let logged = (issue.fields["timespent"]?.numberValue ?? 0) + (issue.fields["timeestimate"]?.numberValue ?? 0)
        if logged > 0 { return DerivedSeconds(seconds: logged, kind: .logged, from: nil, to: nil) }
        if optionLabel(issue.fields["issuetype"]) == "Epic" { return nil }
        guard !timeline.startFieldId.isEmpty,
              let start = dateValue(issue.fields[timeline.startFieldId], calendar: calendar),
              let end = dateValue(issue.fields[timeline.endFieldId], calendar: calendar),
              let days = workingDays(from: start, to: end, calendar: calendar) else { return nil }
        return DerivedSeconds(seconds: Double(days) * workdaySeconds, kind: .timeline,
                              from: issue.fields[timeline.startFieldId]?.stringValue.map { String($0.prefix(10)) },
                              to: issue.fields[timeline.endFieldId]?.stringValue.map { String($0.prefix(10)) })
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
        // Effort fallback (D29): issues with no Original estimate but logged time or a start/end window.
        var derived: [String: DerivedSeconds] = [:]
        if let tl = timelineFallback(for: axes.effort), case .number(let id, _, _, _)? = axes.effort.mapping {
            for issue in issues where issue.fields[id]?.numberValue == nil {
                if let d = derivedSeconds(for: issue, timeline: tl, calendar: calendar) { derived[issue.key] = d }
            }
            // The range comes from real estimates only; with fewer than 2 distinct ones derived values join it.
            let real = ranges[.effort]
            if !derived.isEmpty, real == nil || real!.lowerBound == real!.upperBound {
                let all = issues.compactMap { $0.fields[id]?.numberValue } + derived.values.map(\.seconds)
                if let lo = all.min(), let hi = all.max() { ranges[.effort] = lo...hi }
            }
        }
        return issues.map { issue in
            var values: [Axis: Double] = [:]
            var missing = MissingFlags()
            var derivedEffort: DerivedEffort?
            for axis in Axis.allCases {
                let cfg = axes[axis]
                var n = cfg.mapping.flatMap {
                    normalize(issue.fields[$0.fieldId], mapping: $0, autoRange: ranges[axis], now: now, calendar: calendar)
                }
                if n == nil, axis == .effort, let d = derived[issue.key], let mapping = cfg.mapping, let tl = cfg.timeline {
                    n = normalize(.number(d.seconds), mapping: mapping, autoRange: ranges[axis], now: now, calendar: calendar)
                    var top = ranges[axis]?.upperBound
                    if case .number(_, _, let fixedMax?, _) = mapping { top = fixedMax }
                    let days = tl.unit == .days
                    derivedEffort = DerivedEffort(kind: d.kind, amount: days ? d.seconds / workdaySeconds : d.seconds / 3600,
                                                  unit: days ? "d" : "h", from: d.from, to: d.to,
                                                  clamped: top.map { d.seconds > $0 } ?? false)
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
                missing: missing, derived: derivedEffort
            )
        }
    }
}

public enum DefaultMappings {
    public static let priorityLevels: [String: Double] = ["Highest": 5, "High": 3.75, "Medium": 2.5, "Low": 1.25, "Lowest": 0]

    /// Date fields offered as Start / End for the effort timeline fallback (input order).
    public static func timelineDateFields(_ fields: [JiraField]) -> [JiraField] {
        fields.filter { FieldClassifier.kind(of: $0) == .date }
    }

    /// The site's custom "Start date" field, if any (exact name; "Target start" etc. are left to the user).
    public static func guessStartField(_ fields: [JiraField]) -> JiraField? {
        fields.first { $0.custom && FieldClassifier.kind(of: $0) == .date && $0.name.lowercased() == "start date" }
    }

    public static func mapping(for field: JiraField) -> AxisMapping? {
        switch FieldClassifier.kind(of: field) {
        case .option: return .option(fieldId: field.id, levels: field.id == "priority" ? priorityLevels : [:])
        case .number: return .number(fieldId: field.id, min: nil, max: nil, invert: false)
        case .date: return .date(fieldId: field.id, horizonDays: 14, invert: false)
        case .unsupported: return nil
        }
    }

    /// Saves each mapped axis' field display name from the loaded field list (unknown ids keep their name).
    public static func withFieldNames(_ axes: AxesConfig, fields: [JiraField]) -> AxesConfig {
        var a = axes
        for axis in Axis.allCases {
            guard let id = a[axis].mapping?.fieldId, let field = fields.first(where: { $0.id == id }) else { continue }
            a[axis].fieldName = field.name
        }
        return a
    }

    /// Pre-fills empty axes: urgency ← Priority, effort ← Story Points / Story point estimate / Original estimate;
    /// then refreshes the saved field names of all mapped axes.
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
                // D29: fresh setups get the timeline fallback when the site has a "Start date" field.
                if let start = guessStartField(fields) { a.effort.timeline = TimelineFallback(startFieldId: start.id) }
            }
        }
        return withFieldNames(a, fields: fields)
    }
}
