// JS port of AxisMapper.map + Scorer.rank + RenderStateBuilder (Swift is the reference; see fixtures/parity-*.json).
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const AXES = ['value', 'effort', 'urgency'];
const WORKDAY = 8 * 3600;

const kindOf = (m) => (m ? Object.keys(m)[0] : null); // 'option' | 'number' | 'date'
const spec = (m) => (m ? m[kindOf(m)] : null);

export function optionLabel(raw) {
  if (raw == null) return null;
  if (typeof raw === 'string') return raw === '' ? null : raw;
  if (typeof raw === 'number') return Number.isInteger(raw) ? String(raw) : String(raw);
  if (typeof raw === 'boolean') return raw ? 'true' : 'false';
  if (Array.isArray(raw)) { for (const x of raw) { const l = optionLabel(x); if (l != null) return l; } return null; }
  if (typeof raw === 'object') {
    if (typeof raw.name === 'string') return raw.name;
    if (typeof raw.value === 'string') return raw.value;
  }
  return null;
}

// Calendar day number from "yyyy-MM-dd" or an ISO datetime (first 10 chars; time zone ignored on purpose).
export function dayNumber(raw) {
  if (typeof raw !== 'string' || raw.length < 10) return null;
  const p = raw.slice(0, 10).split('-');
  if (p.length !== 3) return null;
  const [y, m, d] = p.map((x) => (/^\d+$/.test(x) ? Number(x) : NaN));
  if ([y, m, d].some(Number.isNaN)) return null;
  return Math.round(Date.UTC(y, m - 1, d) / 86400000);
}
export const todayNumber = (now = new Date()) => Math.round(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000);
const weekday = (day) => (new Date(day * 86400000).getUTCDay()); // 0 = Sunday

function workingDays(a, b) {
  if (b < a) return null;
  const total = b - a + 1;
  let n = Math.floor(total / 7) * 5;
  for (let i = 0; i < total % 7; i++) { const wd = weekday(a + i); if (wd !== 0 && wd !== 6) n++; }
  return Math.max(1, n);
}

const num = (v) => (typeof v === 'number' ? v : null);

function normalize(raw, mapping, autoRange, today) {
  const k = kindOf(mapping), s = spec(mapping);
  if (k === 'option') {
    const label = optionLabel(raw);
    if (label == null) return null;
    const lv = s.levels || {};
    return clamp01((Object.hasOwn(lv, label) ? lv[label] : 2.5) / 5);
  }
  if (k === 'number') {
    const n = num(raw);
    if (n == null) return null;
    const lo = s.min ?? (autoRange ? autoRange[0] : n), hi = s.max ?? (autoRange ? autoRange[1] : n);
    const t = hi > lo ? clamp01((n - lo) / (hi - lo)) : 0.5;
    return s.invert ? 1 - t : t;
  }
  if (k === 'date') {
    const day = dayNumber(raw);
    if (day == null) return null;
    const days = day - today;
    const t = days <= 0 ? 1 : (s.horizonDays <= 0 ? 0 : clamp01(1 - days / s.horizonDays));
    return s.invert ? 1 - t : t;
  }
  return null;
}

function autoRange(fieldId, issues) {
  const v = issues.map((i) => num(i.fields[fieldId])).filter((x) => x != null);
  return v.length ? [Math.min(...v), Math.max(...v)] : null;
}

function timelineFallback(effort) {
  const m = effort.mapping;
  return effort.timeline && kindOf(m) === 'number' && spec(m).fieldId === 'timeoriginalestimate' ? effort.timeline : null;
}

function derivedSeconds(issue, tl) {
  const f = issue.fields;
  const logged = (num(f.timespent) ?? 0) + (num(f.timeestimate) ?? 0);
  if (logged > 0) return { seconds: logged, kind: 'logged' };
  if (optionLabel(f.issuetype) === 'Epic') return null;
  if (!tl.startFieldId) return null;
  const a = dayNumber(f[tl.startFieldId]), b = dayNumber(f[tl.endFieldId]);
  if (a == null || b == null) return null;
  const days = workingDays(a, b);
  if (days == null) return null;
  const str = (v) => (typeof v === 'string' ? v.slice(0, 10) : undefined);
  return { seconds: days * WORKDAY, kind: 'timeline', from: str(f[tl.startFieldId]), to: str(f[tl.endFieldId]) };
}

// D36: fields.parent -> {key, summary}; undefined when absent.
function parentOf(f) {
  const p = f.parent;
  if (!p || typeof p !== 'object' || typeof p.key !== 'string') return undefined;
  const s = p.fields && p.fields.summary;
  return { key: p.key, summary: typeof s === 'string' ? s : p.key };
}
// D36: issuetype named "Epic" or hierarchy level >= 1.
const isEpic = (f) => !!f.issuetype && typeof f.issuetype === 'object' && (f.issuetype.name === 'Epic' || (f.issuetype.hierarchyLevel ?? 0) >= 1);

// D37: drop every epic that has at least one other issue in the result as a direct child.
function hideCoveredEpics(rows) {
  const parents = new Set(rows.map((r) => r.parent && r.parent.key).filter(Boolean));
  return rows.filter((r) => !(r.epic && parents.has(r.t.key))).map((r) => r.t);
}

