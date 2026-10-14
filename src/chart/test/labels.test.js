import { describe, test, expect } from 'vitest';
import { truncate, brightness, placeLabels, chooseCardCorner, labelLines, axisTitle, clampLabel } from '../src/labels.js';

const measure = (s) => s.length * 6;
const task = (key, o = {}) => ({ key, summary: `Summary ${key}`, value: 0.5, effort: 0.5, urgency: 0.5, rank: null, ...o });
const item = (t, x, y) => ({ task: t, x, y, r: 6 });
const opts = (o = {}) => ({ width: 600, height: 400, mode: 'smart', selectedKey: null, measure, ...o });

describe('truncate/brightness', () => {
  test('truncates to 28 chars with ellipsis', () => {
    expect(truncate('a'.repeat(28))).toBe('a'.repeat(28));
    expect(truncate('a'.repeat(30))).toBe('a'.repeat(27) + '…');
  });
  test('brightness = (urgency + ease + value) / 3', () => {
    expect(brightness({ urgency: 1, effort: 0, value: 1 })).toBe(1);
    expect(brightness({ urgency: 0, effort: 1, value: 0 })).toBe(0);
  });
});

describe('placeLabels', () => {
  test('places label to the right when free', () => {
    const r = placeLabels([item(task('A'), 100, 100)], opts());
    expect(r.hidden).toBe(0);
    expect(r.placed[0].rect.x).toBe(110);
    expect(r.placed[0].text).toBe('Summary A');
  });
  test('key mode uses the issue key', () => {
    expect(placeLabels([item(task('A'), 100, 100)], opts({ mode: 'key' })).placed[0].text).toBe('A');
  });
  test('off mode labels only the selected task', () => {
    const r = placeLabels([item(task('A'), 100, 100), item(task('B'), 300, 300)], opts({ mode: 'off', selectedKey: 'B' }));
    expect(r.placed.map((p) => p.item.task.key)).toEqual(['B']);
  });
  test('ranked tasks win the contested spot', () => {
    const low = item(task('LOW', { value: 1, effort: 0, urgency: 1 }), 100, 100);
    const top = item(task('TOP', { rank: 1, value: 0, effort: 1, urgency: 0 }), 100, 100);
    const r = placeLabels([low, top], opts());
    expect(r.placed[0].item.task.key).toBe('TOP');
  });
  test('coincident dots never share a label rect and produce no NaN', () => {
    // Review Focus #4
    const r = placeLabels([item(task('A'), 200, 200), item(task('B'), 200, 200)], opts());
    const rects = r.placed.map((p) => p.rect);
    for (const rc of rects) expect(Object.values(rc).every(Number.isFinite)).toBe(true);
    if (rects.length === 2) {
      const [a, b] = rects;
      const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(overlap).toBe(false);
    }
    expect(r.placed.length + r.hidden).toBe(2);
  });
  test('label that fits nowhere is hidden in smart mode but forced in all mode', () => {
    const items = [item(task('A'), 3, 3), item(task('B'), 3, 3)];
    const tiny = { width: 20, height: 20 };
    expect(placeLabels(items, opts(tiny)).hidden).toBe(2);
    expect(placeLabels(items, opts({ ...tiny, mode: 'all' })).placed).toHaveLength(2);
  });
});

