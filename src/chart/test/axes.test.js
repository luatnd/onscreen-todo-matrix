import { describe, test, expect } from 'vitest';
import { AXES, CONE, coneApex, coneShape, labelAnchor, placeAxisLabel } from '../src/axes.js';
import { DEFAULT_CAMERA } from '../src/projection.js';

const cam = (yaw, pitch) => ({ yaw, pitch, ...DEFAULT_CAMERA, fit: { cx: 300, cy: 200, sc: 400 } });
const area = (ps) => Math.abs(ps.reduce((a, p, i) => { const q = ps[(i + 1) % ps.length]; return a + p.x * q.y - q.x * p.y; }, 0)) / 2;
const finite = (ps) => ps.every((p) => Number.isFinite(p.x) && Number.isFinite(p.y));

describe('axis cones', () => {
  test('apexes point away from the origin (value +, effort toward less, urgency up)', () => {
    const [v, e, u] = AXES.map((a) => coneApex(a));
    expect(v[0]).toBeCloseTo(1 + CONE.len); expect(v.slice(1)).toEqual([1, 0]);
    expect(e[1]).toBeCloseTo(-CONE.len); expect([e[0], e[2]]).toEqual([0, 0]);
    expect(u[2]).toBeCloseTo(1 + CONE.len / DEFAULT_CAMERA.H); // render space, not squashed by H
  });
  test('side view: outline is a finite polygon containing the apex', () => {
    for (const a of AXES) {
      const c = coneShape(a, cam(-179.7, 33.9));
      expect(finite(c.hull)).toBe(true);
      expect(area(c.hull)).toBeGreaterThan(1);
      expect(c.hull).toContainEqual(expect.objectContaining({ x: c.apex.x, y: c.apex.y }));
    }
  });
  test('looking straight down an axis the cone is still a visible disc', () => {
    const c = coneShape(AXES[2], cam(0, 89)); // urgency points at the viewer
    expect(finite(c.hull)).toBe(true);
    expect(area(c.hull)).toBeGreaterThan(20);
    expect(c.baseVisible).toBe(false);
  });
});

describe('axis label anchor', () => {
  test('label box sits just beyond the apex along the on-screen axis direction', () => {
    expect(labelAnchor({ x: 100, y: 50 }, { x: 80, y: 50 }, 20, 6)).toEqual({ x: 126, y: 50 });
    expect(labelAnchor({ x: 50, y: 10 }, { x: 50, y: 40 }, 20, 6)).toEqual({ x: 50, y: 10 - 12 });
  });
  test('axis pointing at the viewer (apex on base) still gives a finite point', () => {
    const p = labelAnchor({ x: 5, y: 5 }, { x: 5, y: 5 }, 20, 6);
    expect(Number.isFinite(p.x) && Number.isFinite(p.y)).toBe(true);
  });
});

describe('placeAxisLabel', () => {
  const box = { x: 10, y: 90, w: 30, h: 20 };
  test('beyond the apex when it fits', () => {
    expect(placeAxisLabel({ x: 300, y: 100 }, { x: 280, y: 100 }, box, 20, 7, 600, 400)).toEqual({ x: 326, y: 100 });
  });
  test('off-canvas beyond the apex: below the cone, kept inside', () => {
    expect(placeAxisLabel({ x: 10, y: 100 }, { x: 40, y: 100 }, box, 20, 7, 600, 400)).toEqual({ x: 24, y: 90 + 20 + 6 + 7 });
  });
  test('axis line coming from below (urgency at the edge): above the cone first', () => {
    expect(placeAxisLabel({ x: 595, y: 100 }, { x: 590, y: 140 }, { x: 580, y: 95, w: 20, h: 30 }, 20, 7, 600, 400)).toEqual({ x: 576, y: 95 - 6 - 7 });
  });
  test('no room below either: above the cone', () => {
    const low = { x: 10, y: 380, w: 30, h: 15 };
    expect(placeAxisLabel({ x: 10, y: 390 }, { x: 40, y: 390 }, low, 20, 7, 600, 400)).toEqual({ x: 24, y: 380 - 6 - 7 });
  });
});
