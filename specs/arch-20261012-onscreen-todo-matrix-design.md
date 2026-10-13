# onscreen-todo-matrix: Design Spec

**Version:** 1.0.0
**Date:** 2026-10-12
**Category:** arch
**Status:** Design approved in brainstorming session (2026-10-12); implemented. **Superseded by [v1.1.0](arch-20261013-onscreen-todo-matrix-design-v1.1.0.md)** (as built) and [v1.2.0](arch-20261013-onscreen-todo-matrix-design-v1.2.0.md) (multi-account). Rows D16–D19 and a few body lines below were edited during the build; v1.1.0 is the clean as-built version.
**Prototype:** [`../prototype/panel-prototype.html`](../prototype/panel-prototype.html), the final interactive panel; brainstorm mockups are in [`../prototype/brainstorm-mockups/`](../prototype/brainstorm-mockups/)

---

## 1. Purpose

A macOS desktop app that shows the user's Jira Cloud issues as a 3D priority space inside a floating, always-on-top panel. A global hotkey toggles the panel.

The user already has a Jira dashboard for prioritization, but its UI does not answer the important questions at a glance. This app must answer three questions in a ~2-second look:

| # | Question | Answered by |
|---|---|---|
| A | What should I do next (top 1–3)? | Gold-numbered badges + "Next" strip |
| C | What is on fire (high value + high urgency)? | Red glow + brightest (white) dots |
| D | What is the overall shape of my workload? | The 3D stem plot over the Value × Effort floor |

The user explicitly did **not** prioritize "find a specific task" (B) or "what changed since last look" (E). Search (⌘F) and change glides are included as low-cost extras.

### Audience and constraints
- Open source, single user, personal use.
- All data stays on the local machine. There is no server.
- Jira Cloud only (not Data Center/Server).
- macOS only.

### Success criteria
1. Pressing ⌥Space shows the panel over any app. The top-3 and on-fire tasks are identifiable without reading the whole chart.
2. After editing an issue in Jira (opened from the panel with ⌘O) and returning to the panel, the issue's new position is shown without manual action (refetch on focus).
3. Any Jira field can be mapped to any axis, with its values mapped to levels, without editing files.
4. The panel never goes blank because of a network/auth error; it shows the last good data plus a status banner.

---

## 2. Scope

### In scope (v1)
- Jira Cloud connection (site + email + API token, token in Keychain).
- Named JQL presets.
- One Jira field per axis, with type-specific value mapping.
- 3D stem chart, floating panel, chart-first layout, smart summary labels.
- Interactions, quick settings popover and full settings window, as specified below.
- Read-only access to Jira. The app never writes to Jira.
- Local cache for instant/offline display.

### Out of scope (v1), possible later
- Writing to Jira (drag-to-reprioritize). The v1 flow is one-way: **Jira → app**. The user edits in Jira via ⌘O, then the app refetches.
- Combining several fields into one axis (e.g. urgency = max(Priority, due-date closeness)).
- User-editable scoring formula.
- Full-screen overlay window mode (option B in §4.2 decision).
- Jira Data Center/Server, OAuth login, multiple Jira sites.
- Windows/Linux.
- Signed + notarized distribution and Homebrew cask (needs Apple Developer ID).

---

## 3. Core concepts

### 3.1 The three axes (combination of Eisenhower + Action Priority Matrix)
The original idea came from combining two 2D frameworks into one 3D space:

| Axis | Meaning | Origin framework | Normalized range |
|---|---|---|---|
| X: **Value** | importance / impact | Eisenhower "important" + Action Priority "impact" | 0 (low) … 1 (high) |
| Y: **Effort** | effort / time | Action Priority "effort" | 0 (low) … 1 (high) |
| Z: **Urgency** | how urgent | Eisenhower "urgent" | 0 (low) … 1 (high) |

Rendering coordinates (from the prototype): `x = value`, `y = effort` (depth on the floor), `z = urgency` (up).

### 3.2 The floor: Action Priority quadrants
The Value × Effort floor is split at 0.5 / 0.5 into four zones:

| Zone | Value | Effort | Tint (RGBA) | Label opacity |
|---|---|---|---|---|
| Quick wins | ≥ 0.5 | < 0.5 | `70,180,120,.16` | .5 |
| Major projects | ≥ 0.5 | ≥ 0.5 | `90,130,220,.12` | .5 |
| Fill-ins | < 0.5 | < 0.5 | `160,160,160,.04` | .2 |
| Thankless | < 0.5 | ≥ 0.5 | `200,90,90,.05` | .2 |

