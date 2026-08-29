import { describe, expect, it } from 'vitest';
import { attendanceExceptions } from './exceptions.js';

describe('attendance exception classification', () => {
  it('surfaces every issue on a session with stable severity', () => {
    expect(attendanceExceptions({
      status: 'incomplete',
      lateMinutes: 12,
      earlyMinutes: 8,
      overtimeMinutes: 0,
    })).toEqual([
      { type: 'missed_checkout', severity: 'high', minutes: null },
      { type: 'late_arrival', severity: 'medium', minutes: 12 },
      { type: 'early_departure', severity: 'medium', minutes: 8 },
    ]);
  });

  it('does not flag a normal closed session', () => {
    expect(attendanceExceptions({
      status: 'closed',
      lateMinutes: 0,
      earlyMinutes: 0,
      overtimeMinutes: 0,
    })).toEqual([]);
  });
});
