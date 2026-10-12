# onscreen-todo-matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the macOS menu-bar app "onscreen-todo-matrix": a floating, always-on-top panel (⌥Space) that shows Jira Cloud issues as a 3D Value × Effort × Urgency stem chart.

**Architecture:** One SwiftPM package. `OTMCore` (library, no UI) holds all logic: models, config/cache/token stores, field→axis mapping, scoring, Jira REST client, refresh scheduling, and `AppModel` (single source of truth that produces a `RenderState`). `OnscreenTodoMatrix` (executable) is a thin AppKit/SwiftUI shell: status-bar item, `NSPanel` hosting a `WKWebView`, settings window. The chart is the brainstorm prototype ported to ES modules in `chart/`, bundled by esbuild to one IIFE file, and driven via `window.otm.render(state)`; it posts user actions back through `webkit.messageHandlers.otm`.

**Tech Stack:** Swift (tools 5.10 / language mode 5, Swift 6.2 toolchain, Xcode 26.0.1), AppKit + SwiftUI + WebKit + Security + ServiceManagement, `sindresorhus/KeyboardShortcuts` 3.1.0, Swift Testing; JS (ES2022) with esbuild 0.28.2 and Vitest 5.0.4 on Node 22.

**Spec:** [`../specs/arch-20261012-onscreen-todo-matrix-design.md`](../specs/arch-20261012-onscreen-todo-matrix-design.md). Read it before starting any task. Visual reference: [`../prototype/panel-prototype.html`](../prototype/panel-prototype.html) (open it in a browser).

## Global Constraints

- All source lives under `productivity/onscreen-todo-matrix/src/` (called **SRC** below). All shell commands in this plan run from SRC unless stated otherwise.
- macOS 14.0 minimum (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0).
- `// swift-tools-version: 5.10` (Swift 5 language mode, avoids strict-concurrency errors).
- Dependencies are exactly: KeyboardShortcuts `exact: "3.1.0"` (Swift); `esbuild` `0.28.2` and `vitest` `5.0.4` (JS devDependencies). Add nothing else.
- Jira access is **read-only**: only `GET /rest/api/3/myself`, `GET /rest/api/3/field`, `GET /rest/api/3/priority/search`, `POST /rest/api/3/search/jql`, `POST /rest/api/3/search/approximate-count`. No other endpoint, never PUT/DELETE.
- The API token is stored only in Keychain (service `onscreen-todo-matrix`, account `jira-api-token`), never in config JSON.
- Config: `~/Library/Application Support/onscreen-todo-matrix/config.json`; cache: `…/last-fetch.json`; corrupt config is renamed to `config.json.bak`.
- Issue cap: 500 per fetch.
- View: default yaw −179.7°, pitch 33.9°, zoom 1. Limited rotation: yaw ±18°, pitch ±10° around default. Free: pitch clamped ±89°. Zoom 0.5–3. Saved default pitch clamped ±80°.
- Color channel = `round(55 + 200·clamp01(v))`; RGB = (urgency, 1 − effort, value).
- Score = `value × (0.5 + urgency) / (0.3 + effort)`; top 3 ranked; fire = value ≥ 0.7 AND urgency ≥ 0.8.
- Labels: summary truncated to 28 chars with `…`.
- UI copy strings that appear in this plan are exact (banners, button labels).
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

## Review Focus

1. **Datetime due dates with time zones** (`"2026-10-14T23:30:00.000-0700"`): urgency must use the calendar date (first 10 chars), not crash or drift by a day. Test in Task 4.
2. **Mapped custom field present but `null` on an issue**: the task is drawn hollow at the axis default, never dropped or crashing. Test in Task 4.
3. **JQL that matches zero issues**: the chart still draws the floor and the Next strip says "No issues match this filter"; no banner, no NaN in fit. Tests in Task 8 (AppModel) and Task 9 (`fitPoints([])`).
4. **Two issues at exactly the same position**: only one label may occupy a spot; the other tries the remaining positions or is hidden, and no NaN. Test in Task 9.
5. **429 without `Retry-After` header**: back off 60 s, not forever and not zero. Tests in Task 6 (client returns `retryAfter: nil`) and Task 7 (scheduler uses 60 s).

---

## File Structure

```
productivity/onscreen-todo-matrix/src/
├── Package.swift
├── .gitignore
├── fixtures/render-state.json            # shared Swift↔JS contract fixture
├── Sources/OTMCore/
│   ├── JSONValue.swift                   # heterogeneous Jira field values
│   ├── Models.swift                      # JiraIssue/JiraUser/JiraField/Axis/AxisMapping/AxisConfig/AxesConfig/MappedTask
│   ├── Config.swift                      # AppConfig, JQLPreset, ViewDefaults, QuickSettings(+applying)
│   ├── ConfigStore.swift                 # load/save config.json, corrupt → .bak
│   ├── IssueCache.swift                  # last-fetch.json
│   ├── TokenStore.swift                  # protocol + InMemory + Keychain
│   ├── AxisMapper.swift                  # FieldClassifier, AxisMapper, DefaultMappings
│   ├── Scorer.swift                      # score/rank/fire
│   ├── RenderState.swift                 # RenderState + builder
│   ├── JiraClient.swift                  # JiraAPI protocol + URLSession client + JiraError
│   ├── RefreshScheduler.swift            # trigger decisions, pause/back-off
│   └── AppModel.swift                    # orchestration, banners
├── Sources/OnscreenTodoMatrix/
│   ├── main.swift                        # NSApplication bootstrap (accessory)
│   ├── AppDelegate.swift                 # status item, hotkey, timer, message routing
│   ├── PanelController.swift             # FloatingPanel (NSPanel) + window behavior
│   ├── ChartWebView.swift                # WKWebView host + bridge
│   ├── LoginItem.swift                   # SMAppService wrapper
│   ├── Shortcuts.swift                   # KeyboardShortcuts.Name.togglePanel
│   ├── SettingsViewModel.swift
│   ├── SettingsView.swift                # TabView: Connection, Filters, Axes, Shortcuts, General
│   └── SettingsWindowController.swift
├── Tests/OTMCoreTests/
│   ├── TestSupport.swift                 # temp dirs, fixture path, FakeJiraAPI, StubURLProtocol
│   ├── ModelsTests.swift
│   ├── StoresTests.swift
│   ├── AxisMapperTests.swift
│   ├── ScorerRenderStateTests.swift
│   ├── JiraClientTests.swift
│   ├── RefreshSchedulerTests.swift
│   └── AppModelTests.swift
├── chart/
│   ├── package.json
│   ├── public/index.html, public/style.css
│   ├── src/projection.js, fit.js, labels.js, color.js, state.js, render.js, main.js
│   └── test/projection.test.js, fit.test.js, labels.test.js, color.test.js, state.test.js
├── scripts/build-app.sh, scripts/Info.plist
└── docs/manual-checklist.md
```

---

### Task 1: Scaffold the Swift package and the chart JS project

**Files:**
- Create: `SRC/Package.swift`, `SRC/.gitignore`, `SRC/Sources/OTMCore/JSONValue.swift` (placeholder, replaced in Task 2), `SRC/Sources/OnscreenTodoMatrix/main.swift` (placeholder, replaced in Task 11), `SRC/Tests/OTMCoreTests/ModelsTests.swift`
- Create: `SRC/chart/package.json`, `SRC/chart/test/smoke.test.js` (deleted in Task 9)

**Interfaces:**
- Produces: buildable package with targets `OTMCore`, `OnscreenTodoMatrix`, `OTMCoreTests`; `npm test` works in `chart/`.

- [ ] **Step 1: Create directories and Package.swift**

```bash
mkdir -p productivity/onscreen-todo-matrix/src && cd productivity/onscreen-todo-matrix/src
mkdir -p Sources/OTMCore Sources/OnscreenTodoMatrix Tests/OTMCoreTests chart/src chart/test chart/public fixtures scripts docs
```

`Package.swift`:
```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OnscreenTodoMatrix",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OnscreenTodoMatrix", targets: ["OnscreenTodoMatrix"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "OTMCore"),
        .executableTarget(
            name: "OnscreenTodoMatrix",
            dependencies: ["OTMCore", "KeyboardShortcuts"]
        ),
        .testTarget(name: "OTMCoreTests", dependencies: ["OTMCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
chart/node_modules/
chart/dist/
*.xcodeproj
.swiftpm/
```

`Sources/OTMCore/JSONValue.swift` (placeholder):
```swift
public enum OTMCoreVersion { public static let string = "1.0.0" }
```

`Sources/OnscreenTodoMatrix/main.swift` (placeholder):
```swift
import OTMCore
print("onscreen-todo-matrix \(OTMCoreVersion.string)")
```

- [ ] **Step 2: Write the smoke test**

`Tests/OTMCoreTests/ModelsTests.swift`:
```swift
import Testing
@testable import OTMCore

@Test func coreVersionIsSet() {
    #expect(OTMCoreVersion.string == "1.0.0")
}
```

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: build succeeds (KeyboardShortcuts resolves), `1 test passed`.

- [ ] **Step 4: Create the chart project**

`chart/package.json`:
```json
{
  "name": "otm-chart",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "build": "esbuild src/main.js --bundle --format=iife --target=safari17 --outfile=dist/chart.js && cp public/index.html public/style.css dist/"
  },
  "devDependencies": {
    "esbuild": "0.28.2",
    "vitest": "5.0.4"
  }
}
```

`chart/test/smoke.test.js`:
```js
import { test, expect } from 'vitest';
test('smoke', () => { expect(1 + 1).toBe(2); });
```

Run: `cd chart && npm install && npm test && cd ..`
Expected: `1 passed`. Commit `chart/package-lock.json`.

- [ ] **Step 5: Commit**

```bash
git add . && git commit -m "chore(otm): scaffold Swift package and chart project

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Core models and configuration types

**Files:**
- Modify (replace): `SRC/Sources/OTMCore/JSONValue.swift`
- Create: `SRC/Sources/OTMCore/Models.swift`, `SRC/Sources/OTMCore/Config.swift`
- Modify (replace): `SRC/Tests/OTMCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `enum JSONValue: Codable, Equatable { string, number, bool, object, array, null }`, `subscript(key:) -> JSONValue?`, `stringValue: String?`, `numberValue: Double?`, `boolValue: Bool?`, `init(any: Any?)`
  - `struct JiraIssue { key: String; fields: [String: JSONValue] }`, `struct JiraUser { displayName, accountId }`, `struct JiraField { id, name, custom: Bool, schemaType: String?, schemaItems: String? }`
  - `enum Axis: String, CaseIterable { value, effort, urgency }`
  - `enum AxisMapping { option(fieldId:levels:), number(fieldId:min:max:invert:), date(fieldId:horizonDays:invert:) }` + `fieldId`
  - `struct AxisConfig { mapping: AxisMapping?; missingDefault: Double }`, `struct AxesConfig { value, effort, urgency; subscript(Axis); isComplete }`
  - `struct MissingFlags { value, effort, urgency: Bool; subscript(Axis) }`, `struct MappedTask { key, summary, status, priority?, due?, url, value, effort, urgency, missing }`
  - `struct JQLPreset { id, name, jql }`, `JQLPreset.myOpenWork`, `struct ViewDefaults { yaw, pitch, zoom }`, `struct QuickSettings {…}` + `applying(key:value:)`, `struct AppConfig {…}` + `activePreset`, `siteURL`, `static normalizeSite(_:) -> URL?`

- [ ] **Step 1: Write the failing tests**

`Tests/OTMCoreTests/ModelsTests.swift`:
```swift
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
        #expect(c.presets == [JQLPreset.myOpenWork])
        #expect(c.activePreset.jql == "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC")
        #expect(c.view == ViewDefaults(yaw: -179.7, pitch: 33.9, zoom: 1))
        #expect(c.quick.labelMode == "smart")
        #expect(c.quick.stemStyle == "dotted")
        #expect(c.quick.stemOpacity == 30)
        #expect(c.quick.refreshMinutes == 5)
        #expect(c.quick.alwaysOnTop)
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

    @Test func quickSettingsApplyValidValuesOnly() {
        let q = QuickSettings()
        #expect(q.applying(key: "labelMode", value: .string("key")).labelMode == "key")
        #expect(q.applying(key: "labelMode", value: .string("bogus")).labelMode == "smart")
        #expect(q.applying(key: "stemOpacity", value: .number(200)).stemOpacity == 80)
        #expect(q.applying(key: "stemOpacity", value: .number(1)).stemOpacity == 5)
        #expect(q.applying(key: "panelOpacity", value: .number(10)).panelOpacity == 40)
        #expect(q.applying(key: "grid", value: .bool(false)).grid == false)
        #expect(q.applying(key: "refreshMinutes", value: .number(15)).refreshMinutes == 15)
        #expect(q.applying(key: "refreshMinutes", value: .number(7)).refreshMinutes == 5)
        #expect(q.applying(key: "rotation", value: .string("free")).rotation == "free")
        #expect(q.applying(key: "unknown", value: .null) == q)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`JSONValue`, `JiraField`, `AppConfig` … not found).

- [ ] **Step 3: Implement**

`Sources/OTMCore/JSONValue.swift` (replace whole file):
```swift
import Foundation

/// A Jira field value: Jira fields are heterogeneous JSON.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// Converts a value received from WKScriptMessage (Foundation types).
    public init(any: Any?) {
        guard let any else { self = .null; return }
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSONValue(any: $0) })
        case let d as [String: Any]: self = .object(d.mapValues { JSONValue(any: $0) })
        default: self = .null
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
```

`Sources/OTMCore/Models.swift`:
```swift
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

public struct AxisConfig: Codable, Equatable, Sendable {
    public var mapping: AxisMapping?
    public var missingDefault: Double
    public init(mapping: AxisMapping? = nil, missingDefault: Double = 0.5) {
        self.mapping = mapping
        self.missingDefault = missingDefault
    }
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

    public init(key: String, summary: String, status: String, priority: String?, due: String?, url: String,
                value: Double, effort: Double, urgency: Double, missing: MissingFlags = MissingFlags()) {
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
    }
}
```

`Sources/OTMCore/Config.swift`:
```swift
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
    public var alwaysOnTop = true
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
            if let n = value.numberValue, [0, 1, 5, 15].contains(Int(n)) { q.refreshMinutes = Int(n) }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all ModelsTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): core models and configuration types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Config store, issue cache and token store

**Files:**
- Create: `SRC/Sources/OTMCore/ConfigStore.swift`, `SRC/Sources/OTMCore/IssueCache.swift`, `SRC/Sources/OTMCore/TokenStore.swift`
- Create: `SRC/Tests/OTMCoreTests/TestSupport.swift`, `SRC/Tests/OTMCoreTests/StoresTests.swift`

**Interfaces:**
- Consumes: `AppConfig`, `JiraIssue` (Task 2).
- Produces:
  - `enum ConfigLoadResult: Equatable { loaded(AppConfig), missing, corrupt(backup: URL) }`
  - `final class ConfigStore { init(directory: URL); let url: URL; func load() -> ConfigLoadResult; func save(_: AppConfig) throws; static func defaultDirectory() -> URL }`
  - `struct CachedFetch: Codable, Equatable { issues: [JiraIssue]; fetchedAt: Date }`, `final class IssueCache { init(directory: URL); func save(_: CachedFetch) throws; func load() -> CachedFetch? }`
  - `protocol TokenStore: AnyObject { func read() throws -> String?; func write(_: String) throws; func delete() throws }`, `final class InMemoryTokenStore: TokenStore { var token: String?; var readError: Error? }`, `final class KeychainTokenStore: TokenStore`, `enum TokenStoreError: Error, Equatable { status(Int32) }`
  - Test helper `func makeTempDir() -> URL`

- [ ] **Step 1: Write the failing tests**

`Tests/OTMCoreTests/TestSupport.swift`:
```swift
import Foundation
@testable import OTMCore

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("otm-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// SRC directory, derived from this file's location (Tests/OTMCoreTests/TestSupport.swift).
let srcDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
```

`Tests/OTMCoreTests/StoresTests.swift`:
```swift
import Foundation
import Testing
@testable import OTMCore

@Suite struct ConfigStoreTests {
    @Test func missingFileReportsMissing() {
        #expect(ConfigStore(directory: makeTempDir()).load() == .missing)
    }

    @Test func roundTripsConfig() throws {
        let store = ConfigStore(directory: makeTempDir().appendingPathComponent("nested"))
        var c = AppConfig()
        c.site = "acme.atlassian.net"
        c.axes.urgency.mapping = .option(fieldId: "priority", levels: ["High": 4])
        try store.save(c)
        #expect(store.load() == .loaded(c))
    }

    @Test func corruptFileIsBackedUpNotLost() throws {
        let dir = makeTempDir()
        let store = ConfigStore(directory: dir)
        try Data("{not json".utf8).write(to: store.url)
        let result = store.load()
        let bak = dir.appendingPathComponent("config.json.bak")
        #expect(result == .corrupt(backup: bak))
        #expect(String(decoding: try Data(contentsOf: bak), as: UTF8.self) == "{not json")
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

@Suite struct IssueCacheTests {
    @Test func emptyCacheLoadsNil() {
        #expect(IssueCache(directory: makeTempDir()).load() == nil)
    }

    @Test func roundTripsIssuesAndTimestamp() throws {
        let cache = IssueCache(directory: makeTempDir())
        let fetch = CachedFetch(
            issues: [JiraIssue(key: "SEC-5", fields: ["summary": .string("Rotate key")])],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try cache.save(fetch)
        #expect(cache.load() == fetch)
    }
}

@Suite struct InMemoryTokenStoreTests {
    @Test func writeReadDelete() throws {
        let s = InMemoryTokenStore()
        #expect(try s.read() == nil)
        try s.write("abc")
        #expect(try s.read() == "abc")
        try s.delete()
        #expect(try s.read() == nil)
    }

    @Test func readErrorIsThrown() {
        let s = InMemoryTokenStore()
        s.readError = TokenStoreError.status(-25293)
        #expect(throws: TokenStoreError.status(-25293)) { try s.read() }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`ConfigStore`, `IssueCache`, `InMemoryTokenStore` not found).

- [ ] **Step 3: Implement**

`Sources/OTMCore/ConfigStore.swift`:
```swift
import Foundation

