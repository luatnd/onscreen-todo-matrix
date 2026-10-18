import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { mapIssues, rank, dayNumber, buildState } from '../src/mapper.js';
import { validateState } from '../../chart/src/state.js';

const fx = (n) => JSON.parse(readFileSync(new URL(`../../fixtures/${n}`, import.meta.url)));
const input = fx('parity-input.json'), expected = fx('parity-expected.json');
const today = dayNumber(input.today);

const strip = (o) => JSON.parse(JSON.stringify(o, (k, v) => (k === 'changed' || v === null ? undefined : v)));
function close(a, b, path = '') {
  if (typeof a === 'number' && typeof b === 'number') return expect(Math.abs(a - b), path).toBeLessThan(1e-9);
  if (a && typeof a === 'object') {
    expect(Object.keys(a).sort(), path).toEqual(Object.keys(b).sort());
    for (const k of Object.keys(a)) close(a[k], b[k], `${path}.${k}`);
  } else expect(a, path).toEqual(b);
}

describe('Swift parity', () => {
  for (const c of input.cases) {
    it(c.name, () => {
      const got = rank(mapIssues(c.issues, c.axes, input.site, today));
      const want = expected.find((e) => e.name === c.name).tasks;
      expect(got.map((t) => t.key)).toEqual(want.map((t) => t.key));
      close(strip(got), strip(want), c.name);
    });
  }
});

describe('buildState', () => {
  it('produces a payload the chart accepts', () => {
    const c = input.cases[0];
    const config = { accounts: [{ id: 'a', name: 'Acme', axes: c.axes }], presets: [{ id: 'p', name: 'Mine', jql: 'x', accountId: 'a' }],
      activePresetId: 'p', view: { yaw: -179.7, pitch: 33.9, zoom: 1 }, quick: { labelMode: 'smart' } };
    const s = buildState({ tasks: mapIssues(c.issues, c.axes, input.site, today), config, status: { syncedAt: null } });
    expect(validateState(JSON.parse(JSON.stringify(s)))).toEqual([]);
    expect(s.activePresetId).toBe('p');
    expect(s.axisLabels.urgency).toBe('priority');
  });
});

describe('epics (D36/D37)', () => {
  it('hides a covered epic, keeps a lone epic and an orphaned child with its parent', () => {
    const c = input.cases.find((x) => x.name.startsWith('D '));
    const got = mapIssues(c.issues, c.axes, input.site, today);
    expect(got.map((t) => t.key).sort()).toEqual(['PA-43', 'PA-50', 'PA-61']);
    expect(got.find((t) => t.key === 'PA-43').parent).toEqual({ key: 'PA-40', summary: 'Clavis project deal' });
  });
});
