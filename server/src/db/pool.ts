import pg from 'pg';

// bigint ids fit comfortably in a JS number; parse them as numbers.
pg.types.setTypeParser(pg.types.builtins.INT8, (value) => Number.parseInt(value, 10));

export type Db = pg.Pool;
export type DbClient = pg.PoolClient;

// Hosted Postgres (e.g. Neon) hands out URLs like
// `...?sslmode=require&channel_binding=require`. node-postgres already
// treats `require` as full certificate verification but warns about it, and
// ignores `channel_binding`; spell both out so they are explicit and used.
export function poolConfig(connectionString: string): pg.PoolConfig {
  const url = new URL(connectionString);
  const params = url.searchParams;
  const sslmode = params.get('sslmode');
  if (sslmode === 'require' || sslmode === 'prefer' || sslmode === 'verify-ca') params.set('sslmode', 'verify-full');
  const channelBinding = params.get('channel_binding');
  params.delete('channel_binding');
  return {
    connectionString: url.toString(),
    ...(channelBinding === 'require' ? { enableChannelBinding: true } : {}),
  };
}

// Pooled endpoints (PgBouncer in transaction mode, e.g. Neon's `-pooler`
// hosts) drop LISTEN between transactions, which silently breaks live
// updates. Returns a warning to log, or null.
export function pooledEndpointWarning(connectionString: string): string | null {
  const host = new URL(connectionString).hostname;
  return host.includes('-pooler')
    ? `DATABASE_URL points at a pooled endpoint (${host}); live updates need the direct connection string`
    : null;
}

export function createPool(connectionString = process.env.DATABASE_URL): Db {
  if (!connectionString) throw new Error('DATABASE_URL is not set');
  return new pg.Pool(poolConfig(connectionString));
}

export async function inTransaction<T>(db: Db, fn: (client: DbClient) => Promise<T>): Promise<T> {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
