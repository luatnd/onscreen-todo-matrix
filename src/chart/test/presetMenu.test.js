import { describe, test, expect } from 'vitest';
import {
  NEW, MANAGE, orderedPresets, shortcutPresetId, newPresetAccountId, menuRows, initialHighlight,
  moveHighlight, rowAction, menuKey, messageFor, buttonLabel, safeColor,
} from '../src/presetMenu.js';

const state = () => ({
  accounts: [
    { id: 'default', name: 'Personal', color: '#3b82f6', error: false },
    { id: 'c1', name: 'Company', color: '#f59e0b', error: true },
  ],
  presets: [
    { id: 'team', name: 'Team sprint', accountId: 'c1' },
    { id: 'mine', name: 'My open work', accountId: 'default' },
    { id: 'orphan', name: 'Old filter', accountId: 'gone' },
    { id: 'due', name: 'Due this week', accountId: 'default' },
    { id: 'cw', name: 'My company work', accountId: 'c1' },
  ],
  activePresetId: 'mine',
});
const ids = (rows) => rows.map((r) => (r.kind === 'header' ? `#${r.account ? r.account.name : 'missing'}` : r.id));

describe('grouping and ordering', () => {
  test('presets are grouped by account order, missing-account presets last', () => {
    expect(orderedPresets(state().presets, state().accounts).map((p) => p.id)).toEqual(['mine', 'due', 'team', 'cw', 'orphan']);
  });
  test('rows: account headers, presets with ⌘ shortcuts, then the two actions', () => {
    const rows = menuRows(state());
    expect(ids(rows)).toEqual(['#Personal', 'mine', 'due', '#Company', 'team', 'cw', '#missing', 'orphan', NEW, MANAGE]);
    const byId = Object.fromEntries(rows.filter((r) => r.kind === 'preset').map((r) => [r.id, r]));
    expect(byId.mine).toMatchObject({ shortcut: '⌘1', active: true, missing: false, error: false });
    expect(byId.team).toMatchObject({ shortcut: '⌘3', error: true });
    expect(byId.orphan).toMatchObject({ shortcut: '⌘5', missing: true });
    expect(rows.at(-2)).toEqual({ kind: 'action', id: NEW, label: '+ New preset…' });
    expect(rows.at(-1)).toEqual({ kind: 'action', id: MANAGE, label: '⚙ Manage presets…' });
  });
  test('presets whose account is missing get their own header row', () => {
    const h = menuRows(state()).filter((r) => r.kind === 'header');
    expect(h.map((r) => r.missing)).toEqual([false, false, true]);
    expect(h[2].account).toBeNull();
  });
  test('no presets: only the actions', () => {
    expect(ids(menuRows({ ...state(), presets: [] }))).toEqual([NEW, MANAGE]);
  });
  test('only the first nine presets get a shortcut', () => {
    const presets = Array.from({ length: 11 }, (_, i) => ({ id: `p${i}`, name: `P${i}`, accountId: 'default' }));
    const rows = menuRows({ ...state(), presets }).filter((r) => r.kind === 'preset');
    expect(rows.map((r) => r.shortcut)).toEqual(['⌘1', '⌘2', '⌘3', '⌘4', '⌘5', '⌘6', '⌘7', '⌘8', '⌘9', null, null]);
  });
});

describe('⌘1…⌘9', () => {
  test('maps to menu order', () => {
    expect(shortcutPresetId(state(), '1')).toBe('mine');
    expect(shortcutPresetId(state(), '3')).toBe('team');
    expect(shortcutPresetId(state(), '5')).toBe('orphan');
  });
  test('out of range or not a digit → null', () => {
    expect(shortcutPresetId(state(), '6')).toBeNull();
    expect(shortcutPresetId(state(), '0')).toBeNull();
    expect(shortcutPresetId(state(), 'x')).toBeNull();
  });
});

