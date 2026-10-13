import Foundation
import Testing
@testable import OTMCore

@Suite struct JSONValueTests {
    @Test func decodesMixedJiraFields() throws {
        let json = #"{"a":"x","b":3.5,"c":true,"d":null,"e":[1,"y"],"f":{"name":"High"}}"#
        let v = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
        #expect(v["a"] == .string("x"))
        #expect(v["b"] == .number(3.5))
        #expect(v["c"] == .bool(true))
        #expect(v["d"] == .null)
        #expect(v["e"] == .array([.number(1), .string("y")]))
        #expect(v["f"]?["name"]?.stringValue == "High")
    }

    @Test func numberValueParsesNumericStrings() {
        #expect(JSONValue.string("8").numberValue == 8)
        #expect(JSONValue.string("abc").numberValue == nil)
        #expect(JSONValue.string("nan").numberValue == nil)
        #expect(JSONValue.string("inf").numberValue == nil)
        #expect(JSONValue.number(.infinity).numberValue == nil)
        #expect(JSONValue.number(.nan).numberValue == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let v: JSONValue = .object(["k": .array([.bool(false), .null, .number(2)])])
        let data = try JSONEncoder().encode(v)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == v)
    }

    @Test func initFromAnyDistinguishesBoolFromNumber() {
        #expect(JSONValue(any: NSNumber(value: true)) == .bool(true))
        #expect(JSONValue(any: NSNumber(value: 30)) == .number(30))
        #expect(JSONValue(any: "dotted") == .string("dotted"))
        #expect(JSONValue(any: nil) == .null)
        #expect(JSONValue(any: ["a": 1]) == .object(["a": .number(1)]))
    }
}

@Suite struct ModelTests {
    @Test func jiraFieldDecodesSchema() throws {
        let json = #"{"id":"customfield_10016","name":"Story Points","custom":true,"schema":{"type":"number","custom":"x"}}"#
        let f = try JSONDecoder().decode(JiraField.self, from: Data(json.utf8))
        #expect(f.id == "customfield_10016")
        #expect(f.schemaType == "number")
        #expect(f.custom)
    }

