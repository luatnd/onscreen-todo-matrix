import { describe, it, expect } from 'vitest';
import worker from '../worker/index.js';

const env = (calls = []) => ({
  JIRA_HOST: 'acme.atlassian.net',
  ASSETS: { fetch: async () => new Response('<html>app</html>', { headers: { 'content-type': 'text/html' } }) },
  _calls: calls,
});
const stubFetch = (calls, resp = () => new Response('{"ok":1}', { status: 200, headers: { 'content-type': 'application/json', 'set-cookie': 'a=b', 'x-evil': '1' } })) =>
  (globalThis.fetch = async (u, init) => { calls.push([String(u), init]); return resp(); });
const req = (path, init = {}) => new Request('https://glance.example.workers.dev' + path, init);

describe('worker proxy', () => {
  it('forwards an allowed GET to the Jira host with only Authorization/Accept', async () => {
    const calls = []; stubFetch(calls);
    const r = await worker.fetch(req('/jira/rest/api/3/search/jql?jql=a%3Db&fields=summary', {
      headers: { Authorization: 'Basic abc', Cookie: 'x=1', 'X-Forwarded-For': '1.1.1.1', Accept: 'application/json' } }), env());
    expect(r.status).toBe(200);
    const [url, init] = calls[0];
    expect(url).toBe('https://acme.atlassian.net/rest/api/3/search/jql?jql=a%3Db&fields=summary');
    const h = new Headers(init.headers);
    expect(h.get('authorization')).toBe('Basic abc');
    expect(h.get('cookie')).toBeNull();
    expect(h.get('x-forwarded-for')).toBeNull();
    expect(init.method).toBe('GET');
  });
  it('strips set-cookie and unknown headers, sets no-store', async () => {
    stubFetch([]);
    const r = await worker.fetch(req('/jira/rest/api/3/myself', { headers: { Authorization: 'Basic x' } }), env());
    expect(r.headers.get('set-cookie')).toBeNull();
    expect(r.headers.get('x-evil')).toBeNull();
    expect(r.headers.get('cache-control')).toBe('no-store');
  });
  it('rejects non-GET', async () => {
    const calls = []; stubFetch(calls);
    for (const m of ['POST', 'PUT', 'DELETE', 'PATCH']) {
      const r = await worker.fetch(req('/jira/rest/api/3/search/jql', { method: m, body: '{}' }), env());
      expect(r.status).toBe(405);
    }
    expect(calls).toHaveLength(0);
  });
  it('rejects paths outside the allowlist and traversal tricks', async () => {
    const calls = []; stubFetch(calls);
    for (const p of ['/jira/rest/api/3/issue/ABC-1/transitions', '/jira/rest/api/3/user/search', '/jira/rest/api/2/field', '/jira/',
      '/jira/rest/api/3/%2e%2e/myself', '/jira/rest/api/3/field%2f..%2fmyself',
      '/jira//rest/api/3/field', '/jira/rest/api/3/field\\x', '/jira/rest/api/3/issue/abc-1', '/jira/wiki/rest/api/space']) {
      const r = await worker.fetch(req(p, { headers: { Authorization: 'Basic x' } }), env());
      expect(r.status, p).toBe(403);
    }
    expect(calls).toHaveLength(0);
  });
  it('allows issue reads by key', async () => {
    stubFetch([]);
    const r = await worker.fetch(req('/jira/rest/api/3/issue/ABC-123?fields=summary', { headers: { Authorization: 'Basic x' } }), env());
    expect(r.status).toBe(200);
  });
  it('rejects cross-origin callers', async () => {
    const calls = []; stubFetch(calls);
    let r = await worker.fetch(req('/jira/rest/api/3/myself', { headers: { Origin: 'https://evil.example', Authorization: 'Basic x' } }), env());
    expect(r.status).toBe(403);
    r = await worker.fetch(req('/jira/rest/api/3/myself', { headers: { 'Sec-Fetch-Site': 'cross-site', Authorization: 'Basic x' } }), env());
    expect(r.status).toBe(403);
    expect(calls).toHaveLength(0);
  });
  it('requires Authorization (never proxies anonymously) and a sane JIRA_HOST', async () => {
    const calls = []; stubFetch(calls);
    expect((await worker.fetch(req('/jira/rest/api/3/myself'), env())).status).toBe(401);
    expect((await worker.fetch(req('/jira/rest/api/3/myself', { headers: { Authorization: 'Basic x' } }), { ...env(), JIRA_HOST: 'evil.com/x' })).status).toBe(500);
    expect((await worker.fetch(req('/jira/rest/api/3/myself', { headers: { Authorization: 'Basic x' } }), { ...env(), JIRA_HOST: undefined })).status).toBe(500);
    expect(calls).toHaveLength(0);
  });
  it('serves static assets with security headers', async () => {
    const r = await worker.fetch(req('/'), env());
    expect(await r.text()).toContain('app');
    expect(r.headers.get('content-security-policy')).toContain("default-src 'none'");
    expect(r.headers.get('strict-transport-security')).toBeTruthy();
    expect(r.headers.get('referrer-policy')).toBe('no-referrer');
    expect(r.headers.get('x-content-type-options')).toBe('nosniff');
  });
});
