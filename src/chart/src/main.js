import { computeFit, fitPoints } from './fit.js';
import { DEFAULT_CAMERA, FACTORY_VIEW, clampView, normalizeYaw } from './projection.js';
import { drawScene } from './render.js';
import { chooseCardCorner } from './labels.js';
import { validateState } from './state.js';
import { stackKey, byScoreThenKey } from './stacks.js';
import { describeDerived, tipSuffix } from './derived.js';
import { buttonLabel, initialHighlight, menuKey, menuRows, messageFor, rowAction, safeColor, shortcutPresetId } from './presetMenu.js';
import sample from '../../fixtures/render-state.json';

const $ = (id) => document.getElementById(id);
const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.otm;
const post = (m) => (native ? native.postMessage(m) : console.log('[otm→native]', m));

const st = {
  state: null, tasks: [], sel: null, query: '', yaw: FACTORY_VIEW.yaw, pitch: FACTORY_VIEW.pitch, zoom: 1,
  fit: { cx: 0, cy: 0, sc: 1 }, scene: { proj: [], labels: [] }, pulses: new Map(), glide: null, viewInit: false,
};
const cv = $('cv');
let g, w = 0, h = 0, raf = 0;

let lastViewTimer = 0;
const saveLastViewSoon = () => {
  clearTimeout(lastViewTimer);
  lastViewTimer = setTimeout(() => {
    if (drag) return;
    post({ type: 'saveLastView', yaw: normalizeYaw(st.yaw), pitch: st.pitch, zoom: st.zoom });
  }, 500);
};

const S = () => st.state.settings;
const def = () => ({ yaw: st.state.view.yaw, pitch: st.state.view.pitch });
const cam = () => ({ yaw: st.yaw, pitch: st.pitch, ...DEFAULT_CAMERA, fit: st.fit });
const matches = (t) => !st.query || `${t.key} ${t.summary}`.toLowerCase().includes(st.query);
// const byScore = () => [...st.tasks].sort((a, b) => b.score - a.score || (a.key < b.key ? -1 : 1));
const byScore = () => [...st.tasks].sort(byScoreThenKey);
/** Members of the stack holding key (D27), in stack order; only search matches unless none match. */
function stackOf(key) {
  const t = key && st.tasks.find((x) => x.key === key);
  if (!t) return [];
  const all = st.tasks.filter((x) => stackKey(x) === stackKey(t)).sort(byScoreThenKey);
  const lit = all.filter((x) => matches(x) || x.key === st.sel); // the selected member always stays in the list
  return lit.length ? lit : all;
}
function stepInStack(dir) {
  const ms = stackOf(st.sel);
  if (ms.length < 2) return false;
  const i = ms.findIndex((t) => t.key === st.sel);
  select(ms[(i + dir + ms.length) % ms.length].key);
  return true;
}

