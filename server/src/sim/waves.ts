// Enemy waves (PLAN.md §7.2–7.3). Everything is derived from the world seed
// and the wave index, so a wave is the same whenever it is (re)computed.
//
// A wave is planned ahead (front, spawn time, composition, threat level).
// When it spawns it picks a hex in its front's spawn zone and marches to the
// nearest village by path cost. Until battles exist (M1 step 5) it camps at
// its target for the rampage time and then disperses.
import type { GameData, Stance, TerrainId } from '../data/index.js';
import { waveStance } from './battle.js';
import { findPath, hex, hexDistance, hexKey, type Hex } from './hex.js';
import { frontOf, type Front } from './mapgen.js';
import { createRng } from './rng.js';

const MS_PER_HOUR = 3_600_000;
// Spawn hexes tried, in seeded random order, before giving up.
const MAX_SPAWN_CANDIDATES = 12;

export type Composition = Record<string, number>;

export interface PlannedWave {
  readonly index: number;
  readonly front: Front;
  readonly spawnAt: Date;
  readonly composition: Composition;
  readonly threat: string;
  readonly stance: Stance;
}

export interface PathStep {
  readonly q: number;
  readonly r: number;
  // Milliseconds after departure at which the wave enters this hex.
  readonly atMs: number;
}

export interface March {
  readonly spawn: Hex;
  readonly targetVillageId: number | null;
  readonly path: readonly PathStep[];
  readonly arrivesAt: Date;
}

export interface WaveContext {
  readonly seed: number;
  readonly activeFronts: readonly Front[];
  readonly playerCount: number;
  readonly startedAt: Date;
  readonly worldSpeed: number;
}

function rngFor(seed: number, index: number, salt: number): () => number {
  return createRng((seed ^ Math.imul(index + 1, 0x9e3779b1) ^ salt) >>> 0);
}

// Fronts that send waves in this world, in rotation order.
export function waveFronts(data: GameData, activeFronts: readonly Front[]): Front[] {
  const fronts = data.waves.enabledFronts.filter((front) => activeFronts.includes(front));
  if (fronts.length === 0) throw new Error('No enabled front is active in this world');
  return fronts;
}

export function spawnTime(
  data: GameData,
  ctx: WaveContext,
  index: number,
  previousSpawnAt: Date | null,
): Date {
  const { graceHours, intervalHours } = data.waves;
  let hours: number;
  let from: Date;
  if (index === 0 || !previousSpawnAt) {
    hours = graceHours;
    from = ctx.startedAt;
  } else {
    const [min, max] = intervalHours;
    hours = min + (max - min) * rngFor(ctx.seed, index, 0x51)();
    from = previousSpawnAt;
  }
  return new Date(from.getTime() + (hours * MS_PER_HOUR) / ctx.worldSpeed);
}

export function waveSize(data: GameData, index: number, playerCount: number): number {
  const { baseUnits, growthPerWave, perExtraPlayer } = data.waves;
  const players = 1 + perExtraPlayer * Math.max(0, playerCount - 1);
  return Math.max(1, Math.round(baseUnits * growthPerWave ** index * players));
}

// Splits the wave size between the front's units by weight. Whole units by
// weight first; the remainder is drawn at random, weighted.
export function composeWave(data: GameData, front: Front, index: number, size: number, seed: number, playerCount = 1): Composition {
  const units = Object.entries(data.enemies.fronts[front]!.units).filter(
    ([, def]) => def.minWave <= index && (def.minPlayers ?? 1) <= playerCount,
  );
  const totalWeight = units.reduce((sum, [, def]) => sum + def.weight, 0);
  const composition: Composition = {};
  let assigned = 0;
  for (const [id, def] of units) {
    const count = Math.floor((size * def.weight) / totalWeight);
    if (count > 0) composition[id] = count;
    assigned += count;
  }
  const rng = rngFor(seed, index, 0xc0);
  for (; assigned < size; assigned++) {
    let roll = rng() * totalWeight;
    const [id] = units.find(([, def]) => (roll -= def.weight) < 0) ?? units.at(-1)!;
    composition[id] = (composition[id] ?? 0) + 1;
  }
  return composition;
}

export function threatOf(data: GameData, composition: Composition): string {
  const count = Object.values(composition).reduce((sum, n) => sum + n, 0);
  const level = data.waves.threatLevels.find((t) => t.maxUnits === null || count <= t.maxUnits);
  return (level ?? data.waves.threatLevels.at(-1)!).name;
}

