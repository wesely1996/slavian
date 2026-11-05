// Daily pruning: once a day (real hours, whatever the world's speed) a
// running world forgets what is done and more than PRUNE_HOURS old: finished
// battles, raids, notices, chat, caravans, scouting trips, expeditions,
// armies, ruin searches, cleared camps and processed events. Only the last
// day stays, so the world (and what is sent of it) keeps small. Battles won
// and camps cleared are tallied first, for the run's summary.
import type { DbClient } from '../db/pool.js';
import { notifyWorld } from '../db/notify.js';
import type { World } from '../db/worlds.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const PRUNE_HOURS = 24;
const PRUNE_MS = PRUNE_HOURS * 3_600_000;

// A running world has its next pruning planned.
export async function ensurePrune(client: DbClient, world: World, now: Date): Promise<void> {
  if (world.status !== 'running' || !world.startedAt) return;
  const { rows } = await client.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'world_prune' AND status = 'pending'", [world.id]);
  if (rows.length) return;
  const n = Math.max(1, Math.floor((now.getTime() - world.startedAt.getTime()) / PRUNE_MS) + 1);
  await scheduleEvent(client, world.id, new Date(world.startedAt.getTime() + n * PRUNE_MS), 'world_prune', {});
}

export const pruneHandlers: HandlerRegistry = {
  async world_prune({ client, world }, event) {
    if (world.status !== 'running') return;
    const at = event.dueAt;
    const cutoff = new Date(at.getTime() - PRUNE_MS);
    const id = world.id;
    const { rows: battles } = await client.query<{ n: number }>(
      `WITH gone AS (DELETE FROM battles WHERE world_id = $1 AND status <> 'ongoing' AND ended_at < $2 RETURNING status)
       SELECT count(*) FILTER (WHERE status IN ('defended', 'cleared', 'repelled'))::int AS n FROM gone`,
      [id, cutoff],
    );
    const { rows: camps } = await client.query<{ n: number }>(
      `WITH gone AS (DELETE FROM camps WHERE world_id = $1 AND status = 'cleared' AND created_at < $2 RETURNING 1) SELECT count(*)::int AS n FROM gone`,
      [id, cutoff],
    );
    await client.query(
      `UPDATE worlds SET pruned = jsonb_build_object(
         'battlesWon', COALESCE((pruned->>'battlesWon')::int, 0) + $2::int,
         'campsCleared', COALESCE((pruned->>'campsCleared')::int, 0) + $3::int)
       WHERE id = $1`,
      [id, battles[0]!.n, camps[0]!.n],
    );
    for (const sql of [
      'DELETE FROM raids WHERE world_id = $1 AND at < $2',
      'DELETE FROM notifications WHERE world_id = $1 AND created_at < $2',
      'DELETE FROM chat_messages WHERE world_id = $1 AND created_at < $2',
      "DELETE FROM caravans WHERE world_id = $1 AND status = 'done' AND returns_at < $2",
      "DELETE FROM scout_missions WHERE world_id = $1 AND status = 'done' AND returns_at < $2",
      "DELETE FROM expeditions WHERE world_id = $1 AND status = 'done' AND returns_at < $2",
      "DELETE FROM armies WHERE world_id = $1 AND status = 'done' AND COALESCE(returns_at, arrives_at) < $2",
      "DELETE FROM ruin_searches WHERE world_id = $1 AND status = 'done' AND returns_at < $2",
      "DELETE FROM scheduled_events WHERE world_id = $1 AND status = 'done' AND due_at < $2",
    ]) {
      await client.query(sql, [id, cutoff]);
    }
    await scheduleEvent(client, id, new Date(at.getTime() + PRUNE_MS), 'world_prune', {});
    await notifyWorld(client, { worldId: id, type: 'world' });
  },
};
