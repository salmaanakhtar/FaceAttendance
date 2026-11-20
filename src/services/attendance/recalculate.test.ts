import { describe, expect, it } from 'vitest';
import { deriveSessionValues, type RecalculateRow } from './recalculate.js';

const base: RecalculateRow = {
  id: 'session-1',
  org_id: 'org-1',
  employee_id: 'employee-1',
  work_date: '2026-11-05',
  check_in_at: '2026-11-05T07:00:00.000Z',
  check_out_at: '2026-11-05T16:30:00.000Z',
  check_in_source: 'manual',
  check_out_source: 'manual',
  status: 'closed',
  break_minutes: 0,
  policy: {
    shiftStart: '09:00',
    shiftEnd: '18:00',
    graceMinutes: 5,
    breakAfterHours: 6,
    breakMinutes: 30,
    overnight: false,
    timezone: 'UTC',
  },
  stats: null,
  note: null,
  timezone: 'Africa/Johannesburg',
};

describe('attendance recalculation', () => {
  it('derives work_date from the check-in in the org timezone', () => {
    const result = deriveSessionValues({
      ...base,
      check_in_at: '2026-11-05T22:30:00.000Z', // 00:30 on 6 Nov in Johannesburg
      check_out_at: '2026-11-06T07:00:00.000Z',
    });
    expect(result.workDate).toBe('2026-11-06');
  });

  it('always uses the org timezone instead of a stale policy snapshot', () => {
    const result = deriveSessionValues(base);
    expect(result.policy.timezone).toBe('Africa/Johannesburg');
  });

  it('recomputes worked and overtime minutes from edited times', () => {
    const result = deriveSessionValues(base);
    expect(result.stats.workedMinutes).toBe(570); // 09:00–18:30 local
    expect(result.stats.overtimeMinutes).toBe(30);
    expect(result.stats.isLate).toBe(false);
  });

  it('keeps an explicitly edited work_date when requested', () => {
    const result = deriveSessionValues(
      {
        ...base,
        check_in_at: '2026-11-05T22:30:00.000Z',
        work_date: '2026-11-05',
      },
      new Date(),
      false,
    );
    expect(result.workDate).toBe('2026-11-05');
  });

  it('keeps incomplete sessions incomplete and open sessions open', () => {
    expect(
      deriveSessionValues({ ...base, status: 'incomplete', check_out_at: null }).status,
    ).toBe('incomplete');
    expect(
      deriveSessionValues({ ...base, status: 'open', check_out_at: null }).status,
    ).toBe('open');
    expect(deriveSessionValues(base).status).toBe('closed');
  });
});