public enum ConfigLoadResult: Equatable {
    case loaded(AppConfig)
    case missing
    case corrupt(backup: URL)
}

public final class ConfigStore {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("config.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onscreen-todo-matrix")
    }

    public func load() -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.json.bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return .corrupt(backup: backup)
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: url, options: .atomic)
    }
}
```

`Sources/OTMCore/IssueCache.swift`:
```swift
import Foundation

public struct CachedFetch: Codable, Equatable, Sendable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    public init(issues: [JiraIssue], fetchedAt: Date) {
        self.issues = issues
        self.fetchedAt = fetchedAt
    }
}

public final class IssueCache {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("last-fetch.json")
    }

    public func save(_ fetch: CachedFetch) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(fetch).write(to: url, options: .atomic)
    }

    public func load() -> CachedFetch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CachedFetch.self, from: data)
    }
}
```

`Sources/OTMCore/TokenStore.swift`:
```swift
import Foundation
import Security

public protocol TokenStore: AnyObject {
    func read() throws -> String?
    func write(_ token: String) throws
    func delete() throws
}

public enum TokenStoreError: Error, Equatable {
    case status(Int32)
}

public final class InMemoryTokenStore: TokenStore {
    public var token: String?
    public var readError: Error?
    public init(token: String? = nil) { self.token = token }
    public func read() throws -> String? {
        if let readError { throw readError }
        return token
    }
    public func write(_ token: String) throws { self.token = token }
    public func delete() throws { token = nil }
}

/// API token in the macOS Keychain (generic password).
public final class KeychainTokenStore: TokenStore {
    private let service = "onscreen-todo-matrix"
    private let account = "jira-api-token"
    public init() {}

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() throws -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw TokenStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.status(update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.status(status) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError.status(status) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all pass. (`KeychainTokenStore` is verified manually in Task 13; tests never touch the real Keychain.)

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): config store, issue cache and keychain token store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Field classification, axis mapping and default mappings

**Files:**
- Create: `SRC/Sources/OTMCore/AxisMapper.swift`, `SRC/Tests/OTMCoreTests/AxisMapperTests.swift`

**Interfaces:**
- Consumes: `JSONValue`, `JiraIssue`, `JiraField`, `AxisMapping`, `AxesConfig`, `MappedTask`, `MissingFlags` (Task 2).
- Produces:
  - `enum FieldKind { option, number, date, unsupported }`, `enum FieldClassifier { static func kind(of: JiraField) -> FieldKind }`
  - `enum AxisMapper { static func optionLabel(_: JSONValue?) -> String?; static func dateValue(_: JSONValue?, calendar: Calendar) -> Date?; static func autoRange(fieldId: String, issues: [JiraIssue]) -> ClosedRange<Double>?; static func normalize(_ raw: JSONValue?, mapping: AxisMapping, autoRange: ClosedRange<Double>?, now: Date, calendar: Calendar) -> Double?; static func observedLabels(fieldId: String, issues: [JiraIssue]) -> [String]; static func unmappedLabels(issues: [JiraIssue], mapping: AxisMapping) -> [String]; static func map(issues: [JiraIssue], axes: AxesConfig, site: URL, now: Date, calendar: Calendar) -> [MappedTask] }`
  - `enum DefaultMappings { static let priorityLevels: [String: Double]; static func mapping(for: JiraField) -> AxisMapping?; static func suggest(fields: [JiraField], current: AxesConfig) -> AxesConfig }`

- [ ] **Step 1: Write the failing tests**

`Tests/OTMCoreTests/AxisMapperTests.swift`:
```swift
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
        #expect(DefaultMappings.suggest(fields: fields, current: cur).urgency == cur.urgency)
    }

    @Test func priorityLevelsMatchSpec() {
        #expect(DefaultMappings.priorityLevels == ["Highest": 5, "High": 3.75, "Medium": 2.5, "Low": 1.25, "Lowest": 0])
    }

    @Test func mappingForFieldKind() {
        #expect(DefaultMappings.mapping(for: fields[3]) == .date(fieldId: "duedate", horizonDays: 14, invert: false))
        #expect(DefaultMappings.mapping(for: JiraField(id: "u", name: "U", custom: false, schemaType: "user")) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`FieldClassifier`, `AxisMapper`, `DefaultMappings` not found).

- [ ] **Step 3: Implement**

`Sources/OTMCore/AxisMapper.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): field classification and axis mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Scorer, RenderState and the shared contract fixture

**Files:**
- Create: `SRC/Sources/OTMCore/Scorer.swift`, `SRC/Sources/OTMCore/RenderState.swift`, `SRC/fixtures/render-state.json`, `SRC/Tests/OTMCoreTests/ScorerRenderStateTests.swift`

**Interfaces:**
- Consumes: `MappedTask`, `AppConfig`, `QuickSettings`, `ViewDefaults`, `MissingFlags` (Task 2).
- Produces:
  - `struct ScoredTask { task: MappedTask; score: Double; rank: Int?; fire: Bool }`, `enum Scorer { static func score(value:effort:urgency:) -> Double; static func isFire(value:urgency:) -> Bool; static func rank(_: [MappedTask]) -> [ScoredTask] }` (returned sorted by score desc, key asc)
  - `struct RenderTask: Codable { key, summary, status, priority?, due?, url, value, effort, urgency, missing, score, rank?, fire, changed }`
  - `struct RenderStatus: Codable { syncedAt: Date?; banner: String?; truncated: String? }`, `struct RenderPreset: Codable { id, name }`
  - `struct RenderState: Codable, Equatable { tasks: [RenderTask]; view: ViewDefaults; settings: QuickSettings; status: RenderStatus; presets: [RenderPreset]; activePresetId: String; configured: Bool }` + `static let empty`
  - `enum RenderStateBuilder { static func build(tasks: [MappedTask], previous: [String: MappedTask]?, config: AppConfig, status: RenderStatus, configured: Bool) -> RenderState; static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }`
  - JSON keys of `fixtures/render-state.json` are the contract the JS side (Task 9/10) relies on.

- [ ] **Step 1: Create the fixture**

`fixtures/render-state.json`:
```json
{
  "tasks": [
    { "key": "SEC-5", "summary": "Rotate leaked Stripe API key", "status": "In Progress", "priority": "Highest",
      "due": "2026-10-12", "url": "https://acme.atlassian.net/browse/SEC-5",
      "value": 0.95, "effort": 0.1, "urgency": 1.0,
      "missing": { "value": false, "effort": false, "urgency": false },
      "score": 3.5625, "rank": 1, "fire": true, "changed": false },
    { "key": "PAY-412", "summary": "Refund webhook returns 500 for partial refunds", "status": "To Do", "priority": "High",
      "due": null, "url": "https://acme.atlassian.net/browse/PAY-412",
      "value": 0.92, "effort": 0.2, "urgency": 0.95,
      "missing": { "value": false, "effort": false, "urgency": false },
      "score": 2.668, "rank": 2, "fire": true, "changed": true },
    { "key": "DATA-19", "summary": "Rebuild data warehouse on ClickHouse", "status": "Backlog", "priority": null,
      "due": null, "url": "https://acme.atlassian.net/browse/DATA-19",
      "value": 0.8, "effort": 0.5, "urgency": 0.2,
      "missing": { "value": false, "effort": true, "urgency": false },
      "score": 0.7, "rank": null, "fire": false, "changed": false }
  ],
  "view": { "yaw": -179.7, "pitch": 33.9, "zoom": 1 },
  "settings": { "labelMode": "smart", "stemStyle": "dotted", "stemOpacity": 30, "colorMode": "rgb", "grid": true,
                "zoneNames": true, "rotation": "limited", "panelOpacity": 100, "alwaysOnTop": true, "refreshMinutes": 5 },
  "status": { "syncedAt": "2026-10-12T10:42:00Z", "banner": null, "truncated": null },
  "presets": [ { "id": "my-open-work", "name": "My open work" } ],
  "activePresetId": "my-open-work",
  "configured": true
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/OTMCoreTests/ScorerRenderStateTests.swift`:
```swift
import Foundation
import Testing
@testable import OTMCore

private func task(_ key: String, v: Double, e: Double, u: Double) -> MappedTask {
    MappedTask(key: key, summary: key, status: "", priority: nil, due: nil, url: "u/\(key)", value: v, effort: e, urgency: u)
}

@Suite struct ScorerTests {
    @Test func formulaMatchesSpec() {
        #expect(abs(Scorer.score(value: 0.95, effort: 0.1, urgency: 1) - 3.5625) < 1e-9)
        #expect(Scorer.score(value: 0, effort: 0, urgency: 1) == 0)
    }

    @Test func fireThresholdsAreInclusive() {
        #expect(Scorer.isFire(value: 0.7, urgency: 0.8))
        #expect(!Scorer.isFire(value: 0.69, urgency: 1))
        #expect(!Scorer.isFire(value: 1, urgency: 0.79))
    }

    @Test func ranksTopThreeByScoreThenKey() {
        let scored = Scorer.rank([
            task("D", v: 0.1, e: 0.9, u: 0.1), task("B", v: 1, e: 0, u: 1),
            task("A", v: 1, e: 0, u: 1), task("C", v: 0.9, e: 0.2, u: 0.5),
        ])
        #expect(scored.map(\.task.key) == ["A", "B", "C", "D"])
        #expect(scored.map(\.rank) == [1, 2, 3, nil])
    }

    @Test func emptyInput() {
        #expect(Scorer.rank([]).isEmpty)
    }
}

@Suite struct RenderStateTests {
    @Test func buildMarksChangedOnlyAgainstPrevious() {
        let old = task("A", v: 0.5, e: 0.5, u: 0.5)
        let moved = task("A", v: 0.9, e: 0.5, u: 0.5)
        let same = task("B", v: 0.2, e: 0.2, u: 0.2)
        let new = task("C", v: 0.3, e: 0.3, u: 0.3)
        let s = RenderStateBuilder.build(tasks: [moved, same, new], previous: ["A": old, "B": same],
                                         config: AppConfig(), status: RenderStatus(), configured: true)
        let changed = Dictionary(uniqueKeysWithValues: s.tasks.map { ($0.key, $0.changed) })
        #expect(changed == ["A": true, "B": false, "C": false])
        let noDiff = RenderStateBuilder.build(tasks: [moved], previous: nil, config: AppConfig(),
                                              status: RenderStatus(), configured: true)
        #expect(noDiff.tasks[0].changed == false)
    }

    @Test func buildCopiesConfigAndScores() {
        var c = AppConfig()
        c.quick.labelMode = "key"
        c.presets.append(JQLPreset(id: "p2", name: "Team", jql: "project = X"))
        let s = RenderStateBuilder.build(tasks: [task("A", v: 1, e: 0, u: 1)], previous: nil, config: c,
                                         status: RenderStatus(syncedAt: nil, banner: "b", truncated: nil), configured: false)
        #expect(s.settings.labelMode == "key")
        #expect(s.presets == [RenderPreset(id: "my-open-work", name: "My open work"), RenderPreset(id: "p2", name: "Team")])
        #expect(s.activePresetId == "my-open-work")
        #expect(s.tasks[0].rank == 1)
        #expect(s.tasks[0].fire)
        #expect(s.status.banner == "b")
        #expect(!s.configured)
    }

    @Test func sharedFixtureDecodesAndRoundTrips() throws {
        // Contract test: the same file is decoded by chart/test/state.test.js.
        let data = try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/render-state.json"))
        let state = try RenderStateBuilder.decoder().decode(RenderState.self, from: data)
        #expect(state.tasks.count == 3)
        #expect(state.tasks[2].missing.effort)
        #expect(state.tasks[2].rank == nil)
        #expect(state.view == ViewDefaults())
        #expect(state.settings == QuickSettings())
        let again = try RenderStateBuilder.decoder().decode(RenderState.self, from: RenderStateBuilder.encoder().encode(state))
        #expect(again == state)
    }

    @Test func encodesSpecialCharactersSafely() throws {
        var t = task("Q-1", v: 0.5, e: 0.5, u: 0.5)
        t.summary = "Quote \" backslash \\ </script> emoji 🔥 line\u{2028}sep"
        let s = RenderStateBuilder.build(tasks: [t], previous: nil, config: AppConfig(), status: RenderStatus(), configured: true)
        let back = try RenderStateBuilder.decoder().decode(RenderState.self, from: RenderStateBuilder.encoder().encode(s))
        #expect(back.tasks[0].summary == t.summary)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`Scorer`, `RenderStateBuilder` not found).

- [ ] **Step 4: Implement**

`Sources/OTMCore/Scorer.swift`:
```swift
import Foundation

public struct ScoredTask: Equatable, Sendable {
    public var task: MappedTask
    public var score: Double
    public var rank: Int?
    public var fire: Bool
}

public enum Scorer {
    public static func score(value: Double, effort: Double, urgency: Double) -> Double {
        value * (0.5 + urgency) / (0.3 + effort)
    }

    public static func isFire(value: Double, urgency: Double) -> Bool {
        value >= 0.7 && urgency >= 0.8
    }

    /// Sorted by score (desc), then key (asc). The first three get rank 1…3.
    public static func rank(_ tasks: [MappedTask]) -> [ScoredTask] {
        tasks
            .map { ScoredTask(task: $0, score: score(value: $0.value, effort: $0.effort, urgency: $0.urgency),
                              rank: nil, fire: isFire(value: $0.value, urgency: $0.urgency)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.task.key < $1.task.key }
            .enumerated()
            .map { i, s in var s = s; s.rank = i < 3 ? i + 1 : nil; return s }
    }
}
```

`Sources/OTMCore/RenderState.swift`:
```swift
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
    public var settings: QuickSettings
    public var status: RenderStatus
    public var presets: [RenderPreset]
    public var activePresetId: String
    public var configured: Bool