High-value zones are deliberately brighter (the user asked to prioritize seeing Quick wins + Major projects).

### 3.3 Color: RGB = (Urgency, Ease, Value)
Each task's dot color mixes the three axes as real RGB channels:

```
R = urgency
G = ease = 1 − effort
B = value
channel = 55 + 200 × v      (floor of 55 so "nothing" tasks don't vanish on the dark background)
```

So **brightness ≈ priority** and **hue = why**:

| Color | Meaning |
|---|---|
| White `#FFFFFF` | urgent + valuable + easy, do now |
| Magenta | urgent + valuable + hard, big & pressing |
| Cyan | valuable + easy, not urgent, quick win to schedule |
| Yellow | urgent + easy, low value, someone else's fire (delegate) |
| Blue | valuable + hard, not urgent, major project |
| Green | easy, low value, not urgent, fill-in |
| Dark `#373737` | hard, low value, not urgent, thankless (drop) |

An alternative "Urgency only" color mode (blue → amber → red sequential) is available in quick settings.

### 3.4 Scoring (fixed in v1)
```
score   = value × (0.5 + urgency) / (0.3 + effort)
top 3   = highest scores → gold numbered badges ①②③ + "Next" strip
on fire = value ≥ 0.7 AND urgency ≥ 0.8 → red glow (shadow #ff3b3b, blur 18) + red label text
```
A missing axis value uses that axis' default position (§6.2) in the score too, so a task with unknown effort is neither rewarded nor punished beyond the default.

---

## 4. UI design

### 4.1 Chart: 3D stem plot (option C, final iteration "C v9b")
Each task is a dot floating above its (value, effort) position on the floor; height = urgency. A stem connects the dot to its floor position, so the floor tells you exactly where the task sits.

| Element | Spec (from the approved prototype) |
|---|---|
| Projection | Hand-written perspective: yaw around vertical axis, then pitch; camera distance `D = 1.5`; urgency height scale `H = 0.55` of floor size (`py = z·H − 0.2`) |
| Default camera | **yaw −179.7°, pitch 33.9°** (user-chosen; equivalent to the −539.7° the user found while free-rotating). Yaw is displayed normalized to ±180°. |
| Origin | The "not worth it" corner (value 0, effort high, urgency 0) sits at the back of the scene |
| Axis lines | From the origin: Value = blue `rgba(90,140,255,.85)`, Effort/ease = green `rgba(80,220,120,.85)`, Urgency = red `rgba(255,80,80,.85)`, width 2 |
| Grid | 10×10, `rgba(255,255,255,.10)`; the 0.5 quadrant split lines `rgba(255,255,255,.28)` |
| Stems | **Dotted** by default: dash `[0.5, 3.5]`, round cap, width 1.6, opacity 30% of the dot color. Styles: Solid / Dotted / Dashed / Off; opacity slider 5–80% |
| Floor shadow | Ellipse under each stem, `rgba(0,0,0,.3)` |
| Dot | Radius `6 × perspective scale`; white stroke `rgba(255,255,255,.55)`; drawn far → near |
| Depth fade | `alpha = 1 − 0.55 × (depth − min)/(max − min)`; far tasks dimmer |
| Missing value | Hollow dot at the axis' default position (see §6.2, "Missing value") |
| Auto-fit | Fit to what is drawn (4 floor corners, urgency axis top, all tasks) at the **current** angle; padding 24px; refit animates over 220ms after the mouse is released (not during drag), and on resize |
| Zoom | Scroll / pinch, 0.5×–3×, multiplies the fit scale |
| Rotation | **Limited** (default): yaw ±18°, pitch ±10° around the default angle. **Free** (F key / quick setting): unlimited yaw, pitch clamped ±89° |
| Reset | "⟲ Reset view" pill (top-right, shown only when off-default) or the R key returns to the saved default angle and zoom (double-click removed, see D19) |
| Set default | Saves current angle + zoom as the default (pitch capped ±80°); persisted in config |
| Refetch glide | Tasks whose values changed glide to the new position over 700ms (ease-out cubic) with a gold pulse ring for 1.6s |
| Search dim | Non-matching tasks drawn at 12% opacity |
| Selection | Blue ring `#3b82f6`, width 2.5, radius `r + 4` |

