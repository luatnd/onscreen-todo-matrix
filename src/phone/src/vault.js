// Encrypted-at-rest storage in IndexedDB. The AES-GCM device key is non-extractable: page script (or a disk/backup
// dump of the stored values) cannot read it back as bytes, so the token is never stored as plaintext.
const DB = 'glance-lite', STORE = 'kv';

function db() {
  return new Promise((resolve, reject) => {
    const rq = indexedDB.open(DB, 1);
    rq.onupgradeneeded = () => rq.result.createObjectStore(STORE);
    rq.onsuccess = () => resolve(rq.result);
    rq.onerror = () => reject(rq.error);
  });
}
const run = async (mode, fn) => {
  const d = await db();
  try {
    return await new Promise((resolve, reject) => {
      const tx = d.transaction(STORE, mode);
      const rq = fn(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(rq && rq.result);
      tx.onerror = tx.onabort = () => reject(tx.error);
    });
  } finally { d.close(); }
};

async function deviceKey() {
  const existing = await run('readonly', (s) => s.get('device-key'));
  if (existing) return existing;
  const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  await run('readwrite', (s) => s.put(key, 'device-key'));
  return key;
}

export async function saveItem(name, obj) {
  const key = await deviceKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(JSON.stringify(obj)));
  await run('readwrite', (s) => s.put({ iv, ct }, name));
}

export async function loadItem(name) {
  try {
    const row = await run('readonly', (s) => s.get(name));
    if (!row) return null;
    const key = await deviceKey();
    return JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: row.iv }, key, row.ct)));
  } catch { return null; }
}

export function wipe() {
  return new Promise((resolve) => {
    const rq = indexedDB.deleteDatabase(DB);
    rq.onsuccess = rq.onerror = rq.onblocked = () => resolve();
  });
}
