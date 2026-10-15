import { DEMO_TASKS } from './demo-tasks.js';

const score = (t) => (t.value * (0.5 + t.urgency)) / (0.3 + t.effort);

/** Raw demo tasks -> full RenderState (same contract as fixtures/render-state.json). Score, rank and fire are computed. */
export function buildDemoState(tasks, now = new Date()) {
  const scored = tasks.map(({ missingEffort, ...t }) => ({
    ...t,
    url: `https://acme.example/browse/${t.key}`,
    missing: { value: false, effort: !!missingEffort, urgency: false },
    score: score(t),
    rank: null,
    fire: t.value >= 0.7 && t.urgency >= 0.8,
    changed: false,
  }));
  [...scored].sort((a, b) => b.score - a.score || (a.key < b.key ? -1 : 1)).slice(0, 3).forEach((t, i) => { t.rank = i + 1; });
  return {
    tasks: scored,
    view: { yaw: -179.7, pitch: 33.9, zoom: 1 },
    lastView: null,
    settings: { labelMode: 'smart', stemStyle: 'dotted', stemOpacity: 30, colorMode: 'rgb', grid: true, zoneNames: true,
                rotation: 'limited', panelOpacity: 100, alwaysOnTop: false, refreshMinutes: 5 },
    status: { syncedAt: new Date(now.getTime() - 40000).toISOString(), banner: null, truncated: null },
    accounts: [{ id: 'personal', name: 'Personal', color: '#3b82f6', error: false },
               { id: 'acme', name: 'Acme', color: '#f59e0b', error: false }],
    presets: [{ id: 'side', name: 'Side project', accountId: 'personal' },
              { id: 'open', name: 'My open work', accountId: 'acme' },
              { id: 'sprint', name: 'This sprint', accountId: 'acme' },
              { id: 'inc', name: 'Incidents', accountId: 'acme' }],
    activePresetId: 'open',
    configured: true,
    axisLabels: { value: 'Business value', effort: 'Original estimate', urgency: 'Priority' },
  };
}

// Browser entry: #hero selects the top task, #menu opens the preset menu.
if (typeof window !== 'undefined' && window.otm) {
  const state = buildDemoState(DEMO_TASKS, new Date());
  window.otm.render(state);
  const mode = location.hash.slice(1);
  if (mode === 'hero') window.otm.select(state.tasks.find((x) => x.rank === 1).key);
  if (mode === 'menu') window.otm.openMenu();
}