    public static let empty = RenderState(tasks: [], view: ViewDefaults(), settings: QuickSettings(),
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
        return RenderState(tasks: rendered, view: config.view, settings: config.quick, status: status,
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests fixtures && git commit -m "feat(otm): scoring and render state contract

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Jira Cloud REST client (read-only)

**Files:**
- Create: `SRC/Sources/OTMCore/JiraClient.swift`, `SRC/Tests/OTMCoreTests/JiraClientTests.swift`
- Modify: `SRC/Tests/OTMCoreTests/TestSupport.swift` (append `StubURLProtocol`)

**Interfaces:**
- Consumes: `JiraIssue`, `JiraUser`, `JiraField` (Task 2).
- Produces:
  - `enum JiraError: Error, Equatable { notConfigured, unauthorized, rateLimited(retryAfter: Double?), badRequest(String), http(Int), network(String), decoding(String) }`
  - `struct SearchResult: Equatable { issues: [JiraIssue]; truncated: Bool; approximateTotal: Int? }`
  - `protocol JiraAPI: AnyObject { func myself() async throws -> JiraUser; func fields() async throws -> [JiraField]; func priorities() async throws -> [String]; func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult; func approximateCount(jql: String) async throws -> Int }`
  - `final class JiraClient: JiraAPI { init(site: URL, email: String, token: String, session: URLSession = .shared) }`

- [ ] **Step 1: Add the URL stub to TestSupport**

Append to `Tests/OTMCoreTests/TestSupport.swift`:
```swift
/// Intercepts URLSession requests. Use only from `.serialized` suites (static state).
final class StubURLProtocol: URLProtocol {
    struct Response { var status: Int; var headers: [String: String] = [:]; var body: String }
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> Response)?
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data?)] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        Self.requests.append((request, body))
        let r = Self.handler?(request, body) ?? Response(status: 500, body: "{}")
        let http = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(r.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/OTMCoreTests/JiraClientTests.swift`:
```swift
import Foundation
import Testing
@testable import OTMCore

@Suite(.serialized) struct JiraClientTests {
    let site = URL(string: "https://acme.atlassian.net")!

    func client() -> JiraClient {
        StubURLProtocol.reset()
        return JiraClient(site: site, email: "me@x.com", token: "tok", session: StubURLProtocol.session())
    }

    func bodyJSON(_ i: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: StubURLProtocol.requests[i].body ?? Data())) as? [String: Any] ?? [:]
    }

    @Test func myselfSendsBasicAuth() async throws {
        let c = client()
        StubURLProtocol.handler = { _, _ in .init(status: 200, body: #"{"accountId":"1","displayName":"Neo","emailAddress":"x"}"#) }
        let me = try await c.myself()
        #expect(me == JiraUser(displayName: "Neo", accountId: "1"))
        let req = StubURLProtocol.requests[0].request
        #expect(req.url?.absoluteString == "https://acme.atlassian.net/rest/api/3/myself")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("me@x.com:tok".utf8).base64EncodedString())
        #expect(req.httpMethod == "GET")
    }

    @Test func fieldsAndPriorities() async throws {
        let c = client()
        StubURLProtocol.handler = { req, _ in
            if req.url!.path.hasSuffix("/field") {
                return .init(status: 200, body: #"[{"id":"priority","name":"Priority","custom":false,"schema":{"type":"priority"}}]"#)
            }
            return .init(status: 200, body: #"{"values":[{"id":"1","name":"Highest"},{"id":"2","name":"Low"}],"isLast":true}"#)
        }
        #expect(try await c.fields().map(\.id) == ["priority"])
        #expect(try await c.priorities() == ["Highest", "Low"])
        #expect(StubURLProtocol.requests[1].request.url?.absoluteString
                == "https://acme.atlassian.net/rest/api/3/priority/search?maxResults=100")
    }

    @Test func searchPaginatesWithNextPageToken() async throws {
        let c = client()
        StubURLProtocol.handler = { _, body in
            let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
            if json["nextPageToken"] == nil {
                return .init(status: 200, body: #"{"issues":[{"id":"1","key":"A-1","fields":{"summary":"one"}}],"nextPageToken":"p2","isLast":false}"#)
            }
            return .init(status: 200, body: #"{"issues":[{"id":"2","key":"A-2","fields":{"summary":"two"}}],"isLast":true}"#)
        }
        let r = try await c.search(jql: "project = A", fields: ["summary", "priority"], cap: 500)
        #expect(r.issues.map(\.key) == ["A-1", "A-2"])
        #expect(!r.truncated)
        #expect(r.approximateTotal == nil)
        let first = bodyJSON(0)
        #expect(first["jql"] as? String == "project = A")
        #expect(first["fields"] as? [String] == ["summary", "priority"])
        #expect(first["maxResults"] as? Int == 100)
        #expect(bodyJSON(1)["nextPageToken"] as? String == "p2")
        #expect(StubURLProtocol.requests[0].request.httpMethod == "POST")
        #expect(StubURLProtocol.requests[0].request.url?.path == "/rest/api/3/search/jql")
    }

    @Test func searchStopsAtCapAndAsksApproximateCount() async throws {
        let c = client()
        StubURLProtocol.handler = { req, _ in
            if req.url!.path.hasSuffix("approximate-count") { return .init(status: 200, body: #"{"count":1240}"#) }
            return .init(status: 200, body: #"{"issues":[{"key":"A-1","fields":{}},{"key":"A-2","fields":{}}],"nextPageToken":"more"}"#)
        }
        let r = try await c.search(jql: "x", fields: [], cap: 2)
        #expect(r.issues.count == 2)
        #expect(r.truncated)
        #expect(r.approximateTotal == 1240)
        #expect(bodyJSON(0)["maxResults"] as? Int == 2)
    }

    @Test func mapsHttpErrors() async {
        let c = client()
        let cases: [(StubURLProtocol.Response, JiraError)] = [
            (.init(status: 401, body: ""), .unauthorized),
            (.init(status: 403, body: ""), .unauthorized),
            (.init(status: 429, headers: ["Retry-After": "12"], body: ""), .rateLimited(retryAfter: 12)),
            (.init(status: 429, body: ""), .rateLimited(retryAfter: nil)),   // Review Focus #5
            (.init(status: 400, body: #"{"errorMessages":["Field 'x' does not exist."],"errors":{}}"#),
             .badRequest("Field 'x' does not exist.")),
            (.init(status: 500, body: ""), .http(500)),
        ]
        for (response, expected) in cases {
            StubURLProtocol.handler = { _, _ in response }
            await #expect(throws: expected) { _ = try await c.myself() }
        }
    }

    @Test func undecodableBodyIsDecodingError() async {
        let c = client()
        StubURLProtocol.handler = { _, _ in .init(status: 200, body: "<html>") }
        do {
            _ = try await c.fields()
            Issue.record("expected error")
        } catch let e as JiraError {
            if case .decoding = e {} else { Issue.record("wrong error \(e)") }
        } catch {
            Issue.record("wrong error type \(error)")
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter JiraClientTests`
Expected: compile errors (`JiraClient`, `JiraError` not found).

- [ ] **Step 4: Implement**

`Sources/OTMCore/JiraClient.swift`:
```swift
import Foundation

public enum JiraError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: Double?)
    case badRequest(String)
    case http(Int)
    case network(String)
    case decoding(String)
}

public struct SearchResult: Equatable, Sendable {
    public var issues: [JiraIssue]
    public var truncated: Bool
    public var approximateTotal: Int?
    public init(issues: [JiraIssue], truncated: Bool = false, approximateTotal: Int? = nil) {
        self.issues = issues
        self.truncated = truncated
        self.approximateTotal = approximateTotal
    }
}

/// Read-only Jira Cloud API surface used by the app.
public protocol JiraAPI: AnyObject {
    func myself() async throws -> JiraUser
    func fields() async throws -> [JiraField]
    func priorities() async throws -> [String]
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult
    func approximateCount(jql: String) async throws -> Int
}

public final class JiraClient: JiraAPI {
    private let base: URL
    private let authorization: String
    private let session: URLSession

    public init(site: URL, email: String, token: String, session: URLSession = .shared) {
        base = site
        authorization = "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
        self.session = session
    }

    public func myself() async throws -> JiraUser {
        try decode(JiraUser.self, from: await send("rest/api/3/myself"))
    }

    public func fields() async throws -> [JiraField] {
        try decode([JiraField].self, from: await send("rest/api/3/field"))
    }

    public func priorities() async throws -> [String] {
        struct Page: Decodable { struct P: Decodable { var name: String }; var values: [P] }
        let data = try await send("rest/api/3/priority/search", query: [URLQueryItem(name: "maxResults", value: "100")])
        return try decode(Page.self, from: data).values.map(\.name)
    }

    public func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        struct Page: Decodable { var issues: [JiraIssue]; var nextPageToken: String?; var isLast: Bool? }
        var issues: [JiraIssue] = []
        var token: String?
        var more = false
        repeat {
            var body: [String: Any] = ["jql": jql, "fields": fields, "maxResults": min(100, cap - issues.count)]
            if let token { body["nextPageToken"] = token }
            let data = try await send("rest/api/3/search/jql", method: "POST",
                                      body: try JSONSerialization.data(withJSONObject: body))
            let page = try decode(Page.self, from: data)
            issues.append(contentsOf: page.issues)
            token = page.nextPageToken
            more = token != nil && page.isLast != true && !page.issues.isEmpty
        } while more && issues.count < cap
        let truncated = more && issues.count >= cap
        let total: Int? = truncated ? (try? await approximateCount(jql: jql)) : nil
        return SearchResult(issues: Array(issues.prefix(cap)), truncated: truncated, approximateTotal: total)
    }

    public func approximateCount(jql: String) async throws -> Int {
        struct Count: Decodable { var count: Int }
        let data = try await send("rest/api/3/search/approximate-count", method: "POST",
                                  body: try JSONSerialization.data(withJSONObject: ["jql": jql]))
        return try decode(Count.self, from: data).count
    }

    // MARK: - Transport

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw JiraError.network("No HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw JiraError.unauthorized
        case 429: throw JiraError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        case 400: throw JiraError.badRequest(Self.errorMessage(data) ?? "Bad request")
        default: throw JiraError.http(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw JiraError.decoding(String(describing: error)) }
    }

    static func errorMessage(_ data: Data) -> String? {
        struct Body: Decodable { var errorMessages: [String]?; var errors: [String: String]? }
        guard let b = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        let all = (b.errorMessages ?? []) + (b.errors ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return all.isEmpty ? nil : all.joined(separator: "; ")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): read-only Jira Cloud REST client

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Refresh scheduler

**Files:**
- Create: `SRC/Sources/OTMCore/RefreshScheduler.swift`, `SRC/Tests/OTMCoreTests/RefreshSchedulerTests.swift`

**Interfaces:**
- Consumes: `JiraError` (Task 6).
- Produces: `enum RefreshTrigger { manual, focus, timer }`; `final class RefreshScheduler { init(now: @escaping () -> Date = Date.init); var lastFetch: Date? { get }; var backoffUntil: Date? { get }; var isPaused: Bool { get }; func shouldRefresh(_: RefreshTrigger, intervalMinutes: Int) -> Bool; func recordSuccess(); func recordFailure(_: JiraError); func resume() }`

- [ ] **Step 1: Write the failing tests**

`Tests/OTMCoreTests/RefreshSchedulerTests.swift`:
```swift
import Foundation
import Testing
@testable import OTMCore

final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

@Suite struct RefreshSchedulerTests {
    let clock = FakeClock()
    var s: RefreshScheduler { RefreshScheduler(now: { [clock] in clock.now }) }

    @Test func firstFetchAlwaysAllowed() {
        let s = self.s
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func focusNeedsMoreThan30Seconds() {
        let s = self.s
        s.recordSuccess()
        clock.advance(30)
        #expect(!s.shouldRefresh(.focus, intervalMinutes: 5))
        clock.advance(1)
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
    }

    @Test func timerFollowsIntervalAndOff() {
        let s = self.s
        s.recordSuccess()
        clock.advance(4 * 60)
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 5))
        clock.advance(60)
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 0))
    }

    @Test func unauthorizedPausesAutomaticTriggersButNotManual() {
        let s = self.s
        s.recordFailure(.unauthorized)
        clock.advance(3600)
        #expect(s.isPaused)
        #expect(!s.shouldRefresh(.focus, intervalMinutes: 5))
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
        s.resume()
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
    }

