# Glance Lite (iPhone PWA) Implementation Plan

> Executed natively in one session (user asked for a non-stop run). Steps are TDD: failing test → implement → pass → commit.

**Goal:** Read-only iPhone PWA that shows the Glance canvas standalone, imported from the Mac by an encrypted link.
**Architecture:** `phone/` holds a vanilla-JS PWA that reuses `chart/src` unchanged by installing a `window.webkit.messageHandlers.otm` shim before the chart loads; JS ports of AxisMapper/Scorer/RenderStateBuilder build the same RenderState the Swift app sends. A Cloudflare Worker serves the PWA and proxies GET-only Jira reads. The Mac adds `PhoneExport` (AES-GCM + PBKDF2, QR).
**Tech Stack:** JS (esbuild, vitest, WebCrypto, IndexedDB, service worker), Cloudflare Workers (static assets), Swift (CryptoKit, CommonCrypto, CoreImage).
**Spec:** specs/arch-20261016-onscreen-todo-matrix-design-v1.4.0.md

## Global Constraints
- Phone never receives the Mac API token. Token only in IndexedDB, encrypted with a non-extractable AES-GCM CryptoKey.
- Proxy: GET only, host = `JIRA_HOST` env var, paths limited to `/rest/api/3/{search/jql,issue/*,field,myself,priority/search}`; no logs; same-origin only.
- CSP: `default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'`.
- Jira search on the phone uses `GET /rest/api/3/search/jql` (the Mac uses POST; the approximate-count POST is dropped, so no "N of M" on the phone).
- Link: v1 | salt(16) | iv(12) | ciphertext+tag, base64url, in `#fragment`; PBKDF2-SHA256 600000 iterations; plaintext JSON has `exp` (epoch s, now+600).
- Code: 8 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, shown as `XXXX-XXXX`.

## Review Focus
- Wrong/lowercase/dashed code, truncated or tampered link, expired link → clear error, nothing stored.
- Token revoked (401/403) → "token rejected" screen with re-enter option; cached snapshot kept, marked stale.
- Offline start → cached snapshot shown, marked stale.
- Issue with no values on an axis → `missingDefault` and `missing` flag (parity with Swift).
- Non-Jira host / POST / other path through the Worker → 403/405.
- Fragment must be removed from URL/history after import; no secrets in the console.

## File map
- `phone/src/crypto.js` seal/open (link) · `phone/src/vault.js` IndexedDB device-key storage · `phone/src/mapper.js` AxisMapper+Scorer+state builder · `phone/src/jira.js` fetch client · `phone/src/shim.js` native bridge · `phone/src/entry.js` glue · `phone/public/` index.html, style, manifest, sw.js, icons · `phone/worker/index.js` + `wrangler.toml` · `phone/test/*` · Swift `Sources/OTMCore/PhoneExport.swift`, Settings UI button, `Tests/OTMCoreTests/PhoneExportTests.swift` · `fixtures/parity-*.json`.

### Task 1: crypto.js (link seal/open)
Produces: `seal(obj, code, {now, ttl, iterations}) → base64url`, `open(blob, code, {now, iterations}) → obj`, `makeCode()`, `normalizeCode(s)`; errors `BadCode`, `Expired`, `Malformed`.
- [ ] Tests: round-trip; wrong code → BadCode; flipped byte → BadCode; expired → Expired; garbage → Malformed; code normalisation (lowercase, dash, spaces).
- [ ] Implement with WebCrypto; commit.

### Task 2: mapper.js + parity
Produces: `mapIssues(issues, axes, site, today) → MappedTask[]`, `rank(tasks)`, `buildState({issues, config, presetId, status, ...}) → RenderState` (passes `validateState`).
- [ ] Swift test writes nothing; add `fixtures/parity-input.json` (issues, axes covering option/number/date/derived effort, today=2026-10-14) and Swift `ParityTests` asserting mapped+ranked output equals `fixtures/parity-expected.json` (generated once by Swift, committed).
- [ ] JS test loads the same two files and asserts deep equality (1e-9). Implement port; commit.

### Task 3: jira.js
Produces: `createJira({base='', token, email, fetch}) → {myself(), fields(), search(jql, fieldIds, cap)}`; maps 401/403 → `Unauthorized`, 429 → `RateLimited`, network → `Network`.
- [ ] Tests with fake fetch: Basic auth header, `/jira/...` URLs, paging via `nextPageToken`, cap, error mapping. Implement; commit.

### Task 4: Worker proxy
- [ ] Tests (vitest, call `worker.fetch`): allowed GET → forwards to `https://$JIRA_HOST` with Authorization passed through and no cookies; POST 405; unknown path 403; path traversal (`..`, `%2e%2e`) 403; foreign `Origin` 403; response strips `set-cookie`, adds `Cache-Control: no-store`; static fallthrough via `env.ASSETS`.
- [ ] Implement `phone/worker/index.js`, `wrangler.toml` (`[assets]`, `run_worker_first=["/jira/*"]`, headers file for CSP/HSTS); commit.

### Task 5: vault.js
Produces: `saveSession({config, token, email}) / loadSession() / wipe()`; snapshot cache `saveSnapshot/loadSnapshot`.
- [ ] Tests with `fake-indexeddb`: stored values are not plaintext; key is non-extractable; wipe clears everything. Commit.

### Task 6: PWA shell
- [ ] `shim.js` (bridge: ready, quickSetting, selectPreset, refetch, saveLastView, saveDefaultView, openIssue, openSettings→menu, log, hide); touch→mouse/wheel mapping for rotate/pinch/tap; `entry.js` flow: fragment → code prompt → token prompt → fetch → render; pull-to-refresh button; stale banner; "Forget this phone"; manifest, icons, service worker (cache shell only, never `/jira/*`); `index.html` with CSP meta.
- [ ] Tests for flow logic that is pure (state machine of import: idle→needCode→needToken→ready, errors). Build script `npm run build`; commit.

### Task 7: Mac export
- [ ] `PhoneExport.seal(config, code, now)` in OTMCore (CryptoKit AES.GCM, CommonCrypto PBKDF2, same layout); Swift test decrypts a vector produced by JS (`fixtures/link-vector.json`: code, now, blob) and round-trips; config JSON strips secrets (accounts have no token; nothing from Keychain).
- [ ] Settings → General "Send to phone…" sheet: choose the PWA URL (saved in config, default empty → asks once), shows QR (CIQRCodeGenerator) + code, 10-min countdown, Close wipes. Commit.

### Task 8: Docs, deploy, verify
- [ ] README: setup (wrangler deploy, JIRA_HOST, phone token), security notes; manual iPhone checklist `docs/phone-checklist.md`; mark spec v1.4.0 "as built".
- [ ] Local end-to-end with `wrangler dev` + headless browser against a fake Jira; deploy (needs user's `wrangler login`).
- [ ] PR, merge.
