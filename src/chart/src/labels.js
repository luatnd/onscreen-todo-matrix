export const truncate = (s, n = 28) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
export const brightness = (t) => (t.urgency + (1 - t.effort) + t.value) / 3;
const overlaps = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/**
 * items: [{ task, x, y, r }]; opts: { width, height, mode: smart|all|key|off, selectedKey, measure(text) }
 * Order: selected, then ranked (1..3), then brightness. Tries right, left, above, below.
 */
export function placeLabels(items, { width, height, mode, selectedKey, measure }) {
  const dots = items.map((it) => ({ x: it.x - it.r, y: it.y - it.r, w: 2 * it.r, h: 2 * it.r, it }));
  const prio = (it) => (it.task.key === selectedKey ? 3 : 0) + (it.task.rank ? 2 - it.task.rank / 10 : 0);
  const order = items
    .filter((it) => mode !== 'off' || it.task.key === selectedKey)
    .sort((a, b) => prio(b) - prio(a) || brightness(b.task) - brightness(a.task));
  const placed = [];
  let hidden = 0;
  for (const it of order) {
    const t = it.task;
    const text = mode === 'key' ? t.key : truncate(t.summary);
    const bw = t.rank ? 16 : 0;
    const tw = measure(text) + bw + 8, th = 16, { x, y, r } = it;
    const cands = [
      { x: x + r + 4, y: y - th / 2 }, { x: x - r - 4 - tw, y: y - th / 2 },
      { x: x - tw / 2, y: y - r - th - 2 }, { x: x - tw / 2, y: y + r + 2 },
    ];
    let spot = null;
    for (const c of cands) {
      const R = { x: c.x, y: c.y, w: tw, h: th };
      if (R.x < 2 || R.y < 2 || R.x + R.w > width - 2 || R.y + R.h > height - 2) continue;
      if (mode !== 'all' && (placed.some((p) => overlaps(p.rect, R)) || dots.some((d) => d.it !== it && overlaps(d, R)))) continue;
      spot = R;
      break;
    }
    if (!spot && mode === 'all') spot = { x: cands[0].x, y: cands[0].y, w: tw, h: th };
    if (!spot) { hidden++; continue; }
    placed.push({ item: it, rect: spot, text });
  }
  return { placed, hidden };
}

/** Emptiest panel corner for the detail card that does not cover the selected dot. */
export function chooseCardCorner(obstacles, point, w, h, cw, ch, pad = 8) {
  const corners = [
    { x: w - cw - pad, y: pad }, { x: pad, y: pad },
    { x: w - cw - pad, y: h - ch - pad }, { x: pad, y: h - ch - pad },
  ];
  let best = corners[0], bestScore = Infinity;
  for (const c of corners) {
    const R = { x: c.x, y: c.y, w: cw, h: ch };
    if (point.x >= R.x - 10 && point.x <= R.x + R.w + 10 && point.y >= R.y - 10 && point.y <= R.y + R.h + 10) continue;
    const score = obstacles.filter((o) => overlaps(o, R)).length;
    if (score < bestScore) { best = c; bestScore = score; }
  }
  return best;
}

/**
 * Axis label with the mapped Jira field name(s) (spec §11.8.1): axisTitle('↑ Urgency', 'Priority') → "↑ Urgency (Priority)".
 * `names` is a string or an array (several fields join with " + "); nothing usable → "(not mapped)".
 */
export function axisTitle(base, names) {
  const list = (Array.isArray(names) ? names : [names]).filter((n) => typeof n === 'string' && n.trim() !== '');
  return `${base} (${list.length ? list.join(' + ') : 'not mapped'})`;
}

/** Keep a text of `width` px fully inside [8, w-8] x [12, h-12]; x is the anchor for align 'center' | 'left' | 'right'. */
export function clampLabel(x, y, width, w, h, align = 'center') {
  const left = align === 'center' ? x - width / 2 : align === 'right' ? x - width : x;
  const L = Math.max(8, Math.min(w - 8 - width, left));
  return { x: align === 'center' ? L + width / 2 : align === 'right' ? L + width : L, y: Math.max(12, Math.min(h - 12, y)) };
}
