import type { FastifyInstance } from 'fastify';
import { query, queryOne } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import { encryptAesGcm, decryptAesGcm, deriveOrgKey } from '../lib/crypto.js';
import { audit } from '../services/audit.js';

interface EmployeeRow {
  id: string;
  org_id: string;
  employee_code: string;
  name: string;
  email: string | null;
  phone: string | null;
  status: string;
  schedule: Record<string, unknown>;
  face_template: Buffer | null;
  template_version: number | null;
  enrollment_quality: Record<string, unknown> | null;
  enrolled_at: string | null;
  created_at: string;
}

const employeeBodySchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    employeeCode: { type: 'string', minLength: 1, maxLength: 50 },
    name: { type: 'string', minLength: 1, maxLength: 200 },
    email: { type: ['string', 'null'], maxLength: 200 },
    phone: { type: ['string', 'null'], maxLength: 50 },
    schedule: {
      type: 'object',
      additionalProperties: true,
    },
  },
};

function rowToDto(r: EmployeeRow) {
  return {
    id: r.id,
    employeeCode: r.employee_code,
    name: r.name,
    email: r.email,
    phone: r.phone,
    status: r.status,
    schedule: r.schedule,
    enrolled: !!r.face_template,
    templateVersion: r.template_version,
    enrollmentQuality: r.enrollment_quality,
    enrolledAt: r.enrolled_at,
    createdAt: r.created_at,
  };
}

