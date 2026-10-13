import Foundation
import Testing
@testable import OTMCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 15))!
private let site = URL(string: "https://acme.atlassian.net")!

private func norm(_ raw: JSONValue?, _ m: AxisMapping, range: ClosedRange<Double>? = nil) -> Double? {
    AxisMapper.normalize(raw, mapping: m, autoRange: range, now: now, calendar: utc)
}

@Suite struct FieldClassifierTests {
    @Test(arguments: [
        ("priority", nil as String?, FieldKind.option),
        ("option", nil, .option),
        ("status", nil, .option),
        ("string", nil, .option),
        ("number", nil, .number),
        ("date", nil, .date),
        ("datetime", nil, .date),
        ("array", "option", .option),
        ("array", "string", .option),
        ("array", "user", .unsupported),
        ("user", nil, .unsupported),
    ])
    func classifies(type: String, items: String?, expected: FieldKind) {
        let f = JiraField(id: "f", name: "F", custom: true, schemaType: type, schemaItems: items)
        #expect(FieldClassifier.kind(of: f) == expected)
    }

    @Test func noSchemaIsUnsupported() {
        #expect(FieldClassifier.kind(of: JiraField(id: "x", name: "X", custom: false, schemaType: nil)) == .unsupported)
    }
}

@Suite struct OptionMappingTests {
    let m = AxisMapping.option(fieldId: "priority", levels: ["Highest": 5, "High": 3.75, "Lowest": 0])

    @Test func mapsKnownLevels() {
        #expect(norm(.object(["name": .string("Highest")]), m) == 1)
        #expect(norm(.object(["name": .string("High")]), m) == 0.75)
        #expect(norm(.object(["name": .string("Lowest")]), m) == 0)
    }

    @Test func selectOptionUsesValueKey() {
        let sel = AxisMapping.option(fieldId: "cf", levels: ["Big": 5])
        #expect(norm(.object(["value": .string("Big")]), sel) == 1)
    }

    @Test func unknownLabelGoesToMiddle() {
        #expect(norm(.object(["name": .string("Blocker")]), m) == 0.5)
    }

    @Test func arrayUsesFirstLabel() {
        #expect(norm(.array([.string("High"), .string("Lowest")]), m) == 0.75)
    }

    @Test func nullAndAbsentAreMissing() {
        #expect(norm(nil, m) == nil)
        #expect(norm(.null, m) == nil)
        #expect(norm(.array([]), m) == nil)
    }
}

@Suite struct NumberMappingTests {
    @Test func autoRangeScalesLinearly() {
        let m = AxisMapping.number(fieldId: "sp", min: nil, max: nil, invert: false)
        #expect(norm(.number(5), m, range: 1...9) == 0.5)
        #expect(norm(.number(9), m, range: 1...9) == 1)
    }

    @Test func fixedRangeClampsAndInverts() {
        let m = AxisMapping.number(fieldId: "sp", min: 0, max: 10, invert: true)
        #expect(norm(.number(2), m) == 0.8)
        #expect(norm(.number(50), m) == 0)
    }

    @Test func degenerateRangeIsMiddle() {
        let m = AxisMapping.number(fieldId: "sp", min: nil, max: nil, invert: false)
        #expect(norm(.number(3), m, range: 3...3) == 0.5)
        #expect(norm(.number(3), m, range: nil) == 0.5)
    }

    @Test func numericStringAccepted_nonNumericMissing() {
        let m = AxisMapping.number(fieldId: "sp", min: 0, max: 10, invert: false)
        #expect(norm(.string("5"), m) == 0.5)
        #expect(norm(.string("n/a"), m) == nil)
    }
}

@Suite struct DateMappingTests {
    let m = AxisMapping.date(fieldId: "duedate", horizonDays: 14, invert: false)

    @Test func overdueAndTodayAreMax() {
        #expect(norm(.string("2026-10-01"), m) == 1)
        #expect(norm(.string("2026-10-12"), m) == 1)
    }

