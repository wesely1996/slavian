// Outpost raids on the scheduler: when a horde sets out (or an outpost is
// finished while one is on the march), every outpost near its route gets an
// outpost_raid event for when the horde comes close.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { insertRaid } from '../db/raids.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { listActiveWaves, loadWave, type Wave } from '../db/waves.js';
import type { World } from '../db/worlds.js';
import { outpostHex, outpostPlots, raidOutpost } from '../sim/village.js';
import { raidsAlong, type OutpostTarget } from '../sim/waves.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const outpostRaidPayload = z.object({ waveId: z.number().int(), villageId: z.number().int(), plot: z.string() });
export type OutpostRaidPayload = z.infer<typeof outpostRaidPayload>;

// Hordes still able to raid: on the march, or fighting / camped at the end
// of their route.
const RAIDING = new Set<Wave['status']>(['marching', 'battling', 'arrived']);

function standingOutposts(villages: readonly Village[]): OutpostTarget[] {
  return villages.flatMap((village) =>
    outpostPlots(village.state.plots)
      .filter((plot) => village.state.plots[plot]!.level > 0)
      .map((plot) => ({ villageId: village.id, plot, cell: outpostHex(plot)! })),
  );
}

async function scheduleRaids(
  client: DbClient,
  data: GameData,
  world: World,
  wave: Wave,
  outposts: readonly OutpostTarget[],
  fromMs: number,
): Promise<void> {
  if (!wave.path) return;
  for (const raid of raidsAlong(wave.path, outposts, data.waves.raidReach, fromMs)) {
    const payload: OutpostRaidPayload = { waveId: wave.id, villageId: raid.villageId, plot: raid.plot };
    const { rows } = await client.query(
      `SELECT 1 FROM scheduled_events
       WHERE world_id = $1 AND type = 'outpost_raid' AND status = 'pending' AND payload @> $2::jsonb`,
      [world.id, JSON.stringify(payload)],
    );
    if (rows.length) continue;
    await scheduleEvent(client, world.id, new Date(wave.spawnAt.getTime() + raid.atMs), 'outpost_raid', payload);
  }
}

// A horde has just set out: plan raids on every standing outpost near its route.
export async function planRaids(client: DbClient, data: GameData, world: World, waveId: number): Promise<void> {
  const wave = await loadWave(client, waveId);
  await scheduleRaids(client, data, world, wave, standingOutposts(await listVillages(client, world.id)), 0);
}

// An outpost has just been (re)built: hordes still on the march may pass it.
export async function outpostStanding(
  client: DbClient,
  data: GameData,
  world: World,
  target: OutpostTarget,
  at: Date,
): Promise<void> {
  for (const wave of await listActiveWaves(client, world.id)) {
    if (wave.status !== 'marching') continue;
    await scheduleRaids(client, data, world, wave, [target], at.getTime() - wave.spawnAt.getTime());
  }
}

export const outpostHandlers: HandlerRegistry = {
  async outpost_raid({ client, data, world }, event) {
    const payload = outpostRaidPayload.parse(event.payload);
    const wave = await loadWave(client, payload.waveId);
    if (!RAIDING.has(wave.status)) return;
    const village = await loadVillage(client, payload.villageId);
    const before = village.state.plots[payload.plot];
    const state = raidOutpost(data, village.state, payload.plot, event.dueAt, world.speed);
    const after = state.plots[payload.plot];
    if (!before || !after || after.level === before.level) return;
    await saveVillageState(client, village.id, state);
    const cell = outpostHex(payload.plot)!;
    await insertRaid(client, {
      worldId: world.id,
      waveId: wave.id,
      villageId: village.id,
      q: cell.q,
      r: cell.r,
      levelAfter: after.level,
      at: event.dueAt,
    });
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'raids' });
  },
};
