// Local test rig (no Cloudflare, no real Jira): serves dist/ through the real Worker code and fakes the Jira host.
// Usage: npm run build && node dev-server.mjs   -> prints a ready-to-open import link + code.
import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { extname, join } from 'node:path';
import worker from './worker/index.js';
import { seal, makeCode } from './src/crypto.js';

const PORT = Number(process.env.PORT || 8787);
const input = JSON.parse(readFileSync(new URL('../fixtures/parity-input.json', import.meta.url)));
const caseA = input.cases[0];
const caseD = input.cases.find((c) => c.name.startsWith('D ')); // epics + parents (D36/D37)
const TOKEN = 'test-token', EMAIL = 'me@acme.test';

const realFetch = globalThis.fetch;
globalThis.fetch = async (u, init) => {
  const url = new URL(String(u));
  if (url.hostname !== 'acme.atlassian.net') return realFetch(u, init);
  const auth = new Headers(init.headers).get('authorization');
  if (auth !== 'Basic ' + Buffer.from(`${EMAIL}:${TOKEN}`).toString('base64')) return new Response('{}', { status: 401 });
  const j = (o) => new Response(JSON.stringify(o), { headers: { 'content-type': 'application/json' } });
  if (url.pathname.endsWith('/myself')) return j({ displayName: 'Me', accountId: '1' });
  if (url.pathname.endsWith('/search/jql')) return j({ issues: [...caseA.issues, ...caseD.issues], isLast: true });
  return new Response('{}', { status: 404 });
};

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const env = {
  JIRA_HOST: 'acme.atlassian.net',
  ASSETS: { fetch: async (req) => {
    let p = new URL(req.url).pathname; if (p === '/') p = '/index.html';
    const f = join('dist', p);
    return existsSync(f) ? new Response(readFileSync(f), { headers: { 'content-type': types[extname(f)] || 'application/octet-stream' } }) : new Response('nf', { status: 404 });
  } },
};

let LINK = null;
http.createServer(async (rq, rs) => {
  if (rq.url === '/__link') { rs.writeHead(200, { 'content-type': 'application/json' }); return rs.end(JSON.stringify(LINK)); } // dev only
  const chunks = []; for await (const c of rq) chunks.push(c);
  const r = await worker.fetch(new Request(`http://localhost:${PORT}${rq.url}`, { method: rq.method, headers: rq.headers, body: ['GET', 'HEAD'].includes(rq.method) ? undefined : Buffer.concat(chunks) }), env);
  rs.writeHead(r.status, Object.fromEntries(r.headers)); rs.end(Buffer.from(await r.arrayBuffer()));
}).listen(PORT, async () => {
  const cfg = { accounts: [{ id: 'a', name: 'Acme', site: 'https://acme.atlassian.net', email: EMAIL, axes: caseA.axes }],
    presets: [{ id: 'p1', name: 'My open work', jql: 'assignee = currentUser()', accountId: 'a' }, { id: 'p2', name: 'Due this week', jql: 'due <= endOfWeek()', accountId: 'a' }],
    activePresetId: 'p1', view: { yaw: -179.7, pitch: 33.9, zoom: 1 }, quick: { labelMode: 'smart', stemStyle: 'dotted', stemOpacity: 30, colorMode: 'rgb', grid: true, zoneNames: true, rotation: 'limited', refreshMinutes: 5 } };
  const code = makeCode();
  LINK = { url: `http://localhost:${PORT}/#g1=${await seal(cfg, code)}`, code, token: TOKEN };
  console.log(`${LINK.url}\ncode: ${code}\ntoken: ${TOKEN}`);
});
