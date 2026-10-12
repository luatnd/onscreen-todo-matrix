import { project } from './projection.js';

/** Floor corners, urgency axis top, and every task. */
export function fitPoints(tasks) {
  return [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 1, 1], ...tasks.map((t) => [t.value, t.effort, t.urgency])];
}

/** Scale/offset so all points fit inside the canvas at the current angle; zoom multiplies on top. */
export function computeFit(points, cam, w, h, zoom = 1, pad = 24) {
  const c = { ...cam, fit: { cx: 0, cy: 0, sc: 1 } };
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (const p of points) {
    const q = project(p[0], p[1], p[2], c);
    x0 = Math.min(x0, q.rx); x1 = Math.max(x1, q.rx);
    y0 = Math.min(y0, q.ry); y1 = Math.max(y1, q.ry);
  }
  const bw = Math.max(x1 - x0, 1e-6), bh = Math.max(y1 - y0, 1e-6);
  const sc = Math.max(1e-6, Math.min((w - 2 * pad) / bw, (h - 2 * pad) / bh)) * zoom;
  return { sc, cx: w / 2 - ((x0 + x1) / 2) * sc, cy: h / 2 - ((y0 + y1) / 2) * sc };
}
