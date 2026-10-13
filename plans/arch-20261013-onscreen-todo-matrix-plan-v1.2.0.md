# Glance — Onscreen Todo Matrix v1.2.0 (multiple Jira accounts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one user use several Jira Cloud accounts (e.g. personal + company): each JQL preset belongs to one account, axis mappings and API tokens are per account, the last chosen preset is restored, and a grouped preset menu with "+ New preset…" / "⚙ Manage presets…" and ⌘1…⌘9 replaces the native `<select>` — without losing the user's existing v1.1 setup.

**Architecture:** All logic stays in `OTMCore` (headless, `swift test`): `AppConfig` gains `accounts: [JiraAccount]` (site/email/axes move there), `JQLPreset.accountId`, a keyed `TokenStore`, a per-preset `IssueCache`, a `ConfigMigration` (v1.1 → v1.2, with `config.v1.json` backup and verified Keychain copy) and an `AppModel` whose active account is always the active preset's account. The Swift ↔ JS `RenderState` contract gains `accounts`, `presets[].accountId`, `setup` and `status.bannerTab`. The chart gets a pure `presetMenu.js` module (grouping, ordering, ⌘ shortcuts, filter, keyboard reducer) wired into `main.js`. Settings is re-split into an Accounts tab, a Presets tab with a New preset sheet (JQL templates + live Test) and a per-account Axes tab, routed by `SettingsViewModel`.

**Tech Stack:** Swift (tools 5.10 / Swift 5 language mode, Swift 6.2 toolchain), AppKit + SwiftUI + WebKit + Security, `sindresorhus/KeyboardShortcuts` 3.1.0, Swift Testing; JS ES modules bundled by esbuild 0.28.2, tested with Vitest 5.0.4 on Node 22.

**Spec:** [`../specs/arch-20261013-onscreen-todo-matrix-design-v1.2.0.md`](../specs/arch-20261013-onscreen-todo-matrix-design-v1.2.0.md) — implement **§11** fully (and the earlier sections it amends). Read §11 before any task. Previous plan (conventions): [`arch-20261012-onscreen-todo-matrix-plan.md`](arch-20261012-onscreen-todo-matrix-plan.md).

## Global Constraints

Still binding from plan v1:

- All source lives under `productivity/onscreen-todo-matrix/src/` (called **SRC** below). All shell commands in this plan run from SRC unless stated otherwise.
- macOS 14.0 minimum (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0).
- `// swift-tools-version: 5.10` (Swift 5 language mode, avoids strict-concurrency errors).
- Dependencies are exactly: KeyboardShortcuts `exact: "3.1.0"` (Swift); `esbuild` `0.28.2` and `vitest` `5.0.4` (JS devDependencies). Add nothing else.
- Jira access is **read-only**: only `GET /rest/api/3/myself`, `GET /rest/api/3/field`, `GET /rest/api/3/priority/search`, `POST /rest/api/3/search/jql`, `POST /rest/api/3/search/approximate-count`. No other endpoint, never PUT/DELETE.
- API tokens are stored only in Keychain (service `onscreen-todo-matrix`), never in config JSON.
- Config: `~/Library/Application Support/onscreen-todo-matrix/config.json`; corrupt config is renamed to `config.json.bak`.
- Issue cap: 500 per fetch.
- View: default yaw −179.7°, pitch 33.9°, zoom 1. Limited rotation: yaw ±18°, pitch ±10° around default. Free: pitch clamped ±89°. Zoom 0.5–3. Saved default pitch clamped ±80°.
- Color channel = `round(55 + 200·clamp01(v))`; RGB = (urgency, 1 − effort, value).
- Score = `value × (0.5 + urgency) / (0.3 + effort)`; top 3 ranked; fire = value ≥ 0.7 AND urgency ≥ 0.8.
- Labels: summary truncated to 28 chars with `…`.
- UI copy strings that appear in this plan are exact (banners, button labels).
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

New for v1.2.0:

- Work on branch `feat/onscreen-todo-matrix` in its worktree; never commit on `prod`, `dev` or `unstable`.
- Internal identifiers do not change: Keychain service `onscreen-todo-matrix`, config dir `onscreen-todo-matrix`, package/target/executable names `OnscreenTodoMatrix` / `OTMCore`, bundle id `io.github.luatnd.glance`, app name "Glance", frame autosave `GlancePanel2`.
- Keychain items: one generic password per account, account attribute `jira-api-token:<accountId>`. The v1.1 item (account `jira-api-token`) is read and deleted **only** by the migration, and deleted only after the copy has been read back equal.
- Per-preset cache: `<config dir>/cache/<presetId>.json` (`issues`, `fetchedAt`, `accountId`); the v1.1 `last-fetch.json` is moved there by the migration. v1.1 backup: `<config dir>/config.v1.json` (kept forever).
- The migrated account has id `"default"` and name `"Personal"`. Decoding is tolerant: every config key is optional except `accounts[].id` and `presets[].id`; a valid v1.1 file must never be treated as corrupt.
- Tests never touch the real config directory or the real Keychain: always `makeTempDir()` and `InMemoryTokenStore`.
- **Protect the user's real setup:** before the first launch of any v1.2 build (`swift run`, `open build/Glance.app`), back it up: `cp -R ~/Library/Application\ Support/onscreen-todo-matrix ~/onscreen-todo-matrix-backup-v1.1`. Never edit or delete the real `config.json` by hand.
- Every task leaves `swift build` green: `swift test` also compiles the `OnscreenTodoMatrix` executable target, so a task that changes an OTMCore API also patches its app-target call sites (the steps say exactly how).
- Spec copy used verbatim: "+ New preset…", "⚙ Manage presets…", "⚠ account missing", "Jira sign-in failed (<account>) · Open settings", "Could not migrate settings · Open settings", "Map axes for <account> to see this preset", "Map axes for <account>", "+ Add account", "Save & Test", "Edit", "Remove", "+ New preset", "Test", "Make active", "Delete", "Create & show", "Connected as <displayName>", template chips "My open work" / "Due this week" / "Reported by me" / "Unassigned in project…" with the JQL of §11.7.

## Review Focus

1. **The user's real v1.1 `config.json`** (site stored as `"https:\/\/…atlassian.net"`, number mapping without `min`/`max` keys, `missingDefault: 0`, `rotation: "free"`, `refreshMinutes: 15`, `launchAtLogin: true`, presets without `accountId`) must load as `.legacy`, never `.corrupt`, migrate losslessly, and `load()` must not write. Pinned by `realShapeV11IsLegacyNotCorruptAndLossless` (Task 3).
2. **Keychain copy fails or cannot be read back**: the legacy item and the v1.1 `config.json` stay untouched (migration retried next launch), the app keeps working with the legacy token, and the banner says "Could not migrate settings · Open settings". Pinned by `keychainWriteFailureKeepsLegacyItemAndOldFile` + `unverifiedCopyKeepsLegacyItem` (Task 3) and `migrationFailureShowsBannerAndKeepsWorkingWithLegacyToken` (Task 5).
3. **A fetch for preset A is still in flight when the user switches to preset B** (success or 401): A's issues are cached under A only and never shown under B's name; A's 401 marks A's account ⚠ but neither pauses B's refresh nor shows a banner on B. Pinned by `inFlightResultOfPreviousPresetIsCachedButNotShown` + `inFlightFailureOfPreviousPresetDoesNotPauseOrBannerTheNewOne` (Task 5).
4. **A hand-edited preset id with path characters** (`"../config"`, `"a/b"`) must not let the cache write outside `cache/`. Pinned by `presetIdCannotEscapeTheCacheFolder` (Task 2).
5. **Typing a filter in the preset menu that matches nothing**: "+ New preset…" and "⚙ Manage presets…" stay, Enter activates "+ New preset…" (never a hidden preset), and ⌘ labels never renumber while filtering. Pinned by "nothing matches" + "Enter with a filter that hides everything" in `presetMenu.test.js` (Task 6).

## Rulings on spec gaps (binding for all tasks)

1. **Account ids:** the first account ever added on a fresh install gets id `"default"` (so the pre-filled "My open work" preset, whose `accountId` defaults to `"default"`, belongs to it — this is the wizard's "pre-filled 'My open work' for that account"); every later account gets a UUID string (`AppModel.newAccountId()`).
2. **Legacy token API:** `TokenStore` is keyed (`read(accountId:)`, `write(_:accountId:)`, `delete(accountId:)`) plus two migration-only methods `readLegacy()` / `deleteLegacy()`. Until the keyed copy exists, `AppModel` reads the legacy item for account `"default"` (so a failed migration never logs the user out).
3. **Migration failure:** `config.json` is not rewritten (the next launch retries; every step is idempotent); the in-memory migrated config is used; the banner stays until the user saves an account in Settings.
4. **Tolerant decoding:** a preset without `accountId` decodes with `accountId == ""` (shown as "⚠ account missing" if it ever survives outside the migration). An account without `id` makes the file corrupt (→ `config.json.bak`).
5. **Menu order = ⌘1…⌘9 order:** accounts in account order, presets in config order within each account, presets whose account is missing last (they get numbers too; activating one opens the Presets tab).
6. **Names:** account and preset names are compared trimmed and case-insensitively. The New preset sheet blocks duplicates; inline renames in the Presets tab only show a warning (blocking keystrokes would make intermediate text untypable).
7. **Cache per preset:** a cache whose `accountId` differs from the preset's account is ignored; a preset without a cache shows an empty chart (never the previous preset's issues) until its refresh lands.
8. **Live Test:** the New preset sheet runs Test automatically 600 ms after the last change of account or JQL, plus a Test button; editing clears the previous result.
9. **"+ New preset…"** pre-selects the active preset's account, else the first account; with no accounts it opens the Accounts tab.
10. **Contract additions beyond §11.8** (needed for §11.10 routing): `status.bannerTab` (`"accounts" | "presets" | "axes"`, omitted when nil) and `setup {message, tab}` (omitted when configured). The banner and setup-overlay "Open settings" post `openSettings {tab}`.
11. **Copy not given by the spec** (use exactly): overlay "Finish setup to see your Jira issues." (v1.1), "Create a preset to see your Jira issues.", "This preset's account is missing · reassign it in settings"; menu button "No presets" when there is no preset; Settings tab labels "Accounts", "Presets", "Axes", "Shortcuts", "General"; wizard steps "1. Add account", "2. Presets", "3. Axes"; account row status "Jira sign-in failed" / "Not connected"; remove dialog "Remove <name>?" with message "Its presets and its API token in the Keychain are deleted too."; hints "An account with this name already exists.", "A preset with this name already exists for this account.", "Preset names must be unique within an account."; Presets tab section "⚠ account missing" with picker item "Choose…".
12. `CFBundleShortVersionString` 1.2.0, `CFBundleVersion` 2.

---

## File Structure

```
productivity/onscreen-todo-matrix/src/
├── fixtures/
│   ├── render-state.json                  # MODIFY: + accounts, presets[].accountId (shared Swift↔JS contract)
│   └── config-v1.1.json                   # CREATE: real v1.1 config shape with fake site/email (migration tests)
├── Sources/OTMCore/
│   ├── Config.swift                       # MODIFY: JiraAccount, AccountPalette, JQLPreset.accountId, JQLTemplate,
│   │                                      #         tolerant AppConfig (accounts, menu order, name rules)
│   ├── TokenStore.swift                   # MODIFY: keyed protocol + legacy methods; InMemory + Keychain stores
│   ├── IssueCache.swift                   # MODIFY: cache/<presetId>.json, CachedFetch.accountId, legacy move
│   ├── ConfigStore.swift                  # MODIFY: .legacy load result, config.v1.json URL
│   ├── ConfigMigration.swift              # CREATE: LegacyAppConfigV1, migrated(from:), finish(...)
│   ├── RenderState.swift                  # MODIFY: RenderAccount, RenderPreset.accountId, RenderSetup, bannerTab
│   └── AppModel.swift                     # MODIFY: multi-account refresh/select/errors/setup, account+preset CRUD
├── Sources/OnscreenTodoMatrix/
│   ├── AppDelegate.swift                  # MODIFY: newPreset, openSettings{tab}, selectPreset results
│   ├── SettingsWindowController.swift     # MODIFY: show(tab:accountId:), showNewPreset(accountId:)
│   ├── SettingsViewModel.swift            # MODIFY: router (tab, editAccountId, axesAccountId, newPreset)
│   ├── SettingsView.swift                 # MODIFY: container, wizard header, Shortcuts + General tabs only
│   ├── AccountsTab.swift                  # CREATE: Accounts tab + AccountDot + Color(hex:)
│   ├── PresetsTab.swift                   # CREATE: Presets tab grouped by account, drag reorder
│   ├── NewPresetSheet.swift               # CREATE: New preset sheet (templates + live Test)
│   └── AxesTab.swift                      # CREATE: Axes tab per account + AxisEditor
├── Tests/OTMCoreTests/
│   ├── ModelsTests.swift                  # MODIFY: accounts model tests
│   ├── StoresTests.swift                  # MODIFY: keyed tokens, per-preset cache, corrupt cases
│   ├── MigrationTests.swift               # CREATE
│   ├── ScorerRenderStateTests.swift       # MODIFY: contract additions
│   ├── AppModelTests.swift                # MODIFY (rewritten in Task 5)
│   └── TestSupport.swift                  # MODIFY: FakeJiraAPI.countResult
├── chart/
│   ├── public/index.html, public/style.css   # MODIFY: preset menu button + dropdown, setup message
│   ├── src/state.js                       # MODIFY: validate accounts / presets[].accountId / setup
│   ├── src/presetMenu.js                  # CREATE: pure preset-menu logic
│   ├── src/main.js                        # MODIFY: menu wiring, P, ⌘1…⌘9, openSettings{tab}
│   └── test/state.test.js, test/presetMenu.test.js
├── scripts/Info.plist                     # MODIFY: 1.2.0 / 2
└── docs/manual-checklist.md               # MODIFY: v1.2.0 checks
productivity/onscreen-todo-matrix/README.md   # MODIFY: plan link, TODO, DMG name
```

Task order and dependencies (each task compiles and passes all tests on its own):

| # | Task | Depends on |
|---|---|---|
| 1 | Accounts data model + keyed TokenStore | — |
| 2 | Per-preset issue cache | 1 |
| 3 | v1.1 → v1.2 migration | 1, 2 |
| 4 | RenderState contract + shared fixture + JS `validateState` | 1 |
| 5 | AppModel: multi-account refresh, switching, errors, CRUD | 1–4 |
| 6 | JS preset menu logic (`presetMenu.js`) | 4 |
| 7 | Chart UI: preset menu, P, ⌘1…⌘9, setup/banner routing | 6 |
| 8 | Settings routing, AppDelegate messages, Accounts tab | 5 |
| 9 | Presets tab + New preset sheet | 8 |
| 10 | Axes tab per account + wizard cleanup | 9 |
| 11 | Manual checklist, README, version 1.2.0, DMG | 1–10 |

---

### Task 1: Accounts data model + keyed TokenStore

Moves `site`, `email` and `axes` from `AppConfig` into `JiraAccount`, adds `JQLPreset.accountId`, tolerant decoding, menu order, name rules, palette and JQL templates, and makes `TokenStore` keyed per account. `AppModel` and the v1.1 Settings views get the minimal port to the new model (Task 5 and Tasks 8–10 replace them).

**Files:**
- Modify (full replacement): `SRC/Sources/OTMCore/Config.swift`, `SRC/Sources/OTMCore/TokenStore.swift`, `SRC/Sources/OTMCore/AppModel.swift`
- Modify: `SRC/Sources/OTMCore/RenderState.swift:66` (one line)
- Modify: `SRC/Sources/OnscreenTodoMatrix/SettingsViewModel.swift`, `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift` (call-site ports)
- Test: `SRC/Tests/OTMCoreTests/ModelsTests.swift`, `SRC/Tests/OTMCoreTests/StoresTests.swift`, `SRC/Tests/OTMCoreTests/AppModelTests.swift`

**Interfaces:**
- Consumes: existing `AxesConfig`, `AxisConfig`, `ViewDefaults`, `QuickSettings`, `JSONValue`, `JiraAPI`, `RenderStateBuilder`.
- Produces:
  - `struct JiraAccount: Codable, Equatable, Identifiable, Sendable { static let defaultId = "default"; var id, name, site, email: String; var axes: AxesConfig; init(id: String, name: String, site: String = "", email: String = "", axes: AxesConfig = AxesConfig()); var siteURL: URL? }`
  - `enum AccountPalette { static let colors: [String]; static func color(at index: Int) -> String }` — `["#3b82f6", "#f59e0b", "#10b981", "#ec4899", "#8b5cf6", "#06b6d4"]`
  - `struct JQLPreset { var id, name, jql, accountId: String; init(id:name:jql:accountId: String = JiraAccount.defaultId); static let myOpenWork }`
  - `struct JQLTemplate: Equatable, Sendable { let title: String; let jql: String; static let all: [JQLTemplate] }`
  - `struct AppConfig { var accounts: [JiraAccount]; var presets: [JQLPreset]; var activePresetId: String; var view; var lastView; var quick; var launchAtLogin; var activePreset: JQLPreset? ; func account(id: String?) -> JiraAccount?; var activeAccount: JiraAccount?; var menuOrderedPresets: [JQLPreset]; mutating func upsertAccount(_:); func movingPresets(accountId: String, fromOffsets: IndexSet, toOffset: Int) -> [JQLPreset]; func isAccountNameValid(_ name: String, excludingId: String? = nil) -> Bool; func isPresetNameValid(_ name: String, accountId: String, excludingId: String? = nil) -> Bool; static func normalizeSite(_:) -> URL? }` (no more `site`, `email`, `axes`, `siteURL`)
  - `protocol TokenStore: AnyObject { func read(accountId: String) throws -> String?; func write(_ token: String, accountId: String) throws; func delete(accountId: String) throws; func readLegacy() throws -> String?; func deleteLegacy() throws }`
  - `final class InMemoryTokenStore: TokenStore { var tokens: [String: String]; var legacyToken: String?; var readError: Error?; var writeError: Error?; var dropsWrites: Bool; init(tokens: [String: String] = [:], legacyToken: String? = nil) }`
  - `final class KeychainTokenStore: TokenStore { static let service = "onscreen-todo-matrix"; static let legacyAccount = "jira-api-token"; static func keychainAccount(for accountId: String) -> String }`
  - `AppModel` (new or changed public API): `var activeAccount: JiraAccount?`, `func storedToken(accountId: String) -> String?`, `func isAccountConfigured(_: JiraAccount) -> Bool`, `func newAccountId() -> String`, `func makeAPI(accountId: String) throws -> JiraAPI`, `func saveAccount(_ account: JiraAccount, token: String) throws`, `func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void)`. Removed: `storedToken` (property), `makeAPI()`, `setToken(_:)`.

- [ ] **Step 1: Write the failing tests**

In `Tests/OTMCoreTests/ModelsTests.swift`, inside `ConfigTests.defaultsMatchSpec()`, replace

```swift
        #expect(c.presets == [JQLPreset.myOpenWork])
        #expect(c.activePreset.jql == "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC")
```

with

```swift
        #expect(c.accounts.isEmpty)
        #expect(c.presets == [JQLPreset.myOpenWork])
        #expect(c.presets[0].accountId == JiraAccount.defaultId)
        #expect(c.activePreset?.jql == "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC")
```

and insert these tests into `ConfigTests`, directly before `@Test func quickSettingsApplyValidValuesOnly() {`:

```swift
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

```

In `Tests/OTMCoreTests/StoresTests.swift`, in `ConfigStoreTests.roundTripsConfig()`, replace

```swift
        var c = AppConfig()
        c.site = "acme.atlassian.net"
        c.axes.urgency.mapping = .option(fieldId: "priority", levels: ["High": 4])
        try store.save(c)
```

with

```swift
        var axes = AxesConfig()
        axes.urgency.mapping = .option(fieldId: "priority", levels: ["High": 4])
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com", axes: axes)]
        c.presets.append(JQLPreset(id: "p2", name: "Company", jql: "project = C", accountId: "c1"))
        try store.save(c)
```

and replace the whole `@Suite struct InMemoryTokenStoreTests { … }` (end of file) with:

```swift
@Suite struct InMemoryTokenStoreTests {
    @Test func writeReadDeletePerAccount() throws {
        let s = InMemoryTokenStore()
        #expect(try s.read(accountId: "default") == nil)
        try s.write("abc", accountId: "default")
        try s.write("xyz", accountId: "c1")
        #expect(try s.read(accountId: "default") == "abc")
        #expect(try s.read(accountId: "c1") == "xyz")
        try s.delete(accountId: "default")
        #expect(try s.read(accountId: "default") == nil)
        #expect(try s.read(accountId: "c1") == "xyz")
    }

    @Test func legacyItemIsSeparateFromKeyedItems() throws {
        let s = InMemoryTokenStore(legacyToken: "old")
        #expect(try s.readLegacy() == "old")
        #expect(try s.read(accountId: "default") == nil)
        try s.delete(accountId: "default")
        #expect(try s.readLegacy() == "old")
        try s.deleteLegacy()
        #expect(try s.readLegacy() == nil)
    }

    @Test func readErrorIsThrown() {
        let s = InMemoryTokenStore()
        s.readError = TokenStoreError.status(-25293)
        #expect(throws: TokenStoreError.status(-25293)) { try s.read(accountId: "default") }
        #expect(throws: TokenStoreError.status(-25293)) { try s.readLegacy() }
    }

    @Test func keychainItemNamesKeepV11Identifiers() {
        #expect(KeychainTokenStore.service == "onscreen-todo-matrix")
        #expect(KeychainTokenStore.legacyAccount == "jira-api-token")
        #expect(KeychainTokenStore.keychainAccount(for: "default") == "jira-api-token:default")
        #expect(KeychainTokenStore.keychainAccount(for: "c1f") == "jira-api-token:c1f")
    }
}
```

In `Tests/OTMCoreTests/AppModelTests.swift`, replace

```swift
    let tokens = InMemoryTokenStore(token: "tok")
```

with

```swift
    let tokens = InMemoryTokenStore(tokens: ["default": "tok"])
```

and replace the body of `configuredConfig()`

```swift
        var c = AppConfig()
        c.site = "acme.atlassian.net"
        c.email = "me@x.com"
        c.axes.value.mapping = .number(fieldId: "cf_value", min: 0, max: 10, invert: false)
        c.axes.effort.mapping = .number(fieldId: "cf_sp", min: 0, max: 10, invert: false)
        c.axes.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        return c
```

with

```swift
        var axes = AxesConfig()
        axes.value.mapping = .number(fieldId: "cf_value", min: 0, max: 10, invert: false)
        axes.effort.mapping = .number(fieldId: "cf_sp", min: 0, max: 10, invert: false)
        axes.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com", axes: axes)]
        return c
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigTests`
Expected: build FAILS with errors such as `cannot find 'JiraAccount' in scope` and `extra argument 'tokens' in call`.

- [ ] **Step 3: Implement the model**

Replace `Sources/OTMCore/Config.swift` with:

```swift
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
```

Replace `Sources/OTMCore/TokenStore.swift` with:

```swift
import Foundation
import Security

/// API tokens, one per Jira account. The legacy (v1.1) single item is read/deleted only by the migration.
public protocol TokenStore: AnyObject {
    func read(accountId: String) throws -> String?
    func write(_ token: String, accountId: String) throws
    func delete(accountId: String) throws
    func readLegacy() throws -> String?
    func deleteLegacy() throws
}

public enum TokenStoreError: Error, Equatable {
    case status(Int32)
}

public final class InMemoryTokenStore: TokenStore {
    public var tokens: [String: String]
    public var legacyToken: String?
    public var readError: Error?
    public var writeError: Error?
    /// Simulates a store that reports success but keeps nothing (used to test "copy verified").
    public var dropsWrites = false

    public init(tokens: [String: String] = [:], legacyToken: String? = nil) {
        self.tokens = tokens
        self.legacyToken = legacyToken
    }

    public func read(accountId: String) throws -> String? {
        if let readError { throw readError }
        return tokens[accountId]
    }

    public func write(_ token: String, accountId: String) throws {
        if let writeError { throw writeError }
        if !dropsWrites { tokens[accountId] = token }
    }

    public func delete(accountId: String) throws { tokens[accountId] = nil }

    public func readLegacy() throws -> String? {
        if let readError { throw readError }
        return legacyToken
    }

    public func deleteLegacy() throws { legacyToken = nil }
}

/// API tokens in the macOS Keychain (generic passwords, service `onscreen-todo-matrix`).
public final class KeychainTokenStore: TokenStore {
    public static let service = "onscreen-todo-matrix"
    /// v1.1 single-account item, kept until the migration has verified its copy.
    public static let legacyAccount = "jira-api-token"
    public static func keychainAccount(for accountId: String) -> String { "\(legacyAccount):\(accountId)" }

    public init() {}

    public func read(accountId: String) throws -> String? { try read(account: Self.keychainAccount(for: accountId)) }
    public func write(_ token: String, accountId: String) throws { try write(token, account: Self.keychainAccount(for: accountId)) }
    public func delete(accountId: String) throws { try delete(account: Self.keychainAccount(for: accountId)) }
    public func readLegacy() throws -> String? { try read(account: Self.legacyAccount) }
    public func deleteLegacy() throws { try delete(account: Self.legacyAccount) }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }

    private func read(account: String) throws -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw TokenStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.status(update) }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.status(status) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError.status(status) }
    }
}
```