export function mapIssues(issues, axes, site, today) {
  const ranges = {};
  for (const a of AXES) if (kindOf(axes[a].mapping) === 'number') ranges[a] = autoRange(spec(axes[a].mapping).fieldId, issues);
  const derived = new Map();
  const tl = timelineFallback(axes.effort);
  if (tl) {
    const id = spec(axes.effort.mapping).fieldId;
    for (const i of issues) if (num(i.fields[id]) == null) { const d = derivedSeconds(i, tl); if (d) derived.set(i.key, d); }
    const real = ranges.effort;
    if (derived.size && (!real || real[0] === real[1])) {
      const all = issues.map((i) => num(i.fields[id])).filter((x) => x != null).concat([...derived.values()].map((d) => d.seconds));
      if (all.length) ranges.effort = [Math.min(...all), Math.max(...all)];
    }
  }
  const rows = issues.map((issue) => {
    const values = {}, missing = {};
    let derivedEffort;
    for (const a of AXES) {
      const cfg = axes[a];
      let n = cfg.mapping ? normalize(issue.fields[spec(cfg.mapping).fieldId], cfg.mapping, ranges[a], today) : null;
      const d = derived.get(issue.key);
      if (n == null && a === 'effort' && d && cfg.mapping && cfg.timeline) {
        n = normalize(d.seconds, cfg.mapping, ranges[a], today);
        let top = ranges[a] ? ranges[a][1] : null;
        if (kindOf(cfg.mapping) === 'number' && spec(cfg.mapping).max != null) top = spec(cfg.mapping).max;
        const days = cfg.timeline.unit === 'days';
        derivedEffort = { kind: d.kind, amount: days ? d.seconds / WORKDAY : d.seconds / 3600, unit: days ? 'd' : 'h',
          clamped: top != null ? d.seconds > top : false };
        if (d.from !== undefined) derivedEffort.from = d.from;
        if (d.to !== undefined) derivedEffort.to = d.to;
      }
      values[a] = n ?? (cfg.missingDefault ?? 0.5);
      missing[a] = n == null;
    }
    const f = issue.fields;
    const t = { key: issue.key, summary: typeof f.summary === 'string' ? f.summary : issue.key,
      status: optionLabel(f.status) ?? '', url: `${site.replace(/\/+$/, '')}/browse/${issue.key}`,
      value: values.value, effort: values.effort, urgency: values.urgency, missing };
    const p = optionLabel(f.priority); if (p != null) t.priority = p;
    if (typeof f.duedate === 'string') t.due = f.duedate;
    if (derivedEffort) t.derived = derivedEffort;
    const parent = parentOf(f); if (parent) t.parent = parent;
    return { t, parent, epic: isEpic(f) };
  });
  return hideCoveredEpics(rows);
}

export const score = (t) => (t.value * (0.5 + t.urgency)) / (0.3 + t.effort);
export const isFire = (t) => t.value >= 0.7 && t.urgency >= 0.8;

export function rank(tasks) {
  return tasks.map((t) => ({ ...t, score: score(t), fire: isFire(t) }))
    .sort((a, b) => (a.score !== b.score ? b.score - a.score : a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map((t, i) => ({ ...t, rank: i < 3 ? i + 1 : undefined }));
}

export const ACCOUNT_COLORS = ['#3b82f6', '#f59e0b', '#10b981', '#ec4899', '#8b5cf6', '#06b6d4'];

// field ids the search must request (summary/status/etc. + mapped fields + fallback fields)
export function fieldIds(axes) {
  const ids = new Set(['summary', 'status', 'priority', 'duedate', 'parent', 'issuetype']);
  for (const a of AXES) if (axes[a].mapping) ids.add(spec(axes[a].mapping).fieldId);
  const tl = timelineFallback(axes.effort);
  if (tl) [tl.startFieldId, tl.endFieldId, 'timespent', 'timeestimate'].filter(Boolean).forEach((x) => ids.add(x));
  return [...ids];
}

const labelName = (c) => (c.mapping ? (c.fieldName ?? spec(c.mapping).fieldId) : undefined);

// config = the exported AppConfig JSON; previous = Map(key -> {value,effort,urgency}) for the "changed" pulse.
export function buildState({ tasks, previous, config, status, configured = true, accountErrors = [], setup }) {
  const ranked = rank(tasks).map((t) => {
    const p = previous && previous.get(t.key);
    const changed = !!p && (Math.abs(p.value - t.value) > 1e-9 || Math.abs(p.effort - t.effort) > 1e-9 || Math.abs(p.urgency - t.urgency) > 1e-9);
    return { ...t, changed };
  });
  const accounts = config.accounts.map((a, i) => ({ id: a.id, name: a.name, color: ACCOUNT_COLORS[i % ACCOUNT_COLORS.length], error: accountErrors.includes(a.id) }));
  const known = new Set(config.accounts.map((a) => a.id));
  const menu = config.accounts.flatMap((a) => config.presets.filter((p) => p.accountId === a.id)).concat(config.presets.filter((p) => !known.has(p.accountId)));
  const active = config.presets.find((p) => p.id === config.activePresetId) ?? menu.find((p) => known.has(p.accountId)) ?? config.presets[0];
  const acct = active && config.accounts.find((a) => a.id === active.accountId);
  const ax = acct ? acct.axes : null;
  const axisLabels = {};
  if (ax) for (const a of AXES) { const n = labelName(ax[a]); if (n != null) axisLabels[a] = n; }
  const s = { tasks: ranked, view: config.view, settings: config.quick, status, accounts,
    presets: menu.map((p) => ({ id: p.id, name: p.name, accountId: p.accountId })),
    activePresetId: active ? active.id : '', configured, axisLabels };
  if (config.lastView) s.lastView = config.lastView;
  if (setup) s.setup = setup;
  return s;
}
