const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const unit = (v) => typeof v === 'number' && v >= 0 && v <= 1;

/** Returns a list of problems; empty means the payload matches the Swift RenderState contract. */
export function validateState(s) {
  if (!isObj(s)) return ['state is not an object'];
  const e = [];
  if (!Array.isArray(s.tasks)) e.push('tasks must be an array');
  else s.tasks.forEach((t, i) => {
    if (typeof t.key !== 'string') e.push(`tasks[${i}].key must be a string`);
    if (typeof t.summary !== 'string') e.push(`tasks[${i}].summary must be a string`);
    for (const k of ['value', 'effort', 'urgency']) if (!unit(t[k])) e.push(`tasks[${i}].${k} must be a number in 0..1`);
    if (!isObj(t.missing)) e.push(`tasks[${i}].missing must be an object`);
    if (typeof t.score !== 'number') e.push(`tasks[${i}].score must be a number`);
    if (t.derived != null) {
      const d = t.derived;
      if (!isObj(d)) e.push(`tasks[${i}].derived must be an object`);
      else {
        if (d.kind !== 'timeline' && d.kind !== 'logged') e.push(`tasks[${i}].derived.kind must be timeline or logged`);
        if (typeof d.amount !== 'number' || !Number.isFinite(d.amount)) e.push(`tasks[${i}].derived.amount must be a number`);
        if (d.unit !== 'h' && d.unit !== 'd') e.push(`tasks[${i}].derived.unit must be h or d`);
      }
    }
  });
  if (!isObj(s.view)) e.push('view missing');
  else for (const k of ['yaw', 'pitch', 'zoom']) if (typeof s.view[k] !== 'number') e.push(`view.${k} must be a number`);
  if (s.lastView != null) {
    if (!isObj(s.lastView)) e.push('lastView must be an object');
    else for (const k of ['yaw', 'pitch', 'zoom']) if (typeof s.lastView[k] !== 'number') e.push(`lastView.${k} must be a number`);
  }
  if (!isObj(s.settings)) e.push('settings missing');
  if (!isObj(s.status)) e.push('status missing');
  if (!Array.isArray(s.accounts)) e.push('accounts must be an array');
  else s.accounts.forEach((a, i) => {
    if (!isObj(a)) { e.push(`accounts[${i}] must be an object`); return; }
    for (const k of ['id', 'name', 'color']) if (typeof a[k] !== 'string') e.push(`accounts[${i}].${k} must be a string`);
    if (typeof a.error !== 'boolean') e.push(`accounts[${i}].error must be a boolean`);
  });
  if (!Array.isArray(s.presets)) e.push('presets must be an array');
  else s.presets.forEach((p, i) => {
    if (!isObj(p)) { e.push(`presets[${i}] must be an object`); return; }
    for (const k of ['id', 'name', 'accountId']) if (typeof p[k] !== 'string') e.push(`presets[${i}].${k} must be a string`);
  });
  if (typeof s.activePresetId !== 'string') e.push('activePresetId must be a string');
  if (typeof s.configured !== 'boolean') e.push('configured must be a boolean');
  if (!isObj(s.axisLabels)) e.push('axisLabels must be an object');
  else for (const k of ['value', 'effort', 'urgency']) {
    if (s.axisLabels[k] != null && typeof s.axisLabels[k] !== 'string') e.push(`axisLabels.${k} must be a string`);
  }
  if (s.setup != null && (!isObj(s.setup) || typeof s.setup.message !== 'string' || typeof s.setup.tab !== 'string')) {
    e.push('setup must have string message and tab');
  }
  return e;
}
