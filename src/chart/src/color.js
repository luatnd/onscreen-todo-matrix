const clamp01 = (v) => Math.min(1, Math.max(0, v));
export const channel = (v) => Math.round(55 + 200 * clamp01(v));
export const rgbColor = (t, a = 1) => `rgba(${channel(t.urgency)},${channel(1 - t.effort)},${channel(t.value)},${a})`;

export function urgencyColor(u, a = 1) {
  const s = [[91, 123, 181], [224, 160, 48], [229, 72, 77]];
  const v = clamp01(u);
  const t = v < 0.5 ? v / 0.5 : (v - 0.5) / 0.5;
  const A = v < 0.5 ? s[0] : s[1], B = v < 0.5 ? s[1] : s[2];
  const c = A.map((x, i) => Math.round(x + (B[i] - x) * t));
  return `rgba(${c[0]},${c[1]},${c[2]},${a})`;
}

export const taskColor = (t, mode, a = 1) => (mode === 'u' ? urgencyColor(t.urgency, a) : rgbColor(t, a));
