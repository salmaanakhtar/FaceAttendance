import { afterEach, describe, expect, it, vi } from 'vitest';
import Fastify from 'fastify';
vi.mock('../db.js', () => ({ queryOne: vi.fn() }));
vi.mock('./tokens.js', () => ({ verifyToken: vi.fn() }));
import { queryOne } from '../db.js';
import { verifyToken } from './tokens.js';
import { requireAdmin } from './guards.js';

describe('server authorization enforcement', () => {
  afterEach(() => vi.resetAllMocks());
  it.each([
    ['viewer', 'POST', '/api/v1/admin/corrections', 403],
    ['viewer', 'GET', '/api/v1/admin/attendance', 200],
    ['supervisor', 'POST', '/api/v1/admin/corrections', 200],
    ['supervisor', 'POST', '/api/v1/admin/payroll/report', 403],
    ['admin', 'POST', '/api/v1/admin/payroll/report', 200],
    ['viewer', 'PATCH', '/api/v1/admin/team/id', 403],
  ])('%s %s %s returns %s', async (role, method, url, status) => {
    vi.mocked(verifyToken).mockResolvedValue({ sub: 'a', org: 'o', kind: 'admin' });
    vi.mocked(queryOne).mockResolvedValue({ id: 'a', org_id: 'o', name: 'Test', role, active: true });
    const app = Fastify();
    const handler = vi.fn(async () => ({ ok: true }));
    app.route({ method: method as 'GET' | 'POST' | 'PATCH', url: String(url), preHandler: requireAdmin, handler });
    try {
      const response = await app.inject({ method: method as 'GET' | 'POST' | 'PATCH', url: String(url), headers: { authorization: 'Bearer test' } });
      expect(response.statusCode).toBe(status);
      expect(handler).toHaveBeenCalledTimes(status === 200 ? 1 : 0);
    } finally { await app.close(); }
  });
});
