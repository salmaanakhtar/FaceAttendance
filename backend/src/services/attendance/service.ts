/**
 * Attendance service — the only place that turns raw scan events into
 * sessions. Everything here is transactional and audited. The decision
 * logic itself lives in the pure engine module.
 */

import { pool, query, queryOne } from '../../db.js';
import { badRequest, conflict, notFound } from '../../lib/errors.js';
import { localDate } from '../../lib/time.js';
import { DEFAULT_POLICY, flagMissedCheckouts, processScan, type Session, type ShiftPolicy } from './engine.js';
import { audit } from '../audit.js';

export interface EmployeeRow {
  id: string;
  org_id: string;
  employee_code: string;
  name: string;
  email: string | null;
  status: string;
  schedule: Record<string, unknown>;
  face_template: Buffer | null;
}

export interface SessionRow {
  id: string;
  employee_id: string;
  work_date: string;
  check_in_at: string | null;
  check_out_at: string | null;
  check_in_source: string;
  check_out_source: string;
  status: string;
  break_minutes: number;
  policy: Record<string, unknown>;
  stats: Record<string, unknown>;
  note: string | null;
  corrected: boolean;
}

export function toEngineSession(r: SessionRow): Session {
  return {
    id: r.id,
    employeeId: r.employee_id,
    workDate: r.work_date,
    checkInAt: r.check_in_at ? new Date(r.check_in_at) : null,
    checkOutAt: r.check_out_at ? new Date(r.check_out_at) : null,
    checkInSource: r.check_in_source as Session['checkInSource'],
    checkOutSource: r.check_out_source as Session['checkOutSource'],
    status: r.status as Session['status'],
    breakMinutes: r.break_minutes,
    policy: { ...DEFAULT_POLICY, ...(r.policy as Partial<ShiftPolicy>) },
    stats: r.stats as unknown as Session['stats'],
    note: r.note,
  };
}

export function toEnginePolicy(schedule: Record<string, unknown>, tz: string): ShiftPolicy {
  return {
    ...DEFAULT_POLICY,
    timezone: tz,
    ...(schedule as Partial<ShiftPolicy>),
  };
}

export interface ScanIngest {
  deviceId: string;
  orgId: string;
  dedupeKey: string;
  deviceTime?: string | null;
  directionHint?: 'in' | 'out' | null;
  employeeId: string;
  confidence?: number | null;
  livenessScore?: number | null;
  faceHash?: string | null;
  syncState: 'live' | 'offline';
  deviceTimeDeltaMs?: number | null;
}

export interface ScanResult {
  action: string;
  employee: { id: string; name: string; employeeCode: string };
  session?: Session;
  status: 'checked_in' | 'checked_out' | 'none';
  scanTime: string;
  message?: string;
}

