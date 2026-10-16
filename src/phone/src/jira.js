// Read-only Jira client; talks to the same-origin Worker proxy at /jira/*.
export class Unauthorized extends Error {}
export class RateLimited extends Error { constructor(m, retryAfter) { super(m); this.retryAfter = retryAfter; } }
export class NetworkError extends Error {}
export class HttpError extends Error { constructor(status) { super(`HTTP ${status}`); this.status = status; } }

export function createJira({ email, token, fetch: f = (...a) => fetch(...a), base = '/jira' }) {
  const headers = { Authorization: 'Basic ' + btoa(`${email}:${token}`), Accept: 'application/json' };
  async function get(path, params) {
    const qs = params ? '?' + new URLSearchParams(params) : '';
    let r;
    try { r = await f(`${base}/${path}${qs}`, { method: 'GET', headers, credentials: 'omit', cache: 'no-store' }); }
    catch (e) { throw new NetworkError(String(e && e.message || e)); }
    if (r.status === 401 || r.status === 403) throw new Unauthorized('token rejected');
    if (r.status === 429) { const ra = r.headers.get('Retry-After'); throw new RateLimited('rate limited', ra ? Number(ra) : null); }
    if (!r.ok) throw new HttpError(r.status);
    return r.json();
  }
  return {
    myself: () => get('rest/api/3/myself'),
    fields: () => get('rest/api/3/field'),
    async search(jql, fields, cap) {
      const issues = [];
      let token2, more = false;
      do {
        const p = { jql, fields: fields.join(','), maxResults: String(Math.min(100, cap - issues.length)) };
        if (token2) p.nextPageToken = token2;
        const page = await get('rest/api/3/search/jql', p);
        issues.push(...page.issues);
        token2 = page.nextPageToken;
        more = !!token2 && page.isLast !== true && page.issues.length > 0;
      } while (more && issues.length < cap);
      return { issues: issues.slice(0, cap), truncated: more && issues.length >= cap };
    },
  };
}
