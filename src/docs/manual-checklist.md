# Manual checklist (window behavior; not covered by unit tests)

Run after `./scripts/build-app.sh` and `open "build/Glance.app"`.

- [ ] Status-bar icon appears; no Dock icon; menu has Show / Hide Panel, Refresh Now, Settings…, Quit.
- [ ] First launch without config opens Settings with the 1-2-3 setup header.
- [ ] ⌥Space toggles the panel from another app (e.g. while typing in an editor); keyboard focus lands in the panel.
- [ ] Tab / ⇧Tab cycle tasks; ⌘O opens the issue in the default browser; Esc deselects then hides.
- [ ] ⌘R refetches; returning focus to the panel after >30 s refetches (watch "synced …").
- [ ] ⌥Space brings the panel to the front with focus; clicking another app puts that app on top of the panel; ⌥Space again (panel in front) hides it; Quick settings → Always on top On keeps it above other apps.
- [ ] Panel appears on every Space and over a full-screen app.
- [ ] Panel size/position persist across relaunch.
- [ ] Settings → Shortcuts: recording a new shortcut works and ⌥Space stops working.
- [ ] Settings → General → Launch at login toggles without error (ad-hoc signed builds may show an error: expected; it must be shown, not crash).
- [ ] Keychain: tokens survive relaunch; `security find-generic-password -s onscreen-todo-matrix -a "jira-api-token:default"` finds the Personal token.
- [ ] Offline (Wi-Fi off) → banner "Offline · showing data from HH:mm", dots still shown.
- [ ] Paste the API token with ⌘V in Settings → Accounts → Edit (also ⌘A / ⌘C / ⌘Z work in text fields).
- [ ] First run ends with the panel showing real issues after closing Settings / pressing Done.
- [ ] Dragging a file onto the panel does not navigate away.
- [ ] First launch opens the panel at about 1120×875 (75% larger than before), centered; later launches keep the size/position you last left it at.
- [ ] Rotate/zoom away from the default view → a 'Reset view' pill appears top-right; clicking it or pressing R animates back; double-click on empty space does nothing; double-click on a task dot opens it in Jira and the pill fades out.
- [ ] Rotate/zoom, quit, relaunch → the chart opens at the same angle/zoom; Reset view returns to the saved default.

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
