import type { FastifyInstance } from 'fastify';
import { pool, query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { audit } from '../services/audit.js';

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

      if (field === 'add_check_in' || field === 'add_check_out') {
        if (sessionId) throw badRequest('sessionId must be empty when adding an event');
        const at = new Date(String(value));
        if (Number.isNaN(at.getTime())) throw badRequest('invalid timestamp');
        // find the open target: for add_check_in, prevent double-open
        const open = await client.query(
          `SELECT * FROM attendance_sessions WHERE employee_id = $1 AND status = 'open'`,
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
          // add_check_out: close an open or incomplete session
          if (!open.rowCount) throw badRequest('no open session to check out of');
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
        'SELECT * FROM attendance_sessions WHERE id = $1 AND org_id = $2',
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
