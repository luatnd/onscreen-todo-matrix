# onscreen-todo-matrix

An open-source macOS floating panel that shows your Jira Cloud issues as a 3D priority space (Value × Effort × Urgency). Press ⌥Space for a 2-second look at what to do next, what's on fire, and the overall shape of your workload.

- Idea: [idea-v1.0.0.md](idea-v1.0.0.md)
- Feature (non-technical): [features/product-20261012-3d-priority-panel.md](features/product-20261012-3d-priority-panel.md)
- Design spec (technical): [specs/arch-20261012-onscreen-todo-matrix-design.md](specs/arch-20261012-onscreen-todo-matrix-design.md)
- Interactive prototype: [prototype/panel-prototype.html](prototype/panel-prototype.html)

# TODO
- [x] Brainstorm: concept, chart design, window form, panel layout, labels, interactions, quick settings
- [x] Tech stack decision (Swift + WKWebView chart)
- [x] Design spec v1.0.0
- [ ] Review written spec
- [x] Implementation plan (writing-plans)
- [x] Implement v1 (TDD + code review per phase)
- [ ] Later: combine multiple fields per axis; editable scoring; signed + notarized release; Homebrew cask

# Build & run
Requirements: macOS 14+, Xcode 26 (Swift 6.2 toolchain), Node 22.

~~~bash
cd productivity/onscreen-todo-matrix/src
./scripts/build-app.sh
open "build/Onscreen Todo Matrix.app"
~~~

Development: `swift test` (core logic), `cd chart && npm test` (chart), `swift run OnscreenTodoMatrix` (runs with `chart/dist` from the source tree; run `npm run build` in `chart/` first). Manual window checks: [src/docs/manual-checklist.md](src/docs/manual-checklist.md).
