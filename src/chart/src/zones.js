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
