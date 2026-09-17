export interface PayrollWorker {
  id: string;
  name: string;
  code: string;
  schedule: Record<string, unknown>;
}

export interface PayrollSession {
  employeeId: string;
  date: string;
  inAt: string | null;
  outAt: string | null;
  status: string;
  workedMinutes: number;
  overtimeMinutes: number;
  breakMinutes: number;
}

export interface PayAdjustment {
  employeeId: string;
  holidayPay: number;
  otherPay: number;
  uif: number;
  otherDeductions: number;
}

export function money(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function configured(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

export function calculatePayroll(workers: PayrollWorker[], sessions: PayrollSession[], adjustments: PayAdjustment[] = []) {
  return workers.map(worker => {
    const shifts = sessions.filter(s => s.employeeId === worker.id);
    // Open/incomplete shifts cannot supply final hours for payroll.
    const completed = shifts.filter(s => s.status === 'closed' && s.inAt && s.outAt);
    const workedMinutes = completed.reduce((sum, s) => sum + Math.max(0, s.workedMinutes), 0);
    const overtimeMinutes = completed.reduce((sum, s) => sum + Math.max(0, Math.min(s.workedMinutes, s.overtimeMinutes)), 0);
    const regularMinutes = workedMinutes - overtimeMinutes;
    const rate = configured(worker.schedule.hourlyRate);
    const multiplier = configured(worker.schedule.overtimeMultiplier);
    const adjustment = adjustments.find(a => a.employeeId === worker.id);
    const holidayPay = adjustment?.holidayPay ?? 0;
    const otherPay = adjustment?.otherPay ?? 0;
    const uif = adjustment?.uif ?? 0;
    const otherDeductions = adjustment?.otherDeductions ?? 0;
    const regularPay = rate === null ? null : money(regularMinutes / 60 * rate);
    const overtimePay = overtimeMinutes === 0 ? 0
      : rate === null || multiplier === null ? null : money(overtimeMinutes / 60 * rate * multiplier);
    const gross = regularPay === null || overtimePay === null ? null
      : money(regularPay + overtimePay + holidayPay + otherPay);
    const deductions = money(uif + otherDeductions);
    return { ...worker, shifts, workedMinutes, regularMinutes, overtimeMinutes,
      unresolvedShifts: shifts.length - completed.length,
      rate, multiplier, regularPay, overtimePay, holidayPay, otherPay, uif,
      otherDeductions, gross, deductions, net: gross === null ? null : money(gross - deductions) };
  });
}

export type PayrollRow = ReturnType<typeof calculatePayroll>[number];
export interface PayrollReport {
  organization: string;
  timezone: string;
  from: string;
  to: string;
  workers: PayrollRow[];
}
