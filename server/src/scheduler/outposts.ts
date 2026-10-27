// Outpost raids on the scheduler: when a horde sets out (or an outpost is
// finished while one is on the march), every outpost near its route gets an
// outpost_raid event for when the horde comes close. Supply points near its
// route get a supply_raid: unless an army stands on one then, the horde
// burns it with all its grain.
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
import { tell } from './notices.js';
import { armiesHolding } from '../db/armies.js';
import { deleteFort, listForts, loadFort, type Fort } from '../db/forts.js';
import { hex } from '../sim/hex.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const supplyRaidPayload = z.object({ waveId: z.number().int(), fortId: z.number().int() });
export type SupplyRaidPayload = z.infer<typeof supplyRaidPayload>;

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
  for (const raid of raidsAlong(wave.path, outposts, data.enemies.fronts[wave.front]!.personality.raidReach, fromMs)) {
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

async function scheduleSupplyRaids(client: DbClient, data: GameData, world: World, wave: Wave, points: readonly Fort[], fromMs: number): Promise<void> {
  if (!wave.path) return;
  const targets = points.filter((f) => f.kind === 'supply').map((f) => ({ fortId: f.id, cell: hex(f.q, f.r) }));
  for (const raid of raidsAlong(wave.path, targets, data.enemies.fronts[wave.front]!.personality.raidReach, fromMs)) {
    const payload: SupplyRaidPayload = { waveId: wave.id, fortId: raid.fortId };
    const { rows } = await client.query(
      `SELECT 1 FROM scheduled_events
       WHERE world_id = $1 AND type = 'supply_raid' AND status = 'pending' AND payload @> $2::jsonb`,
      [world.id, JSON.stringify(payload)],
    );
    if (rows.length) continue;
    await scheduleEvent(client, world.id, new Date(wave.spawnAt.getTime() + raid.atMs), 'supply_raid', payload);
  }
}

// A horde has just set out (or set out again `fromMs` into its march): plan
// raids on every standing outpost and every supply point near the rest of
// its route.
export async function planRaids(client: DbClient, data: GameData, world: World, waveId: number, fromMs = 0): Promise<void> {
  const wave = await loadWave(client, waveId);
  await scheduleRaids(client, data, world, wave, standingOutposts(await listVillages(client, world.id)), fromMs);
  await scheduleSupplyRaids(client, data, world, wave, await listForts(client, world.id), fromMs);
}

// A supply point has just been placed: hordes still on the march may pass it.
export async function supplyPointPlaced(client: DbClient, data: GameData, world: World, point: Fort, at: Date): Promise<void> {
  for (const wave of await listActiveWaves(client, world.id)) {
    if (wave.status !== 'marching') continue;
    await scheduleSupplyRaids(client, data, world, wave, [point], at.getTime() - wave.spawnAt.getTime());
  }
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
  // A horde comes by a supply point: with no army standing on it, it burns.
  async supply_raid({ client, world }, event) {
    const payload = supplyRaidPayload.parse(event.payload);
    const wave = await loadWave(client, payload.waveId);
    if (!RAIDING.has(wave.status)) return;
    const point = await loadFort(client, payload.fortId);
    if (!point || point.kind !== 'supply') return;
    if ((await armiesHolding(client, world.id, point.q, point.r, ['stationed', 'engaged'])).length) return;
    await deleteFort(client, point.id);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
    await tell(client, world, point.ownerAccountId, {
      kind: 'outpost_raided',
      tier: 'push',
      title: 'A horde burned the supply point at ({q}, {r})',
      body: 'Its {grain} grain burned with it.',
      vars: { q: point.q, r: point.r, grain: Math.floor(point.grain) },
    }, event.dueAt);
  },

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
    await tell(client, world, village.ownerAccountId, {
      kind: 'outpost_raided',
      tier: 'push',
      title: 'A horde burned an outpost of {village}',
      body: after.level > 0
        ? 'The outpost at ({q}, {r}) is down to level {level}.'
        : 'The outpost at ({q}, {r}) lies in ruins.',
      vars: { village: village.name, q: cell.q, r: cell.r, level: after.level },
    }, event.dueAt);
  },
};
