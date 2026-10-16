import { describe, it, expect } from 'vitest';
import { createJira, Unauthorized, RateLimited, NetworkError } from '../src/jira.js';

const res = (status, body, headers = {}) => ({ status, ok: status < 300, headers: { get: (k) => headers[k] ?? null }, json: async () => body });

describe('jira client', () => {
  it('sends Basic auth to /jira/ and pages with nextPageToken', async () => {
    const calls = [];
    const pages = [res(200, { issues: [{ key: 'A-1', fields: {} }, { key: 'A-2', fields: {} }], nextPageToken: 't2' }),
      res(200, { issues: [{ key: 'A-3', fields: {} }], isLast: true })];
    const j = createJira({ email: 'me@x.io', token: 'tok', fetch: async (u, o) => { calls.push([u, o]); return pages.shift(); } });
    const r = await j.search('assignee = currentUser()', ['summary', 'status'], 100);
    expect(r.issues.map((i) => i.key)).toEqual(['A-1', 'A-2', 'A-3']);
    const [u, o] = calls[0];
    expect(u).toMatch(/^\/jira\/rest\/api\/3\/search\/jql\?/);
    expect(new URL(u, 'https://x').searchParams.get('fields')).toBe('summary,status');
    expect(new URL(calls[1][0], 'https://x').searchParams.get('nextPageToken')).toBe('t2');
    expect(o.method ?? 'GET').toBe('GET');
    expect(o.headers.Authorization).toBe('Basic ' + btoa('me@x.io:tok'));
    expect(o.credentials).toBe('omit');
  });
  it('caps results and flags truncation', async () => {
    const mk = (n, s) => Array.from({ length: n }, (_, i) => ({ key: `K-${s + i}`, fields: {} }));
    const pages = [res(200, { issues: mk(2, 0), nextPageToken: 'x' }), res(200, { issues: mk(2, 2), nextPageToken: 'y' })];
    const j = createJira({ email: 'e', token: 't', fetch: async () => pages.shift() });
    const r = await j.search('q', ['summary'], 3);
    expect(r.issues).toHaveLength(3);
    expect(r.truncated).toBe(true);
  });
  it('maps errors', async () => {
    const mk = (f) => createJira({ email: 'e', token: 't', fetch: f });
    await expect(mk(async () => res(401, {})).myself()).rejects.toBeInstanceOf(Unauthorized);
    await expect(mk(async () => res(403, {})).myself()).rejects.toBeInstanceOf(Unauthorized);
    await expect(mk(async () => res(429, {}, { 'Retry-After': '7' })).myself()).rejects.toMatchObject({ retryAfter: 7 });
    await expect(mk(async () => res(429, {})).myself()).rejects.toBeInstanceOf(RateLimited);
    await expect(mk(async () => { throw new TypeError('x'); }).myself()).rejects.toBeInstanceOf(NetworkError);
  });
  it('fields() returns the array', async () => {
    const j = createJira({ email: 'e', token: 't', fetch: async () => res(200, [{ id: 'priority' }]) });
    expect(await j.fields()).toEqual([{ id: 'priority' }]);
  });
});
