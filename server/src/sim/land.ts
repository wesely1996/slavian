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
  // Steps (edge keys) along a river a finished boat sails (riverLanes).
  readonly lanes?: ReadonlySet<string>;
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

// The share of the terrain's move cost a step along a boat's river costs.
export function laneFactor(data: GameData): number {
  return 1 / data.events.kinds.shipyard.laneSpeed;
}

// The cheapest step players can take on this land: along the best road, or
// along a boat's river where there is one.
export function fastestStep(data: GameData, land: Land): number {
  return land.lanes?.size ? Math.min(fastestRoad(data), laneFactor(data)) : fastestRoad(data);
}

// The steps a boat built on `edge` sails: between any two neighbouring
// hexes on the banks of its river (every river edge joined to it through a
// shared bank hex).
export function riverLanes(rivers: readonly { a: Hex; b: Hex }[], edge: { a: Hex; b: Hex }): string[] {
  const byHex = new Map<string, number[]>();
  rivers.forEach((e, i) => {
    for (const end of [e.a, e.b]) byHex.set(hexKey(end), [...(byHex.get(hexKey(end)) ?? []), i]);
  });
  const start = rivers.findIndex((e) => edgeKey(e.a, e.b) === edgeKey(edge.a, edge.b));
  if (start < 0) return [];
  const seen = new Set([start]);
  const queue = [start];
  const banks = new Map<string, Hex>();
  while (queue.length) {
    const e = rivers[queue.shift()!]!;
    for (const end of [e.a, e.b]) {
      banks.set(hexKey(end), end);
      for (const next of byHex.get(hexKey(end)) ?? []) {
        if (!seen.has(next)) {
          seen.add(next);
          queue.push(next);
        }
      }
    }
  }
  const lanes = new Set<string>();
  for (const bank of banks.values()) {
    for (const n of neighbors(bank)) if (banks.has(hexKey(n))) lanes.add(edgeKey(bank, n));
  }
  return [...lanes].sort();
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
    if (!roads) return cost;
    const road = roadFactor(data, roadLevel(land, from, to));
    return cost * (land.lanes?.has(edgeKey(from, to)) ? Math.min(road, laneFactor(data)) : road);
  };
}

// Terrain plus blocked river edges and roads ([edge key, level]), as one Land.
export function landOf(
  terrain: ReadonlyMap<string, TerrainId>,
  blocked: Iterable<string>,
  roads: Iterable<readonly [string, number]> = [],
  lanes: Iterable<string> = [],
): Land {
  const land = new Map(terrain) as Map<string, TerrainId> & { blocked?: ReadonlySet<string>; roads?: ReadonlyMap<string, number>; lanes?: ReadonlySet<string> };
  land.blocked = new Set(blocked);
  land.roads = new Map(roads);
  land.lanes = new Set(lanes);
  return land;
}

// The two hexes that touch both a and b (the ends of their shared edge).
export function commonNeighbors(a: Hex, b: Hex): Hex[] {
  const around = new Set(neighbors(b).map(hexKey));
  return neighbors(a).filter((n) => around.has(hexKey(n)));
}

// What a road link to the village adds to an outpost's yield (0: none):
// over the fewest road steps from `from` to `to` (of those, the best
// built), the average of each step's level `outpostBonus`. `roads`: the
// level of each standing road, by edge key.
export function roadLink(data: GameData, roads: ReadonlyMap<string, number>, from: Hex, to: Hex): number {
  const levels = data.field.road.levels;
  const gain = (level: number) => levels[Math.min(level, levels.length) - 1]!.outpostBonus;
  const goal = hexKey(to);
  const best = new Map<string, { steps: number; sum: number }>([[hexKey(from), { steps: 0, sum: 0 }]]);
  let layer: Hex[] = [from];
  for (let steps = 1; layer.length && !(best.get(goal)); steps++) {
    const next: Hex[] = [];
    for (const cell of layer) {
      const here = best.get(hexKey(cell))!;
      for (const n of neighbors(cell)) {
        const level = roads.get(edgeKey(cell, n)) ?? 0;
        if (level <= 0) continue;
        const k = hexKey(n);
        const seen = best.get(k);
        const sum = here.sum + gain(level);
        if (!seen) {
          best.set(k, { steps, sum });
          next.push(n);
        } else if (seen.steps === steps && sum > seen.sum) {
          best.set(k, { steps, sum });
        }
      }
    }
    layer = next;
  }
  const link = best.get(goal);
  return link && link.steps > 0 ? link.sum / link.steps : 0;
}
