import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = join(__dirname, 'migrations');
const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://postgres@127.0.0.1:5434/faceattendance';

const bootstrap = new Pool({
  connectionString: DATABASE_URL.replace(/\/[^/]+$/, '/postgres'),
});
bootstrap.on('error', () => {});

function parseUrl(url: string) {
  const m = url.match(/^postgres:\/\/([^:]+)(?::([^@]+))?@([^:]+):(\d+)\/(.+)$/);
  if (!m) return {};
  return { user: m[1], password: m[2] ?? undefined, host: m[3], port: Number(m[4]), database: m[5] };
}

async function ensureDatabase() {
  const parsed = parseUrl(DATABASE_URL);
  const client = await bootstrap.connect();
  try {
    const exists = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [parsed.database]);
    if (exists.rowCount === 0) {
      await client.query(`CREATE DATABASE "${parsed.database}"`);
      console.log(`created database ${parsed.database}`);
    }
  } finally {
    client.release();
  }
}

async function migrate() {
  await ensureDatabase();
  const pool = new Pool({ connectionString: DATABASE_URL });
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    filename text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
  )`);
  const applied = new Set(
    (await pool.query('SELECT filename FROM schema_migrations')).rows.map((r) => r.filename),
  );
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
      await client.query('COMMIT');
      console.log(`applied ${file}`);
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
  await pool.end();
  console.log('migrations up to date');
}

migrate().catch((err) => {
  console.error('migration failed:', err);
  process.exit(1);
});