### 4.2 Window form: floating panel (option A)
- Resizable floating panel (NSPanel), brought to front by the hotkey; optional **always-on-top** (off by default), stays open while you work beside it.
- **Global hotkey ⌥Space** shows/hides it (rebindable).
- Panel opacity adjustable 40–100% (the desktop shows through).
- Remembers size and position.
- Menu-bar icon only, no Dock icon. Menu: Show panel · Refresh · Settings… · Quit.
- Launch at login (setting).

### 4.3 Panel layout: chart-first (option A)
```
┌──────────────────────────────────────────────────────────────┐
│ ● ● ●  [My open work ▾]  [search…]      synced 2m ago ⟳ ◐ ⚙   │ ← top bar
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                     3D stem chart (fills panel)              │
│        detail card appears beside the selected dot           │
│        status banner (when an error) under top bar           │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ Next: 1. Rotate leaked Stripe API key · 2. … · 3. …           │ ← Next strip
└──────────────────────────────────────────────────────────────┘
```
- Top bar: JQL preset dropdown, search box (shown on ⌘F), "synced Xs/m ago", refresh ⟳, quick settings ◐, full settings ⚙.
- Next strip: top 3 by score; clicking an item selects it.
- Detail card (on click/Tab): key · status, summary, Value / Ease / Urgency (0–5 scale), Jira priority, due, rank, **⌘O Open in Jira ↗**.
- Known issue from the prototype: the card can cover top-ranked labels. **Requirement:** place the card in the emptiest corner region of the panel that does not cover the selected dot.

### 4.4 Labels: smart summary labels
- Label text = issue **summary**, truncated to 28 characters (`…`). The key is shown on hover/detail card.
- Placement in priority order: selected task first, then top 3 (with gold badge), then by brightness `(urgency + ease + value)/3`.
- Candidate positions tried in order: right, left, above, below the dot. A label is placed only if it stays in bounds and overlaps no placed label and no other dot.
- Labels that cannot be placed are hidden (hover/zoom reveals them).
- Label backdrop `rgba(15,20,32,.6)`; text opacity `.35 + .65 × brightness`; on-fire text `#ff9a9a`; selected text `#8fb8ff`.
- Modes (quick setting): **Smart** (default) / All (no culling) / Key only / Off (only the selected task is labeled).

### 4.5 Interactions
| Action | Default |
|---|---|
| Show / hide panel (global) | **⌥Space** (rebindable; note conflicts with Raycast/Alfred/ChatGPT) |
| Hover dot | Tooltip: key + summary |
| Click dot | Select, show detail card. Click empty space deselects |
| Double-click dot | Open that issue in Jira (same as select + ⌘O) |
| Next / previous task by priority | **Tab** / **⇧Tab** |
| Open selected issue in Jira | **⌘O** or **Enter** (default browser, `https://<site>/browse/<KEY>`) |
| Refetch now | **⌘R** or ⟳ |
| Refetch on focus | On panel focus, if the last fetch is more than 30s old |
| Background refresh | Every 5 min (1m / 5m / 15m / Off) |
| Search | **⌘F**: matches by key or summary stay lit, others dim; Enter selects the best match |
| Esc | Closes search → deselects → hides the panel (in that order) |
| Quick settings | **Q** or ◐ |
| Full settings | **⌘,** |
| Rotate / zoom / reset | Drag / scroll / R or the Reset view pill |
| Free rotation toggle | **F** |

### 4.6 Quick settings popover (◐ / Q)
View-only settings, changed while looking at the chart:

| Group | Settings |
|---|---|
| Look | Labels (Smart / All / Key / Off) · Stems (Solid / Dotted / Dashed / Off) + opacity · Color (RGB / Urgency) · Grid on/off · Zone names on/off |
| View | Rotation (Limited / Free) · Zoom slider · live angle readout `yaw / pitch · zoom` · **Set default** · **Reset** |
| Window | Panel opacity 40–100% · Always on top · Auto refresh (1m / 5m / 15m / Off) |

Footer: "Jira, JQL & field mapping → full settings (⌘,)".

### 4.7 Full settings window (⌘,) and first-run setup
SwiftUI window. On first run (or when the config is missing/corrupt) it opens as a 3-step wizard:

