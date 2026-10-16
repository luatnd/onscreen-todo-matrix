// Builds dist/: the PWA (chart UI + phone shell). Run: npm run build
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';

rmSync('dist', { recursive: true, force: true });
mkdirSync('dist', { recursive: true });
await build({ entryPoints: ['src/entry.js'], bundle: true, format: 'iife', target: 'safari16', outfile: 'dist/app.js', minify: true, legalComments: 'none' });
for (const [from, to] of [['../chart/public/style.css', 'style.css'], ['public/phone.css', 'phone.css'], ['public/manifest.webmanifest', 'manifest.webmanifest'],
  ['public/icon-192.png', 'icon-192.png'], ['public/icon-512.png', 'icon-512.png'], ['public/apple-touch-icon.png', 'apple-touch-icon.png']]) copyFileSync(from, 'dist/' + to);

const csp = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'; base-uri 'none'; form-action 'none'";
let html = readFileSync('../chart/public/index.html', 'utf8');
html = html.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/, `<meta http-equiv="Content-Security-Policy" content="${csp}">`)
  .replace('<title>Glance</title>', '<title>Glance</title>\n<meta name="apple-mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n<meta name="theme-color" content="#0a0e17">\n<link rel="manifest" href="manifest.webmanifest">\n<link rel="apple-touch-icon" href="apple-touch-icon.png">')
  .replace('<link rel="stylesheet" href="style.css">', '<link rel="stylesheet" href="style.css">\n<link rel="stylesheet" href="phone.css">')
  .replace('<meta name="viewport" content="width=device-width, initial-scale=1">', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">')
  .replace('<script src="chart.js"></script>', readFileSync('public/gate.html', 'utf8') + '\n<script src="app.js"></script>');
if (!html.includes('app.js') || !html.includes('phone.css') || !html.includes('id="gate"')) throw new Error('index.html template changed upstream');
writeFileSync('dist/index.html', html);

const hash = createHash('sha256');
for (const f of ['app.js', 'style.css', 'phone.css', 'index.html']) hash.update(readFileSync('dist/' + f));
writeFileSync('dist/sw.js', readFileSync('public/sw.js', 'utf8').replace('__BUILD__', hash.digest('hex').slice(0, 12)));
console.log('built dist/');
