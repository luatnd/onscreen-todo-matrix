// One-off: writes icon-192/512 and apple-touch-icon PNGs (dark tile with a 3-dot "chart"). Run: node make-icons.mjs
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
function png(n) {
  const dots = [[0.32, 0.66, 0.11, [229, 72, 77]], [0.62, 0.42, 0.14, [224, 160, 48]], [0.45, 0.30, 0.09, [91, 123, 181]]];
  const raw = Buffer.alloc((n * 4 + 1) * n);
  for (let y = 0; y < n; y++) {
    raw[y * (n * 4 + 1)] = 0;
    for (let x = 0; x < n; x++) {
      let px = [10, 14, 23], a = 255;
      for (const [cx, cy, r, col] of dots) if (Math.hypot(x / n - cx, y / n - cy) < r) px = col;
      const o = y * (n * 4 + 1) + 1 + x * 4; raw[o] = px[0]; raw[o + 1] = px[1]; raw[o + 2] = px[2]; raw[o + 3] = a;
    }
  }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(n, 0); ihdr.writeUInt32BE(n, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
mkdirSync('public', { recursive: true });
writeFileSync('public/icon-192.png', png(192)); writeFileSync('public/icon-512.png', png(512)); writeFileSync('public/apple-touch-icon.png', png(180));
