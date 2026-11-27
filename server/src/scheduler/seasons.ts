// Seasons on the scheduler (data/seasons.json, sim/seasons.ts): at each
// game day's turn (season_turn), every settlement's grain follows the new
// season, and every player hears of it.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { listMembers, type World } from '../db/worlds.js';
import { seasonAt, seasonBonuses } from '../sim/seasons.js';
import { withSeason } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { tell } from './notices.js';

export const seasonTurnPayload = z.object({ day: z.number().int() });

// Every settlement on the season of `at`.
export async function applySeason(client: DbClient, data: GameData, world: World, at: Date): Promise<void> {
  const { season } = seasonAt(data, world, at);
  const bonuses = seasonBonuses(data, season);
  for (const village of await listVillages(client, world.id)) {
    const before = village.state.bonuses['season.grain'];
    if (before === bonuses['season.grain']) continue;
    await saveVillageState(client, village.id, withSeason(data, village.state, bonuses, at, world.speed));
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  }
}

// The next season's turn on the calendar (worlds running from before
// seasons: their settlements on today's season first).
export async function ensureSeasons(client: DbClient, data: GameData, world: World, now: Date): Promise<void> {
  if (world.status !== 'running' || !world.startedAt) return;
  const { rows } = await client.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'season_turn' AND status = 'pending'", [world.id]);
  if (rows.length) return;
  await applySeason(client, data, world, now);
  const { day, endsAt } = seasonAt(data, world, now);
  await scheduleEvent(client, world.id, endsAt, 'season_turn', { day: day + 1 });
}

export const seasonHandlers: HandlerRegistry = {
  async season_turn({ client, data, world }, event) {
    if (world.status !== 'running') return;
    const { day } = seasonTurnPayload.parse(event.payload);
    await applySeason(client, data, world, event.dueAt);
    const { season, endsAt } = seasonAt(data, world, event.dueAt);
    const def = data.seasons.seasons[season];
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, { kind: 'season', tier: 'push', title: `${def.name} has come`, body: def.description }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    await scheduleEvent(client, world.id, endsAt, 'season_turn', { day: day + 1 });
  },
};
