# Glance v1.5.0 — epics, parent-aware search, discoverable search (+ spec catch-up)

Status: approved design (2026-10-18). Builds on v1.4.0. Applies to the Mac app and Glance Lite (same chart code; Swift ↔ JS parity).

## Catch-up: shipped without a spec
- **D32 Zone numbers.** Floor zone labels read `1  QUICK WINS`, `2  MAJOR PROJECTS`, `3  FILL-INS`, `4  THANKLESS` (do-first order). (Shipped in 1.3.2; that spec file never reached this repo.)
- **D33 Menu hotkey hint.** The menu-bar item "Show / Hide Panel" shows the user's global shortcut (default ⌥Space) and follows changes (`NSMenuItem.setShortcut(for: .togglePanel)`).
- **D34 Crash guards.** Accounts form binding never force-unwraps a nil draft; KeyboardShortcuts is vendored without a resource bundle (English strings inlined) and `build-app.sh` fails if any `.bundle` lands at the app root, then runs a launch self-test (`GLANCE_SELFTEST=1`).
- **D35 Lite top bar.** On the phone the bar is one 48px row: preset pill (ellipsized) left; small sync text (hidden < 360px); ⟳ ◐ ⚙ as 44px targets right; safe-area padding. Preset menu nearly full width with 44px rows; quick settings full width.

## D36 Parent of each issue
- Both clients request Jira field `parent` with every search (in addition to today's fields).
- Mapped/render task gains optional `parent: { key: String, summary: String }` (from `fields.parent.key` and `fields.parent.fields.summary`; absent when the issue has no parent or the field is missing).
- Mapped task gains `isEpic: Bool` = `issuetype.name == "Epic"` or `issuetype.hierarchyLevel >= 1`. `issuetype` is always requested.
- `RenderTask` JSON adds `parent` (optional object). `isEpic` is not sent to the chart (filtered before render).

## D37 Hide an epic covered by its children
- After mapping, before ranking: drop every epic E for which at least one other issue in the same result has `parent.key == E.key`.
- Dropped epics take no rank, are not in "Next", not in search, not on the canvas.
- An epic with no matching child stays.
- Only direct children count (one level). No setting (always on).
- Same function in Swift (`AxisMapper`/`RenderStateBuilder` path used by AppModel) and JS (`phone/src/mapper.js`); parity fixture gets a case: epic with a child (hidden), epic without child (kept), child of an epic not in the result (kept, parent still shown).

## D38 Parent-aware search
- Search text matches (case-insensitive substring) any of: key, summary, parent key, parent summary.
- Card shows the parent above the title, muted: `Clavis project deal ›` (escaped; omitted when no parent).
- Tooltip rows unchanged.

## D39 Discoverable search
- A 🔍 button in the top bar (before ⟳) on Mac and phone toggles the search field.
- Field: placeholder "Search title, parent or key…", a clear ✕ inside/next to it, Esc closes (as today), Enter selects the best match (as today).
- While a query is active the sync text area shows `N matches` (0 → `No matches`).
- Shortcuts: ⌘F (existing) and `/` open search (when no text field is focused).
- Phone: the search field takes the full bar width while open (pill and other buttons hidden), with ✕ to close; the existing `#q { display:none }` override is replaced.

## Testing
- Parity fixture + Swift and JS tests for D36/D37 (epic hidden/kept, parent extracted, missing parent ok).
- Chart unit tests for the search matcher (parent summary match, key match, no false match) — extract it to a small pure function (e.g. `search.js`) so it is testable.
- Manual: Mac panel and Lite at 393×852: 🔍 opens, typing "Clavis" finds the child task, count shows, ✕/Esc clear.
