import type { FastifyInstance } from 'fastify';
import { query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { badRequest } from '../lib/errors.js';
import { isIsoDate } from '../services/attendance/absence.js';
import { calculatePayroll, type PayrollWorker, type PayrollSession, type PayAdjustment } from '../services/payroll.js';
import { payrollExcel } from '../services/payroll-export.js';
import { audit } from '../services/audit.js';

export function payrollRoutes(app: FastifyInstance) {
  app.post('/api/v1/admin/payroll/report', { preHandler: requireAdmin }, async (req, reply) => {
    const body = req.body as { from?: string; to?: string; format?: string; adjustments?: PayAdjustment[] } | null;
    if (!body || !isIsoDate(body.from ?? '') || !isIsoDate(body.to ?? '') || body.to! < body.from!) {
      throw badRequest('Choose a valid payroll date range');
    }
    if (new Date(body.to!).getTime() - new Date(body.from!).getTime() > 366 * 86400000) {
      throw badRequest('Choose a payroll range of at most one year');
    }
    if (!['json', 'xlsx'].includes(body.format ?? 'json')) throw badRequest('Invalid report format');
    if (body.adjustments !== undefined && (!Array.isArray(body.adjustments) || body.adjustments.length > 10000)) {
      throw badRequest('Invalid pay adjustments');
    }
    const seen = new Set<string>();
    for (const a of body.adjustments ?? []) {
      if (!a || typeof a.employeeId !== 'string' || seen.has(a.employeeId) ||
        [a.holidayPay, a.otherPay, a.uif, a.otherDeductions].some(n => typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > 1e9)) {
        throw badRequest('Enter each worker once with valid non-negative pay adjustments');
      }
      seen.add(a.employeeId);
    }
    const orgId = req.admin!.orgId;
    const [org, workers, sessions] = await Promise.all([
      queryOne<{ name: string; timezone: string }>('SELECT name, timezone FROM orgs WHERE id = $1', [orgId]),
      query<PayrollWorker>(`SELECT e.id, e.name, e.employee_code AS code, e.schedule FROM employees e
        WHERE e.org_id = $1 AND e.status <> 'deleted' AND (e.status = 'active' OR EXISTS (
          SELECT 1 FROM attendance_sessions s WHERE s.employee_id = e.id AND s.org_id = $1
          AND s.work_date BETWEEN $2 AND $3 AND s.voided_at IS NULL)) ORDER BY e.name, e.employee_code`, [orgId, body.from, body.to]),
      query<PayrollSession>(`SELECT s.employee_id AS "employeeId", s.work_date::text AS date,
        s.check_in_at AS "inAt", s.check_out_at AS "outAt", s.status,
        coalesce((s.stats->>'workedMinutes')::int,0) AS "workedMinutes",
        coalesce((s.stats->>'overtimeMinutes')::int,0) AS "overtimeMinutes", s.break_minutes AS "breakMinutes"
        FROM attendance_sessions s JOIN employees e ON e.id = s.employee_id
        WHERE s.org_id = $1 AND s.work_date BETWEEN $2 AND $3 AND s.voided_at IS NULL
        AND e.status <> 'deleted' ORDER BY s.work_date, s.check_in_at`, [orgId, body.from, body.to]),
    ]);
    if ((body.adjustments ?? []).some(a => !workers.some(w => w.id === a.employeeId))) throw badRequest('Unknown worker in adjustments');
    const report = { organization: org?.name ?? '', timezone: org?.timezone ?? 'UTC', from: body.from!, to: body.to!,
      workers: calculatePayroll(workers, sessions, body.adjustments) };
    if (!body.format || body.format === 'json') return reply.send(report);
    const bytes = await payrollExcel(report);
    await audit({ orgId, actorType: 'admin', actorId: req.admin!.id, action: 'export_monthly_payroll',
      details: { from: body.from, to: body.to, format: body.format, adjustments: body.adjustments ?? [] } });
    reply.header('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    reply.header('Content-Disposition', `attachment; filename="payroll-${body.from}-${body.to}.${body.format}"`);
    return reply.send(bytes);
  });
}
