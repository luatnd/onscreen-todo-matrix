// Pure helpers for the floor zone labels (spec §4.9). zone = [x0, x1, y0, y1, ...] as in render.js ZONES.
export const ZONE_STYLE = [
  { name: 'Quick wins', color: '#5fd39a', hi: true },
  { name: 'Major projects', color: '#7ea6ff', hi: true },
  { name: 'Fill-ins', color: '#aab3c5', hi: false },
  { name: 'Thankless', color: '#e08a8a', hi: false },
];

/** Floor point: zone value-centre, inset 0.06 from the outer effort edge. */
export const zoneAnchor = ([x0, x1, y0, y1]) => ({ x: (x0 + x1) / 2, y: y0 === 0 ? 0.06 : y1 === 1 ? 0.94 : (y0 + y1) / 2 });

/** Screen rect centred on the projected anchor. */
export const zoneLabelRect = (c, textWidth, h = 24, pad = 6) => ({ x: c.x - textWidth / 2 - pad, y: c.y - h / 2, w: textWidth + 2 * pad, h });

const overlap = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));

/** Tries left shifts 0..max (outer) and, for each, down shifts 0..max (inner), in `step`s; returns the first spot clear of all obstacles, else the least-overlapping one. */
export function nudgeAway(rect, obstacles, step = 8, max = 80) {
  let best = rect, bestA = Infinity;
  for (let l = 0; l <= max; l += step) {
    for (let d = 0; d <= max; d += step) {
      const c = { ...rect, x: rect.x - l, y: rect.y + d };
      const a = obstacles.reduce((s, o) => s + overlap(c, o), 0);
      if (a === 0) return c;
      if (a < bestA) { best = c; bestA = a; }
    }
  }
  return best;
}
