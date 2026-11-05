import type { FastifyInstance } from 'fastify';
import { query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { localDate } from '../lib/time.js';
import { audit } from '../services/audit.js';
import {
  addDays,
  buildOvertimeAlert,
  mondayOf,
  readOvertimeSettings,
  type OvertimeSettings,
} from '../services/overtime.js';

function monthEnd(today: string): string {
  const [year, month] = today.split('-').map(Number);
  return new Date(Date.UTC(year!, month!, 0)).toISOString().slice(0, 10);
}

export function overtimeRoutes(app: FastifyInstance): void {
  app.get('/api/v1/admin/overtime', { preHandler: requireAdmin }, async (req) => {
    const org = await queryOne<{
      timezone: string;
      settings: Record<string, unknown> | null;
    }>('SELECT timezone, settings FROM orgs WHERE id = $1', [req.admin!.orgId]);
    const settings = readOvertimeSettings(org?.settings);
    const timezone = org?.timezone ?? 'Africa/Johannesburg';
    const today = localDate(new Date(), timezone);
    const weekStart = mondayOf(today);
    const weekEnd = addDays(weekStart, 6);
    const monthStart = `${today.slice(0, 7)}-01`;
    const endOfMonth = monthEnd(today);

    if (!settings.enabled) {
      return {
        settings,
        today,
        weekStart,
        weekEnd,
        monthStart,
        monthEnd: endOfMonth,
        workers: [],
        alerts: [],
      };
    }

    const from = weekStart < monthStart ? weekStart : monthStart;
    const employees = await query<{
      id: string;
      name: string;
      employee_code: string;
      schedule: Record<string, unknown>;
    }>(
      `SELECT id, name, employee_code, schedule
       FROM employees
       WHERE org_id = $1 AND status = 'active'
       ORDER BY name ASC`,
      [req.admin!.orgId],
    );

    const sessions = await query<{
      employee_id: string;
      work_date: string;
      minutes: number;
    }>(
      `SELECT employee_id, work_date::text AS work_date,
              coalesce((stats->>'workedMinutes')::int, 0) AS minutes
       FROM attendance_sessions
       WHERE org_id = $1 AND voided_at IS NULL
         AND work_date >= $2 AND work_date <= $3`,
      [req.admin!.orgId, from, today],
    );

    const weekMinutes = new Map<string, number>();
    const monthMinutes = new Map<string, number>();
    for (const session of sessions) {
      const minutes = Number(session.minutes ?? 0);
      if (session.work_date >= weekStart) {
        weekMinutes.set(session.employee_id, (weekMinutes.get(session.employee_id) ?? 0) + minutes);
      }
      if (session.work_date >= monthStart) {
        monthMinutes.set(
          session.employee_id,
          (monthMinutes.get(session.employee_id) ?? 0) + minutes,
        );
      }
    }

    const workers = employees.map((employee) =>
      buildOvertimeAlert({
        employee: {
          id: employee.id,
          name: employee.name,
          employeeCode: employee.employee_code,
          schedule: employee.schedule,
        },
        weeklyWorkedMinutes: weekMinutes.get(employee.id) ?? 0,
        monthlyWorkedMinutes: monthMinutes.get(employee.id) ?? 0,
        settings,
        weekStart,
        weekEnd,
        monthStart,
        monthEnd: endOfMonth,
        today,
      }),
    );

    return {
      settings,
      today,
      weekStart,
      weekEnd,
      monthStart,
      monthEnd: endOfMonth,
      workers,
      alerts: workers.filter((worker) => worker.status !== 'ok'),
    };
  });

  app.put('/api/v1/admin/overtime/settings', { preHandler: requireAdmin }, async (req) => {
    const body = (req.body ?? {}) as Partial<OvertimeSettings>;
    const weeklyHours = Number(body.weeklyHours);
    const monthlyHours = Number(body.monthlyHours);
    if (!Number.isFinite(weeklyHours) || weeklyHours < 1 || weeklyHours > 168) {
      throw badRequest('weekly hours must be between 1 and 168');
    }
    if (!Number.isFinite(monthlyHours) || monthlyHours < 1 || monthlyHours > 744) {
      throw badRequest('monthly hours must be between 1 and 744');
    }
    const settings: OvertimeSettings = {
      enabled: body.enabled !== false,
      weeklyHours,
      monthlyHours,
    };

    const current = await queryOne<{ settings: Record<string, unknown> | null }>(
      'SELECT settings FROM orgs WHERE id = $1',
      [req.admin!.orgId],
    );
    if (!current) throw notFound('organization not found');

    await query(
      `UPDATE orgs
       SET settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('overtime', $2::jsonb)
       WHERE id = $1`,
      [req.admin!.orgId, JSON.stringify(settings)],
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'overtime_settings_update',
      details: { settings },
    });
    return { settings };
  });

  app.post(
    '/api/v1/admin/overtime/:employeeId/apply-suggestion',
    { preHandler: requireAdmin },
    async (req) => {
      const employeeId = (req.params as { employeeId: string }).employeeId;
      const body = (req.body ?? {}) as { weeklyHours?: number };
      const weeklyHours = Number(body.weeklyHours);
      if (!Number.isFinite(weeklyHours) || weeklyHours < 0 || weeklyHours > 168) {
        throw badRequest('weekly hours must be between 0 and 168');
      }

      const employee = await queryOne<{
        id: string;
        name: string;
        schedule: Record<string, unknown>;
      }>(
        'SELECT id, name, schedule FROM employees WHERE id = $1 AND org_id = $2 AND status = $3',
        [employeeId, req.admin!.orgId, 'active'],
      );
      if (!employee) throw notFound('active employee not found');

      const previous = Number(employee.schedule.hoursPerWeek ?? 0);
      const schedule = { ...employee.schedule, hoursPerWeek: weeklyHours };
      await query(
        'UPDATE employees SET schedule = $3, updated_at = now() WHERE id = $1 AND org_id = $2',
        [employeeId, req.admin!.orgId, JSON.stringify(schedule)],
      );
      await audit({
        orgId: req.admin!.orgId,
        actorType: 'admin',
        actorId: req.admin!.id,
        action: 'overtime_schedule_apply',
        targetType: 'employee',
        targetId: employeeId,
        details: { previousWeeklyHours: previous, weeklyHours },
      });
      return { ok: true, weeklyHours, employeeId };
    },
  );
}
