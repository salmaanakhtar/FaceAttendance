import type { PoolClient } from 'pg';
import { notFound } from '../../lib/errors.js';
import { localDate } from '../../lib/time.js';
import {
  DEFAULT_POLICY,
  classify,
  type Session,
  type SessionStats,
  type ShiftPolicy,
} from './engine.js';

/**
 * The subset of an attendance row needed to re-derive its stats. The org
 * timezone is joined in by the caller so manual edits and legacy rows can
 * never fall back to UTC by accident.
 */
export interface RecalculateRow {
  id: string;
  org_id: string;
  employee_id: string;
  work_date: string;
  check_in_at: string | null;
  check_out_at: string | null;
  check_in_source: string;
  check_out_source: string;
  status: string;
  break_minutes: number;
  policy: Record<string, unknown> | null;
  stats: Record<string, unknown> | null;
  note: string | null;
  timezone: string;
}

export interface DerivedSessionValues {
  workDate: string;
  status: Session['status'];
  policy: ShiftPolicy;
  stats: SessionStats;
}

/**
 * Pure derivation used by the SQL recalculation below and by unit tests.
 * The org timezone always wins over a stale snapshot timezone.
 */
export function deriveSessionValues(
  row: Pick<
    RecalculateRow,
    | 'id'
    | 'employee_id'
    | 'work_date'
    | 'check_in_at'
    | 'check_out_at'
    | 'check_in_source'
    | 'check_out_source'
    | 'status'
    | 'break_minutes'
    | 'policy'
    | 'note'
    | 'timezone'
  >,
  now: Date = new Date(),
  deriveWorkDate = true,
): DerivedSessionValues {
  const policy: ShiftPolicy = {
    ...DEFAULT_POLICY,
    ...((row.policy ?? {}) as Partial<ShiftPolicy>),
    timezone: row.timezone,
  };
  const checkIn = row.check_in_at ? new Date(row.check_in_at) : null;
  const checkOut = row.check_out_at ? new Date(row.check_out_at) : null;
  const workDate =
    deriveWorkDate && checkIn ? localDate(checkIn, row.timezone) : String(row.work_date);
  const status: Session['status'] = checkOut
    ? 'closed'
    : row.status === 'incomplete'
      ? 'incomplete'
      : 'open';

  const session: Session = {
    id: row.id,
    employeeId: row.employee_id,
    workDate,
    checkInAt: checkIn,
    checkOutAt: checkOut,
    checkInSource: row.check_in_source as Session['checkInSource'],
    checkOutSource: row.check_out_source as Session['checkOutSource'],
    status,
    breakMinutes: Number(row.break_minutes ?? 0),
    policy,
    stats: {} as SessionStats,
    note: row.note,
  };
  classify(session, now);

  return { workDate, status, policy, stats: session.stats };
}

/**
 * Recompute a session after a manual edit. This:
 * - derives work_date from the (possibly changed) check-in in org time;
 * - refreshes the policy snapshot with the org timezone;
 * - recomputes worked/late/early/overtime stats;
 * - returns the session to needs_review so an approved payroll period cannot
 *   silently retain edited hours.
 */
export async function recalculateSession(
  client: PoolClient,
  sessionId: string,
  orgId: string,
  options: { deriveWorkDate?: boolean } = {},
): Promise<RecalculateRow> {
  const selected = await client.query<RecalculateRow>(
    `SELECT s.*, o.timezone
     FROM attendance_sessions s
     JOIN orgs o ON o.id = s.org_id
     WHERE s.id = $1 AND s.org_id = $2 AND s.voided_at IS NULL
     FOR UPDATE`,
    [sessionId, orgId],
  );
  const row = selected.rows[0];
  if (!row) throw notFound('session not found');

  const derived = deriveSessionValues(row, new Date(), options.deriveWorkDate !== false);

  await client.query(
    `UPDATE attendance_sessions
     SET work_date = $2,
         policy = $3,
         stats = $4,
         status = $5,
         review_status = 'needs_review',
         reviewed_by = NULL,
         reviewed_at = NULL,
         updated_at = now()
     WHERE id = $1 AND org_id = $6`,
    [
      sessionId,
      derived.workDate,
      JSON.stringify(derived.policy),
      JSON.stringify(derived.stats),
      derived.status,
      orgId,
    ],
  );

  return {
    ...row,
    work_date: derived.workDate,
    status: derived.status,
    policy: derived.policy as unknown as Record<string, unknown>,
    stats: derived.stats as unknown as Record<string, unknown>,
  };
}
