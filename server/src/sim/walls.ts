// Walls and siege (PLAN.md M5 step 10). A village's walls stand on plot "w"
// and rise through three tiers; wall slots ("t0"...) open as they rise and
// hold towers. While the walls stand they toughen the garrison, and a horde
// must batter them down; a horde without the siege to do it in time builds
// engines on site first. Numbers in data/walls.json; siege values and
// engines in data/enemies.json.
import type { GameData } from '../data/index.js';
import type { Front } from './mapgen.js';
import type { Units } from './training.js';
import type { Plots } from './village.js';

const MS_PER_HOUR = 3_600_000;

export const WALL_PLOT = 'w';
export const WALL = 'wall';

export function towerPlot(index: number): string {
  return `t${index}`;
}

export function towerIndex(plot: string): number | null {
  const match = /^t(\d+)$/.exec(plot);
  return match ? Number(match[1]) : null;
}

export function wallLevel(plots: Plots): number {
  return plots[WALL_PLOT]?.level ?? 0;
}

// The best level of a kind of tower in the wall slots (0: none).
export function towerLevel(plots: Plots, tower: string): number {
  let best = 0;
  for (const [id, plot] of Object.entries(plots)) {
    if (towerIndex(id) !== null && plot.building === tower) best = Math.max(best, plot.level);
  }
  return best;
}

// "Palisade", "Stone Wall", "Fortress Walls"; null with no walls.
export function wallTier(data: GameData, level: number): string | null {
  if (level <= 0) return null;
  return [...data.walls.tiers].reverse().find((t) => level >= t.minLevel)?.name ?? data.walls.tiers[0]!.name;
}

// How many wall slots the walls at `level` hold.
export function openTowerSlots(data: GameData, level: number): number {
  return data.walls.slotsAt.filter((at) => level >= at).length;
}

// How much battering the walls take before they are breached.
export function wallIntegrity(data: GameData, plots: Plots): number {
  const level = wallLevel(plots);
  const gate = towerLevel(plots, 'gate_tower') * data.walls.towers.gate_tower.integrityPerLevel;
  return Math.round(data.walls.integrityPerLevel * level * (1 + gate));
}

// While the walls stand: the garrison's defense and attack multipliers
// (walls and murder holes; archer towers).
export function wallFactors(data: GameData, plots: Plots): { defense: number; attack: number } {
  const t = data.walls.towers;
  return {
    defense: 1 + wallLevel(plots) * data.walls.defensePerLevel + towerLevel(plots, 'murder_holes') * t.murder_holes.defensePerLevel,
    attack: 1 + towerLevel(plots, 'archer_tower') * t.archer_tower.attackPerLevel,
  };
}

// The share of the battering a ditch and stakes keep off.
export function siegeCut(data: GameData, plots: Plots): number {
  return Math.min(0.9, towerLevel(plots, 'ditch') * data.walls.towers.ditch.siegeCutPerLevel);
}

function unitSiege(data: GameData, front: Front, unit: string): number {
  const def = data.enemies.fronts[front]?.units[unit];
  if (!def) return 0;
  return def.siege ?? def.attack * data.walls.siege.unitSiegeShare;
}

// An engine (rams, catapults, ladders), as ballistae see it.
export function isEngine(data: GameData, front: Front, unit: string): boolean {
  return (data.enemies.fronts[front]?.units[unit]?.siege ?? 0) >= 6;
}

// How hard a horde batters the walls each round.
export function siegePower(data: GameData, front: Front, units: Units): number {
  return Object.entries(units).reduce((sum, [unit, n]) => sum + n * unitSiege(data, front, unit), 0);
}

export interface SiegeWorks {
  // The engine built and how many; how long building them takes.
  readonly engine: string;
  readonly count: number;
  readonly setupMs: number;
}

// What a horde arriving at walls of `integrity` builds before it assaults
// them: enough engines to breach within walls.siege.breachRounds rounds, in
// set-up time scaled by its front's siegeCraft and the village's ditch.
// Null when it has the siege already, or its front builds no engines.
export function siegeWorks(data: GameData, front: Front, units: Units, integrity: number, plots: Plots, worldSpeed: number): SiegeWorks | null {
  const def = data.enemies.fronts[front];
  if (!def?.engine || def.personality.siegeCraft <= 0 || integrity <= 0) return null;
  const cut = 1 - siegeCut(data, plots);
  const needed = integrity / data.walls.siege.breachRounds;
  const have = siegePower(data, front, units) * cut;
  if (have >= needed) return null;
  const perEngine = unitSiege(data, front, def.engine) * cut;
  const count = Math.ceil((needed - have) / perEngine);
  const ditch = 1 + towerLevel(plots, 'ditch') * data.walls.towers.ditch.setupPerLevel;
  const hours = data.walls.siege.setupHours * def.personality.siegeCraft * ditch;
  return { engine: def.engine, count, setupMs: Math.round((hours * MS_PER_HOUR) / worldSpeed) };
}

// The battering the walls take this round.
export function siegeDamage(data: GameData, front: Front, units: Units, plots: Plots): number {
  return siegePower(data, front, units) * (1 - siegeCut(data, plots));
}

// Engines the ballistae smash this round: their expected kills, rounded at
// random, taken from the biggest engines first.
export function ballistaKills(data: GameData, front: Front, units: Units, plots: Plots, rng: () => number): Record<string, number> {
  const expected = towerLevel(plots, 'ballista') * data.walls.towers.ballista.enginesPerLevel;
  let left = Math.floor(expected) + (rng() < expected - Math.floor(expected) ? 1 : 0);
  const engines = Object.entries(units)
    .filter(([unit, n]) => n > 0 && isEngine(data, front, unit))
    .sort((a, b) => unitSiege(data, front, b[0]) - unitSiege(data, front, a[0]));
  const kills: Record<string, number> = {};
  for (const [unit, n] of engines) {
    if (left <= 0) break;
    const k = Math.min(n, left);
    kills[unit] = k;
    left -= k;
  }
  return kills;
}

// Extra warning, in game hours, a watchtower gives before a horde arrives.
export function warningHours(data: GameData, plots: Plots): number {
  return towerLevel(plots, 'watchtower') * data.walls.towers.watchtower.warningHoursPerLevel;
}
