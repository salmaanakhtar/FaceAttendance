import type { FastifyInstance } from 'fastify';
import { pool, query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { audit } from '../services/audit.js';
import { classify, DEFAULT_POLICY, type Session } from '../services/attendance/engine.js';
import { localDate } from '../lib/time.js';

const correctionSchema = {
  body: {
    type: 'object',
    required: ['employeeId', 'field', 'reason'],
    properties: {
      employeeId: { type: 'string', minLength: 1 },
      sessionId: { type: 'string' },
      field: {
        type: 'string',
        enum: ['check_in', 'check_out', 'break_minutes', 'note', 'add_check_in', 'add_check_out', 'work_date'],
      },
      value: { type: ['string', 'number', 'null'] },
      reason: { type: 'string', minLength: 3, maxLength: 1000 },
    },
    additionalProperties: false,
  },
};

/**
 * Manual overrides. Every correction:
 * - snapshots old value, writes new value on the session
 * - inserts an attendance_corrections row (original/modified/admin/reason/time)
 * - inserts audit_events rows
 * Raw scan events are never touched.
 */
export function correctionRoutes(app: FastifyInstance): void {
  app.post('/api/v1/admin/corrections/manual-session', {
    schema: {
      body: {
        type: 'object',
        required: ['employeeId', 'checkInAt', 'reason'],
        additionalProperties: false,
        properties: {
          employeeId: { type: 'string', minLength: 1 },
          checkInAt: { type: 'string', minLength: 1 },
          checkOutAt: { type: ['string', 'null'] },
          reason: { type: 'string', minLength: 3, maxLength: 1000 },
        },
      },
    },
    preHandler: requireAdmin,
  }, async (req, reply) => {
    const body = req.body as {
      employeeId: string;
      checkInAt: string;
      checkOutAt?: string | null;
      reason: string;
    };
    const checkIn = new Date(body.checkInAt);
    const checkOut = body.checkOutAt ? new Date(body.checkOutAt) : null;
    if (Number.isNaN(checkIn.getTime()) || (checkOut && Number.isNaN(checkOut.getTime()))) {
      throw badRequest('invalid manual entry timestamp');
    }
    if (checkOut && checkOut <= checkIn) {
      throw badRequest('time out must be later than time in');
    }

    const orgId = req.admin!.orgId;
    const employee = await queryOne<{ id: string; timezone: string }>(
      `SELECT e.id, o.timezone FROM employees e
       JOIN orgs o ON o.id = e.org_id
       WHERE e.id = $1 AND e.org_id = $2 AND e.status = 'active'`,
      [body.employeeId, orgId],
    );
    if (!employee) throw notFound('active employee not found');

    const client = await pool.connect();
    let sessionId: string;
    try {
      await client.query('BEGIN');
      if (!checkOut) {
        const open = await client.query(
          `SELECT id FROM attendance_sessions
           WHERE org_id = $1 AND employee_id = $2 AND status = 'open'
             AND voided_at IS NULL
           LIMIT 1 FOR UPDATE`,
          [orgId, body.employeeId],
        );
        if (open.rowCount) {
          throw badRequest('worker already has an open shift; close it before adding another');
        }
      }

      const workDate = localDate(checkIn, employee.timezone);
      const session = {
        id: '',
        employeeId: body.employeeId,
        workDate,
        checkInAt: checkIn,
        checkOutAt: checkOut,
        checkInSource: 'manual' as const,
        checkOutSource: 'manual' as const,
        status: (checkOut ? 'closed' : 'open') as Session['status'],
        breakMinutes: 0,
        policy: { ...DEFAULT_POLICY, timezone: employee.timezone },
        stats: {} as Session['stats'],
        note: 'manual time entry',
      } satisfies Session;
      classify(session, new Date());
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO attendance_sessions
          (id, org_id, employee_id, work_date, check_in_at, check_out_at,
           check_in_source, check_out_source, status, policy, stats, note, corrected)
         VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, 'manual', 'manual',
           $6, $7, $8, $9, true) RETURNING id`,
        [orgId, body.employeeId, workDate, checkIn, checkOut, session.status,
         JSON.stringify(session.policy), JSON.stringify(session.stats), session.note],
      );
      sessionId = inserted.rows[0]!.id;
      const corrections = [
        [sessionId, 'add_check_in', JSON.stringify({ at: checkIn.toISOString() })],
        ...(checkOut
          ? [[sessionId, 'add_check_out', JSON.stringify({ at: checkOut.toISOString() })]]
          : []),
      ];
      for (const [id, field, newValue] of corrections) {
        await client.query(
          `INSERT INTO attendance_corrections
            (id, org_id, session_id, employee_id, field, old_value, new_value, admin_id, reason)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, NULL, $5, $6, $7)`,
          [orgId, id, body.employeeId, field, newValue, req.admin!.id, body.reason],
        );
      }
      await client.query(
        `INSERT INTO audit_events
          (org_id, actor_type, actor_id, action, target_type, target_id, details)
         VALUES ($1, 'admin', $2, 'correction_add_session',
           'attendance_session', $3, $4)`,
        [orgId, req.admin!.id, sessionId, JSON.stringify({
          employeeId: body.employeeId,
          checkInAt: checkIn.toISOString(),
          checkOutAt: checkOut?.toISOString() ?? null,
          reason: body.reason,
        })],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    return reply.code(201).send({ ok: true, sessionId });
  });

  app.post('/api/v1/admin/corrections', { schema: correctionSchema, preHandler: requireAdmin }, async (req, reply) => {
    const { employeeId, sessionId: sessionIdInput, field, value, reason } = req.body as {
      employeeId: string;
      sessionId?: string;
      field: string;
      value: string | number | null;
      reason: string;
    };
    let sessionId = sessionIdInput;
    const orgId = req.admin!.orgId;
    const emp = await queryOne<{ id: string; name: string }>(
      'SELECT id, name FROM employees WHERE id = $1 AND org_id = $2',
      [employeeId, orgId],
    );
    if (!emp) throw notFound('employee not found');

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const apply = async (sql: string, params: unknown[], fieldName: string, oldValue: unknown, newValue: unknown) => {
        await client.query(sql, params);
        await client.query(
          `INSERT INTO attendance_corrections (id, org_id, session_id, employee_id, field, old_value, new_value, admin_id, reason)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8)`,
          [orgId, sessionId ?? null, employeeId, fieldName, oldValue === null ? null : JSON.stringify(oldValue),
           newValue === null ? null : JSON.stringify(newValue), req.admin!.id, reason],
        );
      };
      const recalculate = async (id: string) => {
        const refreshed = await client.query(
          `SELECT check_in_at, check_out_at, break_minutes, policy, status, work_date
           FROM attendance_sessions WHERE id = $1 AND voided_at IS NULL`,
          [id],
        );
        const current = refreshed.rows[0];
        const recalculated = {
          id,
          employeeId,
          workDate: String(current.work_date),
          checkInAt: current.check_in_at ? new Date(current.check_in_at) : null,
          checkOutAt: current.check_out_at ? new Date(current.check_out_at) : null,
          checkInSource: 'manual' as const,
          checkOutSource: 'manual' as const,
          status: current.status as Session['status'],
          breakMinutes: Number(current.break_minutes ?? 0),
          policy: { ...DEFAULT_POLICY, ...(current.policy ?? {}) },
          stats: {} as Session['stats'],
          note: null,
        } satisfies Session;
        classify(recalculated, new Date());
        await client.query(
          'UPDATE attendance_sessions SET stats = $2, updated_at = now() WHERE id = $1',
          [id, JSON.stringify(recalculated.stats)],
        );
      };

      if (field === 'add_check_in' || field === 'add_check_out') {
        if (sessionId) throw badRequest('sessionId must be empty when adding an event');
        const at = new Date(String(value));
        if (Number.isNaN(at.getTime())) throw badRequest('invalid timestamp');
        // find the open target: for add_check_in, prevent double-open
        const open = await client.query(
          `SELECT * FROM attendance_sessions
             WHERE employee_id = $1 AND status IN ('open', 'incomplete')
               AND voided_at IS NULL
             ORDER BY check_in_at DESC LIMIT 1`,
          [employeeId],
        );
        const newSession = {
          id: `manual:${employeeId}:${at.getTime()}`,
          employeeId,
          workDate: '',
          checkInAt: field === 'add_check_in' ? at : null,
          checkOutAt: field === 'add_check_out' ? at : null,
          checkInSource: 'manual' as const,
          checkOutSource: 'manual' as const,
          status: 'open' as const,
          breakMinutes: 0,
          policy: {},
          stats: {},
          note: null,
        };
        if (field === 'add_check_in') {
          if (open.rowCount) throw badRequest('employee already has an open session');
          const tz = await client.query('SELECT timezone FROM orgs WHERE id = $1', [orgId]);
          const local = new Intl.DateTimeFormat('en-CA', {
            timeZone: tz.rows[0]?.timezone ?? 'UTC',
            year: 'numeric', month: '2-digit', day: '2-digit',
          }).format(at).replaceAll('/', '-');
          newSession.workDate = local;
          const inserted = await client.query(
            `INSERT INTO attendance_sessions (id, org_id, employee_id, work_date, check_in_at, check_in_source, status, policy)
             VALUES (gen_random_uuid(), $1, $2, $3, $4, 'manual', 'open', '{}'::jsonb) RETURNING id, work_date`,
            [orgId, employeeId, newSession.workDate, at],
          );
          await apply(`UPDATE attendance_sessions SET note = 'manual check-in' WHERE id = $1`, [inserted.rows[0].id],
            'add_check_in', null, { at: at.toISOString(), sessionId: inserted.rows[0].id });
          sessionId = inserted.rows[0].id;
        } else {
          // add_check_out: close an open or rolled-over incomplete session.
          // Rollover marks yesterday's missed checkout as incomplete; admins
          // still need the same quick manual checkout path to finish it.
          if (!open.rowCount) throw badRequest('no open or incomplete session to check out of');
          const target = open.rows[0];
          if (at <= new Date(target.check_in_at)) throw badRequest('checkout must be after check-in');
          await client.query(
            `UPDATE attendance_sessions SET check_out_at = $2, check_out_source = 'manual', status = 'closed', updated_at = now()
             WHERE id = $1`,
            [target.id, at],
          );
          await apply(`UPDATE attendance_sessions SET note = 'manual check-out' WHERE id = $1`, [target.id],
            'add_check_out', null, { at: at.toISOString() });
          sessionId = target.id;
        }
        await recalculate(sessionId!);
        await audit({
          orgId, actorType: 'admin', actorId: req.admin!.id,
          action: `correction_${field}`, targetType: 'attendance_session', targetId: sessionId,
          details: { employeeId, at: at.toISOString(), reason },
        });
        await client.query('COMMIT');
        return reply.code(201).send({ ok: true, field, sessionId });
      }

      if (!sessionId) throw badRequest('sessionId required for field edits');
      const session = await client.query(
        `SELECT * FROM attendance_sessions
         WHERE id = $1 AND org_id = $2 AND voided_at IS NULL`,
        [sessionId, orgId],
      );
      if (!session.rowCount) throw notFound('session not found');
      const s = session.rows[0];

      switch (field) {
        case 'check_in': {
          const at = new Date(String(value));
          if (Number.isNaN(at.getTime())) throw badRequest('invalid timestamp');
          if (s.check_out_at && at >= new Date(s.check_out_at)) throw badRequest('check-in must precede check-out');
          await apply(
            `UPDATE attendance_sessions SET check_in_at = $2, check_in_source = 'manual', corrected = true, updated_at = now() WHERE id = $1`,
            [sessionId, at], 'check_in', s.check_in_at, at.toISOString());
          break;
        }
        case 'check_out': {
          const at = new Date(String(value));
          if (Number.isNaN(at.getTime())) throw badRequest('invalid timestamp');
          if (s.check_in_at && at <= new Date(s.check_in_at)) throw badRequest('check-out must follow check-in');
          await apply(
            `UPDATE attendance_sessions SET check_out_at = $2, check_out_source = 'manual', status = 'closed', corrected = true, updated_at = now() WHERE id = $1`,
            [sessionId, at], 'check_out', s.check_out_at, at.toISOString());
          break;
        }
        case 'break_minutes': {
          const mins = Number(value);
          if (!Number.isFinite(mins) || mins < 0 || mins > 1440) throw badRequest('break minutes must be 0..1440');
          await apply(
            `UPDATE attendance_sessions SET break_minutes = $2, corrected = true, updated_at = now() WHERE id = $1`,
            [sessionId, Math.round(mins)], 'break_minutes', s.break_minutes, mins);
          break;
        }
        case 'note': {
          await apply(
            `UPDATE attendance_sessions SET note = $2, updated_at = now() WHERE id = $1`,
            [sessionId, String(value)], 'note', s.note, String(value));
          break;
        }
        case 'work_date': {
          const d = String(value);
          if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) throw badRequest('work_date must be YYYY-MM-DD');
          await apply(
            `UPDATE attendance_sessions SET work_date = $2, corrected = true, updated_at = now() WHERE id = $1`,
            [sessionId, d], 'work_date', s.work_date, d);
          break;
        }
        default:
          throw badRequest(`unsupported field ${field}`);
      }

      // Corrections change the derived session inputs. Recompute all payable
      // and exception stats immediately so totals and reports never show the
      // old hours after an edit.
      await recalculate(sessionId);

      await audit({
        orgId, actorType: 'admin', actorId: req.admin!.id,
        action: `correction_${field}`, targetType: 'attendance_session', targetId: sessionId,
        details: { employeeId, field, reason },
      });
      await client.query('COMMIT');
      return reply.send({ ok: true, field, sessionId });
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  });

  // Correction history for an employee or session
  app.get('/api/v1/admin/corrections', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { employeeId?: string; sessionId?: string; limit?: string };
    const where: string[] = ['c.org_id = $1'];
    const params: unknown[] = [req.admin!.orgId];
    if (q.employeeId) {
      params.push(q.employeeId);
      where.push(`c.employee_id = $${params.length}`);
    }
    if (q.sessionId) {
      params.push(q.sessionId);
      where.push(`c.session_id = $${params.length}`);
    }
    const limit = Math.min(Number(q.limit ?? 50), 200);
    const rows = await query(
      `SELECT c.*, a.name AS admin_name
       FROM attendance_corrections c JOIN admins a ON a.id = c.admin_id
       WHERE ${where.join(' AND ')} ORDER BY c.created_at DESC LIMIT $${params.length + 1}`,
      [...params, limit],
    );
    return reply.send({
      corrections: rows.map((r) => ({
        id: r.id,
        sessionId: r.session_id,
        employeeId: r.employee_id,
        field: r.field,
        oldValue: r.old_value,
        newValue: r.new_value,
        admin: r.admin_name,
        reason: r.reason,
        createdAt: r.created_at,
      })),
    });
  });
}
