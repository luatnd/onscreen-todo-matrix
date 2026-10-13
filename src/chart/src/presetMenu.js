// Pure logic of the top-bar preset menu (spec §11.6). No DOM here: main.js draws what menuRows() returns.

export const NEW = 'new';
export const MANAGE = 'manage';

/** Presets in menu order: grouped by account order; presets whose account is missing come last. */
export function orderedPresets(presets, accounts) {
  const known = new Set(accounts.map((a) => a.id));
  return [
    ...accounts.flatMap((a) => presets.filter((p) => p.accountId === a.id)),
    ...presets.filter((p) => !known.has(p.accountId)),
  ];
}

/** ⌘1…⌘9 → id of the 1st…9th preset in menu order, or null. */
export function shortcutPresetId(state, digit) {
  const n = Number(digit);
  if (!Number.isInteger(n) || n < 1 || n > 9) return null;
  const p = orderedPresets(state.presets, state.accounts)[n - 1];
  return p ? p.id : null;
}

/** Account "+ New preset…" pre-selects: the active preset's account, else the first account, else null. */
export function newPresetAccountId(state) {
  const active = state.presets.find((p) => p.id === state.activePresetId);
  if (active && state.accounts.some((a) => a.id === active.accountId)) return active.accountId;
  return state.accounts.length ? state.accounts[0].id : null;
}

/**
 * Rows to draw, top to bottom:
 *   { kind: 'header', account, missing }                         one per account that has visible presets (account null +
 *                                                                  missing for the "⚠ Account missing" group)
 *   { kind: 'preset', id, name, shortcut, active, missing, error }
 *   { kind: 'action', id: NEW | MANAGE, label }                   always last, also when nothing matches
 * `filter` keeps presets whose name contains it (case-insensitive). Shortcut labels follow the
 * unfiltered menu order, so they never change while typing.
 */
export function menuRows(state, filter = '') {
  const byId = new Map(state.accounts.map((a) => [a.id, a]));
  const f = filter.trim().toLowerCase();
  const rows = [];
  let group;
  orderedPresets(state.presets, state.accounts).forEach((p, i) => {
    if (f && !p.name.toLowerCase().includes(f)) return;
    const account = byId.get(p.accountId) || null;
    const g = account ? account.id : null;
    if (g !== group) {
      rows.push({ kind: 'header', account, missing: !account });
      group = g;
    }
    rows.push({
      kind: 'preset', id: p.id, name: p.name, shortcut: i < 9 ? `⌘${i + 1}` : null,
      active: p.id === state.activePresetId, missing: !account, error: !!(account && account.error),
    });
  });
  rows.push({ kind: 'action', id: NEW, label: '+ New preset…' }, { kind: 'action', id: MANAGE, label: '⚙ Manage presets…' });
  return rows;
}

/** Highlight when the menu opens or the filter changes: the active preset, else the first preset, else "+ New preset…". */
export function initialHighlight(rows) {
  const active = rows.findIndex((r) => r.kind === 'preset' && r.active);
  if (active >= 0) return active;
  const first = rows.findIndex((r) => r.kind === 'preset');
  return first >= 0 ? first : rows.findIndex((r) => r.kind === 'action');
}

/** Next selectable row (presets and actions; headers are skipped) in direction dir (+1 / -1), wrapping. */
export function moveHighlight(rows, current, dir) {
  const selectable = rows.flatMap((r, i) => (r.kind === 'header' ? [] : [i]));
  const at = selectable.indexOf(current);
  if (at < 0) return dir > 0 ? selectable[0] : selectable[selectable.length - 1];
  return selectable[(at + dir + selectable.length) % selectable.length];
}

/** What activating a row does: { type: 'select', id } | { type: 'new' } | { type: 'manage' } | null. */
export function rowAction(row) {
  if (!row || row.kind === 'header') return null;
  if (row.kind === 'action') return { type: row.id === NEW ? 'new' : 'manage' };
  return { type: 'select', id: row.id };
}

/**
 * Keyboard reducer while the menu is open. menu = { filter, hi } (hi = index into menuRows(state, filter)).
 * ↑/↓ move, Enter activates, Esc closes, Backspace / printable characters edit the filter.
 * Returns { menu, action }; action is null, { type: 'close' } or a rowAction().
 */
export function menuKey(state, menu, key) {
  const rows = menuRows(state, menu.filter);
  if (key === 'ArrowDown' || key === 'ArrowUp') {
    return { menu: { ...menu, hi: moveHighlight(rows, menu.hi, key === 'ArrowDown' ? 1 : -1) }, action: null };
  }
  if (key === 'Escape') return { menu, action: { type: 'close' } };
  if (key === 'Enter') return { menu, action: rowAction(rows[menu.hi]) };
  if (key === 'Backspace' || key.length === 1) {
    const filter = key === 'Backspace' ? menu.filter.slice(0, -1) : menu.filter + key;
    return { menu: { filter, hi: initialHighlight(menuRows(state, filter)) }, action: null };
  }
  return { menu, action: null };
}

/** The message posted to Swift for a menu action. */
export function messageFor(action, state) {
  if (!action) return null;
  if (action.type === 'select') return { type: 'selectPreset', id: action.id };
  if (action.type === 'new') return { type: 'newPreset', accountId: newPresetAccountId(state) };
  if (action.type === 'manage') return { type: 'openSettings', tab: 'presets' };
  return null;
}

/** Top-bar button: account colour dot + "Account · Preset". */
export function buttonLabel(state) {
  const p = state.presets.find((x) => x.id === state.activePresetId);
  if (!p) return { color: null, text: 'No presets' };
  const a = state.accounts.find((x) => x.id === p.accountId);
  return a ? { color: safeColor(a.color), text: `${a.name} · ${p.name}` } : { color: null, text: p.name };
}

/** Only "#rrggbb" reaches a style attribute. */
export function safeColor(c) {
  return /^#[0-9a-fA-F]{6}$/.test(c) ? c : '#6b7895';
}
