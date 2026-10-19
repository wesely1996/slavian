// Horde AI (PLAN.md §7.3): what a horde does after beating a village (raid
// or raze, by reasoning), ruins and their rebuilding, where survivors camp,
// refugee camps and the Holy City's guard. Targeting by fear is in waves.ts
// (routeFrom). Numbers in data/horde.json.
import type { GameData, TerrainId } from '../data/index.js';
import { hex, hexDistance, hexKey, ring, type Hex } from './hex.js';
import type { Front } from './mapgen.js';
import { mapResources, type Resources } from './resources.js';
import { levelCost, type Plot } from './village.js';

const MS_PER_HOUR = 3_600_000;

export interface RazeInput {
  readonly front: Front;
  readonly waveIndex: number;
  // From the difficulty preset (defaults: data/horde.json).
  readonly graceWaves?: number;
  readonly thresholdOffset?: number;
  // A refugee camp: never razed.
  readonly refuge?: boolean;
  // Units left now, and when it spawned.
  readonly hordeNow: number;
  readonly hordeInitial: number;
  // Troops that could come to the village's aid (reinforce rules nearby).
  readonly helpNearby: number;
  // Game time left on its rampage clock, in ms (world speed applied).
  readonly rampageLeftMs: number;
  readonly worldSpeed: number;
}

export interface Decision {
  readonly choice: 'raid' | 'raze';
  readonly reasons: string[];
}

export function razeMs(data: GameData, worldSpeed: number): number {
  return (data.horde.raze.hours * MS_PER_HOUR) / worldSpeed;
}

// Raze when there is time, the strength to hold off help, and the faction
// leans that way; otherwise take what can be carried and move on.
export function decideRaze(data: GameData, input: RazeInput): Decision {
  const rules = data.horde.raze;
  // The first hordes are raiding parties, testing the land.
  if (input.waveIndex < (input.graceWaves ?? rules.graceWaves)) return { choice: 'raid', reasons: ['an early raiding party'] };
  if (input.refuge) return { choice: 'raid', reasons: ['refugees have nothing left to burn'] };
  if (input.rampageLeftMs < razeMs(data, input.worldSpeed)) return { choice: 'raid', reasons: ['no time to raze'] };
  const strength = input.hordeNow / Math.max(1, input.helpNearby);
  if (strength < rules.minStrength) return { choice: 'raid', reasons: ['help is near'] };
  const reasons: string[] = [];
  const bias = data.enemies.fronts[input.front]!.personality.razeBias;
  let score = bias + Math.log2(strength);
  if (bias > 0) reasons.push('its faction burns what it takes');
  if (bias < 0) reasons.push('its faction prefers plunder');
  if (input.hordeNow < input.hordeInitial / 2) {
    score -= rules.weakenedPenalty;
    reasons.push('it is weakened');
  }
  reasons.push(strength >= 4 ? 'nothing nearby can stop it' : 'it outnumbers the help nearby');
  return score >= rules.threshold + (input.thresholdOffset ?? 0) ? { choice: 'raze', reasons } : { choice: 'raid', reasons };
}

// After a raid the horde swells with recruits (or beasts drawn to the kill).
export function recruit(data: GameData, initial: Record<string, number>, now: Record<string, number>): Record<string, number> {
  const share = data.horde.raid.recruitShare;
  const next: Record<string, number> = { ...now };
  for (const [unit, n] of Object.entries(initial)) {
    const extra = Math.floor(n * share);
    if (extra > 0) next[unit] = (next[unit] ?? 0) + extra;
  }
  return next;
}

// Everything burned: buildings and fields stand at level 0.
export function ruinPlots(plots: Readonly<Record<string, Plot>>): Record<string, Plot> {
  return Object.fromEntries(Object.entries(plots).map(([id, plot]) => [id, { ...plot, level: 0 }]));
}

// A share of what everything that stood cost to build.
export function rebuildCost(data: GameData, plots: Readonly<Record<string, Plot>>): Resources {
  const sum = mapResources(() => 0);
  for (const plot of Object.values(plots)) {
    const def = plot.building ? data.buildings.buildings[plot.building] : undefined;
    if (!def) continue;
    for (let level = 1; level <= plot.level; level++) {
      const cost = levelCost(def, level);
      for (const kind of Object.keys(sum) as (keyof Resources)[]) sum[kind] += cost[kind];
    }
  }
  return mapResources((kind) => Math.round(sum[kind] * data.horde.ruins.rebuildCostShare));
}

export function rebuildMs(data: GameData, worldSpeed: number): number {
  return (data.horde.ruins.rebuildHours * MS_PER_HOUR) / worldSpeed;
}

function passable(data: GameData, terrain: ReadonlyMap<string, TerrainId>, cell: Hex): boolean {
  const type = terrain.get(hexKey(cell));
  return type !== undefined && type !== 'holy_city' && data.terrain.terrain[type].moveCost !== null;
}

// Where survivors settle: the nearest free passable hex around `from`.
export function campSite(data: GameData, terrain: ReadonlyMap<string, TerrainId>, from: Hex, taken: ReadonlySet<string>): Hex | null {
  for (let radius = 1; radius <= 4; radius++) {
    const cell = ring(from, radius).find((c) => passable(data, terrain, c) && !taken.has(hexKey(c)));
    if (cell) return cell;
  }
  return null;
}

// A refugee camp near the Holy City, on settleable free ground (the
// nearest there is, if none is close).
export function refugeeSite(data: GameData, terrain: ReadonlyMap<string, TerrainId>, taken: ReadonlySet<string>): Hex | null {
  const { minDistance } = data.horde.refugeeCamp;
  const radius = Math.max(...[...terrain.keys()].map((key) => { const [q, r] = key.split(',').map(Number); return hexDistance(hex(q!, r!), hex(0, 0)); }), 0);
  for (let d = minDistance; d <= radius; d++) {
    const cell = ring(hex(0, 0), d).find((c) => {
      const type = terrain.get(hexKey(c));
      return type !== undefined && data.terrain.terrain[type].settleable && !taken.has(hexKey(c));
    });
    if (cell) return cell;
  }
  return null;
}

// The Holy City's guard grows with every wave.
export function holyCityGuard(data: GameData, waveIndex: number): Record<string, number> {
  const growth = data.horde.holyCity.guardGrowthPerWave ** waveIndex;
  return Object.fromEntries(Object.entries(data.horde.holyCity.guard).map(([unit, n]) => [unit, Math.round(n * growth)]));
}

export function sanctityDamage(data: GameData, survivors: number): number {
  return Math.ceil(survivors * data.horde.holyCity.damagePerUnit);
}

export function fearLeft(data: GameData, killed: number): number {
  return data.horde.fear.perDefeat + data.horde.fear.perUnitLost * killed;
}

export function isHolyCity(cell: Hex): boolean {
  return hexDistance(cell, hex(0, 0)) === 0;
}
