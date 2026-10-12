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
  });
  if (!isObj(s.view)) e.push('view missing');
  else for (const k of ['yaw', 'pitch', 'zoom']) if (typeof s.view[k] !== 'number') e.push(`view.${k} must be a number`);
  if (!isObj(s.settings)) e.push('settings missing');
  if (!isObj(s.status)) e.push('status missing');
  if (!Array.isArray(s.presets)) e.push('presets must be an array');
  if (typeof s.configured !== 'boolean') e.push('configured must be a boolean');
  return e;
}