export function planWave(data: GameData, ctx: WaveContext, index: number, previousSpawnAt: Date | null): PlannedWave {
  const fronts = waveFronts(data, ctx.activeFronts);
  const front = fronts[index % fronts.length]!;
  const composition = composeWave(data, front, index, waveSize(data, index, ctx.playerCount), ctx.seed, ctx.playerCount);
  return {
    index,
    front,
    spawnAt: spawnTime(data, ctx, index, previousSpawnAt),
    composition,
    threat: threatOf(data, composition),
    stance: waveStance(data, front, ctx.seed, index),
  };
}

// The slowest unit sets the pace, in hexes per hour on plains.
export function marchSpeed(data: GameData, front: Front, composition: Composition): number {
  const units = data.enemies.fronts[front]!.units;
  return Math.min(...Object.keys(composition).map((id) => units[id]!.speed));
}

export function planMarch(
  data: GameData,
  input: {
    terrain: ReadonlyMap<string, TerrainId>;
    radius: number;
    wave: PlannedWave;
    villages: readonly { id: number; q: number; r: number }[];
    seed: number;
    departAt: Date;
    worldSpeed: number;
  },
): March {
  const { terrain, wave } = input;
  const spawnTerrain = data.enemies.fronts[wave.front]!.spawnTerrain;
  const moveCost = (_: Hex, to: Hex): number | null => {
    const type = terrain.get(hexKey(to));
    return type === undefined ? null : data.terrain.terrain[type].moveCost;
  };

  // Spawn hexes: the front's spawn terrain on its side of the map.
  const candidates = [...terrain.entries()]
    .filter(([, type]) => spawnTerrain.includes(type))
    .map(([key]) => {
      const [q, r] = key.split(',').map(Number);
      return hex(q!, r!);
    })
    .filter((cell) => frontOf(cell) === wave.front)
    .sort((a, b) => a.q - b.q || a.r - b.r);
  const rng = rngFor(input.seed, wave.index, 0x5a);
  for (let i = candidates.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j]!, candidates[i]!];
  }

  // Targets: every village, or the Holy City when there are none.
  const targets = input.villages.length
    ? input.villages.map((v) => ({ id: v.id as number | null, cell: hex(v.q, v.r) }))
    : [{ id: null, cell: hex(0, 0) }];

  for (const spawn of candidates.slice(0, MAX_SPAWN_CANDIDATES)) {
    let best: { id: number | null; path: Hex[]; cost: number } | null = null;
    for (const target of targets) {
      const path = findPath(spawn, target.cell, moveCost);
      if (!path) continue;
      const cost = path.slice(1).reduce((sum, cell) => sum + moveCost(cell, cell)!, 0);
      if (!best || cost < best.cost || (cost === best.cost && (target.id ?? 0) < (best.id ?? 0))) {
        best = { id: target.id, path, cost };
      }
    }
    if (!best) continue;

    const hoursPerCost = 1 / marchSpeed(data, wave.front, wave.composition);
    let atMs = 0;
    const path = best.path.map((cell, i) => {
      if (i > 0) atMs += (moveCost(cell, cell)! * hoursPerCost * MS_PER_HOUR) / input.worldSpeed;
      return { q: cell.q, r: cell.r, atMs: Math.round(atMs) };
    });
    return {
      spawn,
      targetVillageId: best.id,
      path,
      arrivesAt: new Date(input.departAt.getTime() + path.at(-1)!.atMs),
    };
  }
  throw new Error(`Wave ${wave.index} found no path from the ${wave.front} front`);
}

export interface OutpostTarget {
  readonly villageId: number;
  readonly plot: string;
  readonly cell: Hex;
}

// Outposts within `reach` hexes of a route, each with the time (ms after
// departure) the horde first comes that close. Steps before `fromMs` are
// already behind it.
export function raidsAlong(
  path: readonly PathStep[],
  outposts: readonly OutpostTarget[],
  reach: number,
  fromMs = 0,
): (OutpostTarget & { atMs: number })[] {
  const raids: (OutpostTarget & { atMs: number })[] = [];
  for (const outpost of outposts) {
    const step = path.find((s) => s.atMs >= fromMs && hexDistance(hex(s.q, s.r), outpost.cell) <= reach);
    if (step) raids.push({ ...outpost, atMs: step.atMs });
  }
  return raids;
}
