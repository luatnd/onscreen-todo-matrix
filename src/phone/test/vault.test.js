import 'fake-indexeddb/auto';
import { describe, it, expect, beforeEach } from 'vitest';
import { saveItem, loadItem, wipe } from '../src/vault.js';

const rawDump = () => new Promise((resolve, reject) => {
  const rq = indexedDB.open('glance-lite');
  rq.onsuccess = () => {
    const db = rq.result;
    const out = [];
    const c = db.transaction('kv').objectStore('kv').openCursor();
    c.onsuccess = () => { const cur = c.result; if (cur) { out.push([cur.key, cur.value]); cur.continue(); } else { db.close(); resolve(out); } };
    c.onerror = () => reject(c.error);
  };
  rq.onerror = () => reject(rq.error);
});

beforeEach(async () => { await wipe(); });

describe('vault', () => {
  it('round-trips and does not store plaintext', async () => {
    await saveItem('session', { token: 'SECRET-TOKEN-123', email: 'me@x.io' });
    expect(await loadItem('session')).toEqual({ token: 'SECRET-TOKEN-123', email: 'me@x.io' });
    const dump = await rawDump();
    const text = JSON.stringify(dump, (k, v) => (v instanceof Uint8Array || v instanceof ArrayBuffer ? Array.from(new Uint8Array(v)).join(',') : v));
    expect(text).not.toContain('SECRET-TOKEN-123');
    const bytes = dump.flatMap(([, v]) => (v && v.ct ? [new TextDecoder('latin1').decode(v.ct)] : []));
    expect(bytes.join('')).not.toContain('SECRET-TOKEN-123');
  });
  it('device key is non-extractable', async () => {
    await saveItem('a', { x: 1 });
    const keyRow = (await rawDump()).find(([k]) => k === 'device-key');
    expect(keyRow[1].extractable).toBe(false);
    await expect(crypto.subtle.exportKey('raw', keyRow[1])).rejects.toBeTruthy();
  });
  it('missing item -> null; wipe clears everything', async () => {
    expect(await loadItem('nope')).toBeNull();
    await saveItem('session', { a: 1 });
    await wipe();
    expect(await loadItem('session')).toBeNull();
  });
  it('tampered ciphertext -> null (not a crash)', async () => {
    await saveItem('session', { a: 1 });
    const db = await new Promise((r) => { const q = indexedDB.open('glance-lite'); q.onsuccess = () => r(q.result); });
    await new Promise((res) => {
      const tx = db.transaction('kv', 'readwrite'); const st = tx.objectStore('kv');
      const g = st.get('session'); g.onsuccess = () => { const v = g.result; new Uint8Array(v.ct)[0] ^= 1; st.put(v, 'session'); };
      tx.oncomplete = () => { db.close(); res(); };
    });
    expect(await loadItem('session')).toBeNull();
  });
});
