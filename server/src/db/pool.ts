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

// A client for building one view: a read asked twice (same text, same
// parameters) is answered from memory the second time, so views that share
// their sources (the land, the villages, the world) cost one round trip
// each. Rows are copied on a repeat, so no caller sees another's changes;
// anything that is not a plain SELECT goes through and empties the memory.
export function memoReads(client: DbClient): DbClient {
  const seen = new Map<string, Promise<pg.QueryResult>>();
  const query = (text: unknown, params?: unknown[]): Promise<pg.QueryResult> => {
    if (typeof text !== 'string' || !/^\s*\(?\s*SELECT\b/i.test(text) || /\bpg_notify\b|\bpg_(try_)?advisory|\bFOR (UPDATE|SHARE)\b/i.test(text)) {
      seen.clear();
      return (client.query as (text: unknown, params?: unknown[]) => Promise<pg.QueryResult>)(text, params);
    }
    const key = `${text}\u0000${JSON.stringify(params ?? [])}`;
    const known = seen.get(key);
    if (known) return known.then((result) => ({ ...result, rows: structuredClone(result.rows) }));
    const asked = client.query(text, params);
    seen.set(key, asked);
    asked.catch(() => seen.delete(key));
    return asked;
  };
  return new Proxy(client, {
    get(target, property) {
      if (property === 'query') return query;
      const value: unknown = Reflect.get(target, property);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
}