describe('filter', () => {
  test('case-insensitive name match; empty groups disappear; shortcuts keep their numbers', () => {
    const rows = menuRows(state(), 'WORK');
    expect(ids(rows)).toEqual(['#Personal', 'mine', '#Company', 'cw', NEW, MANAGE]);
    expect(rows.find((r) => r.id === 'cw').shortcut).toBe('⌘4');
  });
  test('nothing matches: the actions stay and are highlighted', () => {
    // Review Focus #5
    const rows = menuRows(state(), 'zzz');
    expect(ids(rows)).toEqual([NEW, MANAGE]);
    expect(rows[initialHighlight(rows)].id).toBe(NEW);
  });
});

describe('keyboard navigation', () => {
  test('opens on the active preset; ↓ skips headers and wraps; ↑ wraps backwards', () => {
    const rows = menuRows(state());
    const hi = initialHighlight(rows);
    expect(rows[hi].id).toBe('mine');
    const next = moveHighlight(rows, hi, 1);
    expect(rows[next].id).toBe('due');
    expect(rows[moveHighlight(rows, next, 1)].id).toBe('team');
    expect(rows[moveHighlight(rows, rows.length - 1, 1)].id).toBe('mine');
    expect(rows[moveHighlight(rows, hi, -1)].id).toBe(MANAGE);
  });
  test('typing filters and re-highlights; Backspace widens again; Enter selects; Esc closes', () => {
    const s = state();
    let menu = { filter: '', hi: initialHighlight(menuRows(s)) };
    for (const k of ['c', 'o', 'm']) menu = menuKey(s, menu, k).menu;
    expect(menu.filter).toBe('com');
    expect(menuRows(s, menu.filter)[menu.hi].id).toBe('cw');
    expect(menuKey(s, menu, 'Enter').action).toEqual({ type: 'select', id: 'cw' });
    menu = menuKey(s, menu, 'Backspace').menu;
    expect(menu.filter).toBe('co');
    expect(menuKey(s, menu, 'Escape').action).toEqual({ type: 'close' });
    expect(menuKey(s, menu, 'Shift')).toEqual({ menu, action: null });
  });
  test('Enter with a filter that hides everything activates "+ New preset…", never a hidden preset', () => {
    // Review Focus #5
    const s = state();
    let menu = { filter: '', hi: initialHighlight(menuRows(s)) };
    for (const k of ['z', 'z']) menu = menuKey(s, menu, k).menu;
    expect(menuKey(s, menu, 'Enter').action).toEqual({ type: 'new' });
  });
  test('headers do nothing; actions map to new/manage', () => {
    expect(rowAction({ kind: 'header', account: {} })).toBeNull();
    expect(rowAction(undefined)).toBeNull();
    expect(rowAction({ kind: 'action', id: MANAGE })).toEqual({ type: 'manage' });
  });
});

describe('messages to Swift', () => {
  test('"+ New preset…" posts newPreset with the active preset\'s account', () => {
    const s = { ...state(), activePresetId: 'team' };
    expect(messageFor({ type: 'new' }, s)).toEqual({ type: 'newPreset', accountId: 'c1' });
  });
  test('active preset with a missing account → first account; no accounts → null', () => {
    expect(newPresetAccountId({ ...state(), activePresetId: 'orphan' })).toBe('default');
    expect(newPresetAccountId({ accounts: [], presets: [], activePresetId: '' })).toBeNull();
  });
  test('select and manage', () => {
    expect(messageFor({ type: 'select', id: 'due' }, state())).toEqual({ type: 'selectPreset', id: 'due' });
    expect(messageFor({ type: 'manage' }, state())).toEqual({ type: 'openSettings', tab: 'presets' });
    expect(messageFor(null, state())).toBeNull();
    expect(messageFor({ type: 'close' }, state())).toBeNull();
  });
});

describe('button label', () => {
  test('colour dot + "Account · Preset"', () => {
    expect(buttonLabel(state())).toEqual({ color: '#3b82f6', text: 'Personal · My open work' });
    expect(buttonLabel({ ...state(), activePresetId: 'orphan' })).toEqual({ color: null, text: 'Old filter' });
    expect(buttonLabel({ ...state(), presets: [], activePresetId: '' })).toEqual({ color: null, text: 'No presets' });
  });
  test('only #rrggbb colours pass', () => {
    expect(safeColor('#F59E0B')).toBe('#F59E0B');
    expect(safeColor('red;background:url(x)')).toBe('#6b7895');
  });
});
