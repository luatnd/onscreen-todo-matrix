import 'fake-indexeddb/auto';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as vault from '../src/vault.js';
import { seal } from '../src/crypto.js';
import { createApp, applyQuick, parseHash, validateConfig } from '../src/app.js';
import { Unauthorized, NetworkError } from '../src/jira.js';
import { validateState } from '../../chart/src/state.js';

const axes = {
  value: { mapping: { option: { fieldId: 'customfield_1', levels: { Big: 5, Small: 0 } } }, missingDefault: 0.5 },
  effort: { mapping: { number: { fieldId: 'timeoriginalestimate', invert: false } }, missingDefault: 0.5 },
  urgency: { mapping: { option: { fieldId: 'priority', levels: { High: 3.75, Low: 1.25 } } }, missingDefault: 0.5 },
};
const config = () => ({ accounts: [{ id: 'a', name: 'Acme', site: 'https://acme.atlassian.net', email: 'me@x.io', axes }],
  presets: [{ id: 'p1', name: 'Mine', jql: 'assignee = currentUser()', accountId: 'a' }, { id: 'p2', name: 'Other', jql: 'x', accountId: 'a' }],
  activePresetId: 'p1', view: { yaw: -179.7, pitch: 33.9, zoom: 1 }, quick: { labelMode: 'smart', stemStyle: 'dotted', stemOpacity: 30, colorMode: 'rgb', grid: true, zoneNames: true, rotation: 'limited', refreshMinutes: 5 } });
const issues = [{ key: 'A-1', fields: { summary: 'One', status: { name: 'To Do' }, priority: { name: 'High' }, customfield_1: { name: 'Big' }, timeoriginalestimate: 3600 } }];

function setup(jiraImpl) {
  const ui = { showCode: vi.fn(), showToken: vi.fn(), showEmpty: vi.fn(), showSettings: vi.fn(), hide: vi.fn() };
  const rendered = [];
  const jira = jiraImpl ?? { myself: async () => ({}), search: async () => ({ issues, truncated: false }) };
  const app = createApp({ vault, makeJira: () => jira, ui, render: (s) => rendered.push(s), openUrl: vi.fn(), now: () => new Date('2026-10-14T05:00:00Z') });
  return { app, ui, rendered, jira };
}
const IT = 600000;
beforeEach(async () => { await vault.wipe(); });

describe('import flow', () => {
  it('fragment -> code -> token -> render; token is stored encrypted, fragment parse only accepts #g1=', async () => {
    expect(parseHash('#g1=abc_-')).toBe('abc_-');
    expect(parseHash('#x=1')).toBeNull();
    const blob = await seal(config(), 'ABCDEFGH', { iterations: IT });
    const { app, ui, rendered } = setup();
    expect(await app.boot('#g1=' + blob)).toBe('code');
    expect(await app.submitCode('abcd-efgh')).toBe('token');
    expect(ui.showToken).toHaveBeenCalledWith('me@x.io');
    expect(await app.submitToken('  SECRET  ')).toBe('ready');
    await vi.waitFor(() => expect(rendered.at(-1).tasks).toHaveLength(1));
    for (const s of rendered) expect(validateState(JSON.parse(JSON.stringify(s)))).toEqual([]);
    expect(app.session.token).toBe('SECRET');
    expect(rendered.at(-1).status.syncedAt).toBe('2026-10-14T05:00:00.000Z');
    const again = setup();
    expect(await again.app.boot('')).toBe('ready');            // survives reload
    expect(again.app.session.token).toBe('SECRET');
  });
  it('wrong code keeps the link; expired/damaged links are dropped', async () => {
    const blob = await seal(config(), 'ABCDEFGH', { iterations: IT });
    const a = setup(); await a.app.boot('#g1=' + blob);
    expect(await a.app.submitCode('ZZZZZZZZ')).toBe('badcode');
    expect(await a.app.submitCode('ABCDEFGH')).toBe('token');
    const old = await seal(config(), 'ABCDEFGH', { now: 1, iterations: IT });
    const b = setup(); await b.app.boot('#g1=' + old);
    expect(await b.app.submitCode('ABCDEFGH')).toBe('expired');
    const c = setup(); await c.app.boot('#g1=AAAA');
    expect(await c.app.submitCode('ABCDEFGH')).toBe('malformed');
    expect(await vault.loadItem('session')).toBeNull();
  });
  it('rejected token is not stored', async () => {
    const blob = await seal(config(), 'ABCDEFGH', { iterations: IT });
    const { app } = setup({ myself: async () => { throw new Unauthorized('x'); } });
    await app.boot('#g1=' + blob); await app.submitCode('ABCDEFGH');
    expect(await app.submitToken('bad')).toBe('rejected');
    expect(await vault.loadItem('session')).toBeNull();
  });
  it('rejects settings with more than one account or a non-https site', () => {
    const c = config(); c.accounts.push({ ...c.accounts[0], id: 'b' });
    expect(() => validateConfig(c)).toThrow();
    const d = config(); d.accounts[0].site = 'http://evil.example';
    expect(() => validateConfig(d)).toThrow();
    const e = config(); e.accounts[0].site = 'https://acme.atlassian.net/x';
    expect(() => validateConfig(e)).toThrow();
  });
});

