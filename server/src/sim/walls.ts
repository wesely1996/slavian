// Walls and siege (PLAN.md M5 step 10). A village's walls stand on plot "w"
// and rise through tiers of sturdier material; wall slots ("t0"...) open as
// they rise and hold towers. While the walls stand they toughen the
// garrison, its archers shoot from them, and the horde's fighters can't come
// to grips except where climbing engines (ladders, siege towers) carry them
// over; to end that the horde must batter them down. A horde without the
// engines to do either in time builds them on site first. Numbers in
// data/walls.json; siege values and engines in data/enemies.json.
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

type Tier = GameData['walls']['tiers'][number];

// The tier walls at `level` are built to; null with no walls.
export function wallTierDef(data: GameData, level: number): Tier | null {
  if (level <= 0) return null;
  return [...data.walls.tiers].reverse().find((t) => level >= t.minLevel) ?? data.walls.tiers[0]!;
}

// "Palisade", "Timber Rampart", "Stone Wall", "Fortress Walls"; null with no walls.
export function wallTier(data: GameData, level: number): string | null {
  return wallTierDef(data, level)?.name ?? null;
}

// How many wall slots the walls at `level` hold.
export function openTowerSlots(data: GameData, level: number): number {
  return data.walls.slotsAt.filter((at) => level >= at).length;
}

// How much battering the walls take before they are breached.
export function wallIntegrity(data: GameData, plots: Plots): number {
  const level = wallLevel(plots);
  const gate = towerLevel(plots, 'gate_tower') * data.walls.towers.gate_tower.integrityPerLevel;
  const toughness = wallTierDef(data, level)?.toughness ?? 1;
  return Math.round(data.walls.integrityPerLevel * level * toughness * (1 + gate));
}

// How many men the walls hold.
export function wallCapacity(data: GameData, plots: Plots): number {
  return Math.round(wallLevel(plots) * data.walls.manning.menPerLevel);
}

export interface WallFactors {
  // The garrison's defense and attack multipliers (walls, murder holes;
  // archer towers), and its archers' on top, for those up on the walls.
  readonly defense: number;
  readonly attack: number;
  readonly archers: number;
}

// While the walls stand. `over`: the share of the horde's fighters come over
// the walls by escalade, who take away that share of the walls' defense.
export function wallFactors(data: GameData, plots: Plots, archers = 0, over = 0): WallFactors {
  const t = data.walls.towers;
  const level = wallLevel(plots);
  const shelter = level * data.walls.defensePerLevel + towerLevel(plots, 'murder_holes') * t.murder_holes.defensePerLevel;
  // Archers go up first; the walls hold so many.
  const manned = archers > 0 ? Math.min(1, wallCapacity(data, plots) / archers) : 0;
  return {
    defense: 1 + shelter * (1 - over),
    attack: 1 + towerLevel(plots, 'archer_tower') * t.archer_tower.attackPerLevel,
    archers: 1 + level * data.walls.manning.archerAttackPerLevel * manned,
  };
}

// The share of the battering the moat keeps off.
export function siegeCut(data: GameData, plots: Plots): number {
  return Math.min(0.9, towerLevel(plots, 'ditch') * data.walls.towers.ditch.siegeCutPerLevel);
}

// The share of climbers the moat keeps off the walls.
export function escaladeCut(data: GameData, plots: Plots): number {
  return Math.min(0.9, towerLevel(plots, 'ditch') * data.walls.towers.ditch.escaladeCutPerLevel);
}

function unitSiege(data: GameData, front: Front, unit: string): number {
  const def = data.enemies.fronts[front]?.units[unit];
  if (!def) return 0;
  return def.siege ?? def.attack * data.walls.siege.unitSiegeShare;
}

function unitEscalade(data: GameData, front: Front, unit: string): number {
  return data.enemies.fronts[front]?.units[unit]?.escalade ?? 0;
}