- [ ] **Step 4: Port AppModel and the RenderState builder**

Replace `Sources/OTMCore/AppModel.swift` with (minimal port: the active account is the active preset's account; tokens are loaded per account; Task 5 replaces this file):

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

    private var tokens: [String: String] = [:]
    private var tokenErrorAccounts: Set<String> = []
    private var syncedAt: Date?
    private var banner: String?
    private var truncated: String?
    private var lastMapped: [MappedTask] = []
    private var isRefreshing = false
    private var rerunRequested = false

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
        for account in config.accounts { loadToken(account.id) }
        if let cached = cache.load() {
            issues = cached.issues
            syncedAt = cached.fetchedAt
        }
        if let id = activeAccount?.id, tokenErrorAccounts.contains(id) {
            banner = "Keychain access denied · re-enter your API token in settings"
        }
        rebuild(previous: nil)
    }

    public var activeAccount: JiraAccount? { config.activeAccount }

    public func storedToken(accountId: String) -> String? { tokens[accountId] }

    /// Site, email, token and all three axes mapped.
    public func isAccountConfigured(_ account: JiraAccount) -> Bool {
        account.siteURL != nil && !account.email.isEmpty && !(tokens[account.id] ?? "").isEmpty && account.axes.isComplete
    }

    /// The active preset's account is configured (§11.7).
    public var isConfigured: Bool { activeAccount.map(isAccountConfigured) ?? false }

    /// "default" for the first account (so the pre-filled "My open work" preset belongs to it), a UUID afterwards.
    public func newAccountId() -> String {
        config.account(id: JiraAccount.defaultId) == nil ? JiraAccount.defaultId : UUID().uuidString
    }

    public func makeAPI(accountId: String) throws -> JiraAPI {
        guard let account = config.account(id: accountId), let site = account.siteURL, !account.email.isEmpty,
              let token = tokens[accountId], !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, account.email, token)
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        if isRefreshing {
            if trigger == .manual { rerunRequested = true }
            return
        }
        guard isConfigured, let preset = config.activePreset,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI(accountId: preset.accountId) else { return }
        isRefreshing = true
        await fetch(api, preset: preset)
        isRefreshing = false
        if rerunRequested {
            rerunRequested = false
            await refresh(.manual)
        }
    }

    private func fetch(_ api: JiraAPI, preset: JQLPreset) async {
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            let result = try await api.search(jql: preset.jql, fields: fetchFields(), cap: Self.issueCap)
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
        banner = nil // stale error; the next refresh re-sets it if still failing
        persist(newConfig)
        scheduler.resume()
    }

    /// Inserts or updates the account and stores its token in Keychain (token first: a Keychain error changes nothing).
    public func saveAccount(_ account: JiraAccount, token: String) throws {
        try tokenStore.write(token, accountId: account.id)
        tokens[account.id] = token
        tokenErrorAccounts.remove(account.id)
        var c = config
        c.upsertAccount(account)
        updateConfig(c)
    }

    public func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void) {
        var c = config
        guard let i = c.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        change(&c.accounts[i].axes)
        updateConfig(c)
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

    /// Persists the live camera view (restored on launch). Deliberately no rebuild: the chart already shows it.
    public func saveLastView(yaw: Double, pitch: Double, zoom: Double) {
        guard yaw.isFinite, pitch.isFinite, zoom.isFinite else { return }
        let normalizedYaw = (((yaw + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        var c = config
        c.lastView = ViewDefaults(yaw: normalizedYaw, pitch: min(89, max(-89, pitch)), zoom: min(3, max(0.5, zoom)))
        config = c
        try? configStore.save(c)
    }

    public func selectPreset(id: String) {
        guard config.presets.contains(where: { $0.id == id }) else { return }
        var c = config
        c.activePresetId = id
        updateConfig(c)
    }

    public func issueURL(key: String) -> URL? {
        activeAccount?.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
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

    private func loadToken(_ accountId: String) {
        do {
            tokens[accountId] = try tokenStore.read(accountId: accountId)
            tokenErrorAccounts.remove(accountId)
        } catch {
            tokens[accountId] = nil
            tokenErrorAccounts.insert(accountId)
        }
    }

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = activeAccount?.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func rebuild(previous: [String: MappedTask]?) {
        let account = activeAccount
        if let account, let site = account.siteURL {
            lastMapped = AxisMapper.map(issues: issues, axes: account.axes, site: site, now: now(), calendar: calendar)
        } else {
            lastMapped = []
        }
        var unmapped: [Axis: [String]] = [:]
        var axisBanner: String?
        for axis in Axis.allCases {
            guard let mapping = account?.axes[axis].mapping else { continue }
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

In `Sources/OTMCore/RenderState.swift` (builder, last argument line of `RenderState(...)`), replace

```swift
                           activePresetId: config.activePreset.id, configured: configured)
```

with

```swift
                           activePresetId: config.activePreset?.id ?? "", configured: configured)
```

- [ ] **Step 5: Port the Settings call sites (temporary until Tasks 8–10)**

In `Sources/OnscreenTodoMatrix/SettingsViewModel.swift`:

Replace (in `init`)

```swift
        site = model.config.site
        email = model.config.email
        token = model.storedToken ?? ""
```

with

```swift
        let account = model.activeAccount
        site = account?.site ?? ""
        email = account?.email ?? ""
        token = account.flatMap { model.storedToken(accountId: $0.id) } ?? ""
```

Replace (in `saveAndTest()`)

```swift
        var c = model.config
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
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
```

with

```swift
        var account = model.activeAccount ?? JiraAccount(id: model.newAccountId(), name: "Personal")
        account.site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.saveAccount(account, token: token)
        } catch {
            connectionStatus = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        do {
            let me = try await model.makeAPI(accountId: account.id).myself()
```

Replace (first line of `loadFields()`)

```swift
        guard let api = try? model.makeAPI() else { return }
```

with

```swift
        guard let account = model.activeAccount, let api = try? model.makeAPI(accountId: account.id) else { return }
```

Replace (end of `loadFields()`)

```swift
        let suggested = DefaultMappings.suggest(fields: fields, current: model.config.axes)
        if suggested != model.config.axes {
            var c = model.config
            c.axes = suggested
            model.updateConfig(c)
        }
```

with

```swift
        let suggested = DefaultMappings.suggest(fields: fields, current: account.axes)
        if suggested != account.axes { model.updateAxes(accountId: account.id) { $0 = suggested } }
```

Replace (in `testJQL(_:)`)

```swift
            let n = try await model.makeAPI().approximateCount(jql: preset.jql)
```

with

```swift
            let n = try await model.makeAPI(accountId: preset.accountId).approximateCount(jql: preset.jql)
```

In `Sources/OnscreenTodoMatrix/SettingsView.swift`:

Replace

```swift
            step("1. Connect", done: vm.isConnected || (model.storedToken != nil && model.config.siteURL != nil))
```

with

```swift
            step("1. Connect", done: vm.isConnected || (model.activeAccount.map { model.storedToken(accountId: $0.id) != nil && $0.siteURL != nil } ?? false))
```

Replace

```swift
            step("3. Axes", done: model.config.axes.isComplete)
```

with

```swift
            step("3. Axes", done: model.activeAccount?.axes.isComplete ?? false)
```

Replace (FiltersTab "Add preset")

```swift
                c.presets.append(JQLPreset(id: UUID().uuidString, name: "New preset", jql: "assignee = currentUser() AND statusCategory != Done"))
```

with

```swift
                c.presets.append(JQLPreset(id: UUID().uuidString, name: "New preset", jql: "assignee = currentUser() AND statusCategory != Done",
                                           accountId: model.activeAccount?.id ?? JiraAccount.defaultId))
```

Replace (FiltersTab `delete`)

```swift
        if wasActive { c.activePresetId = c.presets.first?.id ?? JQLPreset.myOpenWork.id }
```

with

```swift
        if wasActive { c.activePresetId = c.presets.first?.id ?? "" }
```

Replace (AxisEditor)

```swift
    private var cfg: AxisConfig { model.config.axes[axis] }

    private func update(_ change: (inout AxisConfig) -> Void) {
        var c = model.config
        change(&c.axes[axis])
        model.updateConfig(c)
    }
```

with

```swift
    private var cfg: AxisConfig { model.activeAccount?.axes[axis] ?? AxisConfig() }

    private func update(_ change: (inout AxisConfig) -> Void) {
        guard let id = model.activeAccount?.id else { return }
        model.updateAxes(accountId: id) { change(&$0[axis]) }
    }
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `swift build && swift test`
Expected: `Build complete!`, then `✔ Test run with 93 tests in 17 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(otm): accounts data model and keyed token store (v1.2.0)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Per-preset issue cache

One cache file per preset (`cache/<presetId>.json` with `issues`, `fetchedAt`, `accountId`) so switching presets shows that preset's own data instantly, plus the move of the v1.1 `last-fetch.json` used by the migration (Task 3).

**Files:**
- Modify (full replacement): `SRC/Sources/OTMCore/IssueCache.swift`
- Modify: `SRC/Sources/OTMCore/AppModel.swift` (2 call sites)
- Test: `SRC/Tests/OTMCoreTests/StoresTests.swift`, `SRC/Tests/OTMCoreTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `AppConfig.activePreset`, `JQLPreset.accountId` (Task 1).
- Produces:
  - `struct CachedFetch: Codable, Equatable, Sendable { var issues: [JiraIssue]; var fetchedAt: Date; var accountId: String; init(issues:fetchedAt:accountId:) }` — decodes v1.1 files without `accountId` as `""`.
  - `final class IssueCache { let directory: URL /* <dir>/cache */; let legacyURL: URL /* <dir>/last-fetch.json */; init(directory: URL); func url(presetId: String) -> URL; func save(_ fetch: CachedFetch, presetId: String) throws; func load(presetId: String) -> CachedFetch?; func delete(presetId: String); func migrateLegacy(toPresetId presetId: String, accountId: String) }`

- [ ] **Step 1: Write the failing tests**

In `Tests/OTMCoreTests/StoresTests.swift`, replace the whole `@Suite struct IssueCacheTests { … }` with:

```swift
@Suite struct IssueCacheTests {
    let fetch = CachedFetch(issues: [JiraIssue(key: "SEC-5", fields: ["summary": .string("Rotate key")])],
                            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), accountId: "default")

    @Test func emptyCacheLoadsNil() {
        #expect(IssueCache(directory: makeTempDir()).load(presetId: "my-open-work") == nil)
    }

    @Test func roundTripsPerPreset() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        var other = fetch
        other.issues = []
        other.accountId = "c1"
        try cache.save(fetch, presetId: "my-open-work")
        try cache.save(other, presetId: "p2")
        #expect(cache.load(presetId: "my-open-work") == fetch)
        #expect(cache.load(presetId: "p2") == other)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cache/my-open-work.json").path))
        cache.delete(presetId: "p2")
        #expect(cache.load(presetId: "p2") == nil)
    }

    @Test func presetIdCannotEscapeTheCacheFolder() throws {
        // Review Focus #4
        let cache = IssueCache(directory: makeTempDir())
        for id in ["../config", "a/b", "..", "x.json"] {
            let url = cache.url(presetId: id)
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == cache.directory.standardizedFileURL.path)
            #expect(!url.lastPathComponent.hasPrefix("."))
        }
        try cache.save(fetch, presetId: "../config")
        #expect(cache.load(presetId: "../config") == fetch)
    }

    @Test func legacyFileMovesToActivePresetOnce() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        try Data(#"{"issues":[{"key":"A-1","fields":{}}],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8).write(to: cache.legacyURL)
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default")
        let moved = cache.load(presetId: "my-open-work")
        #expect(moved?.issues.map(\.key) == ["A-1"])
        #expect(moved?.accountId == "default")
        #expect(!FileManager.default.fileExists(atPath: cache.legacyURL.path))
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default") // no legacy file: no-op
        #expect(cache.load(presetId: "my-open-work") == moved)
    }

    @Test func legacyMoveNeverOverwritesAnExistingPresetCache() throws {
        let dir = makeTempDir()
        let cache = IssueCache(directory: dir)
        try cache.save(fetch, presetId: "my-open-work")
        try Data(#"{"issues":[],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8).write(to: cache.legacyURL)
        cache.migrateLegacy(toPresetId: "my-open-work", accountId: "default")
        #expect(cache.load(presetId: "my-open-work") == fetch)
        #expect(FileManager.default.fileExists(atPath: cache.legacyURL.path))
    }
}
```

In `Tests/OTMCoreTests/AppModelTests.swift`, in `successfulRefreshRendersAndCaches()`, replace

```swift
        #expect(IssueCache(directory: dir).load()?.issues.count == 1)
```

with

```swift
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.count == 1)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.accountId == "default")
```

and in `offlineShowsCachedDataTime()`, replace

```swift
        try? IssueCache(directory: dir).save(CachedFetch(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                         fetchedAt: clockNow.addingTimeInterval(-600)))
```

with

```swift
        try? IssueCache(directory: dir).save(CachedFetch(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                         fetchedAt: clockNow.addingTimeInterval(-600), accountId: "default"),
                                             presetId: "my-open-work")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IssueCacheTests`
Expected: build FAILS with `extra argument 'accountId' in call` / `incorrect argument label in call (have 'presetId:', expected …)`.

- [ ] **Step 3: Implement the per-preset cache**

Replace `Sources/OTMCore/IssueCache.swift` with:

```swift
import Foundation

public struct CachedFetch: Codable, Equatable, Sendable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    /// Account the issues came from; a cache whose account differs from the preset's is ignored.
    public var accountId: String

    public init(issues: [JiraIssue], fetchedAt: Date, accountId: String) {
        self.issues = issues
        self.fetchedAt = fetchedAt
        self.accountId = accountId
    }

    private enum CodingKeys: String, CodingKey { case issues, fetchedAt, accountId }

    /// v1.1 `last-fetch.json` has no `accountId`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issues = try c.decode([JiraIssue].self, forKey: .issues)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId) ?? ""
    }
}

/// Last successful fetch per preset: `<app support>/cache/<presetId>.json` (§11.5).
public final class IssueCache {
    public let directory: URL
    /// v1.1 single cache file, moved by `migrateLegacy`.
    public let legacyURL: URL

    public init(directory: URL) {
        self.directory = directory.appendingPathComponent("cache")
        legacyURL = directory.appendingPathComponent("last-fetch.json")
    }

    /// Percent-encodes everything but letters, digits, "-" and "_" so a hand-edited id can't leave the cache folder.
    public func url(presetId: String) -> URL {
        let safe = presetId.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? "invalid"
        return directory.appendingPathComponent(safe + ".json")
    }

    private static let fileNameCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    public func save(_ fetch: CachedFetch, presetId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(fetch).write(to: url(presetId: presetId), options: .atomic)
    }

    public func load(presetId: String) -> CachedFetch? {
        Self.decode(at: url(presetId: presetId))
    }

    public func delete(presetId: String) {
        try? FileManager.default.removeItem(at: url(presetId: presetId))
    }

    /// Moves v1.1 `last-fetch.json` to `cache/<presetId>.json`, tagged with `accountId`.
    /// No-op when there is no readable legacy file or the destination already exists.
    public func migrateLegacy(toPresetId presetId: String, accountId: String) {
        guard var legacy = Self.decode(at: legacyURL),
              !FileManager.default.fileExists(atPath: url(presetId: presetId).path) else { return }
        legacy.accountId = accountId
        guard (try? save(legacy, presetId: presetId)) != nil else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private static func decode(at url: URL) -> CachedFetch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CachedFetch.self, from: data)
    }
}
```

In `Sources/OTMCore/AppModel.swift` (init), replace

```swift
        if let cached = cache.load() {
```

with

```swift
        if let preset = config.activePreset, let cached = cache.load(presetId: preset.id), cached.accountId == preset.accountId {
```

and (in `fetch`) replace

```swift
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt))
```

with

```swift
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt, accountId: preset.accountId), presetId: preset.id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: `✔ Test run with 96 tests in 17 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests
git commit -m "feat(otm): issue cache per preset (cache/<presetId>.json)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: v1.1 → v1.2 migration (never lose the user's setup)

`ConfigStore.load()` recognises a v1.1 file (no `accounts` key), converts it in memory and returns `.legacy` without writing. `ConfigMigration.finish` then backs up `config.json` → `config.v1.json`, copies the Keychain token `jira-api-token` → `jira-api-token:default` (legacy item deleted only after the copy is read back equal), moves `last-fetch.json` → `cache/<activePresetId>.json` and saves the new format. Any failure leaves `config.json` and the legacy item untouched so the next launch retries.

**Files:**
- Create: `SRC/fixtures/config-v1.1.json` (exact shape of the user's real v1.1 config; fake site/email)
- Create: `SRC/Sources/OTMCore/ConfigMigration.swift`
- Modify (full replacement): `SRC/Sources/OTMCore/ConfigStore.swift`
- Modify: `SRC/Sources/OTMCore/AppModel.swift` (init + one property)
- Test: `SRC/Tests/OTMCoreTests/MigrationTests.swift` (create), `SRC/Tests/OTMCoreTests/StoresTests.swift`

**Interfaces:**
- Consumes: `AppConfig` tolerant decoding, `JiraAccount.defaultId`, `TokenStore` legacy methods (Task 1); `IssueCache.migrateLegacy(toPresetId:accountId:)`, `IssueCache.legacyURL` (Task 2).
- Produces:
  - `enum ConfigLoadResult: Equatable { case loaded(AppConfig), legacy(AppConfig), missing, corrupt(backup: URL) }`
  - `ConfigStore.legacyBackupURL: URL` (`<dir>/config.v1.json`)
  - `struct LegacyAppConfigV1: Decodable { var site: String?; var email: String?; var axes: AxesConfig? }` (internal)
  - `enum ConfigMigration { static func migrated(from data: Data) throws -> AppConfig; static func finish(_ config: AppConfig, store: ConfigStore, tokens: TokenStore, cache: IssueCache) -> Bool }`
  - `AppModel.migrationFailed: Bool` (public read-only)
  - Test helper `enum MigrationTestError: Error { case notLegacy }`

- [ ] **Step 1: Add the v1.1 fixture**

Create `fixtures/config-v1.1.json` exactly as below. It is a byte-for-byte copy of the shape the app v1.1 writes (pretty-printed, sorted keys, escaped `\/` in the site, number mapping without `min`/`max`), with a fake site and email. Do not "clean it up".

```json
{
  "activePresetId" : "my-open-work",
  "axes" : {
    "effort" : {
      "mapping" : {
        "number" : {
          "fieldId" : "timeoriginalestimate",
          "invert" : false
        }
      },
      "missingDefault" : 0
    },
    "urgency" : {
      "mapping" : {
        "option" : {
          "fieldId" : "priority",
          "levels" : {
            "High" : 3.75,
            "Highest" : 5,
            "Low" : 1.25,
            "Lowest" : 0,
            "Medium" : 2.5
          }
        }
      },
      "missingDefault" : 0
    },
    "value" : {
      "mapping" : {
        "option" : {
          "fieldId" : "customfield_10110",
          "levels" : {
            "2 Low" : 2,
            "3 Medium" : 3,
            "4 High" : 4,
            "5 Highest" : 5
          }
        }
      },
      "missingDefault" : 0
    }
  },
  "email" : "me@example.com",
  "lastView" : {
    "pitch" : 33.9,
    "yaw" : -179.7,
    "zoom" : 0.6575736466253159
  },
  "launchAtLogin" : true,
  "presets" : [
    {
      "id" : "my-open-work",
      "jql" : "statusCategory != Done ORDER BY priority DESC",
      "name" : "My open work"
    }
  ],
  "quick" : {
    "alwaysOnTop" : false,
    "colorMode" : "rgb",
    "grid" : true,
    "labelMode" : "smart",
    "panelOpacity" : 100,
    "refreshMinutes" : 15,
    "rotation" : "free",
    "stemOpacity" : 30,
    "stemStyle" : "dotted",
    "zoneNames" : true
  },
  "site" : "https:\/\/example-personal.atlassian.net",
  "view" : {
    "pitch" : 33.9,
    "yaw" : -179.7,
    "zoom" : 1
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/OTMCoreTests/MigrationTests.swift`:

```swift
import Foundation
import Testing
@testable import OTMCore

/// v1.1 → v1.2 migration (§11.4). The fixture has the exact shape of a real v1.1 config (fake site/email).
@MainActor
@Suite struct MigrationTests {
    let dir = makeTempDir()

    func fixture() throws -> Data {
        try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/config-v1.1.json"))
    }

    /// Writes the v1.1 fixture as config.json (and optionally a v1.1 last-fetch.json).
    func legacyStore(withCache: Bool = false) throws -> ConfigStore {
        let store = ConfigStore(directory: dir)
        try fixture().write(to: store.url)
        if withCache {
            try Data(#"{"issues":[{"key":"A-1","fields":{}}],"fetchedAt":"2026-10-13T06:46:00Z"}"#.utf8)
                .write(to: IssueCache(directory: dir).legacyURL)
        }
        return store
    }

    func legacyConfig(_ store: ConfigStore) throws -> AppConfig {
        guard case .legacy(let c) = store.load() else { throw MigrationTestError.notLegacy }
        return c
    }

    @Test func realShapeV11IsLegacyNotCorruptAndLossless() throws {
        // Review Focus #1
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let c = try legacyConfig(store)
        #expect(try Data(contentsOf: store.url) == original) // load() never writes
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.bak").path))

        #expect(c.accounts.count == 1)
        let a = c.accounts[0]
        #expect(a.id == "default")
        #expect(a.name == "Personal")
        #expect(a.site == "https://example-personal.atlassian.net")
        #expect(a.siteURL?.absoluteString == "https://example-personal.atlassian.net")
        #expect(a.email == "me@example.com")
        #expect(a.axes.value == AxisConfig(mapping: .option(fieldId: "customfield_10110",
                                                            levels: ["2 Low": 2, "3 Medium": 3, "4 High": 4, "5 Highest": 5]),
                                           missingDefault: 0))
        #expect(a.axes.effort == AxisConfig(mapping: .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false),
                                            missingDefault: 0))
        #expect(a.axes.urgency == AxisConfig(mapping: .option(fieldId: "priority", levels: DefaultMappings.priorityLevels),
                                             missingDefault: 0))
        #expect(c.presets == [JQLPreset(id: "my-open-work", name: "My open work",
                                        jql: "statusCategory != Done ORDER BY priority DESC", accountId: "default")])
        #expect(c.activePresetId == "my-open-work")
        #expect(c.activeAccount?.id == "default")
        #expect(c.view == ViewDefaults())
        #expect(c.lastView == ViewDefaults(yaw: -179.7, pitch: 33.9, zoom: 0.6575736466253159))
        var quick = QuickSettings()
        quick.refreshMinutes = 15
        quick.rotation = "free"
        #expect(c.quick == quick)
        #expect(c.launchAtLogin)
    }

    @Test func finishBacksUpCopiesTokenMovesCacheAndSaves() throws {
        let store = try legacyStore(withCache: true)
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let cache = IssueCache(directory: dir)
        let c = try legacyConfig(store)

        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache))

        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
        #expect(try tokens.read(accountId: "default") == "legacy-tok")
        #expect(tokens.legacyToken == nil)
        #expect(cache.load(presetId: "my-open-work")?.issues.map(\.key) == ["A-1"])
        #expect(cache.load(presetId: "my-open-work")?.accountId == "default")
        #expect(!FileManager.default.fileExists(atPath: cache.legacyURL.path))
        #expect(store.load() == .loaded(c))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        #expect(raw["site"] == nil)
        #expect(raw["email"] == nil)
        #expect(raw["axes"] == nil)
        #expect(raw["accounts"] != nil)
    }

    @Test func migrationIsIdempotent() throws {
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let cache = IssueCache(directory: dir)
        let c = try legacyConfig(store)
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache))
        let saved = try Data(contentsOf: store.url)

        #expect(store.load() == .loaded(c))                                       // second load: no migration
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: cache)) // re-running changes nothing
        #expect(try Data(contentsOf: store.url) == saved)
        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
        #expect(try tokens.read(accountId: "default") == "legacy-tok")
    }

    @Test func emptySiteCreatesNoAccountAndKeepsLegacyToken() throws {
        let store = ConfigStore(directory: dir)
        try Data(#"{"site":"","email":"","presets":[{"id":"my-open-work","name":"My open work","jql":"x"}],"activePresetId":"my-open-work"}"#.utf8)
            .write(to: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "t")
        let c = try legacyConfig(store)
        #expect(c.accounts.isEmpty)
        #expect(c.presets.map(\.accountId) == ["default"])
        #expect(c.quick == QuickSettings())
        #expect(ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.tokens.isEmpty)
        #expect(tokens.legacyToken == "t")
    }

    @Test func keychainWriteFailureKeepsLegacyItemAndOldFile() throws {
        // Review Focus #2
        let store = try legacyStore()
        let original = try Data(contentsOf: store.url)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let c = try legacyConfig(store)
        #expect(!ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.legacyToken == "legacy-tok")
        #expect(try Data(contentsOf: store.url) == original)            // still v1.1 → retried next launch
        #expect(try Data(contentsOf: store.legacyBackupURL) == original)
    }

    @Test func unverifiedCopyKeepsLegacyItem() throws {
        // Review Focus #2: the write "succeeds" but nothing can be read back.
        let store = try legacyStore()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.dropsWrites = true
        let c = try legacyConfig(store)
        #expect(!ConfigMigration.finish(c, store: store, tokens: tokens, cache: IssueCache(directory: dir)))
        #expect(tokens.legacyToken == "legacy-tok")
    }

    @Test func appModelMigratesOnLaunch() throws {
        _ = try legacyStore(withCache: true)
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(!m.configWasCorrupt)
        #expect(!m.migrationFailed)
        #expect(m.config.accounts.map(\.id) == ["default"])
        #expect(m.storedToken(accountId: "default") == "legacy-tok")
        #expect(m.isConfigured)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }

    @Test func appModelReportsMigrationFailure() throws {
        _ = try legacyStore()
        let tokens = InMemoryTokenStore(legacyToken: "legacy-tok")
        tokens.writeError = TokenStoreError.status(-25308)
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(), makeClient: { _, _, _ in FakeJiraAPI() })
        #expect(m.migrationFailed)
        #expect(!m.configWasCorrupt)
        #expect(m.config.accounts.map(\.id) == ["default"]) // the user still sees their setup
    }
}

