// The enemy's forces in its lands (data/enemy-lands.json forces): each
// settlement's garrison and scouts, the war bands it sends out, the chance
// its scouts spot an army, and a horde's scouts finding an ambush. The solo
// engine (client/scripts/local/enemy_forces.gd) reckons it the same.
import type { GameData } from '../data/index.js';
import { hex, type Hex } from './hex.js';
import type { Land, LandWall } from './land.js';
import type { Front } from './mapgen.js';
import type { Units } from './training.js';
import { composeWave, type PathStep } from './waves.js';

const TWO_32 = 4294967296;

// A seed from a few whole numbers (the same in the solo engine).
export function forceSeed(...parts: number[]): number {
  return parts.reduce((sum, p, i) => (sum + p * (i === 0 ? 1 : 7919 * i)) % TWO_32, 0);
}

// How many scouts a settlement of `level` keeps.
export function settlementScouts(data: GameData, level: number): number {
  return 1 + Math.floor((level - 1) / data.enemyLands.forces.scouts.perLevels);
}

// How many troops a settlement's garrison holds at `level`.
export function garrisonSize(data: GameData, kind: string, level: number): number {
  const g = data.enemyLands.forces.garrison;
  return Math.max(1, Math.round(g.baseUnits * (1 + g.perLevel * (level - 1)) * (g.kinds[kind] ?? 1)));
}

// A settlement's garrison: its front's troops, as a horde of index `level`.
export function garrisonOf(data: GameData, s: { id: number; front: string; kind: string }, level: number, seed: number, players: number): Units {
  return composeWave(data, s.front as Front, level, garrisonSize(data, s.kind, level), forceSeed(seed, s.id, level), players);
}

// `share` of a force (by unit, rounded; at least one man).
export function shareOf(units: Units, share: number): Units {
  const out: Record<string, number> = {};
  for (const unit of Object.keys(units).sort()) {
    const n = Math.round((units[unit] ?? 0) * share);
    if (n > 0) out[unit] = n;
  }
  if (!Object.keys(out).length) {
    const first = Object.keys(units).sort().find((u) => (units[u] ?? 0) > 0);
    if (first) out[first] = 1;
  }
  return out;
}

// The scouts among a force (family scout).
export function scoutsIn(data: GameData, units: Readonly<Record<string, number>>): number {
  let n = 0;
  for (const [unit, count] of Object.entries(units)) if (data.units.units[unit]?.family === 'scout') n += count;
  return n;
}

// The chance `scouts` spot (or find) what `against` scouts guard: each one
// not cancelled, one for one, has scoutChance.
export function spotChance(data: GameData, scouts: number, against: number): number {
  const left = scouts - against;
  return left > 0 ? 1 - (1 - data.enemyLands.forces.scoutChance) ** left : 0;
}

// A horde's scouts: one for every hordeUnitsPerScout troops.
export function hordeScouts(data: GameData, composition: Readonly<Record<string, number>>): number {
  const total = Object.values(composition).reduce((sum, n) => sum + n, 0);
  return Math.floor(total / data.enemyLands.forces.scouts.hordeUnitsPerScout);
}

// The hex something on `path` (ms after `departsAt`) is in at `at`: the
// last it entered.
export function hexOnPath(path: readonly PathStep[], departsAt: Date, at: Date): Hex {
  const elapsed = at.getTime() - departsAt.getTime();
  let step = path[0]!;
  for (const s of path) if (s.atMs <= elapsed) step = s;
  return hex(step.q, step.r);
}

// Where an army is at `at`: on its hex, or on its road out or home.
export function armyHexAt(
  army: { status: string; targetQ: number; targetR: number; path: readonly PathStep[] | null; departsAt: Date; leavesAt?: Date | null },
  at: Date,
): Hex | null {
  if (army.status === 'stationed' || army.status === 'engaged') return hex(army.targetQ, army.targetR);
  if (!army.path?.length) return null;
  if (army.status === 'marching') return hexOnPath(army.path, army.departsAt, at);
  if (army.status === 'returning' && army.leavesAt) {
    const total = army.path.at(-1)!.atMs;
    const back = [...army.path].reverse().map((s) => ({ q: s.q, r: s.r, atMs: total - s.atMs }));
    return hexOnPath(back, army.leavesAt, at);
  }
  return null;
}

// The land war bands march on: the players' walls stop them, their own don't.
export function bandLand(land: Land): Land {
  const walls = new Map<string, readonly LandWall[]>();
  for (const [key, list] of land.walls ?? new Map<string, readonly LandWall[]>()) {
    const players = list.filter((w) => !w.enemy);
    if (players.length) walls.set(key, players);
  }
  const out: Record<string, unknown> = {};
  for (const key of ['blocked', 'roads', 'damaged', 'lanes', 'burning', 'forts', 'blessed', 'banks'] as const) {
    if (land[key] !== undefined) out[key] = land[key];
  }
  return Object.assign(new Map(land), out, { walls }) as Land;
}
