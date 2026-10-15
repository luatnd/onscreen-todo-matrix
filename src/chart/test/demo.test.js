import { describe, test, expect } from 'vitest';
import { buildDemoState } from '../demo/demo.js';
import { validateState } from '../src/state.js';

const raw = (key, value, effort, urgency, o = {}) => ({ key, summary: key, status: 'To Do', priority: null, due: null, value, effort, urgency, ...o });
const NOW = new Date('2026-10-15T10:00:00Z');

describe('buildDemoState', () => {
  const tasks = [raw('A', 0.9, 0.1, 0.9), raw('B', 0.5, 0.5, 0.5), raw('C', 0.8, 0.2, 0.2), raw('D', 0.4, 0.4, 0.4), raw('E', 0.7, 0.3, 0.3), raw('F', 0.7, 0.3, 0.3)];
  const s = buildDemoState(tasks, NOW);

  test('score = value * (0.5 + urgency) / (0.3 + effort)', () => {
    expect(s.tasks.find((t) => t.key === 'A').score).toBeCloseTo((0.9 * 1.4) / 0.4);
  });
  test('rank 1..3 go to the top 3 scores (ties by key), others null', () => {
    const r = Object.fromEntries(s.tasks.map((t) => [t.key, t.rank]));
    expect(r).toEqual({ A: 1, C: 2, E: 3, F: null, B: null, D: null });
  });
  test('fire = value >= .7 and urgency >= .8', () => {
    expect(s.tasks.filter((t) => t.fire).map((t) => t.key)).toEqual(['A']);
  });
  test('missing flags and url are filled; state passes validateState', () => {
    expect(s.tasks[0].missing).toEqual({ value: false, effort: false, urgency: false });
    expect(s.tasks[0].url).toMatch(/^https:\/\/acme\.example/);
    expect(validateState(s)).toEqual([]);
    expect(s.status.syncedAt).toBe('2026-10-15T09:59:20.000Z');
  });
  test('missingEffort marks the task hollow', () => {
    const h = buildDemoState([raw('H', 0.5, 0.5, 0.5, { missingEffort: true })], NOW).tasks[0];
    expect(h.missing.effort).toBe(true);
  });
});