export async function ingestScan(input: ScanIngest): Promise<ScanResult> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // idempotency: dedupe key already seen → replay stored outcome
    const existing = await client.query(
      `SELECT action FROM scan_outcomes WHERE dedupe_key = $1`,
      [input.dedupeKey],
    );
    if (existing.rowCount) {
      await client.query('ROLLBACK');
      const outcome = existing.rows[0] as { action: string };
      const emp = await queryOne<{ id: string; name: string; employee_code: string }>(
        `SELECT id, name, employee_code FROM employees WHERE id = $1`,
        [input.employeeId],
      );
      return {
        action: outcome.action,
        employee: emp ? { id: emp.id, name: emp.name, employeeCode: emp.employee_code } : { id: input.employeeId, name: 'unknown', employeeCode: '' },
        status: outcome.action === 'check_in' ? 'checked_in' : outcome.action === 'check_out' ? 'checked_out' : 'none',
        scanTime: new Date().toISOString(),
        message: 'duplicate request — prior outcome returned',
      };
    }

    const scanTime = new Date();
    const employee = await client.query<EmployeeRow>(
      `SELECT id, org_id, employee_code, name, email, status, schedule, face_template
       FROM employees WHERE id = $1 AND org_id = $2 AND status = 'active'`,
      [input.employeeId, input.orgId],
    );
    if (!employee.rowCount) {
      await client.query('ROLLBACK');
      throw notFound('active employee not found');
    }
    const emp = employee.rows[0]!;
    const org = await queryOne<{ timezone: string }>('SELECT timezone FROM orgs WHERE id = $1', [input.orgId]);
    const tz = org?.timezone ?? 'UTC';
    const policy = toEnginePolicy(emp.schedule, tz);

    const ev = {
      id: input.dedupeKey,
      scanTime,
      directionHint: input.directionHint ?? null,
    };

    const openRow = await client.query<SessionRow>(
      `SELECT * FROM attendance_sessions
       WHERE employee_id = $1 AND status = 'open' AND voided_at IS NULL
       ORDER BY check_in_at DESC LIMIT 1`,
      [emp.id],
    );
    const lastRow = await client.query<SessionRow>(
      `SELECT * FROM attendance_sessions
       WHERE employee_id = $1 AND voided_at IS NULL
       ORDER BY check_in_at DESC LIMIT 1`,
      [emp.id],
    );
    const lastEvent = await client.query<{ scan_time: string }>(
      `SELECT scan_time FROM scan_events
       WHERE employee_id = $1 ORDER BY scan_time DESC LIMIT 1`,
      [emp.id],
    );

    const decision = processScan({
      employeeId: emp.id,
      event: ev,
      openSession: openRow.rows[0] ? toEngineSession(openRow.rows[0]) : null,
      lastSession: lastRow.rows[0] ? toEngineSession(lastRow.rows[0]) : null,
      lastEventAt: lastEvent.rows[0] ? new Date(lastEvent.rows[0].scan_time) : null,
      policy,
    });

    // record the raw event (immutable)
    await client.query(
      `INSERT INTO scan_events (id, org_id, device_id, employee_id, scan_time, device_time, direction,
        confidence, liveness_score, face_hash, dedupe_key, sync_state)
       VALUES (gen_random_uuid(), $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [
        input.orgId,
        input.deviceId,
        emp.id,
        scanTime,
        input.deviceTime ?? null,
        input.directionHint ?? null,
        input.confidence ?? null,
        input.livenessScore ?? null,
        input.faceHash ?? null,
        input.dedupeKey,
        input.syncState,
      ],
    );

    let sessionOut: Session | null = null;
    let status: ScanResult['status'] = 'none';
    let action = decision.action;

    if (decision.action === 'check_in') {
      const s = decision.session;
      const inserted = await client.query<SessionRow>(
        `INSERT INTO attendance_sessions (id, org_id, employee_id, work_date, check_in_at, check_in_source, status, policy)
         VALUES (gen_random_uuid(), $1, $2, $3, $4, 'auto', 'open', $5) RETURNING *`,
        [emp.org_id, emp.id, s.workDate, s.checkInAt, JSON.stringify(policy)],
      );
      sessionOut = toEngineSession(inserted.rows[0]!);
      status = 'checked_in';
    } else if (decision.action === 'check_out') {
      const s = decision.session;
      const updated = await client.query<SessionRow>(
        `UPDATE attendance_sessions
         SET check_out_at = $2, check_out_source = 'auto', status = 'closed',
             break_minutes = $3, stats = $4, updated_at = now()
         WHERE id = $1 RETURNING *`,
        [s.id, s.checkOutAt, s.breakMinutes, JSON.stringify(s.stats)],
      );
      sessionOut = updated.rows[0] ? toEngineSession(updated.rows[0]) : null;
      status = 'checked_out';
    }

    await client.query(
      `INSERT INTO scan_outcomes (dedupe_key, action) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
      [input.dedupeKey, action],
    );

    if (input.deviceTime) {
      const delta = scanTime.getTime() - new Date(input.deviceTime).getTime();
      await client.query(
        `UPDATE devices SET last_seen_at = now(), clock_offset_ms = $2 WHERE id = $1`,
        [input.deviceId, delta],
      );
    }

    await client.query('COMMIT');

    return {
      action,
      employee: { id: emp.id, name: emp.name, employeeCode: emp.employee_code },
      session: sessionOut ?? undefined,
      status,
      scanTime: scanTime.toISOString(),
      message: decision.action === 'duplicate' ? decision.reason : undefined,
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Rollover: close stale open sessions as incomplete, once per org per day. */
export async function runRollover(): Promise<number> {
  const orgs = await query<{ id: string; timezone: string }>('SELECT id, timezone FROM orgs');
  let changed = 0;
  for (const org of orgs) {
    const tz = org.timezone;
    const openSessions = await query<SessionRow>(
      `SELECT * FROM attendance_sessions
       WHERE org_id = $1 AND status = 'open' AND voided_at IS NULL`,
      [org.id],
    );
    const sessions = openSessions.map(toEngineSession);
    const toClose = flagMissedCheckouts(sessions, new Date());
    for (const s of toClose) {
      const row = openSessions.find((r) => r.id === s.id);
      if (!row) continue;
      const workDate = localDate(new Date(), tz);
      const isStale = row.work_date < workDate;
      if (!isStale) continue;
      await query(
        `UPDATE attendance_sessions SET status = 'incomplete', note = $2, updated_at = now() WHERE id = $1`,
        [s.id, s.note],
      );
      await audit({
        orgId: org.id,
        actorType: 'system',
        action: 'rollover_missed_checkout',
        targetType: 'attendance_session',
        targetId: s.id,
        details: { employeeId: s.employeeId, note: s.note },
      });
      changed++;
    }
  }
  return changed;
}
