import { project } from './projection.js';
import { taskColor } from './color.js';
import { placeLabels, brightness } from './labels.js';
import { groupStacks, isHollow } from './stacks.js';
import { AXES, coneShape, placeAxisLabel } from './axes.js';

const ZONES = [
  [0.5, 1, 0, 0.5, 'rgba(70,180,120,.16)', 'Quick wins', true],
  [0.5, 1, 0.5, 1, 'rgba(90,130,220,.12)', 'Major projects', true],
  [0, 0.5, 0, 0.5, 'rgba(160,160,160,.04)', 'Fill-ins', false],
  [0, 0.5, 0.5, 1, 'rgba(200,90,90,.05)', 'Thankless', false],
];
const STEM_DASH = { solid: [], dotted: [0.5, 3.5], dashed: [4, 3] };
const FONT = '11px -apple-system, BlinkMacSystemFont, sans-serif';

/**
 * Draws the whole scene and returns hit-test data.
 * o = { w, h, tasks, cam, settings, selectedKey, matches(task) -> bool, pulses: Map<key, startMs>, now }
 * returns { proj: [{t, p, f, r, fade}], labels: [{item, rect, text}], hidden }
 * Each proj entry is one stack (D19): t = lead, stack = all members, lit = members matching the search.
 */
export function drawScene(g, o) {
  const { w, h, cam, settings: S } = o;
  const P = (x, y, z) => project(x, y, z, cam);
  g.clearRect(0, 0, w, h);

  const line = (a, b, c, lw = 1, dash) => {
    g.strokeStyle = c; g.lineWidth = lw; g.setLineDash(dash || []);
    g.lineCap = dash && dash[0] < 2 ? 'round' : 'butt';
    g.beginPath(); g.moveTo(a.x, a.y); g.lineTo(b.x, b.y); g.stroke();
    g.setLineDash([]); g.lineCap = 'butt';
  };
  const poly = (ps, fill) => {
    g.fillStyle = fill; g.beginPath();
    ps.forEach((p, i) => (i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)));
    g.closePath(); g.fill();
  };
  const txt = (p, s, c, align = 'center', clamp = true) => {
    g.fillStyle = c; g.font = FONT; g.textAlign = align; g.textBaseline = 'middle';
    // g.fillText(s, Math.max(45, Math.min(w - 45, p.x)), p.y);
    g.fillText(s, clamp ? Math.max(45, Math.min(w - 45, p.x)) : p.x, p.y);
  };

  for (const [x0, x1, y0, y1, fill, name, hi] of ZONES) {
    poly([P(x0, y0, 0), P(x1, y0, 0), P(x1, y1, 0), P(x0, y1, 0)], fill);
    if (S.zoneNames) txt(P((x0 + x1) / 2, (y0 + y1) / 2, 0), name, hi ? 'rgba(232,236,244,.5)' : 'rgba(232,236,244,.2)');
  }
  if (S.grid) {
    for (let i = 0; i <= 10; i++) {
      const c = i === 5 ? 'rgba(255,255,255,.28)' : 'rgba(255,255,255,.10)';
      line(P(i / 10, 0, 0), P(i / 10, 1, 0), c);
      line(P(0, i / 10, 0), P(1, i / 10, 0), c);
    }
  }
  const O = P(0, 1, 0);
  line(O, P(1, 1, 0), 'rgba(90,140,255,.85)', 2);
  line(O, P(0, 0, 0), 'rgba(80,220,120,.85)', 2);
  line(O, P(0, 1, 1), 'rgba(255,80,80,.85)', 2);
  const coneBoxes = [], cones = [];
  for (const a of AXES) {
    const c = coneShape(a, cam);
    const xs = c.hull.map((q) => q.x), ys = c.hull.map((q) => q.y);
    coneBoxes.push({ x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) });
    poly(c.hull, a.color);
    if (c.baseVisible) poly(c.ring, a.base);
    cones.push(c);
  }
  // txt(P(1.12, 1, 0), 'Value', '#7aa2ff');
  // txt(P(0, -0.14, 0), '← Less effort', '#6ee08f');
  // txt(P(0, 1, 1.1), '↑ Urgency', '#ff7070');
  // Axis names sit just beyond each cone apex on screen (D20).
  g.font = FONT;
  [['Value', '#7aa2ff'], ['← Less effort', '#6ee08f'], ['↑ Urgency', '#ff7070']].forEach(([s, c], i) => {
    const hw = g.measureText(s).width / 2 + 2, p = placeAxisLabel(cones[i].apex, P(...AXES[i].to), coneBoxes[i], hw, 7, w, h);
    txt(p, s, c, 'center', false); // placeAxisLabel already keeps it inside the canvas
    coneBoxes.push({ x: p.x - hw, y: p.y - 7, w: 2 * hw, h: 14 }); // task labels avoid axis names too
  });

  // const proj = o.tasks
  //   .map((t) => ({ t, p: P(t.value, t.effort, t.urgency), f: P(t.value, t.effort, 0) }))
  //   .sort((a, b) => b.p.z - a.p.z);
  const proj = groupStacks(o.tasks)
    .map((stack) => {
      const t = stack[0];
      return { t, stack, lit: stack.filter(o.matches), p: P(t.value, t.effort, t.urgency), f: P(t.value, t.effort, 0) };
    })
    .sort((a, b) => b.p.z - a.p.z);
  const zs = proj.map((m) => m.p.z);
  const zmin = Math.min(...zs), zmax = Math.max(...zs);
  for (const m of proj) {
    // m.fade = (1 - (0.55 * (m.p.z - zmin)) / (zmax - zmin || 1)) * (o.matches(m.t) ? 1 : 0.12);
    m.fade = (1 - (0.55 * (m.p.z - zmin)) / (zmax - zmin || 1)) * (m.lit.length ? 1 : 0.12);
    m.r = 6 * m.p.s;
  }

  for (const m of proj) {
    g.globalAlpha = m.fade;
    g.fillStyle = 'rgba(0,0,0,.3)';
    g.beginPath(); g.ellipse(m.f.x, m.f.y, 4 * m.f.s, 1.8 * m.f.s, 0, 0, 7); g.fill();
    if (S.stemStyle !== 'off') {
      line(m.f, m.p, taskColor(m.t, S.colorMode, S.stemOpacity / 100), S.stemStyle === 'dotted' ? 1.6 : 1.2, STEM_DASH[S.stemStyle]);
    }
    g.globalAlpha = 1;
  }

  for (const m of proj) {
    // const t = m.t, r = m.r, hollow = t.missing && (t.missing.value || t.missing.effort || t.missing.urgency);
    const t = m.t, r = m.r, hollow = isHollow(t), n = m.stack.length;
    g.globalAlpha = m.fade;
    // Coin stack (D19): offset outlines behind the dot, same dot size.
    for (let k = Math.min(n, 3) - 1; k >= 1; k--) {
      g.beginPath(); g.arc(m.p.x + 0.45 * r * k, m.p.y - 0.45 * r * k, r, 0, 7);
      g.fillStyle = hollow ? 'rgba(15,20,32,.9)' : taskColor(t, S.colorMode, 0.45); g.fill();
      g.strokeStyle = hollow ? taskColor(t, S.colorMode, 0.7) : 'rgba(255,255,255,.4)'; g.lineWidth = 1; g.stroke();
    }
    // if (t.fire) { g.shadowColor = '#ff3b3b'; g.shadowBlur = 18; }
    if (m.stack.some((x) => x.fire)) { g.shadowColor = '#ff3b3b'; g.shadowBlur = 18; }
    g.beginPath(); g.arc(m.p.x, m.p.y, r, 0, 7);
    if (hollow) {
      g.fillStyle = 'rgba(15,20,32,.9)'; g.fill(); g.shadowBlur = 0;
      g.strokeStyle = taskColor(t, S.colorMode); g.lineWidth = 2; g.stroke();
    } else {
      g.fillStyle = taskColor(t, S.colorMode); g.fill(); g.shadowBlur = 0;
      g.strokeStyle = 'rgba(255,255,255,.55)'; g.lineWidth = 1; g.stroke();
    }
    // const pt = o.pulses.get(t.key);
    const pt = m.stack.reduce((a, x) => (o.pulses.has(x.key) ? Math.max(a ?? -Infinity, o.pulses.get(x.key)) : a), null);
    if (pt != null) {
      const k = (o.now - pt) / 1600;
      if (k < 1) { g.strokeStyle = `rgba(244,197,66,${1 - k})`; g.lineWidth = 2; g.beginPath(); g.arc(m.p.x, m.p.y, r + 4 + k * 14, 0, 7); g.stroke(); }
    }
    if (n >= 3 || (m.lit.length && m.lit.length < n)) {
      const label = m.lit.length && m.lit.length < n ? `${m.lit.length}/${n}` : String(n);
      g.font = 'bold 9px -apple-system, sans-serif';
      const coins = Math.min(n, 3) - 1;
      const bw = g.measureText(label).width + 6, bx = m.p.x + r + 0.45 * r * coins - 2, by = m.p.y - r - 0.45 * r * coins - 4;
      g.fillStyle = 'rgba(15,20,32,.9)'; g.fillRect(bx, by - 6, bw, 12);
      m.badge = { x: bx, y: by - 6, w: bw, h: 12 };
      g.fillStyle = '#e8ecf4'; g.textAlign = 'left'; g.textBaseline = 'middle'; g.fillText(label, bx + 3, by + 0.5);
      g.font = FONT;
    }
    // if (o.selectedKey === t.key) { g.strokeStyle = '#3b82f6';
    if (m.stack.some((x) => x.key === o.selectedKey)) { g.strokeStyle = '#3b82f6'; g.lineWidth = 2.5; g.beginPath(); g.arc(m.p.x, m.p.y, r + 4, 0, 7); g.stroke(); }
    g.globalAlpha = 1;
  }

  g.font = FONT;
  // const items = proj.filter((m) => o.matches(m.t)).map((m) => ({ task: m.t, x: m.p.x, y: m.p.y, r: m.r, fade: m.fade }));
  const items = proj.filter((m) => m.lit.length).map((m) => ({
    task: m.lit[0], tasks: m.lit, unset: isHollow(m.t), badge: m.badge, x: m.p.x, y: m.p.y, r: m.r, fade: m.fade,
  }));
  const { placed, hidden } = placeLabels(items, {
    width: w, height: h, mode: S.labelMode, selectedKey: o.selectedKey, measure: (s) => g.measureText(s).width, obstacles: coneBoxes,
  });
  for (const { item, rect, lines } of placed) {
    g.globalAlpha = item.fade;
    g.fillStyle = 'rgba(15,20,32,.6)'; g.fillRect(rect.x, rect.y, rect.w, rect.h);
    lines.forEach((l, i) => {
      const t = l.task, cy = rect.y + 8.5 + 14 * i;
      let tx = rect.x + 4;
      if (t && t.rank) {
        g.fillStyle = '#f4c542'; g.beginPath(); g.arc(tx + 6, cy - 0.5, 6, 0, 7); g.fill();
        g.fillStyle = '#0f1420'; g.font = 'bold 9px -apple-system, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText(String(t.rank), tx + 6, cy); tx += 16; g.font = FONT;
      }
      g.fillStyle = !t ? 'rgba(154,166,189,.9)' : l.sel ? '#8fb8ff' : t.fire ? '#ff9a9a' : `rgba(232,236,244,${0.35 + 0.65 * brightness(t)})`;
      g.textAlign = 'left'; g.textBaseline = 'middle'; g.fillText(l.text, tx, cy);
    });
    g.globalAlpha = 1;
  }
  // Previous single-line label drawing (before D19):
  // for (const { item, rect, text } of placed) {
  //   const t = item.task;
  //   g.globalAlpha = item.fade;
  //   g.fillStyle = 'rgba(15,20,32,.6)'; g.fillRect(rect.x, rect.y, rect.w, rect.h);
  //   let tx = rect.x + 4;
  //   if (t.rank) {
  //     g.fillStyle = '#f4c542'; g.beginPath(); g.arc(tx + 6, rect.y + 8, 6, 0, 7); g.fill();
  //     g.fillStyle = '#0f1420'; g.font = 'bold 9px -apple-system, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  //     g.fillText(String(t.rank), tx + 6, rect.y + 8.5); tx += 16; g.font = FONT;
  //   }
  //   g.fillStyle = o.selectedKey === t.key ? '#8fb8ff' : t.fire ? '#ff9a9a' : `rgba(232,236,244,${0.35 + 0.65 * brightness(t)})`;
  //   g.textAlign = 'left'; g.textBaseline = 'middle'; g.fillText(text, tx, rect.y + 8.5);
  //   g.globalAlpha = 1;
  // }
  return { proj, labels: placed, hidden };
}
