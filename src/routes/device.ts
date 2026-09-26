import type { FastifyInstance } from 'fastify';
import { query, queryOne } from '../db.js';
import { signDeviceToken } from '../auth/tokens.js';
import { requireDevice } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { sha256Hex } from '../lib/crypto.js';
import { ingestScan } from '../services/attendance/service.js';
import { audit } from '../services/audit.js';
import { decryptAesGcm, deriveOrgKey } from '../lib/crypto.js';

const deviceSchema = {
  body: {
    type: 'object',
    required: ['deviceKey', 'name'],
    properties: {
      deviceKey: { type: 'string', minLength: 8, maxLength: 200 },
      name: { type: 'string', minLength: 1, maxLength: 100 },
    },
    additionalProperties: false,
  },
};

const scanSchema = {
  body: {
    type: 'object',
    required: ['dedupeKey', 'employeeId'],
    properties: {
      dedupeKey: { type: 'string', minLength: 16, maxLength: 128 },
      employeeId: { type: 'string', minLength: 1, maxLength: 100 },
      deviceTime: { type: 'string', maxLength: 40 },
      directionHint: { type: 'string', enum: ['in', 'out'] },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
      livenessScore: { type: 'number', minimum: 0, maximum: 1 },
      faceHash: { type: 'string', maxLength: 128 },
      syncState: { type: 'string', enum: ['live', 'offline'] },
    },
    additionalProperties: false,
  },
};

export function deviceRoutes(app: FastifyInstance): void {
  // Handshake: exchange provisioned device key for a device token.
  app.post('/api/v1/device/handshake', {
    schema: deviceSchema,
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
  }, async (req, reply) => {
    const { deviceKey, name } = req.body as { deviceKey: string; name: string };
    const hash = sha256Hex(deviceKey);
    const device = await queryOne<{ id: string; org_id: string; site_id: string | null; status: string }>(
      'SELECT id, org_id, site_id, status FROM devices WHERE device_key_hash = $1',
      [hash],
    );
    if (!device) {
      await audit({ actorType: 'system', action: 'handshake_failed', details: { reason: 'unknown device key' } });
      throw notFound('device not recognized');
    }
    if (device.status !== 'active') throw badRequest('device disabled');
    const token = await signDeviceToken(device.id, device.org_id);
    await query('UPDATE devices SET last_seen_at = now(), name = $2 WHERE id = $1', [device.id, name]);
    await audit({
      orgId: device.org_id,
      actorType: 'device',
      actorId: device.id,
      action: 'device_handshake',
    });
    const org = await queryOne<{ name: string; timezone: string; settings: Record<string, unknown> }>(
      'SELECT name, timezone, settings FROM orgs WHERE id = $1',
      [device.org_id],
    );
    return reply.send({
      token,
      org: org ? { id: device.org_id, name: org.name, timezone: org.timezone, settings: org.settings } : null,
      siteId: device.site_id,
      deviceId: device.id,
    });
  });

  // Scan ingest — the critical path. Server time authoritative; idempotent.
  // Rate limited per device so a person standing at the kiosk cannot
  // hammer the server (client-side presence lockout is the first line).
  app.post('/api/v1/scans', {
    schema: scanSchema,
    preHandler: requireDevice,
    config: { rateLimit: { max: 10, timeWindow: '10 seconds' } },
  }, async (req, reply) => {
    const body = req.body as {
      dedupeKey: string;
      employeeId: string;
      deviceTime?: string;
      directionHint?: 'in' | 'out';
      confidence?: number;
      livenessScore?: number;
      faceHash?: string;
      syncState?: 'live' | 'offline';
    };
    const result = await ingestScan({
      deviceId: req.device!.id,
      orgId: req.device!.orgId,
      dedupeKey: body.dedupeKey,
      deviceTime: body.deviceTime ?? null,
      directionHint: body.directionHint ?? null,
      employeeId: body.employeeId,
      confidence: body.confidence ?? null,
      livenessScore: body.livenessScore ?? null,
      faceHash: body.faceHash ?? null,
      syncState: body.syncState ?? 'live',
    });
    return reply.code(result.action === 'check_in' || result.action === 'check_out' ? 201 : 200).send(result);
  });

  // Template bundle for kiosk sync: active employees' encrypted embeddings,
  // decrypted server-side and shipped over TLS to the authenticated device.
  app.get('/api/v1/device/templates', { preHandler: requireDevice }, async (req, reply) => {
    const org = await queryOne<{ encryption_key: string | null; settings: Record<string, unknown> }>(
      'SELECT encryption_key, settings FROM orgs WHERE id = $1',
      [req.device!.orgId],
    );
    const rows = await query<{
      id: string;
      name: string;
      employee_code: string;
      face_template: Buffer | null;
      template_version: number | null;
      enrollment_quality: Record<string, unknown> | null;
    }>(
      `SELECT id, name, employee_code, face_template, template_version, enrollment_quality
       FROM employees WHERE org_id = $1 AND status = 'active'`,
      [req.device!.orgId],
    );
    const key = deriveOrgKey(org?.encryption_key ?? 'dev');
    const templates = rows
      .filter((r) => r.face_template)
      .map((r) => {
        let embedding: number[] | null = null;
        try {
          const dec = decryptAesGcm(r.face_template!, key);
          embedding = JSON.parse(dec.toString('utf8')) as number[];
        } catch {
          embedding = null;
        }
        return {
          employeeId: r.id,
          name: r.name,
          employeeCode: r.employee_code,
          embedding,
          templateVersion: r.template_version,
          quality: r.enrollment_quality,
        };
      })
      .filter((t) => t.embedding);
    return reply.send({ orgId: req.device!.orgId, model: 'mobilefacenet-v1', templates });
  });

  // Lightweight kiosk roster for code-based attendance. Unlike templates,
  // this includes every active worker, including workers without a face
  // enrollment. It never exposes biometric data.
  app.get('/api/v1/device/employees', { preHandler: requireDevice }, async (req, reply) => {
    const rows = await query<{ id: string; name: string; employee_code: string }>(
      `SELECT id, name, employee_code FROM employees
       WHERE org_id = $1 AND status = 'active' ORDER BY name ASC`,
      [req.device!.orgId],
    );
    return reply.send({
      employees: rows.map((r) => ({ id: r.id, name: r.name, employeeCode: r.employee_code })),
    });
  });

  app.get('/api/v1/device/config', { preHandler: requireDevice }, async (req, reply) => {
    const org = await queryOne<{ name: string; timezone: string; settings: Record<string, unknown> }>(
      'SELECT name, timezone, settings FROM orgs WHERE id = $1',
      [req.device!.orgId],
    );
    const device = await queryOne<{ clock_offset_ms: number }>(
      'SELECT clock_offset_ms FROM devices WHERE id = $1',
      [req.device!.id],
    );
    const now = new Date();
    return reply.send({
      orgName: org?.name,
      timezone: org?.timezone,
      settings: org?.settings ?? {},
      serverTime: now.toISOString(),
      clockOffsetMs: device?.clock_offset_ms ?? 0,
    });
  });
}

