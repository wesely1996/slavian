// The land armies, hordes and caravans move over: terrain by hex, and the
// river edges between two hexes that nothing can cross without a standing
// bridge (PLAN.md M5 step 3). A plain terrain map is land without rivers.
import type { GameData, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex, type StepCost } from './hex.js';

export interface Land extends ReadonlyMap<string, TerrainId> {
  // Edge keys (edgeKey) of rivers without a standing bridge.
  readonly blocked?: ReadonlySet<string>;
  // Edge keys of standing roads.
  readonly roads?: ReadonlySet<string>;
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

export function onRoad(land: Land, from: Hex, to: Hex): boolean {
  return land.roads?.has(edgeKey(from, to)) ?? false;
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
    return roads && onRoad(land, from, to) ? cost * data.field.road.factor : cost;
  };
}

// Terrain plus blocked river edges and roads, as one Land.
export function landOf(terrain: ReadonlyMap<string, TerrainId>, blocked: Iterable<string>, roads: Iterable<string> = []): Land {
  const land = new Map(terrain) as Map<string, TerrainId> & { blocked?: ReadonlySet<string>; roads?: ReadonlySet<string> };
  land.blocked = new Set(blocked);
  land.roads = new Set(roads);
  return land;
}

// The two hexes that touch both a and b (the ends of their shared edge).
export function commonNeighbors(a: Hex, b: Hex): Hex[] {
  const around = new Set(neighbors(b).map(hexKey));
  return neighbors(a).filter((n) => around.has(hexKey(n)));
}
