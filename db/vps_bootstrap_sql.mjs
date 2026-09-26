/**
 * Generates INSERT SQL for a clean VPS bootstrap (empty DB after reset):
 * - org: Yabil (Africa/Johannesburg)
 * - admin: admin / admin123
 * - device key: device@yabil
 * - NO employees
 * Run: node db/vps_bootstrap_sql.mjs > bootstrap.sql
 */
import { randomBytes, createHash, scryptSync } from 'node:crypto';

const ORG_ID = randomBytes(16).toString('hex');
const ADMIN_ID = randomBytes(16).toString('hex');
const DEVICE_ID = randomBytes(16).toString('hex');

function sha256Hex(input) {
  return createHash('sha256').update(input).digest('hex');
}

const out = [];
out.push(`INSERT INTO orgs (id, slug, name, timezone, settings, encryption_key)
  VALUES ('${ORG_ID}', 'yabil', 'Yabil', 'Africa/Johannesburg', '{}'::jsonb, 'yabil-encryption-key');`);

const salt = randomBytes(16).toString('hex');
const hash = scryptSync('admin123', salt, 64).toString('hex');
out.push(`INSERT INTO admins (id, org_id, name, username, password_hash, role)
  VALUES ('${ADMIN_ID}', '${ORG_ID}', 'Yabil Admin', 'admin', 'scrypt$${salt}$${hash}', 'owner');`);

out.push(`INSERT INTO devices (id, org_id, name, device_key_hash, status)
  VALUES ('${DEVICE_ID}', '${ORG_ID}', 'Yabil Kiosk', '${sha256Hex('device@yabil')}', 'active');`);

out.push(`INSERT INTO sites (id, org_id, name, timezone)
  VALUES (gen_random_uuid(), '${ORG_ID}', 'Head Office', 'Africa/Johannesburg');`);

out.push(`SELECT 'org: ' || name FROM orgs;`);
out.push(`SELECT 'device key: device@yabil hash: ' || substring(device_key_hash,1,16) || '...' FROM devices;`);

console.log(out.join('\n'));
