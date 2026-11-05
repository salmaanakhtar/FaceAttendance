/**
 * Overtime projection and schedule advice.
 *
 * These are pure functions. The route supplies worked minutes for the current
 * week/month and the employee's schedule; all date math uses calendar strings
 * so a server in another timezone cannot shift the report.
 */

export interface OvertimeSettings {
  enabled: boolean;
  weeklyHours: number;
  monthlyHours: number;
}

export const DEFAULT_OVERTIME_SETTINGS: OvertimeSettings = {
  enabled: true,
  weeklyHours: 46,
  monthlyHours: 184,
};

export interface OvertimeSchedule {
  workDays?: string[];
  hoursPerWeek?: number | string;
}

export type PeriodStatus = 'ok' | 'projected' | 'exceeded';

export interface PeriodProgress {
  workedMinutes: number;
  projectedMinutes: number;
  thresholdMinutes: number;
  status: PeriodStatus;
  scheduledDays: number;
  elapsedScheduledDays: number;
  remainingScheduledDays: number;
}

export type SuggestionReason = 'week' | 'month' | 'both' | null;

export interface OvertimeAlert {
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  weekly: PeriodProgress;
  monthly: PeriodProgress;
  status: PeriodStatus;
  currentWeeklyHours: number;
  suggestedWeeklyHours: number;
  suggestedPerDayHours: number;
  suggestionReason: SuggestionReason;
}

const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

function parseDate(value: string): Date {
  return new Date(`${value}T12:00:00.000Z`);
}

export function addDays(value: string, days: number): string {
  const date = parseDate(value);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function weekdayOf(value: string): string {
  const day = parseDate(value).getUTCDay();
  return ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'][day]!;
}

export function mondayOf(value: string): string {
  const day = parseDate(value).getUTCDay();
  const offset = (day + 6) % 7;
  return addDays(value, -offset);
}

export function enumerateDates(start: string, end: string): string[] {
  const dates: string[] = [];
  for (let cursor = start; cursor <= end; cursor = addDays(cursor, 1)) {
    dates.push(cursor);
  }
  return dates;
}

export function normalizeWorkDays(value: unknown): string[] {
  const days = Array.isArray(value)
    ? [...new Set(value.filter((day): day is string => typeof day === 'string' && WEEKDAYS.includes(day)))]
    : [];
  return days.length ? days : ['mon', 'tue', 'wed', 'thu', 'fri'];
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function readOvertimeSettings(settings: unknown): OvertimeSettings {
  const raw = (settings as { overtime?: Partial<OvertimeSettings> } | null)?.overtime ?? {};
  const weekly = Number(raw.weeklyHours ?? DEFAULT_OVERTIME_SETTINGS.weeklyHours);
  const monthly = Number(raw.monthlyHours ?? DEFAULT_OVERTIME_SETTINGS.monthlyHours);
  return {
    enabled: raw.enabled !== false,
    weeklyHours: clamp(Number.isFinite(weekly) ? weekly : 46, 1, 168),
    monthlyHours: clamp(Number.isFinite(monthly) ? monthly : 184, 1, 744),
  };
}

/**
 * Project end-of-period hours from the pace so far. If the employee has no
 * worked time yet, the projection is zero rather than inventing a schedule.
 */
export function progressForPeriod(params: {
  workedMinutes: number;
  schedule: OvertimeSchedule;
  start: string;
  end: string;
  today: string;
  thresholdHours: number;
}): PeriodProgress {
  const workDays = normalizeWorkDays(params.schedule.workDays);
  const scheduled = enumerateDates(params.start, params.end).filter((date) =>
    workDays.includes(weekdayOf(date)),
  );
  const elapsedScheduledDays = scheduled.filter((date) => date <= params.today).length;
  const remainingScheduledDays = Math.max(0, scheduled.length - elapsedScheduledDays);
  const worked = Math.max(0, Math.round(params.workedMinutes));
  const projected =
    elapsedScheduledDays > 0 && worked > 0
      ? Math.round(worked + (worked / elapsedScheduledDays) * remainingScheduledDays)
      : 0;
  const thresholdMinutes = Math.round(params.thresholdHours * 60);

  const status: PeriodStatus =
    worked >= thresholdMinutes
      ? 'exceeded'
      : projected > thresholdMinutes
        ? 'projected'
        : 'ok';

  return {
    workedMinutes: worked,
    projectedMinutes: projected,
    thresholdMinutes,
    status,
    scheduledDays: scheduled.length,
    elapsedScheduledDays,
    remainingScheduledDays,
  };
}

export function buildOvertimeAlert(params: {
  employee: { id: string; name: string; employeeCode: string; schedule: OvertimeSchedule };
  weeklyWorkedMinutes: number;
  monthlyWorkedMinutes: number;
  settings: OvertimeSettings;
  weekStart: string;
  weekEnd: string;
  monthStart: string;
  monthEnd: string;
  today: string;
}): OvertimeAlert {
  const { employee, settings } = params;
  const weekly = progressForPeriod({
    workedMinutes: params.weeklyWorkedMinutes,
    schedule: employee.schedule,
    start: params.weekStart,
    end: params.weekEnd,
    today: params.today,
    thresholdHours: settings.weeklyHours,
  });
  const monthly = progressForPeriod({
    workedMinutes: params.monthlyWorkedMinutes,
    schedule: employee.schedule,
    start: params.monthStart,
    end: params.monthEnd,
    today: params.today,
    thresholdHours: settings.monthlyHours,
  });

  const workDays = normalizeWorkDays(employee.schedule.workDays);
  const currentWeeklyHours = Number(employee.schedule.hoursPerWeek);
  const safeCurrent =
    Number.isFinite(currentWeeklyHours) && currentWeeklyHours >= 0
      ? currentWeeklyHours
      : workDays.length * 8;

  const weeklyOverMinutes = Math.max(0, weekly.projectedMinutes - weekly.thresholdMinutes);
  const monthlyOverMinutes = Math.max(0, monthly.projectedMinutes - monthly.thresholdMinutes);
  // A monthly overage is spread over roughly 4.35 weeks to keep the weekly
  // suggestion in the same unit as the employee's schedule.
  const weeklyOverageMinutes = Math.max(weeklyOverMinutes, monthlyOverMinutes / 4.35);
  const suggestedWeeklyHours = Math.max(0, safeCurrent - weeklyOverageMinutes / 60);

  const suggestionReason: SuggestionReason =
    weeklyOverMinutes > 0 && monthlyOverMinutes > 0
      ? 'both'
      : weeklyOverMinutes > 0
        ? 'week'
        : monthlyOverMinutes > 0
          ? 'month'
          : null;

  const status: PeriodStatus =
    weekly.status === 'exceeded' || monthly.status === 'exceeded'
      ? 'exceeded'
      : weekly.status === 'projected' || monthly.status === 'projected'
        ? 'projected'
        : 'ok';

  return {
    employeeId: employee.id,
    employeeName: employee.name,
    employeeCode: employee.employeeCode,
    weekly,
    monthly,
    status,
    currentWeeklyHours: round1(safeCurrent),
    suggestedWeeklyHours: round1(suggestedWeeklyHours),
    suggestedPerDayHours: round1(suggestedWeeklyHours / Math.max(workDays.length, 1)),
    suggestionReason,
  };
}
