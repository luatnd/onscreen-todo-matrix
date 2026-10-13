# Glance — Onscreen Todo Matrix: Design Spec

**Version:** 1.3.0 (draft — stack marker, axis cones, effort fallback)
**Date:** 2026-10-13
**Category:** arch
**Status:** Approved by the user 2026-10-13 ("one account per preset; no combined 'All accounts' chart; you decide the other" → axes per account (D21) and New-preset sheet in Settings (D24) kept as recommended). Contains all of [v1.1.0 (as built)](arch-20261013-onscreen-todo-matrix-design-v1.1.0.md) plus the multi-account design in **§11**; where §11 changes an earlier section, the earlier section says so.
**Changes in 1.3.0:** contains all of [v1.2.0](arch-20261013-onscreen-todo-matrix-design-v1.2.0.md) plus, inline in §4.1, §4.4, §4.5 and §6.2 and in Decision Log D27–D29: stack marker for coincident tasks (D27), 3D cones at the axis tips (D28), effort fallback from logged time and the Start → Due timeline in a selectable unit (D29). Requested by the user 2026-10-13.
**Product name:** **Glance — Onscreen Todo Matrix** (app name "Glance"); repo/folder and internal identifiers keep `onscreen-todo-matrix`.
**Prototype:** [`../prototype/panel-prototype.html`](../prototype/panel-prototype.html), the final interactive panel; brainstorm mockups are in [`../prototype/brainstorm-mockups/`](../prototype/brainstorm-mockups/)

---

## 1. Purpose

A macOS desktop app (**Glance**) that shows the user's Jira Cloud issues as a 3D priority space inside a floating panel. A global hotkey brings the panel to the front (or hides it); clicking another app puts that app on top. Always-on-top is an opt-in setting.

The user already has a Jira dashboard for prioritization, but its UI does not answer the important questions at a glance. This app must answer three questions in a ~2-second look:

| # | Question | Answered by |
|---|---|---|
| A | What should I do next (top 1–3)? | Gold-numbered badges + "Next" strip |
| C | What is on fire (high value + high urgency)? | Red glow + brightest (white) dots |
| D | What is the overall shape of my workload? | The 3D stem plot over the Value × Effort floor |

The user explicitly did **not** prioritize "find a specific task" (B) or "what changed since last look" (E). Search (⌘F) and change glides are included as low-cost extras.

### Audience and constraints
- Open source, single user, personal use. **One user can have several Jira Cloud accounts on different sites** (e.g. personal and company) — v1.2.0, §11.
- All data stays on the local machine. There is no server.
- Jira Cloud only (not Data Center/Server).
- macOS only.

### Success criteria
1. Pressing ⌥Space brings the panel to the front over any app. The top-3 and on-fire tasks are identifiable without reading the whole chart.
2. After editing an issue in Jira (opened from the panel with ⌘O) and returning to the panel, the issue's new position is shown without manual action (refetch on focus).
3. Any Jira field can be mapped to any axis, with its values mapped to levels, without editing files.
4. The panel never goes blank because of a network/auth error; it shows the last good data plus a status banner.

---

## 2. Scope

### In scope (v1)
- Jira Cloud connection (site + email + API token, token in Keychain). **v1.2.0: several accounts, one token per account (§11).**
- Named JQL presets. **v1.2.0: each preset belongs to one account; last chosen preset restored; "+ New preset…" in the preset menu (§11).**
- One Jira field per axis, with type-specific value mapping.
- 3D stem chart, floating panel, chart-first layout, smart summary labels.
- Interactions, quick settings popover and full settings window, as specified below.
- Read-only access to Jira. The app never writes to Jira.
- Local cache for instant/offline display.
- Every user setting is remembered across launches (§4.8).
- DMG installer built locally (`./scripts/build-dmg.sh`).

