// Forts as strongholds (forts.json): the Keep, the Storage and three wall
// rings with their towers, built one level at a time and paid from the
// village that built the fort; the Keep's zone of influence; the grain its
// Storage keeps and what it eats.
import type { GameData } from '../data/index.js';
import { hexDistance, type Hex } from './hex.js';
import { mapResources, type Resources } from './resources.js';

// What a level of a fort building costs and takes.
export interface FortBuildingDef {
  readonly name: string;
  readonly cost: Resources;
  readonly costGrowth: number;
  readonly buildSeconds: number;
  readonly timeGrowth: number;
  readonly maxLevel: number;
}

// What stands on a fort's plot: `keep`, `storage`, `w0`-`w2` (the walls,
// inner to outer) and `t<ring>-<slot>` (towers).
export interface FortPlot {
  readonly kind: string;
  readonly level: number;
}
export type FortPlots = Readonly<Record<string, FortPlot>>;

// The one building rising in a fort.
export interface FortWork {
  readonly plot: string;
  readonly kind: string;
  readonly level: number;
  readonly completesAt: string;
}

// What a fort starts with once built: the Keep and the Storage at level 1.
export function startingPlots(): FortPlots {
  return { keep: { kind: 'keep', level: 1 }, storage: { kind: 'storage', level: 1 } };
}

export function levelOf(plots: FortPlots, plot: string): number {
  return plots[plot]?.level ?? 0;
}

const WALL = /^w([0-2])$/;
const TOWER = /^t([0-2])-(\d+)$/;

// The ring a wall or tower plot belongs to (0 inner, 2 outer), or null.
export function ringOf(plot: string): number | null {
  const m = WALL.exec(plot) ?? TOWER.exec(plot);
  return m ? Number(m[1]) : null;
}

// Every plot of a fort, in order: the Keep, the Storage, then each ring's
// wall and its tower slots.
export function fortPlotIds(data: GameData): string[] {
  const out = ['keep', 'storage', 'garrison'];
  data.forts.rings.forEach((ring, i) => {
    out.push(`w${i}`);
    for (let s = 0; s < ring.slots; s++) out.push(`t${i}-${s}`);
  });
  return out;
}

// The building a plot holds or would hold: its cost and times as a
// BuildingDef, its ring's share of the village's for walls and towers.
export function fortBuildingDef(data: GameData, plot: string, kind: string): FortBuildingDef | null {
  if (plot === 'keep' || plot === 'storage' || plot === 'garrison') {
    if (kind !== plot) return null;
    return data.forts.buildings[plot];
  }
  const ring = ringOf(plot);
  if (ring === null) return null;
  const isWall = WALL.test(plot);
  const def = data.buildings.buildings[kind];
  if (!def || def.kind !== (isWall ? 'wall' : 'tower')) return null;
  if (!isWall && !(kind in data.walls.towers)) return null;
  const factor = data.forts.rings[ring]!.costFactor;
  return {
    name: def.name,
    cost: mapResources((k) => Math.round(def.cost[k] * factor)),
    costGrowth: def.costGrowth,
    buildSeconds: def.buildSeconds,
    timeGrowth: def.timeGrowth,
    maxLevel: isWall ? data.forts.wallMaxLevel : data.forts.towerMaxLevel,
  };
}

export function fortLevelCost(def: FortBuildingDef, level: number): Resources {
  const factor = def.costGrowth ** (level - 1);
  return mapResources((kind) => Math.round(def.cost[kind] * factor));
}

// Real-time milliseconds.
export function fortBuildMs(def: FortBuildingDef, level: number, worldSpeed: number): number {
  return Math.round((def.buildSeconds * def.timeGrowth ** (level - 1) * 1000) / worldSpeed);
}

// Why `kind` can't rise a level on `plot` (null: it can).
export function fortBuildProblem(data: GameData, plots: FortPlots, work: FortWork | null, plot: string, kind: string): string | null {
  if (work) return 'Something is already being built in this fort';
  const def = fortBuildingDef(data, plot, kind);
  if (!def) return 'That cannot be built there';
  const now = plots[plot];
  if (now && now.kind !== kind) return 'Something else stands there';
  const level = (now?.level ?? 0) + 1;
  if (level > def.maxLevel) return 'It is at its highest level';
  const ring = ringOf(plot);
  if (ring !== null) {
    const rule = data.forts.rings[ring]!;
    if (levelOf(plots, 'keep') < rule.keepLevel) return `The ${rule.name.toLowerCase()} needs the Keep at level ${rule.keepLevel}`;
    if (!WALL.test(plot)) {
      const wall = levelOf(plots, `w${ring}`);
      if (wall === 0) return 'Build the wall first';
      if (level > wall) return 'A tower cannot rise above its wall';
      const slot = Number(TOWER.exec(plot)![2]);
      if (slot >= rule.slots) return 'That cannot be built there';
    }
  }
  return null;
}

