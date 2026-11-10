import 'dotenv/config';
import pg from 'pg';
import { config } from './config.js';

const { Pool, types } = pg;

// DATE columns represent calendar days, not instants. Letting node-postgres
// turn them into JS Dates shifts the day when the server timezone differs from
// the org timezone. Keep them as YYYY-MM-DD strings.
types.setTypeParser(1082, (value: string) => value);

export const pool = new Pool({ connectionString: config.databaseUrl, max: 10 });
pool.on('error', (err) => console.error('pg pool error', err));

export type Row = Record<string, unknown>;

export async function query<T = Row>(text: string, params: unknown[] = []): Promise<T[]> {
  const res = await pool.query(text, params);
  return res.rows as T[];
}

export async function queryOne<T = Row>(
  text: string,
  params: unknown[] = [],
): Promise<T | null> {
  const res = await pool.query(text, params);
  return (res.rows[0] as T) ?? null;
}
