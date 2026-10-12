import { test, expect } from 'vitest';
import { computeFit, fitPoints } from '../src/fit.js';
import { project, DEFAULT_CAMERA } from '../src/projection.js';

const cam = { yaw: -179.7, pitch: 33.9, ...DEFAULT_CAMERA };

test('fitPoints includes floor corners and urgency axis even with zero tasks', () => {
  // Review Focus #3
  expect(fitPoints([])).toHaveLength(5);
  expect(fitPoints([{ value: 0.2, effort: 0.3, urgency: 0.4 }])).toContainEqual([0.2, 0.3, 0.4]);
});

test('all fitted points land inside the padded canvas', () => {
  const pts = fitPoints([{ value: 1, effort: 0, urgency: 1 }]);
  const fit = computeFit(pts, cam, 640, 420, 1, 24);
  for (const p of pts) {
    const q = project(p[0], p[1], p[2], { ...cam, fit });
    expect(q.x).toBeGreaterThanOrEqual(24 - 1e-6);
    expect(q.x).toBeLessThanOrEqual(640 - 24 + 1e-6);
    expect(q.y).toBeGreaterThanOrEqual(24 - 1e-6);
    expect(q.y).toBeLessThanOrEqual(420 - 24 + 1e-6);
  }
  expect(Number.isFinite(fit.sc)).toBe(true);
});

test('zoom multiplies the scale', () => {
  const pts = fitPoints([]);
  expect(computeFit(pts, cam, 640, 420, 2).sc).toBeCloseTo(computeFit(pts, cam, 640, 420, 1).sc * 2);
});
