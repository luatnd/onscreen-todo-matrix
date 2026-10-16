# Glance Lite — manual checklist (iPhone, Safari)

Needs the deployed Worker, a Mac with Glance 1.4, and a phone-only Jira API token.

1. Mac: Settings → General → Send to phone… → enter the address → QR + code appear; countdown runs; "Done" closes and the QR is gone.
2. iPhone camera → scan → Safari opens "Import settings"; the address bar shows no `#g1=…` after load.
3. Wrong code → "Wrong code."; correct code → "Phone token" screen shows your Jira email.
4. Wrong token → "Jira rejected…"; correct token → canvas appears with your issues, same colours/positions as the Mac.
5. One finger rotates; two fingers pinch-zoom; tap a dot → card; double-tap → opens the issue in Jira; "Reset view" works.
6. ◐ quick settings change labels/stems/colour; kill and reopen Safari → settings kept.
7. Preset menu switches presets; ⟳ refreshes; pull data changes in Jira show after refresh.
8. Share → Add to Home Screen → opens full-screen with the Glance icon.
9. Airplane mode → app opens with saved data and an "Offline · showing saved data" banner.
10. Revoke the phone token in Atlassian → next refresh shows "Jira sign-in failed · Open settings"; ⚙ → Replace phone token works.
11. ⚙ → Forget this phone → back to the empty screen; reopening needs a new link.
12. A link older than 10 minutes → "This link has expired."
