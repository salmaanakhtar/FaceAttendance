/**
 * Attendance engine — PURE module. No I/O, no clocks of its own.
 * All inputs explicit → output is a pure function of inputs → deterministic,
 * unit-testable, reproducible. Server time is authoritative; timezone math is
 * done against the site timezone via lib/time.
 */

import {
  hmToMinutes,
  localDate,
  localTime,
  minutesToHm,
  startOfLocalDay,
} from '../../lib/time.js';

export interface ShiftPolicy {
  shiftStart: string; // "09:00" — local wall time
  shiftEnd: string; // "18:00"
  graceMinutes: number; // late = check-in past shiftStart + grace
  minIntervalMinutes: number; // min gap between two events of same direction
  overnightCheckoutCutoff: string; // "06:00": checkouts earlier than this attach to the open session
  shiftGapHours: number; // min gap before a same-day second shift is accepted
  breakAfterHours: number; // raw shift longer than this triggers break deduction
  breakMinutes: number; // auto-deducted break
  overnight: boolean; // shiftStart > shiftEnd (night shift)
  timezone: string; // IANA, used for work_date + classification
}

export const DEFAULT_POLICY: ShiftPolicy = {
  shiftStart: '09:00',
  shiftEnd: '18:00',
  graceMinutes: 5,
  minIntervalMinutes: 1,
  overnightCheckoutCutoff: '06:00',
  shiftGapHours: 4,
  breakAfterHours: 6,
  breakMinutes: 30,
  overnight: false,
  timezone: 'UTC',
};

export type SessionStatus = 'open' | 'closed' | 'incomplete';
export type SessionSource = 'auto' | 'manual';

export interface Session {
  id: string;
  employeeId: string;
  workDate: string;
  checkInAt: Date | null;
  checkOutAt: Date | null;
  checkInSource: SessionSource;
  checkOutSource: SessionSource;
  status: SessionStatus;
  breakMinutes: number;
  policy: ShiftPolicy;
  stats: SessionStats;
  note: string | null;
}

export interface SessionStats {
  workedMinutes: number;
  lateMinutes: number;
  earlyMinutes: number;
  overtimeMinutes: number;
  isLate: boolean;
  isEarly: boolean;
  hasOvertime: boolean;
}

export interface ScanEvent {
  id: string;
  scanTime: Date;
  directionHint: 'in' | 'out' | null;
}

export type EngineResult =
  | { action: 'check_in'; session: Session }
  | { action: 'check_out'; session: Session }
  | { action: 'duplicate'; reason: string }
  | { action: 'already_in'; message: string }
  | { action: 'already_out'; message: string }
  | { action: 'invalid'; message: string };

function minutesOf(date: Date, tz: string): number {
  return hmToMinutes(localTime(date, tz));
}

/** Shift end expressed on the "evening" axis: for overnight shifts add 1440. */
function shiftEndMinutes(policy: ShiftPolicy): number {
  const end = hmToMinutes(policy.shiftEnd);
  return policy.overnight ? end + 1440 : end;
}

export function classify(session: Session, now: Date): void {
  const p = session.policy;
  const stats: SessionStats = {
    workedMinutes: 0,
    lateMinutes: 0,
    earlyMinutes: 0,
    overtimeMinutes: 0,
    isLate: false,
    isEarly: false,
    hasOvertime: false,
  };
  const checkIn = session.checkInAt;
  const checkOut = session.checkOutAt;
  if (checkIn && checkOut && checkOut > checkIn) {
    stats.workedMinutes = Math.max(
      0,
      Math.round((checkOut.getTime() - checkIn.getTime()) / 60000) - session.breakMinutes,
    );
  }
  if (checkIn) {
    const inMin = minutesOf(checkIn, p.timezone);
    const start = hmToMinutes(p.shiftStart) + p.graceMinutes;
    if (!p.overnight) {
      if (inMin > start) {
        stats.lateMinutes = inMin - start;
        stats.isLate = true;
      }
    } else {
      // night shift: check-in between shiftStart (evening) and end+1440 (next morning)
      const startMin = hmToMinutes(p.shiftStart);
      const shiftedIn = inMin < hmToMinutes(p.shiftEnd) ? inMin + 1440 : inMin;
      if (shiftedIn > startMin + p.graceMinutes && shiftedIn <= startMin + 1440) {
        stats.lateMinutes = shiftedIn - (startMin + p.graceMinutes);
        stats.isLate = true;
      }
    }
  }
  if (checkOut) {
    const outMin = minutesOf(checkOut, p.timezone);
    const end = shiftEndMinutes(p);
    if (!p.overnight) {
      if (outMin < end) {
        stats.earlyMinutes = end - outMin;
        stats.isEarly = true;
      } else if (outMin > end) {
        stats.overtimeMinutes = outMin - end;
        stats.hasOvertime = true;
      }
    } else {
      const shiftedOut = outMin < hmToMinutes(p.shiftEnd) ? outMin + 1440 : outMin;
      if (shiftedOut < end) {
        stats.earlyMinutes = end - shiftedOut;
        stats.isEarly = true;
      } else if (shiftedOut > end) {
        stats.overtimeMinutes = shiftedOut - end;
        stats.hasOvertime = true;
      }
    }
  }
  session.stats = stats;
}