    @Test func rateLimitBacksOffForRetryAfter() {
        let s = self.s
        s.recordFailure(.rateLimited(retryAfter: 12))
        clock.advance(11)
        #expect(!s.shouldRefresh(.manual, intervalMinutes: 5))
        clock.advance(2)
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func rateLimitWithoutHeaderBacksOff60s() {
        // Review Focus #5
        let s = self.s
        s.recordFailure(.rateLimited(retryAfter: nil))
        clock.advance(59)
        #expect(!s.shouldRefresh(.manual, intervalMinutes: 5))
        clock.advance(2)
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func successClearsPauseAndBackoff() {
        let s = self.s
        s.recordFailure(.unauthorized)
        s.recordFailure(.rateLimited(retryAfter: 100))
        s.recordSuccess()
        #expect(!s.isPaused)
        #expect(s.backoffUntil == nil)
        #expect(s.lastFetch == clock.now)
    }

    @Test func networkErrorsDoNotPause() {
        let s = self.s
        s.recordFailure(.network("offline"))
        #expect(!s.isPaused)
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RefreshSchedulerTests`
Expected: compile error (`RefreshScheduler` not found).

- [ ] **Step 3: Implement**

`Sources/OTMCore/RefreshScheduler.swift`:
```swift
import Foundation

public enum RefreshTrigger: Equatable, Sendable {
    case manual, focus, timer
}

/// Decides whether a refresh should run. The app owns the actual timer.
public final class RefreshScheduler {
    public static let focusMinInterval: TimeInterval = 30
    public static let defaultBackoff: TimeInterval = 60

    private let now: () -> Date
    public private(set) var lastFetch: Date?
    public private(set) var backoffUntil: Date?
    public private(set) var isPaused = false

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func shouldRefresh(_ trigger: RefreshTrigger, intervalMinutes: Int) -> Bool {
        let t = now()
        if let until = backoffUntil, t < until { return false }
        switch trigger {
        case .manual:
            return true
        case .focus:
            guard !isPaused else { return false }
            guard let last = lastFetch else { return true }
            return t.timeIntervalSince(last) > Self.focusMinInterval
        case .timer:
            guard !isPaused, intervalMinutes > 0 else { return false }
            guard let last = lastFetch else { return true }
            return t.timeIntervalSince(last) >= Double(intervalMinutes) * 60 - 1
        }
    }

    public func recordSuccess() {
        lastFetch = now()
        backoffUntil = nil
        isPaused = false
    }

    public func recordFailure(_ error: JiraError) {
        switch error {
        case .unauthorized: isPaused = true
        case .rateLimited(let retryAfter): backoffUntil = now().addingTimeInterval(retryAfter ?? Self.defaultBackoff)
        default: break
        }
    }

    /// Call after credentials or JQL change.
    public func resume() {
        isPaused = false
        backoffUntil = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): refresh scheduler with pause and back-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: AppModel (orchestration and banners)

**Files:**
- Create: `SRC/Sources/OTMCore/AppModel.swift`, `SRC/Tests/OTMCoreTests/AppModelTests.swift`
- Modify: `SRC/Tests/OTMCoreTests/TestSupport.swift` (append `FakeJiraAPI`)

**Interfaces:**
- Consumes: everything from Tasks 2–7.
- Produces (used by the app shell in Tasks 11–12):
```swift
@MainActor public final class AppModel: ObservableObject {
    public init(configStore: ConfigStore, cache: IssueCache, tokenStore: TokenStore, scheduler: RefreshScheduler,
                makeClient: @escaping (URL, String, String) -> JiraAPI,
                now: @escaping () -> Date = Date.init, calendar: Calendar = .current)
    @Published public private(set) var renderState: RenderState
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue]
    @Published public private(set) var unmappedLabels: [Axis: [String]]
    public private(set) var configWasCorrupt: Bool
    public var storedToken: String? { get }
    public var isConfigured: Bool { get }
    public func makeAPI() throws -> JiraAPI
    public func refresh(_ trigger: RefreshTrigger) async
    public func updateConfig(_ config: AppConfig)        // persists + resumes scheduler + rebuilds
    public func setToken(_ token: String) throws
    public func setQuickSetting(key: String, value: JSONValue)
    public func saveDefaultView(yaw: Double, pitch: Double, zoom: Double)
    public func selectPreset(id: String)
    public func issueURL(key: String) -> URL?
    public static func bannerText(_ error: JiraError, syncedAt: Date?) -> String
}
```

- [ ] **Step 1: Add FakeJiraAPI to TestSupport**

Append to `Tests/OTMCoreTests/TestSupport.swift`:
```swift
final class FakeJiraAPI: JiraAPI {
    var searchResult: Result<SearchResult, JiraError> = .success(SearchResult(issues: []))
    var searchCalls: [(jql: String, fields: [String], cap: Int)] = []
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { 0 }
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        searchCalls.append((jql, fields, cap))
        return try searchResult.get()
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/OTMCoreTests/AppModelTests.swift`:
```swift
import Foundation
import Testing
@testable import OTMCore

@MainActor
@Suite struct AppModelTests {
    let dir = makeTempDir()
    let api = FakeJiraAPI()
    let tokens = InMemoryTokenStore(token: "tok")
    var clockNow = Date(timeIntervalSince1970: 1_800_000_000)

    func configuredConfig() -> AppConfig {
        var c = AppConfig()
        c.site = "acme.atlassian.net"
        c.email = "me@x.com"
        c.axes.value.mapping = .number(fieldId: "cf_value", min: 0, max: 10, invert: false)
        c.axes.effort.mapping = .number(fieldId: "cf_sp", min: 0, max: 10, invert: false)
        c.axes.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        return c
    }

    func makeModel(config: AppConfig? = nil) -> AppModel {
        if let config { try? ConfigStore(directory: dir).save(config) }
        let t = clockNow
        return AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                        scheduler: RefreshScheduler(now: { t }), makeClient: { [api] _, _, _ in api }, now: { t })
    }

    func issue(_ key: String, value: Double, sp: Double, priority: String) -> JiraIssue {
        JiraIssue(key: key, fields: ["summary": .string("S \(key)"), "cf_value": .number(value),
                                     "cf_sp": .number(sp), "priority": .object(["name": .string(priority)])])
    }

    @Test func notConfiguredDoesNotCallJira() async {
        let m = makeModel()
        #expect(!m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.isEmpty)
        #expect(m.renderState.configured == false)
    }

    @Test func successfulRefreshRendersAndCaches() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 10, sp: 0, priority: "Highest")]))
        let m = makeModel(config: configuredConfig())
        #expect(m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.count == 1)
        #expect(api.searchCalls[0].jql == JQLPreset.myOpenWork.jql)
        #expect(api.searchCalls[0].fields == ["summary", "status", "priority", "duedate", "cf_value", "cf_sp"])
        #expect(api.searchCalls[0].cap == 500)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
        #expect(m.renderState.tasks[0].rank == 1)
        #expect(m.renderState.status.syncedAt == clockNow)
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.configured)
        #expect(IssueCache(directory: dir).load()?.issues.count == 1)
    }

    @Test func secondRefreshFlagsChangedTasks() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low"),
                                                          issue("B-1", value: 5, sp: 5, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 9, sp: 2, priority: "Low"),
                                                          issue("B-1", value: 5, sp: 5, priority: "Low")]))
        await m.refresh(.manual)
        let changed = Dictionary(uniqueKeysWithValues: m.renderState.tasks.map { ($0.key, $0.changed) })
        #expect(changed == ["A-1": true, "B-1": false])
        m.setQuickSetting(key: "grid", value: .bool(false))
        #expect(m.renderState.tasks.allSatisfy { !$0.changed })
    }

    @Test func unauthorizedKeepsDataShowsBannerAndPausesFocus() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed · Open settings")
        #expect(m.renderState.tasks.count == 1)
        let calls = api.searchCalls.count
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls)
    }

    @Test func offlineShowsCachedDataTime() async {
        api.searchResult = .failure(.network("offline"))
        var cfg = configuredConfig()
        cfg.quick.refreshMinutes = 5
        try? IssueCache(directory: dir).save(CachedFetch(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                         fetchedAt: clockNow.addingTimeInterval(-600)))
        let m = makeModel(config: cfg)
        #expect(m.renderState.tasks.count == 1)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner?.hasPrefix("Offline · showing data from ") == true)
        #expect(m.renderState.tasks.count == 1)
    }

    @Test func badJqlShowsJiraMessage() async {
        api.searchResult = .failure(.badRequest("Field 'x' does not exist."))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "JQL error: Field 'x' does not exist.")
    }

    @Test func truncatedResultSetsNotice() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                 truncated: true, approximateTotal: 1240))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.truncated == "Showing 1 of 1240 · narrow your JQL")
    }

    @Test func zeroIssuesIsNotAnError() async {
        // Review Focus #3
        api.searchResult = .success(SearchResult(issues: []))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.tasks.isEmpty)
        #expect(m.renderState.status.banner == nil)
    }

    @Test func axisWithNoDataGetsBanner() async {
        api.searchResult = .success(SearchResult(issues: [JiraIssue(key: "A-1", fields: ["cf_sp": .number(1),
                                                                                       "priority": .object(["name": .string("Low")])])]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "No data for value field · check mapping in settings")
    }

    @Test func quickSettingAndDefaultViewPersist() {
        let m = makeModel(config: configuredConfig())
        m.setQuickSetting(key: "labelMode", value: .string("key"))
        m.saveDefaultView(yaw: -539.7, pitch: 95, zoom: 9)
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(saved.quick.labelMode == "key")
        #expect(abs(saved.view.yaw - -179.7) < 1e-9)
        #expect(saved.view.pitch == 80)
        #expect(saved.view.zoom == 3)
        #expect(m.renderState.settings.labelMode == "key")
    }

    @Test func corruptConfigIsFlagged() throws {
        try Data("{oops".utf8).write(to: ConfigStore(directory: dir).url)
        let m = makeModel()
        #expect(m.configWasCorrupt)
        #expect(m.config == AppConfig())
    }

    @Test func selectPresetAndIssueURL() {
        var cfg = configuredConfig()
        cfg.presets.append(JQLPreset(id: "team", name: "Team", jql: "project = T"))
        let m = makeModel(config: cfg)
        m.selectPreset(id: "team")
        #expect(m.config.activePresetId == "team")
        #expect(m.issueURL(key: "T-1")?.absoluteString == "https://acme.atlassian.net/browse/T-1")
    }

    @Test func unmappedLabelsAreReported() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Blocker")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.unmappedLabels[.urgency] == ["Blocker"])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter AppModelTests`
Expected: compile error (`AppModel` not found).

- [ ] **Step 4: Implement**

`Sources/OTMCore/AppModel.swift`:
```swift
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var renderState: RenderState = .empty
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue] = []
    @Published public private(set) var unmappedLabels: [Axis: [String]] = [:]
    public private(set) var configWasCorrupt = false

    private let configStore: ConfigStore
    private let cache: IssueCache
    private let tokenStore: TokenStore
    private let scheduler: RefreshScheduler
    private let makeClient: (URL, String, String) -> JiraAPI
    private let now: () -> Date
    private let calendar: Calendar

    private var token: String?
    private var tokenError = false
    private var syncedAt: Date?
    private var banner: String?
    private var truncated: String?
    private var lastMapped: [MappedTask] = []
    private var isRefreshing = false

    public static let issueCap = 500

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
        case .loaded(let c): config = c
        case .missing: config = AppConfig()
        case .corrupt: config = AppConfig(); configWasCorrupt = true
        }
        do { token = try tokenStore.read() } catch { tokenError = true }
        if let cached = cache.load() {
            issues = cached.issues
            syncedAt = cached.fetchedAt
        }
        if tokenError { banner = "Keychain access denied · re-enter your API token in settings" }
        rebuild(previous: nil)
    }

    public var storedToken: String? { token }

    public var isConfigured: Bool {
        config.siteURL != nil && !config.email.isEmpty && !(token ?? "").isEmpty && config.axes.isComplete
    }

    public func makeAPI() throws -> JiraAPI {
        guard let site = config.siteURL, !config.email.isEmpty, let token, !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, config.email, token)
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        guard !isRefreshing, isConfigured,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI() else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            let result = try await api.search(jql: config.activePreset.jql, fields: fetchFields(), cap: Self.issueCap)
            scheduler.recordSuccess()
            issues = result.issues
            let fetchedAt = now()
            syncedAt = fetchedAt
            banner = nil
            truncated = result.truncated
                ? "Showing \(result.issues.count) of \(result.approximateTotal.map(String.init) ?? "\(result.issues.count)+") · narrow your JQL"
                : nil
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt))
            rebuild(previous: previous)
        } catch let error as JiraError {
            scheduler.recordFailure(error)
            banner = Self.bannerText(error, syncedAt: syncedAt)
            rebuild(previous: nil)
        } catch {
            banner = "Refresh failed: \(error.localizedDescription)"
            rebuild(previous: nil)
        }
    }

    public func updateConfig(_ newConfig: AppConfig) {
        persist(newConfig)
        scheduler.resume()
    }

    public func setToken(_ newToken: String) throws {
        try tokenStore.write(newToken)
        token = newToken
        tokenError = false
        if banner?.hasPrefix("Keychain") == true { banner = nil }
        scheduler.resume()
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

    public func selectPreset(id: String) {
        guard config.presets.contains(where: { $0.id == id }) else { return }
        var c = config
        c.activePresetId = id
        updateConfig(c)
    }

    public func issueURL(key: String) -> URL? {
        config.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
    }

    public static func bannerText(_ error: JiraError, syncedAt: Date?) -> String {
        switch error {
        case .network:
            guard let syncedAt else { return "Offline · no cached data" }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Offline · showing data from \(f.string(from: syncedAt))"
        case .unauthorized: return "Jira sign-in failed · Open settings"
        case .rateLimited: return "Jira rate limit · retrying later"
        case .badRequest(let m): return "JQL error: \(m)"
        case .http(let code): return "Jira error \(code)"
        case .decoding: return "Unexpected response from Jira"
        case .notConfigured: return "Not configured · Open settings"
        }
    }

    // MARK: - Private

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = config.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func rebuild(previous: [String: MappedTask]?) {
        if let site = config.siteURL {
            lastMapped = AxisMapper.map(issues: issues, axes: config.axes, site: site, now: now(), calendar: calendar)
        } else {
            lastMapped = []
        }
        var unmapped: [Axis: [String]] = [:]
        var axisBanner: String?
        for axis in Axis.allCases {
            guard let mapping = config.axes[axis].mapping else { continue }
            let labels = AxisMapper.unmappedLabels(issues: issues, mapping: mapping)
            if !labels.isEmpty { unmapped[axis] = labels }
            if axisBanner == nil, !lastMapped.isEmpty, lastMapped.allSatisfy({ $0.missing[axis] }) {
                axisBanner = "No data for \(axis.rawValue) field · check mapping in settings"
            }
        }
        unmappedLabels = unmapped
        let status = RenderStatus(syncedAt: syncedAt, banner: banner ?? axisBanner, truncated: truncated)
        renderState = RenderStateBuilder.build(tasks: lastMapped, previous: previous, config: config,
                                               status: status, configured: isConfigured)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests && git commit -m "feat(otm): AppModel orchestration, banners and persistence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Chart JS pure modules (projection, fit, labels, color, state)

**Files:**
- Create: `SRC/chart/src/projection.js`, `fit.js`, `labels.js`, `color.js`, `state.js`
- Create: `SRC/chart/test/projection.test.js`, `fit.test.js`, `labels.test.js`, `color.test.js`, `state.test.js`
- Delete: `SRC/chart/test/smoke.test.js`

**Interfaces:**
- Consumes: `fixtures/render-state.json` (Task 5).
- Produces (ES module exports, used by Task 10):
  - `projection.js`: `DEFAULT_CAMERA = { D: 1.5, H: 0.55 }`, `FACTORY_VIEW = { yaw: -179.7, pitch: 33.9, zoom: 1 }`, `project(x, y, z, cam) -> {x, y, z, s, rx, ry}` (cam: `{yaw, pitch, D, H, fit?: {cx, cy, sc}}`), `normalizeYaw(a)`, `clampView(yaw, pitch, def, free) -> {yaw, pitch}`
  - `fit.js`: `fitPoints(tasks) -> number[][]`, `computeFit(points, cam, w, h, zoom = 1, pad = 24) -> {cx, cy, sc}`
  - `labels.js`: `truncate(s, n = 28)`, `brightness(t)`, `placeLabels(items, opts) -> {placed: [{item, rect, text}], hidden}`, `chooseCardCorner(obstacles, point, w, h, cw, ch, pad = 8) -> {x, y}`
  - `color.js`: `channel(v)`, `rgbColor(t, a = 1)`, `urgencyColor(u, a = 1)`, `taskColor(t, mode, a = 1)`
  - `state.js`: `validateState(s) -> string[]` (empty = valid)

- [ ] **Step 1: Write the failing tests**

`chart/test/projection.test.js`:
```js
import { describe, test, expect } from 'vitest';
import { project, normalizeYaw, clampView, DEFAULT_CAMERA, FACTORY_VIEW } from '../src/projection.js';

const cam = (yaw, pitch, fit) => ({ yaw, pitch, ...DEFAULT_CAMERA, fit });

describe('project', () => {
  test('floor center at yaw 0 pitch 0 projects to the fit center horizontally', () => {
    const p = project(0.5, 0.5, 0, cam(0, 0, { cx: 100, cy: 50, sc: 10 }));
    expect(p.x).toBeCloseTo(100);
    expect(p.z).toBeCloseTo(0);
  });
  test('higher urgency is drawn higher on screen', () => {
    const c = cam(-179.7, 33.9, { cx: 0, cy: 0, sc: 100 });
    expect(project(0.5, 0.5, 1, c).y).toBeLessThan(project(0.5, 0.5, 0, c).y);
  });
  test('nearer points get a larger perspective scale', () => {
    const c = cam(0, 0);
    expect(project(0.5, 0, 0, c).s).toBeGreaterThan(project(0.5, 1, 0, c).s);
  });
  test('factory view matches spec', () => {
    expect(FACTORY_VIEW).toEqual({ yaw: -179.7, pitch: 33.9, zoom: 1 });
  });
});

describe('normalizeYaw', () => {
  test.each([[-539.7, -179.7], [180, -180], [190, -170], [-45, -45]])('%f -> %f', (a, b) => {
    expect(normalizeYaw(a)).toBeCloseTo(b);
  });
});

describe('clampView', () => {
  const def = { yaw: -179.7, pitch: 33.9 };
  test('limited clamps yaw ±18 and pitch ±10 around default', () => {
    const a = clampView(0, 90, def, false), b = clampView(-400, -90, def, false);
    expect(a.yaw).toBeCloseTo(-161.7); expect(a.pitch).toBeCloseTo(43.9);
    expect(b.yaw).toBeCloseTo(-197.7); expect(b.pitch).toBeCloseTo(23.9);
  });
  test('free leaves yaw and clamps pitch ±89', () => {
    expect(clampView(1000, 120, def, true)).toEqual({ yaw: 1000, pitch: 89 });
  });
});
```

`chart/test/fit.test.js`:
```js
import { test, expect } from 'vitest';
import { computeFit, fitPoints } from '../src/fit.js';
import { project, DEFAULT_CAMERA } from '../src/projection.js';

const cam = { yaw: -179.7, pitch: 33.9, ...DEFAULT_CAMERA };

test('fitPoints includes floor corners and urgency axis even with zero tasks', () => {
  // Review Focus #3
  expect(fitPoints([])).toHaveLength(5);
  expect(fitPoints([{ value: 0.2, effort: 0.3, urgency: 0.4 }])).toContainEqual([0.2, 0.3, 0.4]);
});

test('all fitted points land inside the padded canvas', () => {
  const pts = fitPoints([{ value: 1, effort: 0, urgency: 1 }]);
  const fit = computeFit(pts, cam, 640, 420, 1, 24);
  for (const p of pts) {
    const q = project(p[0], p[1], p[2], { ...cam, fit });
    expect(q.x).toBeGreaterThanOrEqual(24 - 1e-6);
    expect(q.x).toBeLessThanOrEqual(640 - 24 + 1e-6);
    expect(q.y).toBeGreaterThanOrEqual(24 - 1e-6);
    expect(q.y).toBeLessThanOrEqual(420 - 24 + 1e-6);
  }
  expect(Number.isFinite(fit.sc)).toBe(true);
});

test('zoom multiplies the scale', () => {
  const pts = fitPoints([]);
  expect(computeFit(pts, cam, 640, 420, 2).sc).toBeCloseTo(computeFit(pts, cam, 640, 420, 1).sc * 2);
});
```

`chart/test/labels.test.js`:
```js
import { describe, test, expect } from 'vitest';
import { truncate, brightness, placeLabels, chooseCardCorner } from '../src/labels.js';

const measure = (s) => s.length * 6;
const task = (key, o = {}) => ({ key, summary: `Summary ${key}`, value: 0.5, effort: 0.5, urgency: 0.5, rank: null, ...o });
const item = (t, x, y) => ({ task: t, x, y, r: 6 });
const opts = (o = {}) => ({ width: 600, height: 400, mode: 'smart', selectedKey: null, measure, ...o });

describe('truncate/brightness', () => {
  test('truncates to 28 chars with ellipsis', () => {
    expect(truncate('a'.repeat(28))).toBe('a'.repeat(28));
    expect(truncate('a'.repeat(30))).toBe('a'.repeat(27) + '…');
  });
  test('brightness = (urgency + ease + value) / 3', () => {
    expect(brightness({ urgency: 1, effort: 0, value: 1 })).toBe(1);
    expect(brightness({ urgency: 0, effort: 1, value: 0 })).toBe(0);
  });
});

describe('placeLabels', () => {
  test('places label to the right when free', () => {
    const r = placeLabels([item(task('A'), 100, 100)], opts());
    expect(r.hidden).toBe(0);
    expect(r.placed[0].rect.x).toBe(110);
    expect(r.placed[0].text).toBe('Summary A');
  });
  test('key mode uses the issue key', () => {
    expect(placeLabels([item(task('A'), 100, 100)], opts({ mode: 'key' })).placed[0].text).toBe('A');
  });
  test('off mode labels only the selected task', () => {
    const r = placeLabels([item(task('A'), 100, 100), item(task('B'), 300, 300)], opts({ mode: 'off', selectedKey: 'B' }));
    expect(r.placed.map((p) => p.item.task.key)).toEqual(['B']);
  });
  test('ranked tasks win the contested spot', () => {
    const low = item(task('LOW', { value: 1, effort: 0, urgency: 1 }), 100, 100);
    const top = item(task('TOP', { rank: 1, value: 0, effort: 1, urgency: 0 }), 100, 100);
    const r = placeLabels([low, top], opts());
    expect(r.placed[0].item.task.key).toBe('TOP');
  });
  test('coincident dots never share a label rect and produce no NaN', () => {
    // Review Focus #4
    const r = placeLabels([item(task('A'), 200, 200), item(task('B'), 200, 200)], opts());
    const rects = r.placed.map((p) => p.rect);
    for (const rc of rects) expect(Object.values(rc).every(Number.isFinite)).toBe(true);
    if (rects.length === 2) {
      const [a, b] = rects;
      const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(overlap).toBe(false);
    }
    expect(r.placed.length + r.hidden).toBe(2);
  });
  test('label that fits nowhere is hidden in smart mode but forced in all mode', () => {
    const items = [item(task('A'), 3, 3), item(task('B'), 3, 3)];
    const tiny = { width: 20, height: 20 };
    expect(placeLabels(items, opts(tiny)).hidden).toBe(2);
    expect(placeLabels(items, opts({ ...tiny, mode: 'all' })).placed).toHaveLength(2);
  });
});

describe('chooseCardCorner', () => {
  test('avoids the corner holding the selected dot', () => {
    const c = chooseCardCorner([], { x: 590, y: 10 }, 600, 400, 230, 120);
    expect(c).toEqual({ x: 8, y: 8 });
  });
  test('prefers the corner with fewest obstacles', () => {
    const obstacles = [{ x: 10, y: 10, w: 50, h: 20 }, { x: 400, y: 20, w: 50, h: 20 }];
    const c = chooseCardCorner(obstacles, { x: 300, y: 200 }, 600, 400, 230, 120);
    expect(c).toEqual({ x: 600 - 230 - 8, y: 400 - 120 - 8 });
  });
});
```

`chart/test/color.test.js`:
```js
import { test, expect } from 'vitest';
import { channel, rgbColor, urgencyColor, taskColor } from '../src/color.js';

test('channel floor 55, ceiling 255, clamped', () => {
  expect(channel(0)).toBe(55);
  expect(channel(1)).toBe(255);
  expect(channel(2)).toBe(255);
  expect(channel(-1)).toBe(55);
});
test('urgent + valuable + easy is white #FFF', () => {
  expect(rgbColor({ urgency: 1, effort: 0, value: 1 })).toBe('rgba(255,255,255,1)');
});
test('thankless is dark #373737', () => {
  expect(rgbColor({ urgency: 0, effort: 1, value: 0 }, 0.5)).toBe('rgba(55,55,55,0.5)');
});
test('urgency mode endpoints', () => {
  expect(urgencyColor(0)).toBe('rgba(91,123,181,1)');
  expect(urgencyColor(1)).toBe('rgba(229,72,77,1)');
  expect(taskColor({ urgency: 1, effort: 0, value: 0 }, 'u')).toBe('rgba(229,72,77,1)');
});
```

`chart/test/state.test.js`:
```js
import { test, expect } from 'vitest';
import fixture from '../../fixtures/render-state.json';
import { validateState } from '../src/state.js';

test('shared Swift fixture is a valid RenderState (contract)', () => {
  expect(validateState(fixture)).toEqual([]);
});
test('detects broken payloads', () => {
  expect(validateState(null)).toContain('state is not an object');
  const bad = structuredClone(fixture);
  bad.tasks[0].value = 'x';
  delete bad.settings;
  const errs = validateState(bad);
  expect(errs).toContain('tasks[0].value must be a number in 0..1');
  expect(errs).toContain('settings missing');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rm chart/test/smoke.test.js && cd chart && npm test; cd ..`
Expected: FAIL, modules not found.

- [ ] **Step 3: Implement**

`chart/src/projection.js`:
```js
export const DEFAULT_CAMERA = { D: 1.5, H: 0.55 };
export const FACTORY_VIEW = { yaw: -179.7, pitch: 33.9, zoom: 1 };

/** World: x = value, y = effort (depth), z = urgency (up). Yaw around vertical axis, then pitch. */
export function project(x, y, z, cam) {
  const px = x - 0.5, py = z * cam.H - 0.2, pz = y - 0.5;
  const a = (cam.yaw * Math.PI) / 180, b = (cam.pitch * Math.PI) / 180;
  const X = px * Math.cos(a) - pz * Math.sin(a);
  const Z1 = px * Math.sin(a) + pz * Math.cos(a);
  const Y = py * Math.cos(b) + Z1 * Math.sin(b);
  const Z = -py * Math.sin(b) + Z1 * Math.cos(b);
  const s = cam.D / (cam.D + Z);
  const f = cam.fit || { cx: 0, cy: 0, sc: 1 };
  return { x: f.cx + X * s * f.sc, y: f.cy - Y * s * f.sc, z: Z, s, rx: X * s, ry: -Y * s };
}

export const normalizeYaw = (a) => ((((a + 180) % 360) + 360) % 360) - 180;

export function clampView(yaw, pitch, def, free) {
  if (free) return { yaw, pitch: Math.max(-89, Math.min(89, pitch)) };
  return {
    yaw: Math.max(def.yaw - 18, Math.min(def.yaw + 18, yaw)),
    pitch: Math.max(def.pitch - 10, Math.min(def.pitch + 10, pitch)),
  };
}
```

`chart/src/fit.js`:
```js
import { project } from './projection.js';

/** Floor corners, urgency axis top, and every task. */
export function fitPoints(tasks) {
  return [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 1, 1], ...tasks.map((t) => [t.value, t.effort, t.urgency])];
}

/** Scale/offset so all points fit inside the canvas at the current angle; zoom multiplies on top. */
export function computeFit(points, cam, w, h, zoom = 1, pad = 24) {
  const c = { ...cam, fit: { cx: 0, cy: 0, sc: 1 } };
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (const p of points) {
    const q = project(p[0], p[1], p[2], c);
    x0 = Math.min(x0, q.rx); x1 = Math.max(x1, q.rx);
    y0 = Math.min(y0, q.ry); y1 = Math.max(y1, q.ry);
  }
  const bw = Math.max(x1 - x0, 1e-6), bh = Math.max(y1 - y0, 1e-6);
  const sc = Math.max(1e-6, Math.min((w - 2 * pad) / bw, (h - 2 * pad) / bh)) * zoom;
  return { sc, cx: w / 2 - ((x0 + x1) / 2) * sc, cy: h / 2 - ((y0 + y1) / 2) * sc };
}
```

`chart/src/labels.js`:
```js
export const truncate = (s, n = 28) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
export const brightness = (t) => (t.urgency + (1 - t.effort) + t.value) / 3;
const overlaps = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/**
 * items: [{ task, x, y, r }]; opts: { width, height, mode: smart|all|key|off, selectedKey, measure(text) }
 * Order: selected, then ranked (1..3), then brightness. Tries right, left, above, below.
 */
export function placeLabels(items, { width, height, mode, selectedKey, measure }) {
  const dots = items.map((it) => ({ x: it.x - it.r, y: it.y - it.r, w: 2 * it.r, h: 2 * it.r, it }));
  const prio = (it) => (it.task.key === selectedKey ? 3 : 0) + (it.task.rank ? 2 - it.task.rank / 10 : 0);
  const order = items
    .filter((it) => mode !== 'off' || it.task.key === selectedKey)
    .sort((a, b) => prio(b) - prio(a) || brightness(b.task) - brightness(a.task));
  const placed = [];
  let hidden = 0;
  for (const it of order) {
    const t = it.task;
    const text = mode === 'key' ? t.key : truncate(t.summary);
    const bw = t.rank ? 16 : 0;
    const tw = measure(text) + bw + 8, th = 16, { x, y, r } = it;
    const cands = [
      { x: x + r + 4, y: y - th / 2 }, { x: x - r - 4 - tw, y: y - th / 2 },
      { x: x - tw / 2, y: y - r - th - 2 }, { x: x - tw / 2, y: y + r + 2 },
    ];
    let spot = null;
    for (const c of cands) {
      const R = { x: c.x, y: c.y, w: tw, h: th };
      if (R.x < 2 || R.y < 2 || R.x + R.w > width - 2 || R.y + R.h > height - 2) continue;
      if (mode !== 'all' && (placed.some((p) => overlaps(p.rect, R)) || dots.some((d) => d.it !== it && overlaps(d, R)))) continue;
      spot = R;
      break;
    }
    if (!spot && mode === 'all') spot = { x: cands[0].x, y: cands[0].y, w: tw, h: th };
    if (!spot) { hidden++; continue; }
    placed.push({ item: it, rect: spot, text });
  }
  return { placed, hidden };
}

/** Emptiest panel corner for the detail card that does not cover the selected dot. */
export function chooseCardCorner(obstacles, point, w, h, cw, ch, pad = 8) {
  const corners = [
    { x: w - cw - pad, y: pad }, { x: pad, y: pad },
    { x: w - cw - pad, y: h - ch - pad }, { x: pad, y: h - ch - pad },
  ];
  let best = corners[0], bestScore = Infinity;
  for (const c of corners) {
    const R = { x: c.x, y: c.y, w: cw, h: ch };
    if (point.x >= R.x - 10 && point.x <= R.x + R.w + 10 && point.y >= R.y - 10 && point.y <= R.y + R.h + 10) continue;
    const score = obstacles.filter((o) => overlaps(o, R)).length;
    if (score < bestScore) { best = c; bestScore = score; }
  }
  return best;
}
```

`chart/src/color.js`:
```js
const clamp01 = (v) => Math.min(1, Math.max(0, v));
export const channel = (v) => Math.round(55 + 200 * clamp01(v));
export const rgbColor = (t, a = 1) => `rgba(${channel(t.urgency)},${channel(1 - t.effort)},${channel(t.value)},${a})`;

export function urgencyColor(u, a = 1) {
  const s = [[91, 123, 181], [224, 160, 48], [229, 72, 77]];
  const v = clamp01(u);
  const t = v < 0.5 ? v / 0.5 : (v - 0.5) / 0.5;
  const A = v < 0.5 ? s[0] : s[1], B = v < 0.5 ? s[1] : s[2];
  const c = A.map((x, i) => Math.round(x + (B[i] - x) * t));
  return `rgba(${c[0]},${c[1]},${c[2]},${a})`;
}

export const taskColor = (t, mode, a = 1) => (mode === 'u' ? urgencyColor(t.urgency, a) : rgbColor(t, a));
```

`chart/src/state.js`:
```js
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const unit = (v) => typeof v === 'number' && v >= 0 && v <= 1;

/** Returns a list of problems; empty means the payload matches the Swift RenderState contract. */
export function validateState(s) {
  if (!isObj(s)) return ['state is not an object'];
  const e = [];
  if (!Array.isArray(s.tasks)) e.push('tasks must be an array');
  else s.tasks.forEach((t, i) => {
    if (typeof t.key !== 'string') e.push(`tasks[${i}].key must be a string`);
    if (typeof t.summary !== 'string') e.push(`tasks[${i}].summary must be a string`);
    for (const k of ['value', 'effort', 'urgency']) if (!unit(t[k])) e.push(`tasks[${i}].${k} must be a number in 0..1`);
    if (!isObj(t.missing)) e.push(`tasks[${i}].missing must be an object`);
    if (typeof t.score !== 'number') e.push(`tasks[${i}].score must be a number`);
  });
  if (!isObj(s.view)) e.push('view missing');
  else for (const k of ['yaw', 'pitch', 'zoom']) if (typeof s.view[k] !== 'number') e.push(`view.${k} must be a number`);
  if (!isObj(s.settings)) e.push('settings missing');
  if (!isObj(s.status)) e.push('status missing');
  if (!Array.isArray(s.presets)) e.push('presets must be an array');
  if (typeof s.configured !== 'boolean') e.push('configured must be a boolean');
  return e;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd chart && npm test; cd ..`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add chart && git commit -m "feat(otm): chart projection, fit, labels, color and state modules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Chart UI (render + panel controller + bridge)

**Files:**
- Create: `SRC/chart/src/render.js`, `SRC/chart/src/main.js`, `SRC/chart/public/index.html`, `SRC/chart/public/style.css`

**Interfaces:**
- Consumes: Task 9 modules; `fixtures/render-state.json` (dev mode only).
- Produces:
  - Global `window.otm.render(state)` (called by Swift with a `RenderState` JSON object).
  - Messages posted to `window.webkit.messageHandlers.otm.postMessage(msg)`; each `msg` is one of:
    `{type:'ready'}`, `{type:'openIssue', key}`, `{type:'refetch'}`, `{type:'hide'}`, `{type:'openSettings'}`,
    `{type:'selectPreset', id}`, `{type:'quickSetting', key, value}`, `{type:'saveDefaultView', yaw, pitch, zoom}`,
    `{type:'log', level, msg}`.
  - Build output `chart/dist/{index.html, style.css, chart.js}`.

Behavior to reproduce is in spec §4 and in `prototype/panel-prototype.html` (same constants). Differences from the prototype: no fake traffic lights (the native window has a title bar), data comes from `render(state)`, actions post to Swift, missing values draw hollow dots, banner and setup overlay exist.

- [ ] **Step 1: Create `public/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>onscreen-todo-matrix</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<div id="pn" tabindex="0">
  <div class="bar">
    <select id="preset" title="JQL preset"></select>
    <input id="q" placeholder="Search summary or key…" autocomplete="off" spellcheck="false">
    <div class="sp">
      <span id="sync"></span>
      <button id="bR" title="Refetch (⌘R)">⟳</button>
      <button id="bQ" title="Quick settings (Q)">◐</button>
      <button id="bS" title="Settings (⌘,)">⚙</button>
    </div>
  </div>
  <div id="banner"></div>
  <div class="vp">
    <canvas id="cv"></canvas>
    <div id="tip"></div>
    <div id="card"></div>
    <div id="toast"></div>
    <div id="setup"><p>Finish setup to see your Jira issues.</p><button id="bSetup">Open settings</button></div>
    <div id="qs">
      <h6>Quick settings <span class="lnk" id="qsX">✕</span></h6>
      <div class="r"><span>Labels</span><div class="seg" data-k="labelMode"><b data-v="smart">Smart</b><b data-v="all">All</b><b data-v="key">Key</b><b data-v="off">Off</b></div></div>
      <div class="r"><span>Stems</span><div class="seg" data-k="stemStyle"><b data-v="solid">Solid</b><b data-v="dotted">Dotted</b><b data-v="dashed">Dashed</b><b data-v="off">Off</b></div></div>
      <div class="r"><span>Stem opacity</span><input type="range" min="5" max="80" data-k="stemOpacity"></div>
      <div class="r"><span>Color</span><div class="seg" data-k="colorMode"><b data-v="rgb">RGB</b><b data-v="u">Urgency</b></div></div>
      <div class="r"><span>Grid</span><div class="seg" data-k="grid"><b data-v="true">On</b><b data-v="false">Off</b></div></div>
      <div class="r"><span>Zone names</span><div class="seg" data-k="zoneNames"><b data-v="true">On</b><b data-v="false">Off</b></div></div>
      <div class="sub">
        <div class="r"><span>Rotation</span><div class="seg" data-k="rotation"><b data-v="limited">Limited</b><b data-v="free">Free</b></div></div>
        <div class="r"><span>Zoom</span><input type="range" min="50" max="300" data-k="zoom"></div>
        <div class="r"><span id="angTxt" class="mono"></span><span><span class="lnk" id="qsPin">Set default</span> · <span class="lnk" id="qsRst">Reset</span></span></div>
      </div>
      <div class="sub">
        <div class="r"><span>Panel opacity</span><input type="range" min="40" max="100" data-k="panelOpacity"></div>
        <div class="r"><span>Always on top</span><div class="seg" data-k="alwaysOnTop"><b data-v="true">On</b><b data-v="false">Off</b></div></div>
        <div class="r"><span>Auto refresh</span><div class="seg" data-k="refreshMinutes"><b data-v="1">1m</b><b data-v="5">5m</b><b data-v="15">15m</b><b data-v="0">Off</b></div></div>
      </div>
      <div class="foot">Jira, JQL &amp; field mapping → full settings (⌘,)</div>
    </div>
  </div>
  <div id="next"></div>
</div>
<script src="chart.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create `public/style.css`**

```css
html, body { margin: 0; height: 100%; overflow: hidden; background: #0f1420; color: #9aa6bd;
  font: 11px -apple-system, BlinkMacSystemFont, sans-serif; -webkit-user-select: none; user-select: none; }
#pn { height: 100vh; display: flex; flex-direction: column; outline: none; background: #0f1420; }
.bar { height: 30px; flex: none; display: flex; align-items: center; gap: 8px; padding: 0 10px; background: #131a28; border-bottom: 1px solid #1e2636; }
#preset { background: #1e2636; color: #c9d2e3; border: none; border-radius: 10px; padding: 2px 6px; font-size: 10.5px; outline: none; }
#q { display: none; background: #1e2636; border: 1px solid #3b82f6; color: #e8ecf4; border-radius: 5px; padding: 2px 6px; font-size: 11px; width: 170px; outline: none; }
.bar .sp { margin-left: auto; display: flex; gap: 10px; align-items: center; }
.bar button { background: none; border: none; color: #9aa6bd; cursor: pointer; font-size: 13px; padding: 0 2px; }
.bar button:hover { color: #e8ecf4; }
#banner { display: none; flex: none; padding: 4px 10px; background: #3a2a12; color: #f4c542; border-bottom: 1px solid #5a4218; font-size: 11px; cursor: default; }
#banner.link { cursor: pointer; text-decoration: underline; }
.vp { flex: 1; position: relative; min-height: 0; }
#cv { display: block; width: 100%; height: 100%; cursor: grab; }
#tip { position: absolute; pointer-events: none; background: #1e2636; color: #e8ecf4; padding: 4px 7px; border-radius: 4px; display: none; white-space: nowrap; z-index: 3; }
#card { position: absolute; display: none; background: #1e2636; color: #e8ecf4; border-radius: 8px; padding: 9px 11px; line-height: 1.55; width: 230px; box-shadow: 0 6px 20px rgba(0,0,0,.55); z-index: 4; border: 1px solid #2b3550; }
#card .k { color: #9aa6bd; font-size: 10px; }
#card .row { display: flex; justify-content: space-between; color: #9aa6bd; font-size: 10px; }
#card .row b { color: #e8ecf4; font-weight: 500; }
#card .open { display: inline-block; margin-top: 6px; background: #3b82f6; color: #fff; padding: 2px 8px; border-radius: 4px; cursor: pointer; }
#toast { position: absolute; left: 50%; bottom: 14px; transform: translateX(-50%); background: #e8ecf4; color: #0f1420; padding: 5px 10px; border-radius: 6px; opacity: 0; transition: opacity .2s; pointer-events: none; z-index: 5; white-space: nowrap; }
#setup { position: absolute; inset: 0; display: none; flex-direction: column; align-items: center; justify-content: center; gap: 8px; background: rgba(15,20,32,.85); color: #e8ecf4; font-size: 13px; z-index: 6; }
#setup button { background: #3b82f6; color: #fff; border: none; border-radius: 5px; padding: 5px 12px; cursor: pointer; }
#qs { position: absolute; top: 8px; right: 8px; width: 250px; background: rgba(22,28,42,.97); border: 1px solid #2b3550; border-radius: 9px; padding: 10px 12px; box-shadow: 0 8px 24px rgba(0,0,0,.55); z-index: 7; display: none; color: #c9d2e3; }
#qs h6 { margin: 0 0 8px; font-size: 11px; color: #e8ecf4; display: flex; justify-content: space-between; }
#qs .r { display: flex; align-items: center; justify-content: space-between; margin: 7px 0; gap: 8px; }
#qs .r > span { color: #9aa6bd; white-space: nowrap; }
#qs input[type=range] { width: 110px; accent-color: #3b82f6; }
#qs .sub { border-top: 1px solid #2b3550; margin-top: 8px; padding-top: 8px; }
#qs .foot { margin-top: 6px; color: #6b7895; font-size: 10px; }
.seg { display: flex; background: #0f1420; border-radius: 6px; padding: 2px; gap: 2px; }
.seg b { font-weight: 500; padding: 2px 7px; border-radius: 4px; cursor: pointer; color: #9aa6bd; font-size: 10.5px; }
.seg b.on { background: #3b82f6; color: #fff; }
.lnk { color: #8fb8ff; cursor: pointer; } .lnk:hover { text-decoration: underline; }
.mono { font: 10px ui-monospace, Menlo, monospace; }
#next { flex: none; padding: 6px 10px; border-top: 1px solid #1e2636; font-size: 10.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#next b { color: #f4c542; } #next span { cursor: pointer; } #next span:hover { color: #e8ecf4; }
```

- [ ] **Step 3: Create `src/render.js`**

```js
import { project } from './projection.js';
import { taskColor, brightness } from './color.js';
import { placeLabels } from './labels.js';

const ZONES = [
  [0.5, 1, 0, 0.5, 'rgba(70,180,120,.16)', 'Quick wins', true],
  [0.5, 1, 0.5, 1, 'rgba(90,130,220,.12)', 'Major projects', true],
  [0, 0.5, 0, 0.5, 'rgba(160,160,160,.04)', 'Fill-ins', false],
  [0, 0.5, 0.5, 1, 'rgba(200,90,90,.05)', 'Thankless', false],
];
const STEM_DASH = { solid: [], dotted: [0.5, 3.5], dashed: [4, 3] };
const FONT = '11px -apple-system, BlinkMacSystemFont, sans-serif';

/**
 * Draws the whole scene and returns hit-test data.
 * o = { w, h, tasks, cam, settings, selectedKey, matches(task) -> bool, pulses: Map<key, startMs>, now }
 * returns { proj: [{t, p, f, r, fade}], labels: [{item, rect, text}], hidden }
 */
export function drawScene(g, o) {
  const { w, h, cam, settings: S } = o;
  const P = (x, y, z) => project(x, y, z, cam);
  g.clearRect(0, 0, w, h);

  const line = (a, b, c, lw = 1, dash) => {
    g.strokeStyle = c; g.lineWidth = lw; g.setLineDash(dash || []);
    g.lineCap = dash && dash[0] < 2 ? 'round' : 'butt';
    g.beginPath(); g.moveTo(a.x, a.y); g.lineTo(b.x, b.y); g.stroke();
    g.setLineDash([]); g.lineCap = 'butt';
  };
  const poly = (ps, fill) => {
    g.fillStyle = fill; g.beginPath();
    ps.forEach((p, i) => (i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)));
    g.closePath(); g.fill();
  };
  const txt = (p, s, c, align = 'center') => {
    g.fillStyle = c; g.font = FONT; g.textAlign = align; g.textBaseline = 'middle';
    g.fillText(s, Math.max(45, Math.min(w - 45, p.x)), p.y);
  };

  for (const [x0, x1, y0, y1, fill, name, hi] of ZONES) {
    poly([P(x0, y0, 0), P(x1, y0, 0), P(x1, y1, 0), P(x0, y1, 0)], fill);
    if (S.zoneNames) txt(P((x0 + x1) / 2, (y0 + y1) / 2, 0), name, hi ? 'rgba(232,236,244,.5)' : 'rgba(232,236,244,.2)');
  }
  if (S.grid) {
    for (let i = 0; i <= 10; i++) {
      const c = i === 5 ? 'rgba(255,255,255,.28)' : 'rgba(255,255,255,.10)';
      line(P(i / 10, 0, 0), P(i / 10, 1, 0), c);
      line(P(0, i / 10, 0), P(1, i / 10, 0), c);
    }
  }
  const O = P(0, 1, 0);
  line(O, P(1, 1, 0), 'rgba(90,140,255,.85)', 2);
  line(O, P(0, 0, 0), 'rgba(80,220,120,.85)', 2);
  line(O, P(0, 1, 1), 'rgba(255,80,80,.85)', 2);
  txt(P(1.12, 1, 0), 'Value', '#7aa2ff');
  txt(P(0, -0.14, 0), '← Less effort', '#6ee08f');
  txt(P(0, 1, 1.1), '↑ Urgency', '#ff7070');

  const proj = o.tasks
    .map((t) => ({ t, p: P(t.value, t.effort, t.urgency), f: P(t.value, t.effort, 0) }))
    .sort((a, b) => b.p.z - a.p.z);
  const zs = proj.map((m) => m.p.z);
  const zmin = Math.min(...zs), zmax = Math.max(...zs);
  for (const m of proj) {
    m.fade = (1 - (0.55 * (m.p.z - zmin)) / (zmax - zmin || 1)) * (o.matches(m.t) ? 1 : 0.12);
    m.r = 6 * m.p.s;
  }

  for (const m of proj) {
    g.globalAlpha = m.fade;
    g.fillStyle = 'rgba(0,0,0,.3)';
    g.beginPath(); g.ellipse(m.f.x, m.f.y, 4 * m.f.s, 1.8 * m.f.s, 0, 0, 7); g.fill();
    if (S.stemStyle !== 'off') {
      line(m.f, m.p, taskColor(m.t, S.colorMode, S.stemOpacity / 100), S.stemStyle === 'dotted' ? 1.6 : 1.2, STEM_DASH[S.stemStyle]);
    }
    g.globalAlpha = 1;
  }

  for (const m of proj) {
    const t = m.t, r = m.r, hollow = t.missing && (t.missing.value || t.missing.effort || t.missing.urgency);
    g.globalAlpha = m.fade;
    if (t.fire) { g.shadowColor = '#ff3b3b'; g.shadowBlur = 18; }
    g.beginPath(); g.arc(m.p.x, m.p.y, r, 0, 7);
    if (hollow) {
      g.fillStyle = 'rgba(15,20,32,.9)'; g.fill(); g.shadowBlur = 0;
      g.strokeStyle = taskColor(t, S.colorMode); g.lineWidth = 2; g.stroke();
    } else {
      g.fillStyle = taskColor(t, S.colorMode); g.fill(); g.shadowBlur = 0;
      g.strokeStyle = 'rgba(255,255,255,.55)'; g.lineWidth = 1; g.stroke();
    }
    const pt = o.pulses.get(t.key);
    if (pt != null) {
      const k = (o.now - pt) / 1600;
      if (k < 1) { g.strokeStyle = `rgba(244,197,66,${1 - k})`; g.lineWidth = 2; g.beginPath(); g.arc(m.p.x, m.p.y, r + 4 + k * 14, 0, 7); g.stroke(); }
    }
    if (o.selectedKey === t.key) { g.strokeStyle = '#3b82f6'; g.lineWidth = 2.5; g.beginPath(); g.arc(m.p.x, m.p.y, r + 4, 0, 7); g.stroke(); }
    g.globalAlpha = 1;
  }

  g.font = FONT;
  const items = proj.filter((m) => o.matches(m.t)).map((m) => ({ task: m.t, x: m.p.x, y: m.p.y, r: m.r, fade: m.fade }));
  const { placed, hidden } = placeLabels(items, {
    width: w, height: h, mode: S.labelMode, selectedKey: o.selectedKey, measure: (s) => g.measureText(s).width,
  });
  for (const { item, rect, text } of placed) {
    const t = item.task;
    g.globalAlpha = item.fade;
    g.fillStyle = 'rgba(15,20,32,.6)'; g.fillRect(rect.x, rect.y, rect.w, rect.h);
    let tx = rect.x + 4;
    if (t.rank) {
      g.fillStyle = '#f4c542'; g.beginPath(); g.arc(tx + 6, rect.y + 8, 6, 0, 7); g.fill();
      g.fillStyle = '#0f1420'; g.font = 'bold 9px -apple-system, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(String(t.rank), tx + 6, rect.y + 8.5); tx += 16; g.font = FONT;
    }
    g.fillStyle = o.selectedKey === t.key ? '#8fb8ff' : t.fire ? '#ff9a9a' : `rgba(232,236,244,${0.35 + 0.65 * brightness(t)})`;
    g.textAlign = 'left'; g.textBaseline = 'middle'; g.fillText(text, tx, rect.y + 8.5);
    g.globalAlpha = 1;
  }
  return { proj, labels: placed, hidden };
}
```

- [ ] **Step 4: Create `src/main.js`**

```js
import { computeFit, fitPoints } from './fit.js';
import { DEFAULT_CAMERA, FACTORY_VIEW, clampView, normalizeYaw } from './projection.js';
import { drawScene } from './render.js';
import { chooseCardCorner } from './labels.js';
import { validateState } from './state.js';
import sample from '../../fixtures/render-state.json';

const $ = (id) => document.getElementById(id);
const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.otm;
const post = (m) => (native ? native.postMessage(m) : console.log('[otm→native]', m));

const st = {
  state: null, tasks: [], sel: null, query: '', yaw: FACTORY_VIEW.yaw, pitch: FACTORY_VIEW.pitch, zoom: 1,
  fit: { cx: 0, cy: 0, sc: 1 }, scene: { proj: [], labels: [] }, pulses: new Map(), glide: null, viewInit: false,
};
const cv = $('cv');
let g, w = 0, h = 0, raf = 0;

const S = () => st.state.settings;
const def = () => ({ yaw: st.state.view.yaw, pitch: st.state.view.pitch });
const cam = () => ({ yaw: st.yaw, pitch: st.pitch, ...DEFAULT_CAMERA, fit: st.fit });
const matches = (t) => !st.query || `${t.key} ${t.summary}`.toLowerCase().includes(st.query);
const byScore = () => [...st.tasks].sort((a, b) => b.score - a.score || (a.key < b.key ? -1 : 1));

function setupCanvas() {
  const dpr = window.devicePixelRatio || 1;
  w = cv.clientWidth; h = cv.clientHeight;
  cv.width = Math.max(1, w * dpr); cv.height = Math.max(1, h * dpr);
  g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function displayTasks() {
  if (!st.glide) return st.tasks;
  const k = Math.min(1, (performance.now() - st.glide.start) / 700), e = 1 - Math.pow(1 - k, 3);
  if (k >= 1) { st.glide = null; return st.tasks; }
  return st.tasks.map((t) => {
    const f = st.glide.from.get(t.key);
    if (!f) return t;
    return { ...t, value: f.value + (t.value - f.value) * e, effort: f.effort + (t.effort - f.effort) * e, urgency: f.urgency + (t.urgency - f.urgency) * e };
  });
}

function refitNow() { st.fit = computeFit(fitPoints(st.tasks), cam(), w, h, st.zoom); }
function refitAnimated() {
  const a = { ...st.fit }, b = computeFit(fitPoints(st.tasks), cam(), w, h, st.zoom), t0 = performance.now();
  const step = (now) => {
    const k = Math.min(1, (now - t0) / 220), e = 1 - Math.pow(1 - k, 3);
    st.fit = { sc: a.sc + (b.sc - a.sc) * e, cx: a.cx + (b.cx - a.cx) * e, cy: a.cy + (b.cy - a.cy) * e };
    draw();
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

function draw() {
  if (!g || !st.state) return;
  const now = performance.now();
  st.scene = drawScene(g, {
    w, h, tasks: displayTasks(), cam: cam(), settings: S(), selectedKey: st.sel, matches, pulses: st.pulses, now,
  });
  placeCard();
  $('angTxt').textContent = `${normalizeYaw(st.yaw).toFixed(1)}° / ${st.pitch.toFixed(1)}° · ${st.zoom.toFixed(2)}×`;
  const animating = st.glide || [...st.pulses.values()].some((t) => now - t < 1600);
  if (animating && !raf) raf = requestAnimationFrame(() => { raf = 0; draw(); });
}

// ---------- state from Swift ----------
function render(state) {
  const errs = validateState(state);
  if (errs.length) { post({ type: 'log', level: 'error', msg: `invalid state: ${errs.join('; ')}` }); return; }
  const prev = new Map(st.tasks.map((t) => [t.key, t]));
  st.state = state;
  if (!st.viewInit) { st.yaw = state.view.yaw; st.pitch = state.view.pitch; st.zoom = state.view.zoom; st.viewInit = true; }
  const v = clampView(st.yaw, st.pitch, def(), state.settings.rotation === 'free');
  st.yaw = v.yaw; st.pitch = v.pitch;
  st.tasks = state.tasks;
  const from = new Map();
  const now = performance.now();
  for (const t of state.tasks) {
    if (t.changed && prev.has(t.key)) { from.set(t.key, prev.get(t.key)); st.pulses.set(t.key, now); }
  }
  if (from.size) st.glide = { from, start: now };
  if (st.sel && !st.tasks.some((t) => t.key === st.sel)) select(null);
  renderChrome();
  refitNow();
  if (st.sel) select(st.sel, false);
  draw();
}

function renderChrome() {
  const s = st.state;
  const sel = $('preset');
  sel.innerHTML = '';
  for (const p of s.presets) {
    const o = document.createElement('option'); o.value = p.id; o.textContent = p.name;
    if (p.id === s.activePresetId) o.selected = true;
    sel.appendChild(o);
  }
  const b = $('banner');
  const text = s.status.banner || s.status.truncated;
  b.style.display = text ? 'block' : 'none';
  b.textContent = text || '';
  b.className = s.status.banner && /settings/i.test(s.status.banner) ? 'link' : '';
  $('setup').style.display = s.configured ? 'none' : 'flex';
  const top = byScore().filter((t) => t.rank).slice(0, 3);
  const next = $('next');
  if (!s.tasks.length) next.innerHTML = s.configured ? '<b>Next:</b> No issues match this filter' : '';
  else next.innerHTML = '<b>Next:</b> ' + top.map((t) => `<span data-k="${encodeURIComponent(t.key)}">${t.rank}. ${escapeHTML(t.summary)}</span>`).join(' &nbsp;·&nbsp; ');
  next.querySelectorAll('span').forEach((el) => { el.onclick = () => select(decodeURIComponent(el.dataset.k)); });
  syncQS();
  updateSync();
}

const escapeHTML = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function updateSync() {
  const at = st.state && st.state.status.syncedAt ? Date.parse(st.state.status.syncedAt) : NaN;
  if (Number.isNaN(at)) { $('sync').textContent = 'not synced'; return; }
  const s = Math.round((Date.now() - at) / 1000);
  $('sync').textContent = s < 5 ? 'synced just now' : s < 60 ? `synced ${s}s ago` : s < 3600 ? `synced ${Math.round(s / 60)}m ago` : `synced ${Math.round(s / 3600)}h ago`;
}
setInterval(updateSync, 1000);

// ---------- selection / card ----------
function select(key, redraw = true) {
  st.sel = key;
  const card = $('card');
  const t = key && st.tasks.find((x) => x.key === key);
  if (!t) { card.style.display = 'none'; st.sel = null; if (redraw) draw(); return; }
  const f = (v) => (v * 5).toFixed(1);
  card.innerHTML = `<div class="k">${escapeHTML(t.key)} · ${escapeHTML(t.status || '')}</div><b>${escapeHTML(t.summary)}</b>
    <div class="row" style="margin-top:4px"><span>Value <b>${f(t.value)}</b></span><span>Ease <b>${f(1 - t.effort)}</b></span><span>Urgency <b>${f(t.urgency)}</b></span></div>
    <div class="row"><span>Priority <b>${escapeHTML(t.priority || '—')}</b></span><span>Due <b>${escapeHTML(t.due || '—')}</b></span>${t.rank ? `<span style="color:#f4c542">#${t.rank} next</span>` : ''}</div>
    <span class="open" id="openBtn">⌘O Open in Jira ↗</span>`;
  card.style.display = 'block';
  $('openBtn').onclick = openIssue;
  if (redraw) draw();
}

function placeCard() {
  if (!st.sel) return;
  const m = st.scene.proj.find((x) => x.t.key === st.sel);
  if (!m) return;
  const card = $('card');
  const obstacles = [...st.scene.labels.map((l) => l.rect), ...st.scene.proj.map((x) => ({ x: x.p.x - x.r, y: x.p.y - x.r, w: 2 * x.r, h: 2 * x.r }))];
  const c = chooseCardCorner(obstacles, m.p, w, h, card.offsetWidth || 230, card.offsetHeight || 110);
  card.style.left = `${c.x}px`; card.style.top = `${c.y}px`;
}

function openIssue() {
  if (!st.sel) return toast('Select a task first (click a dot or press Tab)');
  post({ type: 'openIssue', key: st.sel });
}

function step(dir) {
  const order = byScore().filter(matches);
  if (!order.length) return;
  const i = order.findIndex((t) => t.key === st.sel);
  select(order[(i + dir + order.length) % order.length].key);
}

function toast(s) {
  const t = $('toast'); t.textContent = s; t.style.opacity = 1;
  clearTimeout(t._h); t._h = setTimeout(() => { t.style.opacity = 0; }, 2200);
}

// ---------- search ----------
const q = $('q');
function openSearch() { q.style.display = 'inline-block'; q.focus(); q.select(); }
function closeSearch() { q.value = ''; st.query = ''; q.style.display = 'none'; $('pn').focus(); draw(); }
q.oninput = () => { st.query = q.value.toLowerCase().trim(); draw(); };
q.onkeydown = (e) => {
  if (e.key === 'Escape') { e.preventDefault(); closeSearch(); }
  if (e.key === 'Enter') { e.preventDefault(); const m = byScore().find(matches); if (m) select(m.key); $('pn').focus(); }
};

// ---------- quick settings ----------
const qs = $('qs');
function toggleQS() { qs.style.display = qs.style.display === 'block' ? 'none' : 'block'; syncQS(); }
function syncQS() {
  if (!st.state) return;
  qs.querySelectorAll('.seg').forEach((sg) => {
    const v = String(S()[sg.dataset.k]);
    sg.querySelectorAll('b').forEach((b) => b.classList.toggle('on', b.dataset.v === v));
  });
  qs.querySelectorAll('input[type=range]').forEach((i) => { i.value = i.dataset.k === 'zoom' ? Math.round(st.zoom * 100) : S()[i.dataset.k]; });
}
function setSetting(key, value) {
  st.state.settings = { ...S(), [key]: value };
  post({ type: 'quickSetting', key, value });
  if (key === 'rotation') {
    const v = clampView(st.yaw, st.pitch, def(), value === 'free'); st.yaw = v.yaw; st.pitch = v.pitch; refitAnimated();
  }
  syncQS(); draw();
}
const parseSeg = (key, v) => (['grid', 'zoneNames', 'alwaysOnTop'].includes(key) ? v === 'true' : key === 'refreshMinutes' ? Number(v) : v);
qs.querySelectorAll('.seg b').forEach((b) => { b.onclick = () => setSetting(b.parentNode.dataset.k, parseSeg(b.parentNode.dataset.k, b.dataset.v)); });
qs.querySelectorAll('input[type=range]').forEach((i) => {
  i.oninput = () => {
    if (i.dataset.k === 'zoom') { st.zoom = Number(i.value) / 100; refitNow(); draw(); return; }
    setSetting(i.dataset.k, Number(i.value));
  };
});
$('qsX').onclick = toggleQS;
$('qsPin').onclick = () => {
  const view = { yaw: normalizeYaw(st.yaw), pitch: Math.max(-80, Math.min(80, st.pitch)), zoom: st.zoom };
  st.state.view = view;
  post({ type: 'saveDefaultView', ...view });
  toast('Current angle and zoom saved as default');
};
$('qsRst').onclick = () => {
  st.yaw = FACTORY_VIEW.yaw; st.pitch = FACTORY_VIEW.pitch; st.zoom = FACTORY_VIEW.zoom;
  st.state.view = { ...FACTORY_VIEW };
  post({ type: 'saveDefaultView', ...FACTORY_VIEW });
  refitAnimated(); syncQS();
};

// ---------- top bar ----------
$('bR').onclick = () => post({ type: 'refetch' });
$('bQ').onclick = toggleQS;
$('bS').onclick = () => post({ type: 'openSettings' });
$('bSetup').onclick = () => post({ type: 'openSettings' });
$('banner').onclick = () => { if ($('banner').className === 'link') post({ type: 'openSettings' }); };
$('preset').onchange = (e) => post({ type: 'selectPreset', id: e.target.value });

// ---------- keyboard ----------
window.addEventListener('keydown', (e) => {
  if (!st.state || document.activeElement === q || document.activeElement === $('preset')) return;
  const m = e.metaKey || e.ctrlKey, k = e.key.toLowerCase();
  if (e.key === 'Tab') { e.preventDefault(); return step(e.shiftKey ? -1 : 1); }
  if (e.key === 'Escape') {
    e.preventDefault();
    if (qs.style.display === 'block') return toggleQS();
    if (st.sel) return select(null);
    return post({ type: 'hide' });
  }
  if ((m && k === 'o') || e.key === 'Enter') { e.preventDefault(); return openIssue(); }
  if (m && k === 'r') { e.preventDefault(); return post({ type: 'refetch' }); }
  if (m && k === 'f') { e.preventDefault(); return openSearch(); }
  if (m && e.key === ',') { e.preventDefault(); return post({ type: 'openSettings' }); }
  if (!m && k === 'q') return toggleQS();
  if (!m && k === 'f') { setSetting('rotation', S().rotation === 'free' ? 'limited' : 'free'); toast(S().rotation === 'free' ? 'Free rotation' : 'Limited rotation'); }
});

// ---------- mouse ----------
let drag = null;
const hit = (ev) => {
  const r = cv.getBoundingClientRect(), mx = ev.clientX - r.left, my = ev.clientY - r.top;
  let best = null, bd = 14;
  for (const m of st.scene.proj) { const d = Math.hypot(m.p.x - mx, m.p.y - my); if (d < bd && matches(m.t)) { bd = d; best = m; } }
  return best;
};
cv.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY, yaw: st.yaw, pitch: st.pitch, moved: false }; $('pn').focus(); });
window.addEventListener('mousemove', (e) => {
  if (!drag || !st.state) return;
  if (Math.abs(e.clientX - drag.x) + Math.abs(e.clientY - drag.y) > 3) drag.moved = true;
  if (!drag.moved) return;
  const v = clampView(drag.yaw + (e.clientX - drag.x) * 0.3, drag.pitch + (e.clientY - drag.y) * 0.3, def(), S().rotation === 'free');
  st.yaw = v.yaw; st.pitch = v.pitch; draw();
});
window.addEventListener('mouseup', (e) => {
  if (!drag) return;
  const d = drag; drag = null;
  if (d.moved) return refitAnimated();
  if (e.target === cv) { const m = hit(e); select(m ? m.t.key : null); }
});
cv.addEventListener('dblclick', () => { if (!st.state) return; st.yaw = st.state.view.yaw; st.pitch = st.state.view.pitch; st.zoom = st.state.view.zoom; refitAnimated(); syncQS(); });
cv.addEventListener('wheel', (e) => { e.preventDefault(); st.zoom = Math.max(0.5, Math.min(3, st.zoom * Math.exp(-e.deltaY * 0.0015))); refitNow(); draw(); syncQS(); }, { passive: false });
cv.addEventListener('mousemove', (e) => {
  const tip = $('tip');
  if (drag) { tip.style.display = 'none'; return; }
  const m = hit(e);
  if (m && m.t.key !== st.sel) {
    tip.style.display = 'block'; tip.style.left = `${m.p.x + 12}px`; tip.style.top = `${m.p.y + 10}px`;
    tip.textContent = `${m.t.key} · ${m.t.summary}`; cv.style.cursor = 'pointer';
  } else { tip.style.display = 'none'; cv.style.cursor = 'grab'; }
});
cv.addEventListener('mouseleave', () => { $('tip').style.display = 'none'; });
window.addEventListener('resize', () => { setupCanvas(); refitNow(); draw(); });
window.addEventListener('error', (e) => post({ type: 'log', level: 'error', msg: String(e.message) }));

// ---------- boot ----------
setupCanvas();
window.otm = { render };
post({ type: 'ready' });
if (!native) setTimeout(() => render(structuredClone(sample)), 0);
```

- [ ] **Step 5: Build and check in a browser (dev mode uses the fixture)**

Run: `cd chart && npm run build && npm test && cd .. && ls chart/dist`
Expected: `chart.js index.html style.css`; tests still pass.

Then open `chart/dist/index.html` in the built-in browser (or `open chart/dist/index.html`). Verify by eye and record the result in the task report:
1. Three dots from the fixture: SEC-5 and PAY-412 bright with gold ① ②; DATA-19 drawn **hollow** (its effort is missing).
2. Next strip: `Next: 1. Rotate leaked Stripe API key · 2. Refund webhook returns 500 for partial refunds`.
3. PAY-412 pulses gold once (it has `changed: true`).
4. Tab selects SEC-5, the detail card appears in a corner without covering the dot; Esc deselects.
5. Q opens quick settings; switching Stems to Solid changes the stems; Labels → Key shows keys.
6. Drag rotates within limits; double-click resets; wheel zooms.
7. Browser console shows `[otm→native] {type: "ready"}` and no errors.

- [ ] **Step 6: Commit**

```bash
git add chart && git commit -m "feat(otm): chart panel UI, rendering and native bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: macOS app shell (status item, floating panel, web view bridge, hotkey)

**Files:**
- Modify (replace): `SRC/Sources/OnscreenTodoMatrix/main.swift`
- Create: `SRC/Sources/OnscreenTodoMatrix/AppDelegate.swift`, `PanelController.swift`, `ChartWebView.swift`, `LoginItem.swift`, `Shortcuts.swift`
- Create (temporary stub, replaced in Task 12): `SRC/Sources/OnscreenTodoMatrix/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `AppModel` and friends (Task 8), chart bridge messages (Task 10), `chart/dist` (built by Task 10).
- Produces: `final class SettingsWindowController { init(model: AppModel, onDone: @escaping () -> Void); func show() }` (stub here, full in Task 12); `KeyboardShortcuts.Name.togglePanel`; `enum LoginItem { static var isEnabled: Bool; static func set(_ on: Bool) throws }`.

No unit tests in this task (thin UI shell; OTMCore is fully tested). Verification is a build plus a manual launch.

- [ ] **Step 1: Write the shell files**

`Sources/OnscreenTodoMatrix/main.swift` (replace):
```swift
import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    app.run()
}
```

`Sources/OnscreenTodoMatrix/Shortcuts.swift`:
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}
```

`Sources/OnscreenTodoMatrix/LoginItem.swift`:
```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
```

`Sources/OnscreenTodoMatrix/ChartWebView.swift`:
```swift
import OTMCore
import WebKit
import os

/// Hosts the bundled chart (index.html + chart.js) and bridges messages.
@MainActor
final class ChartWebView: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var onMessage: (([String: Any]) -> Void)?
    private var ready = false
    private var pending: RenderState?
    private let log = Logger(subsystem: "onscreen-todo-matrix", category: "chart")

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakMessageHandler(self), name: "otm")
        let dir = Self.chartDirectory()
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }

    /// App bundle `Contents/Resources/chart`, or `chart/dist` in the source tree when run via `swift run`.
    static func chartDirectory() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("chart"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("index.html").path) {
            return res
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("chart/dist")
    }

    func render(_ state: RenderState) {
        guard ready else { pending = state; return }
        guard let data = try? RenderStateBuilder.encoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.otm && window.otm.render(\(json))") { [log] _, error in
            if let error { log.error("render failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            if let p = pending { pending = nil; render(p) }
        case "log":
            log.log("js \(String(describing: body["level"]), privacy: .public): \(String(describing: body["msg"]), privacy: .public)")
        default:
            onMessage?(body)
        }
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
```

`Sources/OnscreenTodoMatrix/PanelController.swift`:
```swift
import AppKit
import Combine
import OTMCore

/// NSPanel that can take keyboard focus without activating the app.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    let chart = ChartWebView()
    private let model: AppModel
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = "onscreen-todo-matrix"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 320)
        panel.contentView = chart.webView
        panel.delegate = self
        if !panel.setFrameUsingName("OTMPanel") { panel.center() }
        panel.setFrameAutosaveName("OTMPanel")
        model.$renderState
            .sink { [weak self] state in
                self?.chart.render(state)
                self?.apply(state.settings)
            }
            .store(in: &bag)
    }

    private func apply(_ q: QuickSettings) {
        panel.level = q.alwaysOnTop ? .floating : .normal
        panel.alphaValue = CGFloat(q.panelOpacity / 100)
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(chart.webView)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.refresh(.focus) }
    }
}
```

`Sources/OnscreenTodoMatrix/SettingsWindowController.swift` (temporary stub):
```swift
import AppKit
import OTMCore

@MainActor
final class SettingsWindowController {
    init(model: AppModel, onDone: @escaping () -> Void) {}
    func show() {}
}
```

`Sources/OnscreenTodoMatrix/AppDelegate.swift`:
```swift
import AppKit
import Combine
import KeyboardShortcuts
import OTMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var settings: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = ConfigStore.defaultDirectory()
        model = AppModel(
            configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir),
            tokenStore: KeychainTokenStore(), scheduler: RefreshScheduler(),
            makeClient: { site, email, token in JiraClient(site: site, email: email, token: token) }
        )
        panel = PanelController(model: model)
        settings = SettingsWindowController(model: model) { [weak self] in
            self?.panel.show()
            Task { await self?.model.refresh(.manual) }
        }
        panel.chart.onMessage = { [weak self] msg in self?.handle(msg) }
        setUpStatusItem()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh(.timer) }
        }
        model.$renderState
            .map { $0.status.banner != nil }
            .removeDuplicates()
            .sink { [weak self] warn in self?.updateIcon(warning: warn) }
            .store(in: &bag)

        if model.isConfigured {
            panel.show()
            Task { await model.refresh(.manual) }
        } else {
            settings.show()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(warning: false)
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit onscreen-todo-matrix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateIcon(warning: Bool) {
        let name = warning ? "exclamationmark.triangle" : "circle.hexagongrid"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "onscreen-todo-matrix")
    }

    @objc private func togglePanel() { panel.toggle() }
    @objc private func refreshNow() { Task { await model.refresh(.manual) } }
    @objc private func openSettings() { settings.show() }

    // MARK: - Messages from the chart

    private func handle(_ msg: [String: Any]) {
        switch msg["type"] as? String {
        case "openIssue":
            if let key = msg["key"] as? String, let url = model.issueURL(key: key) { NSWorkspace.shared.open(url) }
        case "refetch":
            Task { await model.refresh(.manual) }
        case "hide":
            panel.hide()
        case "openSettings":
            settings.show()
        case "selectPreset":
            if let id = msg["id"] as? String {
                model.selectPreset(id: id)
                Task { await model.refresh(.manual) }
            }
        case "quickSetting":
            if let key = msg["key"] as? String { model.setQuickSetting(key: key, value: JSONValue(any: msg["value"])) }
        case "saveDefaultView":
            if let yaw = msg["yaw"] as? Double, let pitch = msg["pitch"] as? Double, let zoom = msg["zoom"] as? Double {
                model.saveDefaultView(yaw: yaw, pitch: pitch, zoom: zoom)
            }
        default:
            break
        }
    }
}
```

Note: `msg["yaw"] as? Double` works for JS numbers (bridged as NSNumber). If a JS integer arrives (e.g. `zoom: 1`), `as? Double` still succeeds for NSNumber.

- [ ] **Step 2: Build**

Run: `cd chart && npm run build && cd .. && swift build`
Expected: build succeeds with no errors (warnings acceptable).

- [ ] **Step 3: Manual smoke run**

Run: `swift run OnscreenTodoMatrix` (in the background or a separate terminal), then:
1. A status-bar icon (hexagon grid) appears; there is no Dock icon.
2. With no config, nothing else opens yet (settings is a stub). Choose **Show / Hide Panel** from the status menu: the panel opens showing the "Finish setup to see your Jira issues." overlay over the floor/axes.
3. Press ⌥Space from another app: the panel hides/shows.
4. Quit from the status menu.
Record results in the task report.

- [ ] **Step 4: Commit**

```bash
git add Sources/OnscreenTodoMatrix && git commit -m "feat(otm): menu-bar app shell with floating panel and chart bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Settings window (connection, filters, axes, shortcuts, general)