describe('stack labels (D27)', () => {
  const ms = ['A', 'B', 'C', 'D', 'E', 'F', 'G'].map((k, i) => task(k, { rank: i === 0 ? 1 : null }));
  const texts = (ls) => ls.map((l) => l.text);
  test('smart: two members show both titles', () => {
    expect(texts(labelLines(ms.slice(0, 2), { mode: 'smart' }))).toEqual(['Summary A', 'Summary B']);
  });
  test('smart: more than two members show the best two then +N more', () => {
    expect(texts(labelLines(ms.slice(0, 4), { mode: 'smart' }))).toEqual(['Summary A', 'Summary B', '+2 more']);
  });
  test('all: up to five titles', () => {
    expect(texts(labelLines(ms, { mode: 'all' }))).toEqual(['Summary A', 'Summary B', 'Summary C', 'Summary D', 'Summary E', '+2 more']);
  });
  test('the selected member is always shown and flagged', () => {
    const ls = labelLines(ms.slice(0, 4), { mode: 'smart', selectedKey: 'D' });
    expect(texts(ls)).toEqual(['Summary A', 'Summary D', '+2 more']);
    expect(ls.map((l) => !!l.sel)).toEqual([false, true, false]);
  });
  test('key mode joins two keys on one line', () => {
    expect(texts(labelLines(ms.slice(0, 4), { mode: 'key' }))).toEqual(['A, B +2']);
    expect(texts(labelLines(ms.slice(0, 1), { mode: 'key' }))).toEqual(['A']);
  });
  test('off mode shows only the selected member', () => {
    expect(texts(labelLines(ms.slice(0, 3), { mode: 'off', selectedKey: 'C' }))).toEqual(['Summary C']);
  });
  test('hollow stack of 2+ starts with an unset header', () => {
    expect(texts(labelLines(ms.slice(0, 3), { mode: 'smart', unset: true }))).toEqual(['3 unset', 'Summary A', 'Summary B', '+1 more']);
    expect(texts(labelLines(ms.slice(0, 1), { mode: 'smart', unset: true }))).toEqual(['Summary A']);
  });
  test('placeLabels sizes one rect for all lines of a stack', () => {
    const it = { task: ms[0], tasks: ms.slice(0, 2), x: 100, y: 100, r: 6 };
    const r = placeLabels([it], opts());
    expect(r.placed).toHaveLength(1);
    expect(r.placed[0].lines).toHaveLength(2);
    expect(r.placed[0].rect.h).toBe(30);
    expect(r.placed[0].rect.w).toBe(measure('Summary A') + 16 + 8);
  });
  test('labels avoid extra obstacles and every badge, their own included', () => {
    const it = { task: ms[0], x: 100, y: 100, r: 6, badge: { x: 106, y: 90, w: 12, h: 12 } };
    const right = { x: 110, y: 92, w: 80, h: 16 };
    expect(placeLabels([it], opts()).placed[0].rect.x).toBeLessThan(100); // own badge blocks the right spot
    expect(placeLabels([{ ...it, badge: undefined }], opts({ obstacles: [right] })).placed[0].rect.x).toBeLessThan(100);
  });
  test('all mode still avoids obstacles when another side is free', () => {
    const right = { x: 110, y: 92, w: 80, h: 16 };
    const r = placeLabels([item(task('A'), 100, 100)], opts({ mode: 'all', obstacles: [right] }));
    expect(r.placed[0].rect.x).toBeLessThan(100);
  });
  test('all mode still places (overlapping) when every side is blocked', () => {
    const all = { x: 0, y: 0, w: 600, h: 400 };
    const r = placeLabels([item(task('A'), 100, 100)], opts({ mode: 'all', obstacles: [all] }));
    expect(r.placed).toHaveLength(1);
  });
  test('smart mode: all sides blocked -> hidden (unchanged)', () => {
    const all = { x: 0, y: 0, w: 600, h: 400 };
    expect(placeLabels([item(task('A'), 100, 100)], opts({ obstacles: [all] })).hidden).toBe(1);
  });
  test('off mode labels a stack holding the selected member', () => {
    const it = { task: ms[0], tasks: ms.slice(0, 2), x: 100, y: 100, r: 6 };
    expect(placeLabels([it], opts({ mode: 'off', selectedKey: 'B' })).placed[0].text).toBe('Summary B');
  });
});

describe('chooseCardCorner', () => {
  test('avoids the corner holding the selected dot', () => {
    const c = chooseCardCorner([], { x: 590, y: 10 }, 600, 400, 230, 120);
    expect(c).toEqual({ x: 8, y: 8 });
  });
  test('prefers the corner with fewest obstacles', () => {
    const obstacles = [{ x: 10, y: 10, w: 50, h: 20 }, { x: 400, y: 20, w: 50, h: 20 }];
    const c = chooseCardCorner(obstacles, { x: 300, y: 200 }, 600, 400, 230, 120);
    expect(c).toEqual({ x: 600 - 230 - 8, y: 400 - 120 - 8 });
  });
});

describe('axisTitle', () => {
  test('appends the mapped field name', () => {
    expect(axisTitle('↑ Urgency', 'Priority')).toBe('↑ Urgency (Priority)');
    expect(axisTitle('Value', 'Business Value')).toBe('Value (Business Value)');
    expect(axisTitle('← Less effort', 'Story Points')).toBe('← Less effort (Story Points)');
  });
  test('unmapped → (not mapped)', () => {
    expect(axisTitle('Value', undefined)).toBe('Value (not mapped)');
    expect(axisTitle('Value', '  ')).toBe('Value (not mapped)');
    expect(axisTitle('Value', [])).toBe('Value (not mapped)');
  });
  test('several fields join with " + "', () => {
    expect(axisTitle('↑ Urgency', ['Priority', 'Due date'])).toBe('↑ Urgency (Priority + Due date)');
  });
});

describe('clampLabel', () => {
  test('keeps wide centered text inside the canvas', () => {
    expect(clampLabel(390, 100, 100, 400, 300)).toEqual({ x: 342, y: 100 });
    expect(clampLabel(5, 100, 100, 400, 300)).toEqual({ x: 58, y: 100 });
  });
  test('left / right alignment and y clamp', () => {
    expect(clampLabel(380, 2, 100, 400, 300, 'left')).toEqual({ x: 292, y: 12 });
    expect(clampLabel(20, 400, 100, 400, 300, 'right')).toEqual({ x: 108, y: 288 });
  });
  test('inside stays put', () => {
    expect(clampLabel(200, 100, 50, 400, 300)).toEqual({ x: 200, y: 100 });
  });
});
