import { test, expect } from 'vitest';
import { matchesQuery, normalizeQuery, matchLabel } from '../src/search.js';

const t = { key: 'PA-43', summary: 'Find out collab solution', parent: { key: 'PA-40', summary: 'Clavis project deal' } };

test('empty query matches everything', () => {
  expect(matchesQuery(t, '')).toBe(true);
});
test('matches key, summary, parent key and parent summary case-insensitively', () => {
  for (const q of ['pa-43', 'COLLAB', 'pa-40', 'clavis']) expect(matchesQuery(t, normalizeQuery(q)), q).toBe(true);
});
test('no false match; tasks without a parent still work', () => {
  expect(matchesQuery(t, 'zzz')).toBe(false);
  expect(matchesQuery({ key: 'A-1', summary: 'x' }, 'clavis')).toBe(false);
  expect(matchesQuery({ key: 'A-1', summary: 'x' }, 'a-1')).toBe(true);
});
test('label', () => {
  expect(matchLabel(0)).toBe('No matches');
  expect(matchLabel(1)).toBe('1 match');
  expect(matchLabel(5)).toBe('5 matches');
});
