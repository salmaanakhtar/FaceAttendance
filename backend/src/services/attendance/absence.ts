const DEFAULT_WORK_DAYS = ['mon', 'tue', 'wed', 'thu', 'fri'];
const WEEK_DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

export interface AbsenceEmployee {
  id: string;
  name: string;
  startDate: string;
  schedule?: Record<string, unknown>;
}

export interface AbsenceSession {
  employeeId: string;
  workDate: string;
}

export interface ApprovedLeave {
  employeeId: string;
  startDate: string;
  endDate: string;
}

export interface WorkerAbsence {
  employeeId: string;
  employeeName: string;
  absentDays: number;
  leaveDays: number;
  absentDates: string[];
}

export function isIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function addDays(date: string, days: number): string {
  const parsed = new Date(`${date}T00:00:00.000Z`);
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}

function workDays(schedule: Record<string, unknown> | undefined): Set<string> {
  const configured = schedule?.workDays;
  if (!Array.isArray(configured) || configured.length === 0) {
    return new Set(DEFAULT_WORK_DAYS);
  }
  return new Set(
    configured
      .filter((value): value is string => typeof value === 'string')
      .map((value) => value.toLowerCase().slice(0, 3)),
  );
}

/**
 * Deterministic absence calculation over completed calendar days.
 * Today is deliberately excluded because a worker may still punch later.
 */
export function calculateAbsence(input: {
  from: string;
  to: string;
  today: string;
  employees: AbsenceEmployee[];
  sessions: AbsenceSession[];
  approvedLeave: ApprovedLeave[];
}): { through: string; totalAbsentDays: number; totalLeaveDays: number; workers: WorkerAbsence[] } {
  const through = input.to < addDays(input.today, -1) ? input.to : addDays(input.today, -1);
  const attended = new Set(input.sessions.map((s) => `${s.employeeId}:${s.workDate}`));
  const workers = input.employees.map((employee) => {
    const scheduled = workDays(employee.schedule);
    const start = employee.startDate > input.from ? employee.startDate : input.from;
    const absentDates: string[] = [];
    let leaveDays = 0;
    if (through >= start) {
      for (let date = start; date <= through; date = addDays(date, 1)) {
        const weekday = WEEK_DAYS[new Date(`${date}T00:00:00.000Z`).getUTCDay()]!;
        if (!scheduled.has(weekday)) continue;
        if (attended.has(`${employee.id}:${date}`)) continue;
        const onLeave = input.approvedLeave.some(
          (leave) =>
            leave.employeeId === employee.id &&
            leave.startDate <= date &&
            leave.endDate >= date,
        );
        if (onLeave) leaveDays++;
        else absentDates.push(date);
      }
    }
    return {
      employeeId: employee.id,
      employeeName: employee.name,
      absentDays: absentDates.length,
      leaveDays,
      absentDates,
    };
  });
  return {
    through,
    totalAbsentDays: workers.reduce((sum, worker) => sum + worker.absentDays, 0),
    totalLeaveDays: workers.reduce((sum, worker) => sum + worker.leaveDays, 0),
    workers,
  };
}