**Files:**
- Modify (replace stub): `SRC/Sources/OnscreenTodoMatrix/SettingsWindowController.swift`
- Create: `SRC/Sources/OnscreenTodoMatrix/SettingsViewModel.swift`, `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift`

**Interfaces:**
- Consumes: `AppModel` API (Task 8), `DefaultMappings`, `FieldClassifier`, `AxisMapper.observedLabels` (Task 4), `LoginItem`, `KeyboardShortcuts.Name.togglePanel` (Task 11).
- Produces: `SettingsWindowController(model:onDone:)` with `show()` (same signature as the stub).

No unit tests (UI); the logic it calls is tested in OTMCore. Verification is manual against a real Jira Cloud site, or the stub checks below if no Jira site is available.

- [ ] **Step 1: Write the view model**

`Sources/OnscreenTodoMatrix/SettingsViewModel.swift`:
```swift
import Foundation
import OTMCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var site: String
    @Published var email: String
    @Published var token: String
    @Published var connectionStatus = ""
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []
    @Published var jqlStatus: [String: String] = [:]
    @Published var generalError = ""
    @Published var busy = false

    let model: AppModel

    init(model: AppModel) {
        self.model = model
        site = model.config.site
        email = model.config.email
        token = model.storedToken ?? ""
    }

    var isConnected: Bool { connectionStatus.hasPrefix("Connected as") }

    func saveAndTest() async {
        busy = true
        defer { busy = false }
        var c = model.config
        c.site = site
        c.email = email
        model.updateConfig(c)
        do {
            try model.setToken(token)
        } catch {
            connectionStatus = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        do {
            let me = try await model.makeAPI().myself()
            connectionStatus = "Connected as \(me.displayName)"
            await loadFields()
        } catch {
            connectionStatus = Self.describe(error)
        }
    }

    func loadFields() async {
        guard let api = try? model.makeAPI() else { return }
        fields = ((try? await api.fields()) ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        priorities = (try? await api.priorities()) ?? []
        if !fields.isEmpty && !isConnected { connectionStatus = "Connected" }
        let suggested = DefaultMappings.suggest(fields: fields, current: model.config.axes)
        if suggested != model.config.axes {
            var c = model.config
            c.axes = suggested
            model.updateConfig(c)
        }
    }

    func testJQL(_ preset: JQLPreset) async {
        jqlStatus[preset.id] = "Testing…"
        do {
            let n = try await model.makeAPI().approximateCount(jql: preset.jql)
            jqlStatus[preset.id] = "\(n) issues match"
        } catch {
            jqlStatus[preset.id] = Self.describe(error)
        }
    }

    /// Values offered in the option-level editor.
    func optionValues(for mapping: AxisMapping) -> [String] {
        guard case .option(let fieldId, let levels) = mapping else { return [] }
        var values = fieldId == "priority" && !priorities.isEmpty
            ? priorities : AxisMapper.observedLabels(fieldId: fieldId, issues: model.issues)
        for key in levels.keys.sorted() where !values.contains(key) { values.append(key) }
        return values
    }

    func usableFields(matching filter: String) -> [JiraField] {
        fields.filter {
            FieldClassifier.kind(of: $0) != .unsupported
                && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter))
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? JiraError { return AppModel.bannerText(e, syncedAt: nil) }
        return error.localizedDescription
    }
}
```

