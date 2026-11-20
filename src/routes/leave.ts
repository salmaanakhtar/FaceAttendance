import type { FastifyInstance } from 'fastify';
import { requireAdmin } from '../auth/guards.js';
import { query, queryOne } from '../db.js';
import { badRequest, notFound } from '../lib/errors.js';
import { localDate } from '../lib/time.js';
import { audit } from '../services/audit.js';
import { calculateAbsence, isIsoDate } from '../services/attendance/absence.js';

interface LeaveRow {
  id: string;
  employee_id: string;
  employee_name: string;
  employee_code: string;
  start_date: string;
  end_date: string;
  leave_type: string;
  status: string;
  note: string | null;
  created_at: string;
  updated_at: string;
}

const leaveTypes = ['annual', 'sick', 'unpaid', 'other', 'absence'] as const;
const leaveStatuses = ['pending', 'approved', 'rejected', 'cancelled'] as const;

function leaveDto(row: LeaveRow) {
  return {
    id: row.id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    employeeCode: row.employee_code,
    startDate: String(row.start_date),
    endDate: String(row.end_date),
    leaveType: row.leave_type,
    status: row.status,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function validateLeave(input: { startDate: string; endDate: string; leaveType: string; status: string }): void {
  if (!isIsoDate(input.startDate) || !isIsoDate(input.endDate)) {
    throw badRequest('startDate and endDate must be valid YYYY-MM-DD dates');
  }
  if (input.endDate < input.startDate) throw badRequest('endDate must be on or after startDate');
  if (!leaveTypes.includes(input.leaveType as typeof leaveTypes[number])) throw badRequest('invalid leaveType');
  if (!leaveStatuses.includes(input.status as typeof leaveStatuses[number])) throw badRequest('invalid leave status');
}

async function recordAbsence(input: {
  orgId: string;
  adminId: string;
  employeeId: string;
  workDate: string;
  note?: string | null;
}) {
  if (!isIsoDate(input.workDate)) throw badRequest('workDate must be a valid YYYY-MM-DD date');
  const employee = await queryOne<{ id: string }>(
    `SELECT id FROM employees WHERE id = $1 AND org_id = $2 AND status <> 'deleted'`,
    [input.employeeId, input.orgId],
  );
  if (!employee) throw notFound('employee not found');
  const attendance = await queryOne<{ id: string }>(
    `SELECT id FROM attendance_sessions
     WHERE org_id = $1 AND employee_id = $2 AND work_date = $3
       AND voided_at IS NULL LIMIT 1`,
    [input.orgId, input.employeeId, input.workDate],
  );
  if (attendance) throw badRequest('worker already has attendance recorded for this date');
  const inserted = await queryOne<{ id: string; created_at: string }>(
    `INSERT INTO employee_absences (org_id, employee_id, work_date, note, created_by)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (org_id, employee_id, work_date) DO NOTHING
     RETURNING id, created_at`,
    [input.orgId, input.employeeId, input.workDate, input.note?.trim() || null, input.adminId],
  );
  if (!inserted) throw badRequest('worker is already marked absent for this date');
  await audit({
    orgId: input.orgId,
    actorType: 'admin',
    actorId: input.adminId,
    action: 'absence_create',
    targetType: 'employee_absence',
    targetId: inserted.id,
    details: { employeeId: input.employeeId, workDate: input.workDate },
  });
  return {
    id: inserted.id,
    employeeId: input.employeeId,
    workDate: input.workDate,
    note: input.note?.trim() || null,
    createdAt: inserted.created_at,
  };
}

export function leaveRoutes(app: FastifyInstance): void {
  app.get('/api/v1/admin/leave', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string; employeeId?: string; status?: string };
    const where = ['l.org_id = $1', "l.leave_type <> 'absence'"];
    const params: unknown[] = [req.admin!.orgId];
    if (q.from) { params.push(q.from); where.push(`l.end_date >= $${params.length}`); }
    if (q.to) { params.push(q.to); where.push(`l.start_date <= $${params.length}`); }
    if (q.employeeId) { params.push(q.employeeId); where.push(`l.employee_id = $${params.length}`); }
    if (q.status && q.status !== 'all') { params.push(q.status); where.push(`l.status = $${params.length}`); }
    const rows = await query<LeaveRow>(
      `SELECT l.*, e.name AS employee_name, e.employee_code
       FROM employee_leave l JOIN employees e ON e.id = l.employee_id
       WHERE ${where.join(' AND ')} ORDER BY l.start_date DESC, e.name ASC`,
      params,
    );
    return reply.send({ leave: rows.map(leaveDto), total: rows.length });
  });

  app.post('/api/v1/admin/leave', { preHandler: requireAdmin }, async (req, reply) => {
    const body = req.body as {
      employeeId: string;
      startDate: string;
      endDate: string;
      leaveType: string;
      status?: string;
      note?: string | null;
    };
    const status = body.status ?? 'approved';
    validateLeave({ ...body, status });
    if (body.leaveType === 'absence' && body.startDate !== body.endDate) {
      throw badRequest('an absence must be recorded for one day at a time');
    }
    // Backward compatibility for v1.2.16/v1.2.17 clients: route their old
    // absence-shaped leave request into the dedicated absence table.
    if (body.leaveType === 'absence') {
      const absence = await recordAbsence({
        orgId: req.admin!.orgId,
        adminId: req.admin!.id,
        employeeId: body.employeeId,
        workDate: body.startDate,
        note: body.note,
      });
      return reply.code(201).send(absence);
    }
    const employee = await queryOne<{ id: string }>(
      `SELECT id FROM employees WHERE id = $1 AND org_id = $2 AND status <> 'deleted'`,
      [body.employeeId, req.admin!.orgId],
    );
    if (!employee) throw notFound('employee not found');
    const row = await queryOne<LeaveRow>(
      `WITH inserted AS (
         INSERT INTO employee_leave
           (org_id, employee_id, start_date, end_date, leave_type, status, note, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *
       )
       SELECT inserted.*, e.name AS employee_name, e.employee_code
       FROM inserted JOIN employees e ON e.id = inserted.employee_id`,
      [req.admin!.orgId, body.employeeId, body.startDate, body.endDate,
       body.leaveType, status, body.note?.trim() || null, req.admin!.id],
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'leave_create',
      targetType: 'employee_leave',
      targetId: row!.id,
      details: { employeeId: body.employeeId, startDate: body.startDate, endDate: body.endDate, leaveType: body.leaveType, status },
    });
    return reply.code(201).send(leaveDto(row!));
  });

  app.post('/api/v1/admin/attendance/absence', { preHandler: requireAdmin }, async (req, reply) => {
    const body = req.body as { employeeId: string; workDate: string; note?: string | null };
    const absence = await recordAbsence({
      orgId: req.admin!.orgId,
      adminId: req.admin!.id,
      employeeId: body.employeeId,
      workDate: body.workDate,
      note: body.note,
    });
    return reply.code(201).send(absence);
  });

  app.patch('/api/v1/admin/leave/:id', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const body = req.body as Partial<{
      startDate: string;
      endDate: string;
      leaveType: string;
      status: string;
      note: string | null;
    }>;
    const existing = await queryOne<LeaveRow & { org_id: string }>(
      `SELECT l.*, e.name AS employee_name, e.employee_code
       FROM employee_leave l JOIN employees e ON e.id = l.employee_id
       WHERE l.id = $1 AND l.org_id = $2`,
      [id, req.admin!.orgId],
    );
    if (!existing) throw notFound('leave record not found');
    const next = {
      startDate: body.startDate ?? String(existing.start_date),
      endDate: body.endDate ?? String(existing.end_date),
      leaveType: body.leaveType ?? existing.leave_type,
      status: body.status ?? existing.status,
    };
    validateLeave(next);
    await queryOne<{ id: string }>(
      `UPDATE employee_leave SET start_date = $3, end_date = $4, leave_type = $5,
         status = $6, note = $7, updated_at = now()
       WHERE id = $1 AND org_id = $2 RETURNING id`,
      [id, req.admin!.orgId, next.startDate, next.endDate, next.leaveType,
       next.status, body.note === undefined ? existing.note : body.note?.trim() || null],
    );
    const row = await queryOne<LeaveRow>(
      `SELECT l.*, e.name AS employee_name, e.employee_code
       FROM employee_leave l JOIN employees e ON e.id = l.employee_id
       WHERE l.id = $1 AND l.org_id = $2`,
      [id, req.admin!.orgId],
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'leave_update',
      targetType: 'employee_leave',
      targetId: id,
      details: { before: leaveDto(existing), after: leaveDto(row!) },
    });
    return reply.send(leaveDto(row!));
  });

  app.get('/api/v1/admin/attendance/absence', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as { from?: string; to?: string };
    const org = await queryOne<{ timezone: string }>('SELECT timezone FROM orgs WHERE id = $1', [req.admin!.orgId]);
    const today = localDate(new Date(), org?.timezone ?? 'UTC');
    const from = q.from ?? `${today.slice(0, 8)}01`;
    const to = q.to ?? today;
    if (!isIsoDate(from) || !isIsoDate(to) || to < from) throw badRequest('invalid absence date range');
    const [employees, sessions, approvedLeave, explicitAbsence] = await Promise.all([
      query<{ id: string; name: string; created_at: string; schedule: Record<string, unknown> }>(
        `SELECT id, name, created_at, schedule FROM employees WHERE org_id = $1 AND status = 'active'`,
        [req.admin!.orgId],
      ),
      query<{ employee_id: string; work_date: string }>(
        `SELECT DISTINCT employee_id, work_date FROM attendance_sessions
         WHERE org_id = $1 AND work_date BETWEEN $2 AND $3
           AND voided_at IS NULL`,
        [req.admin!.orgId, from, to],
      ),
      query<{ employee_id: string; start_date: string; end_date: string }>(
        `SELECT employee_id, start_date, end_date FROM employee_leave
         WHERE org_id = $1 AND status = 'approved' AND leave_type <> 'absence'
           AND end_date >= $2 AND start_date <= $3`,
        [req.admin!.orgId, from, to],
      ),
      query<{ employee_id: string; work_date: string }>(
        `SELECT employee_id, work_date FROM employee_absences
         WHERE org_id = $1 AND work_date BETWEEN $2 AND $3`,
        [req.admin!.orgId, from, to],
      ),
    ]);
    const calculated = calculateAbsence({
      from,
      to,
      today,
      employees: employees.map((employee) => ({
        id: employee.id,
        name: employee.name,
        startDate: localDate(new Date(employee.created_at), org?.timezone ?? 'UTC'),
        schedule: employee.schedule,
      })),
      sessions: sessions.map((session) => ({ employeeId: session.employee_id, workDate: String(session.work_date) })),
      approvedLeave: approvedLeave.map((leave) => ({
        employeeId: leave.employee_id,
        startDate: String(leave.start_date),
        endDate: String(leave.end_date),
      })),
      explicitAbsence: explicitAbsence.map((absence) => ({
        employeeId: absence.employee_id,
        date: String(absence.work_date),
      })),
    });
    return reply.send({ from, to, ...calculated });
  });
}