// How far the Keep's zone of influence reaches.
export function zoneRadius(data: GameData, plots: FortPlots): number {
  const keep = levelOf(plots, 'keep');
  if (keep === 0) return 0;
  return data.forts.zone.base + Math.floor((keep - 1) / data.forts.zone.every);
}

export interface ZoneFort {
  readonly kind: string;
  readonly status: string;
  readonly villageId: number | null;
  readonly q: number;
  readonly r: number;
  readonly plots: FortPlots;
}

// Whether `cell` lies in the zone of a standing fort built by `villageId`.
export function inFortZone(data: GameData, forts: readonly ZoneFort[], villageId: number, cell: Hex): boolean {
  return forts.some(
    (f) => f.kind === 'fort' && f.status === 'standing' && f.villageId === villageId && hexDistance(cell, { q: f.q, r: f.r }) <= zoneRadius(data, f.plots),
  );
}

// The grain a fort or supply point keeps at most.
export function grainCapacity(data: GameData, fort: { readonly kind: string; readonly plots?: FortPlots | undefined }): number {
  if (fort.kind === 'supply') return data.field.supplyPoint.grainCapacity;
  return data.forts.storage.grainBase + data.forts.storage.grainPerLevel * levelOf(fort.plots ?? {}, 'storage');
}

// The grain a standing fort eats a game hour (its defenders' too).
export function fortUpkeep(data: GameData, plots: FortPlots, defenders: Readonly<Record<string, number>> = {}): number {
  const men = Object.values(defenders).reduce((a, b) => a + b, 0);
  return data.forts.upkeep.grainPerHour + data.forts.upkeep.perKeepLevel * levelOf(plots, 'keep') + data.forts.upkeep.perDefender * men;
}

// The defenders the Fort Garrison keeps at its level.
export function defendersWanted(data: GameData, plots: FortPlots): Record<string, number> {
  const level = levelOf(plots, 'garrison');
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(data.forts.garrison.perLevel)) if (n * level > 0) out[unit] = n * level;
  return out;
}

// `count` fallen defenders come back, one at a time, each the kind most
// short of what the Garrison keeps (in perLevel's order on a tie).
export function musterDefenders(data: GameData, plots: FortPlots, defenders: Readonly<Record<string, number>>, count: number): Record<string, number> {
  const wanted = defendersWanted(data, plots);
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(defenders)) if (n > 0 && (wanted[unit] ?? 0) > 0) out[unit] = Math.min(n, wanted[unit]!);
  for (let i = 0; i < count; i++) {
    let best: string | null = null;
    let short = 0;
    for (const unit of Object.keys(data.forts.garrison.perLevel)) {
      const gap = (wanted[unit] ?? 0) - (out[unit] ?? 0);
      if (gap > short) {
        best = unit;
        short = gap;
      }
    }
    if (!best) break;
    out[best] = (out[best] ?? 0) + 1;
  }
  return out;
}

// The village-style plots of a fort's wall ring (sim/walls.ts): its wall
// on "w" and its towers on "t0"...
export function ringPlots(plots: FortPlots, ring: number): Record<string, { building: string; level: number }> {
  const out: Record<string, { building: string; level: number }> = {};
  const wall = plots[`w${ring}`];
  if (wall) out.w = { building: 'wall', level: wall.level };
  for (const [id, p] of Object.entries(plots)) {
    const m = TOWER.exec(id);
    if (m && Number(m[1]) === ring) out[`t${m[2]}`] = { building: p.kind, level: p.level };
  }
  return out;
}

// The rings a horde meets, outer to inner: those with walls built.
export function standingRings(plots: FortPlots): number[] {
  return [2, 1, 0].filter((ring) => levelOf(plots, `w${ring}`) > 0);
}
