import { describe, expect, it } from 'vitest';
import { calculateAbsence } from './absence.js';

describe('absence calculation', () => {
  it('counts only completed scheduled days without attendance or approved leave', () => {
    const result = calculateAbsence({
      from: '2026-08-31',
      to: '2026-09-04',
      today: '2026-09-04',
      employees: [
        { id: 'e1', name: 'Worker', startDate: '2026-08-01', schedule: {} },
      ],
      sessions: [{ employeeId: 'e1', workDate: '2026-08-31' }],
      approvedLeave: [
        { employeeId: 'e1', startDate: '2026-09-01', endDate: '2026-09-01' },
      ],
    });

    expect(result.through).toBe('2026-09-03');
    expect(result.totalLeaveDays).toBe(1);
    expect(result.totalAbsentDays).toBe(2);
    expect(result.workers[0]?.absentDates).toEqual(['2026-09-02', '2026-09-03']);
  });

  it('uses configured work days and never counts dates before employment', () => {
    const result = calculateAbsence({
      from: '2026-08-31',
      to: '2026-09-07',
      today: '2026-09-08',
      employees: [
        {
          id: 'e1',
          name: 'Part time',
          startDate: '2026-09-02',
          schedule: { workDays: ['wed', 'fri'] },
        },
      ],
      sessions: [],
      approvedLeave: [],
    });

    expect(result.workers[0]?.absentDates).toEqual(['2026-09-02', '2026-09-04']);
  });
});
