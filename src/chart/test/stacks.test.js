import { describe, test, expect } from 'vitest';
import { groupStacks, stackKey, isHollow } from '../src/stacks.js';

const t = (key, o = {}) => ({ key, summary: key, value: 0.5, effort: 0.5, urgency: 0.5, score: 1, missing: {}, ...o });

describe('groupStacks', () => {
  test('tasks at the same position share one stack ordered by score, then key', () => {
    const s = groupStacks([t('B', { score: 1 }), t('C', { score: 2 }), t('A', { score: 1 }), t('X', { value: 0.9 })]);
    expect(s.map((m) => m.map((x) => x.key))).toEqual([['C', 'A', 'B'], ['X']]);
  });
  test('hollow and solid tasks at the same position are separate stacks', () => {
    const s = groupStacks([t('A'), t('B', { missing: { effort: true } })]);
    expect(s).toHaveLength(2);
    expect(isHollow(s[1][0])).toBe(true);
  });
  test('floating-point noise below 1e-6 still groups', () => {
    expect(stackKey(t('A', { value: 0.1 + 0.2 }))).toBe(stackKey(t('B', { value: 0.3 })));
    expect(groupStacks([])).toEqual([]);
  });
});
