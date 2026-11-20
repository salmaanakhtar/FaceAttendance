import { query } from '../db.js';

export interface AuditInput {
  orgId?: string | null;
  actorType: 'admin' | 'device' | 'system';
  actorId?: string | null;
  action: string;
  targetType?: string | null;
  targetId?: string | null;
  details?: Record<string, unknown> | null;
}

export async function audit(input: AuditInput): Promise<void> {
  await query(
    `INSERT INTO audit_events (org_id, actor_type, actor_id, action, target_type, target_id, details)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [
      input.orgId ?? null,
      input.actorType,
      input.actorId ?? null,
      input.action,
      input.targetType ?? null,
      input.targetId ?? null,
      input.details ? JSON.stringify(input.details) : null,
    ],
  );
}
