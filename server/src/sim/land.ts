// The land armies, hordes and caravans move over: terrain by hex, and the
// river edges between two hexes that nothing can cross without a standing
// bridge (PLAN.md M5 step 3). A plain terrain map is land without rivers.
import type { GameData, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex, type StepCost } from './hex.js';

export interface Land extends ReadonlyMap<string, TerrainId> {
  // Edge keys (edgeKey) of rivers without a standing bridge.
  readonly blocked?: ReadonlySet<string>;
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

// The terrain's move cost of entering `to`, or null when it is impassable
// or a river lies between.
export function moveCostOn(data: GameData, land: Land): StepCost {
  return (from, to) => {
    const type = land.get(hexKey(to));
    if (type === undefined || !canCross(land, from, to)) return null;
    return data.terrain.terrain[type].moveCost;
  };
}

// Terrain plus blocked river edges, as one Land.
export function landOf(terrain: ReadonlyMap<string, TerrainId>, blocked: Iterable<string>): Land {
  const land = new Map(terrain) as Map<string, TerrainId> & { blocked?: ReadonlySet<string> };
  land.blocked = new Set(blocked);
  return land;
}

// The two hexes that touch both a and b (the ends of their shared edge).
export function commonNeighbors(a: Hex, b: Hex): Hex[] {
  const around = new Set(neighbors(b).map(hexKey));
  return neighbors(a).filter((n) => around.has(hexKey(n)));
}
