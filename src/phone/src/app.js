// Glance Lite app logic. All I/O is injected so the flow is unit-testable (see test/app.test.js).
import { open as openLink, BadCode, Expired, Malformed } from './crypto.js';
import { Unauthorized, NetworkError, RateLimited } from './jira.js';
import { mapIssues, buildState, fieldIds, todayNumber } from './mapper.js';

export const ISSUE_CAP = 500;
const isStr = (v) => typeof v === 'string';
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

export const parseHash = (hash) => { const m = /^#g1=([A-Za-z0-9_-]+)$/.exec(hash || ''); return m ? m[1] : null; };

// Same rules as Swift QuickSettings.applying; the phone has no always-on-top / panel opacity.
export function applyQuick(q, key, value) {
  const pick = (allowed) => (isStr(value) && allowed.includes(value) ? value : undefined);
  const r = { ...q };
  const set = (v) => { if (v !== undefined) r[key] = v; };
  switch (key) {
    case 'labelMode': set(pick(['smart', 'all', 'key', 'off'])); break;
    case 'stemStyle': set(pick(['solid', 'dotted', 'dashed', 'off'])); break;
    case 'stemOpacity': if (typeof value === 'number') r.stemOpacity = Math.min(80, Math.max(5, value)); break;
    case 'colorMode': set(pick(['rgb', 'u'])); break;
    case 'grid': case 'zoneNames': if (typeof value === 'boolean') r[key] = value; break;
    case 'rotation': set(pick(['limited', 'free'])); break;
    case 'refreshMinutes': if ([0, 1, 5, 15].includes(value)) r.refreshMinutes = value; break;
    default: break;
  }
  return r;
}

// Validates the imported payload (already authenticated by AES-GCM, but a bug on the Mac must not wedge the phone).
export function validateConfig(c) {
  if (!isObj(c) || !Array.isArray(c.accounts) || c.accounts.length !== 1 || !Array.isArray(c.presets) || !c.presets.length) throw new Malformed('bad settings');
  const a = c.accounts[0];
  if (!isObj(a) || !isStr(a.id) || !isStr(a.site) || !isStr(a.email) || !isObj(a.axes)) throw new Malformed('bad account');
  if (!/^https:\/\/[a-z0-9.-]+$/i.test(a.site)) throw new Malformed('bad site');
  for (const p of c.presets) if (!isObj(p) || !isStr(p.id) || !isStr(p.name) || !isStr(p.jql) || p.accountId !== a.id) throw new Malformed('bad preset');
  if (!isObj(c.view) || !isObj(c.quick)) throw new Malformed('bad view');
  return c;
}

export function createApp({ vault, makeJira, ui, render, openUrl, now = () => new Date() }) {
  let blob = null, session = null, tasks = [], status = {}, busy = false, prev = null;
  const day = () => todayNumber(now());

  const preset = () => session.config.presets.find((p) => p.id === session.config.activePresetId) ?? session.config.presets[0];
  const draw = (extra = {}) => {
    status = { ...status, ...extra };
    render(buildState({ tasks, previous: prev, config: session.config, status, accountErrors: status.authFailed ? [session.config.accounts[0].id] : [] }));
    prev = new Map(tasks.map((t) => [t.key, { value: t.value, effort: t.effort, urgency: t.urgency }]));
  };
  const persist = () => vault.saveItem('session', session);

  async function boot(hash) {
    blob = parseHash(hash);
    if (blob) { ui.showCode(); return 'code'; }
    session = await vault.loadItem('session');
    if (!session) { ui.showEmpty(); return 'empty'; }
    ui.hide();
    const snap = await vault.loadItem('snapshot');
    if (snap && snap.presetId === preset().id) {
      tasks = snap.tasks;
      draw({ syncedAt: snap.at, banner: 'Showing saved data · refreshing…' });
    } else draw({});
    refresh();
    return 'ready';
  }

  async function submitCode(code) {
    try {
      const cfg = validateConfig(await openLink(blob, code));
      session = { config: cfg, email: cfg.accounts[0].email, token: null };
      blob = null;
      ui.showToken(session.email);
      return 'token';
    } catch (e) {
      if (e instanceof Expired) { blob = null; ui.showCode('This link has expired. Send a new one from the Mac.', true); return 'expired'; }
      if (e instanceof Malformed) { blob = null; ui.showCode('This link is damaged. Send a new one from the Mac.', true); return 'malformed'; }
      if (e instanceof BadCode) { ui.showCode('Wrong code.'); return 'badcode'; }
      throw e;
    }
  }

  async function submitToken(token) {
    token = String(token || '').trim();
    if (!token) { ui.showToken(session.email, 'Paste the phone token.'); return 'empty'; }
    const jira = makeJira({ email: session.email, token });
    try { await jira.myself(); }
    catch (e) {
      if (e instanceof Unauthorized) { ui.showToken(session.email, 'Jira rejected this token (or email).'); return 'rejected'; }
      ui.showToken(session.email, 'Could not reach Jira. Check your connection and try again.'); return 'network';
    }
    session.token = token;
    await persist();
    await vault.saveItem('snapshot', null);
    ui.hide();
    tasks = []; prev = null; status = {};
    draw({});
    refresh();
    return 'ready';
  }

  async function refresh() {
    if (!session || !session.token || busy) return;
    busy = true;
    const p = preset();
    try {
      const jira = makeJira({ email: session.email, token: session.token });
      const r = await jira.search(p.jql, fieldIds(session.config.accounts[0].axes), ISSUE_CAP);
      tasks = mapIssues(r.issues, session.config.accounts[0].axes, session.config.accounts[0].site, day());
      const at = now().toISOString();
      draw({ syncedAt: at, banner: undefined, authFailed: false, truncated: r.truncated ? `Showing the first ${ISSUE_CAP} issues` : undefined });
      await vault.saveItem('snapshot', { presetId: p.id, tasks, at });
    } catch (e) {
      let banner = 'Refresh failed';
      if (e instanceof Unauthorized) banner = 'Jira sign-in failed · Open settings';
      else if (e instanceof NetworkError) banner = 'Offline · showing saved data';
      else if (e instanceof RateLimited) banner = 'Jira rate limit · retrying later';
      draw({ banner, authFailed: e instanceof Unauthorized });
    } finally { busy = false; }
  }

  async function handle(m) {
    if (!session || !m) return;
    const c = session.config;
    switch (m.type) {
      case 'quickSetting': c.quick = applyQuick(c.quick, m.key, m.value); await persist(); break;
      case 'saveLastView': c.lastView = { yaw: m.yaw, pitch: m.pitch, zoom: m.zoom }; await persist(); break;
      case 'saveDefaultView': c.view = { yaw: m.yaw, pitch: m.pitch, zoom: m.zoom }; await persist(); break;
      case 'selectPreset':
        if (c.presets.some((p) => p.id === m.id) && m.id !== c.activePresetId) {
          c.activePresetId = m.id; await persist(); tasks = []; prev = null; draw({ banner: undefined, syncedAt: undefined }); refresh();
        }
        break;
      case 'refetch': refresh(); break;
      case 'openSettings': ui.showSettings(); break;
      case 'openIssue': {
        const t = tasks.find((x) => x.key === m.key);
        if (t && t.url.startsWith(c.accounts[0].site + '/browse/')) openUrl(t.url);
        break;
      }
      default: break;
    }
  }

  async function forget() {
    await vault.wipe();
    session = null; tasks = []; blob = null; prev = null; status = {};
    ui.showEmpty();
  }

  function reenterToken() { if (session) ui.showToken(session.email); }

  return { boot, submitCode, submitToken, refresh, handle, forget, reenterToken, get session() { return session; } };
}
