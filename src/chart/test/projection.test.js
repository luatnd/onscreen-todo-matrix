import { describe, test, expect } from 'vitest';
import { project, normalizeYaw, clampView, DEFAULT_CAMERA, FACTORY_VIEW } from '../src/projection.js';

const cam = (yaw, pitch, fit) => ({ yaw, pitch, ...DEFAULT_CAMERA, fit });

describe('project', () => {
  test('floor center at yaw 0 pitch 0 projects to the fit center horizontally', () => {
    const p = project(0.5, 0.5, 0, cam(0, 0, { cx: 100, cy: 50, sc: 10 }));
    expect(p.x).toBeCloseTo(100);
    expect(p.z).toBeCloseTo(0);
  });
  test('higher urgency is drawn higher on screen', () => {
    const c = cam(-179.7, 33.9, { cx: 0, cy: 0, sc: 100 });
    expect(project(0.5, 0.5, 1, c).y).toBeLessThan(project(0.5, 0.5, 0, c).y);
  });
  test('nearer points get a larger perspective scale', () => {
    const c = cam(0, 0);
    expect(project(0.5, 0, 0, c).s).toBeGreaterThan(project(0.5, 1, 0, c).s);
  });
  test('factory view matches spec', () => {
    expect(FACTORY_VIEW).toEqual({ yaw: -179.7, pitch: 33.9, zoom: 1 });
  });
});

describe('normalizeYaw', () => {
  test.each([[-539.7, -179.7], [180, -180], [190, -170], [-45, -45]])('%f -> %f', (a, b) => {
    expect(normalizeYaw(a)).toBeCloseTo(b);
  });
});

describe('clampView', () => {
  const def = { yaw: -179.7, pitch: 33.9 };
  test('limited clamps yaw ±18 and pitch ±10 around default', () => {
    const a = clampView(0, 90, def, false), b = clampView(-400, -90, def, false);
    expect(a.yaw).toBeCloseTo(-161.7); expect(a.pitch).toBeCloseTo(43.9);
    expect(b.yaw).toBeCloseTo(-197.7); expect(b.pitch).toBeCloseTo(23.9);
  });
  test('free leaves yaw and clamps pitch ±89', () => {
    expect(clampView(1000, 120, def, true)).toEqual({ yaw: 1000, pitch: 89 });
  });
});