### Out of scope (v1), possible later
- Writing to Jira (drag-to-reprioritize). The v1 flow is one-way: **Jira → app**. The user edits in Jira via ⌘O, then the app refetches.
- Combining several fields into one axis (e.g. urgency = max(Priority, due-date closeness)).
- User-editable scoring formula.
- Full-screen overlay window mode (option B in §4.2 decision).
- Jira Data Center/Server, OAuth login. (Multiple Jira sites moved **in scope** in v1.2.0.)
- A combined chart that mixes issues from several accounts in one view ("All accounts" preset) — possible later (§11.9).
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
| Axis cones | A 3D cone at the tip of each axis, pointing away from the origin O (D28): length 0.06, radius 0.016 (floor units; 0.022 was too stubby in the visual check; built in render space so the urgency `H` scale does not squash it), 16 base segments, projected and filled with the axis color; the base disc is drawn darker when it faces the viewer. Effort's cone points toward **less effort** (the line runs from O at effort 1 to effort 0, matching "← Less effort"). Axis names are placed on screen just beyond each apex along the axis direction; if that would leave the canvas, beside the cone on the side away from its line (labels replaced the fixed positions Value 1.12, Effort −0.14, Urgency 1.1). Cone boxes are label obstacles |
| Grid | 10×10, `rgba(255,255,255,.10)`; the 0.5 quadrant split lines `rgba(255,255,255,.28)` |
| Stems | **Dotted** by default: dash `[0.5, 3.5]`, round cap, width 1.6, opacity 30% of the dot color. Styles: Solid / Dotted / Dashed / Off; opacity slider 5–80% |
| Floor shadow | Ellipse under each stem, `rgba(0,0,0,.3)` |
| Dot | Radius `6 × perspective scale`; white stroke `rgba(255,255,255,.55)`; drawn far → near |
| Depth fade | `alpha = 1 − 0.55 × (depth − min)/(max − min)`; far tasks dimmer |
| Missing value | Hollow dot at the axis' default position (see §6.2, "Missing value") |
| Derived effort | An effort estimated from the timeline or logged time (D29) is drawn as a normal solid dot with a **dashed ring** (any member of a stack is enough). The card adds `Effort ≈ 56 h from timeline (Oct 1 → Oct 10)` (`≥ max` when clamped; `from logged time` for spent + remaining); the tooltip adds `≈ 56 h`. Three states: estimated = solid, derived = solid + dashed ring, missing = hollow |
| Stacked tasks | Tasks at exactly the same (value, effort, urgency) and hollow state are one **stack marker** (D27): same dot size; 1 offset outline behind it for 2 tasks, 2 outlines for 3+ ("coin stack"); count badge from 3 tasks (`2/5` while a search matches only part of the stack). Members are ordered by score, then key; the best member drives rank. Fire glow if any member is on fire. Grouping is by data, not screen distance, so stacks do not change while rotating |
| Auto-fit | Fit to what is drawn (4 floor corners, urgency axis top, the 3 axis cone apexes, all tasks) at the **current** angle; padding 24px; refit animates over 220ms after the mouse is released (not during drag), and on resize |
| Zoom | Scroll / pinch, 0.5×–3×, multiplies the fit scale |
| Rotation | **Limited** (default): yaw ±18°, pitch ±10° around the default angle. **Free** (F key / quick setting): unlimited yaw, pitch clamped ±89° |
| Reset | "⟲ Reset view" pill (top-right, shown only when off-default) or the R key returns to the saved default angle and zoom (double-click removed, see D19) |
| Set default | Saves current angle + zoom as the default (pitch capped ±80°); persisted in config (`view`) |
| Last view | Current angle + zoom saved automatically 500 ms after the user stops rotating/zooming (`lastView`); the chart opens at the last view on launch (falls back to the default view) |
| Refetch glide | Tasks whose values changed glide to the new position over 700ms (ease-out cubic) with a gold pulse ring for 1.6s |
| Search dim | Non-matching tasks drawn at 12% opacity |
| Selection | Blue ring `#3b82f6`, width 2.5, radius `r + 4` |

### 4.2 Window form: floating panel (option A)
- Resizable floating panel (NSPanel), brought to front by the hotkey; optional **always-on-top** (off by default), stays open while you work beside it.
- **Global hotkey ⌥Space** (rebindable): if the panel is hidden or behind another app → bring it to the front with keyboard focus (`NSApp.activate()` + `makeKeyAndOrderFront` + `orderFrontRegardless`); if it is already in front with focus → hide it.
- Clicking another app puts that app's windows on top; the panel stays behind (not hidden). With **Always on top** on, the panel uses `.floating` level and stays above other apps.
- Panel opacity adjustable 40–100% (the desktop shows through).
- **Default size 1120×875** (75% larger than the original 640×500), centered in the screen's visible frame and clamped to it; minimum 420×320.
- Remembers the last user size and position (frame autosave `GlancePanel2`); the default size applies only before the first resize/move.
- Title bar shows "Glance" (utility-style title bar; no fake traffic lights in the web content).
- A hidden main menu with an **Edit** submenu (Undo/Redo/Cut/Copy/Paste/Select All) so ⌘V/⌘C/⌘A work in text fields of this accessory app.
- Menu-bar icon only, no Dock icon. Menu: Show panel · Refresh · Settings… · Quit.
- Launch at login (setting).

