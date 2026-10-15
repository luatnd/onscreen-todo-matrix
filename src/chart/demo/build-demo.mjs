// Builds dist-demo/ (demo page) and, with --images, screenshots it into ../../assets/*.png.
import { execFileSync, spawn } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..'); // src/chart
const out = join(root, 'dist-demo');
const assets = join(root, '..', '..', 'assets');
const run = (cmd, args) => execFileSync(cmd, args, { cwd: root, stdio: 'inherit' });

const FRAME_CSS = `<style>
html, body { margin: 0; width: 1280px; height: 820px; overflow: hidden; }
body { background: linear-gradient(135deg, #27324d, #5a4a78 55%, #8a5f6a); display: flex; align-items: center; justify-content: center; }
#win { width: 1120px; height: 720px; border-radius: 12px; overflow: hidden; background: #0a0e17;
  box-shadow: 0 30px 80px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.12); display: flex; flex-direction: column; }
#tb { flex: none; height: 32px; position: relative; background: linear-gradient(#2b3347, #232a3b); border-bottom: 1px solid #111725;
  display: flex; align-items: center; justify-content: center; color: #aab4c8; font: 600 13px -apple-system, "SF Pro Text", sans-serif; }
#tb i { position: absolute; top: 10px; width: 12px; height: 12px; border-radius: 50%; }
#win #pn { height: auto; flex: 1; min-height: 0; }
</style>`;
const TITLE = `<div id="win"><div id="tb"><i style="left:14px;background:#ff5f57"></i><i style="left:34px;background:#febc2e"></i><i style="left:54px;background:#28c840"></i>Glance</div>`;

function build() {
  run('npm', ['run', 'build']);
  mkdirSync(out, { recursive: true });
  run('npx', ['esbuild', 'demo/demo.js', '--bundle', '--format=iife', '--target=safari17', `--outfile=${join(out, 'demo.js')}`]);
  for (const f of ['chart.js', 'style.css']) copyFileSync(join(root, 'dist', f), join(out, f));
  let html = readFileSync(join(root, 'public', 'index.html'), 'utf8');
  const swap = (a, b) => { if (!html.includes(a)) throw new Error(`index.html changed: missing ${a}`); html = html.replace(a, b); };
  swap('</head>', `${FRAME_CSS}\n</head>`);
  swap('<div id="pn"', `${TITLE}\n<div id="pn"`);
  swap('</div>\n<script src="chart.js"></script>', '</div></div>\n<script src="demo-flag.js"></script>\n<script src="chart.js"></script>\n<script src="demo.js"></script>');
  writeFileSync(join(out, 'demo-flag.js'), 'window.__otmDemo = true;\n'); // external file: the page CSP forbids inline scripts
  writeFileSync(join(out, 'demo.html'), html);
}

const freePort = () => new Promise((res, rej) => {
  const s = createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); });
  s.on('error', rej);
});

async function images() {
  const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (!existsSync(chrome)) throw new Error(`Google Chrome not found at ${chrome}`);
  mkdirSync(assets, { recursive: true });
  const port = await freePort();
  const srv = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', out], { stdio: 'ignore' });
  try {
    await new Promise((r) => setTimeout(r, 1000));
    for (const [hash, file] of [['hero', 'glance-demo.png'], ['menu', 'glance-preset-menu.png']]) {
      const png = join(assets, file);
      run(chrome, ['--headless=new', '--hide-scrollbars', '--window-size=1280,820', '--force-device-scale-factor=2',
        '--virtual-time-budget=4000', `--screenshot=${png}`, `http://127.0.0.1:${port}/demo.html#${hash}`]);
      run('sips', ['-Z', '1800', png]); // max 1800 px on the long edge
    }
  } finally { srv.kill(); }
}

build();
if (process.argv.includes('--images')) await images();
