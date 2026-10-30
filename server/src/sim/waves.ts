// Enemy waves (PLAN.md §7.2–7.3). Everything is derived from the world seed
// and the wave index, so a wave is the same whenever it is (re)computed.
//
// A wave is planned ahead (front, spawn time, composition, threat level).
// When it spawns it picks a hex in its front's spawn zone and marches to its
// target: the cheapest by road, fear and faction (routeFrom; the Holy City
// is always one). What it does there is the horde AI (horde.ts).
import { canCross, fastestRoad, roadFactor, roadLevel, type Land } from './land.js';
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
  // Difficulty and group power (difficulty.ts): base size × this.
  readonly sizeFactor?: number;
}

export function rngFor(seed: number, index: number, salt: number): () => number {
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
// The units a wave of `index` draws from, with their weights: a tier joins
// from tiers.minWave, and each tier unlocked after a unit's own halves (by
// tiers.fade) how common it is.
export function waveUnits(data: GameData, front: Front, index: number, playerCount = 1): [string, number][] {
  const tiers = data.enemies.tiers;
  const unlocked = tiers.minWave.filter((wave) => wave <= index).length;
  const out: [string, number][] = [];
  for (const [id, def] of Object.entries(data.enemies.fronts[front]!.units)) {
    const from = def.tier ? tiers.minWave[def.tier - 1]! : def.minWave;
    // Engines built on site (weight 0) never set out with a wave.
    if (def.weight <= 0 || from > index || (def.minPlayers ?? 1) > playerCount) continue;
    out.push([id, def.tier ? def.weight * tiers.fade ** (unlocked - def.tier) : def.weight]);
  }
  return out;
}

export function composeWave(data: GameData, front: Front, index: number, size: number, seed: number, playerCount = 1): Composition {
  const units = waveUnits(data, front, index, playerCount);
  const totalWeight = units.reduce((sum, [, weight]) => sum + weight, 0);
  const composition: Composition = {};
  let assigned = 0;
  for (const [id, weight] of units) {
    const count = Math.floor((size * weight) / totalWeight);
    if (count > 0) composition[id] = count;
    assigned += count;
  }
  const rng = rngFor(seed, index, 0xc0);
  for (; assigned < size; assigned++) {
    let roll = rng() * totalWeight;
    const [id] = units.find(([, weight]) => (roll -= weight) < 0) ?? units.at(-1)!;
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
  const size = Math.max(1, Math.round(waveSize(data, index, ctx.playerCount) * (ctx.sizeFactor ?? 1)));
  const composition = composeWave(data, front, index, size, ctx.seed, ctx.playerCount);
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

export interface Target {
  readonly id: number | null;
  readonly cell: Hex;
}

// The cheapest target from `from` for this horde: road cost (terrain plus
// fear along the way) plus fear at the target, plus extra for the Holy City
// (always a target, taken when it is cheaper than every village). Erratic
// factions jitter the costs of villages against each other. Steps are timed
// by terrain alone, from `startMs` (ms after spawn).
export function routeFrom(
  data: GameData,
  input: {
    terrain: Land;
    from: Hex;
    targets: readonly Target[];
    front: Front;
    composition: Composition;
    fear?: ReadonlyMap<string, number>;
    rng: () => number;
    startMs: number;
    worldSpeed: number;
  },
): { targetVillageId: number | null; path: PathStep[]; arrivesMs: number } | null {
  const { terrain, fear } = input;
  const rules = data.horde;
  const moveCost = (to: Hex): number | null => {
    const type = terrain.get(hexKey(to));
    return type === undefined ? null : data.terrain.terrain[type].moveCost;
  };
  // Human hordes take the roads; the Monsters of the North keep off them.
  const roads = input.front !== 'north';
  const stepCost = (from: Hex, to: Hex): number | null => {
    const cost = canCross(terrain, from, to) ? moveCost(to) : null;
    return cost !== null && roads ? cost * roadFactor(data, roadLevel(terrain, from, to)) : cost;
  };
  const searchCost = (from: Hex, to: Hex): number | null => {
    const cost = stepCost(from, to);
    return cost === null ? null : cost + rules.fear.pathWeight * (fear?.get(hexKey(to)) ?? 0);
  };
  const erratic = data.enemies.fronts[input.front]!.personality.erratic;
  let best: { id: number | null; path: Hex[]; score: number } | null = null;
  let holy: { path: Hex[]; cost: number } | null = null;
  let cheapestVillage = Infinity;
  for (const target of input.targets) {
    const path = findPath(input.from, target.cell, searchCost, roads ? fastestRoad(data) : 1);
    if (!path) continue;
    const road = path.slice(1).reduce((sum, cell, i) => sum + searchCost(path[i]!, cell)!, 0);
    const cost = road + rules.fear.targetWeight * (fear?.get(hexKey(target.cell)) ?? 0);
    if (target.id === null) {
      holy = { path, cost: cost + rules.holyCityExtraCost };
      continue;
    }
    cheapestVillage = Math.min(cheapestVillage, cost);
    const score = cost * (1 + erratic * input.rng());
    if (!best || score < best.score || (score === best.score && (target.id ?? 0) < (best.id ?? 0))) {
      best = { id: target.id, path, score };
    }
  }
  if (holy && holy.cost < cheapestVillage) best = { id: null, path: holy.path, score: holy.cost };
  if (!best) return null;
  const hoursPerCost = 1 / marchSpeed(data, input.front, input.composition);
  let atMs = input.startMs;
  const path = best.path.map((cell, i) => {
    if (i > 0) atMs += (stepCost(best!.path[i - 1]!, cell)! * hoursPerCost * MS_PER_HOUR) / input.worldSpeed;
    return { q: cell.q, r: cell.r, atMs: Math.round(atMs) };
  });
  return { targetVillageId: best.id, path, arrivesMs: path.at(-1)!.atMs };
}

// Every village it may strike, and the Holy City.
export function targetsOf(villages: readonly { id: number; q: number; r: number }[]): Target[] {
  return [...villages.map((v) => ({ id: v.id as number | null, cell: hex(v.q, v.r) })), { id: null, cell: hex(0, 0) }];
}

export function planMarch(
  data: GameData,
  input: {
    terrain: Land;
    radius: number;
    wave: PlannedWave;
    villages: readonly { id: number; q: number; r: number }[];
    seed: number;
    departAt: Date;
    worldSpeed: number;
    fear?: ReadonlyMap<string, number>;
  },
): March {
  const { terrain, wave } = input;
  const spawnTerrain = data.enemies.fronts[wave.front]!.spawnTerrain;

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

  const targets = targetsOf(input.villages);
  for (const spawn of candidates.slice(0, MAX_SPAWN_CANDIDATES)) {
    const route = routeFrom(data, {
      terrain,
      from: spawn,
      targets,
      front: wave.front,
      composition: wave.composition,
      ...(input.fear ? { fear: input.fear } : {}),
      rng: rngFor(input.seed, wave.index, 0x7a),
      startMs: 0,
      worldSpeed: input.worldSpeed,
    });
    if (!route) continue;
    return {
      spawn,
      targetVillageId: route.targetVillageId,
      path: route.path,
      arrivesAt: new Date(input.departAt.getTime() + route.arrivesMs),
    };
  }
  throw new Error(`Wave ${wave.index} found no path from the ${wave.front} front`);
}

export interface OutpostTarget {
  readonly villageId: number;
  readonly plot: string;
  readonly cell: Hex;
}

// Outposts (or supply points) within `reach` hexes of a route, each with
// the time (ms after departure) the horde first comes that close. Steps
// before `fromMs` are already behind it.
export function raidsAlong<T extends { readonly cell: Hex }>(
  path: readonly PathStep[],
  outposts: readonly T[],
  reach: number,
  fromMs = 0,
): (T & { atMs: number })[] {
  const raids: (T & { atMs: number })[] = [];
  for (const outpost of outposts) {
    const step = path.find((s) => s.atMs >= fromMs && hexDistance(hex(s.q, s.r), outpost.cell) <= reach);
    if (step) raids.push({ ...outpost, atMs: step.atMs });
  }
  return raids;
}
