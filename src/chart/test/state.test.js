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
test('lastView is optional but must be numeric when present', () => {
  const ok = structuredClone(fixture);
  delete ok.lastView;
  expect(validateState(ok)).toEqual([]);
  const bad = structuredClone(fixture);
  bad.lastView.yaw = 'x';
  expect(validateState(bad)).toContain('lastView.yaw must be a number');
});
test('accounts and presets[].accountId are validated (v1.2.0 contract)', () => {
  expect(fixture.accounts).toHaveLength(2);
  expect(fixture.presets.every((p) => typeof p.accountId === 'string')).toBe(true);
  const bad = structuredClone(fixture);
  delete bad.accounts;
  bad.presets[0].accountId = 7;
  const errs = validateState(bad);
  expect(errs).toContain('accounts must be an array');
  expect(errs).toContain('presets[0].accountId must be a string');
  const bad2 = structuredClone(fixture);
  bad2.accounts[1].error = 'yes';
  bad2.accounts[0].color = null;
  expect(validateState(bad2)).toEqual(['accounts[0].color must be a string', 'accounts[1].error must be a boolean']);
});
test('setup is optional but must carry message and tab', () => {
  const ok = structuredClone(fixture);
  ok.configured = false;
  ok.setup = { message: 'Map axes for Company to see this preset', tab: 'axes' };
  expect(validateState(ok)).toEqual([]);
  const bad = structuredClone(ok);
  delete bad.setup.tab;
  expect(validateState(bad)).toContain('setup must have string message and tab');
});
test('axisLabels: object of optional strings (omitted key = not mapped)', () => {
  expect(fixture.axisLabels).toEqual({ value: 'Business Value', effort: 'Story Points', urgency: 'Priority' });
  const ok = structuredClone(fixture);
  delete ok.axisLabels.value;
  expect(validateState(ok)).toEqual([]);
  const bad = structuredClone(fixture);
  bad.axisLabels.effort = 3;
  expect(validateState(bad)).toEqual(['axisLabels.effort must be a string']);
  delete bad.axisLabels;
  expect(validateState(bad)).toContain('axisLabels must be an object');
});
