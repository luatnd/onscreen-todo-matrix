import { test, expect } from 'vitest';
import { channel, rgbColor, urgencyColor, taskColor } from '../src/color.js';

test('channel floor 55, ceiling 255, clamped', () => {
  expect(channel(0)).toBe(55);
  expect(channel(1)).toBe(255);
  expect(channel(2)).toBe(255);
  expect(channel(-1)).toBe(55);
});
test('urgent + valuable + easy is white #FFF', () => {
  expect(rgbColor({ urgency: 1, effort: 0, value: 1 })).toBe('rgba(255,255,255,1)');
});
test('thankless is dark #373737', () => {
  expect(rgbColor({ urgency: 0, effort: 1, value: 0 }, 0.5)).toBe('rgba(55,55,55,0.5)');
});
test('urgency mode endpoints', () => {
  expect(urgencyColor(0)).toBe('rgba(91,123,181,1)');
  expect(urgencyColor(1)).toBe('rgba(229,72,77,1)');
  expect(taskColor({ urgency: 1, effort: 0, value: 0 }, 'u')).toBe('rgba(229,72,77,1)');
});
