import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import type { World } from '../db/worlds.js';

export interface ScheduledEvent<P = unknown> {
  id: number;
  worldId: number;
  dueAt: Date;
  type: string;
  payload: P;
}

export interface HandlerContext {
  client: DbClient;
  data: GameData;
  world: World;
}

// Handlers run inside the world's transaction with the world lock held. They
// must treat `event.dueAt` as "now", since processing may happen later.
export type EventHandler = (ctx: HandlerContext, event: ScheduledEvent) => Promise<void>;
export type HandlerRegistry = Readonly<Record<string, EventHandler>>;

export interface SchedulerDeps {
  data: GameData;
  handlers: HandlerRegistry;
}

export async function scheduleEvent(
  client: DbClient,
  worldId: number,
  dueAt: Date,
  type: string,
  payload: unknown,
): Promise<number> {
  const { rows } = await client.query<{ id: number }>(
    'INSERT INTO scheduled_events (world_id, due_at, type, payload) VALUES ($1, $2, $3, $4) RETURNING id',
    [worldId, dueAt, type, JSON.stringify(payload)],
  );
  return rows[0]!.id;
}
