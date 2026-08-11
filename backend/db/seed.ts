import { pool } from '../src/db.js';
import { hashSecret, sha256Hex } from '../src/lib/crypto.js';
import { randomBytes } from 'node:crypto';
import { encryptAesGcm, deriveOrgKey } from '../src/lib/crypto.js';

/**
 * Demo seed: org + site + admin + kiosk device + employees with fake
 * templates (random embeddings — the real enrollment flow replaces them).
 *
 * Credentials (dev only):
 *   admin username: admin   password: admin123
 *   device key: kiosk-demo-001
 */

function randomEmbedding(seed: number): number[] {
  let s = seed;
  const next = () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  };
  const v = Array.from({ length: 128 }, () => next() * 2 - 1);
  const norm = Math.sqrt(v.reduce((a, b) => a + b * b, 0));
  return v.map((x) => x / norm);
}

async function seed() {
  const existing = await pool.query('SELECT id FROM orgs WHERE slug = $1', ['acme-demo']);
  if (existing.rowCount) {
    console.log('already seeded');
    await pool.end();
    return;
  }

  await pool.query('BEGIN');

  const org = (
    await pool.query(
      `INSERT INTO orgs (id, slug, name, timezone, settings, encryption_key)
       VALUES (gen_random_uuid(), 'acme-demo', 'Acme Demo Corp', 'Asia/Karachi', $1, $2) RETURNING id`,
      [
        JSON.stringify({
          minIntervalMinutes: 1,
          breakAfterHours: 6,
          breakMinutes: 30,
          overnightCheckoutCutoff: '06:00',
          shiftGapHours: 4,
        }),
        'acme-demo-encryption-key',
      ],
    )
  ).rows[0] as { id: string };

  const site = (
    await pool.query(
      `INSERT INTO sites (id, org_id, name, timezone) VALUES (gen_random_uuid(), $1, 'HQ Kiosk', 'Asia/Karachi') RETURNING id`,
      [org.id],
    )
  ).rows[0] as { id: string };

  await pool.query(
    `INSERT INTO admins (id, org_id, name, username, password_hash, role)
     VALUES (gen_random_uuid(), $1, 'Demo Admin', 'admin', $2, 'owner')`,
    [org.id, hashSecret('admin123')],
  );

  const deviceKey = 'kiosk-demo-001';
  await pool.query(
    `INSERT INTO devices (id, org_id, site_id, name, device_key_hash)
     VALUES (gen_random_uuid(), $1, $2, 'Demo Kiosk', $3)`,
    [org.id, site.id, sha256Hex(deviceKey)],
  );

  const key = deriveOrgKey('acme-demo-encryption-key');
  const names = [
    'Ayesha Khan', 'Bilal Ahmed', 'Fatima Noor', 'Hassan Raza',
    'Imran Shah', 'Maryam Ali', 'Omar Farooq', 'Sana Tariq',
  ];
  const schedule = {
    shiftStart: '09:00',
    shiftEnd: '18:00',
    graceMinutes: 5,
    minIntervalMinutes: 1,
    overnightCheckoutCutoff: '06:00',
    shiftGapHours: 4,
    breakAfterHours: 6,
    breakMinutes: 30,
    overnight: false,
  };
  for (let i = 0; i < names.length; i++) {
    const name = names[i]!;
    const embedding = randomEmbedding(i + 1);
    const encrypted = encryptAesGcm(Buffer.from(JSON.stringify(embedding), 'utf8'), key);
    await pool.query(
      `INSERT INTO employees (id, org_id, site_id, employee_code, name, email, schedule,
         face_template, template_version, enrollment_quality, enrolled_at)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, 1, $8, now())`,
      [
        org.id, site.id, `E${String(i + 1).padStart(3, '0')}`, name,
        `${name.toLowerCase().replace(/[^a-z]+/g, '.')}@acme.demo`,
        JSON.stringify(schedule),
        encrypted,
        JSON.stringify({ samples: 8, model: 'mobilefacenet-v1', meanConfidence: 0.93 }),
      ],
    );
  }

  await pool.query('COMMIT');
  console.log('seeded: org acme-demo, 1 site, 1 admin (admin/admin123), 1 device, 8 employees');
  console.log(`device key for kiosk provisioning: ${deviceKey}`);
  await pool.end();
}

seed().catch((err) => {
  console.error('seed failed', err);
  process.exit(1);
});
