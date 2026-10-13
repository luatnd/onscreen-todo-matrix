# Glance — Onscreen Todo Matrix

**Glance — Onscreen Todo Matrix** (app: `Glance.app`; repo/internal name: `onscreen-todo-matrix`) is an open-source macOS floating panel that shows your Jira Cloud issues as a 3D priority space (Value × Effort × Urgency). Press ⌥Space for a 2-second look at what to do next, what's on fire, and the overall shape of your workload.

- Idea: [idea-v1.0.0.md](idea-v1.0.0.md)
- Feature (non-technical): [features/product-20261012-3d-priority-panel.md](features/product-20261012-3d-priority-panel.md)
- Design spec (technical): [specs/arch-20261012-onscreen-todo-matrix-design.md](specs/arch-20261012-onscreen-todo-matrix-design.md) (v1.0.0)
  - [v1.1.0 — as built](specs/arch-20261013-onscreen-todo-matrix-design-v1.1.0.md)
  - [v1.2.0 — multiple Jira accounts (draft)](specs/arch-20261013-onscreen-todo-matrix-design-v1.2.0.md)
- Implementation plan v1: [plans/arch-20261012-onscreen-todo-matrix-plan.md](plans/arch-20261012-onscreen-todo-matrix-plan.md)
- Interactive prototype: [prototype/panel-prototype.html](prototype/panel-prototype.html)

# TODO
- [x] Brainstorm: concept, chart design, window form, panel layout, labels, interactions, quick settings
- [x] Tech stack decision (Swift + WKWebView chart)
- [x] Design spec v1.0.0
- [x] Review written spec
- [x] Implementation plan (writing-plans)
- [x] Implement v1 (TDD + code review per phase)
- [x] Post-v1 requests: Glance brand, DMG, reset pill, panel size, not always-on-top, last view, double-click opens Jira (spec v1.1.0)
- [ ] v1.2.0: multiple Jira accounts, per-account presets/axes, "+ New preset…" menu — spec review → plan → implement
- [ ] Later: combine multiple fields per axis; editable scoring; signed + notarized release; Homebrew cask

# Build & run
Requirements: macOS 14+, Xcode 26 (Swift 6.2 toolchain), Node 22.

~~~bash
cd productivity/onscreen-todo-matrix/src
./scripts/build-app.sh
open "build/Glance.app"
~~~

Installer: `./scripts/build-dmg.sh` → `build/Glance-1.0.0.dmg`; open it and drag Glance to Applications.

The build is ad-hoc signed: a DMG built on your own Mac opens normally; on another Mac macOS blocks it the first time → System Settings → Privacy & Security → "Open Anyway" (or `xattr -dr com.apple.quarantine /Applications/Glance.app`). Notarized builds need an Apple Developer ID (future).

Development: `swift test` (core logic), `cd chart && npm test` (chart), `swift run OnscreenTodoMatrix` (runs with `chart/dist` from the source tree; run `npm run build` in `chart/` first). Manual window checks: [src/docs/manual-checklist.md](src/docs/manual-checklist.md).