enum MigrationTestError: Error { case notLegacy }
```

In `Tests/OTMCoreTests/StoresTests.swift`, add these two tests at the end of `ConfigStoreTests` (after `corruptFileIsBackedUpNotLost()`):

```swift
    @Test func nonObjectJSONIsCorrupt() throws {
        let store = ConfigStore(directory: makeTempDir())
        try Data("[]".utf8).write(to: store.url)
        guard case .corrupt = store.load() else { Issue.record("expected .corrupt"); return }
    }

    @Test func wrongTypeInV12FileIsCorrupt() throws {
        let store = ConfigStore(directory: makeTempDir())
        try Data(#"{"accounts":[],"presets":5}"#.utf8).write(to: store.url)
        guard case .corrupt = store.load() else { Issue.record("expected .corrupt"); return }
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter MigrationTests`
Expected: build FAILS with `type 'ConfigLoadResult' has no member 'legacy'` and `cannot find 'ConfigMigration' in scope`.

- [ ] **Step 4: Implement the store and the migration**

Replace `Sources/OTMCore/ConfigStore.swift` with:

```swift
import Foundation

public enum ConfigLoadResult: Equatable {
    case loaded(AppConfig)
    /// A v1.1 file (no `accounts` key), converted in memory only; `ConfigMigration.finish` persists it.
    case legacy(AppConfig)
    case missing
    case corrupt(backup: URL)
}

public final class ConfigStore {
    public let url: URL
    /// Backup of the v1.1 file, written by the migration and kept.
    public let legacyBackupURL: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("config.json")
        legacyBackupURL = directory.appendingPathComponent("config.v1.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onscreen-todo-matrix")
    }

    /// Never rewrites a readable file: a v1.1 file comes back as `.legacy` and stays on disk untouched.
    public func load() -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            if object["accounts"] == nil { return .legacy(try ConfigMigration.migrated(from: data)) }
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

Create `Sources/OTMCore/ConfigMigration.swift`:

```swift
import Foundation

/// The v1.1 keys that moved into `accounts[]` in v1.2 (§11.4). Every key optional: tolerant decoding.
struct LegacyAppConfigV1: Decodable {
    var site: String?
    var email: String?
    var axes: AxesConfig?
}

/// v1.1 → v1.2: one account per Jira site, keyed tokens, cache per preset. Must never lose the user's setup.
public enum ConfigMigration {
    /// Pure conversion of a v1.1 `config.json`. Presets, active preset, views, quick settings and
    /// launch-at-login decode as-is; site/email/axes become account "default" (no account when the site is empty).
    public static func migrated(from data: Data) throws -> AppConfig {
        let decoder = JSONDecoder()
        var config = try decoder.decode(AppConfig.self, from: data)
        let legacy = try decoder.decode(LegacyAppConfigV1.self, from: data)
        let site = (legacy.site ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        config.accounts = site.isEmpty ? [] : [JiraAccount(id: JiraAccount.defaultId, name: "Personal", site: site,
                                                           email: legacy.email ?? "", axes: legacy.axes ?? AxesConfig())]
        config.presets = config.presets.map { var p = $0; p.accountId = JiraAccount.defaultId; return p }
        return config
    }

    /// Persists a `.legacy` config:
    /// 1. copy `config.json` → `config.v1.json` (kept);
    /// 2. copy the Keychain token `jira-api-token` → `jira-api-token:default`, delete the legacy item only after
    ///    reading the copy back;
    /// 3. move `last-fetch.json` → `cache/<activePresetId>.json`;
    /// 4. save the new format.
    /// Returns false — leaving `config.json` and the legacy token untouched — if step 1, 2 or 4 fails.
    /// Every step is idempotent, so the next launch simply retries.
    public static func finish(_ config: AppConfig, store: ConfigStore, tokens: TokenStore, cache: IssueCache) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: store.legacyBackupURL.path) {
            guard (try? fm.copyItem(at: store.url, to: store.legacyBackupURL)) != nil else { return false }
        }
        if config.account(id: JiraAccount.defaultId) != nil {
            do {
                if let legacy = try tokens.readLegacy() {
                    if try tokens.read(accountId: JiraAccount.defaultId) != legacy {
                        try tokens.write(legacy, accountId: JiraAccount.defaultId)
                    }
                    guard try tokens.read(accountId: JiraAccount.defaultId) == legacy else { return false }
                    try? tokens.deleteLegacy()
                }
            } catch {
                return false
            }
        }
        if let preset = config.activePreset {
            cache.migrateLegacy(toPresetId: preset.id, accountId: preset.accountId)
        }
        return (try? store.save(config)) != nil
    }
}
```

In `Sources/OTMCore/AppModel.swift`, replace

```swift
    public private(set) var configWasCorrupt = false
```

with

```swift
    public private(set) var configWasCorrupt = false
    /// The v1.1 → v1.2 migration could not finish; the old setup is kept (§11.10).
    public private(set) var migrationFailed = false
```

and in `init`, replace

```swift
        case .loaded(let c): config = c
        case .missing: config = AppConfig()
```

with

```swift
        case .loaded(let c): config = c
        case .legacy(let c):
            config = c
            migrationFailed = !ConfigMigration.finish(c, store: configStore, tokens: tokenStore, cache: cache)
        case .missing: config = AppConfig()
```

(The migration runs before tokens and the cache are loaded, so the first frame already shows the migrated cache with the copied token.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: `✔ Test run with 106 tests in 18 suites passed`. In particular `realShapeV11IsLegacyNotCorruptAndLossless`, `keychainWriteFailureKeepsLegacyItemAndOldFile`, `unverifiedCopyKeepsLegacyItem` and `migrationIsIdempotent` pass.

- [ ] **Step 6: Commit**

```bash
git add fixtures/config-v1.1.json Sources/OTMCore Tests/OTMCoreTests
git commit -m "feat(otm): migrate v1.1 config, token and cache to accounts (backup config.v1.json)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: RenderState contract (accounts, presets[].accountId, setup, bannerTab, axisLabels) + shared fixture + JS `validateState`

Extends the Swift ↔ JS contract per §11.8 (plus the routing fields of Ruling 10 and the axis field names of §11.8.1), updates the shared fixture used by both suites, and saves each axis' Jira field display name with its mapping (`AxisConfig.fieldName`) so the chart can label axes offline.

**Files:**
- Modify (full replacement): `SRC/Sources/OTMCore/RenderState.swift`, `SRC/fixtures/render-state.json`, `SRC/chart/src/state.js`
- Modify: `SRC/Sources/OTMCore/Models.swift` (`AxisConfig`), `SRC/Sources/OTMCore/AxisMapper.swift` (`DefaultMappings`)
- Modify: `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift` (AxisEditor field picker saves `fieldName`; Task 10 replaces this view)
- Test: `SRC/Tests/OTMCoreTests/ScorerRenderStateTests.swift`, `SRC/Tests/OTMCoreTests/AxisMapperTests.swift`, `SRC/chart/test/state.test.js`

**Interfaces:**
- Consumes: `AppConfig.menuOrderedPresets`, `AppConfig.activePreset`, `AppConfig.activeAccount`, `AccountPalette.color(at:)` (Task 1).
- Produces:
  - `AxisConfig.fieldName: String?` (init gains `fieldName: String? = nil`, last parameter) and `AxisConfig.labelName: String?` (= `fieldName ?? mapping.fieldId`, nil when unmapped)
  - `DefaultMappings.withFieldNames(_ axes: AxesConfig, fields: [JiraField]) -> AxesConfig`; `DefaultMappings.suggest` now also refreshes `fieldName` of every mapped axis whose field is in `fields`
  - `struct RenderAccount: Codable, Equatable, Sendable { var id, name, color: String; var error: Bool; init(id:name:color:error:) }`
  - `struct RenderPreset { var id, name, accountId: String; init(id:name:accountId:) }`
  - `struct RenderSetup: Codable, Equatable, Sendable { var message: String; var tab: String; init(message:tab:) }`
  - `struct RenderAxisLabels: Codable, Equatable, Sendable { var value, effort, urgency: String?; init(value:effort:urgency:) ; init(axes: AxesConfig?) }`
  - `RenderStatus.bannerTab: String?` (init gains `bannerTab: String? = nil`, last parameter)
  - `RenderState { …, accounts: [RenderAccount], presets: [RenderPreset] /* menu order */, activePresetId, configured, setup: RenderSetup?, axisLabels: RenderAxisLabels }`
  - `RenderStateBuilder.build(tasks:previous:config:status:configured:accountErrors: Set<String> = [], setup: RenderSetup? = nil) -> RenderState` (axis labels come from `config.activeAccount?.axes`)
  - JSON: nil optionals are omitted (`setup`, `bannerTab`, unmapped `axisLabels` keys); `accounts` is always present.
  - JS: `validateState(s)` additionally checks `accounts[]` (`id`, `name`, `color` strings, `error` boolean), `presets[].{id,name,accountId}` strings, `activePresetId` string, optional `setup {message, tab}`, `axisLabels` object of optional strings.

- [ ] **Step 1: Write the failing tests**

In `Tests/OTMCoreTests/ScorerRenderStateTests.swift` (`RenderStateTests`):

In `buildCopiesConfigAndScores()`, replace

```swift
        #expect(s.presets == [RenderPreset(id: "my-open-work", name: "My open work"), RenderPreset(id: "p2", name: "Team")])
```

with

```swift
        #expect(s.presets == [RenderPreset(id: "my-open-work", name: "My open work", accountId: "default"),
                              RenderPreset(id: "p2", name: "Team", accountId: "default")])
        #expect(s.accounts.isEmpty)
        #expect(s.setup == nil)
```

In `sharedFixtureDecodesAndRoundTrips()`, replace

```swift
        #expect(state.settings == QuickSettings())
```

with

```swift
        #expect(state.settings == QuickSettings())
        #expect(state.accounts == [RenderAccount(id: "default", name: "Personal", color: "#3b82f6", error: false),
                                   RenderAccount(id: "c1f0", name: "Company", color: "#f59e0b", error: true)])
        #expect(state.presets.map(\.accountId) == ["default", "default", "c1f0"])
        #expect(state.activePresetId == "my-open-work")
        #expect(state.setup == nil)
        #expect(state.status.bannerTab == nil)
        #expect(state.axisLabels == RenderAxisLabels(value: "Business Value", effort: "Story Points", urgency: "Priority"))
```

and insert before `@Test func sharedFixtureDecodesAndRoundTrips() throws {`:

```swift
    @Test func buildEmitsAccountsWithColoursErrorsAndPresetsInMenuOrder() {
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal"), JiraAccount(id: "c1", name: "Company")]
        c.presets = [JQLPreset(id: "cw", name: "My company work", jql: "x", accountId: "c1"),
                     JQLPreset(id: "mine", name: "My open work", jql: "x", accountId: "default")]
        c.activePresetId = "cw"
        let setup = RenderSetup(message: "Map axes for Company to see this preset", tab: "axes")
        let s = RenderStateBuilder.build(tasks: [], previous: nil, config: c, status: RenderStatus(bannerTab: "accounts"),
                                         configured: false, accountErrors: ["c1"], setup: setup)
        #expect(s.accounts == [RenderAccount(id: "default", name: "Personal", color: "#3b82f6", error: false),
                               RenderAccount(id: "c1", name: "Company", color: "#f59e0b", error: true)])
        #expect(s.presets.map(\.id) == ["mine", "cw"])
        #expect(s.activePresetId == "cw")
        #expect(s.setup == setup)
        #expect(s.status.bannerTab == "accounts")
    }

    @Test func axisLabelsComeFromTheActiveAccount() throws {
        var personal = AxesConfig()
        personal.urgency = AxisConfig(mapping: .option(fieldId: "priority", levels: [:]), fieldName: "Priority")
        var company = AxesConfig()
        company.value = AxisConfig(mapping: .option(fieldId: "customfield_200", levels: [:]), fieldName: "Business Value")
        company.effort = AxisConfig(mapping: .number(fieldId: "customfield_201", min: nil, max: nil, invert: false))
        var c = AppConfig()
        c.accounts = [JiraAccount(id: "default", name: "Personal", axes: personal),
                      JiraAccount(id: "c1", name: "Company", axes: company)]
        c.presets.append(JQLPreset(id: "p2", name: "My company work", jql: "x", accountId: "c1"))
        let mine = RenderStateBuilder.build(tasks: [], previous: nil, config: c, status: RenderStatus(), configured: true)
        #expect(mine.axisLabels == RenderAxisLabels(value: nil, effort: nil, urgency: "Priority"))
        c.activePresetId = "p2"
        let theirs = RenderStateBuilder.build(tasks: [], previous: nil, config: c, status: RenderStatus(), configured: true)
        #expect(theirs.axisLabels == RenderAxisLabels(value: "Business Value", effort: "customfield_201", urgency: nil))
        let json = String(decoding: try RenderStateBuilder.encoder().encode(theirs), as: UTF8.self)
        #expect(json.contains(#""axisLabels":{"effort":"customfield_201","value":"Business Value"}"#))
    }

    @Test func absentOptionalsAreOmittedFromJSON() throws {
        let s = RenderStateBuilder.build(tasks: [], previous: nil, config: AppConfig(), status: RenderStatus(), configured: true)
        let json = String(decoding: try RenderStateBuilder.encoder().encode(s), as: UTF8.self)
        #expect(!json.contains("\"setup\""))
        #expect(!json.contains("\"bannerTab\""))
        #expect(json.contains("\"accounts\":[]"))
    }

```

In `Tests/OTMCoreTests/AxisMapperTests.swift` (`DefaultMappingsTests`), replace

```swift
        #expect(DefaultMappings.suggest(fields: fields, current: cur).urgency == cur.urgency)
```

with

```swift
        #expect(DefaultMappings.suggest(fields: fields, current: cur).urgency.mapping == cur.urgency.mapping)
```

and insert before `@Test func priorityLevelsMatchSpec() {`:

```swift
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

```

Append to `chart/test/state.test.js`:

```js
test('accounts and presets[].accountId are validated (v1.2.0 contract)', () => {
  expect(fixture.accounts).toHaveLength(2);
  expect(fixture.presets.every((p) => typeof p.accountId === 'string')).toBe(true);
  const bad = structuredClone(fixture);
  delete bad.accounts;
  bad.presets[0].accountId = 7;
  const errs = validateState(bad);
  expect(errs).toContain('accounts must be an array');
  expect(errs).toContain('presets[0].accountId must be a string');
  const bad2 = structuredClone(fixture);
  bad2.accounts[1].error = 'yes';
  bad2.accounts[0].color = null;
  expect(validateState(bad2)).toEqual(['accounts[0].color must be a string', 'accounts[1].error must be a boolean']);
});
test('setup is optional but must carry message and tab', () => {
  const ok = structuredClone(fixture);
  ok.configured = false;
  ok.setup = { message: 'Map axes for Company to see this preset', tab: 'axes' };
  expect(validateState(ok)).toEqual([]);
  const bad = structuredClone(ok);
  delete bad.setup.tab;
  expect(validateState(bad)).toContain('setup must have string message and tab');
});
test('axisLabels: object of optional strings (omitted key = not mapped)', () => {
  expect(fixture.axisLabels).toEqual({ value: 'Business Value', effort: 'Story Points', urgency: 'Priority' });
  const ok = structuredClone(fixture);
  delete ok.axisLabels.value;
  expect(validateState(ok)).toEqual([]);
  const bad = structuredClone(fixture);
  bad.axisLabels.effort = 3;
  expect(validateState(bad)).toEqual(['axisLabels.effort must be a string']);
  delete bad.axisLabels;
  expect(validateState(bad)).toContain('axisLabels must be an object');
});
```

Replace `fixtures/render-state.json` with (adds `accounts`, a second Personal preset, a Company preset, `presets[].accountId`, `axisLabels`):

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
  "lastView": { "yaw": -150, "pitch": 30, "zoom": 1.2 },
  "settings": { "labelMode": "smart", "stemStyle": "dotted", "stemOpacity": 30, "colorMode": "rgb", "grid": true,
                "zoneNames": true, "rotation": "limited", "panelOpacity": 100, "alwaysOnTop": false, "refreshMinutes": 5 },
  "status": { "syncedAt": "2026-10-12T10:42:00Z", "banner": null, "truncated": null },
  "accounts": [ { "id": "default", "name": "Personal", "color": "#3b82f6", "error": false },
                { "id": "c1f0", "name": "Company", "color": "#f59e0b", "error": true } ],
  "presets": [ { "id": "my-open-work", "name": "My open work", "accountId": "default" },
               { "id": "due-week", "name": "Due this week", "accountId": "default" },
               { "id": "p2", "name": "My company work", "accountId": "c1f0" } ],
  "activePresetId": "my-open-work",
  "configured": true,
  "axisLabels": { "value": "Business Value", "effort": "Story Points", "urgency": "Priority" }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RenderStateTests`
Expected: build FAILS with `cannot find 'RenderAccount' in scope` / `extra argument 'accountId' in call`.
Run: `cd chart && npx vitest run test/state.test.js; cd ..`
Expected: FAIL — `accounts must be an array` is not reported and `axisLabels must be an object` is missing.

- [ ] **Step 3: Implement the contract**

In `Sources/OTMCore/Models.swift`, replace the whole `AxisConfig` struct

```swift
public struct AxisConfig: Codable, Equatable, Sendable {
    public var mapping: AxisMapping?
    public var missingDefault: Double
    public init(mapping: AxisMapping? = nil, missingDefault: Double = 0.5) {
        self.mapping = mapping
        self.missingDefault = missingDefault
    }
}
```

with

```swift
public struct AxisConfig: Codable, Equatable, Sendable {
    public var mapping: AxisMapping?
    public var missingDefault: Double
    /// Display name of the mapped Jira field (JiraField.name), saved with the mapping so the chart's axis
    /// label works offline (§11.8.1). nil → the label falls back to the field id. Optional: older files decode.
    public var fieldName: String?
    public init(mapping: AxisMapping? = nil, missingDefault: Double = 0.5, fieldName: String? = nil) {
        self.mapping = mapping
        self.missingDefault = missingDefault
        self.fieldName = fieldName
    }

    /// Axis-label name: the saved field name, else the field id; nil when unmapped.
    public var labelName: String? { mapping.map { fieldName ?? $0.fieldId } }
}
```

In `Sources/OTMCore/AxisMapper.swift` (`DefaultMappings`), replace

```swift
    /// Pre-fills empty axes: urgency ← Priority, effort ← Story Points / Story point estimate / Original estimate.
    public static func suggest(fields: [JiraField], current: AxesConfig) -> AxesConfig {
```

with

```swift
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
```

and at the end of `suggest`, replace

```swift
                a.effort.mapping = .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false)
            }
        }
        return a
    }
```

with

```swift
                a.effort.mapping = .number(fieldId: "timeoriginalestimate", min: nil, max: nil, invert: false)
            }
        }
        return withFieldNames(a, fields: fields)
    }
```

Replace `Sources/OTMCore/RenderState.swift` with:

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
                              score: s.score, rank: s.rank, fire: s.fire, changed: changed)
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
```

Replace `chart/src/state.js` with:

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
  if (s.lastView != null) {
    if (!isObj(s.lastView)) e.push('lastView must be an object');
    else for (const k of ['yaw', 'pitch', 'zoom']) if (typeof s.lastView[k] !== 'number') e.push(`lastView.${k} must be a number`);
  }
  if (!isObj(s.settings)) e.push('settings missing');
  if (!isObj(s.status)) e.push('status missing');
  if (!Array.isArray(s.accounts)) e.push('accounts must be an array');
  else s.accounts.forEach((a, i) => {
    if (!isObj(a)) { e.push(`accounts[${i}] must be an object`); return; }
    for (const k of ['id', 'name', 'color']) if (typeof a[k] !== 'string') e.push(`accounts[${i}].${k} must be a string`);
    if (typeof a.error !== 'boolean') e.push(`accounts[${i}].error must be a boolean`);
  });
  if (!Array.isArray(s.presets)) e.push('presets must be an array');
  else s.presets.forEach((p, i) => {
    if (!isObj(p)) { e.push(`presets[${i}] must be an object`); return; }
    for (const k of ['id', 'name', 'accountId']) if (typeof p[k] !== 'string') e.push(`presets[${i}].${k} must be a string`);
  });
  if (typeof s.activePresetId !== 'string') e.push('activePresetId must be a string');
  if (typeof s.configured !== 'boolean') e.push('configured must be a boolean');
  if (!isObj(s.axisLabels)) e.push('axisLabels must be an object');
  else for (const k of ['value', 'effort', 'urgency']) {
    if (s.axisLabels[k] != null && typeof s.axisLabels[k] !== 'string') e.push(`axisLabels.${k} must be a string`);
  }
  if (s.setup != null && (!isObj(s.setup) || typeof s.setup.message !== 'string' || typeof s.setup.tab !== 'string')) {
    e.push('setup must have string message and tab');
  }
  return e;
}
```

In `Sources/OnscreenTodoMatrix/SettingsView.swift` (AxisEditor, field `Picker` setter), replace

```swift
                    let mapping = vm.fields.first(where: { $0.id == id }).flatMap { DefaultMappings.mapping(for: $0) }
                    update { $0.mapping = mapping }
```

with

```swift
                    let field = vm.fields.first(where: { $0.id == id })
                    update {
                        $0.mapping = field.flatMap { DefaultMappings.mapping(for: $0) }
                        $0.fieldName = field?.name
                    }
```

