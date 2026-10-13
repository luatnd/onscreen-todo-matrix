/** Presentation of an effort derived from logged time or the timeline window (D21). */
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** One decimal, no trailing ".0". */
export const formatAmount = (n) => String(Math.round(n * 10) / 10);

/** "2026-10-01" → "Oct 1"; anything else → null. */
function shortDate(s) {
  const m = typeof s === 'string' && /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  return m && MONTHS[Number(m[2]) - 1] ? `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}` : null;
}

/** Card line, e.g. "Effort ≈ 56 h from timeline (Oct 1 → Oct 10)". */
export function describeDerived(d) {
  const head = `Effort ≈ ${formatAmount(d.amount)} ${d.unit}`;
  if (d.kind === 'logged') return `${head} from logged time`;
  const a = shortDate(d.from), b = shortDate(d.to);
  const win = a && b ? ` (${a} → ${b})` : '';
  return `${head} from timeline${win}${d.clamped ? ' · ≥ max' : ''}`;
}

/** Tooltip suffix, e.g. " · ≈56 h"; empty for tasks with a real estimate. */
export const tipSuffix = (t) => (t.derived ? ` · ≈${formatAmount(t.derived.amount)} ${t.derived.unit}` : '');
