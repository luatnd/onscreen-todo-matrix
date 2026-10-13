# Manual checklist (window behavior; not covered by unit tests)

Run after `./scripts/build-app.sh` and `open "build/Glance.app"`.

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
- [ ] Paste the API token with ⌘V in Settings → Connect (also ⌘A / ⌘C / ⌘Z work in text fields).
- [ ] First run ends with the panel showing real issues after closing Settings / pressing Done.
- [ ] Dragging a file onto the panel does not navigate away.
- [ ] First launch opens the panel at about 75% of the screen, centered.