function setupCanvas() {
  const dpr = window.devicePixelRatio || 1;
  w = cv.clientWidth; h = cv.clientHeight;
  cv.width = Math.max(1, w * dpr); cv.height = Math.max(1, h * dpr);
  g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function displayTasks() {
  if (!st.glide) return st.tasks;
  const k = Math.min(1, (performance.now() - st.glide.start) / 700), e = 1 - Math.pow(1 - k, 3);
  if (k >= 1) { st.glide = null; return st.tasks; }
  return st.tasks.map((t) => {
    const f = st.glide.from.get(t.key);
    if (!f) return t;
    return { ...t, value: f.value + (t.value - f.value) * e, effort: f.effort + (t.effort - f.effort) * e, urgency: f.urgency + (t.urgency - f.urgency) * e };
  });
}

function refitNow() { st.fit = computeFit(fitPoints(st.tasks), cam(), w, h, st.zoom); }
function refitAnimated() {
  const a = { ...st.fit }, b = computeFit(fitPoints(st.tasks), cam(), w, h, st.zoom), t0 = performance.now();
  const step = (now) => {
    const k = Math.min(1, (now - t0) / 220), e = 1 - Math.pow(1 - k, 3);
    st.fit = { sc: a.sc + (b.sc - a.sc) * e, cx: a.cx + (b.cx - a.cx) * e, cy: a.cy + (b.cy - a.cy) * e };
    draw();
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

function draw() {
  if (!g || !st.state) return;
  const now = performance.now();
  // Toggle the pill first so its rect is current; the scene keeps axis names / labels clear of it.
  const rb = $('bReset');
  rb.classList.toggle('show', !atDefault());
  let reserved = [];
  if (rb.classList.contains('show')) {
    const a = rb.getBoundingClientRect(), b = cv.getBoundingClientRect();
    reserved = [{ x: a.left - b.left - 4, y: a.top - b.top - 4, w: a.width + 8, h: a.height + 8 }];
  }
  st.scene = drawScene(g, {
    reserved, w, h, tasks: displayTasks(), cam: cam(), settings: S(), selectedKey: st.sel, matches, pulses: st.pulses, now,
    axisLabels: st.state.axisLabels,
  });
  placeCard();
  // $('bReset').classList.toggle('show', !atDefault()); (moved above drawScene)
  $('angTxt').textContent = `${normalizeYaw(st.yaw).toFixed(1)}° / ${st.pitch.toFixed(1)}° · ${st.zoom.toFixed(2)}×`;
  const animating = st.glide || [...st.pulses.values()].some((t) => now - t < 1600);
  if (animating && !raf) raf = requestAnimationFrame(() => { raf = 0; draw(); });
}

// ---------- state from Swift ----------
function render(state) {
  const errs = validateState(state);
  if (errs.length) { post({ type: 'log', level: 'error', msg: `invalid state: ${errs.join('; ')}` }); return; }
  const prev = new Map(st.tasks.map((t) => [t.key, t]));
  st.state = state;
  if (!st.viewInit) { const v0 = state.lastView ?? state.view; st.yaw = v0.yaw; st.pitch = v0.pitch; st.zoom = v0.zoom; st.viewInit = true; }
  const v = clampView(st.yaw, st.pitch, def(), state.settings.rotation === 'free');
  st.yaw = v.yaw; st.pitch = v.pitch;
  st.tasks = state.tasks;
  const from = new Map();
  const now = performance.now();
  for (const t of state.tasks) {
    if (t.changed && prev.has(t.key)) { from.set(t.key, prev.get(t.key)); st.pulses.set(t.key, now); }
  }
  if (from.size) st.glide = { from, start: now };
  if (st.sel && !st.tasks.some((t) => t.key === st.sel)) select(null);
  renderChrome();
  refitNow();
  if (st.sel) select(st.sel, false);
  draw();
}

function renderChrome() {
  const s = st.state;
  const lbl = buttonLabel(s);
  $('pbtn').querySelector('.dot').style.background = lbl.color || 'transparent';
  $('pbtn').querySelector('.lbl').textContent = lbl.text;
  if (menu) {
    const rows = menuRows(s, menu.filter);
    if (!rows[menu.hi] || rows[menu.hi].kind === 'header') menu.hi = initialHighlight(rows);
    drawMenu();
  }
  const b = $('banner');
  const text = s.status.banner || s.status.truncated;
  b.style.display = text ? 'block' : 'none';
  b.textContent = text || '';
  b.className = s.status.banner && /settings/i.test(s.status.banner) ? 'link' : '';
  $('setup').style.display = s.configured ? 'none' : 'flex';
  $('setupMsg').textContent = (s.setup && s.setup.message) || 'Finish setup to see your Jira issues.';
  const top = byScore().filter((t) => t.rank).slice(0, 3);
  const next = $('next');
  if (!s.tasks.length) next.innerHTML = s.configured ? '<b>Next:</b> No issues match this filter' : '';
  else next.innerHTML = '<b>Next:</b> ' + top.map((t) => `<span data-k="${encodeURIComponent(t.key)}">${t.rank}. ${escapeHTML(t.summary)}</span>`).join(' &nbsp;·&nbsp; ');
  next.querySelectorAll('span').forEach((el) => { el.onclick = () => select(decodeURIComponent(el.dataset.k)); });
  syncQS();
  updateSync();
}

const escapeHTML = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function updateSync() {
  const at = st.state && st.state.status.syncedAt ? Date.parse(st.state.status.syncedAt) : NaN;
  if (Number.isNaN(at)) { $('sync').textContent = 'not synced'; return; }
  const s = Math.round((Date.now() - at) / 1000);
  $('sync').textContent = s < 5 ? 'synced just now' : s < 60 ? `synced ${s}s ago` : s < 3600 ? `synced ${Math.round(s / 60)}m ago` : `synced ${Math.round(s / 3600)}h ago`;
}
setInterval(updateSync, 1000);

// ---------- selection / card ----------
function select(key, redraw = true) {
  st.sel = key;
  const card = $('card');
  const t = key && st.tasks.find((x) => x.key === key);
  if (!t) { card.style.display = 'none'; st.sel = null; if (redraw) draw(); return; }
  const f = (v) => (v * 5).toFixed(1);
  card.innerHTML = `<div class="k">${escapeHTML(t.key)} · ${escapeHTML(t.status || '')}</div><b>${escapeHTML(t.summary)}</b>
    <div class="row" style="margin-top:4px"><span>Value <b>${f(t.value)}</b></span><span>Ease <b>${f(1 - t.effort)}</b></span><span>Urgency <b>${f(t.urgency)}</b></span></div>
    <div class="row"><span>Priority <b>${escapeHTML(t.priority || '—')}</b></span><span>Due <b>${escapeHTML(t.due || '—')}</b></span>${t.rank ? `<span style="color:#f4c542">#${t.rank} next</span>` : ''}</div>
    ${t.derived ? `<div class="row"><span>${escapeHTML(describeDerived(t.derived))}</span></div>` : ''}
    ${stackRow(t)}<span class="open" id="openBtn">⌘O Open in Jira ↗</span>`;
  card.style.display = 'block';
  $('openBtn').onclick = openIssue;
  if ($('stPrev')) { $('stPrev').onclick = () => stepInStack(-1); $('stNext').onclick = () => stepInStack(1); }
  if (redraw) draw();
}

function stackRow(t) {
  const ms = stackOf(t.key);
  if (ms.length < 2) return '';
  const i = ms.findIndex((x) => x.key === t.key) + 1;
  return `<div class="row stk"><span>Stacked here</span><span><span class="lnk" id="stPrev" title="Previous (←)">‹</span> ${i} of ${ms.length} <span class="lnk" id="stNext" title="Next (→)">›</span></span></div>`;
}

function atDefault() {
  const dv = st.state.view;
  return Math.abs(st.yaw - dv.yaw) < 0.05 && Math.abs(st.pitch - dv.pitch) < 0.05 && Math.abs(st.zoom - dv.zoom) < 0.005;
}

function placeCard() {
  if (!st.sel) return;
  // const m = st.scene.proj.find((x) => x.t.key === st.sel);
  const m = st.scene.proj.find((x) => x.stack.some((t) => t.key === st.sel));
  if (!m) return;
  const card = $('card');
  const obstacles = [...st.scene.labels.map((l) => l.rect), ...st.scene.proj.map((x) => ({ x: x.p.x - x.r, y: x.p.y - x.r, w: 2 * x.r, h: 2 * x.r }))];
  const rb = $('bReset');
  if (rb.classList.contains('show')) {
    const a = rb.getBoundingClientRect(), b = cv.getBoundingClientRect();
    obstacles.push({ x: a.left - b.left, y: a.top - b.top, w: a.width, h: a.height }, { x: w - 130, y: 0, w: 130, h: 44 });
  }
  const c = chooseCardCorner(obstacles, m.p, w, h, card.offsetWidth || 230, card.offsetHeight || 110);
  card.style.left = `${c.x}px`; card.style.top = `${c.y}px`;
}

function openIssue() {
  if (!st.sel) return toast('Select a task first (click a dot or press Tab)');
  post({ type: 'openIssue', key: st.sel });
}

function step(dir) {
  const order = byScore().filter(matches);
  if (!order.length) return;
  const i = order.findIndex((t) => t.key === st.sel);
  const j = i < 0 ? (dir > 0 ? 0 : order.length - 1) : (i + dir + order.length) % order.length;
  select(order[j].key);
}

function toast(s) {
  const t = $('toast'); t.textContent = s; t.style.opacity = 1;
  clearTimeout(t._h); t._h = setTimeout(() => { t.style.opacity = 0; }, 2200);
}

// ---------- search ----------
const q = $('q');
function openSearch() { q.style.display = 'inline-block'; q.focus(); q.select(); }
// function closeSearch() { q.value = ''; st.query = ''; q.style.display = 'none'; $('pn').focus(); draw(); }
// q.oninput = () => { st.query = q.value.toLowerCase().trim(); draw(); };
// The card's "i of n" depends on the search, so rebuild it (select) before drawing.
function closeSearch() { q.value = ''; st.query = ''; q.style.display = 'none'; $('pn').focus(); if (st.sel) select(st.sel, false); draw(); }
q.oninput = () => { st.query = q.value.toLowerCase().trim(); if (st.sel) select(st.sel, false); draw(); };
q.onkeydown = (e) => {
  if (e.key === 'Escape') { e.preventDefault(); closeSearch(); }
  if (e.key === 'Enter') { e.preventDefault(); const m = byScore().find(matches); if (m) select(m.key); $('pn').focus(); }
};

// ---------- quick settings ----------
const qs = $('qs');
function toggleQS() { qs.style.display = qs.style.display === 'block' ? 'none' : 'block'; syncQS(); }
function syncQS() {
  if (!st.state) return;
  qs.querySelectorAll('.seg').forEach((sg) => {
    const v = String(S()[sg.dataset.k]);
    sg.querySelectorAll('b').forEach((b) => b.classList.toggle('on', b.dataset.v === v));
  });
  qs.querySelectorAll('input[type=range]').forEach((i) => { i.value = i.dataset.k === 'zoom' ? Math.round(st.zoom * 100) : S()[i.dataset.k]; });
}
function setSetting(key, value) {
  st.state.settings = { ...S(), [key]: value };
  post({ type: 'quickSetting', key, value });
  if (key === 'rotation') {
    const v = clampView(st.yaw, st.pitch, def(), value === 'free'); st.yaw = v.yaw; st.pitch = v.pitch; refitAnimated(); saveLastViewSoon();
  }
  syncQS(); draw();
}
const parseSeg = (key, v) => (['grid', 'zoneNames', 'alwaysOnTop'].includes(key) ? v === 'true' : key === 'refreshMinutes' ? Number(v) : v);
qs.querySelectorAll('.seg b').forEach((b) => { b.onclick = () => setSetting(b.parentNode.dataset.k, parseSeg(b.parentNode.dataset.k, b.dataset.v)); });
qs.querySelectorAll('input[type=range]').forEach((i) => {
  i.oninput = () => {
    if (i.dataset.k === 'zoom') { st.zoom = Number(i.value) / 100; refitNow(); draw(); saveLastViewSoon(); return; }
    setSetting(i.dataset.k, Number(i.value));
  };
});
$('qsX').onclick = toggleQS;
$('qsPin').onclick = () => {
  const view = { yaw: normalizeYaw(st.yaw), pitch: Math.max(-80, Math.min(80, st.pitch)), zoom: st.zoom };
  st.state.view = view;
  post({ type: 'saveDefaultView', ...view });
  toast('Current angle and zoom saved as default');
};
$('qsRst').onclick = () => {
  st.yaw = FACTORY_VIEW.yaw; st.pitch = FACTORY_VIEW.pitch; st.zoom = FACTORY_VIEW.zoom;
  st.state.view = { ...FACTORY_VIEW };
  post({ type: 'saveDefaultView', ...FACTORY_VIEW });
  refitAnimated(); syncQS();
};

// ---------- preset menu (§11.6) ----------
let menu = null; // { filter, hi } while open
function openMenu() {
  if (!st.state) return;
  menu = { filter: '', hi: initialHighlight(menuRows(st.state, '')) };
  drawMenu();
}
function closeMenu() { menu = null; drawMenu(); $('pn').focus(); }
function runMenuAction(action) {
  if (!action) return;
  const msg = messageFor(action, st.state);
  closeMenu();
  if (msg) post(msg);
}
function drawMenu() {
  const el = $('pmenu');
  if (!menu || !st.state) { el.style.display = 'none'; el.innerHTML = ''; return; }
  const rows = menuRows(st.state, menu.filter);
  let html = menu.filter ? `<div class="pf">${escapeHTML(menu.filter)}</div>` : '';
  rows.forEach((r, i) => {
    if (r.kind === 'header') {
      if (!r.account) { html += '<div class="ph warn">⚠ Account missing</div>'; return; }
      html += `<div class="ph"><span class="dot" style="background:${safeColor(r.account.color)}"></span>${escapeHTML(r.account.name)}</div>`;
      return;
    }
    const cls = `pi${i === menu.hi ? ' hi' : ''}`;
    if (r.kind === 'action') {
      if (rows[i - 1] && rows[i - 1].kind !== 'action') html += '<div class="sep"></div>';
      html += `<div class="${cls}" data-i="${i}"><span class="ck"></span>${escapeHTML(r.label)}</div>`;
      return;
    }
    const warn = r.error ? ' <span class="warn">⚠</span>' : '';
    html += `<div class="${cls}" data-i="${i}"><span class="ck">${r.active ? '✓' : ''}</span>${escapeHTML(r.name)}${warn}<span class="sc">${r.shortcut || ''}</span></div>`;
  });
  el.innerHTML = html;
  el.style.display = 'block';
  el.querySelectorAll('[data-i]').forEach((d) => {
    d.onmousedown = (e) => e.preventDefault();
    d.onmouseenter = () => { const i = Number(d.dataset.i); if (menu.hi !== i) { menu.hi = i; drawMenu(); } };
    d.onclick = () => runMenuAction(rowAction(rows[Number(d.dataset.i)]));
  });
  const hi = el.querySelector('.pi.hi');
  if (hi) hi.scrollIntoView({ block: 'nearest' });
}
$('pbtn').onclick = () => (menu ? closeMenu() : openMenu());
window.addEventListener('mousedown', (e) => { if (menu && !$('pwrap').contains(e.target)) closeMenu(); });

// ---------- top bar ----------
$('bR').onclick = () => post({ type: 'refetch' });
$('bQ').onclick = toggleQS;
$('bS').onclick = () => post({ type: 'openSettings' });
$('bSetup').onclick = () => post({ type: 'openSettings', tab: (st.state && st.state.setup && st.state.setup.tab) || 'accounts' });
$('banner').onclick = () => {
  if ($('banner').className !== 'link') return;
  const tab = st.state && st.state.status.bannerTab;
  post(tab ? { type: 'openSettings', tab } : { type: 'openSettings' });
};

// ---------- keyboard ----------
window.addEventListener('keydown', (e) => {
  if (!st.state || document.activeElement === q) return;
  const m = e.metaKey || e.ctrlKey, k = e.key.toLowerCase();
  if (menu && ['Meta', 'Control', 'Alt', 'Shift'].includes(e.key)) return;
  if (menu && !m && !e.altKey) {
    e.preventDefault();
    const r = menuKey(st.state, menu, e.key);
    menu = r.menu;
    if (r.action && r.action.type === 'close') return closeMenu();
    if (r.action) return runMenuAction(r.action);
    return drawMenu();
  }
  if (menu) closeMenu();
  if (m && /^[1-9]$/.test(e.key)) {
    e.preventDefault();
    const id = shortcutPresetId(st.state, e.key);
    if (id) post({ type: 'selectPreset', id });
    return;
  }
  if (!m && k === 'p') { e.preventDefault(); return openMenu(); }
  if (e.key === 'Tab') { e.preventDefault(); return step(e.shiftKey ? -1 : 1); }
  if (!m && (e.key === 'ArrowLeft' || e.key === 'ArrowRight') && st.sel && !['INPUT', 'SELECT', 'BUTTON'].includes(document.activeElement.tagName)) {
    if (stepInStack(e.key === 'ArrowLeft' ? -1 : 1)) e.preventDefault();
    return;
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    if (qs.style.display === 'block') return toggleQS();
    if (q.style.display === 'inline-block') return closeSearch();
    if (st.sel) return select(null);
    return post({ type: 'hide' });
  }
  if ((m && k === 'o') || (e.key === 'Enter' && document.activeElement.tagName !== 'BUTTON')) { e.preventDefault(); return openIssue(); }
  if (m && k === 'r') { e.preventDefault(); return post({ type: 'refetch' }); }
  if (m && k === 'f') { e.preventDefault(); return openSearch(); }
  if (m && e.key === ',') { e.preventDefault(); return post({ type: 'openSettings' }); }
  if (!m && k === 'r') { resetView(); return; }
  if (!m && k === 'q') return toggleQS();
  if (!m && k === 'f') { setSetting('rotation', S().rotation === 'free' ? 'limited' : 'free'); toast(S().rotation === 'free' ? 'Free rotation' : 'Limited rotation'); }
});

// ---------- mouse ----------
let drag = null;
const hit = (ev) => {
  const r = cv.getBoundingClientRect(), mx = ev.clientX - r.left, my = ev.clientY - r.top;
  let best = null, bd = 14;
  // for (const m of st.scene.proj) { const d = Math.hypot(m.p.x - mx, m.p.y - my); if (d < bd && matches(m.t)) { bd = d; best = m; } }
  // <= : on a tie (a hollow and a solid stack at the same spot) the nearer one, drawn on top, wins.
  for (const m of st.scene.proj) { const d = Math.hypot(m.p.x - mx, m.p.y - my); if (d <= bd && m.lit.length) { bd = d; best = m; } }
  return best;
};
cv.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY, yaw: st.yaw, pitch: st.pitch, moved: false }; $('pn').focus(); });
window.addEventListener('mousemove', (e) => {
  if (!drag || !st.state) return;
  if (Math.abs(e.clientX - drag.x) + Math.abs(e.clientY - drag.y) > 3) drag.moved = true;
  if (!drag.moved) return;
  const v = clampView(drag.yaw + (e.clientX - drag.x) * 0.3, drag.pitch + (e.clientY - drag.y) * 0.3, def(), S().rotation === 'free');
  st.yaw = v.yaw; st.pitch = v.pitch; draw();
});
window.addEventListener('mouseup', (e) => {
  if (!drag) return;
  const d = drag; drag = null;
  if (d.moved) { saveLastViewSoon(); return refitAnimated(); }
  // if (e.target === cv) { const m = hit(e); select(m ? m.t.key : null); }
  if (e.target === cv) {
    const m = hit(e);
    // Click a stack: best member first; clicking it again cycles through the members (D27).
    if (m && m.lit.some((t) => t.key === st.sel) && stepInStack(1)) return;
    select(m ? m.lit[0].key : null);
  }
});
function resetView() { if (!st.state || atDefault()) return; st.yaw = st.state.view.yaw; st.pitch = st.state.view.pitch; st.zoom = st.state.view.zoom; refitAnimated(); syncQS(); saveLastViewSoon(); toast('View reset'); }
$('bReset').addEventListener('click', resetView);
// double-click a task dot opens it in Jira; double-click on empty space does nothing
// cv.addEventListener('dblclick', (e) => { const m = hit(e); if (m) { select(m.t.key); openIssue(); } });
// On a stack (D27) double-click opens its best matching member.
cv.addEventListener('dblclick', (e) => { const m = hit(e); if (m) { select(m.lit[0].key); openIssue(); } });
cv.addEventListener('wheel', (e) => { e.preventDefault(); st.zoom = Math.max(0.5, Math.min(3, st.zoom * Math.exp(-e.deltaY * 0.0015))); refitNow(); draw(); syncQS(); saveLastViewSoon(); }, { passive: false });
cv.addEventListener('mousemove', (e) => {
  const tip = $('tip');
  if (drag) { tip.style.display = 'none'; return; }
  const m = hit(e);
  // if (m && m.t.key !== st.sel) {
  if (m && (m.lit.length > 1 || m.lit[0].key !== st.sel)) {
    tip.style.display = 'block'; tip.style.left = `${m.p.x + 12}px`; tip.style.top = `${m.p.y + 10}px`;
    // tip.textContent = `${m.t.key} · ${m.t.summary}`; cv.style.cursor = 'pointer';
    const rows = m.lit.slice(0, 5).map((t) => `<div>${t.rank ? `<b class="rk">${t.rank}</b> ` : ''}${escapeHTML(`${t.key} · ${t.summary}${tipSuffix(t)}`)}</div>`);
    if (m.lit.length > 5) rows.push(`<div class="more">+${m.lit.length - 5} more</div>`);
    tip.innerHTML = rows.join(''); cv.style.cursor = 'pointer';
  } else { tip.style.display = 'none'; cv.style.cursor = 'grab'; }
});
cv.addEventListener('mouseleave', () => { $('tip').style.display = 'none'; });
window.addEventListener('resize', () => { setupCanvas(); refitNow(); draw(); });
window.addEventListener('error', (e) => post({ type: 'log', level: 'error', msg: String(e.message) }));

// ---------- boot ----------
setupCanvas();
// window.otm = { render };
window.otm = { render, select, openMenu }; // select/openMenu: used by the README demo page (chart/demo)
post({ type: 'ready' });
// if (!native) setTimeout(() => render(structuredClone(sample)), 0);
if (!native && !window.__otmDemo) setTimeout(() => render(structuredClone(sample)), 0);
