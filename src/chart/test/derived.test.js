import { describe, test, expect } from 'vitest';
import { describeDerived, formatAmount, tipSuffix } from '../src/derived.js';
import { validateState } from '../src/state.js';
import sample from '../../fixtures/render-state.json';

describe('formatAmount', () => {
  test('one decimal, no trailing .0', () => {
    expect(formatAmount(56)).toBe('56');
    expect(formatAmount(3.25)).toBe('3.3');
    expect(formatAmount(0.04)).toBe('0');
  });
});

describe('describeDerived', () => {
  test('timeline: amount, unit and date window', () => {
    const d = { kind: 'timeline', amount: 56, unit: 'h', from: '2026-10-01', to: '2026-10-10', clamped: false };
    expect(describeDerived(d)).toBe('Effort ≈ 56 h from timeline (Oct 1 → Oct 10)');
  });
  test('days unit and clamped marker', () => {
    const d = { kind: 'timeline', amount: 7, unit: 'd', from: '2026-10-01', to: '2026-10-09', clamped: true };
    expect(describeDerived(d)).toBe('Effort ≈ 7 d from timeline (Oct 1 → Oct 9) · ≥ max');
  });
  test('logged time has no window', () => {
    expect(describeDerived({ kind: 'logged', amount: 12.5, unit: 'h', clamped: false })).toBe('Effort ≈ 12.5 h from logged time');
  });
  test('unparseable dates never throw', () => {
    expect(describeDerived({ kind: 'timeline', amount: 8, unit: 'h', from: 'x', to: null, clamped: false })).toBe('Effort ≈ 8 h from timeline');
  });
});

test('tooltip suffix only for derived tasks', () => {
  expect(tipSuffix({})).toBe('');
  expect(tipSuffix({ derived: { kind: 'timeline', amount: 56, unit: 'h' } })).toBe(' · ≈56 h');
});

describe('validateState derived', () => {
  const withDerived = (d) => { const s = structuredClone(sample); s.tasks[1].derived = d; return s; };
  test('fixture (with one derived task) is valid', () => {
    expect(sample.tasks.some((t) => t.derived)).toBe(true);
    expect(validateState(sample)).toEqual([]);
  });
  test('rejects a malformed derived block', () => {
    expect(validateState(withDerived({ kind: 'magic', amount: 1, unit: 'h', clamped: false })).length).toBeGreaterThan(0);
    expect(validateState(withDerived({ kind: 'timeline', amount: 'x', unit: 'h', clamped: false })).length).toBeGreaterThan(0);
    expect(validateState(withDerived({ kind: 'timeline', amount: 1, unit: 'w', clamped: false })).length).toBeGreaterThan(0);
  });
  test('derived is optional', () => {
    const s = structuredClone(sample); delete s.tasks[1].derived;
    expect(validateState(s)).toEqual([]);
  });
});