    @Test func jiraFieldWithoutSchemaDecodes() throws {
        let f = try JSONDecoder().decode(JiraField.self, from: Data(#"{"id":"issuekey","name":"Key","custom":false}"#.utf8))
        #expect(f.schemaType == nil)
    }

    @Test func axisMappingRoundTripsAndExposesFieldId() throws {
        let m = AxisMapping.date(fieldId: "duedate", horizonDays: 14, invert: false)
        let back = try JSONDecoder().decode(AxisMapping.self, from: JSONEncoder().encode(m))
        #expect(back == m)
        #expect(back.fieldId == "duedate")
    }

    @Test func axesConfigCompleteOnlyWhenAllMapped() {
        var a = AxesConfig()
        #expect(!a.isComplete)
        a[.value].mapping = .number(fieldId: "v", min: nil, max: nil, invert: false)
        a[.effort].mapping = .number(fieldId: "e", min: nil, max: nil, invert: false)
        a[.urgency].mapping = .option(fieldId: "priority", levels: [:])
        #expect(a.isComplete)
    }
}

@Suite struct ConfigTests {
    @Test func defaultsMatchSpec() {
        let c = AppConfig()
        #expect(c.accounts.isEmpty)
        #expect(c.presets == [JQLPreset.myOpenWork])
        #expect(c.presets[0].accountId == JiraAccount.defaultId)
        #expect(c.activePreset?.jql == "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC")
        #expect(c.view == ViewDefaults(yaw: -179.7, pitch: 33.9, zoom: 1))
        #expect(c.quick.labelMode == "smart")
        #expect(c.quick.stemStyle == "dotted")
        #expect(c.quick.stemOpacity == 30)
        #expect(c.quick.refreshMinutes == 5)
        #expect(!c.quick.alwaysOnTop)
    }

    @Test(arguments: [
        ("acme.atlassian.net", "https://acme.atlassian.net"),
        ("https://acme.atlassian.net/", "https://acme.atlassian.net"),
        ("  http://acme.atlassian.net/jira/software/projects?x=1  ", "https://acme.atlassian.net"),
    ])
    func normalizesSite(input: String, expected: String) {
        #expect(AppConfig.normalizeSite(input)?.absoluteString == expected)
    }

    @Test func rejectsEmptySite() {
        #expect(AppConfig.normalizeSite("   ") == nil)
    }

    @Test func activePresetFallsBackToFirst() {
        var c = AppConfig()
        c.activePresetId = "gone"
        #expect(c.activePreset == JQLPreset.myOpenWork)
    }

    @Test func activeAccountIsTheActivePresetsAccount() {
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal"), JiraAccount(id: "c1", name: "Company")]
        c.presets.append(JQLPreset(id: "p2", name: "My company work", jql: "x", accountId: "c1"))
        #expect(c.activeAccount?.id == "default")
        c.activePresetId = "p2"
        #expect(c.activeAccount?.id == "c1")
        c.presets[1].accountId = "gone"
        #expect(c.activeAccount == nil)
        #expect(c.account(id: nil) == nil)
    }

    @Test func menuOrderGroupsByAccountOrderThenOrphans() {
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal"), JiraAccount(id: "c1", name: "Company")]
        c.presets = [
            JQLPreset(id: "team", name: "Team sprint", jql: "x", accountId: "c1"),
            JQLPreset(id: "orphan", name: "Old", jql: "x", accountId: "gone"),
            JQLPreset(id: "mine", name: "My open work", jql: "x", accountId: "default"),
            JQLPreset(id: "cw", name: "My company work", jql: "x", accountId: "c1"),
            JQLPreset(id: "due", name: "Due this week", jql: "x", accountId: "default"),
        ]
        #expect(c.menuOrderedPresets.map(\.id) == ["mine", "due", "team", "cw", "orphan"])
    }

    @Test func movingPresetsReordersOnlyWithinTheAccount() {
        var c = AppConfig()
        c.presets = [
            JQLPreset(id: "a1", name: "A1", jql: "x", accountId: "a"),
            JQLPreset(id: "b1", name: "B1", jql: "x", accountId: "b"),
            JQLPreset(id: "a2", name: "A2", jql: "x", accountId: "a"),
            JQLPreset(id: "a3", name: "A3", jql: "x", accountId: "a"),
        ]
        // drag A3 (offset 2) to the top of account a
        #expect(c.movingPresets(accountId: "a", fromOffsets: [2], toOffset: 0).map(\.id) == ["a3", "b1", "a1", "a2"])
        // drag A1 (offset 0) to the end (SwiftUI reports toOffset == count)
        #expect(c.movingPresets(accountId: "a", fromOffsets: [0], toOffset: 3).map(\.id) == ["a2", "b1", "a3", "a1"])
        // out-of-range input leaves the order unchanged
        #expect(c.movingPresets(accountId: "a", fromOffsets: [7], toOffset: 0) == c.presets)
        #expect(c.movingPresets(accountId: "a", fromOffsets: [0], toOffset: 9) == c.presets)
    }

    @Test func namesAreNonEmptyAndUniqueCaseInsensitive() {
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal"), JiraAccount(id: "c1", name: "Company")]
        #expect(!c.isAccountNameValid("  "))
        #expect(!c.isAccountNameValid(" personal "))
        #expect(c.isAccountNameValid("Personal", excludingId: "default"))
        #expect(c.isAccountNameValid("Side project"))
        #expect(!c.isPresetNameValid("my open WORK", accountId: "default"))
        #expect(c.isPresetNameValid("My open work", accountId: "c1"))
        #expect(c.isPresetNameValid("My open work", accountId: "default", excludingId: "my-open-work"))
        #expect(!c.isPresetNameValid("", accountId: "c1"))
    }

    @Test func partialFileDecodesWithDefaults() throws {
        let json = #"{"accounts":[{"id":"default","name":"Personal"}],"presets":[{"id":"p","name":"P","jql":"x"}]}"#
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(c.accounts == [JiraAccount(id: "default", name: "Personal")])
        #expect(c.presets[0].accountId == "")
        #expect(c.activePresetId == JQLPreset.myOpenWork.id)
        #expect(c.activePreset?.id == "p")
        #expect(c.view == ViewDefaults())
        #expect(c.quick == QuickSettings())
        #expect(c.lastView == nil)
        #expect(!c.launchAtLogin)
    }

    @Test func accountWithoutIdIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[{"name":"x"}]}"#.utf8))
        }
    }

    @Test func paletteCyclesSixColors() {
        #expect(AccountPalette.color(at: 0) == "#3b82f6")
        #expect(AccountPalette.color(at: 1) == "#f59e0b")
        #expect(AccountPalette.color(at: 6) == "#3b82f6")
        #expect(AccountPalette.colors.count == 6)
    }

    @Test func templatesMatchSpec() {
        #expect(JQLTemplate.all.map(\.title) == ["My open work", "Due this week", "Reported by me", "Unassigned in project…"])
        #expect(JQLTemplate.all[0].jql == JQLPreset.myOpenWork.jql)
        #expect(JQLTemplate.all[1].jql == "assignee = currentUser() AND due <= endOfWeek() AND statusCategory != Done")
        #expect(JQLTemplate.all[2].jql == "reporter = currentUser() AND statusCategory != Done")
        #expect(JQLTemplate.all[3].jql == "project = <KEY> AND assignee is EMPTY AND statusCategory != Done")
    }

    @Test func quickSettingsApplyValidValuesOnly() {
        let q = QuickSettings()
        #expect(q.applying(key: "labelMode", value: .string("key")).labelMode == "key")
        #expect(q.applying(key: "labelMode", value: .string("bogus")).labelMode == "smart")
        #expect(q.applying(key: "stemOpacity", value: .number(200)).stemOpacity == 80)
        #expect(q.applying(key: "stemOpacity", value: .number(1)).stemOpacity == 5)
        #expect(q.applying(key: "panelOpacity", value: .number(10)).panelOpacity == 40)
        #expect(q.applying(key: "grid", value: .bool(false)).grid == false)
        #expect(q.applying(key: "refreshMinutes", value: .number(15)).refreshMinutes == 15)
        #expect(q.applying(key: "refreshMinutes", value: .number(.infinity)).refreshMinutes == 5)
        #expect(q.applying(key: "refreshMinutes", value: .number(.nan)).refreshMinutes == 5)
        #expect(q.applying(key: "refreshMinutes", value: .number(1e30)).refreshMinutes == 5)
        #expect(q.applying(key: "refreshMinutes", value: .number(7)).refreshMinutes == 5)
        #expect(q.applying(key: "rotation", value: .string("free")).rotation == "free")
        #expect(q.applying(key: "unknown", value: .null) == q)
    }
}
