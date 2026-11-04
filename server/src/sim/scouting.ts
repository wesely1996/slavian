// Scouting (PLAN.md §7.4). Scouts walk to a wave, some die, and the
// survivors' report is as precise as their number allows. Everything is
// seeded by the world seed and mission id, so a mission resolves the same
// way every time.
import { fastestStep, moveCostOn, type Land } from './land.js';
import type { GameData, Stance, TerrainId } from '../data/index.js';
import { findPath, hex, hexDistance, hexKey, type Hex } from './hex.js';
import { frontOf, type Front } from './mapgen.js';
import { createRng } from './rng.js';
import type { Composition } from './waves.js';
import { bonus, type Bonuses } from './research.js';

const MS_PER_HOUR = 3_600_000;
export const SCOUT_UNIT = 'scout';

export interface ScoutedUnit {
  readonly unit: string;
  readonly name: string;
  // Null when the report only names the unit (rough tier).
  readonly min: number | null;
  readonly max: number | null;
}

export interface ScoutReport {
  readonly sent: number;
  readonly survivors: number;
  readonly tier: 'none' | string;
  readonly size: { readonly min: number; readonly max: number } | null;
  // Rough reports name only the most numerous unit; better ones list all.
  readonly units: readonly ScoutedUnit[];
  // Revealed by good enough reports; null otherwise.
  readonly stance: Stance | null;
  // The horde had scattered before the scouts arrived.
  readonly dispersed: boolean;
  // Assassins killed the horde's leader (their title then).
  readonly leaderSlain?: string;
}

// The scout kinds (family scout), in the order of units.json.
export function scoutKinds(data: GameData): string[] {
  return Object.keys(data.units.units).filter((unit) => data.units.units[unit]!.family === 'scout');
}

export function isScout(data: GameData, unit: string): boolean {
  return data.units.units[unit]?.family === 'scout';
}

// What scouts are worth to a report or an army: their units' intel.
export function intelOf(data: GameData, units: Readonly<Record<string, number>>): number {
  let sum = 0;
  for (const [unit, n] of Object.entries(units)) if (n > 0 && isScout(data, unit)) sum += n * (data.units.units[unit]!.scouting?.intel ?? 1);
  return sum;
}

// What an army's scouts add to its attack and defense.
export function intelBonus(data: GameData, units: Readonly<Record<string, number>>): number {
  return Math.min(data.scouting.intel.max, data.scouting.intel.perPoint * intelOf(data, units));
}

// An army's stats with its scouts' intel bonus.
export function withIntel<S extends { attack: number; defense: number }>(
  data: GameData,
  units: Readonly<Record<string, number>>,
  stats: (unit: string) => S,
): (unit: string) => S {
  const f = 1 + intelBonus(data, units);
  if (f === 1) return stats;
  return (unit) => {
    const s = stats(unit);
    return { ...s, attack: s.attack * f, defense: s.defense * f };
  };
}

// The units that fight: all but scouts.
export function combatants(data: GameData, units: Readonly<Record<string, number>>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(units)) if (n > 0 && !isScout(data, unit)) out[unit] = n;
  return out;
}

// The scouts among `units`.
export function scoutsIn(data: GameData, units: Readonly<Record<string, number>>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(units)) if (n > 0 && isScout(data, unit)) out[unit] = n;
  return out;
}

// Where a wave can be found at `at`: on the march, at its target, or (not
// yet spawned) gathering in its front's spawn zone nearest to the village.
export function scoutTarget(
  data: GameData,
  terrain: ReadonlyMap<string, TerrainId>,
  wave: { front: Front; status: string; spawnAt: Date; path: readonly { q: number; r: number; atMs: number }[] | null },
  from: Hex,
  at: Date,
): Hex {
  if (wave.path && wave.path.length > 0) {
    const elapsed = at.getTime() - wave.spawnAt.getTime();
    const reached = wave.path.filter((step) => step.atMs <= elapsed).at(-1) ?? wave.path[0]!;
    return hex(reached.q, reached.r);
  }
  const zone = data.enemies.fronts[wave.front]?.spawnTerrain ?? [];
  let best: Hex | null = null;
  for (const [key, type] of terrain) {
    if (!zone.includes(type)) continue;
    const [q, r] = key.split(',').map(Number);
    const cell = hex(q!, r!);
    if (frontOf(cell) !== wave.front) continue;
    if (!best || hexDistance(from, cell) < hexDistance(from, best)) best = cell;
  }
  return best ?? from;
}