### 4.3 Panel layout: chart-first (option A)
```
┌──────────────────────────────────────────────────────────────┐
│ [My open work ▾]  [search…]              synced 2m ago ⟳ ◐ ⚙   │ ← top bar
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                     3D stem chart (fills panel)              │
│   detail card in the emptiest corner     [⟲ Reset view] (TR) │
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
- **Reset view pill** (top-right, `⟲ Reset view`): hidden at the saved default view; fades in (opacity + 4 px slide, 180 ms) when yaw/pitch/zoom differ from the default; click or **R** animates back to the default view and shows a "View reset" toast; hover/focus-visible states; while it is shown, the detail card treats the top-right corner as occupied.

### 4.4 Labels: smart summary labels
- Label text = issue **summary**, truncated to 28 characters (`…`). The key is shown on hover/detail card.
- Placement in priority order: selected task first, then top 3 (with gold badge), then by brightness `(urgency + ease + value)/3`.
- Candidate positions tried in order: right, left, above, below the dot. A label is placed only if it stays in bounds and overlaps no placed label and no other dot.
- Labels that cannot be placed are hidden (hover/zoom reveals them).
- Label backdrop `rgba(15,20,32,.6)`; text opacity `.35 + .65 × brightness`; on-fire text `#ff9a9a`; selected text `#8fb8ff`.
- Modes (quick setting): **Smart** (default) / All (no culling) / Key only / Off (only the selected task is labeled).
- Stacks (D27) get **one multi-line label**, one line per member (14px line step), each line with its own rank badge and color:
  - Smart: up to 2 titles, then `+N more`; All: up to 5 titles, then `+N more`; Key: `KEY-1, KEY-2 +N` on one line; Off: the selected member only.
  - The selected member is always one of the shown lines.
  - In Smart / All, a hollow (missing-field) stack of 2+ starts with a header line `N unset` (Key mode stays one line).
  - While searching, only matching members are listed (the card's `i of n` counts matching members plus the selected one).
  - Task labels avoid count badges (their own included), axis cones and axis names.

### 4.5 Interactions
| Action | Default |
|---|---|
| Show / hide panel (global) | **⌥Space** (rebindable; note conflicts with Raycast/Alfred/ChatGPT) |
| Hover dot | Tooltip: key + summary. On a stack: up to 5 lines `KEY · summary`, then `+N more` |
| Click dot | Select, show detail card. Click empty space deselects. On a stack: selects the best member; clicking it again selects the next member (cycles) |
| Step within a stack | Detail card shows `Stacked here ‹ 2 of 3 ›`; **←** / **→** or the arrows step through the members (Tab / ⇧Tab still visit every task by score) |
| Double-click dot | Open that issue in Jira (same as select + ⌘O); on a stack (D27): its best matching member |
| Next / previous task by priority | **Tab** / **⇧Tab** |
| Open selected issue in Jira | **⌘O** or **Enter** (default browser, `https://<site>/browse/<KEY>`) |
| Refetch now | **⌘R** or ⟳ |
| Refetch on focus | On panel focus, if the last fetch is more than 30s old |
| Background refresh | Every 5 min (1m / 5m / 15m / Off) |
| Search | **⌘F**: matches by key or summary stay lit, others dim; Enter selects the best match |
| Esc | Closes search → deselects → hides the panel (in that order) |
| Quick settings | **Q** or ◐ |
| Full settings | **⌘,** |
| Rotate / zoom / reset | Drag / scroll / **R** or the Reset view pill (double-click does NOT reset) |
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

Other tabs after setup: Connection · Filters · Axes · Shortcuts (hotkey rebinding) · General (launch at login, refresh interval). **v1.2.0 renames/extends these to Accounts · Presets · Axes (per account) — see §11.7.**

As built:
- The 1-2-3 setup header is **latched** for the first-run session (it does not disappear the moment the 3rd axis is mapped), and its **Done · show panel** button is enabled once configured.
- Closing the Settings window (Done or the close button) shows the panel if configured and runs a manual refresh.
- **Save & Test** trims email/token, saves the token to Keychain, calls `/myself`, loads fields/priorities, then refreshes.
- **Make active** / deleting the active preset refreshes immediately.
- Fixing credentials or config clears a stale error banner; the next refresh shows it again if still failing.
- Field-list load errors keep the previously loaded fields and show the error; the field picker always keeps the selected field visible even when filtered out.

### 4.8 What is remembered across launches
| Setting | Where |
|---|---|
| Panel size + position | Window frame autosave `GlancePanel2` |
| Last camera view (yaw/pitch/zoom) | `config.lastView` (auto-saved, debounced 500 ms) |
| Default camera view | `config.view` ("Set default") |
| Quick settings (labels, stems, color, grid, zone names, rotation, panel opacity, always-on-top, auto refresh) | `config.quick` |
| Active JQL preset (last chosen) | `config.activePresetId` (saved on every switch; restored on launch — v1.2.0 keeps this across accounts) |
| Presets, axis mappings, site, email, launch at login | `config` (v1.2.0: site/email/axes move into `config.accounts[]`, §11.2) |
| API token | Keychain (service `onscreen-todo-matrix`; v1.2.0: one item per account, §11.3) |
| Hotkey | KeyboardShortcuts (UserDefaults) |
| Last fetched issues | `last-fetch.json` (instant display on launch/offline; v1.2.0: one cache file per preset, §11.5) |

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
| **PanelController** | `NSPanel` subclass that can become key (keyboard shortcuts work), `level = .normal` by default and `.floating` when always-on-top, `alphaValue` for opacity, `collectionBehavior` `.canJoinAllSpaces` + `.fullScreenAuxiliary`, default frame 1120×875 centered, frame autosave `GlancePanel2`, hotkey toggle (front-with-focus → hide, otherwise bring to front) | AppKit, KeyboardShortcuts |
| **ChartView** | Hosts the bundled chart in `WKWebView`. Swift → JS: `window.otm.render(RenderState)`. JS → Swift (`webkit.messageHandlers.otm`): `ready`, `openIssue{key}`, `refetch`, `hide`, `openSettings`, `selectPreset{id}`, `quickSetting{key,value}`, `saveDefaultView{yaw,pitch,zoom}`, `saveLastView{yaw,pitch,zoom}`, `log{level,msg}`. Navigation locked to the bundled `index.html` (`WKNavigationDelegate`); reloads and re-renders the last state if the web content process crashes; CSP `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'` | WebKit |
| **AppModel** | Single source of truth: issues, mapped tasks, selection, settings; builds `RenderState` | units below |
| **JiraClient** | Read-only Jira Cloud REST v3 with Basic auth (email + API token): `GET /rest/api/3/myself`, `GET /rest/api/3/field`, `GET /rest/api/3/priority`, `POST /rest/api/3/search/jql` (paginated via `nextPageToken`, requesting only needed `fields`) | URLSession |
| **AxisMapper** | Pure: raw field value + axis mapping → 0–1 plus a "missing" flag | — |
| **Scorer** | Pure: score, top 3, on-fire | — |
| **RefreshScheduler** | Triggers: interval timer, panel focus (> 30s since last fetch), manual; honors back-off after 429 | injected clock |
| **ConfigStore** | JSON at `~/Library/Application Support/onscreen-todo-matrix/config.json` holding site, email, JQL presets, axis mappings, default view, quick settings, hotkey, refresh interval | FileManager |
| **IssueCache** | Last successful fetch at `…/last-fetch.json` with timestamp, used for instant launch and offline display | FileManager |
| **TokenStore** | API token in Keychain only, never in config | Security framework |

**Boundaries:** all logic (mapping, scoring, scheduling, Jira client, config) lives in a local Swift package with no UI dependency, so `swift test` runs headless. The panel and web view are thin shells. The JS chart only draws and reports user actions; it never talks to Jira.

### 5.3 Swift ↔ JS contract: `RenderState` (JSON, as built)
```json
{
  "tasks": [
    { "key": "SEC-5", "summary": "Rotate leaked Stripe API key", "status": "In Progress",
      "priority": "Highest", "due": "2026-10-12", "url": "https://acme.atlassian.net/browse/SEC-5",
      "value": 0.95, "effort": 0.10, "urgency": 1.0,
      "missing": { "value": false, "effort": false, "urgency": false },
      "score": 3.5625, "rank": 1, "fire": true, "changed": false }
  ],
  "view": { "yaw": -179.7, "pitch": 33.9, "zoom": 1 },
  "lastView": { "yaw": -150, "pitch": 30, "zoom": 1.2 },
  "settings": { "labelMode": "smart", "stemStyle": "dotted", "stemOpacity": 30, "colorMode": "rgb",
                "grid": true, "zoneNames": true, "rotation": "limited", "panelOpacity": 100,
                "alwaysOnTop": false, "refreshMinutes": 5 },
  "status": { "syncedAt": "2026-10-12T10:42:00Z", "banner": null, "truncated": null },
  "presets": [ { "id": "my-open-work", "name": "My open work" } ],
  "activePresetId": "my-open-work",
  "configured": true
}
```
(The v1.0.0 sketch used `defaultYaw`/`defaultPitch` and `quickSettingChanged`; the build uses `view.yaw/pitch/zoom` and `quickSetting` on both sides.) Absent optionals (`rank`, `due`, `priority`, `lastView`) are omitted by the encoder and treated as falsy in JS.
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
| **Effort fallback** (D29) | Original estimate empty | Only when Effort is mapped to Original estimate and the toggle "If missing, estimate from timeline" is on. Order: (1) **Time spent + Remaining estimate** when > 0; (2) **timeline window** Start field → End field (default Due date): working days (Mon–Fri, both ends inclusive, at least 1; holidays ignored) × 8 h (1 day = 8 h, Jira's default; the site's real hours/day cannot be read through the read-only API). Skipped for Epics. Start or End missing, or End before Start → still `missing` (hollow). The auto range uses real estimates only, so a derived value above the range is clamped to the top; when fewer than 2 real estimates exist (or min = max) derived values join the range. **Effort unit** (setting: Hours / Days) is how derived values are shown (`≈ 56 h` / `≈ 7 d`) |

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
| Manual refresh while another is in flight | Coalesced: the manual request re-runs right after the in-flight fetch finishes (so a preset switch never shows the old preset's data under the new name) |
| Non-finite numbers from the bridge or Jira | Ignored (`NaN`/`inf` never reach config or the render state) |
| Web view navigated away / content process crash | Navigation blocked; crash → reload + re-render last state |
| Stale error banner after fixing settings | Cleared on config/token change; re-set by the next refresh if still failing |

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
- SwiftPM package (no Xcode project): library `OTMCore` + executable `OnscreenTodoMatrix`; chart built by esbuild and bundled as app resources (no CDN, no network).
- `./scripts/build-app.sh` → runs all tests, builds `build/Glance.app` (bundle id `io.github.luatnd.glance`, LSUIElement, ad-hoc signed; fails if the KeyboardShortcuts resource bundle is missing).
- `./scripts/build-dmg.sh` → `build/Glance-<version>.dmg` (Glance.app + Applications shortcut, UDZO, verified).
- Ad-hoc signed: opens normally on the Mac that built it; on another Mac use System Settings → Privacy & Security → Open Anyway (or remove the quarantine attribute).
- Later: Developer ID signing + notarization, Homebrew cask.

---

## 11. Multiple Jira accounts (v1.2.0)

### 11.1 Requirements (from the user, 2026-10-13)
1. Support several Jira Cloud accounts at different sites — e.g. a **personal** site and a **company** site.
2. Each JQL preset belongs to one account: besides "My open work" (personal) the user has e.g. "My company work" (company), etc.
3. **Remember the last chosen preset** and load it on launch.
4. Good UX for adding a preset: a **"+ New preset…"** item right at the bottom of the preset list.

### 11.2 Data model
```swift
struct JiraAccount: Codable, Identifiable {
    var id: String          // stable UUID string; migrated account uses "default"
    var name: String        // user label, e.g. "Personal", "Company"
    var site: String        // "acme.atlassian.net" (normalized like v1.1 AppConfig.site)
    var email: String
    var axes: AxesConfig    // axis mappings are per account (custom field ids differ per site)
}
struct JQLPreset: Codable, Identifiable {
    var id: String; var name: String; var jql: String
    var accountId: String   // NEW — the account this preset queries
}
struct AppConfig: Codable {
    var accounts: [JiraAccount]          // NEW (replaces top-level site/email/axes)
    var presets: [JQLPreset]
    var activePresetId: String           // last chosen preset (already persisted in v1.1)
    var view: ViewDefaults; var lastView: ViewDefaults?
    var quick: QuickSettings; var launchAtLogin: Bool
}
```
- The **active account** is always the account of the active preset — there is no separate "current account" setting.
- A preset whose `accountId` no longer exists is shown as "⚠ account missing" and cannot be activated until reassigned.
- Account names must be non-empty and unique (case-insensitive); preset names must be unique **within an account**.

### 11.3 Tokens
- One Keychain generic-password item per account: service `onscreen-todo-matrix`, account `jira-api-token:<accountId>`.
- Deleting an account deletes its Keychain item (after confirmation).
- `TokenStore` becomes keyed: `read(accountId)`, `write(_:accountId)`, `delete(accountId)`; the in-memory fake is keyed the same way.

### 11.4 Migration from v1.1 config (must not lose the user's setup)
The user's real v1.1 `config.json` has top-level `site`, `email`, `axes` and presets without `accountId`, and a Keychain item with account `jira-api-token`.
On load, if `accounts` is absent:
1. Copy the file to `config.v1.json` (backup, kept).
2. Create account `{id: "default", name: "Personal" (renameable in the Accounts tab), site, email, axes}`; if `site` is empty, create no account (fresh setup).
3. Set every preset's `accountId = "default"`.
4. Copy the Keychain token from `jira-api-token` to `jira-api-token:default`; delete the legacy item only after the copy is verified.
5. Save the config in the new format.
Decoding is tolerant: unknown/legacy keys are read via a `LegacyAppConfigV1` struct; all new keys are optional on decode so a partially written file never counts as corrupt. A test uses a fixture copied from the user's real v1.1 config shape (with fake site/email).

### 11.5 Fetching, caching and switching presets
- A refresh queries **only the active preset**: its account's site + token, its JQL, and its account's axis mappings (fields requested = summary, status, priority, duedate + that account's mapped fields).
- Issue URLs use the active preset's account site.
- **Cache per preset**: `cache/<presetId>.json` (issues + fetchedAt + accountId). Switching presets renders that preset's cached issues **instantly** (with its own "synced Xm ago"), then refreshes. Migration moves `last-fetch.json` to `cache/<activePresetId>.json`.
- Switching presets resumes the scheduler (a 401 pause on the company account must not block the personal one). The coalesced manual refresh (v1.1) guarantees the new preset's data, never the old one's, ends up on screen.
- `selectPreset` persists `activePresetId` immediately → the last chosen preset is restored on launch (requirement 3).
- Shortcuts: **⌘1…⌘9** activate the 1st…9th preset in menu order.

### 11.6 Panel: preset menu (replaces the native `<select>`)
```
[● Personal · My open work ▾]                  ← button in the top bar (account colour dot + names)
┌───────────────────────────────┐
│ PERSONAL                      │  account header (colour dot, small caps)
│ ✓ My open work          ⌘1    │
│   Due this week         ⌘2    │
│ COMPANY                       │
│   My company work       ⌘3    │
│   Team sprint           ⌘4    │
│───────────────────────────────│
│ + New preset…                 │  always last; also shown when there are no presets
│ ⚙ Manage presets…             │
└───────────────────────────────┘
```
- Opened by clicking the button or **P**; ↑/↓ move, Enter selects, Esc closes, typing filters by name.
- Each account gets a stable colour (from a fixed 6-colour palette by account order); the dot is also shown in the button, so it's clear at a glance whether the chart shows personal or company work.
- A preset whose account has a sign-in error shows a small ⚠ next to its name.
- **"+ New preset…"** posts `newPreset {accountId: <active preset's account>}` → Swift opens Settings directly on the **New preset** sheet (§11.7) with that account pre-selected.
- **"Manage presets…"** posts `openSettings {tab: "presets"}`.

### 11.7 Settings window changes
- **Accounts** tab (replaces Connection): list of accounts (colour dot, name, site, status "Connected as …" / error). **+ Add account** opens a form: name, site, email, API token, **Save & Test**. Edit / Remove (Remove asks for confirmation, removes its presets and its Keychain item).
- **Presets** tab (replaces Filters): presets grouped by account; each group has **+ New preset**; each preset row: name, JQL, Test (count), Make active, Delete. Drag to reorder within the list (order = menu order = ⌘1…⌘9).
- **New preset sheet**: Account picker (default from the caller), Name, JQL with **template chips** — "My open work" (`assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC`), "Due this week" (`assignee = currentUser() AND due <= endOfWeek() AND statusCategory != Done`), "Reported by me" (`reporter = currentUser() AND statusCategory != Done`), "Unassigned in project…" (`project = <KEY> AND assignee is EMPTY AND statusCategory != Done`) — and a live **Test** showing the match count or Jira's error. **Create & show** saves the preset, makes it active, closes Settings and refreshes. Save is disabled while the name is empty/duplicate or the last Test failed with a JQL error.
- **Axes** tab: account picker at the top; mappings edited per account (fields/priorities loaded from that account's site).
- **First-run wizard**: 1. Add first account → 2. Presets (pre-filled "My open work" for that account) → 3. Axes for that account. Adding a second account later re-uses the same Account form and then offers "Map axes for <account>" (axes pre-filled by `DefaultMappings.suggest`).
- `isConfigured` = at least one account with a token and complete axes, and an active preset whose account is configured.

### 11.8 Swift ↔ JS contract additions
```json
{
  "accounts": [ { "id": "default", "name": "Personal", "color": "#3b82f6", "error": false },
                { "id": "c1f…", "name": "Company", "color": "#f59e0b", "error": true } ],
  "presets": [ { "id": "my-open-work", "name": "My open work", "accountId": "default" },
               { "id": "p2", "name": "My company work", "accountId": "c1f…" } ],
  "activePresetId": "my-open-work"
}
```
New JS → Swift messages: `newPreset {accountId}`, `openSettings {tab?}` (tab: `accounts` | `presets` | `axes`). `selectPreset {id}` is unchanged. The shared fixture gains `accounts` and `presets[].accountId`; both test suites validate them.

### 11.8.1 Mapped field names on the axes (user request 2026-10-13)
- Each axis label in the chart shows the Jira field(s) it is mapped to: `↑ Urgency (Priority)`, `Value (Business Value)`, `← Less effort (Story Points)`; an unmapped axis shows `(not mapped)`.
- Field display names come from the active account's field list (`JiraField.name`) and are stored with the mapping (`fieldName`) when chosen in Settings, so labels work offline; fallback = field id.
- `RenderState.axisLabels: {value?, effort?, urgency?}` (strings). The label helper accepts a list of names joined with " + " (e.g. "Priority + Due Date") so a future multi-field axis needs no format change; multi-field axes themselves stay out of scope.

### 11.9 Out of scope for v1.2.0
- A combined "All accounts" chart mixing issues from several sites in one view (would need per-account axis normalisation and per-task account badges). Possible later as a special preset type.
- Per-preset axis overrides (axes are per account).
- OAuth / SSO sign-in (API tokens only).

### 11.10 Errors (additions to §7)
| Situation | Behaviour |
|---|---|
| Active account 401/403 | Banner "Jira sign-in failed (Company) · Open settings" → opens Accounts tab on that account; ⚠ on that account's presets in the menu |
| Preset's account deleted | Preset shown with "⚠ account missing"; selecting it opens the Presets tab to reassign |
| Migration failure (config or Keychain copy) | Keep `config.v1.json`, keep the legacy Keychain item, show "Could not migrate settings · Open settings"; never leave the user without their old setup |
| Account has no complete axes | Chart shows "Map axes for <account> to see this preset" with an Open settings button |

### 11.11 Testing (additions to §8)
| Layer | Tests |
|---|---|
| Migration | Real-shape v1.1 config → accounts[default] + presets.accountId + axes moved; `config.v1.json` written; Keychain copy via fake keyed TokenStore; idempotent on second load; empty-site config → no account |
| Keyed TokenStore | read/write/delete per account; legacy item untouched until copy verified |
| AppModel | refresh uses active preset's account site/token/axes; switching preset shows that preset's cache instantly and refetches; activePresetId persisted and restored; 401 on one account doesn't pause after switching to another |
| Per-preset cache | save/load by preset id; legacy `last-fetch.json` migrated |
| JS | preset menu grouping/ordering, keyboard nav, filter, ⌘1…⌘9 mapping, "+ New preset…" posts `newPreset` with the active account; contract fixture with accounts |
| Manual | add a second account; create "My company work" from "+ New preset…"; switch with ⌘1/⌘2; quit/relaunch keeps the last preset |

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
| D20 | **Multiple Jira accounts, one account per preset** | Single account (v1.1); account chosen globally; presets spanning accounts | A preset can't mix sites | User has personal + company Jira; a preset maps naturally to one site's JQL |
| D21 | **Axis mappings per account** | Global mappings (v1.1); per preset | More setup when adding an account (mitigated by DefaultMappings.suggest) | Custom field ids (e.g. Value field `customfield_10110`) differ per site, so one global mapping cannot work |
| D22 | **Active account = account of the active preset** | Separate account switcher | — | One switch (the preset menu) instead of two; matches how the user thinks ("My company work") |
| D23 | **Custom preset menu with account groups + "+ New preset…" / "Manage presets…" at the bottom** | Native `<select>` with a "+ New preset" option | More JS (menu, keyboard nav) | User asked for a "+ new preset" right at the bottom of the list; native select can't group nicely, show colour dots or shortcuts |
| D24 | **New preset is created in a Settings sheet with JQL templates + live Test** | Inline form inside the panel | Opens a second window briefly | JQL needs room, validation and the account picker; templates make the common cases one click |
| D25 | **Cache per preset** | One shared `last-fetch.json` | More files | Instant, correct data when switching between personal and company presets; no stale cross-account flashes |
| D26 | **Migrate v1.1 config + token automatically, with backup** | Ask the user to set up again | Migration code + tests | User already has a working setup; never lose it (AGENTS knowledge-preservation spirit) |
| D27 | **Coincident tasks: stack marker (coin-stack look, normal size) + multi-line label + click-to-cycle** | Bigger dot by count (sqrt, capped 1.4×); always-on fan-out ring; spiderfy on click (Leaflet style); data jitter / stacking along the stem; pop-up member list instead of click-to-cycle | Bigger dot: shows workload mass, but size already means "nearer" (perspective) and reads as importance, and covers neighbours. Fan-out: every dot clickable, but draws false positions and the large `unset` group becomes a blob. Spiderfy: spatial, keeps colours, but leader lines + re-layout while rotating + extra hit-testing. Jitter: misstates data (height *is* urgency). Pop-up list: richer, but needs a focus-managed popover. Multi-line labels are taller, so Smart mode may hide a nearby label | Collisions are structural (discrete Jira fields; all missing-field tasks share the default spot). The stack keeps true positions and dot-size meaning, says "N here" at a glance, and reaches every member by mouse and keyboard. User chose the coin-stack look over size growth and wanted both titles shown. Grouping by data keeps stacks stable during rotation. Spiderfy kept as a later option |
| D28 | **3D cones at the axis tips** | Flat screen-space triangles; text arrows only (as before) | 3D cones cost a convex hull per axis per frame (3 × 17 points) and make the fit ~6% of an axis length smaller | User request: show each axis' direction from O. A projected cone stays correct from any angle (a circle when the axis points at the viewer), where a flat triangle collapses; Effort's cone follows its line from O toward less effort, matching the label and the green = ease color |
| D29 | **Effort fallback: logged time, then the Start → Due timeline window, in a selectable unit (hours / days)** | Calendar days × 8 h; calendar days × 24 h; story-point conversion; Created date as start; apply to every issue type; hours-per-day as a setting; a plain solid dot without a marker; derive for any number field | Calendar days count weekends as work; 24 h is absurd; a window is an upper bound (a 2-week window may hold 4 h of work); Created measures age, not effort; "today" as start drifts daily; an Epic's window covers its children; story points would need an invented points-per-hour rate; hours-per-day cannot be read from Jira (read-only endpoint list) and the user clarified that "hour/day" is the **unit** to show, not a rate | Original estimate stays the primary signal. Working days × 8 h (inclusive, ≥ 1) makes the window comparable to estimates; range from real estimates keeps one long window from squashing the scale; a dashed ring separates estimated / derived / missing without overstating confidence; unit picker (Hours / Days) controls display; 1 day = 8 h is a constant (Jira default), configurable later if needed |

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
