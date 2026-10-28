// The land armies, hordes and caravans move over: terrain by hex, and the
// river edges between two hexes that nothing can cross without a standing
// bridge (PLAN.md M5 step 3). A plain terrain map is land without rivers.
import type { GameData, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex, type StepCost } from './hex.js';

export interface Land extends ReadonlyMap<string, TerrainId> {
  // Edge keys (edgeKey) of rivers without a standing bridge.
  readonly blocked?: ReadonlySet<string>;
  // The level of each standing road, by edge key.
  readonly roads?: ReadonlyMap<string, number>;
}

// One key for the edge between two neighbouring hexes, whichever way round.
export function edgeKey(a: Hex, b: Hex): string {
  const ka = hexKey(a);
  const kb = hexKey(b);
  return ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`;
}

export function canCross(land: Land, from: Hex, to: Hex): boolean {
  return !land.blocked?.has(edgeKey(from, to));
}

// The level of the road between two hexes (0: none).
export function roadLevel(land: Land, from: Hex, to: Hex): number {
  return land.roads?.get(edgeKey(from, to)) ?? 0;
}

// The share of the terrain's move cost a road of `level` costs (1: none).
export function roadFactor(data: GameData, level: number): number {
  const levels = data.field.road.levels;
  return level <= 0 ? 1 : levels[Math.min(level, levels.length) - 1]!.factor;
}

// The cheapest a step can be: along the best road there is (the path
// search's lower bound).
export function fastestRoad(data: GameData): number {
  return Math.min(...data.field.road.levels.map((l) => l.factor));
}

// The terrain's move cost of entering `to`, or null when it is impassable
// or a river lies between; along a road it is cheaper, unless `roads` is
// false (the Monsters of the North keep off them).
export function moveCostOn(data: GameData, land: Land, roads = true): StepCost {
  return (from, to) => {
    const type = land.get(hexKey(to));
    if (type === undefined || !canCross(land, from, to)) return null;
    const cost = data.terrain.terrain[type].moveCost;
    if (cost === null) return null;
    return roads ? cost * roadFactor(data, roadLevel(land, from, to)) : cost;
  };
}

// Terrain plus blocked river edges and roads ([edge key, level]), as one Land.
export function landOf(terrain: ReadonlyMap<string, TerrainId>, blocked: Iterable<string>, roads: Iterable<readonly [string, number]> = []): Land {
  const land = new Map(terrain) as Map<string, TerrainId> & { blocked?: ReadonlySet<string>; roads?: ReadonlyMap<string, number> };
  land.blocked = new Set(blocked);
  land.roads = new Map(roads);
  return land;
}

// The two hexes that touch both a and b (the ends of their shared edge).
export function commonNeighbors(a: Hex, b: Hex): Hex[] {
  const around = new Set(neighbors(b).map(hexKey));
  return neighbors(a).filter((n) => around.has(hexKey(n)));
}