// An engine (rams, catapults, ladders, siege towers), as ballistae see it.
export function isEngine(data: GameData, front: Front, unit: string): boolean {
  return (data.enemies.fronts[front]?.units[unit]?.siege ?? 0) >= 6 || unitEscalade(data, front, unit) > 0;
}

// Its fighters: everyone but the engines.
function fighters(data: GameData, front: Front, units: Units): number {
  return Object.entries(units).reduce((sum, [unit, n]) => sum + (isEngine(data, front, unit) ? 0 : n), 0);
}

// How many men a horde's climbers carry over the walls each round.
export function escaladePower(data: GameData, front: Front, units: Units, plots: Plots): number {
  const raw = Object.entries(units).reduce((sum, [unit, n]) => sum + n * unitEscalade(data, front, unit), 0);
  return raw * (1 - escaladeCut(data, plots));
}

// The share of a horde's fighters over the walls this round.
export function overTheWalls(data: GameData, front: Front, units: Units, plots: Plots): number {
  const men = fighters(data, front, units);
  return men > 0 ? Math.min(1, escaladePower(data, front, units, plots) / men) : 0;
}

// How hard the horde's fighters (not its archers) strike while the walls
// stand, with `over` of them over the walls.
export function heldBack(data: GameData, over: number): number {
  const held = data.walls.escalade.meleeHeld;
  return held + (1 - held) * over;
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
// them: rams enough to breach within walls.siege.breachRounds rounds, or
// climbers enough to carry walls.escalade.climbShare of its fighters over
// each round, by its front's engine; in set-up time scaled by its front's
// siegeCraft, the engine's setupFactor and the village's moat. Null when it
// has what it needs already, or its front builds no engines.
export function siegeWorks(data: GameData, front: Front, units: Units, integrity: number, plots: Plots, worldSpeed: number): SiegeWorks | null {
  const def = data.enemies.fronts[front];
  if (!def?.engine || def.personality.siegeCraft <= 0 || integrity <= 0) return null;
  const engine = def.units[def.engine]!;
  let count: number;
  if (unitEscalade(data, front, def.engine) > 0) {
    const cut = 1 - escaladeCut(data, plots);
    const needed = fighters(data, front, units) * data.walls.escalade.climbShare;
    const have = escaladePower(data, front, units, plots);
    if (have >= needed) return null;
    count = Math.ceil((needed - have) / (unitEscalade(data, front, def.engine) * cut));
  } else {
    const cut = 1 - siegeCut(data, plots);
    const needed = integrity / data.walls.siege.breachRounds;
    const have = siegePower(data, front, units) * cut;
    if (have >= needed) return null;
    count = Math.ceil((needed - have) / (unitSiege(data, front, def.engine) * cut));
  }
  const moat = 1 + towerLevel(plots, 'ditch') * data.walls.towers.ditch.setupPerLevel;
  const hours = data.walls.siege.setupHours * def.personality.siegeCraft * engine.setupFactor * moat;
  return { engine: def.engine, count, setupMs: Math.round((hours * MS_PER_HOUR) / worldSpeed) };
}

// The battering the walls take this round.
export function siegeDamage(data: GameData, front: Front, units: Units, plots: Plots): number {
  return siegePower(data, front, units) * (1 - siegeCut(data, plots));
}

// Engines the ballistae smash this round: their expected kills, rounded at
// random, taken from the biggest engines first.
export function ballistaKills(data: GameData, front: Front, units: Units, plots: Plots, rng: () => number): Record<string, number> {
  const worth = (unit: string) => unitSiege(data, front, unit) + unitEscalade(data, front, unit);
  const expected = towerLevel(plots, 'ballista') * data.walls.towers.ballista.enginesPerLevel;
  let left = Math.floor(expected) + (rng() < expected - Math.floor(expected) ? 1 : 0);
  const engines = Object.entries(units)
    .filter(([unit, n]) => n > 0 && isEngine(data, front, unit))
    .sort((a, b) => worth(b[0]) - worth(a[0]));
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