- [ ] **Step 2: Write the views**

`Sources/OnscreenTodoMatrix/SettingsView.swift`:
```swift
import KeyboardShortcuts
import OTMCore
import SwiftUI

enum SettingsTab: Hashable { case connection, filters, axes, shortcuts, general }

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State var tab: SettingsTab = .connection
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !model.isConfigured { setupHeader }
            TabView(selection: $tab) {
                ConnectionTab(vm: vm).tabItem { Text("1. Connect") }.tag(SettingsTab.connection)
                FiltersTab(model: model, vm: vm).tabItem { Text("2. Filter") }.tag(SettingsTab.filters)
                AxesTab(model: model, vm: vm).tabItem { Text("3. Axes") }.tag(SettingsTab.axes)
                ShortcutsTab().tabItem { Text("Shortcuts") }.tag(SettingsTab.shortcuts)
                GeneralTab(model: model, vm: vm).tabItem { Text("General") }.tag(SettingsTab.general)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var setupHeader: some View {
        HStack(spacing: 14) {
            step("1. Connect", done: vm.isConnected || model.storedToken != nil && model.config.siteURL != nil)
            step("2. Filter", done: !model.config.presets.isEmpty)
            step("3. Axes", done: model.config.axes.isComplete)
            Spacer()
            Button(tab == .axes ? "Done · show panel" : "Next") {
                switch tab {
                case .connection: tab = .filters
                case .filters: tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(tab == .axes && !model.isConfigured)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func step(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
    }
}

struct ConnectionTab: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        Form {
            TextField("Jira site", text: $vm.site, prompt: Text("your-company.atlassian.net"))
            TextField("Email", text: $vm.email)
            SecureField("API token", text: $vm.token)
            Link("Create an API token at id.atlassian.com", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
            HStack {
                Button("Save & Test") { Task { await vm.saveAndTest() } }
                    .disabled(vm.busy || vm.site.isEmpty || vm.email.isEmpty || vm.token.isEmpty)
                if vm.busy { ProgressView().controlSize(.small) }
                Text(vm.connectionStatus).foregroundStyle(vm.isConnected ? .green : .secondary)
            }
            Text("The API token is stored only in your macOS Keychain. The app only reads from Jira.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct FiltersTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            ForEach(model.config.presets) { preset in
                Section {
                    TextField("Name", text: binding(preset.id, \.name))
                    TextField("JQL", text: binding(preset.id, \.jql), axis: .vertical).lineLimit(2...5)
                    HStack {
                        Button("Test") { Task { await vm.testJQL(currentPreset(preset.id) ?? preset) } }
                        Text(vm.jqlStatus[preset.id] ?? "").foregroundStyle(.secondary)
                        Spacer()
                        if model.config.activePresetId == preset.id {
                            Text("Active").foregroundStyle(.green)
                        } else {
                            Button("Make active") { model.selectPreset(id: preset.id) }
                        }
                        Button("Delete", role: .destructive) { delete(preset.id) }
                            .disabled(model.config.presets.count <= 1)
                    }
                }
            }
            Button("Add preset") {
                var c = model.config
                c.presets.append(JQLPreset(id: UUID().uuidString, name: "New preset", jql: "assignee = currentUser() AND statusCategory != Done"))
                model.updateConfig(c)
            }
        }
        .formStyle(.grouped)
    }

    private func currentPreset(_ id: String) -> JQLPreset? { model.config.presets.first { $0.id == id } }

    private func binding(_ id: String, _ path: WritableKeyPath<JQLPreset, String>) -> Binding<String> {
        Binding(
            get: { currentPreset(id)?[keyPath: path] ?? "" },
            set: { value in
                var c = model.config
                guard let i = c.presets.firstIndex(where: { $0.id == id }) else { return }
                c.presets[i][keyPath: path] = value
                model.updateConfig(c)
            }
        )
    }

    private func delete(_ id: String) {
        var c = model.config
        c.presets.removeAll { $0.id == id }
        if c.activePresetId == id { c.activePresetId = c.presets.first?.id ?? JQLPreset.myOpenWork.id }
        model.updateConfig(c)
    }
}

struct AxesTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            if vm.fields.isEmpty {
                Text("Connect to Jira first (tab 1) to load your fields.").foregroundStyle(.secondary)
                Button("Reload fields") { Task { await vm.loadFields() } }
            }
            ForEach(Axis.allCases, id: \.self) { axis in
                AxisEditor(axis: axis, model: model, vm: vm)
            }
        }
        .formStyle(.grouped)
    }
}

struct AxisEditor: View {
    let axis: Axis
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var filter = ""

    private var cfg: AxisConfig { model.config.axes[axis] }

    private func update(_ change: (inout AxisConfig) -> Void) {
        var c = model.config
        change(&c.axes[axis])
        model.updateConfig(c)
    }

    private var title: String {
        switch axis {
        case .value: return "Value (X)"
        case .effort: return "Effort (Y)"
        case .urgency: return "Urgency (Z)"
        }
    }

    var body: some View {
        Section(title) {
            TextField("Filter fields", text: $filter)
            Picker("Field", selection: Binding(
                get: { cfg.mapping?.fieldId ?? "" },
                set: { id in
                    let mapping = vm.fields.first(where: { $0.id == id }).flatMap { DefaultMappings.mapping(for: $0) }
                    update { $0.mapping = mapping }
                }
            )) {
                Text("— none —").tag("")
                if let current = cfg.mapping?.fieldId, !vm.fields.contains(where: { $0.id == current }) {
                    Text(current).tag(current)
                }
                ForEach(vm.usableFields(matching: filter)) { f in
                    Text("\(f.name)  ·  \(f.schemaType ?? "?")").tag(f.id)
                }
            }
            if let mapping = cfg.mapping { editor(for: mapping) }
            HStack {
                Text("Missing value position")
                Slider(value: Binding(get: { cfg.missingDefault }, set: { v in update { $0.missingDefault = v } }), in: 0...1)
                Text(String(format: "%.2f", cfg.missingDefault)).monospacedDigit()
            }
            Text(liveLine).font(.caption).foregroundStyle(.secondary)
            if let unmapped = model.unmappedLabels[axis], !unmapped.isEmpty {
                Text("Unmapped values (placed at the middle): \(unmapped.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var liveLine: String {
        let tasks = model.renderState.tasks
        let missing = tasks.filter { $0.missing[axis] }.count
        return "\(tasks.count) issues mapped · \(missing) missing value"
    }

    @ViewBuilder
    private func editor(for mapping: AxisMapping) -> some View {
        switch mapping {
        case .option(let fieldId, let levels):
            ForEach(vm.optionValues(for: mapping), id: \.self) { label in
                HStack {
                    Text(label).frame(width: 140, alignment: .leading)
                    Slider(value: Binding(
                        get: { levels[label] ?? 2.5 },
                        set: { v in
                            var l = levels
                            l[label] = v
                            update { $0.mapping = .option(fieldId: fieldId, levels: l) }
                        }
                    ), in: 0...5, step: 0.25)
                    Text(String(format: "%.2f", levels[label] ?? 2.5)).monospacedDigit()
                }
            }
        case .number(let fieldId, let lo, let hi, let invert):
            Toggle("Auto range (from current issues)", isOn: Binding(
                get: { lo == nil && hi == nil },
                set: { auto in update { $0.mapping = .number(fieldId: fieldId, min: auto ? nil : 0, max: auto ? nil : 10, invert: invert) } }
            ))
            if lo != nil || hi != nil {
                HStack {
                    TextField("Min", value: Binding(get: { lo ?? 0 }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: v, max: hi, invert: invert) } }), format: .number)
                    TextField("Max", value: Binding(get: { hi ?? 10 }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: lo, max: v, invert: invert) } }), format: .number)
                }
            }
            Toggle("Invert", isOn: Binding(get: { invert }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: lo, max: hi, invert: v) } }))
        case .date(let fieldId, let horizon, let invert):
            Stepper("Horizon: \(horizon) days (due today or overdue = max)", value: Binding(
                get: { horizon },
                set: { v in update { $0.mapping = .date(fieldId: fieldId, horizonDays: v, invert: invert) } }
            ), in: 1...90)
            Toggle("Invert", isOn: Binding(get: { invert }, set: { v in update { $0.mapping = .date(fieldId: fieldId, horizonDays: horizon, invert: v) } }))
        }
    }
}

struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Show / hide panel:", name: .togglePanel)
            Text("Default ⌥Space. If it conflicts with Raycast, Alfred or ChatGPT, record another shortcut.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { model.config.launchAtLogin },
                set: { on in
                    do {
                        try LoginItem.set(on)
                        var c = model.config
                        c.launchAtLogin = on
                        model.updateConfig(c)
                        vm.generalError = ""
                    } catch {
                        vm.generalError = "Could not change login item: \(error.localizedDescription)"
                    }
                }
            ))
            Picker("Auto refresh", selection: Binding(
                get: { model.config.quick.refreshMinutes },
                set: { v in model.setQuickSetting(key: "refreshMinutes", value: .number(Double(v))) }
            )) {
                Text("1 min").tag(1); Text("5 min").tag(5); Text("15 min").tag(15); Text("Off").tag(0)
            }
            if !vm.generalError.isEmpty { Text(vm.generalError).foregroundStyle(.red) }
            if model.configWasCorrupt {
                Text("Your previous config file was unreadable and was saved as config.json.bak.")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Replace the controller stub**

`Sources/OnscreenTodoMatrix/SettingsWindowController.swift`:
```swift
import AppKit
import OTMCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let vm: SettingsViewModel
    private let onDone: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        self.vm = SettingsViewModel(model: model)
        self.onDone = onDone
    }

    func show() {
        if window == nil {
            let view = SettingsView(model: model, vm: vm) { [weak self] in
                self?.window?.close()
                self?.onDone()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "onscreen-todo-matrix Settings"
            w.setContentSize(NSSize(width: 640, height: 560))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: build succeeds. Fix any SwiftUI type-check errors by extracting sub-views; do not change behavior.

- [ ] **Step 5: Manual check**

Run `swift run OnscreenTodoMatrix`. With no config the settings window opens with the 3-step header.
- If a Jira Cloud site + API token are available: enter them, **Save & Test** → "Connected as …"; Axes tab shows Urgency ← Priority and Effort ← Story Points pre-filled; pick a Value field; **Done · show panel** opens the panel with real issues.
- If not available: enter `example.atlassian.net`, any email and token → **Save & Test** shows an error line (e.g. "Jira sign-in failed · Open settings" or "Offline · no cached data"); the app must not crash. Record what was verified.

- [ ] **Step 6: Commit**

```bash
git add Sources/OnscreenTodoMatrix && git commit -m "feat(otm): settings window with setup steps and axis mapping editors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: App bundle build script, manual checklist and README

**Files:**
- Create: `SRC/scripts/build-app.sh`, `SRC/scripts/Info.plist`, `SRC/docs/manual-checklist.md`
- Modify: `productivity/onscreen-todo-matrix/README.md` (add "Build & run" section; keep all existing content)

**Interfaces:**
- Consumes: everything. Produces `SRC/build/Onscreen Todo Matrix.app`.

- [ ] **Step 1: Write Info.plist**

`scripts/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Onscreen Todo Matrix</string>
  <key>CFBundleDisplayName</key><string>Onscreen Todo Matrix</string>
  <key>CFBundleIdentifier</key><string>io.github.luatnd.onscreen-todo-matrix</string>
  <key>CFBundleExecutable</key><string>OnscreenTodoMatrix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Write the build script**

`scripts/build-app.sh`:
```bash
#!/usr/bin/env bash
# Builds "Onscreen Todo Matrix.app" (ad-hoc signed) into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd chart && npm ci && npm test && npm run build)
swift test
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Onscreen Todo Matrix.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/chart"
cp "$BIN/OnscreenTodoMatrix" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp chart/dist/index.html chart/dist/style.css chart/dist/chart.js "$APP/Contents/Resources/chart/"
# SwiftPM resource bundles of dependencies (KeyboardShortcuts localizations)
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
codesign --force --deep --sign - "$APP"
echo "Built: $(pwd)/$APP"
```

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: tests pass, ends with `Built: …/build/Onscreen Todo Matrix.app`.

- [ ] **Step 3: Write the manual checklist**

`docs/manual-checklist.md`:
```markdown
# Manual checklist (window behavior; not covered by unit tests)

Run after `./scripts/build-app.sh` and `open "build/Onscreen Todo Matrix.app"`.

- [ ] Status-bar icon appears; no Dock icon; menu has Show / Hide Panel, Refresh Now, Settings…, Quit.
- [ ] First launch without config opens Settings with the 1-2-3 setup header.
- [ ] ⌥Space toggles the panel from another app (e.g. while typing in an editor); keyboard focus lands in the panel.
- [ ] Tab / ⇧Tab cycle tasks; ⌘O opens the issue in the default browser; Esc deselects then hides.
- [ ] ⌘R refetches; returning focus to the panel after >30 s refetches (watch "synced …").
- [ ] Quick settings (Q): panel opacity 40% shows the desktop through; Always on top Off lets other windows cover it.
- [ ] Panel appears on every Space and over a full-screen app.
- [ ] Panel size/position persist across relaunch.
- [ ] Settings → Shortcuts: recording a new shortcut works and ⌥Space stops working.
- [ ] Settings → General → Launch at login toggles without error (ad-hoc signed builds may show an error: expected; it must be shown, not crash).
- [ ] Keychain: token survives relaunch; `security find-generic-password -s onscreen-todo-matrix` finds the item.
- [ ] Offline (Wi-Fi off) → banner "Offline · showing data from HH:mm", dots still shown.
```

- [ ] **Step 4: Update the idea README**

Append to `productivity/onscreen-todo-matrix/README.md` (keep everything above it):
```markdown

# Build & run
Requirements: macOS 14+, Xcode 26 (Swift 6.2 toolchain), Node 22.

~~~bash
cd productivity/onscreen-todo-matrix/src
./scripts/build-app.sh
open "build/Onscreen Todo Matrix.app"
~~~

Development: `swift test` (core logic), `cd chart && npm test` (chart), `swift run OnscreenTodoMatrix` (runs with `chart/dist` from the source tree; run `npm run build` in `chart/` first). Manual window checks: [src/docs/manual-checklist.md](src/docs/manual-checklist.md).
```

Also tick the README TODO items that are now done (`Implementation plan`, `Implement v1`).

- [ ] **Step 5: Smoke-launch the bundle**

Run: `open "build/Onscreen Todo Matrix.app"`; confirm the status-bar icon appears and Settings opens (fresh config) or the panel opens (existing config). Quit via the status menu.

- [ ] **Step 6: Commit**

```bash
git add scripts docs ../README.md && git commit -m "build(otm): app bundle script, manual checklist and run docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
