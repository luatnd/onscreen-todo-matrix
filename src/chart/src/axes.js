import { project, DEFAULT_CAMERA } from './projection.js';

/** Axis-tip cone size in floor units, built in render space (urgency × H) so it is never squashed (D20). */
// export const CONE = { len: 0.06, rad: 0.022, seg: 16 };
export const CONE = { len: 0.06, rad: 0.016, seg: 16 }; // slimmer after visual check

/** Axis lines start at the origin O = (value 0, effort 1, urgency 0); dir points away from O. */
export const AXES = [
  { to: [1, 1, 0], dir: [1, 0, 0], color: 'rgba(90,140,255,.85)', base: 'rgb(48,78,150)' },
  { to: [0, 0, 0], dir: [0, -1, 0], color: 'rgba(80,220,120,.85)', base: 'rgb(40,120,66)' },
  { to: [0, 1, 1], dir: [0, 0, 1], color: 'rgba(255,80,80,.85)', base: 'rgb(140,42,42)' },
];

// Render space (value, effort, urgency·H) is Euclidean; convert an offset back to world coordinates.
const offset = (p, v, k, H) => [p[0] + v[0] * k, p[1] + v[1] * k, p[2] + (v[2] * k) / H];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const unit = (a) => { const n = Math.hypot(...a); return a.map((x) => x / n); };

export const coneApex = (axis, H = DEFAULT_CAMERA.H) => offset(axis.to, axis.dir, CONE.len, H);

/** Monotone-chain convex hull of screen points (counter-clockwise, no repeated end point). */
export function convexHull(points) {
  const ps = [...points].sort((a, b) => a.x - b.x || a.y - b.y);
  if (ps.length < 3) return ps;
  const side = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  const half = (list) => {
    const out = [];
    for (const p of list) {
      while (out.length >= 2 && side(out[out.length - 2], out[out.length - 1], p) <= 0) out.pop();
      out.push(p);
    }
    out.pop();
    return out;
  };
  return [...half(ps), ...half(ps.reverse())];
}

/**
 * Center for an axis label box (half sizes hw, hh) just beyond the cone apex, along the axis as seen on screen,
 * so the text never covers the cone from any angle. An axis pointing at the viewer falls back to "up".
 */
export function labelAnchor(apex, base, hw, hh, gap = 6) {
  let dx = apex.x - base.x, dy = apex.y - base.y;
  const n = Math.hypot(dx, dy);
  if (n < 1e-6) { dx = 0; dy = -1; } else { dx /= n; dy /= n; }
  const k = gap + hw * Math.abs(dx) + hh * Math.abs(dy);
  return { x: apex.x + dx * k, y: apex.y + dy * k };
}

/**
 * Axis label center inside a w×h canvas: beyond the apex when it fits, else beside the cone box on the side away
 * from the axis line (below by default, above when the line comes from below), else the other side.
 * box = the cone's screen bounding box; hw, hh = label half sizes.
 */
export function placeAxisLabel(apex, base, box, hw, hh, w, h, gap = 6) {
  const fits = (p) => p.x - hw >= 4 && p.x + hw <= w - 4 && p.y - hh >= 4 && p.y + hh <= h - 4;
  const beyond = labelAnchor(apex, base, hw, hh, gap);
  if (fits(beyond)) return beyond;
  const x = Math.max(hw + 4, Math.min(w - hw - 4, apex.x));
  const below = { x, y: box.y + box.h + gap + hh }, above = { x, y: box.y - gap - hh };
  const [first, second] = base.y > apex.y + 1 ? [above, below] : [below, above];
  return fits(first) ? first : second;
}

/**
 * Projected cone at the tip of an axis.
 * returns { hull, ring, apex, baseVisible } — baseVisible when the base disc faces the viewer.
 */
export function coneShape(axis, cam) {
  const P = (p) => project(p[0], p[1], p[2], cam);
  const up = Math.abs(axis.dir[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  const u = unit(cross(axis.dir, up)), w = cross(axis.dir, u);
  const ring = [];
  for (let i = 0; i < CONE.seg; i++) {
    const a = (2 * Math.PI * i) / CONE.seg;
    const v = [0, 1, 2].map((k) => u[k] * Math.cos(a) + w[k] * Math.sin(a));
    ring.push(P(offset(axis.to, v, CONE.rad, cam.H)));
  }
  const apex = P(coneApex(axis, cam.H)), base = P(axis.to);
  return { hull: convexHull([apex, ...ring]), ring, apex, baseVisible: apex.z > base.z };
}
