import { afterEach, describe, expect, it, vi } from 'vitest';
import Fastify from 'fastify';
vi.mock('../db.js', () => ({ queryOne: vi.fn(), query: vi.fn(), pool: { connect: vi.fn() } }));
vi.mock('../auth/tokens.js', () => ({ verifyToken: vi.fn() }));
import { queryOne, pool } from '../db.js';
import { verifyToken } from '../auth/tokens.js';
import { appError } from '../auth/guards.js';
import { teamRoutes } from './team.js';

async function setup(role = 'admin', found = true) {
  vi.mocked(verifyToken).mockResolvedValue({ sub: 'admin-a', org: 'org-a', kind: 'admin' });
  vi.mocked(queryOne).mockResolvedValue({ id: 'admin-a', org_id: 'org-a', name: 'Admin', role, active: true });
  const sql = vi.fn(async (statement: string) => ({ rows: statement.includes('RETURNING') && found ? [{ id: 'limited', name: 'Worker', role: 'viewer', active: true }] : [] }));
  vi.mocked(pool.connect).mockResolvedValue({ query: sql, release: vi.fn() } as never);
  const app = Fastify();
  app.setErrorHandler((error, _req, reply) => appError(reply, error));
  teamRoutes(app);
  return { app, sql };
}

describe('limited team accounts', () => {
  afterEach(() => vi.resetAllMocks());
  const member = { name: 'Worker', username: 'worker.viewer', password: 'long-test-password', role: 'viewer' };
  it('does not allow creating a privileged role through the limited-account endpoint', async () => {
    const { app } = await setup();
    try {
      const response = await app.inject({ method: 'POST', url: '/api/v1/admin/team', headers: { authorization: 'Bearer test' }, payload: { ...member, role: 'owner' } });
      expect(response.statusCode).toBe(400);
      expect(pool.connect).not.toHaveBeenCalled();
    } finally { await app.close(); }
  });
  it('denies account creation to a viewer', async () => {
    const { app } = await setup('viewer');
    try {
      const response = await app.inject({ method: 'POST', url: '/api/v1/admin/team', headers: { authorization: 'Bearer test' }, payload: member });
      expect(response.statusCode).toBe(403);
      expect(pool.connect).not.toHaveBeenCalled();
    } finally { await app.close(); }
  });
  it('creates and audits atomically without storing the plaintext password', async () => {
    const { app, sql } = await setup();
    try {
      const response = await app.inject({ method: 'POST', url: '/api/v1/admin/team', headers: { authorization: 'Bearer test' }, payload: member });
      expect(response.statusCode).toBe(201);
      const calls = sql.mock.calls as unknown as [string, unknown[]][];
      const insert = calls.find(([s]) => s.includes('INSERT INTO admins'))!;
      expect(insert[1][0]).toBe('org-a');
      expect(String(insert[1][3])).toMatch(/^scrypt\$/);
      const audit = calls.find(([s]) => s.includes('INSERT INTO audit_events'))!;
      expect(JSON.stringify(audit)).not.toContain(member.password);
      expect(calls.at(-1)?.[0]).toBe('COMMIT');
    } finally { await app.close(); }
  });
  it('limits account changes to the same organization and revokes refresh sessions', async () => {
    const { app, sql } = await setup();
    try {
      const response = await app.inject({ method: 'PATCH', url: '/api/v1/admin/team/limited', headers: { authorization: 'Bearer test' }, payload: { active: false } });
      expect(response.statusCode).toBe(200);
      const calls = sql.mock.calls as unknown as [string, unknown[]][];
      const update = calls.find(([s]) => s.includes('UPDATE admins'))!;
      expect(update[0]).toContain("role IN ('supervisor','viewer')");
      expect(update[1]).toEqual([false, 'limited', 'org-a']);
      expect(calls.some(([s]) => s.includes('UPDATE admin_sessions'))).toBe(true);
      expect(calls.at(-1)?.[0]).toBe('COMMIT');
    } finally { await app.close(); }
  });
  it('rolls back when a target account is outside the allowed scope', async () => {
    const { app, sql } = await setup('admin', false);
    try {
      const response = await app.inject({ method: 'PATCH', url: '/api/v1/admin/team/other-org', headers: { authorization: 'Bearer test' }, payload: { active: false } });
      expect(response.statusCode).toBe(404);
      expect(sql.mock.calls.at(-1)?.[0]).toBe('ROLLBACK');
    } finally { await app.close(); }
  });
});
