import type { FastifyInstance } from 'fastify';
import { query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { notFound } from '../lib/errors.js';
import { attendanceExceptions } from '../services/attendance/exceptions.js';

interface SessionRow {
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
  employee_name: string;
  employee_code: string;
}

const sessionColumns = `
  s.*, e.name AS employee_name, e.employee_code AS employee_code
  FROM attendance_sessions s
  JOIN employees e ON e.id = s.employee_id AND e.status <> 'deleted'`;

function sessionDto(r: SessionRow) {
  const stats = r.stats as Record<string, number | boolean>;
  return {
    id: r.id,
    employeeId: r.employee_id,
    employeeName: r.employee_name,
    employeeCode: r.employee_code,
    workDate: r.work_date,
    checkInAt: r.check_in_at,
    checkOutAt: r.check_out_at,
    checkInSource: r.check_in_source,
    checkOutSource: r.check_out_source,
    status: r.status,
    breakMinutes: r.break_minutes,
    workedMinutes: (stats.workedMinutes as number) ?? 0,
    lateMinutes: (stats.lateMinutes as number) ?? 0,
    earlyMinutes: (stats.earlyMinutes as number) ?? 0,
    overtimeMinutes: (stats.overtimeMinutes as number) ?? 0,
    isLate: !!stats.isLate,
    isEarly: !!stats.isEarly,
    hasOvertime: !!stats.hasOvertime,
    note: r.note,
    corrected: r.corrected,
  };
}

export function attendanceRoutes(app: FastifyInstance): void {
  // Currently checked in — live snapshot for dashboard/kiosk status
  app.get('/api/v1/admin/attendance/now', { preHandler: requireAdmin }, async (req, reply) => {
    const rows = await query<SessionRow>(
      `SELECT ${sessionColumns} WHERE s.org_id = $1 AND s.status = 'open' ORDER BY s.check_in_at ASC`,
      [req.admin!.orgId],
    );
    return reply.send({ currentlyIn: rows.map(sessionDto), count: rows.length });
  });

  // Actionable exception inbox. A session can produce more than one issue;
  // managers see the individual reasons instead of only aggregate counters.
  app.get('/api/v1/admin/attendance/exceptions', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string; limit?: string };
      const where = [
      's.org_id = $1',
      "e.status <> 'deleted'",
      `(s.status = 'incomplete'
        OR coalesce((s.stats->>'lateMinutes')::int, 0) > 0
        OR coalesce((s.stats->>'earlyMinutes')::int, 0) > 0
        OR coalesce((s.stats->>'overtimeMinutes')::int, 0) > 0)`,
    ];
    const params: unknown[] = [req.admin!.orgId];
    if (q.from) {
      params.push(q.from);
      where.push(`s.work_date >= $${params.length}`);
    }
    if (q.to) {
      params.push(q.to);
      where.push(`s.work_date <= $${params.length}`);
    }
    const requestedLimit = Number(q.limit ?? 50);
    const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 200) : 50;
    const rows = await query<SessionRow>(
      `SELECT ${sessionColumns} WHERE ${where.join(' AND ')}
       ORDER BY s.work_date DESC, s.check_in_at DESC LIMIT $${params.length + 1}`,
      [...params, limit],
    );
    const exceptions = rows.flatMap((row) => {
      const session = sessionDto(row);
      return attendanceExceptions({
        status: session.status,
        lateMinutes: session.lateMinutes,
        earlyMinutes: session.earlyMinutes,
        overtimeMinutes: session.overtimeMinutes,
      }).map((issue) => ({ ...issue, session }));
    });
    const counts = exceptions.reduce<Record<string, number>>((acc, issue) => {
      acc[issue.type] = (acc[issue.type] ?? 0) + 1;
      return acc;
    }, {});
    return reply.send({ exceptions, counts, count: exceptions.length });
  });

  // Sessions within a range, optionally filtered by employee
  app.get('/api/v1/admin/attendance', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as {
      from?: string;
      to?: string;
      employeeId?: string;
      status?: string;
      limit?: string;
      offset?: string;
    };
    const orgId = req.admin!.orgId;
    const where = ['s.org_id = $1', "s.employee_id IN (SELECT id FROM employees WHERE org_id = s.org_id AND status <> 'deleted')"];
    const params: unknown[] = [orgId];
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
    if (q.status && q.status !== 'all') {
      params.push(q.status);
      where.push(`s.status = $${params.length}`);
    }
    const limit = Math.min(Number(q.limit ?? 100), 500);
    const offset = Number(q.offset ?? 0);
    const rows = await query<SessionRow>(
      `SELECT ${sessionColumns} WHERE ${where.join(' AND ')}
       ORDER BY s.check_in_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, limit, offset],
    );
    const total = await queryOne<{ count: string }>(
      `SELECT count(*)::text AS count FROM attendance_sessions s
       WHERE ${where.join(' AND ')}`,
      params,
    );
    return reply.send({ sessions: rows.map(sessionDto), total: Number(total?.count ?? 0) });
  });

  // Per-employee history with running totals
  app.get('/api/v1/admin/attendance/employee/:id', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const q = req.query as { from?: string; to?: string };
    const emp = await queryOne(
      'SELECT id, name, employee_code FROM employees WHERE id = $1 AND org_id = $2',
      [id, req.admin!.orgId],
    );
    if (!emp) throw notFound('employee not found');
    const where = ['s.employee_id = $1', 's.org_id = $2', "e.status <> 'deleted'"];
    const params: unknown[] = [id, req.admin!.orgId];
    if (q.from) {
      params.push(q.from);
      where.push(`s.work_date >= $${params.length}`);
    }
    if (q.to) {
      params.push(q.to);
      where.push(`s.work_date <= $${params.length}`);
    }
    const rows = await query<SessionRow>(
      `SELECT ${sessionColumns} WHERE ${where.join(' AND ')} ORDER BY s.check_in_at DESC`,
      params,
    );
    const sessions = rows.map(sessionDto);
    const totals = sessions.reduce(
      (acc, s) => {
        acc.workedMinutes += s.workedMinutes;
        acc.lateCount += s.isLate ? 1 : 0;
        acc.earlyCount += s.isEarly ? 1 : 0;
        acc.overtimeMinutes += s.overtimeMinutes;
        acc.incompleteCount += s.status === 'incomplete' ? 1 : 0;
        return acc;
      },
      { workedMinutes: 0, lateCount: 0, earlyCount: 0, overtimeMinutes: 0, incompleteCount: 0 },
    );
    return reply.send({ employee: emp, sessions, totals });
  });

  // Aggregates over a period: late/early/ot/missed counts + unusual patterns
  app.get('/api/v1/admin/attendance/stats', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string };
    const orgId = req.admin!.orgId;
    const where = ['s.org_id = $1', "s.employee_id IN (SELECT id FROM employees WHERE org_id = s.org_id AND status <> 'deleted')"];
    const params: unknown[] = [orgId];
    if (q.from) {
      params.push(q.from);
      where.push(`s.work_date >= $${params.length}`);
    }
    if (q.to) {
      params.push(q.to);
      where.push(`s.work_date <= $${params.length}`);
    }
    const w = where.join(' AND ');
    const [agg, byEmployee, anomalies] = await Promise.all([
      queryOne<{
        days: string;
        sessions: string;
        employees: string;
        worked_min: string;
        late: string;
        early: string;
        overtime_min: string;
        incomplete: string;
        missed_checkouts: string;
        average_check_in: string;
      }>(
        `SELECT count(DISTINCT s.work_date)::text AS days,
                count(*)::text AS sessions,
                count(DISTINCT s.employee_id)::text AS employees,
                coalesce(sum((s.stats->>'workedMinutes')::int),0)::text AS worked_min,
                count(*) FILTER (WHERE (s.stats->>'isLate')::boolean)::text AS late,
                count(*) FILTER (WHERE (s.stats->>'isEarly')::boolean)::text AS early,
                coalesce(sum((s.stats->>'overtimeMinutes')::int),0)::text AS overtime_min,
                count(*) FILTER (WHERE s.status='incomplete')::text AS incomplete,
                count(*) FILTER (WHERE s.status='incomplete' AND s.note LIKE '%missed checkout%')::text AS missed_checkouts,
                to_char(to_timestamp(avg(extract(epoch FROM s.check_in_at AT TIME ZONE tz.tz))), 'HH24:MI') AS average_check_in
         FROM attendance_sessions s,
         LATERAL (SELECT timezone AS tz FROM orgs WHERE id = s.org_id) tz
         WHERE ${w}`,
        params,
      ),
      query<{
        employee_id: string;
        employee_name: string;
        sessions: string;
        worked_min: string;
        avg_check_in: string;
        late: string;
        early: string;
      }>(
        `SELECT s.employee_id, max(e.name) AS employee_name, count(*)::text AS sessions,
                coalesce(sum((s.stats->>'workedMinutes')::int),0)::text AS worked_min,
                to_char(to_timestamp(avg(extract(epoch FROM s.check_in_at AT TIME ZONE tz.tz))), 'HH24:MI') AS avg_check_in,
                count(*) FILTER (WHERE (s.stats->>'isLate')::boolean)::text AS late,
                count(*) FILTER (WHERE (s.stats->>'isEarly')::boolean)::text AS early
         FROM attendance_sessions s
         JOIN employees e ON e.id = s.employee_id,
         LATERAL (SELECT timezone AS tz FROM orgs WHERE id = s.org_id) tz
         WHERE ${w} GROUP BY s.employee_id ORDER BY worked_min DESC`,
        params,
      ),
      query<{ employee_name: string; details: string; severity: string }>(
        `SELECT e.name AS employee_name, d.details, d.severity FROM (
           SELECT s.employee_id,
             count(*) FILTER (WHERE (s.stats->>'workedMinutes')::int < 120) AS very_short,
             count(*) FILTER (WHERE (s.stats->>'isLate')::boolean) AS late,
             count(DISTINCT s.work_date) AS days
           FROM attendance_sessions s WHERE ${w} GROUP BY s.employee_id
         ) s JOIN employees e ON e.id = s.employee_id,
         LATERAL (
           SELECT 'frequent_very_short_shifts' AS details, 'high' AS severity
           WHERE s.very_short >= 3
           UNION ALL SELECT 'frequent_late_arrivals'::text, 'medium'::text
           WHERE s.late >= 3 AND s.days >= s.late
         ) d`,
        params,
      ),
    ]);
    return reply.send({
      period: { from: q.from ?? null, to: q.to ?? null },
      aggregate: agg
        ? {
            days: Number(agg.days),
            sessions: Number(agg.sessions),
            employees: Number(agg.employees),
            workedMinutes: Number(agg.worked_min),
            lateCount: Number(agg.late),
            earlyCount: Number(agg.early),
            overtimeMinutes: Number(agg.overtime_min),
            incompleteCount: Number(agg.incomplete),
            missedCheckouts: Number(agg.missed_checkouts),
            averageCheckIn: agg.average_check_in,
          }
        : null,
      byEmployee: byEmployee.map((r) => ({
        employeeId: r.employee_id,
        employeeName: r.employee_name,
        sessions: Number(r.sessions),
        workedMinutes: Number(r.worked_min),
        averageCheckIn: r.avg_check_in,
        lateCount: Number(r.late),
        earlyCount: Number(r.early),
      })),
      anomalies: anomalies.map((r) => ({ employeeName: r.employee_name, type: r.details, severity: r.severity })),
    });
  });
}
