import { describe, expect, it } from 'vitest';
import {
  DEFAULT_OVERTIME_SETTINGS,
  addDays,
  buildOvertimeAlert,
  mondayOf,
  progressForPeriod,
  readOvertimeSettings,
} from './overtime.js';

const schedule = { workDays: ['mon', 'tue', 'wed', 'thu', 'fri'], hoursPerWeek: 45 };

describe('overtime settings', () => {
  it('uses the requested defaults', () => {
    expect(readOvertimeSettings(null)).toEqual(DEFAULT_OVERTIME_SETTINGS);
    expect(DEFAULT_OVERTIME_SETTINGS.weeklyHours).toBe(46);
    expect(DEFAULT_OVERTIME_SETTINGS.monthlyHours).toBe(184);
  });

  it('reads, clamps, and keeps enabled false', () => {
    expect(
      readOvertimeSettings({ overtime: { enabled: false, weeklyHours: 0, monthlyHours: 999 } }),
    ).toEqual({ enabled: false, weeklyHours: 1, monthlyHours: 744 });
  });
});

describe('overtime projection', () => {
  it('finds the Monday of a week', () => {
    expect(mondayOf('2026-11-05')).toBe('2026-11-02');
    expect(addDays('2026-11-02', 6)).toBe('2026-11-08');
  });

  it('projects a crossing from the current pace', () => {
    const result = progressForPeriod({
      workedMinutes: 30 * 60,
      schedule,
      start: '2026-11-02',
      end: '2026-11-08',
      today: '2026-11-04',
      thresholdHours: 46,
    });
    expect(result.elapsedScheduledDays).toBe(3);
    expect(result.remainingScheduledDays).toBe(2);
    expect(result.projectedMinutes).toBe(50 * 60);
    expect(result.status).toBe('projected');
  });

  it('marks an actual crossing as exceeded', () => {
    const result = progressForPeriod({
      workedMinutes: 47 * 60,
      schedule,
      start: '2026-11-02',
      end: '2026-11-08',
      today: '2026-11-06',
      thresholdHours: 46,
    });
    expect(result.status).toBe('exceeded');
  });

  it('does not invent a projection before any work is recorded', () => {
    const result = progressForPeriod({
      workedMinutes: 0,
      schedule,
      start: '2026-11-02',
      end: '2026-11-08',
      today: '2026-11-02',
      thresholdHours: 46,
    });
    expect(result.projectedMinutes).toBe(0);
    expect(result.status).toBe('ok');
  });
});

describe('schedule advice', () => {
  it('reduces the weekly schedule by the projected overage', () => {
    const alert = buildOvertimeAlert({
      employee: { id: 'e1', name: 'Worker', employeeCode: '001', schedule },
      weeklyWorkedMinutes: 30 * 60,
      monthlyWorkedMinutes: 18 * 60,
      settings: { enabled: true, weeklyHours: 46, monthlyHours: 184 },
      weekStart: '2026-11-02',
      weekEnd: '2026-11-08',
      monthStart: '2026-11-01',
      monthEnd: '2026-11-30',
      today: '2026-11-04',
    });
    expect(alert.weekly.status).toBe('projected');
    expect(alert.suggestedWeeklyHours).toBe(41);
    expect(alert.suggestedPerDayHours).toBe(8.2);
    expect(alert.suggestionReason).toBe('week');
  });
});
