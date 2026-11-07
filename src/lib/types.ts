export type Employee = {
  id: string;
  employeeCode: string;
  name: string;
  email: string | null;
  phone: string | null;
  status: string;
  enrolled: boolean;
  schedule: Record<string, any>;
  enrolledAt?: string | null;
};

export type Session = {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  workDate: string;
  checkInAt: string | null;
  checkOutAt: string | null;
  status: 'open' | 'closed' | 'incomplete';
  workedMinutes: number;
  lateMinutes: number;
  earlyMinutes: number;
  overtimeMinutes: number;
  reviewStatus: string;
  note: string | null;
  corrected: boolean;
};

export type Leave = {
  id: string;
  employeeId: string;
  employeeName: string;
  leaveType: string;
  status: string;
  startDate: string;
  endDate: string;
  note: string | null;
};

export type PeriodProgress = {
  workedMinutes: number;
  projectedMinutes: number;
  thresholdMinutes: number;
  status: 'ok' | 'projected' | 'exceeded';
};

export type OvertimeWorker = {
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  weekly: PeriodProgress;
  monthly: PeriodProgress;
  status: 'ok' | 'projected' | 'exceeded';
  currentWeeklyHours: number;
  suggestedWeeklyHours: number;
  suggestedPerDayHours: number;
  suggestionReason: string | null;
};

export type OvertimeReport = {
  settings: { enabled: boolean; weeklyHours: number; monthlyHours: number };
  today: string;
  weekStart: string;
  weekEnd: string;
  monthStart: string;
  monthEnd: string;
  workers: OvertimeWorker[];
  alerts: OvertimeWorker[];
};

export type AuditEvent = {
  id: string;
  actorType: string;
  actorId: string;
  action: string;
  targetType: string | null;
  targetId: string | null;
  details: Record<string, unknown> | null;
  createdAt: string;
};

export type PayrollWorker = {
  id: string;
  name: string;
  code: string;
  workedMinutes: number;
  rate: number;
  gross: number;
  uif: number;
  otherDeductions: number;
  net: number;
  unresolvedShifts?: number;
};

export type PayrollReport = {
  from: string;
  to: string;
  workers: PayrollWorker[];
  organization?: string;
};