    @Test func linearToHorizon() {
        #expect(norm(.string("2026-10-19"), m) == 0.5)
        #expect(norm(.string("2026-10-26"), m) == 0)
        #expect(norm(.string("2027-01-01"), m) == 0)
    }

    @Test func datetimeWithTimezoneUsesCalendarDate() {
        // Review Focus #1: must not shift by a day because of the offset.
        #expect(norm(.string("2026-10-19T23:30:00.000-0700"), m) == 0.5)
    }

    @Test func invertAndGarbage() {
        let inv = AxisMapping.date(fieldId: "duedate", horizonDays: 14, invert: true)
        #expect(norm(.string("2026-10-12"), inv) == 0)
        #expect(norm(.string("soon"), m) == nil)
    }
}

@Suite struct MapIssuesTests {
    func axes() -> AxesConfig {
        var a = AxesConfig()
        a.value = AxisConfig(mapping: .number(fieldId: "cf_value", min: 0, max: 10, invert: false), missingDefault: 0.5)
        a.effort = AxisConfig(mapping: .number(fieldId: "cf_sp", min: nil, max: nil, invert: false), missingDefault: 0.3)
        a.urgency = AxisConfig(mapping: .option(fieldId: "priority", levels: DefaultMappings.priorityLevels))
        return a
    }

    @Test func mapsIssueFieldsAndUrl() {
        let issues = [
            JiraIssue(key: "SEC-5", fields: [
                "summary": .string("Rotate leaked key"), "status": .object(["name": .string("In Progress")]),
                "priority": .object(["name": .string("Highest")]), "duedate": .string("2026-10-12"),
                "cf_value": .number(10), "cf_sp": .number(1),
            ]),
            JiraIssue(key: "OPS-1", fields: [
                "summary": .string("Other"), "status": .object(["name": .string("To Do")]),
                "priority": .object(["name": .string("Low")]), "cf_value": .number(2), "cf_sp": .number(5),
            ]),
        ]
        let out = AxisMapper.map(issues: issues, axes: axes(), site: site, now: now, calendar: utc)
        #expect(out.count == 2)
        #expect(out[0] == MappedTask(key: "SEC-5", summary: "Rotate leaked key", status: "In Progress",
                                    priority: "Highest", due: "2026-10-12",
                                    url: "https://acme.atlassian.net/browse/SEC-5",
                                    value: 1, effort: 0, urgency: 1, missing: MissingFlags()))
        #expect(out[1].effort == 1)
        #expect(out[1].urgency == 0.25)
    }

    @Test func nullCustomFieldIsHollowAtDefault() {
        // Review Focus #2
        let issue = JiraIssue(key: "A-1", fields: ["summary": .string("s"), "cf_value": .null,
                                                    "cf_sp": .number(2), "priority": .object(["name": .string("High")])])
        let t = AxisMapper.map(issues: [issue], axes: axes(), site: site, now: now, calendar: utc)[0]
        #expect(t.value == 0.5)
        #expect(t.missing.value)
        #expect(!t.missing.effort)
    }

    @Test func unmappedAxisUsesDefaultAndMissing() {
        var a = axes()
        a.effort.mapping = nil
        let issue = JiraIssue(key: "A-1", fields: ["summary": .string("s")])
        let t = AxisMapper.map(issues: [issue], axes: a, site: site, now: now, calendar: utc)[0]
        #expect(t.effort == 0.3)
        #expect(t.missing.effort)
        #expect(t.status == "")
    }

    @Test func summaryFallsBackToKey() {
        let t = AxisMapper.map(issues: [JiraIssue(key: "K-9", fields: [:])], axes: axes(), site: site, now: now, calendar: utc)[0]
        #expect(t.summary == "K-9")
    }

    @Test func observedAndUnmappedLabels() {
        let issues = ["High", "Blocker", "High", "Trivial"].enumerated().map {
            JiraIssue(key: "K-\($0.offset)", fields: ["priority": .object(["name": .string($0.element)])])
        }
        #expect(AxisMapper.observedLabels(fieldId: "priority", issues: issues) == ["Blocker", "High", "Trivial"])
        let m = AxisMapping.option(fieldId: "priority", levels: ["High": 4])
        #expect(AxisMapper.unmappedLabels(issues: issues, mapping: m) == ["Blocker", "Trivial"])
    }
}

