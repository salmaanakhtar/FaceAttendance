import { afterAll, describe, expect, it } from 'vitest';
import pg from 'pg';
import { pool } from './db.js';

describe('PostgreSQL DATE parsing', () => {
  it('returns calendar dates as YYYY-MM-DD strings', () => {
    const parser = pg.types.getTypeParser(1082);
    expect(parser('2026-11-06')).toBe('2026-11-06');
  });

  afterAll(async () => {
    await pool.end();
  });
});
