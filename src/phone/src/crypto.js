// Link crypto: v1 | salt(16) | iv(12) | AES-GCM(ciphertext+tag), base64url. Key = PBKDF2-SHA256(code, salt).
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const ITERATIONS = 600000;
const enc = new TextEncoder();

export class BadCode extends Error {}
export class Expired extends Error {}
export class Malformed extends Error {}

export const normalizeCode = (s) => String(s).replace(/[\s-]/g, '').toUpperCase();

export function makeCode() {
  const r = crypto.getRandomValues(new Uint8Array(8));
  // 256 % 32 === 0, so the modulo has no bias
  return Array.from(r, (b) => ALPHABET[b % 32]).join('');
}

const b64u = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
function unb64u(s) {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Malformed('not base64url');
  const t = s.replace(/-/g, '+').replace(/_/g, '/');
  try { return Uint8Array.from(atob(t + '='.repeat((4 - (t.length % 4)) % 4)), (c) => c.charCodeAt(0)); }
  catch { throw new Malformed('not base64url'); }
}

async function deriveKey(code, salt, iterations) {
  const base = await crypto.subtle.importKey('raw', enc.encode(normalizeCode(code)), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, base,
    { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

export async function seal(obj, code, { now = Math.floor(Date.now() / 1000), ttl = 600, iterations = ITERATIONS } = {}) {
  const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(code, salt, iterations);
  const plain = enc.encode(JSON.stringify({ exp: now + ttl, data: obj }));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plain));
  const out = new Uint8Array(1 + 16 + 12 + ct.length);
  out[0] = 1; out.set(salt, 1); out.set(iv, 17); out.set(ct, 29);
  return b64u(out);
}

export async function open(blob, code, { now = Math.floor(Date.now() / 1000), iterations = ITERATIONS } = {}) {
  const u = unb64u(blob);
  if (u.length < 29 + 16 || u[0] !== 1) throw new Malformed('bad link');
  const key = await deriveKey(code, u.slice(1, 17), iterations);
  let plain;
  try { plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: u.slice(17, 29) }, key, u.slice(29)); }
  catch { throw new BadCode('wrong code or damaged link'); }
  const { exp, data } = JSON.parse(new TextDecoder().decode(plain));
  if (!(now <= exp)) throw new Expired('link expired');
  return data;
}
