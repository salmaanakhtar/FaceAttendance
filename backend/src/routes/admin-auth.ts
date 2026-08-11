import type { FastifyInstance } from 'fastify';
import { randomBytes } from 'node:crypto';
import { query, queryOne } from '../db.js';
import { config } from '../config.js';
import { sha256Hex, verifySecret } from '../lib/crypto.js';
import { requireAdmin } from '../auth/guards.js';
import { signAdminAccessToken } from '../auth/tokens.js';
import { badRequest, unauthorized } from '../lib/errors.js';
import { audit } from '../services/audit.js';

const loginSchema = {
  body: {
    type: 'object',
    required: ['username', 'password'],
    properties: {
      username: { type: 'string', minLength: 1, maxLength: 100 },
      password: { type: 'string', minLength: 1, maxLength: 200 },
      deviceId: { type: 'string', maxLength: 100 },
    },
    additionalProperties: false,
  },
};

export function adminAuthRoutes(app: FastifyInstance): void {
  app.post('/api/v1/admin/login', { schema: loginSchema }, async (req, reply) => {
    const { username, password, deviceId } = req.body as {
      username: string;
      password: string;
      deviceId?: string;
    };
    const admin = await queryOne<{
      id: string;
      org_id: string;
      name: string;
      role: string;
      active: boolean;
      password_hash: string;
    }>('SELECT * FROM admins WHERE username = $1', [username]);

    if (!admin || !verifySecret(password, admin.password_hash) || !admin.active) {
      await audit({
        actorType: 'admin',
        action: 'login_failed',
        details: { username, ip: req.ip },
      });
      throw unauthorized('invalid credentials');
    }

    const refreshToken = randomBytes(32).toString('hex');
    await query(
      `INSERT INTO admin_sessions (id, admin_id, device_id, token_hash, expires_at)
       VALUES (gen_random_uuid(), $1, $2, $3, now() + interval '1 hour' * $4)`,
      [admin.id, deviceId ?? null, sha256Hex(refreshToken), config.adminSessionTtlSec / 3600],
    );
    const accessToken = await signAdminAccessToken(admin.id, admin.org_id);
    await audit({
      orgId: admin.org_id,
      actorType: 'admin',
      actorId: admin.id,
      action: 'login',
      details: { deviceId: deviceId ?? null },
    });
    return reply.send({
      accessToken,
      refreshToken,
      expiresInSec: config.jwtAdminTtlSec,
      admin: { id: admin.id, name: admin.name, role: admin.role, orgId: admin.org_id },
    });
  });

  app.post('/api/v1/admin/refresh', async (req) => {
    const body = req.body as { refreshToken?: string };
    if (!body?.refreshToken) throw badRequest('refreshToken required');
    const session = await queryOne<{
      id: string;
      admin_id: string;
      expires_at: string;
      revoked_at: string | null;
    }>(
      'SELECT id, admin_id, expires_at, revoked_at FROM admin_sessions WHERE token_hash = $1',
      [sha256Hex(body.refreshToken)],
    );
    if (!session || session.revoked_at || new Date(session.expires_at) < new Date()) {
      throw unauthorized('refresh token invalid');
    }
    const admin = await queryOne<{ id: string; org_id: string; active: boolean }>(
      'SELECT id, org_id, active FROM admins WHERE id = $1',
      [session.admin_id],
    );
    if (!admin?.active) throw unauthorized('admin inactive');
    const accessToken = await signAdminAccessToken(admin.id, admin.org_id);
    return { accessToken, expiresInSec: config.jwtAdminTtlSec };
  });

  app.post('/api/v1/admin/logout', async (req) => {
    const body = req.body as { refreshToken?: string };
    if (body?.refreshToken) {
      await query('UPDATE admin_sessions SET revoked_at = now() WHERE token_hash = $1', [
        sha256Hex(body.refreshToken),
      ]);
    }
    return { ok: true };
  });

  app.get('/api/v1/admin/me', { preHandler: requireAdmin }, async (req) => {
    return req.admin;
  });
}
