/**
 * Generates SQL to bootstrap the VPS database with the Yabil org identity:
 * renames the platform org, resets admin password, sets the kiosk device
 * key, and inserts the 8 seed employees with encrypted templates.
 * Run: node db/vps_bootstrap_sql.mjs > bootstrap.sql
 */
import { randomBytes, createHash, createCipheriv, scryptSync } from 'node:crypto';

const IV_LEN = 12;

function encryptAesGcm(plain, key) {
  const iv = randomBytes(IV_LEN);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]);
}

function deriveOrgKey(orgSecret) {
  return scryptSync(`faceatt:org:${orgSecret}`, 'faceatt-org-salt', 32);
}

function sha256Hex(input) {
  return createHash('sha256').update(input).digest('hex');
}

const ORG_ID = '9711a4d4-8c25-4714-b01a-16c9c9edcc89';

function randomEmbedding(seed) {
  let s = seed;
  const next = () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  };
  const v = Array.from({ length: 128 }, () => next() * 2 - 1);
  const norm = Math.sqrt(v.reduce((a, b) => a + b * b, 0));
  return v.map((x) => x / norm);
}

const out = [];
out.push(`UPDATE orgs SET name = 'Yabil', slug = 'yabil', timezone = 'Asia/Karachi', encryption_key = 'yabil-encryption-key' WHERE id = '${ORG_ID}';`);

// admin password: admin123 (scrypt)
const salt = randomBytes(16).toString('hex');
const hash = scryptSync('admin123', salt, 64).toString('hex');
out.push(`UPDATE admins SET password_hash = 'scrypt$${salt}$${hash}', name = 'Yabil Admin' WHERE username = 'admin';`);

// device key: kiosk-demo-001
out.push(`UPDATE devices SET device_key_hash = '${sha256Hex('kiosk-demo-001')}' WHERE name = 'Kiosk';`);

const key = deriveOrgKey('yabil-encryption-key');
const schedule = {
  shiftStart: '09:00', shiftEnd: '18:00', graceMinutes: 5,
  minIntervalMinutes: 1, overnightCheckoutCutoff: '06:00',
  shiftGapHours: 4, breakAfterHours: 6, breakMinutes: 30, overnight: false,
};
const names = [
  'Ayesha Khan', 'Bilal Ahmed', 'Fatima Noor', 'Hassan Raza',
  'Imran Shah', 'Maryam Ali', 'Omar Farooq', 'Sana Tariq',
];
names.forEach((name, i) => {
  const emb = randomEmbedding(i + 1);
  const encrypted = encryptAesGcm(Buffer.from(JSON.stringify(emb), 'utf8'), key);
  const code = `E${String(i + 1).padStart(3, '0')}`;
  const email = `${name.toLowerCase().replace(/[^a-z]+/g, '.')}@yabil.dev`;
  const quality = JSON.stringify({ samples: 8, model: 'mobilefacenet-v1', meanConfidence: 0.93 }).replaceAll("'", "''");
  out.push(`INSERT INTO employees (id, org_id, employee_code, name, email, schedule, face_template, template_version, enrollment_quality, enrolled_at)
    VALUES (gen_random_uuid(), '${ORG_ID}', '${code}', '${name}', '${email}', '${JSON.stringify(schedule).replaceAll("'", "''")}', decode('${encrypted.toString('hex')}', 'hex'), 1, '${quality}', now());`);
});

console.log(out.join('\n'));
