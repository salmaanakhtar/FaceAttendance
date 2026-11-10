export type AttendanceExceptionType =
  | 'missed_checkout'
  | 'late_arrival'
  | 'early_departure'
  | 'overtime';

export interface ExceptionSource {
  status: string;
  lateMinutes: number;
  earlyMinutes: number;
  overtimeMinutes: number;
}

export interface AttendanceException {
  type: AttendanceExceptionType;
  severity: 'high' | 'medium' | 'low';
  minutes: number | null;
}

/** Pure, deterministic exception classification for manager review. */
export function attendanceExceptions(source: ExceptionSource): AttendanceException[] {
  const out: AttendanceException[] = [];
  if (source.status === 'incomplete') {
    out.push({ type: 'missed_checkout', severity: 'high', minutes: null });
  }
  if (source.lateMinutes > 0) {
    out.push({ type: 'late_arrival', severity: 'medium', minutes: source.lateMinutes });
  }
  if (source.earlyMinutes > 0) {
    out.push({ type: 'early_departure', severity: 'medium', minutes: source.earlyMinutes });
  }
  if (source.overtimeMinutes > 0) {
    out.push({ type: 'overtime', severity: 'low', minutes: source.overtimeMinutes });
  }
  return out;
}
