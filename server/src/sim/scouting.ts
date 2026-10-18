// Scouting (PLAN.md §7.4). Scouts walk to a wave, some die, and the
// survivors' report is as precise as their number allows. Everything is
// seeded by the world seed and mission id, so a mission resolves the same
// way every time.
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
  terrain: ReadonlyMap<string, TerrainId>,
  from: Hex,
  to: Hex,
  worldSpeed: number,
  bonuses: Bonuses = {},
): number {
  const moveCost = (_: Hex, cell: Hex): number | null => {
    const type = terrain.get(hexKey(cell));
    return type === undefined ? null : data.terrain.terrain[type].moveCost;
  };
  const path = findPath(from, to, moveCost);
  // Off-road targets (e.g. a horde standing in impassable terrain): count
  // straight-line distance over rough ground.
  const cost = path ? path.slice(1).reduce((sum, cell) => sum + moveCost(cell, cell)!, 0) : hexDistance(from, to) * 2;
  const speed = data.units.units[SCOUT_UNIT]!.speed * (1 + bonus(bonuses, 'scoutSpeed'));
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
  const base = data.scouting.survival[front] ?? data.scouting.defaultSurvival;
  const chance = Math.min(0.98, base + bonus(bonuses, 'scoutSurvival'));
  const rng = rngFor(seed, missionId, 0x17);
  let survivors = 0;
  for (let i = 0; i < sent; i++) if (rng() < chance) survivors++;
  return survivors;
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
    dispersed: boolean;
    seed: number;
    missionId: number;
  },
): ScoutReport {
  const base = { sent: input.sent, survivors: input.survivors, dispersed: input.dispersed };
  const tier = [...data.scouting.tiers].reverse().find((t) => input.survivors >= t.minSurvivors);
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