// Real-time milliseconds for scouts to walk from `from` to `to`.
export function scoutTravelMs(
  data: GameData,
  terrain: Land,
  from: Hex,
  to: Hex,
  worldSpeed: number,
  bonuses: Bonuses = {},
  units: Readonly<Record<string, number>> = { [SCOUT_UNIT]: 1 },
): number {
  const moveCost = moveCostOn(data, terrain);
  const path = findPath(from, to, moveCost, fastestStep(data, terrain));
  // Off-road targets (e.g. a horde standing in impassable terrain): count
  // straight-line distance over rough ground.
  const cost = path ? path.slice(1).reduce((sum, cell, i) => sum + moveCost(path[i]!, cell)!, 0) : hexDistance(from, to) * 2;
  // At the pace of the slowest sent.
  const sent = Object.keys(units).filter((unit) => (units[unit] ?? 0) > 0);
  const slowest = Math.min(...(sent.length ? sent : [SCOUT_UNIT]).map((unit) => data.units.units[unit]!.speed));
  const speed = slowest * (1 + bonus(bonuses, 'scoutSpeed'));
  return Math.max(1, Math.round(((cost / speed) * MS_PER_HOUR) / worldSpeed));
}

function rngFor(seed: number, missionId: number, salt: number): () => number {
  return createRng((seed ^ Math.imul(missionId + 1, 0x85ebca6b) ^ salt) >>> 0);
}

export function survivorsOf(
  data: GameData,
  front: Front,
  sent: number,
  seed: number,
  missionId: number,
  bonuses: Bonuses = {},
): number {
  return survivingScouts(data, front, { [SCOUT_UNIT]: sent }, seed, missionId, bonuses)[SCOUT_UNIT] ?? 0;
}

// Which of the scouts sent come through, kind by kind (in units.json
// order): each is caught with the front's chance scaled by its stealth.
export function survivingScouts(
  data: GameData,
  front: Front,
  sent: Readonly<Record<string, number>>,
  seed: number,
  missionId: number,
  bonuses: Bonuses = {},
): Record<string, number> {
  const base = data.scouting.survival[front] ?? data.scouting.defaultSurvival;
  const rng = rngFor(seed, missionId, 0x17);
  const out: Record<string, number> = {};
  for (const unit of scoutKinds(data)) {
    const n = sent[unit] ?? 0;
    if (n <= 0) continue;
    const stealth = data.units.units[unit]!.scouting?.stealth ?? 1;
    const chance = Math.min(0.98, 1 - (1 - base) * stealth + bonus(bonuses, 'scoutSurvival'));
    let survivors = 0;
    for (let i = 0; i < n; i++) if (rng() < chance) survivors++;
    out[unit] = survivors;
  }
  return out;
}

// Whether the assassins among the survivors kill the horde's leader.
export function assassinates(data: GameData, survivors: Readonly<Record<string, number>>, seed: number, missionId: number): boolean {
  const rng = rngFor(seed, missionId, 0x5a);
  for (const unit of scoutKinds(data)) {
    const chance = data.units.units[unit]!.scouting?.assassinate ?? 0;
    if (chance <= 0) continue;
    for (let i = 0; i < (survivors[unit] ?? 0); i++) if (rng() < chance) return true;
  }
  return false;
}

// A range of relative width `error` around `value` that always contains it,
// with the true value placed randomly inside so it cannot be read off the
// midpoint.
function range(value: number, error: number, rng: () => number): { min: number; max: number } {
  if (error === 0) return { min: value, max: value };
  const shift = (rng() - 0.5) * error * value;
  return {
    min: Math.max(0, Math.floor(value + shift - error * value)),
    max: Math.ceil(value + shift + error * value),
  };
}

export function scoutReport(
  data: GameData,
  input: {
    front: Front;
    composition: Composition;
    stance: Stance;
    sent: number;
    survivors: number;
    // The survivors' intel (absent: one a scout).
    intel?: number;
    dispersed: boolean;
    seed: number;
    missionId: number;
  },
): ScoutReport {
  const base = { sent: input.sent, survivors: input.survivors, dispersed: input.dispersed };
  const intel = input.intel ?? input.survivors;
  const tier = [...data.scouting.tiers].reverse().find((t) => intel >= t.minSurvivors);
  if (!tier || input.dispersed) return { ...base, tier: 'none', size: null, units: [], stance: null };

  const names = data.enemies.fronts[input.front]!.units;
  const rng = rngFor(input.seed, input.missionId, 0x2e);
  const entries = Object.entries(input.composition).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const total = entries.reduce((sum, [, count]) => sum + count, 0);
  const size = range(total, tier.sizeError, rng);

  const unitError = tier.unitError;
  const units: ScoutedUnit[] =
    unitError === null
      ? entries.slice(0, 1).map(([unit]) => ({ unit, name: names[unit]?.name ?? unit, min: null, max: null }))
      : entries.map(([unit, count]) => ({ unit, name: names[unit]?.name ?? unit, ...range(count, unitError, rng) }));
  return { ...base, tier: tier.name, size, units, stance: tier.revealsStance ? input.stance : null };
}