describe('runtime', () => {
  async function ready(jiraImpl) {
    const blob = await seal(config(), 'ABCDEFGH', { iterations: IT });
    const s = setup(jiraImpl);
    await s.app.boot('#g1=' + blob); await s.app.submitCode('ABCDEFGH'); await s.app.submitToken('T');
    await vi.waitFor(() => expect(s.rendered.at(-1).status.syncedAt).toBeTruthy());
    return s;
  }
  it('401 on refresh -> sign-in banner + account error; keeps data', async () => {
    let fail = false;
    const { app, rendered } = await ready({ myself: async () => ({}), search: async () => { if (fail) throw new Unauthorized('x'); return { issues, truncated: false }; } });
    await new Promise((r) => setTimeout(r, 30)); // let the first refresh finish (busy flag)
    fail = true; await app.refresh();
    const s = rendered.at(-1);
    expect(s.status.banner).toMatch(/sign-in failed/);
    expect(s.accounts[0].error).toBe(true);
    expect(s.tasks).toHaveLength(1);
  });
  it('offline -> stale banner; offline boot shows the snapshot', async () => {
    const { app, rendered } = await ready();
    const off = setup({ myself: async () => ({}), search: async () => { throw new NetworkError('x'); } });
    await off.app.boot('');
    await vi.waitFor(() => expect(off.rendered.at(-1).status.banner).toMatch(/Offline/));
    expect(off.rendered.at(-1).tasks).toHaveLength(1);
    expect(off.rendered.at(-1).status.syncedAt).toBeTruthy();
  });
  it('quick settings persist and are validated; presets switch', async () => {
    const { app } = await ready();
    await app.handle({ type: 'quickSetting', key: 'labelMode', value: 'all' });
    await app.handle({ type: 'quickSetting', key: 'labelMode', value: '<script>' });
    await app.handle({ type: 'quickSetting', key: 'alwaysOnTop', value: true });
    await app.handle({ type: 'selectPreset', id: 'p2' });
    await app.handle({ type: 'selectPreset', id: 'nope' });
    const stored = await vault.loadItem('session');
    expect(stored.config.quick.labelMode).toBe('all');
    expect(stored.config.quick.alwaysOnTop).toBeUndefined();
    expect(stored.config.activePresetId).toBe('p2');
  });
  it('openIssue only opens URLs under the configured site', async () => {
    const blob = await seal(config(), 'ABCDEFGH', { iterations: IT });
    const { app } = setup();
    const openUrl = vi.fn();
    const a = createApp({ vault, makeJira: () => ({ myself: async () => ({}), search: async () => ({ issues, truncated: false }) }), ui: { showCode() {}, showToken() {}, showEmpty() {}, showSettings() {}, hide() {} }, render() {}, openUrl });
    await a.boot('#g1=' + blob); await a.submitCode('ABCDEFGH'); await a.submitToken('T');
    await vi.waitFor(() => expect(openUrl).not.toHaveBeenCalled());
    await new Promise((r) => setTimeout(r, 20));
    await a.handle({ type: 'openIssue', key: 'A-1' });
    expect(openUrl).toHaveBeenCalledWith('https://acme.atlassian.net/browse/A-1');
    await a.handle({ type: 'openIssue', key: 'ZZ-9' });
    expect(openUrl).toHaveBeenCalledTimes(1);
  });
  it('forget wipes everything', async () => {
    const { app, ui } = await ready();
    await app.forget();
    expect(await vault.loadItem('session')).toBeNull();
    expect(await vault.loadItem('snapshot')).toBeNull();
    expect(ui.showEmpty).toHaveBeenCalled();
  });
});

describe('applyQuick', () => {
  it('clamps and ignores bad values', () => {
    const q = { stemOpacity: 30, refreshMinutes: 5, grid: true };
    expect(applyQuick(q, 'stemOpacity', 999).stemOpacity).toBe(80);
    expect(applyQuick(q, 'refreshMinutes', 7).refreshMinutes).toBe(5);
    expect(applyQuick(q, 'grid', 'yes').grid).toBe(true);
  });
});
