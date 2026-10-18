// Wave lifecycle on the scheduler: scheduled → (wave_spawn) marching →
// (wave_arrive) battling → defeated or (after raiding) dispersed; see
// battles.ts. A horde with no village to strike camps (arrived) and then
// disperses. A spawn also plans the next wave, so `waves.upcoming` waves are
// always announced ahead.
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages } from '../db/villages.js';
import { insertWave, lastWave, loadWave, markArrived, markDispersed, markMarching, type Wave } from '../db/waves.js';
import { listMembers, loadHexes, type World } from '../db/worlds.js';
import { planMarch, planWave, type PlannedWave, type WaveContext } from '../sim/waves.js';
import { startBattle } from './battles.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

const MS_PER_HOUR = 3_600_000;

export const wavePayload = z.object({ waveId: z.number().int() });
export type WavePayload = z.infer<typeof wavePayload>;

async function waveContext(client: DbClient, world: World): Promise<WaveContext> {
  if (!world.startedAt) throw new Error(`World ${world.id} has not started`);
  return {
    seed: world.seed,
    activeFronts: world.activeFronts,
    playerCount: (await listMembers(client, world.id)).length,
    startedAt: world.startedAt,
    worldSpeed: world.speed,
  };
}

async function announceWave(
  client: DbClient,
  data: GameData,
  world: World,
  ctx: WaveContext,
  index: number,
  previousSpawnAt: Date | null,
): Promise<Wave> {
  const wave = await insertWave(client, world.id, planWave(data, ctx, index, previousSpawnAt));
  const payload: WavePayload = { waveId: wave.id };
  await scheduleEvent(client, world.id, wave.spawnAt, 'wave_spawn', payload);
  return wave;
}

// Called when a world starts.
export async function announceFirstWaves(client: DbClient, data: GameData, world: World): Promise<void> {
  const ctx = await waveContext(client, world);
  let previous: Date | null = null;
  for (let index = 0; index < data.waves.upcoming; index++) {
    previous = (await announceWave(client, data, world, ctx, index, previous)).spawnAt;
  }
}

function asPlanned(wave: Wave): PlannedWave {
  return {
    index: wave.index,
    front: wave.front,
    spawnAt: wave.spawnAt,
    composition: wave.composition,
    threat: wave.threat,
    stance: wave.stance,
  };
}

export const waveHandlers: HandlerRegistry = {
  async wave_spawn({ client, data, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'scheduled') return;

    const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t]));
    const villages = (await listVillages(client, world.id)).map((v) => ({ id: v.id, q: v.q, r: v.r }));
    const march = planMarch(data, {
      terrain,
      radius: world.radius ?? 0,
      wave: asPlanned(wave),
      villages,
      seed: world.seed,
      departAt: event.dueAt,
      worldSpeed: world.speed,
    });
    await markMarching(client, wave.id, march);
    const payload: WavePayload = { waveId: wave.id };
    await scheduleEvent(client, world.id, march.arrivesAt, 'wave_arrive', payload);

    const last = (await lastWave(client, world.id))!;
    await announceWave(client, data, world, await waveContext(client, world), last.index + 1, last.spawnAt);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },

  // At a village the horde fights its garrison. With no village to strike
  // (the Holy City, until it has defenses) it camps for the rampage time.
  async wave_arrive({ client, data, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'marching') return;
    if (wave.targetVillageId !== null) {
      await startBattle(client, data, world, wave, wave.targetVillageId, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'waves' });
      return;
    }
    const endsAt = new Date(event.dueAt.getTime() + (data.waves.rampageHours * MS_PER_HOUR) / world.speed);
    await markArrived(client, wave.id, endsAt);
    const payload: WavePayload = { waveId: wave.id };
    await scheduleEvent(client, world.id, endsAt, 'wave_disperse', payload);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },

  async wave_disperse({ client, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'arrived') return;
    await markDispersed(client, wave.id);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },
};
