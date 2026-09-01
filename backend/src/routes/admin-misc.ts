import type { FastifyInstance } from 'fastify';
import { query } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { audit } from '../services/audit.js';

export function adminMiscRoutes(app: FastifyInstance): void {
  // Audit log
  app.get('/api/v1/admin/audit', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { limit?: string; action?: string; targetId?: string };
    const where = ['org_id = $1 OR org_id IS NULL'];
    const params: unknown[] = [req.admin!.orgId];
    if (q.action) {
      params.push(q.action);
      where.push(`action = $${params.length}`);
    }
    if (q.targetId) {
      params.push(q.targetId);
      where.push(`target_id = $${params.length}`);
    }
    const limit = Math.min(Number(q.limit ?? 100), 500);
    const rows = await query(
      `SELECT id, actor_type, actor_id, action, target_type, target_id, details, created_at
       FROM audit_events WHERE ${where.join(' AND ')}
       ORDER BY created_at DESC LIMIT $${params.length + 1}`,
      [...params, limit],
    );
    return reply.send({
      events: rows.map((r) => ({
        id: r.id,
        actorType: r.actor_type,
        actorId: r.actor_id,
        action: r.action,
        targetType: r.target_type,
        targetId: r.target_id,
        details: r.details,
        createdAt: r.created_at,
      })),
    });
  });

  // Raw scan events (system-of-record transparency)
  app.get('/api/v1/admin/scan-events', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { limit?: string; employeeId?: string; syncState?: string };
    const where = ['org_id = $1'];
    const params: unknown[] = [req.admin!.orgId];
    if (q.employeeId) {
      params.push(q.employeeId);
      where.push(`employee_id = $${params.length}`);
    }
    if (q.syncState && q.syncState !== 'all') {
      params.push(q.syncState);
      where.push(`sync_state = $${params.length}`);
    }
    const limit = Math.min(Number(q.limit ?? 100), 500);
    const rows = await query(
      `SELECT s.id, s.employee_id, e.name AS employee_name, s.scan_time, s.device_time, s.direction,
              s.confidence, s.liveness_score, s.sync_state, s.dedupe_key, d.name AS device_name
       FROM scan_events s
       LEFT JOIN employees e ON e.id = s.employee_id
       LEFT JOIN devices d ON d.id = s.device_id
       WHERE ${where.join(' AND ')}
       ORDER BY s.scan_time DESC LIMIT $${params.length + 1}`,
      [...params, limit],
    );
    return reply.send({ events: rows });
  });

  // CSV export of sessions (raw data, not prettified)
  app.get('/api/v1/admin/export', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string; employeeId?: string };
    const where = ['s.org_id = $1'];
    const params: unknown[] = [req.admin!.orgId];
    if (q.from) {
      params.push(q.from);
      where.push(`s.work_date >= $${params.length}`);
    }
    if (q.to) {
      params.push(q.to);
      where.push(`s.work_date <= $${params.length}`);
    }
    if (q.employeeId) {
      params.push(q.employeeId);
      where.push(`s.employee_id = $${params.length}`);
    }
    const rows = await query(
      `SELECT e.employee_code, e.name AS employee_name, s.work_date::text AS work_date,
              to_char(s.check_in_at, 'YYYY-MM-DD HH24:MI:SS') AS check_in_at,
              to_char(s.check_out_at, 'YYYY-MM-DD HH24:MI:SS') AS check_out_at,
              s.check_in_source, s.check_out_source, s.status, s.break_minutes,
              (s.stats->>'workedMinutes')::int AS worked_minutes,
              (s.stats->>'lateMinutes')::int AS late_minutes,
              (s.stats->>'earlyMinutes')::int AS early_minutes,
              (s.stats->>'overtimeMinutes')::int AS overtime_minutes,
              s.note, s.corrected
       FROM attendance_sessions s JOIN employees e ON e.id = s.employee_id
       WHERE ${where.join(' AND ')} AND e.status <> 'deleted' ORDER BY s.check_in_at ASC`,
      params,
    );
    const header = [
      'employee_code', 'employee_name', 'work_date', 'check_in_at', 'check_out_at',
      'check_in_source', 'check_out_source', 'status', 'break_minutes', 'worked_minutes',
      'late_minutes', 'early_minutes', 'overtime_minutes', 'note', 'corrected',
    ];
    const esc = (v: unknown) => {
      const s = v === null || v === undefined ? '' : String(v);
      return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
    };
    const csv = [header.join(','), ...rows.map((r) => header.map((h) => esc(r[h])).join(','))].join('\r\n');
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'export_attendance',
      details: { from: q.from ?? null, to: q.to ?? null },
    });
    reply.header('Content-Type', 'text/csv; charset=utf-8');
    reply.header('Content-Disposition', `attachment; filename="attendance-${q.from ?? 'all'}-${q.to ?? 'all'}.csv"`);
    return reply.send(csv);
  });

  // Auditable gross-pay estimate for a selected payroll period. This is not a
  // statutory tax payslip; hourlyRate is read from employee.schedule.
  app.get('/api/v1/admin/payroll/payslips', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string };
    if (!q.from || !q.to) return reply.code(400).send({ error: { code: 'BAD_REQUEST', message: 'from and to are required' } });
    const rows = await query(
      `SELECT e.employee_code, e.name AS employee_name,
              coalesce(sum((s.stats->>'workedMinutes')::int),0)::int AS worked_minutes,
              coalesce(sum((s.stats->>'overtimeMinutes')::int),0)::int AS overtime_minutes,
              coalesce(max((e.schedule->>'hourlyRate')::numeric),0)::numeric AS hourly_rate
       FROM attendance_sessions s JOIN employees e ON e.id = s.employee_id
       WHERE s.org_id = $1 AND s.work_date >= $2 AND s.work_date <= $3
         AND e.status <> 'deleted'
       GROUP BY e.id, e.employee_code, e.name ORDER BY e.name`,
      [req.admin!.orgId, q.from, q.to],
    );
    const header = ['employee_code', 'employee_name', 'period_from', 'period_to', 'worked_hours', 'overtime_hours', 'hourly_rate', 'overtime_multiplier', 'gross_estimate'];
    const esc = (v: unknown) => {
      const s = v === null || v === undefined ? '' : String(v);
      return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
    };
    const data = rows.map((r) => {
      const worked = Number(r.worked_minutes ?? 0) / 60;
      const overtime = Number(r.overtime_minutes ?? 0) / 60;
      const rate = Number(r.hourly_rate ?? 0);
      return [r.employee_code, r.employee_name, q.from, q.to, worked.toFixed(2), overtime.toFixed(2), rate.toFixed(2), '1.5', (worked * rate + overtime * rate * 0.5).toFixed(2)].map(esc).join(',');
    });
    await audit({ orgId: req.admin!.orgId, actorType: 'admin', actorId: req.admin!.id, action: 'export_payslip_estimate', details: { from: q.from, to: q.to } });
    reply.header('Content-Type', 'text/csv; charset=utf-8');
    reply.header('Content-Disposition', `attachment; filename="payslip-estimate-${q.from}-${q.to}.csv"`);
    return reply.send([header.join(','), ...data].join('\r\n'));
  });
}
