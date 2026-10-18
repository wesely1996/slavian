import type { DbClient } from './pool.js';

// Postgres NOTIFY channel announcing that something in a world changed. It
// is delivered on commit, so listeners never see rolled-back changes, and it
// works across processes (the scheduler worker and the API). Channels are
// per schema: NOTIFY is database-wide, and ids are only unique per schema.
const CHANNEL_PREFIX = 'world_events.';

export type WorldEvent =
  | { worldId: number; type: 'world' }
  | { worldId: number; type: 'village'; villageId: number }
  | { worldId: number; type: 'waves' }
  | { worldId: number; type: 'scouting' }
  | { worldId: number; type: 'battles' }
  | { worldId: number; type: 'raids' }
  | { worldId: number; type: 'caravans' }
  | { worldId: number; type: 'expeditions' }
  | { worldId: number; type: 'research' }
  | { worldId: number; type: 'heroes' };

export async function notifyWorld(client: DbClient, event: WorldEvent): Promise<void> {
  await client.query('SELECT pg_notify($1 || current_schema(), $2)', [CHANNEL_PREFIX, JSON.stringify(event)]);
}

export async function worldEventsChannel(client: DbClient): Promise<string> {
  const { rows } = await client.query<{ channel: string }>('SELECT $1 || current_schema() AS channel', [CHANNEL_PREFIX]);
  return rows[0]!.channel;
}
