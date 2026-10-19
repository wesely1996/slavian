// Wave lifecycle on the scheduler: scheduled → (wave_spawn) marching →
// (wave_arrive) battling at a village or the Holy City → defeated, or on
// winning a raid or a raze (horde.ts) and onward until its rampage clock
// runs out and it settles into a camp. A spawn also plans the next wave, so `waves.upcoming` waves are
// always announced ahead.
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage } from '../db/villages.js';
import { insertWave, lastWave, loadWave, markDispersed, markMarching, markStruck, type Wave } from '../db/waves.js';
import { listMembers, loadHexes, quietWindow, type World } from '../db/worlds.js';
import { planMarch, planWave, type PathStep, type PlannedWave, type WaveContext } from '../sim/waves.js';
import { decayFear, loadFear } from '../db/fear.js';
import { findBridge } from '../db/bridges.js';
import { stagesStanding } from '../sim/bridge.js';
import { fighters } from '../sim/armies.js';
import { afterQuiet, presetOf, waveFactor, type GroupPower } from '../sim/difficulty.js';
import { unitsFed } from '../sim/village.js';
import { hex } from '../sim/hex.js';
import { startBattle } from './battles.js';
import { beginRampage, moveOn, startHolyCityBattle } from './horde.js';
import { campsJoin } from './camps.js';
import { planWaveWarning } from './notices.js';
import { planRaids } from './outposts.js';
import { planIntercepts } from './field.js';
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

// What the group has built up, for wave sizes (difficulty.ts).
export async function groupPower(client: DbClient, data: GameData, world: World, waveIndex: number): Promise<GroupPower> {
  const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin);
  let armyAttack = 0;
  for (const village of villages) {
    for (const [unit, n] of Object.entries(fighters(data, unitsFed(village.state)))) armyAttack += n * (data.units.units[unit]?.attack ?? 0);
  }
  const bridgeStages = stagesStanding(await findBridge(client, world.id));
  return { players: (await listMembers(client, world.id)).length, villages: villages.length, armyAttack, waveIndex, bridgeStages };
}

async function announceWave(
  client: DbClient,
  data: GameData,
  world: World,
  ctx: WaveContext,
  index: number,
  previousSpawnAt: Date | null,
): Promise<Wave> {
  const sizeFactor = waveFactor(data, world.difficulty, await groupPower(client, data, world, index));
  const wave = await insertWave(client, world.id, planWave(data, { ...ctx, sizeFactor }, index, previousSpawnAt));
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

// Fear as this world's hordes heed it (Story hordes don't learn).
export async function fearOf(client: DbClient, data: GameData, world: World): Promise<Map<string, number>> {
  const weight = presetOf(data, world.difficulty).fearWeight;
  return new Map([...(await loadFear(client, world.id)).entries()].map(([key, value]) => [key, value * weight]));
}

// A march arriving in the group's quiet hours waits outside until they end.
export function holdForQuiet<M extends { path: readonly PathStep[]; arrivesAt: Date }>(world: World, spawnAt: Date, march: M): M {
  const at = afterQuiet(quietWindow(world), march.arrivesAt);
  const delay = at.getTime() - march.arrivesAt.getTime();
  if (delay <= 0) return march;
  const path = march.path.map((s, i) => (i === march.path.length - 1 ? { ...s, atMs: at.getTime() - spawnAt.getTime() } : s));
  return { ...march, path, arrivesAt: at };
}

export const waveHandlers: HandlerRegistry = {
  async wave_spawn({ client, data, world }, event) {
    let wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'scheduled') return;
    // Camps of its front send part of themselves along.
    await campsJoin(client, data, world, wave);
    wave = await loadWave(client, wave.id);

    // Old memories fade as a new horde sets out.
    await decayFear(client, world.id, data.horde.fear.decayPerWave, data.horde.fear.minimum);
    const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t]));
    const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin).map((v) => ({ id: v.id, q: v.q, r: v.r }));
    const march = planMarch(data, {
      terrain,
      radius: world.radius ?? 0,
      wave: asPlanned(wave),
      villages,
      seed: world.seed,
      departAt: event.dueAt,
      worldSpeed: world.speed,
      fear: await fearOf(client, data, world),
    });
    await markMarching(client, wave.id, holdForQuiet(world, wave.spawnAt, march));
    const payload: WavePayload = { waveId: wave.id };
    await scheduleEvent(client, world.id, (await loadWave(client, wave.id)).arrivesAt!, 'wave_arrive', payload);
    await planRaids(client, data, world, wave.id);
    await planIntercepts(client, world, wave.id);
    await planWaveWarning(client, data, world, wave.id, event.dueAt);

    const last = (await lastWave(client, world.id))!;
    await announceWave(client, data, world, await waveContext(client, world), last.index + 1, last.spawnAt);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },

  // At a village the horde fights its garrison; at the Holy City, its guard.
  // The rampage clock starts at the first target.
  async wave_arrive({ client, data, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    // A horde held up in a field battle arrives later than first planned.
    if (wave.status !== 'marching' || (wave.arrivesAt && event.dueAt < wave.arrivesAt)) return;
    await beginRampage(client, data, world, wave, event.dueAt);
    if (wave.targetVillageId !== null) {
      const village = await loadVillage(client, wave.targetVillageId);
      if (village.ruin) {
        // Another horde got here first: nothing left to fight for.
        await markStruck(client, wave.id, village.id);
        await moveOn(client, data, world, wave.id, hex(village.q, village.r), event.dueAt);
      } else {
        await startBattle(client, data, world, wave, wave.targetVillageId, event.dueAt);
      }
    } else {
      await startHolyCityBattle(client, data, world, wave, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },

  // Hordes that camped at the Holy City before it had a guard.
  async wave_disperse({ client, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'arrived') return;
    await markDispersed(client, wave.id);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },
};
