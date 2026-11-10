// Wave lifecycle on the scheduler: scheduled → (wave_spawn) marching →
// (wave_arrive) battling at a village or the Holy City → defeated, or on
// winning a raid or a raze (horde.ts) and onward until its rampage clock
// runs out and it settles into a camp. A spawn also plans the next wave, so `waves.upcoming` waves are
// always announced ahead.
import { assignLeader } from './leaders.js';
import { loadLand } from '../db/rivers.js';
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage } from '../db/villages.js';
import { addHatred, endWave, insertWave, lastWave, loadWave, markDispersed, markMarching, markStruck, setWaveStrength, type Wave } from '../db/waves.js';
import { getWorld, listMembers, loadHexes, quietWindow, type World } from '../db/worlds.js';
import { hatredCrossings, planMarch, planWave, routeFrom, rngFor, splitBand, threatOf, waveHexAt, type March, type PathStep, type PlannedWave, type Target, type WaveContext } from '../sim/waves.js';
import { decayFear, loadFear } from '../db/fear.js';
import { findBridge } from '../db/bridges.js';
import { stagesStanding } from '../sim/bridge.js';
import { fighters } from '../sim/armies.js';
import { afterQuiet, presetOf, waveFactor, type GroupPower } from '../sim/difficulty.js';
import { unitsFed } from '../sim/village.js';
import { fieldArmies } from '../db/armies.js';
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

export async function waveContext(client: DbClient, world: World): Promise<WaveContext> {
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
  // Armies out on the map count too.
  for (const army of await fieldArmies(client, world.id)) {
    for (const [unit, n] of Object.entries(fighters(data, army.units))) armyAttack += n * (data.units.units[unit]?.attack ?? 0);
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

// A horde wiped out before it set out (a strike on its encampment): the
// next one is announced in its place, so as many stay announced ahead.
export async function announceNext(client: DbClient, data: GameData, world: World): Promise<void> {
  if ((await getWorld(client, world.id)).ritualAt) return;
  const last = await lastWave(client, world.id);
  if (!last || last.ritual) return;
  await announceWave(client, data, world, await waveContext(client, world), last.index + 1, last.spawnAt);
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

// Where each scheduled wave is expected to go: its march planned as at
// spawn, from today's villages and fear (it is planned again, for real, when
// it sets out, so the forecast can still change). By wave id.
export async function forecastMarches(client: DbClient, data: GameData, world: World, waves: readonly Wave[]): Promise<Map<number, March>> {
  const forecasts = new Map<number, March>();
  const scheduled = waves.filter((w) => w.status === 'scheduled');
  if (scheduled.length === 0) return forecasts;
  const terrain = await loadLand(client, world.id);
  const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin).map((v) => ({ id: v.id, q: v.q, r: v.r }));
  const fear = await fearOf(client, data, world);
  for (const wave of scheduled) {
    try {
      const march = planMarch(data, {
        terrain,
        radius: world.radius ?? 0,
        wave: asPlanned(wave),
        villages,
        seed: world.seed,
        departAt: wave.spawnAt,
        worldSpeed: world.speed,
        fear,
      });
      forecasts.set(wave.id, holdForQuiet(world, wave.spawnAt, march));
    } catch {
      // No way through from its front today: nothing to forecast.
    }
  }
  return forecasts;
}

// A horde grows to hate (horde.json hatred): each time its hatred passes
// another whole 100%, it sends out a band of its troops.
export async function angerHorde(client: DbClient, data: GameData, world: World, waveId: number, amount: number, at: Date): Promise<void> {
  const before = (await loadWave(client, waveId)).hatred;
  await addHatred(client, waveId, amount);
  for (let i = hatredCrossings(before, before + amount); i > 0; i--) {
    const wave = await loadWave(client, waveId);
    const { band, rest } = splitBand(wave.composition, data.horde.hatred.bandShare);
    if (Object.keys(band).length === 0) return;
    await setWaveStrength(client, wave.id, rest);
    const planned: PlannedWave = { index: wave.index, front: wave.front, spawnAt: at, composition: band, threat: threatOf(data, band), stance: wave.stance };
    const created = await insertWave(client, world.id, planned, false, wave.id);
    const payload: WavePayload = { waveId: created.id };
    await scheduleEvent(client, world.id, at, 'wave_spawn', payload);
  }
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

// A band sets out: from where its horde is (or the horde's wilds, if it
// hasn't set out) to the nearest player village, not the one the horde is
// after. With none to go to, it scatters.
async function sendBand(client: DbClient, data: GameData, world: World, band: Wave, at: Date): Promise<void> {
  const horde = await loadWave(client, band.bandOf!);
  const terrain = await loadLand(client, world.id);
  const targets: Target[] = (await listVillages(client, world.id))
    .filter((v) => !v.ruin && v.ownerAccountId !== null && v.id !== horde.targetVillageId)
    .map((v) => ({ id: v.id, cell: hex(v.q, v.r) }));
  const from = horde.status === 'scheduled' ? null : waveHexAt(horde, at);
  let march: March | null = null;
  if (targets.length > 0 && from) {
    const route = routeFrom(data, {
      terrain,
      from,
      targets,
      front: band.front,
      composition: band.composition,
      rng: rngFor(world.seed, band.index, 0x7b),
      startMs: 0,
      worldSpeed: world.speed,
    });
    if (route) march = { spawn: from, targetVillageId: route.targetVillageId, path: route.path, arrivesAt: new Date(at.getTime() + route.arrivesMs) };
  } else if (targets.length > 0) {
    try {
      march = planMarch(data, { terrain, radius: world.radius ?? 0, wave: asPlanned(band), villages: [], seed: world.seed, departAt: at, worldSpeed: world.speed, targets });
    } catch {
      march = null;
    }
  }
  if (!march) {
    await endWave(client, band.id, 'dispersed', at);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
    return;
  }
  await markMarching(client, band.id, holdForQuiet(world, band.spawnAt, march));
  const payload: WavePayload = { waveId: band.id };
  await scheduleEvent(client, world.id, (await loadWave(client, band.id)).arrivesAt!, 'wave_arrive', payload);
  await planRaids(client, data, world, band.id);
  await planIntercepts(client, world, band.id);
  await planWaveWarning(client, data, world, band.id, at);
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

export const waveHandlers: HandlerRegistry = {
  async wave_spawn({ client, data, world }, event) {
    let wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'scheduled') return;
    if (wave.bandOf !== null) return sendBand(client, data, world, wave, event.dueAt);
    // The front's leader takes its head, if free to.
    await assignLeader(client, data, world, wave, event.dueAt);
    // Camps of its front send part of themselves along.
    await campsJoin(client, data, world, wave);
    wave = await loadWave(client, wave.id);

    // Old memories fade as a new horde sets out.
    await decayFear(client, world.id, data.horde.fear.decayPerWave, data.horde.fear.minimum);
    const terrain = await loadLand(client, world.id);
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

    // After Ritual Night is called, no more waves are announced.
    if (!wave.ritual && !(await getWorld(client, world.id)).ritualAt) {
      const last = (await lastWave(client, world.id))!;
      await announceWave(client, data, world, await waveContext(client, world), last.index + 1, last.spawnAt);
    }
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
