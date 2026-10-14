import { describe, test, expect } from 'vitest';
import { ZONE_STYLE, zoneAnchor, zoneLabelRect } from '../src/zones.js';

// zone = [x0, x1, y0, y1] (first four fields of render.js ZONES)
describe('zones', () => {
  test('ZONE_STYLE has the four zones with colour and emphasis', () => {
    expect(ZONE_STYLE.map((z) => z.name)).toEqual(['Quick wins', 'Major projects', 'Fill-ins', 'Thankless']);
    expect(ZONE_STYLE.map((z) => z.color)).toEqual(['#5fd39a', '#7ea6ff', '#aab3c5', '#e08a8a']);
    expect(ZONE_STYLE.map((z) => z.hi)).toEqual([true, true, false, false]);
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