/**
 * Core decision: process one scan event against existing state.
 * @param employeeId who scanned
 * @param event the raw scan (server scanTime!)
 * @param openSession currently open session, if any
 * @param lastSession most recent session overall (open or closed), if any
 * @param lastEventAt time of the employee's previous scan event (for min-interval)
 * @param policy the employee's shift policy snapshot
 */
export function processScan(params: {
  employeeId: string;
  event: ScanEvent;
  openSession: Session | null;
  lastSession: Session | null;
  lastEventAt: Date | null;
  policy: ShiftPolicy;
}): EngineResult {
  const { employeeId, event, openSession, lastSession, lastEventAt, policy } = params;
  const t = event.scanTime;

  const duplicateGuard = (): boolean => {
    if (!lastEventAt) return false;
    const gapMin = (t.getTime() - lastEventAt.getTime()) / 60000;
    return gapMin >= 0 && gapMin < policy.minIntervalMinutes;
  };

  // --- No open session: this is (normally) a check-in ---
  if (!openSession) {
    if (event.directionHint === 'out') {
      return { action: 'already_out', message: 'no open session to check out of' };
    }
    if (duplicateGuard()) {
      return { action: 'duplicate', reason: 'within min interval of previous event' };
    }
    // same-day second shift must clear the gap threshold
    if (
      lastSession &&
      lastSession.status === 'closed' &&
      lastSession.workDate === localDate(t, policy.timezone) &&
      lastSession.checkOutAt
    ) {
      const gapHours = (t.getTime() - lastSession.checkOutAt.getTime()) / 3600000;
      if (gapHours < policy.shiftGapHours) {
        return { action: 'duplicate', reason: 'already checked out this shift period' };
      }
    }
    const session: Session = {
      id: `pending:${employeeId}:${t.getTime()}`,
      employeeId,
      workDate: localDate(t, policy.timezone),
      checkInAt: t,
      checkOutAt: null,
      checkInSource: 'auto',
      checkOutSource: 'auto',
      status: 'open',
      breakMinutes: 0,
      policy,
      stats: {
        workedMinutes: 0,
        lateMinutes: 0,
        earlyMinutes: 0,
        overtimeMinutes: 0,
        isLate: false,
        isEarly: false,
        hasOvertime: false,
      },
      note: null,
    };
    return { action: 'check_in', session };
  }

  // --- Open session exists: this should be a check-out ---
  if (event.directionHint === 'in') {
    if (duplicateGuard()) {
      return { action: 'duplicate', reason: 'within min interval of previous event' };
    }
    return { action: 'already_in', message: 'employee already checked in' };
  }

  // checkout
  if (t <= openSession.checkInAt!) {
    return { action: 'invalid', message: 'checkout earlier than check-in' };
  }
  if (duplicateGuard()) {
    return { action: 'duplicate', reason: 'within min interval of previous event' };
  }
  const closed: Session = {
    ...openSession,
    checkOutAt: t,
    checkOutSource: 'auto',
    status: 'closed',
    breakMinutes:
      openSession.checkInAt && (t.getTime() - openSession.checkInAt.getTime()) / 3600000 >=
        policy.breakAfterHours
        ? policy.breakMinutes
        : 0,
  };
  classify(closed, t);
  return { action: 'check_out', session: closed };
}

/** Rollover: an open session whose check-in local day is not today becomes incomplete. */
export function flagMissedCheckouts(sessions: Session[], now: Date): Session[] {
  const out: Session[] = [];
  for (const s of sessions) {
    if (s.status !== 'open') continue;
    const today = localDate(now, s.policy.timezone);
    if (s.workDate < today) {
      out.push({
        ...s,
        status: 'incomplete',
        note: 'missed checkout — closed by rollover',
      });
    }
  }
  return out;
}

/** Duration string helpers reused by exports. */
export function workedText(s: Session): string {
  if (!s.checkInAt || !s.checkOutAt) return '';
  const raw = s.checkOutAt.getTime() - s.checkInAt.getTime() - s.breakMinutes * 60000;
  const total = Math.max(0, raw);
  const h = Math.floor(total / 3600000);
  const m = Math.round((total % 3600000) / 60000);
  return `${h}h ${m}m`;
}

/** Local "start of work date" for a session's day — used for overnight grouping. */
export function sessionDayStart(s: Session): Date {
  return startOfLocalDay(s.checkInAt ?? new Date(0), s.policy.timezone);
}

export { minutesToHm };
