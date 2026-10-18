import { inTransaction, type Db, type DbClient } from '../db/pool.js';
import { getWorld } from '../db/worlds.js';
import type { ScheduledEvent, SchedulerDeps } from './events.js';

// Advisory locks use the two-key form; the first key namespaces world locks.
// Locks are database-wide while world ids are per schema, so the namespace
// includes the schema (tests run side by side in separate schemas).
const WORLD_LOCK_NAMESPACE = "hashtext('world:' || current_schema())";

// Safety valve against handlers that keep scheduling already-due events.
const MAX_EVENTS_PER_DRAIN = 10_000;

export async function lockWorld(client: DbClient, worldId: number): Promise<void> {
  await client.query(`SELECT pg_advisory_xact_lock(${WORLD_LOCK_NAMESPACE}, $1)`, [worldId]);
}

export async function tryLockWorld(client: DbClient, worldId: number): Promise<boolean> {
  const { rows } = await client.query<{ locked: boolean }>(
    `SELECT pg_try_advisory_xact_lock(${WORLD_LOCK_NAMESPACE}, $1) AS locked`,
    [worldId],
  );
  return rows[0]!.locked;
}

interface EventRow {
  id: number;
  world_id: number;
  due_at: Date;
  type: string;
  payload: unknown;
}

// Processes the world's pending events due at or before `until`, oldest
// first. The caller must hold the world lock inside an open transaction.
// A failing handler marks its event failed and does not block the rest.
export async function drainWorld(
  client: DbClient,
  worldId: number,
  until: Date,
  deps: SchedulerDeps,
): Promise<number> {
  const world = await getWorld(client, worldId);
  let processed = 0;
  for (; processed < MAX_EVENTS_PER_DRAIN; processed++) {
    // One at a time: a handler may schedule a new event that is due earlier
    // than the rest of the backlog.
    const { rows } = await client.query<EventRow>(
      `SELECT id, world_id, due_at, type, payload FROM scheduled_events
       WHERE world_id = $1 AND status = 'pending' AND due_at <= $2
       ORDER BY due_at, id
       LIMIT 1`,
      [worldId, until],
    );
    const row = rows[0];
    if (!row) return processed;

    const event: ScheduledEvent = {
      id: row.id,
      worldId: row.world_id,
      dueAt: row.due_at,
      type: row.type,
      payload: row.payload,
    };
    await client.query('SAVEPOINT event');
    try {
      const handler = deps.handlers[event.type];
      if (!handler) throw new Error(`No handler for event type "${event.type}"`);
      await handler({ client, data: deps.data, world }, event);
      await client.query(
        "UPDATE scheduled_events SET status = 'done', processed_at = now() WHERE id = $1",
        [event.id],
      );
      await client.query('RELEASE SAVEPOINT event');
    } catch (error) {
      await client.query('ROLLBACK TO SAVEPOINT event');
      await client.query(
        "UPDATE scheduled_events SET status = 'failed', processed_at = now(), error = $2 WHERE id = $1",
        [event.id, error instanceof Error ? error.message : String(error)],
      );
      console.error(`Event ${event.id} (${event.type}) in world ${worldId} failed:`, error);
    }
  }
  throw new Error(`World ${worldId} exceeded ${MAX_EVENTS_PER_DRAIN} events in one drain`);
}

// Runs `fn` with exclusive access to the world, after catching the world up
// to `now`. Commands go through here so they never act on stale state.
export async function withWorld<T>(
  db: Db,
  worldId: number,
  now: Date,
  deps: SchedulerDeps,
  fn: (client: DbClient) => Promise<T>,
): Promise<T> {
  return inTransaction(db, async (client) => {
    await lockWorld(client, worldId);
    await drainWorld(client, worldId, now, deps);
    return fn(client);
  });
}
