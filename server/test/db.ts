import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { migrate } from '../src/db/migrate.js';
import type { Db } from '../src/db/pool.js';

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;

// A fresh schema per test file, dropped afterwards.
export async function createTestDb(): Promise<{ db: Db; cleanup: () => Promise<void> }> {
  if (!TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is not set');
  const schema = `test_${randomBytes(6).toString('hex')}`;
  const admin = new pg.Pool({ connectionString: TEST_DATABASE_URL });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const db = new pg.Pool({ connectionString: TEST_DATABASE_URL, options: `-c search_path=${schema}` });
  await migrate(db);
  return {
    db,
    async cleanup() {
      await db.end();
      await admin.query(`DROP SCHEMA ${schema} CASCADE`);
      await admin.end();
    },
  };
}
