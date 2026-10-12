import { test, expect } from 'vitest';
import fixture from '../../fixtures/render-state.json';
import { validateState } from '../src/state.js';

test('shared Swift fixture is a valid RenderState (contract)', () => {
  expect(validateState(fixture)).toEqual([]);
});
test('detects broken payloads', () => {
  expect(validateState(null)).toContain('state is not an object');
  const bad = structuredClone(fixture);
  bad.tasks[0].value = 'x';
  delete bad.settings;
  const errs = validateState(bad);
  expect(errs).toContain('tasks[0].value must be a number in 0..1');
  expect(errs).toContain('settings missing');
});
