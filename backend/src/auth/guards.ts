import type { FastifyRequest, FastifyReply } from 'fastify';
import { queryOne } from '../db.js';
import { unauthorized } from '../lib/errors.js';
import { verifyToken, type TokenPayload } from './tokens.js';

declare module 'fastify' {
  interface FastifyRequest {
    token?: TokenPayload;
    admin?: { id: string; orgId: string; name: string; role: string };
    device?: { id: string; orgId: string };
  }
}

export async function authenticate(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'missing token' } });
  }
  const token = await verifyToken(header.slice(7));
  if (!token) {
    return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'invalid token' } });
  }
  req.token = token;
}

export async function requireDevice(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  await authenticate(req, reply);
  if (!req.token || req.token.kind !== 'device') {
    return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'device token required' } });
  }
  const device = await queryOne<{ id: string; org_id: string; status: string }>(
    'SELECT id, org_id, status FROM devices WHERE id = $1',
    [req.token.sub],
  );
  if (!device || device.status !== 'active') {
    return reply.code(401).send({ error: { code: 'DEVICE_DISABLED', message: 'device not active' } });
  }
  req.device = { id: device.id, orgId: device.org_id };
}

export async function requireAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  await authenticate(req, reply);
  if (!req.token || req.token.kind !== 'admin') {
    return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'admin token required' } });
  }
  const admin = await queryOne<{ id: string; org_id: string; name: string; role: string; active: boolean }>(
    'SELECT id, org_id, name, role, active FROM admins WHERE id = $1',
    [req.token.sub],
  );
  if (!admin || !admin.active) {
    return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'admin not active' } });
  }
  if (admin.org_id !== req.token.org) {
    return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'org mismatch' } });
  }
  req.admin = { id: admin.id, orgId: admin.org_id, name: admin.name, role: admin.role };
}

export function appError(reply: FastifyReply, err: unknown): void {
  const e = err as { status?: number; code?: string; message?: string };
  const status = e.status ?? 500;
  if (status >= 500) console.error('[error]', e);
  void reply.code(status).send({
    error: { code: e.code ?? 'INTERNAL', message: e.message ?? 'internal error' },
  });
}
