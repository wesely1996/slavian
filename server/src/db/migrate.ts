import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createPool, inTransaction, type Db } from './pool.js';

const MIGRATIONS_DIR = fileURLToPath(new URL('../../migrations/', import.meta.url));
const MIGRATION_LOCK_KEY = 0x51a71a;

export async function migrate(db: Db): Promise<string[]> {
  return inTransaction(db, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock($1)', [MIGRATION_LOCK_KEY]);
    await client.query(
      'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
    );
    const { rows } = await client.query<{ name: string }>('SELECT name FROM schema_migrations');
    const applied = new Set(rows.map((row) => row.name));

    const pending = readdirSync(MIGRATIONS_DIR)
      .filter((file) => file.endsWith('.sql') && !applied.has(file))
      .sort();
    for (const file of pending) {
      await client.query(readFileSync(`${MIGRATIONS_DIR}/${file}`, 'utf8'));
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    }
    return pending;
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const db = createPool();
  const applied = await migrate(db);
  console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Up to date');
  await db.end();
}
