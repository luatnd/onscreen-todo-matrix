/** Search matcher (D38): key, summary, parent key or parent summary; `query` is already lower-cased and trimmed. */
export const normalizeQuery = (s) => s.toLowerCase().trim();

export function matchesQuery(t, query) {
  if (!query) return true;
  const p = t.parent;
  return `${t.key} ${t.summary} ${p ? `${p.key} ${p.summary}` : ''}`.toLowerCase().includes(query);
}

/** Text shown in the sync area while a query is active (D39). */
export const matchLabel = (n) => (n === 0 ? 'No matches' : n === 1 ? '1 match' : `${n} matches`);