export function employeeRoutes(app: FastifyInstance): void {
  // List with search + filters
  app.get('/api/v1/admin/employees', { preHandler: requireAdmin }, async (req, reply) => {
    const q = req.query as {
      search?: string;
      status?: string;
      enrolled?: string;
      limit?: string;
      offset?: string;
    };
    const orgId = req.admin!.orgId;
    const where: string[] = ['org_id = $1', "status <> 'deleted'"];
    const params: unknown[] = [orgId];
    if (q.search) {
      params.push(`%${q.search.toLowerCase()}%`);
      where.push(
        `(lower(name) LIKE $${params.length} OR lower(employee_code) LIKE $${params.length} OR lower(coalesce(email,'')) LIKE $${params.length})`,
      );
    }
    if (q.status && q.status !== 'all') {
      params.push(q.status);
      where.push(`status = $${params.length}`);
    }
    if (q.enrolled === 'yes') where.push('face_template IS NOT NULL');
    if (q.enrolled === 'no') where.push('face_template IS NULL');
    const limit = Math.min(Number(q.limit ?? 50), 200);
    const offset = Number(q.offset ?? 0);
    const rows = await query<EmployeeRow>(
      `SELECT * FROM employees WHERE ${where.join(' AND ')}
       ORDER BY name ASC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, limit, offset],
    );
    const total = await queryOne<{ count: string }>(
      `SELECT count(*)::text AS count FROM employees WHERE ${where.join(' AND ')}`,
      params,
    );
    return reply.send({
      employees: rows.map(rowToDto),
      total: Number(total?.count ?? 0),
    });
  });

  app.get('/api/v1/admin/employees/:id', { preHandler: requireAdmin }, async (req, reply) => {
    const row = await queryOne<EmployeeRow>(
      'SELECT * FROM employees WHERE id = $1 AND org_id = $2',
      [(req.params as { id: string }).id, req.admin!.orgId],
    );
    if (!row) throw notFound('employee not found');
    return reply.send(rowToDto(row));
  });

  app.post('/api/v1/admin/employees', { preHandler: requireAdmin }, async (req, reply) => {
    const body = req.body as {
      employeeCode?: string;
      name: string;
      email?: string | null;
      phone?: string | null;
      schedule?: Record<string, unknown>;
    };
    if (!body.name?.trim()) throw badRequest('name required');
    const code = body.employeeCode?.trim() || `E${Date.now().toString(36).toUpperCase()}`;
    const dup = await queryOne('SELECT id FROM employees WHERE org_id = $1 AND employee_code = $2', [
      req.admin!.orgId,
      code,
    ]);
    if (dup) throw conflict('employee code already exists');
    const row = await queryOne<EmployeeRow>(
      `INSERT INTO employees (id, org_id, employee_code, name, email, phone, schedule)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6) RETURNING *`,
      [
        req.admin!.orgId,
        code,
        body.name.trim(),
        body.email ?? null,
        body.phone ?? null,
        JSON.stringify(body.schedule ?? {}),
      ],
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'employee_create',
      targetType: 'employee',
      targetId: row!.id,
      details: { employeeCode: code, name: body.name.trim() },
    });
    return reply.code(201).send(rowToDto(row!));
  });

  app.patch('/api/v1/admin/employees/:id', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const body = req.body as Partial<{
      name: string;
      email: string | null;
      phone: string | null;
      schedule: Record<string, unknown>;
    }>;
    const existing = await queryOne<EmployeeRow>(
      'SELECT * FROM employees WHERE id = $1 AND org_id = $2',
      [id, req.admin!.orgId],
    );
    if (!existing) throw notFound('employee not found');
    const fields: string[] = [];
    const params: unknown[] = [];
    const set = (col: string, val: unknown) => {
      params.push(val);
      fields.push(`${col} = $${params.length}`);
    };
    if (body.name !== undefined) set('name', body.name.trim());
    if (body.email !== undefined) set('email', body.email);
    if (body.phone !== undefined) set('phone', body.phone);
    if (body.schedule !== undefined) set('schedule', JSON.stringify(body.schedule));
    if (!fields.length) return reply.send(rowToDto(existing));
    params.push(id, req.admin!.orgId);
    const row = await queryOne<EmployeeRow>(
      `UPDATE employees SET ${fields.join(', ')}, updated_at = now() WHERE id = $${params.length - 1} AND org_id = $${params.length} RETURNING *`,
      params,
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'employee_update',
      targetType: 'employee',
      targetId: id,
      details: { fields: Object.keys(body) },
    });
    return reply.send(rowToDto(row!));
  });

  app.post('/api/v1/admin/employees/:id/deactivate', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const row = await queryOne<EmployeeRow>(
      `UPDATE employees SET status = 'inactive', updated_at = now() WHERE id = $1 AND org_id = $2 RETURNING *`,
      [id, req.admin!.orgId],
    );
    if (!row) throw notFound('employee not found');
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'employee_deactivate',
      targetType: 'employee',
      targetId: id,
      details: { name: row.name },
    });
    return reply.send(rowToDto(row));
  });

  app.post('/api/v1/admin/employees/:id/delete', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const row = await queryOne<EmployeeRow>(
      `UPDATE employees SET status = 'deleted', face_template = NULL, template_version = NULL,
         enrollment_quality = NULL, updated_at = now()
       WHERE id = $1 AND org_id = $2 RETURNING *`,
      [id, req.admin!.orgId],
    );
    if (!row) throw notFound('employee not found');
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'employee_delete',
      targetType: 'employee',
      targetId: id,
      details: { name: row.name, employeeCode: row.employee_code },
    });
    return reply.send({ ok: true, id });
  });

  // Enrollment: fused embedding + quality metadata. Server encrypts at rest.
  app.post('/api/v1/admin/employees/:id/enroll', { preHandler: requireAdmin }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const body = req.body as {
      embedding: number[];
      templateVersion?: number;
      quality?: Record<string, unknown>;
    };
    if (!Array.isArray(body.embedding) || body.embedding.length < 64 || body.embedding.length > 1024) {
      throw badRequest('embedding must be a 64..1024 length vector');
    }
    if (body.embedding.some((v) => typeof v !== 'number' || !Number.isFinite(v))) {
      throw badRequest('embedding contains non-finite values');
    }
    const existing = await queryOne<EmployeeRow>(
      'SELECT * FROM employees WHERE id = $1 AND org_id = $2',
      [id, req.admin!.orgId],
    );
    if (!existing) throw notFound('employee not found');

    // duplicate-face guard: reject enrolling a face already enrolled to another employee.
    // Only templates from the same pipeline version are comparable — older
    // versions live in a different embedding space and must not be matched
    // (that caused false "same person" hits after the channel-order fix).
    const org = await queryOne<{ encryption_key: string }>(
      'SELECT encryption_key FROM orgs WHERE id = $1',
      [req.admin!.orgId],
    );
    const key = deriveOrgKey(org?.encryption_key ?? 'dev');
    const templateVersion = body.templateVersion ?? 1;
    const allTemplates = await query<{
      id: string;
      name: string;
      employee_code: string;
      face_template: Buffer;
      template_version: number | null;
    }>(
      `SELECT id, name, employee_code, face_template, template_version FROM employees
        WHERE org_id = $1 AND status = 'active' AND face_template IS NOT NULL AND id <> $2`,
      [req.admin!.orgId, id],
    );
    const cosine = (a: number[], b: number[]): number => {
      let dot = 0, na = 0, nb = 0;
      for (let i = 0; i < a.length; i++) {
        dot += a[i]! * b[i]!;
        na += a[i]! * a[i]!;
        nb += b[i]! * b[i]!;
      }
      return dot / (Math.sqrt(na) * Math.sqrt(nb));
    };
    const SAME_FACE = 0.6; // conservative "same person" distance
    for (const t of allTemplates) {
      if ((t.template_version ?? 0) !== templateVersion) continue;
      let other: number[] | null = null;
      try {
        other = JSON.parse(decryptAesGcm(t.face_template, key).toString('utf8')) as number[];
      } catch {
        continue;
      }
      if (other && body.embedding.length === other.length && cosine(body.embedding, other) > SAME_FACE) {
        throw conflict(
          `this face is already enrolled to active employee ${t.name} (${t.employee_code}). ` +
            `Open that employee to re-enroll, or deactivate the obsolete record first ` +
            `(cosine ${cosine(body.embedding, other).toFixed(2)})`,
        );
      }
    }

    const encrypted = encryptAesGcm(Buffer.from(JSON.stringify(body.embedding), 'utf8'), key);
    const row = await queryOne<EmployeeRow>(
      `UPDATE employees SET face_template = $2, template_version = $3, enrollment_quality = $4,
         enrolled_at = now(), updated_at = now()
       WHERE id = $1 AND org_id = $5 RETURNING *`,
      [id, encrypted, body.templateVersion ?? 1, JSON.stringify(body.quality ?? {}), req.admin!.orgId],
    );
    await audit({
      orgId: req.admin!.orgId,
      actorType: 'admin',
      actorId: req.admin!.id,
      action: 'employee_enroll',
      targetType: 'employee',
      targetId: id,
      details: { templateVersion: body.templateVersion ?? 1, quality: body.quality ?? {} },
    });
    return reply.send(rowToDto(row!));
  });
}
