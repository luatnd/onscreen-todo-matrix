// Glance Lite Worker: serves the PWA and proxies read-only Jira GETs to ONE host (env.JIRA_HOST). Stores/logs nothing.
const ALLOWED = [
  /^rest\/api\/3\/search\/jql$/, /^rest\/api\/3\/field$/, /^rest\/api\/3\/myself$/,
  /^rest\/api\/3\/priority\/search$/, /^rest\/api\/3\/issue\/[A-Z][A-Z0-9_]*-\d+$/,
];
const HOST_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;
const SECURITY = {
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

const deny = (status, msg) => withSecurity(new Response(msg, { status, headers: { 'Cache-Control': 'no-store' } }));
function withSecurity(res) {
  const r = new Response(res.body, res);
  for (const [k, v] of Object.entries(SECURITY)) r.headers.set(k, v);
  return r;
}

async function proxy(request, env, url) {
  if (request.method !== 'GET') return deny(405, 'method not allowed');
  const origin = request.headers.get('Origin');
  const site = request.headers.get('Sec-Fetch-Site');
  if ((origin && origin !== url.origin) || (site && site !== 'same-origin')) return deny(403, 'forbidden');
  const raw = url.pathname.slice('/jira/'.length);
  // exact, un-decoded match only: no encoded dots/slashes, no traversal, no backslashes
  if (/%|\\|\.\.|\/\/|^\//.test(raw) || !ALLOWED.some((re) => re.test(raw))) return deny(403, 'path not allowed');
  if (url.search.length > 4096) return deny(414, 'query too long');
  const auth = request.headers.get('Authorization');
  if (!auth) return deny(401, 'missing credentials');
  if (!env.JIRA_HOST || !HOST_RE.test(env.JIRA_HOST)) return deny(500, 'proxy not configured');
  const upstream = await fetch(`https://${env.JIRA_HOST}/${raw}${url.search}`, {
    method: 'GET',
    headers: { Authorization: auth, Accept: request.headers.get('Accept') || 'application/json' },
    redirect: 'manual',
  });
  const h = new Headers({ 'Cache-Control': 'no-store' });
  for (const k of ['content-type', 'retry-after']) { const v = upstream.headers.get(k); if (v) h.set(k, v); }
  return withSecurity(new Response(upstream.body, { status: upstream.status >= 300 && upstream.status < 400 ? 502 : upstream.status, headers: h }));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/jira/')) return proxy(request, env, url);
    if (request.method !== 'GET' && request.method !== 'HEAD') return deny(405, 'method not allowed');
    return withSecurity(await env.ASSETS.fetch(request));
  },
};
