# Glance Lite (iPhone PWA) — design v1.4.0

Status: draft for review. Builds on v1.3.x.

## Goal
See the Glance canvas on an iPhone while the Mac is off. Read-only, "Lite": no iOS app, no Mac needed at runtime.

## Non-goals
Editing Jira, the full Settings window (accounts, field mapping), phone lock, push notifications, multi-user.

## Decisions
- **D40 Standalone.** The phone fetches Jira itself. Mac and phone share nothing after import.
- **D41 One Cloudflare Worker** (user's own account) serves the PWA files and `/jira/*`. Same origin: no CORS, simple CSP.
- **D42 Import by link.** Mac "Send to phone…" shows a QR and an 8-char one-time code. Payload (accounts without secrets, axes, presets, quick, view) is in the URL `#fragment` (never sent to a server), encrypted with AES-GCM; key = PBKDF2-SHA256 (600k iterations) of the code and a random salt. Blob carries an expiry (10 min); the PWA rejects expired blobs and clears the fragment on load.
- **D43 Own token.** The Mac token is never exported. User creates a separate read-only Atlassian API token for the phone and pastes it once. Stored in IndexedDB, encrypted with a non-extractable WebCrypto key. Revoke in Atlassian to cut the phone off.
- **D44 Locked proxy.** Worker forwards only `GET` to `https://$JIRA_HOST` (env var) on an allowlist of read paths (search, issue, field, myself). No logging, no body storage, no cookies; rejects other methods, hosts, and cross-origin callers.
- **D45 Hardening.** CSP `default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:`; no third-party scripts/CDNs; `Referrer-Policy: no-referrer`; HSTS; "Forget this phone" wipes IndexedDB/Cache/SW.
- **D46 Reuse the chart.** Same `chart/` code; a `platform` shim replaces the WKWebView bridge: quick settings and presets persist to localStorage instead of posting to Swift. Scoring/colours ported to JS (single source of truth for the phone); a parity test runs the same fixtures through Swift and JS.
- **D47 Offline.** Last snapshot cached and shown marked "stale"; errors: wrong code, expired link, 401 (token revoked), network.
- **D48 No phone lock** (user decision). Residual risk: unlocked phone shows issue titles; token is read-only.

## Threat notes
Link alone is useless without the code; code alone is useless without the link. The Worker sees the token in transit (self-hosted by the user). A leaked phone token is read-only and independently revocable.

## Testing
Crypto round-trip, tampered/expired/wrong-code blobs, Worker allowlist (POST, other host, other path rejected), Swift↔JS scoring parity, manual iPhone checklist.

## Layout
`phone/` (PWA + Worker), Swift: `PhoneExport.swift` + Settings button.