(`AppModel` needs no change: the builder's new parameters have defaults; Task 5 passes them.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: `✔ Test run with 112 tests in 18 suites passed`.
Run: `cd chart && npm test; cd ..`
Expected: `Tests  33 passed (33)`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests fixtures/render-state.json chart/src/state.js chart/test/state.test.js
git commit -m "feat(otm): render-state contract with accounts, preset accounts, setup, banner tab and axis field names

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: AppModel — multi-account refresh, preset switching, per-account errors, account/preset management

The full v1.2 `AppModel`: a refresh queries only the active preset (its account's site, token, JQL and axes); switching presets persists `activePresetId`, shows that preset's cache instantly and resumes the scheduler; a fetch that finishes after the user switched is cached but never shown; 401s are tracked per account (⚠ in the menu, banner naming the account, Accounts tab routing); setup overlay messages; account and preset CRUD used by Settings; migration-failure banner with legacy-token fallback.

**Files:**
- Modify (full replacement): `SRC/Sources/OTMCore/AppModel.swift`
- Modify (full replacement): `SRC/Tests/OTMCoreTests/AppModelTests.swift`
- Modify: `SRC/Tests/OTMCoreTests/TestSupport.swift` (`FakeJiraAPI.countResult`)

**Interfaces:**
- Consumes: everything from Tasks 1–4 (`AppConfig` helpers, keyed `TokenStore`, `IssueCache` per preset, `ConfigLoadResult.legacy`, `ConfigMigration.finish`, `RenderStateBuilder.build(…accountErrors:setup:)`, `RenderSetup`, `RenderStatus.bannerTab`).
- Produces (public, used by the app target in Tasks 8–10):
  - `enum PresetSelection: Equatable, Sendable { case selected, accountMissing, notFound }`
  - `enum JQLTestResult: Equatable, Sendable { case count(Int), jqlError(String), failed(String); var text: String }` — `.count(n).text == "\(n) issues match"`, `.jqlError(m).text == "JQL error: \(m)"`
  - `extension AppConfig { func canCreatePreset(name: String, accountId: String, lastTest: JQLTestResult?) -> Bool }`
  - `AppModel`: `@Published private(set) var authFailedAccounts: Set<String>`, `private(set) var migrationFailed: Bool`, `static let migrationBanner = "Could not migrate settings · Open settings"`, `static let setupMessage = "Finish setup to see your Jira issues."`, `var activeAccount: JiraAccount?`, `func storedToken(accountId:) -> String?`, `func hasCredentials(_: JiraAccount) -> Bool`, `func isAccountConfigured(_: JiraAccount) -> Bool`, `var isConfigured: Bool`, `func hasError(accountId: String) -> Bool`, `func newAccountId() -> String`, `func makeAPI(accountId: String) throws -> JiraAPI`, `func saveAccount(_: JiraAccount, token: String) throws`, `func removeAccount(id: String)`, `func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void)`, `@discardableResult func selectPreset(id: String) -> PresetSelection`, `func addPreset(_: JQLPreset, activate: Bool)`, `func deletePreset(id: String)`, `func testJQL(_ jql: String, accountId: String) async -> JQLTestResult`, `func refresh(_: RefreshTrigger) async`, `func updateConfig(_: AppConfig)`, `func issueURL(key:) -> URL?`, `static func bannerText(_ error: JiraError, syncedAt: Date?, accountName: String? = nil) -> String` (unauthorized with a name → `"Jira sign-in failed (<name>) · Open settings"`); unchanged: `setQuickSetting`, `saveDefaultView`, `saveLastView`, `renderState`, `config`, `issues`, `unmappedLabels`, `configWasCorrupt`.
  - Test helpers: `final class ClientLog { var calls: [(site: String, email: String, token: String)] }`, `GatedJiraAPI` with `later: [JiraIssue]` and `release(_: Result<[JiraIssue], JiraError>)`, `FakeJiraAPI.countResult: Result<Int, JiraError>`.

- [ ] **Step 1: Write the failing tests**

In `Tests/OTMCoreTests/TestSupport.swift` (`FakeJiraAPI`), replace

```swift
    var searchCalls: [(jql: String, fields: [String], cap: Int)] = []
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { 0 }
```

with

```swift
    var searchCalls: [(jql: String, fields: [String], cap: Int)] = []
    var countResult: Result<Int, JiraError> = .success(0)
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { try countResult.get() }
```

Replace `Tests/OTMCoreTests/AppModelTests.swift` with (two accounts: Personal `default` on `acme`, Company `c1` on `corp`):

```swift
import Foundation
import Testing
@testable import OTMCore

/// Records the (site, email, token) of every client the model creates.
final class ClientLog {
    var calls: [(site: String, email: String, token: String)] = []
}

@MainActor
@Suite struct AppModelTests {
    let dir = makeTempDir()
    let api = FakeJiraAPI()
    let tokens = InMemoryTokenStore(tokens: ["default": "tok", "c1": "ctok"])
    let clients = ClientLog()
    let clockNow = Date(timeIntervalSince1970: 1_800_000_000)
    let scheduler: RefreshScheduler

    init() {
        let t = clockNow
        scheduler = RefreshScheduler(now: { t })
    }

    static func axes(value: String, effort: String) -> AxesConfig {
        var a = AxesConfig()
        a.value.mapping = .number(fieldId: value, min: 0, max: 10, invert: false)
        a.effort.mapping = .number(fieldId: effort, min: 0, max: 10, invert: false)
        a.urgency.mapping = .option(fieldId: "priority", levels: DefaultMappings.priorityLevels)
        return a
    }

    /// Personal (default, acme) with "My open work"; Company (c1, corp) with "My company work" (p2).
    func configuredConfig() -> AppConfig {
        var c = AppConfig()
        c.accounts = [
            JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com",
                        axes: Self.axes(value: "cf_value", effort: "cf_sp")),
            JiraAccount(id: "c1", name: "Company", site: "corp.atlassian.net", email: "me@corp.com",
                        axes: Self.axes(value: "customfield_200", effort: "customfield_201")),
        ]
        c.presets.append(JQLPreset(id: "p2", name: "My company work", jql: "project = CORP", accountId: "c1"))
        return c
    }

    func makeModel(config: AppConfig? = nil) -> AppModel {
        if let config { try? ConfigStore(directory: dir).save(config) }
        let t = clockNow
        return AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                        scheduler: scheduler,
                        makeClient: { [api, clients] site, email, token in
                            clients.calls.append((site.absoluteString, email, token))
                            return api
                        },
                        now: { t })
    }

    func issue(_ key: String, value: Double, sp: Double, priority: String) -> JiraIssue {
        JiraIssue(key: key, fields: ["summary": .string("S \(key)"), "cf_value": .number(value),
                                     "cf_sp": .number(sp), "priority": .object(["name": .string(priority)])])
    }

    func cache(_ presetId: String, _ keys: [String], account: String, age: TimeInterval = 600) {
        let issues = keys.map { issue($0, value: 5, sp: 5, priority: "Low") }
        try? IssueCache(directory: dir).save(CachedFetch(issues: issues, fetchedAt: clockNow.addingTimeInterval(-age),
                                                         accountId: account), presetId: presetId)
    }

    // MARK: - Configured / setup

    @Test func notConfiguredDoesNotCallJira() async {
        let m = makeModel()
        #expect(!m.isConfigured)
        await m.refresh(.manual)
        #expect(api.searchCalls.isEmpty)
        #expect(m.renderState.configured == false)
        #expect(m.renderState.setup == RenderSetup(message: "Finish setup to see your Jira issues.", tab: "accounts"))
    }

    @Test func incompleteAxesAskToMapAxesForThatAccount() {
        var cfg = configuredConfig()
        cfg.accounts[1].axes.value.mapping = nil
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(!m.isConfigured)
        #expect(m.renderState.setup == RenderSetup(message: "Map axes for Company to see this preset", tab: "axes"))
        #expect(m.isAccountConfigured(m.config.accounts[0]))
    }

    @Test func accountWithoutTokenNeedsSetup() {
        tokens.tokens["c1"] = nil
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(!m.isConfigured)
        #expect(m.renderState.setup?.tab == "accounts")
    }

    // MARK: - Refresh uses the active preset's account

    @Test func successfulRefreshRendersAndCachesPerPreset() async {
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
        #expect(m.renderState.setup == nil)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.count == 1)
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.accountId == "default")
    }

    @Test func refreshUsesActivePresetsAccountSiteTokenAndAxes() async {
        api.searchResult = .success(SearchResult(issues: [JiraIssue(key: "C-1", fields: ["customfield_200": .number(5)])]))
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        await m.refresh(.manual)
        #expect(clients.calls.last?.site == "https://corp.atlassian.net")
        #expect(clients.calls.last?.email == "me@corp.com")
        #expect(clients.calls.last?.token == "ctok")
        #expect(api.searchCalls[0].jql == "project = CORP")
        #expect(api.searchCalls[0].fields == ["summary", "status", "priority", "duedate", "customfield_200", "customfield_201"])
        #expect(m.renderState.tasks[0].url == "https://corp.atlassian.net/browse/C-1")
        #expect(m.renderState.tasks[0].value == 0.5)
        #expect(m.issueURL(key: "C-1")?.absoluteString == "https://corp.atlassian.net/browse/C-1")
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

    // MARK: - Switching presets

    @Test func switchingPresetShowsItsCacheInstantlyThenRefetches() async {
        cache("my-open-work", ["A-1"], account: "default", age: 60)
        cache("p2", ["C-1", "C-2"], account: "c1", age: 300)
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
        #expect(m.selectPreset(id: "p2") == .selected)
        #expect(Set(m.renderState.tasks.map(\.key)) == ["C-1", "C-2"])
        #expect(m.renderState.status.syncedAt == clockNow.addingTimeInterval(-300))
        #expect(m.renderState.activePresetId == "p2")
        #expect(api.searchCalls.isEmpty)
        api.searchResult = .success(SearchResult(issues: [issue("C-3", value: 1, sp: 1, priority: "Low")]))
        await m.refresh(.manual)
        #expect(api.searchCalls.map(\.jql) == ["project = CORP"])
        #expect(m.renderState.tasks.map(\.key) == ["C-3"])
    }

    @Test func presetWithoutCacheShowsNothingRatherThanTheOldPresetsIssues() {
        cache("my-open-work", ["A-1"], account: "default")
        let m = makeModel(config: configuredConfig())
        m.selectPreset(id: "p2")
        #expect(m.renderState.tasks.isEmpty)
        #expect(m.renderState.status.syncedAt == nil)
    }

    @Test func cacheWrittenForAnotherAccountIsIgnored() {
        cache("p2", ["X-1"], account: "default") // the preset was reassigned to c1 since
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        #expect(m.renderState.tasks.isEmpty)
    }

    @Test func activePresetIsPersistedAndRestoredOnLaunch() {
        let m = makeModel(config: configuredConfig())
        m.selectPreset(id: "p2")
        let relaunched = makeModel()
        #expect(relaunched.config.activePresetId == "p2")
        #expect(relaunched.renderState.activePresetId == "p2")
        #expect(relaunched.activeAccount?.id == "c1")
    }

    @Test func presetWhoseAccountIsMissingCannotBeActivated() {
        var cfg = configuredConfig()
        cfg.presets.append(JQLPreset(id: "orphan", name: "Old", jql: "x", accountId: "gone"))
        let m = makeModel(config: cfg)
        #expect(m.selectPreset(id: "orphan") == .accountMissing)
        #expect(m.selectPreset(id: "nope") == .notFound)
        #expect(m.config.activePresetId == "my-open-work")
        #expect(m.renderState.presets.last == RenderPreset(id: "orphan", name: "Old", accountId: "gone"))
    }

    // MARK: - Errors per account

    @Test func unauthorizedNamesTheAccountAndDoesNotBlockAnotherAccount() async {
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed (Company) · Open settings")
        #expect(m.renderState.status.bannerTab == "accounts")
        #expect(m.renderState.accounts.map(\.error) == [false, true])
        #expect(m.hasError(accountId: "c1"))
        let calls = api.searchCalls.count
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls) // paused for Company
        m.selectPreset(id: "my-open-work")
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 1, sp: 1, priority: "Low")]))
        await m.refresh(.focus)
        #expect(api.searchCalls.count == calls + 1) // Personal is not blocked
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.accounts.map(\.error) == [false, true]) // ⚠ stays on Company's presets
    }

    @Test func unauthorizedKeepsDataOnScreen() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        api.searchResult = .failure(.unauthorized)
        await m.refresh(.manual)
        #expect(m.renderState.status.banner == "Jira sign-in failed (Personal) · Open settings")
        #expect(m.renderState.tasks.count == 1)
    }

    @Test func offlineShowsCachedDataTime() async {
        api.searchResult = .failure(.network("offline"))
        cache("my-open-work", ["A-1"], account: "default")
        let m = makeModel(config: configuredConfig())
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
        #expect(m.renderState.status.bannerTab == nil)
    }

    @Test func truncatedResultSetsNotice() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Low")],
                                                 truncated: true, approximateTotal: 1240))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.renderState.status.truncated == "Showing 1 of 1240 · narrow your JQL")
    }

    @Test func zeroIssuesIsNotAnError() async {
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
        #expect(m.renderState.status.bannerTab == "axes")
    }

    @Test func keychainReadErrorFlagsTheAccount() {
        tokens.readError = TokenStoreError.status(-25293)
        let m = makeModel(config: configuredConfig())
        #expect(m.renderState.status.banner == "Keychain access denied · re-enter your API token in settings")
        #expect(m.renderState.accounts.map(\.error) == [true, true])
        #expect(!m.isConfigured)
    }

    // MARK: - In-flight fetch vs preset switch (Review Focus #3)

    @Test func inFlightResultOfPreviousPresetIsCachedButNotShown() async {
        let gated = GatedJiraAPI()
        gated.later = [JiraIssue(key: "C-9", fields: [:])]
        try? ConfigStore(directory: dir).save(configuredConfig())
        let t = clockNow
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: RefreshScheduler(now: { t }), makeClient: { _, _, _ in gated }, now: { t })
        let a = Task { await m.refresh(.manual) }
        while gated.searchJQLs.isEmpty { await Task.yield() }
        m.selectPreset(id: "p2")
        await m.refresh(.manual)               // coalesced: re-runs for p2 after the in-flight fetch
        gated.release(.success([issue("A-1", value: 1, sp: 1, priority: "Low")]))
        await a.value
        #expect(gated.searchJQLs == [JQLPreset.myOpenWork.jql, "project = CORP"])
        #expect(m.renderState.tasks.map(\.key) == ["C-9"])
        #expect(m.renderState.activePresetId == "p2")
        #expect(IssueCache(directory: dir).load(presetId: "my-open-work")?.issues.map(\.key) == ["A-1"])
        #expect(IssueCache(directory: dir).load(presetId: "p2")?.issues.map(\.key) == ["C-9"])
    }

    @Test func inFlightFailureOfPreviousPresetDoesNotPauseOrBannerTheNewOne() async {
        let gated = GatedJiraAPI()
        try? ConfigStore(directory: dir).save(configuredConfig())
        let t = clockNow
        let sched = RefreshScheduler(now: { t })
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: tokens,
                         scheduler: sched, makeClient: { _, _, _ in gated }, now: { t })
        let a = Task { await m.refresh(.timer) }
        while gated.searchJQLs.isEmpty { await Task.yield() }
        m.selectPreset(id: "p2")
        gated.release(.failure(.unauthorized))
        await a.value
        #expect(!sched.isPaused)
        #expect(m.renderState.status.banner == nil)
        #expect(m.renderState.accounts.map(\.error) == [true, false]) // ⚠ on Personal's presets only
    }

    // MARK: - Accounts and presets management

    @Test func newAccountIdIsDefaultFirstThenUnique() throws {
        let m = makeModel()
        #expect(m.newAccountId() == "default")
        try m.saveAccount(JiraAccount(id: "default", name: "Personal", site: "acme.atlassian.net", email: "me@x.com"),
                          token: "t1")
        let next = m.newAccountId()
        #expect(next != "default")
        #expect(UUID(uuidString: next) != nil)
    }

    @Test func saveAccountWritesKeyedTokenAndUpserts() throws {
        let m = makeModel(config: configuredConfig())
        var company = m.config.accounts[1]
        company.name = "Work"
        try m.saveAccount(company, token: "new")
        #expect(tokens.tokens["c1"] == "new")
        #expect(m.storedToken(accountId: "c1") == "new")
        #expect(m.config.accounts.map(\.name) == ["Personal", "Work"])
        tokens.writeError = TokenStoreError.status(-25308)
        company.name = "Ignored"
        #expect(throws: TokenStoreError.status(-25308)) { try m.saveAccount(company, token: "x") }
        #expect(m.config.accounts[1].name == "Work")
    }

    @Test func removeAccountDeletesItsPresetsCachesAndTokenAndPicksNextPreset() {
        cache("p2", ["C-1"], account: "c1")
        cache("my-open-work", ["A-1"], account: "default")
        var cfg = configuredConfig()
        cfg.activePresetId = "p2"
        let m = makeModel(config: cfg)
        m.removeAccount(id: "c1")
        #expect(m.config.accounts.map(\.id) == ["default"])
        #expect(m.config.presets.map(\.id) == ["my-open-work"])
        #expect(m.config.activePresetId == "my-open-work")
        #expect(tokens.tokens["c1"] == nil)
        #expect(IssueCache(directory: dir).load(presetId: "p2") == nil)
        #expect(m.renderState.tasks.map(\.key) == ["A-1"])
    }

    @Test func addPresetActivatesAndDeletePresetFallsBack() {
        let m = makeModel(config: configuredConfig())
        m.addPreset(JQLPreset(id: "due", name: "Due this week", jql: "due <= endOfWeek()", accountId: "default"), activate: true)
        #expect(m.config.activePresetId == "due")
        #expect(m.renderState.presets.map(\.id) == ["my-open-work", "due", "p2"])
        m.deletePreset(id: "due")
        #expect(m.config.activePresetId == "my-open-work")
        #expect(!m.config.presets.contains { $0.id == "due" })
    }

    @Test func testJQLMapsJiraErrors() async {
        let m = makeModel(config: configuredConfig())
        api.countResult = .success(42)
        #expect(await m.testJQL("project = A", accountId: "default") == .count(42))
        api.countResult = .failure(.badRequest("Field 'x' does not exist."))
        #expect(await m.testJQL("x = 1", accountId: "default") == .jqlError("Field 'x' does not exist."))
        api.countResult = .failure(.network("offline"))
        #expect(await m.testJQL("x", accountId: "default") == .failed("Offline · no cached data"))
        #expect(await m.testJQL("x", accountId: "gone") == .failed("Not configured · Open settings"))
        #expect(JQLTestResult.count(3).text == "3 issues match")
    }

    @Test func canCreatePresetRules() {
        let c = configuredConfig()
        #expect(c.canCreatePreset(name: "Due this week", accountId: "default", lastTest: nil))
        #expect(c.canCreatePreset(name: "Due this week", accountId: "default", lastTest: .failed("Offline · no cached data")))
        #expect(!c.canCreatePreset(name: " ", accountId: "default", lastTest: nil))
        #expect(!c.canCreatePreset(name: "my open work", accountId: "default", lastTest: nil))
        #expect(c.canCreatePreset(name: "My open work", accountId: "c1", lastTest: .count(3)))
        #expect(!c.canCreatePreset(name: "New", accountId: "default", lastTest: .jqlError("bad")))
        #expect(!c.canCreatePreset(name: "New", accountId: "gone", lastTest: nil))
    }

    // MARK: - Migration failure (§11.10)

    @Test func migrationFailureShowsBannerAndKeepsWorkingWithLegacyToken() async throws {
        try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/config-v1.1.json"))
            .write(to: ConfigStore(directory: dir).url)
        let legacyOnly = InMemoryTokenStore(legacyToken: "legacy-tok")
        legacyOnly.writeError = TokenStoreError.status(-25308)
        let t = clockNow
        let m = AppModel(configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir), tokenStore: legacyOnly,
                         scheduler: RefreshScheduler(now: { t }),
                         makeClient: { [api, clients] site, email, token in
                             clients.calls.append((site.absoluteString, email, token)); return api
                         }, now: { t })
        #expect(m.migrationFailed)
        #expect(m.renderState.status.banner == "Could not migrate settings · Open settings")
        #expect(m.renderState.status.bannerTab == "accounts")
        #expect(m.isConfigured)
        await m.refresh(.manual)
        #expect(clients.calls.last?.token == "legacy-tok")
        #expect(clients.calls.last?.site == "https://example-personal.atlassian.net")
        #expect(legacyOnly.legacyToken == "legacy-tok")
    }

    // MARK: - Unchanged behaviour

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

    @Test func lastViewPersistsNormalizedWithoutRerender() {
        let m = makeModel(config: configuredConfig())
        let before = m.renderState
        m.saveLastView(yaw: -539.7, pitch: 95, zoom: 9)
        guard case .loaded(let saved) = ConfigStore(directory: dir).load() else { Issue.record("not saved"); return }
        #expect(abs(saved.lastView!.yaw - -179.7) < 1e-9)
        #expect(saved.lastView!.pitch == 89)
        #expect(saved.lastView!.zoom == 3)
        #expect(saved.view == ViewDefaults())
        #expect(m.renderState == before)
        m.saveLastView(yaw: .nan, pitch: 0, zoom: 1)
        m.saveLastView(yaw: 0, pitch: .infinity, zoom: 1)
        #expect(m.config.lastView == saved.lastView)
    }

    @Test func corruptConfigIsFlagged() throws {
        try Data("{oops".utf8).write(to: ConfigStore(directory: dir).url)
        let m = makeModel()
        #expect(m.configWasCorrupt)
        #expect(m.config == AppConfig())
    }

    @Test func unmappedLabelsAreReported() async {
        api.searchResult = .success(SearchResult(issues: [issue("A-1", value: 2, sp: 2, priority: "Blocker")]))
        let m = makeModel(config: configuredConfig())
        await m.refresh(.manual)
        #expect(m.unmappedLabels[.urgency] == ["Blocker"])
    }
}

/// First `search` suspends until `release`; later ones return `later` immediately.
final class GatedJiraAPI: JiraAPI {
    var searchJQLs: [String] = []
    var later: [JiraIssue] = []
    private var cont: CheckedContinuation<Result<[JiraIssue], JiraError>, Never>?
    func myself() async throws -> JiraUser { JiraUser(displayName: "Neo", accountId: "1") }
    func fields() async throws -> [JiraField] { [] }
    func priorities() async throws -> [String] { [] }
    func approximateCount(jql: String) async throws -> Int { 0 }
    func search(jql: String, fields: [String], cap: Int) async throws -> SearchResult {
        searchJQLs.append(jql)
        if searchJQLs.count == 1 {
            return SearchResult(issues: try await withCheckedContinuation { cont = $0 }.get())
        }
        return SearchResult(issues: later)
    }
    func release(_ result: Result<[JiraIssue], JiraError>) { cont?.resume(returning: result); cont = nil }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppModelTests`
Expected: build FAILS with `cannot find type 'PresetSelection'…` / `value of type 'AppModel' has no member 'removeAccount'` / `… 'testJQL'`.

- [ ] **Step 3: Implement the multi-account AppModel**

Replace `Sources/OTMCore/AppModel.swift` with:

```swift
import Combine
import Foundation

/// Result of `AppModel.selectPreset(id:)`.
public enum PresetSelection: Equatable, Sendable {
    case selected
    /// The preset's account no longer exists: it cannot be activated until reassigned (§11.2).
    case accountMissing
    case notFound
}

/// Result of a JQL Test in Settings.
public enum JQLTestResult: Equatable, Sendable {
    case count(Int)
    /// Jira rejected the JQL (400); blocks "Create & show".
    case jqlError(String)
    /// Anything else (network, sign-in…); does not block saving.
    case failed(String)

    public var text: String {
        switch self {
        case .count(let n): return "\(n) issues match"
        case .jqlError(let m): return "JQL error: \(m)"
        case .failed(let m): return m
        }
    }
}

extension AppConfig {
    /// New preset sheet: Save is disabled while the name is empty/duplicate (within the account),
    /// the account is unknown, or the last Test failed with a JQL error (§11.7).
    public func canCreatePreset(name: String, accountId: String, lastTest: JQLTestResult?) -> Bool {
        guard account(id: accountId) != nil, isPresetNameValid(name, accountId: accountId) else { return false }
        if case .jqlError = lastTest { return false }
        return true
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var renderState: RenderState = .empty
    @Published public private(set) var config: AppConfig
    @Published public private(set) var issues: [JiraIssue] = []
    @Published public private(set) var unmappedLabels: [Axis: [String]] = [:]
    /// Accounts whose last fetch failed with 401/403 (⚠ in the preset menu, error in the Accounts tab).
    @Published public private(set) var authFailedAccounts: Set<String> = []
    public private(set) var configWasCorrupt = false
    /// The v1.1 → v1.2 migration could not finish; the old setup is kept (§11.10).
    public private(set) var migrationFailed = false

    private let configStore: ConfigStore
    private let cache: IssueCache
    private let tokenStore: TokenStore
    private let scheduler: RefreshScheduler
    private let makeClient: (URL, String, String) -> JiraAPI
    private let now: () -> Date
    private let calendar: Calendar

    private var tokens: [String: String] = [:]
    private var tokenErrorAccounts: Set<String> = []
    private var syncedAt: Date?
    private var banner: String?
    private var bannerTab: String?
    private var truncated: String?
    private var lastMapped: [MappedTask] = []
    private var isRefreshing = false
    private var rerunRequested = false

    public static let issueCap = 500
    public static let migrationBanner = "Could not migrate settings · Open settings"
    public static let setupMessage = "Finish setup to see your Jira issues."

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
        case .legacy(let c):
            config = c
            migrationFailed = !ConfigMigration.finish(c, store: configStore, tokens: tokenStore, cache: cache)
        case .missing: config = AppConfig()
        case .corrupt: config = AppConfig(); configWasCorrupt = true
        }
        for account in config.accounts { loadToken(account.id) }
        loadActiveCache()
        if let id = activeAccount?.id, tokenErrorAccounts.contains(id) {
            banner = "Keychain access denied · re-enter your API token in settings"
            bannerTab = "accounts"
        }
        rebuild(previous: nil)
    }

    // MARK: - Accounts

    public var activeAccount: JiraAccount? { config.activeAccount }

    public func storedToken(accountId: String) -> String? { tokens[accountId] }

    /// Site, email and token present (the account can talk to Jira).
    public func hasCredentials(_ account: JiraAccount) -> Bool {
        account.siteURL != nil && !account.email.isEmpty && !(tokens[account.id] ?? "").isEmpty
    }

    /// Credentials and all three axes mapped.
    public func isAccountConfigured(_ account: JiraAccount) -> Bool {
        hasCredentials(account) && account.axes.isComplete
    }

    /// The active preset's account is configured (§11.7).
    public var isConfigured: Bool { activeAccount.map(isAccountConfigured) ?? false }

    /// Sign-in (401/403) or Keychain error for this account.
    public func hasError(accountId: String) -> Bool { accountErrors.contains(accountId) }

    /// "default" for the first account (so the pre-filled "My open work" preset belongs to it), a UUID afterwards.
    public func newAccountId() -> String {
        config.account(id: JiraAccount.defaultId) == nil ? JiraAccount.defaultId : UUID().uuidString
    }

    public func makeAPI(accountId: String) throws -> JiraAPI {
        guard let account = config.account(id: accountId), let site = account.siteURL, !account.email.isEmpty,
              let token = tokens[accountId], !token.isEmpty else { throw JiraError.notConfigured }
        return makeClient(site, account.email, token)
    }

    /// Inserts or updates the account and stores its token in Keychain (token first: a Keychain error changes nothing).
    public func saveAccount(_ account: JiraAccount, token: String) throws {
        try tokenStore.write(token, accountId: account.id)
        tokens[account.id] = token
        tokenErrorAccounts.remove(account.id)
        authFailedAccounts.remove(account.id)
        migrationFailed = false
        var c = config
        c.upsertAccount(account)
        updateConfig(c)
    }

    /// Removes the account, its presets (and their caches) and its Keychain item (§11.3, §11.7).
    public func removeAccount(id: String) {
        try? tokenStore.delete(accountId: id)
        if id == JiraAccount.defaultId { try? tokenStore.deleteLegacy() }
        tokens[id] = nil
        tokenErrorAccounts.remove(id)
        authFailedAccounts.remove(id)
        var c = config
        for p in c.presets where p.accountId == id { cache.delete(presetId: p.id) }
        c.accounts.removeAll { $0.id == id }
        c.presets.removeAll { $0.accountId == id }
        if !c.presets.contains(where: { $0.id == c.activePresetId }) {
            c.activePresetId = c.menuOrderedPresets.first?.id ?? ""
        }
        updateConfig(c)
    }

    public func updateAxes(accountId: String, _ change: (inout AxesConfig) -> Void) {
        var c = config
        guard let i = c.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        change(&c.accounts[i].axes)
        updateConfig(c)
    }

    // MARK: - Presets

    /// Activates a preset and shows its cached issues instantly; the caller then runs `refresh(.manual)`.
    /// The choice is persisted immediately, so it is restored on launch.
    @discardableResult
    public func selectPreset(id: String) -> PresetSelection {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return .notFound }
        guard config.account(id: preset.accountId) != nil else { return .accountMissing }
        var c = config
        c.activePresetId = id
        updateConfig(c)
        return .selected
    }

    public func addPreset(_ preset: JQLPreset, activate: Bool) {
        var c = config
        c.presets.append(preset)
        updateConfig(c)
        if activate { selectPreset(id: preset.id) }
    }

    public func deletePreset(id: String) {
        var c = config
        c.presets.removeAll { $0.id == id }
        cache.delete(presetId: id)
        if !c.presets.contains(where: { $0.id == c.activePresetId }) {
            c.activePresetId = c.menuOrderedPresets.first?.id ?? ""
        }
        updateConfig(c)
    }

    /// JQL Test for Settings: approximate match count on that account's site.
    public func testJQL(_ jql: String, accountId: String) async -> JQLTestResult {
        do {
            return .count(try await makeAPI(accountId: accountId).approximateCount(jql: jql))
        } catch JiraError.badRequest(let message) {
            return .jqlError(message)
        } catch let error as JiraError {
            return .failed(Self.bannerText(error, syncedAt: nil))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Refresh

    /// Fetches only the active preset: its account's site + token, its JQL, its account's axes (§11.5).
    public func refresh(_ trigger: RefreshTrigger) async {
        if isRefreshing {
            if trigger == .manual { rerunRequested = true }
            return
        }
        guard isConfigured, let preset = config.activePreset,
              scheduler.shouldRefresh(trigger, intervalMinutes: config.quick.refreshMinutes),
              let api = try? makeAPI(accountId: preset.accountId) else { return }
        isRefreshing = true
        await fetch(api, preset: preset)
        isRefreshing = false
        if rerunRequested {
            rerunRequested = false
            await refresh(.manual)
        }
    }

    private func fetch(_ api: JiraAPI, preset: JQLPreset) async {
        let previous = Dictionary(lastMapped.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            let result = try await api.search(jql: preset.jql, fields: fetchFields(), cap: Self.issueCap)
            let fetchedAt = now()
            authFailedAccounts.remove(preset.accountId)
            try? cache.save(CachedFetch(issues: result.issues, fetchedAt: fetchedAt, accountId: preset.accountId),
                            presetId: preset.id)
            // The user switched presets while this was in flight: cached for later, never shown under another preset.
            guard isActive(preset) else { rebuild(previous: nil); return }
            scheduler.recordSuccess()
            issues = result.issues
            syncedAt = fetchedAt
            banner = nil
            bannerTab = nil
            truncated = result.truncated
                ? "Showing \(result.issues.count) of \(result.approximateTotal.map(String.init) ?? "\(result.issues.count)+") · narrow your JQL"
                : nil
            rebuild(previous: previous)
        } catch let error as JiraError {
            if error == .unauthorized { authFailedAccounts.insert(preset.accountId) }
            // A stale failure must neither pause nor banner the preset the user switched to.
            guard isActive(preset) else { rebuild(previous: nil); return }
            scheduler.recordFailure(error)
            banner = Self.bannerText(error, syncedAt: syncedAt, accountName: config.account(id: preset.accountId)?.name)
            bannerTab = error == .unauthorized ? "accounts" : nil
            rebuild(previous: nil)
        } catch {
            guard isActive(preset) else { return }
            banner = "Refresh failed: \(error.localizedDescription)"
            bannerTab = nil
            rebuild(previous: nil)
        }
    }

    // MARK: - Config

    /// Saves settings changes. Clears a stale banner and resumes the scheduler (a 401 pause on one account must not
    /// block another). When the active preset or its account changes, that preset's cache is shown instantly.
    public func updateConfig(_ newConfig: AppConfig) {
        let before = config.activePreset
        banner = nil
        bannerTab = nil
        config = newConfig
        try? configStore.save(newConfig)
        scheduler.resume()
        let after = newConfig.activePreset
        if before?.id != after?.id || before?.accountId != after?.accountId { loadActiveCache() }
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

    /// Persists the live camera view (restored on launch). Deliberately no rebuild: the chart already shows it.
    public func saveLastView(yaw: Double, pitch: Double, zoom: Double) {
        guard yaw.isFinite, pitch.isFinite, zoom.isFinite else { return }
        let normalizedYaw = (((yaw + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        var c = config
        c.lastView = ViewDefaults(yaw: normalizedYaw, pitch: min(89, max(-89, pitch)), zoom: min(3, max(0.5, zoom)))
        config = c
        try? configStore.save(c)
    }

    /// Issue URLs use the active preset's account site.
    public func issueURL(key: String) -> URL? {
        activeAccount?.siteURL?.appendingPathComponent("browse").appendingPathComponent(key)
    }

    public static func bannerText(_ error: JiraError, syncedAt: Date?, accountName: String? = nil) -> String {
        switch error {
        case .network:
            guard let syncedAt else { return "Offline · no cached data" }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Offline · showing data from \(f.string(from: syncedAt))"
        case .unauthorized:
            return accountName.map { "Jira sign-in failed (\($0)) · Open settings" } ?? "Jira sign-in failed · Open settings"
        case .rateLimited: return "Jira rate limit · retrying later"
        case .badRequest(let m): return "JQL error: \(m)"
        case .http(let code): return "Jira error \(code)"
        case .decoding: return "Unexpected response from Jira"
        case .notConfigured: return "Not configured · Open settings"
        }
    }

    // MARK: - Private

    private var accountErrors: Set<String> { authFailedAccounts.union(tokenErrorAccounts) }

    private func isActive(_ preset: JQLPreset) -> Bool {
        config.activePreset?.id == preset.id && config.activePreset?.accountId == preset.accountId
    }

    private func loadToken(_ accountId: String) {
        do {
            var token = try tokenStore.read(accountId: accountId)
            // Migration fallback (§11.10): until the keyed copy exists, the v1.1 item still works.
            if token == nil, accountId == JiraAccount.defaultId { token = try tokenStore.readLegacy() }
            tokens[accountId] = token
            tokenErrorAccounts.remove(accountId)
        } catch {
            tokens[accountId] = nil
            tokenErrorAccounts.insert(accountId)
        }
    }

    /// Shows the active preset's cache (its own issues and "synced" time), or nothing.
    private func loadActiveCache() {
        issues = []
        syncedAt = nil
        truncated = nil
        lastMapped = []
        guard let preset = config.activePreset, let cached = cache.load(presetId: preset.id),
              cached.accountId == preset.accountId else { return }
        issues = cached.issues
        syncedAt = cached.fetchedAt
    }

    private func persist(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        rebuild(previous: nil)
    }

    private func fetchFields() -> [String] {
        var out = ["summary", "status", "priority", "duedate"]
        for axis in Axis.allCases {
            if let id = activeAccount?.axes[axis].mapping?.fieldId, !out.contains(id) { out.append(id) }
        }
        return out
    }

    private func setup() -> RenderSetup? {
        if isConfigured { return nil }
        guard let preset = config.activePreset, let account = config.account(id: preset.accountId) else {
            if config.accounts.isEmpty { return RenderSetup(message: Self.setupMessage, tab: "accounts") }
            return config.activePreset == nil
                ? RenderSetup(message: "Create a preset to see your Jira issues.", tab: "presets")
                : RenderSetup(message: "This preset's account is missing · reassign it in settings", tab: "presets")
        }
        if !hasCredentials(account) { return RenderSetup(message: Self.setupMessage, tab: "accounts") }
        return RenderSetup(message: "Map axes for \(account.name) to see this preset", tab: "axes")
    }

    private func rebuild(previous: [String: MappedTask]?) {
        let account = activeAccount
        if let account, let site = account.siteURL {
            lastMapped = AxisMapper.map(issues: issues, axes: account.axes, site: site, now: now(), calendar: calendar)
        } else {
            lastMapped = []
        }
        var unmapped: [Axis: [String]] = [:]
        var axisBanner: String?
        for axis in Axis.allCases {
            guard let mapping = account?.axes[axis].mapping else { continue }
            let labels = AxisMapper.unmappedLabels(issues: issues, mapping: mapping)
            if !labels.isEmpty { unmapped[axis] = labels }
            if axisBanner == nil, !lastMapped.isEmpty, lastMapped.allSatisfy({ $0.missing[axis] }) {
                axisBanner = "No data for \(axis.rawValue) field · check mapping in settings"
            }
        }
        unmappedLabels = unmapped
        let status: RenderStatus
        if let banner {
            status = RenderStatus(syncedAt: syncedAt, banner: banner, truncated: truncated, bannerTab: bannerTab)
        } else if migrationFailed {
            status = RenderStatus(syncedAt: syncedAt, banner: Self.migrationBanner, truncated: truncated, bannerTab: "accounts")
        } else {
            status = RenderStatus(syncedAt: syncedAt, banner: axisBanner, truncated: truncated,
                                  bannerTab: axisBanner == nil ? nil : "axes")
        }
        renderState = RenderStateBuilder.build(tasks: lastMapped, previous: previous, config: config, status: status,
                                               configured: isConfigured, accountErrors: accountErrors, setup: setup())
    }
}
```

Notes for the implementer:
- `fetch` captures the preset at the start; after `await`, `isActive(preset)` decides whether the result may touch the screen, the banner or the scheduler. The cache is always written for the preset that was fetched. This is Review Focus #3 — do not "simplify" it away.
- `updateConfig` reloads the cache only when the active preset's id or account changes, so typing in a JQL field does not re-read files on every keystroke.
- The app target keeps compiling: `selectPreset(id:)` is `@discardableResult`, and the old `FiltersTab` / `AxisEditor` only use APIs that still exist.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift build && swift test`
Expected: `Build complete!`, `✔ Test run with 128 tests in 18 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OTMCore Tests/OTMCoreTests
git commit -m "feat(otm): multi-account AppModel (active preset's account, per-preset cache, per-account errors)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Preset menu logic (`chart/src/presetMenu.js`)

All decisions of the §11.6 menu as pure functions: grouping by account, menu order, ⌘1…⌘9 mapping, filter, keyboard reducer, the message each action posts, and the top-bar button label. `main.js` (Task 7) only draws rows and forwards keys.

**Files:**
- Create: `SRC/chart/src/presetMenu.js`
- Test: `SRC/chart/test/presetMenu.test.js`

**Interfaces:**
- Consumes: the `RenderState` shape from Task 4 (`state.accounts[] {id,name,color,error}`, `state.presets[] {id,name,accountId}`, `state.activePresetId`).
- Produces (ES module exports):
  - `NEW = 'new'`, `MANAGE = 'manage'`
  - `orderedPresets(presets, accounts) -> preset[]`
  - `shortcutPresetId(state, digit: string) -> string | null`
  - `newPresetAccountId(state) -> string | null`
  - `menuRows(state, filter = '') -> row[]` where row is `{kind:'header', account}` | `{kind:'preset', id, name, shortcut: '⌘N' | null, active, missing, error}` | `{kind:'action', id: NEW | MANAGE, label: '+ New preset…' | '⚙ Manage presets…'}`
  - `initialHighlight(rows) -> index`, `moveHighlight(rows, current, dir: 1 | -1) -> index`
  - `rowAction(row) -> {type:'select', id} | {type:'new'} | {type:'manage'} | null`
  - `menuKey(state, menu: {filter, hi}, key: string) -> {menu, action: null | {type:'close'} | rowAction}`
  - `messageFor(action, state) -> {type:'selectPreset', id} | {type:'newPreset', accountId} | {type:'openSettings', tab:'presets'} | null`
  - `buttonLabel(state) -> {color: string | null, text: string}`, `safeColor(c) -> '#rrggbb'`

- [ ] **Step 1: Write the failing tests**

Create `chart/test/presetMenu.test.js`:

```js
import { describe, test, expect } from 'vitest';
import {
  NEW, MANAGE, orderedPresets, shortcutPresetId, newPresetAccountId, menuRows, initialHighlight,
  moveHighlight, rowAction, menuKey, messageFor, buttonLabel, safeColor,
} from '../src/presetMenu.js';

const state = () => ({
  accounts: [
    { id: 'default', name: 'Personal', color: '#3b82f6', error: false },
    { id: 'c1', name: 'Company', color: '#f59e0b', error: true },
  ],
  presets: [
    { id: 'team', name: 'Team sprint', accountId: 'c1' },
    { id: 'mine', name: 'My open work', accountId: 'default' },
    { id: 'orphan', name: 'Old filter', accountId: 'gone' },
    { id: 'due', name: 'Due this week', accountId: 'default' },
    { id: 'cw', name: 'My company work', accountId: 'c1' },
  ],
  activePresetId: 'mine',
});
const ids = (rows) => rows.map((r) => (r.kind === 'header' ? `#${r.account.name}` : r.id));

describe('grouping and ordering', () => {
  test('presets are grouped by account order, missing-account presets last', () => {
    expect(orderedPresets(state().presets, state().accounts).map((p) => p.id)).toEqual(['mine', 'due', 'team', 'cw', 'orphan']);
  });
  test('rows: account headers, presets with ⌘ shortcuts, then the two actions', () => {
    const rows = menuRows(state());
    expect(ids(rows)).toEqual(['#Personal', 'mine', 'due', '#Company', 'team', 'cw', 'orphan', NEW, MANAGE]);
    const byId = Object.fromEntries(rows.filter((r) => r.kind === 'preset').map((r) => [r.id, r]));
    expect(byId.mine).toMatchObject({ shortcut: '⌘1', active: true, missing: false, error: false });
    expect(byId.team).toMatchObject({ shortcut: '⌘3', error: true });
    expect(byId.orphan).toMatchObject({ shortcut: '⌘5', missing: true });
    expect(rows.at(-2)).toEqual({ kind: 'action', id: NEW, label: '+ New preset…' });
    expect(rows.at(-1)).toEqual({ kind: 'action', id: MANAGE, label: '⚙ Manage presets…' });
  });
  test('no presets: only the actions', () => {
    expect(ids(menuRows({ ...state(), presets: [] }))).toEqual([NEW, MANAGE]);
  });
  test('only the first nine presets get a shortcut', () => {
    const presets = Array.from({ length: 11 }, (_, i) => ({ id: `p${i}`, name: `P${i}`, accountId: 'default' }));
    const rows = menuRows({ ...state(), presets }).filter((r) => r.kind === 'preset');
    expect(rows.map((r) => r.shortcut)).toEqual(['⌘1', '⌘2', '⌘3', '⌘4', '⌘5', '⌘6', '⌘7', '⌘8', '⌘9', null, null]);
  });
});

describe('⌘1…⌘9', () => {
  test('maps to menu order', () => {
    expect(shortcutPresetId(state(), '1')).toBe('mine');
    expect(shortcutPresetId(state(), '3')).toBe('team');
    expect(shortcutPresetId(state(), '5')).toBe('orphan');
  });
  test('out of range or not a digit → null', () => {
    expect(shortcutPresetId(state(), '6')).toBeNull();
    expect(shortcutPresetId(state(), '0')).toBeNull();
    expect(shortcutPresetId(state(), 'x')).toBeNull();
  });
});

describe('filter', () => {
  test('case-insensitive name match; empty groups disappear; shortcuts keep their numbers', () => {
    const rows = menuRows(state(), 'WORK');
    expect(ids(rows)).toEqual(['#Personal', 'mine', '#Company', 'cw', NEW, MANAGE]);
    expect(rows.find((r) => r.id === 'cw').shortcut).toBe('⌘4');
  });
  test('nothing matches: the actions stay and are highlighted', () => {
    // Review Focus #5
    const rows = menuRows(state(), 'zzz');
    expect(ids(rows)).toEqual([NEW, MANAGE]);
    expect(rows[initialHighlight(rows)].id).toBe(NEW);
  });
});

describe('keyboard navigation', () => {
  test('opens on the active preset; ↓ skips headers and wraps; ↑ wraps backwards', () => {
    const rows = menuRows(state());
    const hi = initialHighlight(rows);
    expect(rows[hi].id).toBe('mine');
    const next = moveHighlight(rows, hi, 1);
    expect(rows[next].id).toBe('due');
    expect(rows[moveHighlight(rows, next, 1)].id).toBe('team');
    expect(rows[moveHighlight(rows, rows.length - 1, 1)].id).toBe('mine');
    expect(rows[moveHighlight(rows, hi, -1)].id).toBe(MANAGE);
  });
  test('typing filters and re-highlights; Backspace widens again; Enter selects; Esc closes', () => {
    const s = state();
    let menu = { filter: '', hi: initialHighlight(menuRows(s)) };
    for (const k of ['c', 'o', 'm']) menu = menuKey(s, menu, k).menu;
    expect(menu.filter).toBe('com');
    expect(menuRows(s, menu.filter)[menu.hi].id).toBe('cw');
    expect(menuKey(s, menu, 'Enter').action).toEqual({ type: 'select', id: 'cw' });
    menu = menuKey(s, menu, 'Backspace').menu;
    expect(menu.filter).toBe('co');
    expect(menuKey(s, menu, 'Escape').action).toEqual({ type: 'close' });
    expect(menuKey(s, menu, 'Shift')).toEqual({ menu, action: null });
  });
  test('Enter with a filter that hides everything activates "+ New preset…", never a hidden preset', () => {
    // Review Focus #5
    const s = state();
    let menu = { filter: '', hi: initialHighlight(menuRows(s)) };
    for (const k of ['z', 'z']) menu = menuKey(s, menu, k).menu;
    expect(menuKey(s, menu, 'Enter').action).toEqual({ type: 'new' });
  });
  test('headers do nothing; actions map to new/manage', () => {
    expect(rowAction({ kind: 'header', account: {} })).toBeNull();
    expect(rowAction(undefined)).toBeNull();
    expect(rowAction({ kind: 'action', id: MANAGE })).toEqual({ type: 'manage' });
  });
});

describe('messages to Swift', () => {
  test('"+ New preset…" posts newPreset with the active preset\'s account', () => {
    const s = { ...state(), activePresetId: 'team' };
    expect(messageFor({ type: 'new' }, s)).toEqual({ type: 'newPreset', accountId: 'c1' });
  });
  test('active preset with a missing account → first account; no accounts → null', () => {
    expect(newPresetAccountId({ ...state(), activePresetId: 'orphan' })).toBe('default');
    expect(newPresetAccountId({ accounts: [], presets: [], activePresetId: '' })).toBeNull();
  });
  test('select and manage', () => {
    expect(messageFor({ type: 'select', id: 'due' }, state())).toEqual({ type: 'selectPreset', id: 'due' });
    expect(messageFor({ type: 'manage' }, state())).toEqual({ type: 'openSettings', tab: 'presets' });
    expect(messageFor(null, state())).toBeNull();
    expect(messageFor({ type: 'close' }, state())).toBeNull();
  });
});

describe('button label', () => {
  test('colour dot + "Account · Preset"', () => {
    expect(buttonLabel(state())).toEqual({ color: '#3b82f6', text: 'Personal · My open work' });
    expect(buttonLabel({ ...state(), activePresetId: 'orphan' })).toEqual({ color: null, text: 'Old filter' });
    expect(buttonLabel({ ...state(), presets: [], activePresetId: '' })).toEqual({ color: null, text: 'No presets' });
  });
  test('only #rrggbb colours pass', () => {
    expect(safeColor('#F59E0B')).toBe('#F59E0B');
    expect(safeColor('red;background:url(x)')).toBe('#6b7895');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd chart && npx vitest run test/presetMenu.test.js; cd ..`
Expected: FAIL — `Failed to resolve import "../src/presetMenu.js"`.

- [ ] **Step 3: Implement the module**

Create `chart/src/presetMenu.js`:

```js
// Pure logic of the top-bar preset menu (spec §11.6). No DOM here: main.js draws what menuRows() returns.

export const NEW = 'new';
export const MANAGE = 'manage';

/** Presets in menu order: grouped by account order; presets whose account is missing come last. */
export function orderedPresets(presets, accounts) {
  const known = new Set(accounts.map((a) => a.id));
  return [
    ...accounts.flatMap((a) => presets.filter((p) => p.accountId === a.id)),
    ...presets.filter((p) => !known.has(p.accountId)),
  ];
}

/** ⌘1…⌘9 → id of the 1st…9th preset in menu order, or null. */
export function shortcutPresetId(state, digit) {
  const n = Number(digit);
  if (!Number.isInteger(n) || n < 1 || n > 9) return null;
  const p = orderedPresets(state.presets, state.accounts)[n - 1];
  return p ? p.id : null;
}

/** Account "+ New preset…" pre-selects: the active preset's account, else the first account, else null. */
export function newPresetAccountId(state) {
  const active = state.presets.find((p) => p.id === state.activePresetId);
  if (active && state.accounts.some((a) => a.id === active.accountId)) return active.accountId;
  return state.accounts.length ? state.accounts[0].id : null;
}

/**
 * Rows to draw, top to bottom:
 *   { kind: 'header', account }                                  one per account that has visible presets
 *   { kind: 'preset', id, name, shortcut, active, missing, error }
 *   { kind: 'action', id: NEW | MANAGE, label }                   always last, also when nothing matches
 * `filter` keeps presets whose name contains it (case-insensitive). Shortcut labels follow the
 * unfiltered menu order, so they never change while typing.
 */
export function menuRows(state, filter = '') {
  const byId = new Map(state.accounts.map((a) => [a.id, a]));
  const f = filter.trim().toLowerCase();
  const rows = [];
  let group;
  orderedPresets(state.presets, state.accounts).forEach((p, i) => {
    if (f && !p.name.toLowerCase().includes(f)) return;
    const account = byId.get(p.accountId) || null;
    const g = account ? account.id : null;
    if (g !== group) {
      if (account) rows.push({ kind: 'header', account });
      group = g;
    }
    rows.push({
      kind: 'preset', id: p.id, name: p.name, shortcut: i < 9 ? `⌘${i + 1}` : null,
      active: p.id === state.activePresetId, missing: !account, error: !!(account && account.error),
    });
  });
  rows.push({ kind: 'action', id: NEW, label: '+ New preset…' }, { kind: 'action', id: MANAGE, label: '⚙ Manage presets…' });
  return rows;
}

/** Highlight when the menu opens or the filter changes: the active preset, else the first preset, else "+ New preset…". */
export function initialHighlight(rows) {
  const active = rows.findIndex((r) => r.kind === 'preset' && r.active);
  if (active >= 0) return active;
  const first = rows.findIndex((r) => r.kind === 'preset');
  return first >= 0 ? first : rows.findIndex((r) => r.kind === 'action');
}

/** Next selectable row (presets and actions; headers are skipped) in direction dir (+1 / -1), wrapping. */
export function moveHighlight(rows, current, dir) {
  const selectable = rows.flatMap((r, i) => (r.kind === 'header' ? [] : [i]));
  const at = selectable.indexOf(current);
  if (at < 0) return dir > 0 ? selectable[0] : selectable[selectable.length - 1];
  return selectable[(at + dir + selectable.length) % selectable.length];
}

/** What activating a row does: { type: 'select', id } | { type: 'new' } | { type: 'manage' } | null. */
export function rowAction(row) {
  if (!row || row.kind === 'header') return null;
  if (row.kind === 'action') return { type: row.id === NEW ? 'new' : 'manage' };
  return { type: 'select', id: row.id };
}

/**
 * Keyboard reducer while the menu is open. menu = { filter, hi } (hi = index into menuRows(state, filter)).
 * ↑/↓ move, Enter activates, Esc closes, Backspace / printable characters edit the filter.
 * Returns { menu, action }; action is null, { type: 'close' } or a rowAction().
 */
export function menuKey(state, menu, key) {
  const rows = menuRows(state, menu.filter);
  if (key === 'ArrowDown' || key === 'ArrowUp') {
    return { menu: { ...menu, hi: moveHighlight(rows, menu.hi, key === 'ArrowDown' ? 1 : -1) }, action: null };
  }
  if (key === 'Escape') return { menu, action: { type: 'close' } };
  if (key === 'Enter') return { menu, action: rowAction(rows[menu.hi]) };
  if (key === 'Backspace' || key.length === 1) {
    const filter = key === 'Backspace' ? menu.filter.slice(0, -1) : menu.filter + key;
    return { menu: { filter, hi: initialHighlight(menuRows(state, filter)) }, action: null };
  }
  return { menu, action: null };
}

/** The message posted to Swift for a menu action. */
export function messageFor(action, state) {
  if (!action) return null;
  if (action.type === 'select') return { type: 'selectPreset', id: action.id };
  if (action.type === 'new') return { type: 'newPreset', accountId: newPresetAccountId(state) };
  if (action.type === 'manage') return { type: 'openSettings', tab: 'presets' };
  return null;
}

/** Top-bar button: account colour dot + "Account · Preset". */
export function buttonLabel(state) {
  const p = state.presets.find((x) => x.id === state.activePresetId);
  if (!p) return { color: null, text: 'No presets' };
  const a = state.accounts.find((x) => x.id === p.accountId);
  return a ? { color: safeColor(a.color), text: `${a.name} · ${p.name}` } : { color: null, text: p.name };
}

/** Only "#rrggbb" reaches a style attribute. */
export function safeColor(c) {
  return /^#[0-9a-fA-F]{6}$/.test(c) ? c : '#6b7895';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd chart && npm test; cd ..`
Expected: `Tests  50 passed (50)`.

- [ ] **Step 5: Commit**

```bash
git add chart/src/presetMenu.js chart/test/presetMenu.test.js
git commit -m "feat(otm): preset menu logic (grouping, ⌘1…⌘9, filter, keyboard)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Chart UI — preset menu, P, ⌘1…⌘9, setup/banner routing, axis field names

Replaces the native `<select>` with the account-grouped preset menu (button with account colour dot + "Account · Preset"), opens it with a click or **P**, maps ⌘1…⌘9, posts `newPreset {accountId}` / `openSettings {tab}`, shows the setup overlay message from Swift, and draws axis labels as `<axis label> (<field name>)` (§11.8.1).

**Files:**
- Modify (full replacement): `SRC/chart/public/index.html`, `SRC/chart/public/style.css`, `SRC/chart/src/main.js`
- Modify: `SRC/chart/src/labels.js` (append `axisTitle`), `SRC/chart/src/render.js` (axis labels)
- Test: `SRC/chart/test/labels.test.js`

**Interfaces:**
- Consumes: `presetMenu.js` exports (Task 6); `state.setup`, `state.status.bannerTab`, `state.axisLabels` (Task 4).
- Produces:
  - `labels.js`: `axisTitle(base: string, names: string | string[] | undefined) -> string` — `axisTitle('↑ Urgency', 'Priority') === '↑ Urgency (Priority)'`, unmapped → `'Value (not mapped)'`, arrays join with `' + '`.
  - `render.js`: `drawScene(g, o)` reads optional `o.axisLabels {value?, effort?, urgency?}`.
  - DOM ids: `#pwrap`, `#pbtn` (`.dot`, `.lbl`, `.car`), `#pmenu`, `#setupMsg`. `#preset` is removed.
  - Messages to Swift: `selectPreset {id}` (menu, ⌘1…⌘9), `newPreset {accountId}` ("+ New preset…"), `openSettings {tab: 'presets'}` ("⚙ Manage presets…"), `openSettings {tab}` from the setup overlay (`state.setup.tab`, default `'accounts'`) and from a link banner (`state.status.bannerTab`, omitted when absent).

- [ ] **Step 1: Write the failing test**

In `chart/test/labels.test.js`, change the import line to

```js
import { truncate, brightness, placeLabels, chooseCardCorner, axisTitle } from '../src/labels.js';
```

and append:

```js

describe('axisTitle', () => {
  test('appends the mapped field name', () => {
    expect(axisTitle('↑ Urgency', 'Priority')).toBe('↑ Urgency (Priority)');
    expect(axisTitle('Value', 'Business Value')).toBe('Value (Business Value)');
    expect(axisTitle('← Less effort', 'Story Points')).toBe('← Less effort (Story Points)');
  });
  test('unmapped → (not mapped)', () => {
    expect(axisTitle('Value', undefined)).toBe('Value (not mapped)');
    expect(axisTitle('Value', '  ')).toBe('Value (not mapped)');
    expect(axisTitle('Value', [])).toBe('Value (not mapped)');
  });
  test('several fields join with " + "', () => {
    expect(axisTitle('↑ Urgency', ['Priority', 'Due date'])).toBe('↑ Urgency (Priority + Due date)');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd chart && npx vitest run test/labels.test.js; cd ..`
Expected: FAIL — `axisTitle is not a function`.

- [ ] **Step 3: Implement axis labels**

Append to `chart/src/labels.js`:

```js

/**
 * Axis label with the mapped Jira field name(s) (spec §11.8.1): axisTitle('↑ Urgency', 'Priority') → "↑ Urgency (Priority)".
 * `names` is a string or an array (several fields join with " + "); nothing usable → "(not mapped)".
 */
export function axisTitle(base, names) {
  const list = (Array.isArray(names) ? names : [names]).filter((n) => typeof n === 'string' && n.trim() !== '');
  return `${base} (${list.length ? list.join(' + ') : 'not mapped'})`;
}
```

In `chart/src/render.js`, replace

```js
import { placeLabels, brightness } from './labels.js';
```

with

```js
import { placeLabels, brightness, axisTitle } from './labels.js';
```

replace the doc line

```js
 * o = { w, h, tasks, cam, settings, selectedKey, matches(task) -> bool, pulses: Map<key, startMs>, now }
```

with

```js
 * o = { w, h, tasks, cam, settings, selectedKey, matches(task) -> bool, pulses: Map<key, startMs>, now,
 *       axisLabels: { value?, effort?, urgency? } (mapped field names) }
```

and replace

```js
  txt(P(1.12, 1, 0), 'Value', '#7aa2ff');
  txt(P(0, -0.14, 0), '← Less effort', '#6ee08f');
  txt(P(0, 1, 1.1), '↑ Urgency', '#ff7070');
```

with

```js
  const AL = o.axisLabels || {};
  txt(P(1.12, 1, 0), axisTitle('Value', AL.value), '#7aa2ff');
  txt(P(0, -0.14, 0), axisTitle('← Less effort', AL.effort), '#6ee08f');
  txt(P(0, 1, 1.1), axisTitle('↑ Urgency', AL.urgency), '#ff7070');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd chart && npm test; cd ..`
Expected: `Tests  53 passed (53)`.

- [ ] **Step 5: Replace the preset `<select>` with the menu**

Replace `chart/public/index.html` with (the `<select id="preset">` becomes `#pwrap`; the setup paragraph gets `id="setupMsg"`):

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Glance</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<div id="pn" tabindex="0">
  <div class="bar">
    <div id="pwrap">
      <button id="pbtn" title="Preset (P)"><span class="dot"></span><span class="lbl"></span><span class="car">▾</span></button>
      <div id="pmenu" role="listbox"></div>
    </div>
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
    <button id="bReset" aria-label="Reset view" title="Reset view (R)"><span class="ico">⟲</span><span class="txt">Reset view</span></button>
    <div id="tip"></div>
    <div id="card"></div>
    <div id="toast"></div>
    <div id="setup"><p id="setupMsg">Finish setup to see your Jira issues.</p><button id="bSetup">Open settings</button></div>
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

Replace `chart/public/style.css` with (the `#preset` rule becomes the `#pwrap` / `#pbtn` / `#pmenu` rules):

```css
html, body { margin: 0; height: 100%; overflow: hidden; background: #0f1420; color: #9aa6bd;
  font: 11px -apple-system, BlinkMacSystemFont, sans-serif; -webkit-user-select: none; user-select: none; }
#pn { height: 100vh; display: flex; flex-direction: column; outline: none; background: #0f1420; }
.bar { height: 30px; flex: none; display: flex; align-items: center; gap: 8px; padding: 0 10px; background: #131a28; border-bottom: 1px solid #1e2636; }
#pwrap { position: relative; }
#pbtn { display: flex; align-items: center; gap: 5px; max-width: 340px; background: #1e2636; color: #c9d2e3; border: none; border-radius: 10px; padding: 2px 8px; font-size: 10.5px; cursor: pointer; white-space: nowrap; }
#pbtn .lbl { overflow: hidden; text-overflow: ellipsis; }
#pbtn .car { color: #6b7895; }
#pbtn .dot, #pmenu .dot { width: 8px; height: 8px; border-radius: 50%; flex: none; display: inline-block; }
#pmenu { position: absolute; top: 24px; left: 0; min-width: 250px; max-height: 360px; overflow-y: auto; background: rgba(22,28,42,.98); border: 1px solid #2b3550; border-radius: 8px; padding: 4px 0; box-shadow: 0 8px 24px rgba(0,0,0,.55); z-index: 8; display: none; color: #c9d2e3; font-size: 11px; }
#pmenu .ph { display: flex; align-items: center; gap: 6px; padding: 6px 10px 2px; font-size: 9.5px; letter-spacing: .06em; text-transform: uppercase; color: #6b7895; }
#pmenu .pi { display: flex; align-items: center; gap: 6px; padding: 4px 10px; cursor: pointer; white-space: nowrap; }
#pmenu .pi.hi { background: #3b82f6; color: #fff; }
#pmenu .ck { width: 10px; flex: none; }
#pmenu .sc { margin-left: auto; padding-left: 16px; color: #6b7895; font-size: 10px; }
#pmenu .pi.hi .sc { color: #dbe6ff; }
#pmenu .warn { color: #f4c542; }
#pmenu .pi.hi .warn { color: #fff3c4; }
#pmenu .sep { height: 1px; background: #2b3550; margin: 4px 0; }
#pmenu .pf { padding: 3px 10px 5px; color: #8fb8ff; font-size: 10px; border-bottom: 1px solid #2b3550; margin-bottom: 3px; }
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
#q { -webkit-user-select: text; user-select: text; }
#bReset { position: absolute; top: 10px; right: 10px; z-index: 3; display: flex; align-items: center; gap: 5px; height: 26px; padding: 0 10px 0 8px; border-radius: 13px; background: rgba(30,38,54,.9); border: 1px solid #2b3550; color: #c9d2e3; font: 11px -apple-system, system-ui, sans-serif; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,.4); opacity: 0; transform: translateY(-4px); pointer-events: none; transition: opacity .18s, transform .18s; }
#bReset.show { opacity: 1; transform: translateY(0); pointer-events: auto; }
#bReset:hover { color: #fff; border-color: #3b82f6; }
#bReset:focus-visible { outline: 2px solid #3b82f6; }
#bReset.show:active { transform: scale(.97); }
```

Replace `chart/src/main.js` with. Changes vs. the current file: imports `presetMenu.js`; `renderChrome()` sets the button label instead of filling the `<select>` and sets `#setupMsg`; `draw()` passes `axisLabels`; new "preset menu" section (`openMenu`, `closeMenu`, `runMenuAction`, `drawMenu`, outside-click close); top-bar handlers post `openSettings {tab}`; the keydown handler routes keys to `menuKey` while the menu is open, closes it on ⌘ shortcuts, maps ⌘1…⌘9 and opens the menu on **P**.

```js
import { computeFit, fitPoints } from './fit.js';
import { DEFAULT_CAMERA, FACTORY_VIEW, clampView, normalizeYaw } from './projection.js';
import { drawScene } from './render.js';
import { chooseCardCorner } from './labels.js';
import { validateState } from './state.js';
import { buttonLabel, initialHighlight, menuKey, menuRows, messageFor, rowAction, safeColor, shortcutPresetId } from './presetMenu.js';
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

let lastViewTimer = 0;
const saveLastViewSoon = () => {
  clearTimeout(lastViewTimer);
  lastViewTimer = setTimeout(() => {
    if (drag) return;
    post({ type: 'saveLastView', yaw: normalizeYaw(st.yaw), pitch: st.pitch, zoom: st.zoom });
  }, 500);
};

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
    axisLabels: st.state.axisLabels,
  });
  placeCard();
  $('bReset').classList.toggle('show', !atDefault());
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
  if (!st.viewInit) { const v0 = state.lastView ?? state.view; st.yaw = v0.yaw; st.pitch = v0.pitch; st.zoom = v0.zoom; st.viewInit = true; }
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
  const lbl = buttonLabel(s);
  $('pbtn').querySelector('.dot').style.background = lbl.color || 'transparent';
  $('pbtn').querySelector('.lbl').textContent = lbl.text;
  if (menu) drawMenu();
  const b = $('banner');
  const text = s.status.banner || s.status.truncated;
  b.style.display = text ? 'block' : 'none';
  b.textContent = text || '';
  b.className = s.status.banner && /settings/i.test(s.status.banner) ? 'link' : '';
  $('setup').style.display = s.configured ? 'none' : 'flex';
  $('setupMsg').textContent = (s.setup && s.setup.message) || 'Finish setup to see your Jira issues.';
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

function atDefault() {
  const dv = st.state.view;
  return Math.abs(st.yaw - dv.yaw) < 0.05 && Math.abs(st.pitch - dv.pitch) < 0.05 && Math.abs(st.zoom - dv.zoom) < 0.005;
}

function placeCard() {
  if (!st.sel) return;
  const m = st.scene.proj.find((x) => x.t.key === st.sel);
  if (!m) return;
  const card = $('card');
  const obstacles = [...st.scene.labels.map((l) => l.rect), ...st.scene.proj.map((x) => ({ x: x.p.x - x.r, y: x.p.y - x.r, w: 2 * x.r, h: 2 * x.r }))];
  const rb = $('bReset');
  if (rb.classList.contains('show')) {
    const a = rb.getBoundingClientRect(), b = cv.getBoundingClientRect();
    obstacles.push({ x: a.left - b.left, y: a.top - b.top, w: a.width, h: a.height }, { x: w - 130, y: 0, w: 130, h: 44 });
  }
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
  const j = i < 0 ? (dir > 0 ? 0 : order.length - 1) : (i + dir + order.length) % order.length;
  select(order[j].key);
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
    const v = clampView(st.yaw, st.pitch, def(), value === 'free'); st.yaw = v.yaw; st.pitch = v.pitch; refitAnimated(); saveLastViewSoon();
  }
  syncQS(); draw();
}
const parseSeg = (key, v) => (['grid', 'zoneNames', 'alwaysOnTop'].includes(key) ? v === 'true' : key === 'refreshMinutes' ? Number(v) : v);
qs.querySelectorAll('.seg b').forEach((b) => { b.onclick = () => setSetting(b.parentNode.dataset.k, parseSeg(b.parentNode.dataset.k, b.dataset.v)); });
qs.querySelectorAll('input[type=range]').forEach((i) => {
  i.oninput = () => {
    if (i.dataset.k === 'zoom') { st.zoom = Number(i.value) / 100; refitNow(); draw(); saveLastViewSoon(); return; }
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

// ---------- preset menu (§11.6) ----------
let menu = null; // { filter, hi } while open
function openMenu() {
  if (!st.state) return;
  menu = { filter: '', hi: initialHighlight(menuRows(st.state, '')) };
  drawMenu();
}
function closeMenu() { menu = null; drawMenu(); $('pn').focus(); }
function runMenuAction(action) {
  if (!action) return;
  const msg = messageFor(action, st.state);
  closeMenu();
  if (msg) post(msg);
}
function drawMenu() {
  const el = $('pmenu');
  if (!menu || !st.state) { el.style.display = 'none'; el.innerHTML = ''; return; }
  const rows = menuRows(st.state, menu.filter);
  let html = menu.filter ? `<div class="pf">${escapeHTML(menu.filter)}</div>` : '';
  rows.forEach((r, i) => {
    if (r.kind === 'header') {
      html += `<div class="ph"><span class="dot" style="background:${safeColor(r.account.color)}"></span>${escapeHTML(r.account.name)}</div>`;
      return;
    }
    const cls = `pi${i === menu.hi ? ' hi' : ''}`;
    if (r.kind === 'action') {
      if (rows[i - 1] && rows[i - 1].kind !== 'action') html += '<div class="sep"></div>';
      html += `<div class="${cls}" data-i="${i}"><span class="ck"></span>${escapeHTML(r.label)}</div>`;
      return;
    }
    const warn = r.missing ? ' <span class="warn">⚠ account missing</span>' : r.error ? ' <span class="warn">⚠</span>' : '';
    html += `<div class="${cls}" data-i="${i}"><span class="ck">${r.active ? '✓' : ''}</span>${escapeHTML(r.name)}${warn}<span class="sc">${r.shortcut || ''}</span></div>`;
  });
  el.innerHTML = html;
  el.style.display = 'block';
  el.querySelectorAll('[data-i]').forEach((d) => {
    d.onmousedown = (e) => e.preventDefault();
    d.onclick = () => runMenuAction(rowAction(rows[Number(d.dataset.i)]));
  });
  const hi = el.querySelector('.pi.hi');
  if (hi) hi.scrollIntoView({ block: 'nearest' });
}
$('pbtn').onclick = () => (menu ? closeMenu() : openMenu());
window.addEventListener('mousedown', (e) => { if (menu && !$('pwrap').contains(e.target)) closeMenu(); });

// ---------- top bar ----------
$('bR').onclick = () => post({ type: 'refetch' });
$('bQ').onclick = toggleQS;
$('bS').onclick = () => post({ type: 'openSettings' });
$('bSetup').onclick = () => post({ type: 'openSettings', tab: (st.state && st.state.setup && st.state.setup.tab) || 'accounts' });
$('banner').onclick = () => {
  if ($('banner').className !== 'link') return;
  const tab = st.state && st.state.status.bannerTab;
  post(tab ? { type: 'openSettings', tab } : { type: 'openSettings' });
};

// ---------- keyboard ----------
window.addEventListener('keydown', (e) => {
  if (!st.state || document.activeElement === q) return;
  const m = e.metaKey || e.ctrlKey, k = e.key.toLowerCase();
  if (menu && !m) {
    e.preventDefault();
    const r = menuKey(st.state, menu, e.key);
    menu = r.menu;
    if (r.action && r.action.type === 'close') return closeMenu();
    if (r.action) return runMenuAction(r.action);
    return drawMenu();
  }
  if (menu) closeMenu();
  if (m && /^[1-9]$/.test(e.key)) {
    e.preventDefault();
    const id = shortcutPresetId(st.state, e.key);
    if (id) post({ type: 'selectPreset', id });
    return;
  }
  if (!m && k === 'p') { e.preventDefault(); return openMenu(); }
  if (e.key === 'Tab') { e.preventDefault(); return step(e.shiftKey ? -1 : 1); }
  if (e.key === 'Escape') {
    e.preventDefault();
    if (qs.style.display === 'block') return toggleQS();
    if (q.style.display === 'inline-block') return closeSearch();
    if (st.sel) return select(null);
    return post({ type: 'hide' });
  }
  if ((m && k === 'o') || (e.key === 'Enter' && document.activeElement.tagName !== 'BUTTON')) { e.preventDefault(); return openIssue(); }
  if (m && k === 'r') { e.preventDefault(); return post({ type: 'refetch' }); }
  if (m && k === 'f') { e.preventDefault(); return openSearch(); }
  if (m && e.key === ',') { e.preventDefault(); return post({ type: 'openSettings' }); }
  if (!m && k === 'r') { resetView(); return; }
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
  if (d.moved) { saveLastViewSoon(); return refitAnimated(); }
  if (e.target === cv) { const m = hit(e); select(m ? m.t.key : null); }
});
function resetView() { if (!st.state || atDefault()) return; st.yaw = st.state.view.yaw; st.pitch = st.state.view.pitch; st.zoom = st.state.view.zoom; refitAnimated(); syncQS(); saveLastViewSoon(); toast('View reset'); }
$('bReset').addEventListener('click', resetView);
// double-click a task dot opens it in Jira; double-click on empty space does nothing
cv.addEventListener('dblclick', (e) => { const m = hit(e); if (m) { select(m.t.key); openIssue(); } });
cv.addEventListener('wheel', (e) => { e.preventDefault(); st.zoom = Math.max(0.5, Math.min(3, st.zoom * Math.exp(-e.deltaY * 0.0015))); refitNow(); draw(); syncQS(); saveLastViewSoon(); }, { passive: false });
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

- [ ] **Step 6: Build and check in a browser**

Run: `cd chart && npm test && npm run build && cd ..`
Expected: `Tests  53 passed (53)`, then `dist/chart.js` written.

Run: `python3 -m http.server 8791 --directory chart/dist` (in a second terminal), open `http://localhost:8791/index.html` (it renders the bundled fixture and logs messages as `[otm→native] …` in the console), then check:
- Top bar shows a blue dot + "Personal · My open work ▾"; axis labels read "Value (Business Value)", "← Less effort (Story Points)", "↑ Urgency (Priority)".
- Click the chart, press **P**: menu shows PERSONAL (✓ My open work ⌘1, Due this week ⌘2), COMPANY (My company work ⚠ ⌘3), a separator, "+ New preset…", "⚙ Manage presets…".
- ↓ moves the highlight (skips headers), typing `co` filters to "My company work", Enter logs `{type: selectPreset, id: p2}`, Esc closes.
- ⌘2 logs `{type: selectPreset, id: due-week}`; "+ New preset…" logs `{type: newPreset, accountId: default}`; "⚙ Manage presets…" logs `{type: openSettings, tab: presets}`.
Stop the server afterwards.

- [ ] **Step 7: Commit**

```bash
git add chart/public chart/src chart/test
git commit -m "feat(otm): preset menu with account groups, P and ⌘1…⌘9; axis labels show mapped field names

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Settings routing, panel messages, Accounts tab

`SettingsViewModel` becomes the router (current tab, account to edit, account for the Axes tab, New preset request). `AppDelegate` handles `newPreset {accountId}`, `openSettings {tab}` and the result of `selectPreset`. The Connection tab is replaced by the Accounts tab (§11.7): list with colour dot, name, site and status, "+ Add account", Edit, Remove with confirmation, "Map axes for <account>" for accounts with incomplete axes, and the add/edit form with "Save & Test". UI only: verified by build + manual check (no unit-test target for the app).

**Files:**
- Create: `SRC/Sources/OnscreenTodoMatrix/AccountsTab.swift`
- Modify (full replacement): `SRC/Sources/OnscreenTodoMatrix/SettingsViewModel.swift`
- Modify: `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift`, `SRC/Sources/OnscreenTodoMatrix/SettingsWindowController.swift`, `SRC/Sources/OnscreenTodoMatrix/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppModel.saveAccount`, `removeAccount`, `makeAPI(accountId:)`, `newAccountId()`, `hasCredentials`, `hasError(accountId:)`, `storedToken(accountId:)`, `selectPreset(id:) -> PresetSelection`, `activeAccount`, `AppConfig.isAccountNameValid`, `AccountPalette` (Tasks 1, 5).
- Produces (app target):
  - `enum SettingsTab: String, Hashable { case accounts, presets, axes, shortcuts, general }` (raw values = `openSettings {tab}` strings)
  - `struct NewPresetRequest: Identifiable, Equatable { let id: UUID; var accountId: String? }`
  - `SettingsViewModel`: `@Published var tab: SettingsTab`, `editAccountId: String?`, `axesAccountId: String?`, `newPreset: NewPresetRequest?`, `generalError: String`; `func open(tab: SettingsTab?, accountId: String?)`; `func openNewPreset(accountId: String?)`; `static func describe(_ error: Error) -> String`. Kept temporarily for the old Filters/Axes views: `fields`, `priorities`, `jqlStatus`, `loadFields()`, `testJQL(_:)`, `optionValues(for:)`, `usableFields(matching:)` (removed in Tasks 9–10).
  - `SettingsWindowController.show(tab: SettingsTab? = nil, accountId: String? = nil)`, `showNewPreset(accountId: String?)`
  - `AccountsTab(model:vm:)`, `AccountDot(color: String)`, `Color(hex: String)`, `struct AccountDraft { var id: String?; var name, site, email, token: String }`

- [ ] **Step 1: Replace the view model with the router**

Replace `Sources/OnscreenTodoMatrix/SettingsViewModel.swift` with:

```swift
import Foundation
import OTMCore

/// Asks Settings to show the New preset sheet (§11.7) with this account pre-selected.
struct NewPresetRequest: Identifiable, Equatable {
    let id = UUID()
    var accountId: String?
}

/// Which Settings tab / sheet is showing, set by the panel (`openSettings {tab}`, `newPreset {accountId}`)
/// and by the tabs themselves. Each tab keeps its own form state.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var tab: SettingsTab = .accounts
    /// Accounts tab: open this account's form (e.g. from "Jira sign-in failed (Company) · Open settings").
    @Published var editAccountId: String?
    /// Axes tab: the account being mapped (nil = the active preset's account).
    @Published var axesAccountId: String?
    /// Non-nil while the New preset sheet is shown.
    @Published var newPreset: NewPresetRequest?
    @Published var generalError = ""

    // Used by the v1.1 Filters and Axes tabs until Tasks 9 and 10 replace them.
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []
    @Published var jqlStatus: [String: String] = [:]

    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Routes an `openSettings {tab}` request. `accountId` selects the account for the Accounts/Axes tabs.
    func open(tab: SettingsTab?, accountId: String?) {
        guard let tab else { return }
        self.tab = tab
        switch tab {
        case .accounts: editAccountId = accountId
        case .axes: axesAccountId = accountId ?? axesAccountId
        default: break
        }
    }

    func openNewPreset(accountId: String?) {
        tab = .presets
        newPreset = NewPresetRequest(accountId: accountId)
    }

    func loadFields() async {
        guard let account = model.activeAccount, let api = try? model.makeAPI(accountId: account.id) else { return }
        guard let loaded = try? await api.fields() else { return }
        fields = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let p = try? await api.priorities() { priorities = p }
        let suggested = DefaultMappings.suggest(fields: fields, current: account.axes)
        if suggested != account.axes { model.updateAxes(accountId: account.id) { $0 = suggested } }
    }

    func testJQL(_ preset: JQLPreset) async {
        jqlStatus[preset.id] = "Testing…"
        jqlStatus[preset.id] = await model.testJQL(preset.jql, accountId: preset.accountId).text
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

- [ ] **Step 2: Create the Accounts tab**

Create `Sources/OnscreenTodoMatrix/AccountsTab.swift`:

```swift
import OTMCore
import SwiftUI

extension Color {
    /// "#rrggbb" (AccountPalette).
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x6b7895
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// The account's stable colour dot (same palette and order as the panel's preset menu).
struct AccountDot: View {
    let color: String
    var body: some View { Circle().fill(Color(hex: color)).frame(width: 9, height: 9) }
}

/// Form state for adding (id == nil) or editing one account.
struct AccountDraft: Equatable {
    var id: String?
    var name = ""
    var site = ""
    var email = ""
    var token = ""
}

/// Accounts tab (§11.7): list with status, + Add account, Edit, Remove (with confirmation).
struct AccountsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var draft: AccountDraft?
    @State private var status: [String: String] = [:]
    @State private var formMessage = ""
    @State private var busy = false
    @State private var confirmRemove: JiraAccount?

    var body: some View {
        Form {
            if let form = Binding($draft) {
                accountForm(form)
            } else {
                accountList
            }
            Text("API tokens are stored only in your macOS Keychain. The app only reads from Jira.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear(perform: openRequestedForm)
        .onChange(of: vm.editAccountId) { openRequestedForm() }
        .task { await testAccounts() }
        .confirmationDialog(
            "Remove \(confirmRemove?.name ?? "")?",
            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
            presenting: confirmRemove
        ) { account in
            Button("Remove", role: .destructive) {
                model.removeAccount(id: account.id)
                status[account.id] = nil
            }
        } message: { _ in
            Text("Its presets and its API token in the Keychain are deleted too.")
        }
    }

    // MARK: - List

    private var accountList: some View {
        Section("Accounts") {
            ForEach(Array(model.config.accounts.enumerated()), id: \.element.id) { index, account in
                accountRow(account, color: AccountPalette.color(at: index))
            }
            Button("+ Add account") {
                formMessage = ""
                draft = AccountDraft()
            }
        }
    }

    private func accountRow(_ account: JiraAccount, color: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AccountDot(color: color)
                Text(account.name).fontWeight(.medium)
                Text(account.site).foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { edit(account) }
                Button("Remove", role: .destructive) { confirmRemove = account }
            }
            let line = statusLine(account)
            if !line.isEmpty {
                Text(line).font(.caption).foregroundStyle(line.hasPrefix("Connected as") ? .green : .orange)
            }
            if !account.axes.isComplete {
                Button("Map axes for \(account.name)") {
                    vm.axesAccountId = account.id
                    vm.tab = .axes
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func statusLine(_ account: JiraAccount) -> String {
        if model.hasError(accountId: account.id) { return "Jira sign-in failed" }
        if let s = status[account.id] { return s }
        return model.hasCredentials(account) ? "" : "Not connected"
    }

    // MARK: - Form

    private func accountForm(_ d: Binding<AccountDraft>) -> some View {
        Section(d.wrappedValue.id == nil ? "Add account" : "Edit account") {
            TextField("Name", text: d.name, prompt: Text("Personal, Company…"))
            TextField("Jira site", text: d.site, prompt: Text("your-company.atlassian.net"))
            TextField("Email", text: d.email)
            SecureField("API token", text: d.token)
            Link("Create an API token at id.atlassian.com",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
            if !d.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty,
               !model.config.isAccountNameValid(d.wrappedValue.name, excludingId: d.wrappedValue.id) {
                Text("An account with this name already exists.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Save & Test") { Task { await saveAndTest(d.wrappedValue) } }
                    .disabled(busy || !canSave(d.wrappedValue))
                if busy { ProgressView().controlSize(.small) }
                Text(formMessage).foregroundStyle(.secondary)
                Spacer()
                if !model.config.accounts.isEmpty {
                    Button("Cancel") {
                        draft = nil
                        vm.editAccountId = nil
                    }
                }
            }
        }
    }

    private func canSave(_ d: AccountDraft) -> Bool {
        model.config.isAccountNameValid(d.name, excludingId: d.id)
            && AppConfig.normalizeSite(d.site) != nil
            && !d.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !d.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func edit(_ account: JiraAccount) {
        formMessage = ""
        draft = AccountDraft(id: account.id, name: account.name, site: account.site, email: account.email,
                             token: model.storedToken(accountId: account.id) ?? "")
    }

    /// Opens the form the panel asked for (vm.editAccountId), or the Add form when there is no account yet.
    private func openRequestedForm() {
        if let id = vm.editAccountId, let account = model.config.account(id: id) {
            edit(account)
        } else if model.config.accounts.isEmpty, draft == nil {
            draft = AccountDraft(name: "Personal")
        }
    }

    /// Trims, saves the account + Keychain token, then calls /myself. Success closes the form.
    private func saveAndTest(_ d: AccountDraft) async {
        busy = true
        defer { busy = false }
        let id = d.id ?? model.newAccountId()
        var account = model.config.account(id: id) ?? JiraAccount(id: id, name: "")
        account.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.site = d.site.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = d.email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.saveAccount(account, token: d.token.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            formMessage = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        draft?.id = id // a second Save & Test edits this account instead of adding another
        do {
            let me = try await model.makeAPI(accountId: id).myself()
            status[id] = "Connected as \(me.displayName)"
            draft = nil
            vm.editAccountId = nil
            formMessage = ""
            if model.activeAccount?.id == id { await model.refresh(.manual) }
        } catch {
            formMessage = SettingsViewModel.describe(error)
        }
    }

    /// Fills "Connected as …" for every account that has credentials.
    private func testAccounts() async {
        for account in model.config.accounts where model.hasCredentials(account) && status[account.id] == nil {
            do {
                let me = try await model.makeAPI(accountId: account.id).myself()
                status[account.id] = "Connected as \(me.displayName)"
            } catch {
                status[account.id] = SettingsViewModel.describe(error)
            }
        }
    }
}
```

Behaviour to keep: "Save & Test" trims name/site/email/token, saves the account and its Keychain token (`model.saveAccount`), then calls `/myself`; success shows "Connected as <displayName>" in the row and closes the form, failure keeps the form open with the error. The first account gets id `"default"` (Ruling 1); with no account yet the Add form opens by itself, pre-filled with the name "Personal".

- [ ] **Step 3: Wire the tabs and the wizard header**

In `Sources/OnscreenTodoMatrix/SettingsView.swift`:

Delete the whole `struct ConnectionTab: View { … }` (from `struct ConnectionTab: View {` up to, not including, `struct FiltersTab: View {`).

Replace

```swift
enum SettingsTab: Hashable { case connection, filters, axes, shortcuts, general }
```

with

```swift
/// Raw values are the `tab` strings of the panel's `openSettings {tab}` message.
enum SettingsTab: String, Hashable { case accounts, presets, axes, shortcuts, general }
```

Delete the line

```swift
    @State var tab: SettingsTab = .connection
```

Replace

```swift
            TabView(selection: $tab) {
                ConnectionTab(vm: vm).tabItem { Text("1. Connect") }.tag(SettingsTab.connection)
                FiltersTab(model: model, vm: vm).tabItem { Text("2. Filter") }.tag(SettingsTab.filters)
                AxesTab(model: model, vm: vm).tabItem { Text("3. Axes") }.tag(SettingsTab.axes)
```

with

```swift
            TabView(selection: $vm.tab) {
                AccountsTab(model: model, vm: vm).tabItem { Text("Accounts") }.tag(SettingsTab.accounts)
                FiltersTab(model: model, vm: vm).tabItem { Text("Presets") }.tag(SettingsTab.presets)
                AxesTab(model: model, vm: vm).tabItem { Text("Axes") }.tag(SettingsTab.axes)
```

Replace

```swift
            step("1. Connect", done: vm.isConnected || (model.activeAccount.map { model.storedToken(accountId: $0.id) != nil && $0.siteURL != nil } ?? false))
            step("2. Filter", done: !model.config.presets.isEmpty)
```

with

```swift
            step("1. Add account", done: model.config.accounts.contains { model.hasCredentials($0) })
            step("2. Presets", done: model.activeAccount != nil)
```

Replace

```swift
            Button(tab == .axes ? "Done · show panel" : "Next") {
                switch tab {
                case .connection: tab = .filters
                case .filters: tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(tab == .axes && !model.isConfigured)
```

with

```swift
            Button(vm.tab == .axes ? "Done · show panel" : "Next") {
                switch vm.tab {
                case .accounts: vm.tab = .presets
                case .presets: vm.tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(vm.tab == .axes && !model.isConfigured)
```

- [ ] **Step 4: Route `openSettings {tab}` and `newPreset {accountId}`**

In `Sources/OnscreenTodoMatrix/SettingsWindowController.swift`, replace

```swift
    func show() {
        if window == nil {
```

with

```swift
    /// Shows Settings; `tab` / `accountId` come from the panel's `openSettings {tab}` (nil = keep the current tab).
    func show(tab: SettingsTab? = nil, accountId: String? = nil) {
        if window == nil {
```

and replace

```swift
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
    }
```

with

```swift
        vm.open(tab: tab, accountId: accountId)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
    }

    /// "+ New preset…" in the panel: Settings on the New preset sheet with that account pre-selected.
    func showNewPreset(accountId: String?) {
        show()
        vm.openNewPreset(accountId: accountId)
    }
```

In `Sources/OnscreenTodoMatrix/AppDelegate.swift` (`handle(_:)`), replace

```swift
        case "openSettings":
            settings.show()
        case "selectPreset":
            if let id = msg["id"] as? String {
                model.selectPreset(id: id)
                Task { await model.refresh(.manual) }
            }
```

with

```swift
        case "openSettings":
            let tab = (msg["tab"] as? String).flatMap(SettingsTab.init(rawValue:))
            settings.show(tab: tab, accountId: tab == .accounts || tab == .axes ? model.activeAccount?.id : nil)
        case "newPreset":
            if model.config.accounts.isEmpty {
                settings.show(tab: .accounts)
            } else {
                settings.showNewPreset(accountId: msg["accountId"] as? String)
            }
        case "selectPreset":
            guard let id = msg["id"] as? String else { break }
            switch model.selectPreset(id: id) {
            case .selected: Task { await model.refresh(.manual) }
            case .accountMissing: settings.show(tab: .presets)
            case .notFound: break
            }
```

(`ChartWebView` needs no change: every message other than `ready`/`log` is already forwarded to `onMessage`.)

- [ ] **Step 5: Build and run all tests**

Run: `swift build && swift test`
Expected: `Build complete!`, `✔ Test run with 128 tests in 18 suites passed`.

- [ ] **Step 6: Manual check (back up the real config first — Global Constraints)**

Run: `cp -R ~/Library/Application\ Support/onscreen-todo-matrix ~/onscreen-todo-matrix-backup-v1.1` (once), then `cd chart && npm run build && cd .. && swift run OnscreenTodoMatrix`.
Expected: the existing v1.1 setup appears as account "Personal" (migrated); Settings (⌘,) opens on Accounts with a blue dot, "Personal", the site and "Connected as <you>"; "+ Add account" → form → "Save & Test" with a wrong token shows "Jira sign-in failed · Open settings" and keeps the form; Remove asks "Remove <name>?". In the panel, "⚙ Manage presets…" switches Settings to the Presets tab. Quit with the menu-bar Quit.

- [ ] **Step 7: Commit**

```bash
git add Sources/OnscreenTodoMatrix
git commit -m "feat(otm): settings routing, newPreset/openSettings{tab} messages, Accounts tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Presets tab + New preset sheet

Presets tab (§11.7): presets grouped by account (colour dot + name), each group with "+ New preset"; each row has name, JQL, Test (count or Jira error), Make active / "Active", Delete; drag to reorder within an account (= menu order = ⌘1…⌘9); presets whose account is missing appear under "⚠ account missing" with an account picker to reassign. New preset sheet: Account picker (pre-selected by the caller), Name, JQL template chips, JQL, live Test; "Create & show" saves, activates, closes Settings (the existing close handler shows the panel and refreshes). Save is disabled while the name is empty/duplicate or the last Test failed with a JQL error (`AppConfig.canCreatePreset`, tested in Task 5).

**Files:**
- Create: `SRC/Sources/OnscreenTodoMatrix/PresetsTab.swift`, `SRC/Sources/OnscreenTodoMatrix/NewPresetSheet.swift`
- Modify: `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift`, `SRC/Sources/OnscreenTodoMatrix/SettingsViewModel.swift`

**Interfaces:**
- Consumes: `AppModel.selectPreset`, `addPreset(_:activate:)`, `deletePreset(id:)`, `testJQL(_:accountId:) -> JQLTestResult`, `updateConfig`, `refresh`; `AppConfig.movingPresets(accountId:fromOffsets:toOffset:)`, `isPresetNameValid`, `canCreatePreset`; `JQLTemplate.all` (Tasks 1, 5); `SettingsViewModel.openNewPreset`, `newPreset`, `NewPresetRequest`, `AccountDot` (Task 8).
- Produces: `PresetsTab(model:vm:)`, `NewPresetSheet(model:request:onCreated:)`; `SettingsView` presents the sheet with `.sheet(item: $vm.newPreset)`. Removes `FiltersTab`, `SettingsViewModel.jqlStatus`, `SettingsViewModel.testJQL(_:)`.

- [ ] **Step 1: Create the Presets tab**

Create `Sources/OnscreenTodoMatrix/PresetsTab.swift`:

```swift
import OTMCore
import SwiftUI

/// Presets tab (§11.7): presets grouped by account; drag to reorder within an account (= menu order = ⌘1…⌘9).
struct PresetsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var testStatus: [String: String] = [:]

    private var orphans: [JQLPreset] {
        model.config.presets.filter { model.config.account(id: $0.accountId) == nil }
    }

    var body: some View {
        List {
            ForEach(Array(model.config.accounts.enumerated()), id: \.element.id) { index, account in
                Section {
                    ForEach(model.config.presets.filter { $0.accountId == account.id }) { preset in
                        presetRow(preset)
                    }
                    .onMove { source, destination in
                        var c = model.config
                        c.presets = c.movingPresets(accountId: account.id, fromOffsets: source, toOffset: destination)
                        model.updateConfig(c)
                    }
                    Button("+ New preset") { vm.openNewPreset(accountId: account.id) }
                } header: {
                    HStack(spacing: 6) {
                        AccountDot(color: AccountPalette.color(at: index))
                        Text(account.name)
                    }
                }
            }
            if !orphans.isEmpty {
                Section("⚠ account missing") {
                    ForEach(orphans) { preset in orphanRow(preset) }
                }
            }
            if model.config.accounts.isEmpty {
                Text("Add an account first (Accounts tab).").foregroundStyle(.secondary)
            }
        }
    }

    private func presetRow(_ preset: JQLPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: binding(preset.id, \.name))
            if !model.config.isPresetNameValid(preset.name, accountId: preset.accountId, excludingId: preset.id) {
                Text("Preset names must be unique within an account.").font(.caption).foregroundStyle(.orange)
            }
            TextField("JQL", text: binding(preset.id, \.jql), axis: .vertical)
                .lineLimit(2...5)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Test") { Task { await test(preset.id) } }
                Text(testStatus[preset.id] ?? "").foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.config.activePreset?.id == preset.id {
                    Text("Active").foregroundStyle(.green)
                } else {
                    Button("Make active") {
                        if model.selectPreset(id: preset.id) == .selected { Task { await model.refresh(.manual) } }
                    }
                }
                Button("Delete", role: .destructive) { delete(preset.id) }
                    .disabled(model.config.presets.count <= 1)
            }
        }
        .padding(.vertical, 4)
    }

    /// A preset whose account was deleted: reassign it (it cannot be activated until then) or delete it.
    private func orphanRow(_ preset: JQLPreset) -> some View {
        HStack {
            Text(preset.name)
            Spacer()
            Picker("Account", selection: Binding(
                get: { "" },
                set: { newId in
                    var c = model.config
                    guard !newId.isEmpty, let i = c.presets.firstIndex(where: { $0.id == preset.id }) else { return }
                    c.presets[i].accountId = newId
                    model.updateConfig(c)
                }
            )) {
                Text("Choose…").tag("")
                ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
            }
            .frame(width: 200)
            Button("Delete", role: .destructive) { delete(preset.id) }
        }
    }

    private func current(_ id: String) -> JQLPreset? { model.config.presets.first { $0.id == id } }

    private func binding(_ id: String, _ path: WritableKeyPath<JQLPreset, String>) -> Binding<String> {
        Binding(
            get: { current(id)?[keyPath: path] ?? "" },
            set: { value in
                var c = model.config
                guard let i = c.presets.firstIndex(where: { $0.id == id }) else { return }
                c.presets[i][keyPath: path] = value
                model.updateConfig(c)
            }
        )
    }

    private func test(_ id: String) async {
        guard let preset = current(id) else { return }
        testStatus[id] = "Testing…"
        testStatus[id] = await model.testJQL(preset.jql, accountId: preset.accountId).text
    }

    /// Deleting the active preset activates the next one and refreshes immediately.
    private func delete(_ id: String) {
        let wasActive = model.config.activePreset?.id == id
        model.deletePreset(id: id)
        if wasActive { Task { await model.refresh(.manual) } }
    }
}
```

- [ ] **Step 2: Create the New preset sheet**

Create `Sources/OnscreenTodoMatrix/NewPresetSheet.swift`:

```swift
import OTMCore
import SwiftUI

/// New preset sheet (§11.7): account picker, name, JQL template chips and a live Test.
/// "Create & show" saves the preset, makes it active, closes Settings (which shows the panel and refreshes).
struct NewPresetSheet: View {
    @ObservedObject var model: AppModel
    let request: NewPresetRequest
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accountId = ""
    @State private var name = ""
    @State private var jql = ""
    @State private var test: JQLTestResult?
    @State private var testing = false

    private var trimmedJQL: String { jql.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New preset").font(.headline)
            Form {
                Picker("Account", selection: $accountId) {
                    ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
                }
                TextField("Name", text: $name)
                if !name.trimmingCharacters(in: .whitespaces).isEmpty,
                   !model.config.isPresetNameValid(name, accountId: accountId) {
                    Text("A preset with this name already exists for this account.").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    ForEach(JQLTemplate.all, id: \.title) { template in
                        Button(template.title) { apply(template) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                TextField("JQL", text: $jql, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Test") { Task { await runTest() } }
                        .disabled(trimmedJQL.isEmpty || testing)
                    if testing { ProgressView().controlSize(.small) }
                    Text(test?.text ?? "").foregroundStyle(testColor).lineLimit(3)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create & show") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedJQL.isEmpty
                              || !model.config.canCreatePreset(name: name, accountId: accountId, lastTest: test))
            }
        }
        .padding(16)
        .frame(width: 600)
        .onAppear {
            accountId = request.accountId.flatMap { model.config.account(id: $0)?.id }
                ?? model.activeAccount?.id ?? model.config.accounts.first?.id ?? ""
        }
        .task(id: "\(accountId)\n\(jql)") {
            // Live Test: runs 600 ms after the last edit; editing clears the previous result.
            test = nil
            guard !trimmedJQL.isEmpty, !accountId.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await runTest()
        }
    }

    private var testColor: Color {
        switch test {
        case .count?: return .green
        case .jqlError?, .failed?: return .orange
        case nil: return .secondary
        }
    }

    /// Fills the JQL; also the name while it is still empty ("Unassigned in project…" → "Unassigned in project").
    private func apply(_ template: JQLTemplate) {
        jql = template.jql
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = template.title.replacingOccurrences(of: "…", with: "")
        }
    }

    private func runTest() async {
        testing = true
        test = await model.testJQL(trimmedJQL, accountId: accountId)
        testing = false
    }

    private func create() {
        let preset = JQLPreset(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               jql: trimmedJQL, accountId: accountId)
        model.addPreset(preset, activate: true)
        dismiss()
        DispatchQueue.main.async(execute: onCreated) // close Settings once the sheet is gone
    }
}
```

- [ ] **Step 3: Swap the tab and present the sheet**

In `Sources/OnscreenTodoMatrix/SettingsView.swift`:

Delete the whole `struct FiltersTab: View { … }` (from `struct FiltersTab: View {` up to, not including, `struct AxesTab: View {`).

Replace

```swift
                FiltersTab(model: model, vm: vm).tabItem { Text("Presets") }.tag(SettingsTab.presets)
```

with

```swift
                PresetsTab(model: model, vm: vm).tabItem { Text("Presets") }.tag(SettingsTab.presets)
```

Replace

```swift
        .frame(minWidth: 620, minHeight: 520)
    }
```

with

```swift
        .frame(minWidth: 620, minHeight: 520)
        .sheet(item: $vm.newPreset) { request in
            NewPresetSheet(model: model, request: request, onCreated: onDone)
        }
    }
```

In `Sources/OnscreenTodoMatrix/SettingsViewModel.swift`, replace

```swift
    // Used by the v1.1 Filters and Axes tabs until Tasks 9 and 10 replace them.
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []
    @Published var jqlStatus: [String: String] = [:]
```

with

```swift
    // Used by the v1.1 Axes tab until Task 10 replaces it.
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []
```

and delete

```swift
    func testJQL(_ preset: JQLPreset) async {
        jqlStatus[preset.id] = "Testing…"
        jqlStatus[preset.id] = await model.testJQL(preset.jql, accountId: preset.accountId).text
    }

```

- [ ] **Step 4: Build and run all tests**

Run: `swift build && swift test`
Expected: `Build complete!`, `✔ Test run with 128 tests in 18 suites passed`.

- [ ] **Step 5: Manual check**

Run: `swift run OnscreenTodoMatrix` (real config already backed up in Task 8).
Expected: Settings → Presets lists the presets under a section header with a blue dot and "Personal", ending with "+ New preset"; Test shows "<n> issues match"; dragging a preset within its account changes its ⌘ number in the panel menu. In the panel, "+ New preset…" opens Settings on the "New preset" sheet with the active preset's account selected; clicking "Due this week" fills the name and JQL and, ~0.6 s later, shows "<n> issues match"; typing `bogus =` shows "JQL error: …" and disables "Create & show"; a valid preset + "Create & show" closes Settings, shows the panel with the new preset active and refreshes.

- [ ] **Step 6: Commit**

```bash
git add Sources/OnscreenTodoMatrix
git commit -m "feat(otm): Presets tab grouped by account and New preset sheet with templates + live Test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Axes tab per account + wizard cleanup

Axes tab (§11.7): account picker at the top; mappings are edited per account with that account's fields and priorities (loaded from its site); empty axes are pre-filled by `DefaultMappings.suggest`, which also saves each mapped field's display name (`AxisConfig.fieldName`, §11.8.1) so the chart's axis labels work offline; picking a field saves its name with the mapping. Issue-based hints (live "N issues mapped" line, observed option values, unmapped values) are shown only for the account of the active preset. The v1.1 Axes view and the temporary view-model members are removed; `SettingsView.swift` keeps only the container, the wizard header (1. Add account → 2. Presets → 3. Axes, latched for the first-run session) and the Shortcuts / General tabs.

**Files:**
- Create: `SRC/Sources/OnscreenTodoMatrix/AxesTab.swift`
- Modify (full replacement): `SRC/Sources/OnscreenTodoMatrix/SettingsView.swift`, `SRC/Sources/OnscreenTodoMatrix/SettingsViewModel.swift`
- Modify: `SRC/Sources/OnscreenTodoMatrix/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `AppModel.updateAxes(accountId:_:)`, `makeAPI(accountId:)`, `activeAccount`, `unmappedLabels`, `renderState`, `issues`; `DefaultMappings.suggest` / `mapping(for:)`, `AxisConfig.fieldName` (Tasks 4–5); `SettingsViewModel.axesAccountId`, `describe` (Task 8).
- Produces: `AxesTab(model:vm:)`, `AxisEditor(axis:accountId:model:fields:priorities:)`. `SettingsViewModel` final API: `tab`, `editAccountId`, `axesAccountId`, `newPreset`, `generalError`, `open(tab:accountId:)`, `openNewPreset(accountId:)`, `describe(_:)`. `SettingsWindowController.show` no longer loads fields (the Axes tab loads them for its account).

- [ ] **Step 1: Create the per-account Axes tab**

Create `Sources/OnscreenTodoMatrix/AxesTab.swift`:

```swift
import OTMCore
import SwiftUI

/// Axes tab (§11.7): account picker at the top; mappings are per account, fields/priorities come from that account's site.
struct AxesTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var fields: [JiraField] = []
    @State private var priorities: [String] = []
    @State private var fieldsAccountId: String?
    @State private var loadMessage = ""

    /// vm.axesAccountId if it still exists, else the active preset's account, else the first account.
    private var accountId: String? {
        if let id = vm.axesAccountId, model.config.account(id: id) != nil { return id }
        return model.activeAccount?.id ?? model.config.accounts.first?.id
    }

    var body: some View {
        Form {
            if let accountId {
                Picker("Account", selection: Binding(get: { accountId }, set: { vm.axesAccountId = $0 })) {
                    ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
                }
                if fields.isEmpty || fieldsAccountId != accountId {
                    Text(loadMessage.isEmpty ? "Loading fields from this account's site…" : loadMessage)
                        .foregroundStyle(.secondary)
                    Button("Reload fields") { Task { await loadFields(accountId) } }
                } else if !loadMessage.isEmpty {
                    Text(loadMessage).foregroundStyle(.orange)
                }
                ForEach(OTMCore.Axis.allCases, id: \.self) { axis in
                    AxisEditor(axis: axis, accountId: accountId, model: model,
                               fields: fieldsAccountId == accountId ? fields : [], priorities: priorities)
                }
            } else {
                Text("Add an account first (Accounts tab).").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: accountId) { if let accountId { await loadFields(accountId) } }
    }

    /// Loads that account's fields + priorities, then pre-fills its empty axes (DefaultMappings.suggest).
    /// A failed reload keeps the previously loaded fields of the same account and shows the error.
    private func loadFields(_ id: String) async {
        loadMessage = ""
        guard let api = try? model.makeAPI(accountId: id) else {
            loadMessage = "Connect this account first (Accounts tab)."
            return
        }
        do {
            let loaded = try await api.fields()
            fields = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            fieldsAccountId = id
        } catch {
            loadMessage = SettingsViewModel.describe(error)
            return
        }
        priorities = (try? await api.priorities()) ?? []
        if let account = model.config.account(id: id) {
            let suggested = DefaultMappings.suggest(fields: fields, current: account.axes)
            if suggested != account.axes { model.updateAxes(accountId: id) { $0 = suggested } }
        }
    }
}

struct AxisEditor: View {
    let axis: OTMCore.Axis
    let accountId: String
    @ObservedObject var model: AppModel
    let fields: [JiraField]
    let priorities: [String]
    @State private var filter = ""

    private var cfg: AxisConfig { model.config.account(id: accountId)?.axes[axis] ?? AxisConfig() }
    /// Issue-based hints (live line, observed values, unmapped values) only make sense for the account on screen.
    private var isActiveAccount: Bool { model.activeAccount?.id == accountId }

    private func update(_ change: (inout AxisConfig) -> Void) {
        model.updateAxes(accountId: accountId) { change(&$0[axis]) }
    }

    private var title: String {
        switch axis {
        case .value: return "Value (X)"
        case .effort: return "Effort (Y)"
        case .urgency: return "Urgency (Z)"
        }
    }

    private var usableFields: [JiraField] {
        fields.filter {
            FieldClassifier.kind(of: $0) != .unsupported
                && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        Section(title) {
            TextField("Filter fields", text: $filter)
            Picker("Field", selection: Binding(
                get: { cfg.mapping?.fieldId ?? "" },
                set: { id in
                    let field = fields.first(where: { $0.id == id })
                    update {
                        $0.mapping = field.flatMap { DefaultMappings.mapping(for: $0) }
                        $0.fieldName = field?.name
                    }
                }
            )) {
                Text("— none —").tag("")
                let usable = usableFields
                if let current = cfg.mapping?.fieldId, !usable.contains(where: { $0.id == current }) {
                    Text(fields.first(where: { $0.id == current })?.name ?? current).tag(current)
                }
                ForEach(usable) { f in
                    Text("\(f.name)  ·  \(f.schemaType ?? "?")").tag(f.id)
                }
            }
            if let mapping = cfg.mapping { editor(for: mapping) }
            HStack {
                Text("Missing value position")
                Slider(value: Binding(get: { cfg.missingDefault }, set: { v in update { $0.missingDefault = v } }), in: 0...1)
                Text(String(format: "%.2f", cfg.missingDefault)).monospacedDigit()
            }
            if isActiveAccount {
                Text(liveLine).font(.caption).foregroundStyle(.secondary)
                if let unmapped = model.unmappedLabels[axis], !unmapped.isEmpty {
                    Text("Unmapped values (placed at the middle): \(unmapped.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var liveLine: String {
        let tasks = model.renderState.tasks
        let missing = tasks.filter { $0.missing[axis] }.count
        return "\(tasks.count) issues mapped · \(missing) missing value"
    }

    /// Values offered in the option-level editor.
    private func optionValues(fieldId: String, levels: [String: Double]) -> [String] {
        var values: [String]
        if fieldId == "priority" && !priorities.isEmpty {
            values = priorities
        } else {
            values = isActiveAccount ? AxisMapper.observedLabels(fieldId: fieldId, issues: model.issues) : []
        }
        for key in levels.keys.sorted() where !values.contains(key) { values.append(key) }
        return values
    }

    @ViewBuilder
    private func editor(for mapping: AxisMapping) -> some View {
        switch mapping {
        case .option(let fieldId, let levels):
            ForEach(optionValues(fieldId: fieldId, levels: levels), id: \.self) { label in
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
```

- [ ] **Step 2: Remove the v1.1 Axes view and the temporary members**

Replace `Sources/OnscreenTodoMatrix/SettingsView.swift` with (container + wizard header + Shortcuts + General; `AxesTab` / `AxisEditor` now live in `AxesTab.swift`):

```swift
import KeyboardShortcuts
import OTMCore
import SwiftUI

/// Raw values are the `tab` strings of the panel's `openSettings {tab}` message.
enum SettingsTab: String, Hashable { case accounts, presets, axes, shortcuts, general }

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    let onDone: () -> Void
    /// Latched at creation so the setup header (and its Done button) survives becoming configured mid-wizard.
    @State private var wizard: Bool

    init(model: AppModel, vm: SettingsViewModel, onDone: @escaping () -> Void) {
        self.model = model
        self.vm = vm
        self.onDone = onDone
        _wizard = State(initialValue: !model.isConfigured)
    }

    var body: some View {
        VStack(spacing: 0) {
            if wizard { setupHeader }
            TabView(selection: $vm.tab) {
                AccountsTab(model: model, vm: vm).tabItem { Text("Accounts") }.tag(SettingsTab.accounts)
                PresetsTab(model: model, vm: vm).tabItem { Text("Presets") }.tag(SettingsTab.presets)
                AxesTab(model: model, vm: vm).tabItem { Text("Axes") }.tag(SettingsTab.axes)
                ShortcutsTab().tabItem { Text("Shortcuts") }.tag(SettingsTab.shortcuts)
                GeneralTab(model: model, vm: vm).tabItem { Text("General") }.tag(SettingsTab.general)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 520)
        .sheet(item: $vm.newPreset) { request in
            NewPresetSheet(model: model, request: request, onCreated: onDone)
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 14) {
            step("1. Add account", done: model.config.accounts.contains { model.hasCredentials($0) })
            step("2. Presets", done: model.activeAccount != nil)
            step("3. Axes", done: model.activeAccount?.axes.isComplete ?? false)
            Spacer()
            Button(vm.tab == .axes ? "Done · show panel" : "Next") {
                switch vm.tab {
                case .accounts: vm.tab = .presets
                case .presets: vm.tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(vm.tab == .axes && !model.isConfigured)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func step(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
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

Replace `Sources/OnscreenTodoMatrix/SettingsViewModel.swift` with:

```swift
import Foundation
import OTMCore

/// Asks Settings to show the New preset sheet (§11.7) with this account pre-selected.
struct NewPresetRequest: Identifiable, Equatable {
    let id = UUID()
    var accountId: String?
}

/// Which Settings tab / sheet is showing, set by the panel (`openSettings {tab}`, `newPreset {accountId}`)
/// and by the tabs themselves. Each tab keeps its own form state.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var tab: SettingsTab = .accounts
    /// Accounts tab: open this account's form (e.g. from "Jira sign-in failed (Company) · Open settings").
    @Published var editAccountId: String?
    /// Axes tab: the account being mapped (nil = the active preset's account).
    @Published var axesAccountId: String?
    /// Non-nil while the New preset sheet is shown.
    @Published var newPreset: NewPresetRequest?
    @Published var generalError = ""

    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Routes an `openSettings {tab}` request. `accountId` selects the account for the Accounts/Axes tabs.
    func open(tab: SettingsTab?, accountId: String?) {
        guard let tab else { return }
        self.tab = tab
        switch tab {
        case .accounts: editAccountId = accountId
        case .axes: axesAccountId = accountId ?? axesAccountId
        default: break
        }
    }

    func openNewPreset(accountId: String?) {
        tab = .presets
        newPreset = NewPresetRequest(accountId: accountId)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? JiraError { return AppModel.bannerText(e, syncedAt: nil) }
        return error.localizedDescription
    }
}
```

In `Sources/OnscreenTodoMatrix/SettingsWindowController.swift`, replace

```swift
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
```

with

```swift
        window?.makeKeyAndOrderFront(nil)
```

- [ ] **Step 3: Build and run all tests**

Run: `swift build && swift test && cd chart && npm test && cd ..`
Expected: `Build complete!`, `✔ Test run with 128 tests in 18 suites passed`, `Tests  53 passed (53)`.

- [ ] **Step 4: Manual check**

Run: `cd chart && npm run build && cd .. && swift run OnscreenTodoMatrix`.
Expected: Settings → Axes shows "Account" = the active preset's account; the field pickers show that site's fields; switching the picker to another account loads its fields ("Loading fields from this account's site…" first) and pre-fills Urgency ← Priority and Effort ← Story Points/Original estimate; the panel's axis labels read e.g. "↑ Urgency (Priority)", "Value (<your value field>)"; "Map axes for <account>" in the Accounts tab opens this tab on that account. A preset of an account with incomplete axes shows the overlay "Map axes for <account> to see this preset"; its "Open settings" opens this tab on that account.

- [ ] **Step 5: Commit**

```bash
git add Sources/OnscreenTodoMatrix
git commit -m "feat(otm): Axes tab per account (field names saved for axis labels); settings wizard for accounts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Manual checklist, README, version 1.2.0, DMG

**Files:**
- Modify: `SRC/docs/manual-checklist.md`, `SRC/scripts/Info.plist`, `productivity/onscreen-todo-matrix/README.md`

**Interfaces:**
- Consumes: everything from Tasks 1–10.
- Produces: `build/Glance-1.2.0.dmg` (not committed; `build/` is git-ignored).

- [ ] **Step 1: Update the manual checklist**

In `docs/manual-checklist.md`, replace

```markdown
- [ ] Keychain: token survives relaunch; `security find-generic-password -s onscreen-todo-matrix` finds the item.
```

with

```markdown
- [ ] Keychain: tokens survive relaunch; `security find-generic-password -s onscreen-todo-matrix -a "jira-api-token:default"` finds the Personal token.
```

replace

```markdown
- [ ] Paste the API token with ⌘V in Settings → Connect (also ⌘A / ⌘C / ⌘Z work in text fields).
```

with

```markdown
- [ ] Paste the API token with ⌘V in Settings → Accounts → Edit (also ⌘A / ⌘C / ⌘Z work in text fields).
```

and append:

```markdown

## v1.2.0 — multiple Jira accounts

Before the first launch of a v1.2 build: `cp -R ~/Library/Application\ Support/onscreen-todo-matrix ~/onscreen-todo-matrix-backup-v1.1`.

- [ ] Upgrade from v1.1: the panel shows the same issues and preset as before, without opening Settings; `config.json` now has `accounts` with `"id" : "default"`, `"name" : "Personal"` and no top-level `site`/`email`/`axes`; `config.v1.json` exists next to it; `cache/my-open-work.json` exists and `last-fetch.json` is gone.
- [ ] Keychain after upgrade: `security find-generic-password -s onscreen-todo-matrix -a "jira-api-token:default"` succeeds and `security find-generic-password -s onscreen-todo-matrix -a jira-api-token` reports "could not be found".
- [ ] Settings → Accounts → "+ Add account" (name "Company", company site, email, token) → "Save & Test" shows "Connected as <you>"; the row offers "Map axes for Company"; it opens Axes on Company with Priority/Story Points pre-filled; map Value.
- [ ] In the panel, "+ New preset…" opens the New preset sheet; choose Company, name "My company work", template "My open work", live Test shows the count, "Create & show" shows the panel on "Company · My company work" with an amber dot.
- [ ] P opens the preset menu grouped PERSONAL / COMPANY with ⌘1… shortcuts, "+ New preset…" and "⚙ Manage presets…" last; ↑/↓, typing to filter, Enter and Esc work.
- [ ] ⌘1 / ⌘2 switch presets: the other preset's cached issues and its own "synced …" time appear at once, then refresh.
- [ ] Quit and relaunch: the last chosen preset is active again.
- [ ] Axis labels show the mapped fields, e.g. "↑ Urgency (Priority)", "Value (Business Value)", "← Less effort (Story Points)"; an unmapped axis shows "(not mapped)"; labels stay correct offline (Wi-Fi off, relaunch).
- [ ] Break the Company token (Edit → wrong token → Save & Test, then switch to its preset and ⌘R): banner "Jira sign-in failed (Company) · Open settings"; ⚠ next to Company presets in the menu; clicking the banner opens Settings → Accounts with the Company form; ⌘1 to a Personal preset still refreshes on focus/timer.
- [ ] Settings → Presets: drag a preset within its account → its ⌘ number in the menu changes; Delete of the active preset activates the next one.
- [ ] Settings → Accounts → Remove Company asks "Remove Company?"; confirming removes its presets from the menu and `security find-generic-password -s onscreen-todo-matrix -a "jira-api-token:<its id>"` finds nothing.
```

- [ ] **Step 2: Bump the version**

In `scripts/Info.plist`, replace

```xml
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
```

with

```xml
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
```

- [ ] **Step 3: Update the README**

In `productivity/onscreen-todo-matrix/README.md`, replace

```markdown
- Implementation plan v1: [plans/arch-20261012-onscreen-todo-matrix-plan.md](plans/arch-20261012-onscreen-todo-matrix-plan.md)
```

with

```markdown
- Implementation plan v1: [plans/arch-20261012-onscreen-todo-matrix-plan.md](plans/arch-20261012-onscreen-todo-matrix-plan.md)
- Implementation plan v1.2.0 (multiple Jira accounts): [plans/arch-20261013-onscreen-todo-matrix-plan-v1.2.0.md](plans/arch-20261013-onscreen-todo-matrix-plan-v1.2.0.md)
```

replace

```markdown
- [ ] v1.2.0: multiple Jira accounts, per-account presets/axes, "+ New preset…" menu — spec review → plan → implement
```

with

```markdown
- [x] v1.2.0: multiple Jira accounts, per-account presets/axes, "+ New preset…" menu, axis labels show mapped fields — spec → plan → implement
```

and replace

```markdown
Installer: `./scripts/build-dmg.sh` → `build/Glance-1.0.0.dmg`; open it and drag Glance to Applications.
```

with

```markdown
Installer: `./scripts/build-dmg.sh` → `build/Glance-1.2.0.dmg`; open it and drag Glance to Applications. Upgrading from 1.1 migrates your settings automatically (backup kept as `config.v1.json` in `~/Library/Application Support/onscreen-todo-matrix/`).
```

- [ ] **Step 4: Build the DMG (runs every test)**

Run: `./scripts/build-dmg.sh`
Expected: chart `Tests  53 passed (53)`, `✔ Test run with 128 tests in 18 suites passed`, `Built: …/build/Glance.app`, `hdiutil verify` OK and `DMG: …/build/Glance-1.2.0.dmg`.

- [ ] **Step 5: Run the manual checklist**

Open `build/Glance.app` (quit any running Glance first) and tick every item of `docs/manual-checklist.md`, including the v1.2.0 section. Fix failures in the owning task's files before continuing.

- [ ] **Step 6: Commit**

```bash
git add docs/manual-checklist.md scripts/Info.plist ../README.md
git commit -m "docs(otm): v1.2.0 manual checklist, README; bump version to 1.2.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review (done while writing)

- **Spec coverage (§11):** 11.1 req 1–2 → Tasks 1, 5, 8; req 3 (last preset) → Task 5 `activePresetIsPersistedAndRestoredOnLaunch`; req 4 ("+ New preset…") → Tasks 6, 7, 9. 11.2 data model / account-missing / name rules → Tasks 1, 5, 9. 11.3 keyed tokens + delete with account → Tasks 1, 5 (`removeAccountDeletesItsPresetsCachesAndTokenAndPicksNextPreset`). 11.4 migration → Task 3 (+ Task 5 failure banner). 11.5 active-preset fetch, per-preset cache, scheduler resume, coalesced refresh, persistence, ⌘1…⌘9 → Tasks 2, 5, 6, 7. 11.6 menu → Tasks 6, 7. 11.7 Accounts / Presets / New preset sheet / Axes / wizard / `isConfigured` → Tasks 8, 9, 10, 5. 11.8 contract → Task 4. 11.10 errors → Task 5 (banner text, ⚠, migration banner, setup overlay) + Tasks 7–8 (routing). 11.11 tests → Tasks 2, 3, 5, 6 + Task 11 manual. 11.12 axis field names → Tasks 4 (model + contract), 7 (drawing), 10 (saved on pick / suggest). Out of scope (11.9) untouched.
- **Placeholders:** none; every code step has the full code or an exact old → new replacement.
- **Type consistency:** names used across tasks — `JiraAccount.defaultId`, `menuOrderedPresets`, `movingPresets(accountId:fromOffsets:toOffset:)`, `read(accountId:)`, `readLegacy()`, `CachedFetch(issues:fetchedAt:accountId:)`, `load(presetId:)`, `ConfigLoadResult.legacy`, `ConfigMigration.finish`, `RenderSetup(message:tab:)`, `RenderAxisLabels`, `AxisConfig.fieldName`, `PresetSelection`, `JQLTestResult.text`, `SettingsTab` raw values, `NewPresetRequest`, `vm.open(tab:accountId:)` — are defined once (Interfaces blocks) and used with the same spelling.
- **Review Focus:** each of the five items has its test in the owning task (Tasks 2, 3, 5, 6).
- **Verified:** the code in this plan was built and run task by task in a scratch copy of SRC: Swift 93 → 96 → 106 → 112 → 128 tests and chart 33 → 50 → 53 tests pass at the stated points; the app target builds after every task.

