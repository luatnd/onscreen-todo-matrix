import { describe, test, expect } from 'vitest';
import { ZONES } from '../src/render.js';
import { ZONE_STYLE, zoneAnchor, zoneLabelRect, nudgeAway } from '../src/zones.js';

// zone = [x0, x1, y0, y1] (first four fields of render.js ZONES)
describe('zones', () => {
  test('ZONE_STYLE has the four zones with colour and emphasis', () => {
    expect(ZONE_STYLE.map((z) => z.name)).toEqual(['Quick wins', 'Major projects', 'Fill-ins', 'Thankless']);
    expect(ZONE_STYLE.map((z) => z.color)).toEqual(['#5fd39a', '#7ea6ff', '#aab3c5', '#e08a8a']);
    expect(ZONE_STYLE.map((z) => z.hi)).toEqual([true, true, false, false]);
  });
  test('ZONE_STYLE names match render ZONES', () => {
    ZONE_STYLE.forEach((z, i) => expect(z.name).toBe(ZONES[i][5]));
  });
  test('zoneAnchor: value centre, near the outer effort edge', () => {
    expect(zoneAnchor([0.5, 1, 0, 0.5])).toEqual({ x: 0.75, y: 0.06 });
    expect(zoneAnchor([0.5, 1, 0.5, 1])).toEqual({ x: 0.75, y: 0.94 });
    expect(zoneAnchor([0, 0.5, 0, 0.5])).toEqual({ x: 0.25, y: 0.06 });
    expect(zoneAnchor([0, 0.5, 0.5, 1])).toEqual({ x: 0.25, y: 0.94 });
  });
  test('zoneLabelRect is centred on the anchor with padding', () => {
    expect(zoneLabelRect({ x: 100, y: 50 }, 80)).toEqual({ x: 54, y: 38, w: 92, h: 24 });
    expect(zoneLabelRect({ x: 0, y: 0 }, 10, 20, 2)).toEqual({ x: -7, y: -10, w: 14, h: 20 });
  });
});

describe('nudgeAway', () => {
  const pill = { x: 100, y: 0, w: 80, h: 30 };
  const hits = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
  test('overlap -> moved clear (down first)', () => {
    const r = nudgeAway({ x: 110, y: 5, w: 60, h: 14 }, [pill], 8, 80);
    expect(hits(r, pill)).toBe(false);
    expect(r.x).toBe(110);
  });
  test('no overlap -> unchanged', () => {
    const r = { x: 0, y: 100, w: 20, h: 10 };
    expect(nudgeAway(r, [pill], 8, 80)).toEqual(r);
  });
  test('cannot escape -> least-bad position, no throw', () => {
    const big = { x: -1000, y: -1000, w: 3000, h: 3000 };
    const r = nudgeAway({ x: 0, y: 0, w: 10, h: 10 }, [big], 8, 16);
    expect(Number.isFinite(r.x) && Number.isFinite(r.y)).toBe(true);
  });
});
