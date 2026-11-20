import type { FastifyInstance } from 'fastify';
import { pool, query } from '../db.js';
import { requireAdmin } from '../auth/guards.js';
import { hashSecret } from '../lib/crypto.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';

// Existing owners/admins retain their permissions. This surface only manages
// limited accounts, so it cannot remove the last owner or escalate a role.
export function teamRoutes(app: FastifyInstance): void {
  app.get('/api/v1/admin/team', { preHandler: requireAdmin }, async req => ({
    members: await query('SELECT id, name, username, role, active FROM admins WHERE org_id = $1 ORDER BY name', [req.admin!.orgId]),
  }));
  app.post('/api/v1/admin/team', { preHandler: requireAdmin, schema: { body: {
    type: 'object', additionalProperties: false, required: ['name', 'username', 'password', 'role'],
    properties: { name: { type: 'string', minLength: 1, maxLength: 200 },
      username: { type: 'string', minLength: 3, maxLength: 100 },
      password: { type: 'string', minLength: 12, maxLength: 200 },
      role: { type: 'string', enum: ['supervisor', 'viewer'] } },
  } } }, async (req, reply) => {
    const body = req.body as { name: string; username: string; password: string; role: string };
    if (!body.name.trim() || !/^[a-zA-Z0-9._-]+$/.test(body.username)) throw badRequest('Use a name and a username containing letters, numbers, dots, hyphens or underscores');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `INSERT INTO admins (org_id, name, username, password_hash, role) VALUES ($1,$2,$3,$4,$5) RETURNING id, name, username, role, active`,
        [req.admin!.orgId, body.name.trim(), body.username, hashSecret(body.password), body.role]);
      await client.query(`INSERT INTO audit_events (org_id, actor_type, actor_id, action, details)
        VALUES ($1,'admin',$2,'create_team_member',$3::jsonb)`,
        [req.admin!.orgId, req.admin!.id, JSON.stringify({ memberId: result.rows[0].id, role: body.role })]);
      await client.query('COMMIT');
      return reply.code(201).send(result.rows[0]);
    } catch (error) {
      await client.query('ROLLBACK');
      if ((error as { code?: string }).code === '23505') throw conflict('That username is already in use');
      throw error;
    } finally { client.release(); }
  });
  app.patch('/api/v1/admin/team/:id', { preHandler: requireAdmin, schema: { body: {
    type: 'object', additionalProperties: false, required: ['active'],
    properties: { active: { type: 'boolean' } },
  } } }, async req => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const id = (req.params as { id: string }).id;
      const active = (req.body as { active: boolean }).active;
      const result = await client.query(`UPDATE admins SET active = $1 WHERE id::text = $2 AND org_id = $3
        AND role IN ('supervisor','viewer') RETURNING id, name, username, role, active`, [active, id, req.admin!.orgId]);
      if (!result.rows[0]) throw notFound('Limited account not found');
      await client.query('UPDATE admin_sessions SET revoked_at = now() WHERE admin_id::text = $1 AND revoked_at IS NULL', [id]);
      await client.query(`INSERT INTO audit_events (org_id, actor_type, actor_id, action, details)
        VALUES ($1,'admin',$2,'set_team_access',$3::jsonb)`, [req.admin!.orgId, req.admin!.id, JSON.stringify({ memberId: id, active })]);
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  });
}