@Suite struct DefaultMappingsTests {
    let fields = [
        JiraField(id: "priority", name: "Priority", custom: false, schemaType: "priority"),
        JiraField(id: "customfield_10016", name: "Story point estimate", custom: true, schemaType: "number"),
        JiraField(id: "timeoriginalestimate", name: "Original estimate", custom: false, schemaType: "number"),
        JiraField(id: "duedate", name: "Due date", custom: false, schemaType: "date"),
    ]

    @Test func suggestsPriorityForUrgencyAndStoryPointsForEffort() {
        let a = DefaultMappings.suggest(fields: fields, current: AxesConfig())
        #expect(a.urgency.mapping == .option(fieldId: "priority", levels: DefaultMappings.priorityLevels))
        #expect(a.effort.mapping == .number(fieldId: "customfield_10016", min: nil, max: nil, invert: false))
        #expect(a.value.mapping == nil)
    }

    @Test func fallsBackToOriginalEstimate() {
        let a = DefaultMappings.suggest(fields: fields.filter { $0.id != "customfield_10016" }, current: AxesConfig())
        #expect(a.effort.mapping == .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false))
    }

    @Test func neverOverwritesExistingMappings() {
        var cur = AxesConfig()
        cur.urgency.mapping = .date(fieldId: "duedate", horizonDays: 7, invert: false)
        #expect(DefaultMappings.suggest(fields: fields, current: cur).urgency.mapping == cur.urgency.mapping)
    }

    @Test func suggestSavesFieldDisplayNames() {
        var cur = AxesConfig()
        cur.value.mapping = .option(fieldId: "customfield_10110", levels: [:])     // not in the field list
        let a = DefaultMappings.suggest(fields: fields, current: cur)
        #expect(a.urgency.fieldName == "Priority")
        #expect(a.effort.fieldName == "Story point estimate")
        #expect(a.value.fieldName == nil)
        #expect(a.value.labelName == "customfield_10110")                      // falls back to the field id
    }

    @Test func withFieldNamesRefreshesKnownFieldsOnly() {
        var cur = AxesConfig()
        cur.urgency = AxisConfig(mapping: .date(fieldId: "duedate", horizonDays: 7, invert: false), fieldName: "Old name")
        cur.value = AxisConfig(mapping: .number(fieldId: "gone", min: nil, max: nil, invert: false), fieldName: "Kept")
        let a = DefaultMappings.withFieldNames(cur, fields: fields)
        #expect(a.urgency.fieldName == "Due date")
        #expect(a.value.fieldName == "Kept")
        #expect(a.effort.labelName == nil)
    }

    @Test func axisConfigWithoutFieldNameStillDecodes() throws {
        let c = try JSONDecoder().decode(AxisConfig.self, from: Data(#"{"missingDefault":0}"#.utf8))
        #expect(c == AxisConfig(mapping: nil, missingDefault: 0))
    }

    @Test func priorityLevelsMatchSpec() {
        #expect(DefaultMappings.priorityLevels == ["Highest": 5, "High": 3.75, "Medium": 2.5, "Low": 1.25, "Lowest": 0])
    }

    @Test func mappingForFieldKind() {
        #expect(DefaultMappings.mapping(for: fields[3]) == .date(fieldId: "duedate", horizonDays: 14, invert: false))
        #expect(DefaultMappings.mapping(for: JiraField(id: "u", name: "U", custom: false, schemaType: "user")) == nil)
    }
}