1. **Connect**: site (`xxx.atlassian.net`), email, API token (link to Atlassian's API token page). **Test** calls `/rest/api/3/myself` and shows "Connected as <displayName>".
2. **Filter**: named JQL presets. Default preset "My open work":
   `assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC`.
   **Test** runs the search and shows the match count (or Jira's error message).
3. **Axes**: for each axis choose a field from a searchable list showing the field type, then fill the type-specific editor (§6.2). A live line shows "42 issues mapped · 3 missing value". The chart is not drawn until all 3 axes are mapped.

Other tabs after setup: Connection · Filters · Axes · Shortcuts (hotkey rebinding) · General (launch at login, refresh interval).

---

## 5. Architecture

### 5.1 Tech stack
- **Swift** (SwiftUI + AppKit), macOS 14 (Sonoma) or later.
- **Chart**: the prototype JS (HTML canvas 2D) bundled in the app and hosted in a `WKWebView`. No network access from the web view.
- **Global hotkey**: `sindresorhus/KeyboardShortcuts` (includes rebinding UI; 3.1.0 as of 2026-09).
- **Keychain**: Security framework (`SecItem*`) behind a `TokenStore` protocol.
- **Launch at login**: `SMAppService.mainApp`.
- **Tests**: Swift Testing (core), Vitest (chart JS).

### 5.2 Components
```
┌──────────────────────── onscreen-todo-matrix.app (Swift) ────────────────────────┐
│  AppShell ── menu-bar icon, no Dock icon, launch at login                          │
│     │                                                                              │
│  PanelController ── floating panel: always-on-top toggle, opacity,                 │
│     │                remembers size/position, ⌥Space via KeyboardShortcuts         │
│     ▼                                                                              │
│  ChartView (WKWebView) ◄── render(state JSON) ── AppModel ──► SettingsWindow (⌘,)  │
│     │  the prototype JS chart       ▲                ▲          SwiftUI forms      │
│     └── events: open, refetch, ─────┘                │                             │
│         save view, quick settings                    │                             │
│                                   RefreshScheduler ──┤                             │
│                                   JiraClient ────────┤──► Jira Cloud REST v3       │
│                                   AxisMapper + Scorer┤                             │
│                                   ConfigStore ───────┤──► config.json (App Support)│
│                                   IssueCache ────────┤──► last-fetch.json          │
│                                   TokenStore ────────┘──► macOS Keychain           │
└───────────────────────────────────────────────────────────────────────────────────┘
```

| Unit | Responsibility | Depends on |
|---|---|---|
| **AppShell** | `NSApplication` activation policy `.accessory` (no Dock icon); `MenuBarExtra` with Show panel · Refresh · Settings… · Quit; launch-at-login via `SMAppService` | — |
| **PanelController** | `NSPanel` subclass that can become key (keyboard shortcuts work), `level = .floating` when always-on-top, `alphaValue` for opacity, `collectionBehavior` `.canJoinAllSpaces` + `.fullScreenAuxiliary`, frame autosave, hotkey toggle | AppKit, KeyboardShortcuts |
| **ChartView** | Hosts the bundled chart in `WKWebView`. Swift → JS: `render(RenderState)`. JS → Swift (`WKScriptMessageHandler`): `openIssue(key)`, `refetch`, `saveDefaultView(yaw, pitch, zoom)`, `quickSettingChanged(key, value)`, `log(level, msg)` | WebKit |
| **AppModel** | Single source of truth: issues, mapped tasks, selection, settings; builds `RenderState` | units below |
| **JiraClient** | Read-only Jira Cloud REST v3 with Basic auth (email + API token): `GET /rest/api/3/myself`, `GET /rest/api/3/field`, `GET /rest/api/3/priority`, `POST /rest/api/3/search/jql` (paginated via `nextPageToken`, requesting only needed `fields`) | URLSession |
| **AxisMapper** | Pure: raw field value + axis mapping → 0–1 plus a "missing" flag | — |
| **Scorer** | Pure: score, top 3, on-fire | — |
| **RefreshScheduler** | Triggers: interval timer, panel focus (> 30s since last fetch), manual; honors back-off after 429 | injected clock |
| **ConfigStore** | JSON at `~/Library/Application Support/onscreen-todo-matrix/config.json` holding site, email, JQL presets, axis mappings, default view, quick settings, hotkey, refresh interval | FileManager |
| **IssueCache** | Last successful fetch at `…/last-fetch.json` with timestamp, used for instant launch and offline display | FileManager |
| **TokenStore** | API token in Keychain only, never in config | Security framework |

**Boundaries:** all logic (mapping, scoring, scheduling, Jira client, config) lives in a local Swift package with no UI dependency, so `swift test` runs headless. The panel and web view are thin shells. The JS chart only draws and reports user actions; it never talks to Jira.

### 5.3 Swift ↔ JS contract: `RenderState` (JSON)
```json
{
  "tasks": [
    { "key": "SEC-5", "summary": "Rotate leaked Stripe API key", "status": "In Progress",
      "priority": "Highest", "due": "2026-10-12",
      "value": 0.95, "effort": 0.10, "urgency": 1.0,
      "missing": { "value": false, "effort": false, "urgency": false },
      "score": 9.5, "rank": 1, "fire": true, "changed": false }
  ],
  "view": { "defaultYaw": -179.7, "defaultPitch": 33.9, "zoom": 1.0 },
  "settings": { "labelMode": "smart", "stemStyle": "dotted", "stemOpacity": 30,
                "colorMode": "rgb", "grid": true, "zoneNames": true, "rotation": "limited" },
  "status": { "syncedAt": "2026-10-12T10:42:00Z", "banner": null, "truncated": null }
}
```
One shared fixture file of this shape is used by both the Swift and JS test suites (contract test).

---

## 6. Data flow and field mapping

### 6.1 Refresh flow
```
trigger (timer / focus / ⌘R)
  → JiraClient.search(JQL, fields = summary, status, priority, duedate + mapped fields)
        paginated, capped at 500 issues
  → AxisMapper(config)   raw issue → {key, summary, status, url, value, effort, urgency, missing flags}
  → Scorer               score, top 3, on fire
  → diff with previous   changed keys → glide + pulse
  → ChartView.render(RenderState)  +  IssueCache.save
```

### 6.2 Mapping rules (one Jira field per axis)
| Field type (Jira `schema.type`) | Examples | 0–1 conversion |
|---|---|---|
| **Option list** (`priority`, `option`, `string` with fixed values) | Priority, select fields | User assigns each value a level 0–5 → `level/5`. Values come from `/priority` or from values seen in fetched issues. A newly seen value defaults to the middle (level 2.5) and is flagged "unmapped" in settings |
| **Number** (`number`, time tracking seconds) | Story Points, Original estimate | Linear between min and max: **auto** (from current issues) or **fixed** by user. If min = max → 0.5. Optional **invert** |
| **Date** (`date`, `datetime`) | Due date, custom date | `daysLeft ≤ 0` (overdue or today) → 1.0; linear down to 0 at **horizon** days (default 14); beyond horizon → 0. Optional invert |
| **Missing value** | issue has no story points | Default position per axis (default 0.5, adjustable), `missing` flag → hollow dot |

### 6.3 Starting mappings (pre-filled by the wizard)
- **Urgency ← Priority**: Highest 1.0 · High .75 · Medium .5 · Low .25 · Lowest 0 (the user's own example).
- **Effort ← Story Points** if the field exists (company-managed "Story Points" or team-managed "Story point estimate"), else Original estimate.
- **Value ← user picks** (Jira has no standard value field; e.g. a "Business Value" custom field or a select field).

---

## 7. Error handling
Principle: never show a blank panel. On failure, keep the last good data and show a thin banner under the top bar; the menu-bar icon gets a warning dot.

| Situation | Behavior |
|---|---|
| Offline / network error | Show cached issues: "Offline · showing data from 10:42"; retry on next trigger |
| 401 / 403 | "Jira sign-in failed · Open settings"; auto-refresh paused until credentials are fixed |
| 429 rate limited | Honor `Retry-After`; skip timer ticks until then |
| 400 invalid JQL | Show Jira's error message in the banner and in the settings Test result |
| Mapped field deleted/renamed | Axis flagged in settings; affected issues drawn hollow; banner names the axis |
| > 500 issues | Show first 500: "Showing 500 of 1,240 · narrow your JQL" |
| Config file corrupt | Rename to `config.json.bak` (no data loss), reopen setup wizard |
| Keychain read denied | Ask for the token again |
| JS error in web view | Forwarded to Swift via `log` message → unified logging (`os_log`) |
| Read-only guarantee | `JiraClient` exposes only read calls; there is no code path that writes to Jira |

---

## 8. Testing
TDD per AGENTS.md (`test-driven-development` skill), code review (`requesting-code-review`) before each phase is complete.

| Layer | How |
|---|---|
| AxisMapper, Scorer | Swift Testing; every field type and edge case: overdue, past horizon, min = max, missing values, unmapped option values, invert |
| RefreshScheduler | Injected fake clock: interval ticks, 30s focus rule, 429 back-off |
| ConfigStore, TokenStore | Round trip; corrupt-file → `.bak` recovery; Keychain behind a protocol with an in-memory fake |
| JiraClient | `URLProtocol` stub with recorded JSON fixtures: field list, priority list, paginated search, 401, 429 (+ Retry-After), 400 |
| Chart JS | Prototype split into pure ES modules: `projection`, `fit`, `labels`, `render`; Vitest for projection math, fit bounds, label collision/culling |
| Swift ↔ JS contract | One shared `RenderState` fixture decoded by both suites |
| Window behavior | Manual checklist: hotkey from other apps, panel takes key focus, opacity, always-on-top toggle, all Spaces, launch at login |

---

## 9. Build and distribution
- Xcode app target + local Swift package for core logic.
- Chart JS bundled as app resources (no CDN, no network).
- v1: GitHub releases, ad-hoc signed, personal use.
- Later: Developer ID signing + notarization (DMG), Homebrew cask.

---

## 10. Decision Log

| # | Decision | Alternatives considered | Trade-offs | Rationale |
|---|---|---|---|---|
| D1 | **3D: Value × Effort × Urgency** | Plain Eisenhower 2D; Action Priority 2D; MoSCoW; RICE; ABCDE; Ivy Lee; Pareto (see Appendix A) | 3D adds a dimension but risks occlusion/depth ambiguity | User's own idea: combine Eisenhower (urgent/important) and Action Priority (value/effort); urgency is a separate concern from value/effort |
| D2 | **Chart style C: stems over a quadrant floor** | A: pure 3D scatter; B: 2D Value × Effort with urgency as color/size | A: depth unreadable without rotating. B: fastest read, but urgency is "only" a color. C: hot tasks can cluster and overlap | C keeps a readable 2D floor and a real third dimension; overlap solved by smart labels |
| D3 | **Stems dotted, 30% opacity** | v1 solid 55%/2px; v2 dashed 20%; v3d solid 45% | Too bright competes with dots; too dim is invisible (user feedback both ways) | Dotted reads as a guide, not data; style + opacity are user-adjustable |
| D4 | **Origin at the back; large floor; urgency height 55%; visible grid** | Origin near the viewer; equal height | — | User: "what is near the eyes is what I focus on"; floor is the main reading surface |
| D5 | **RGB = (urgency, ease, value)** | Urgency-only sequential scale; RGB with G = effort (user's first proposal) | G = effort made the green axis contradict the "less effort toward you" direction and hid priority in hue mixes | With G = ease, brightness ≈ priority (white = do now, dark = drop); user confirmed max urgency + value + ease = `#FFF` |
| D6 | **Default view yaw −179.7°, pitch 33.9°** | −45° diagonal (Quick wins corner front); −78°/−90° (high-value half facing viewer) | At −179.7° high effort is nearest, Quick wins at the back | User chose and confirmed this angle; "Set default" lets it change anytime |
| D7 | **Limited rotation by default + Free toggle** | Free only; fixed view | Free makes the fit smaller; fixed gives no depth cues | User asked for small rotation, later added unlimited as an option |
| D8 | **Auto-fit to drawn content at current angle; refit on release; zoom** | Fit for every possible angle | All-angle fit made the chart small (user feedback); per-frame refit would "breathe" | Large chart without clipping and without size changes during drag |
| D9 | **Floating panel (window option A)** | B: full-screen overlay; C: overlay + pinnable panel (assistant's recommendation) | A is smaller and always takes some screen; B can't be worked beside | User chose A |
| D10 | **Chart-first layout** | B: chart + sidebar; C: tall chart + ranked list | Sidebar costs ~27% chart width; list-first makes the chart smallest | User preferred chart-first |
| D11 | **Smart summary labels** | Key-only labels; all summaries (no culling) | Summaries are long; culling hides some labels | Summary is meaningful at a glance; brightest tasks always keep labels. User: "not sure, just try" → default with a setting |
| D12 | **One-way Jira → app; edit via ⌘O + refetch on focus** | Local drag positions; two-way write-back | No in-app editing in v1 | User's explicit flow; avoids write permissions and conflict handling |
| D13 | **Field + value mapping per axis** | Fixed fields | More setup | User requirement ("map field & field values to the axes, e.g. Priority for urgent level") |
| D14 | **Swift (SwiftUI + AppKit) + WKWebView chart** | Go + Wails v3 (pinned v3.0.0-beta.28); Tauri v2 (Rust); Electron | Wails: Go preference fits and covers hotkey/NSPanel/tray, but v3 is pre-release and opacity + launch-at-login need cgo glue. Tauri: mature but Rust, NSPanel via community plugin. Electron: 150+ MB. Swift: not Go, second toolchain | The app is mostly macOS integration with a tiny back end, so Go's strengths go unused; Swift has every requirement first-party, no beta risk, smallest footprint; chart JS reused unchanged. Confirmed by the user per the AGENTS.md "confirm non-Go" rule |
| D15 | **Idea folder `productivity/onscreen-todo-matrix/`** | `tools/`, `personal/` | New top-level category | Existing categories (`ai/`, `infra/`, `auto-earning/`) don't fit; user approved |
| D16 | **Brand name "Glance — Onscreen Todo Matrix"** | Trifocal, Priority Prism, Lumen | 'Glance' is generic and may clash with other apps | User's choice; says the app's purpose (2-second look); internal identifiers unchanged so existing config/token carry over |
| D17 | **Always-on-top off by default** | Always on top by default (original §4.2) | Panel can be covered by other apps | User request: hotkey brings it to front; clicking another app puts that app on top; opt-in toggle kept in quick settings |
| D18 | **Restore last view on launch** | Always start at saved default | Extra config write per view change (debounced 500 ms) | User request: use the last setting on initial load; lastView optional for backward-compatible config |
| D19 | **No double-click reset** | Double-click resets the view (original prototype gesture) | One fewer shortcut | User: not needed; easy to trigger by accident; the Reset view pill and R cover it. Double-click on a task dot now opens the issue in Jira (user request) |

---

## Appendix A: Session context (preserved)

### A.1 Prioritization frameworks considered as alternatives to Eisenhower
- **Action Priority Matrix**: Impact (Value) vs Effort grid; spots quick wins and high-leverage projects.
- **MoSCoW**: Must / Should / Could / Won't; product scope and team planning.
- **RICE**: Reach × Impact × Confidence / Effort; ranks initiatives quantitatively.
- **ABCDE**: letter grades A (critical) to E (eliminate) for daily lists.
- **Ivy Lee**: six key tasks written the night before, done sequentially.
- **Pareto (80/20)**: the vital 20% of tasks producing 80% of results.

User's resulting idea: combine Eisenhower and Action Priority into 3D Oxyz: Ox = value/important, Oy = effort/time, Oz = urgent.

### A.2 "Quick look" questions offered to the user
A. what to do next · B. where a specific task is · C. what's on fire · D. overall shape of the workload · E. what changed since last look. **User chose A, C, D.**

### A.3 Brainstorm iteration history of the chart
1. A/B/C comparison (pure 3D, 2D + color, 3D stems) → C chosen.
2. C v2: lighter dashed stems, origin pushed to the back, depth fade, de-collided labels.
3. C v3: floor ~40% larger, pitch 38°, urgency height 55%, visible 10×10 grid; stems back to 45% (v2 was too dim).
4. C v4: RGB = (urgency, effort, value) per user; assistant flagged axis/color contradiction.
5. C v5: G = ease; brightness = priority; `#FFF` confirmed.
6. C v5b/c: auto-fit so no corner clips (user: "I can not see the corner").
7. C v6: camera faces the high-value half (Quick wins + Major projects).
8. C v7: optional free rotation.
9. C v8: live angle readout + "Set as default".
10. C v9/v9b: default yaw −179.7° / pitch 33.9°; fit to current angle + drawn content; zoom; readout moved below the chart.
11. Labels v1: smart summary labels.
12. Panel: interactions prototype, then quick settings popover + dotted stems (30%).

### A.4 Sample data used in the prototype
18 sample issues (e.g. `SEC-5 Rotate leaked Stripe API key` V .95 / E .10 / U 1.0; `PAY-412 Refund webhook returns 500 for partial refunds` .92 / .20 / .95; `DATA-19 Rebuild data warehouse on ClickHouse` .80 / .95 / .20). Full list in [`../prototype/panel-prototype.html`](../prototype/panel-prototype.html).
