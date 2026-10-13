/** A missing axis value draws the task hollow at that axis' default position. */
export const isHollow = (t) => !!(t.missing && (t.missing.value || t.missing.effort || t.missing.urgency));

/** Score descending, then key: the "1 of N" order inside a stack and the Tab order. */
export const byScoreThenKey = (a, b) => b.score - a.score || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);

const q = (v) => Math.round(v * 1e6);
/** Same (value, effort, urgency) and hollow state = same stack (D27). Data-based, so stable while rotating. */
export const stackKey = (t) => `${q(t.value)},${q(t.effort)},${q(t.urgency)},${isHollow(t) ? 'h' : 's'}`;

/** Groups coincident tasks; each stack is ordered by byScoreThenKey (the first member is the lead). */
export function groupStacks(tasks) {
  const m = new Map();
  for (const t of tasks) {
    const k = stackKey(t);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(t);
  }
  return [...m.values()].map((ts) => ts.sort(byScoreThenKey));
}
