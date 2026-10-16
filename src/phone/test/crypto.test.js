import { describe, it, expect } from 'vitest';
import { seal, open, makeCode, normalizeCode, BadCode, Expired, Malformed } from '../src/crypto.js';

const IT = 1000; // fast for tests; production default is 600000
const obj = { hello: 'world', n: [1, 2, 3] };
const now = 1_800_000_000;

describe('link crypto', () => {
  it('round-trips', async () => {
    const blob = await seal(obj, 'ABCD-EFGH', { now, iterations: IT });
    expect(await open(blob, 'abcdefgh', { now: now + 5, iterations: IT })).toEqual(obj);
  });
  it('blob is not plaintext and is url-safe', async () => {
    const blob = await seal(obj, 'ABCDEFGH', { now, iterations: IT });
    expect(blob).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(atob(blob.replace(/-/g, '+').replace(/_/g, '/'))).not.toContain('hello');
  });
  it('wrong code -> BadCode', async () => {
    const blob = await seal(obj, 'ABCDEFGH', { now, iterations: IT });
    await expect(open(blob, 'ABCDEFGJ', { now, iterations: IT })).rejects.toBeInstanceOf(BadCode);
  });
  it('tampered -> BadCode', async () => {
    const blob = await seal(obj, 'ABCDEFGH', { now, iterations: IT });
    const i = blob.length - 5;
    const bad = blob.slice(0, i) + (blob[i] === 'A' ? 'B' : 'A') + blob.slice(i + 1);
    await expect(open(bad, 'ABCDEFGH', { now, iterations: IT })).rejects.toBeInstanceOf(BadCode);
  });
  it('expired -> Expired', async () => {
    const blob = await seal(obj, 'ABCDEFGH', { now, ttl: 600, iterations: IT });
    await expect(open(blob, 'ABCDEFGH', { now: now + 601, iterations: IT })).rejects.toBeInstanceOf(Expired);
  });
  it('garbage / truncated -> Malformed', async () => {
    await expect(open('###', 'ABCDEFGH', { now, iterations: IT })).rejects.toBeInstanceOf(Malformed);
    await expect(open('AAAA', 'ABCDEFGH', { now, iterations: IT })).rejects.toBeInstanceOf(Malformed);
    await expect(open('', 'ABCDEFGH', { now, iterations: IT })).rejects.toBeInstanceOf(Malformed);
  });
  it('makeCode is 8 chars from the alphabet; normalizeCode tolerates dash/space/case', () => {
    const c = makeCode();
    expect(c).toMatch(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
    expect(normalizeCode(' ab-cd ef gh ')).toBe('ABCDEFGH');
  });
});
