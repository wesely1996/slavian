import { inTransaction, type Db } from '../db/pool.js';
import type { SchedulerDeps } from './events.js';
import { drainWorld, tryLockWorld } from './world.js';

export interface TickResult {
  worlds: number;
  events: number;
  skipped: number;
}

// Processes one world if no one else holds it. Returns null when the world
// is busy (another worker or a command has it); it will be picked up later.
export async function processWorld(db: Db, worldId: number, now: Date, deps: SchedulerDeps): Promise<number | null> {
  return inTransaction(db, async (client) => {
    if (!(await tryLockWorld(client, worldId))) return null;
    return drainWorld(client, worldId, now, deps);
  });
}

// One pass over every world with due events. Safe to run from any number of
// worker processes at once. A finished run (won or lost) stands still.
export async function tick(db: Db, now: Date, deps: SchedulerDeps): Promise<TickResult> {
  const { rows } = await db.query<{ world_id: number }>(
    `SELECT DISTINCT e.world_id FROM scheduled_events e JOIN worlds w ON w.id = e.world_id
     WHERE e.status = 'pending' AND e.due_at <= $1 AND w.status NOT IN ('won', 'lost')`,
    [now],
  );
  const result: TickResult = { worlds: 0, events: 0, skipped: 0 };
  for (const { world_id: worldId } of rows) {
    const processed = await processWorld(db, worldId, now, deps);
    if (processed === null) {
      result.skipped++;
    } else {
      result.worlds++;
      result.events += processed;
    }
  }
  return result;
}
