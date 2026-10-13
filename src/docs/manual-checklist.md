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
- [ ] Keychain: token survives relaunch; `security find-generic-password -s onscreen-todo-matrix` finds the item.
- [ ] Offline (Wi-Fi off) → banner "Offline · showing data from HH:mm", dots still shown.
- [ ] Paste the API token with ⌘V in Settings → Connect (also ⌘A / ⌘C / ⌘Z work in text fields).
- [ ] First run ends with the panel showing real issues after closing Settings / pressing Done.
- [ ] Dragging a file onto the panel does not navigate away.
- [ ] First launch opens the panel at about 1120×875 (75% larger than before), centered; later launches keep the size/position you last left it at.
- [ ] Rotate/zoom away from the default view → a 'Reset view' pill appears top-right; clicking it, pressing R, or double-clicking animates back and the pill fades out.
- [ ] Rotate/zoom, quit, relaunch → the chart opens at the same angle/zoom; Reset view returns to the saved default.
- [ ] Two or more issues with identical axis values (e.g. same Priority and story points, or all missing a field) show one dot with a coin-stack outline (count badge from 3), one label listing both titles (`+N more` beyond 2), and a hover tooltip listing them; clicking the dot again cycles through them and the card shows `‹ 2 of 3 ›` (←/→ also step).
- [ ] Each axis ends in a cone pointing away from the origin (Value → high value, Effort → less effort, Urgency → up); rotate freely and look down an axis: its cone shows as a disc, never disappears or clips.
- [ ] Settings → Axes → Effort (Original estimate): turn on "If missing, estimate from timeline", pick Start field / End field / Unit (Hours or Days). An issue with no Original estimate but a Start date and Due date now shows a solid dot with a dashed ring; its card says `Effort ≈ … from timeline (…)`. An issue without dates stays hollow. Epics stay hollow.
