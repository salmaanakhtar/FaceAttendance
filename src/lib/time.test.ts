import { describe, expect, it } from 'vitest';
import { localDate, localTime } from './time.js';

describe('organization-local dates', () => {
  it('rolls the work date over at local midnight, not UTC midnight', () => {
    const lateUtc = new Date('2026-11-05T22:30:00.000Z');
    expect(localDate(lateUtc, 'Africa/Johannesburg')).toBe('2026-11-06');
    expect(localTime(lateUtc, 'Africa/Johannesburg')).toBe('00:30');
  });

  it('keeps the previous local day before midnight', () => {
    const beforeMidnight = new Date('2026-11-05T21:59:00.000Z');
    expect(localDate(beforeMidnight, 'Africa/Johannesburg')).toBe('2026-11-05');
    expect(localTime(beforeMidnight, 'Africa/Johannesburg')).toBe('23:59');
  });
});
