// The land armies, hordes and caravans move over: terrain by hex, and the
// river edges between two hexes that nothing can cross without a standing
// bridge (PLAN.md M5 step 3). A plain terrain map is land without rivers.
import type { GameData, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex, type StepCost } from './hex.js';
import { mapResources, type Resources } from './resources.js';

export interface Land extends ReadonlyMap<string, TerrainId> {
  // Edge keys (edgeKey) of rivers without a standing bridge.
  readonly blocked?: ReadonlySet<string>;
  // The level of each standing road, by edge key.
  readonly roads?: ReadonlyMap<string, number>;
  // The roads a fire damaged, by edge key.
  readonly damaged?: ReadonlySet<string>;
  // Steps (edge keys) along a river a finished boat sails (riverLanes).
  readonly lanes?: ReadonlySet<string>;
  // Hexes (hexKey) on fire: nothing enters them until the fire is out.
  readonly burning?: ReadonlySet<string>;
  // Forts (hexKey) an army holds: hordes keep out of their zone of control
  // (field.json fort.zoneDetour).
  readonly forts?: ReadonlySet<string>;
  // Blessed by the water god (events.json blessings.water): steps between
  // two hexes on a river's banks (`banks`), and a boat's, go the faster.
  readonly blessed?: boolean;
  readonly banks?: ReadonlySet<string>;
  // Walls standing along edges (data/field.json edgeWalls), by edge key:
  // nobody crosses a wall, the players' own pass a gatehouse (`gate`);
  // hordes tear them down (sim/edgeWalls.ts).
  // (A river edge may hold one on each bank.)
  readonly walls?: ReadonlyMap<string, readonly LandWall[]>;
}

// A wall along an edge as the land sees it: a gatehouse (`gate`) lets the
// players' own through, unless it is the enemy's (`enemy`: no owner).
export interface LandWall {
  readonly gate: boolean;
  readonly tier: number;
  readonly enemy?: boolean;
}

// One key for the edge between two neighbouring hexes, whichever way round.
export function edgeKey(a: Hex, b: Hex): string {
  const ka = hexKey(a);
  const kb = hexKey(b);
  return ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`;
}

export function canCross(land: Land, from: Hex, to: Hex): boolean {
  const walls = land.walls?.get(edgeKey(from, to));
  return !land.blocked?.has(edgeKey(from, to)) && !land.burning?.has(hexKey(to)) && (!walls || walls.every((w) => w.gate && !w.enemy));
}

// Whether a horde can cross from `from` to `to` (a wall it tears down:
// routeFrom counts what that takes).
export function hordeCanCross(land: Land, from: Hex, to: Hex): boolean {
  return !land.blocked?.has(edgeKey(from, to)) && !land.burning?.has(hexKey(to));
}

// The land with these walls standing along its edges.
export function withWalls(land: Land, walls: ReadonlyMap<string, readonly LandWall[]>): Land {
  return walls.size === 0 ? land : Object.assign(land, { walls });
}

// The level of the road between two hexes (0: none).
export function roadLevel(land: Land, from: Hex, to: Hex): number {
  return land.roads?.get(edgeKey(from, to)) ?? 0;
}

// The share of the terrain's move cost a road of `level` costs (1: none);
// a damaged one saves only damage.effect of what it would.
export function roadFactor(data: GameData, level: number, damaged = false): number {
  const levels = data.field.road.levels;
  if (level <= 0) return 1;
  const factor = levels[Math.min(level, levels.length) - 1]!.factor;
  return damaged ? 1 - (1 - factor) * data.field.road.damage.effect : factor;
}

// What repairing a damaged road of `level` costs and how long it takes
// (game seconds): damage.repairShare of building that level.
export function roadRepairCost(data: GameData, level: number, pass: boolean): { cost: Resources; buildSeconds: number } {
  const build = roadLevelCost(data, level, pass);
  const share = data.field.road.damage.repairShare;
  return { cost: mapResources((kind) => Math.round(build.cost[kind] * share)), buildSeconds: build.buildSeconds * share };
}

// What building a road to `level` costs and how long it takes (game
// seconds): a mountain pass (`pass`) mountainFactor times both.
export function roadLevelCost(data: GameData, level: number, pass: boolean): { cost: Resources; buildSeconds: number } {
  const rules = data.field.road;
  const def = rules.levels[level - 1]!;
  const k = pass ? rules.mountainFactor : 1;
  return { cost: mapResources((kind) => def.cost[kind] * k), buildSeconds: def.buildSeconds * k };
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

// How many times as fast river travel is on this land (the water god's blessing).
export function riverSpeed(data: GameData, land: Land): number {
  return land.blessed ? data.events.blessings.water.speed : 1;
}

// The share of the terrain's move cost a step from `from` to `to` costs
// beside the water: along a boat's river, or (blessed) between two hexes on
// a river's banks; 1 off the water.
function waterFactor(data: GameData, land: Land, edge: string): number {
  const speed = riverSpeed(data, land);
  const lane = land.lanes?.has(edge) ? laneFactor(data) / speed : 1;
  const bank = land.banks?.has(edge) ? 1 / speed : 1;
  return Math.min(lane, bank);
}

// The cheapest step players can take on this land: along the best road, or
// along a boat's river (or a blessed river's banks) where there is one.
export function fastestStep(data: GameData, land: Land): number {
  const speed = riverSpeed(data, land);
  let best = fastestRoad(data);
  if (land.lanes?.size) best = Math.min(best, laneFactor(data) / speed);
  if (land.banks?.size) best = Math.min(best, 1 / speed);
  return best;
}

// Every step between two neighbouring hexes on the banks of the same river
// (riverLanes, river by river, lakes aside).
export function riverBanks(rivers: readonly { a: Hex; b: Hex }[]): string[] {
  const banks = new Set<string>();
  const done = new Set<string>();
  for (const e of rivers) {
    if (done.has(edgeKey(e.a, e.b))) continue;
    for (const lane of riverLanes(rivers, e)) banks.add(lane);
    // The river edges whose banks are already in.
    const water = riverWater(rivers, e);
    for (const r of rivers) if (water.has(hexKey(r.a)) && water.has(hexKey(r.b))) done.add(edgeKey(r.a, r.b));
  }
  return [...banks].sort();
}

// How many of `villages` (cells) the roads (edge keys) join to `from`.
export function roadConnected(roads: Iterable<string>, from: Hex, villages: readonly Hex[]): number {
  const next = new Map<string, string[]>();
  for (const edge of roads) {
    const [a, b] = edge.split('|') as [string, string];
    next.set(a, [...(next.get(a) ?? []), b]);
    next.set(b, [...(next.get(b) ?? []), a]);
  }
  const reached = new Set([hexKey(from)]);
  const queue = [hexKey(from)];
  while (queue.length) {
    for (const n of next.get(queue.shift()!) ?? []) {
      if (!reached.has(n)) {
        reached.add(n);
        queue.push(n);
      }
    }
  }
  return villages.filter((v) => hexKey(v) !== hexKey(from) && reached.has(hexKey(v))).length;
}

// The land blessed by the water god, with its rivers' `banks`.
export function blessLand(land: Land, banks: Iterable<string>): Land {
  return Object.assign(land, { blessed: true, banks: new Set(banks) });
}

// The steps a boat built on `edge` sails: between any two neighbouring
// hexes on the banks of its river (every river edge joined to it through a
// shared bank hex) and, with `terrain`, across every lake it reaches: the
// lake's hexes, its shores, and the rivers that flow into it join, and so on.
export function riverLanes(rivers: readonly { a: Hex; b: Hex }[], edge: { a: Hex; b: Hex }, terrain?: ReadonlyMap<string, TerrainId>): string[] {
  const water = riverWater(rivers, edge, terrain);
  const lanes = new Set<string>();
  for (const cell of water.values()) {
    for (const n of neighbors(cell)) if (water.has(hexKey(n))) lanes.add(edgeKey(cell, n));
  }
  return [...lanes].sort();
}

// The hexes on the water of `edge`'s river (riverLanes): its banks, and the
// lakes it reaches with their shores and rivers. One shipyard to a river.
export function riverWater(rivers: readonly { a: Hex; b: Hex }[], edge: { a: Hex; b: Hex }, terrain?: ReadonlyMap<string, TerrainId>): Map<string, Hex> {
  const byHex = new Map<string, number[]>();
  rivers.forEach((e, i) => {
    for (const end of [e.a, e.b]) byHex.set(hexKey(end), [...(byHex.get(hexKey(end)) ?? []), i]);
  });
  const start = rivers.findIndex((e) => edgeKey(e.a, e.b) === edgeKey(edge.a, edge.b));
  if (start < 0) return new Map();
  const seen = new Set([start]);
  const queue = [start];
  // Bank and shore hexes, and lake hexes: all on the water.
  const water = new Map<string, Hex>();
  const lakes = new Set<string>();
  const isLake = (cell: Hex) => terrain?.get(hexKey(cell)) === 'lake';
  // A hex on the water: the rivers along it join, and a lake beside it is
  // sailed whole, its shores with it.
  const reach = (cell: Hex) => {
    const k = hexKey(cell);
    if (water.has(k)) return;
    water.set(k, cell);
    if (isLake(cell)) lakes.add(k);
    for (const next of byHex.get(k) ?? []) {
      if (!seen.has(next)) {
        seen.add(next);
        queue.push(next);
      }
    }
    for (const n of neighbors(cell)) {
      if (isLake(cell) ? terrain!.has(hexKey(n)) : isLake(n)) reach(n);
    }
  };
  while (queue.length) {
    const e = rivers[queue.shift()!]!;
    for (const end of [e.a, e.b]) reach(end);
  }
  return water;
}

// The terrain's move cost of entering `to`, or null when it is impassable
// or a river lies between; along a road it is cheaper, unless `roads` is
// false (the Monsters of the North keep off them).
// `relief`: the share of harsh terrain's slowness (move cost above 1) that
// pathfinders marching along take off (units.json pathfinding).
export function moveCostOn(data: GameData, land: Land, roads = true, relief = 0): StepCost {
  return (from, to) => {
    const type = land.get(hexKey(to));
    if (type === undefined || !canCross(land, from, to)) return null;
    // A lake is crossed only by boat.
    const sailed = roads && type === 'lake' && !!land.lanes?.has(edgeKey(from, to));
    const level = roadLevel(land, from, to);
    // A mountain pass: impassable land entered only along a standing road.
    const pass = roads && level > 0 ? (data.terrain.terrain[type].roadMoveCost ?? null) : null;
    const base = sailed ? data.events.kinds.shipyard.lakeMoveCost : (data.terrain.terrain[type].moveCost ?? pass);
    if (base === null) return null;
    const cost = !sailed && relief > 0 && base > 1 ? 1 + (base - 1) * (1 - relief) : base;
    if (!roads) return cost;
    const road = roadFactor(data, level, !!land.damaged?.has(edgeKey(from, to)));
    return cost * Math.min(road, waterFactor(data, land, edgeKey(from, to)));
  };
}

// Terrain plus blocked river edges and roads ([edge key, level]), as one Land.
export function landOf(
  terrain: ReadonlyMap<string, TerrainId>,
  blocked: Iterable<string>,
  roads: Iterable<readonly [string, number]> = [],
  lanes: Iterable<string> = [],
  burning: Iterable<string> = [],
  damaged: Iterable<string> = [],
  forts: Iterable<string> = [],
): Land {
  const land = new Map(terrain) as Map<string, TerrainId> & {
    blocked?: ReadonlySet<string>;
    roads?: ReadonlyMap<string, number>;
    lanes?: ReadonlySet<string>;
    burning?: ReadonlySet<string>;
    damaged?: ReadonlySet<string>;
    forts?: ReadonlySet<string>;
  };
  land.blocked = new Set(blocked);
  land.roads = new Map(roads);
  land.lanes = new Set(lanes);
  land.burning = new Set(burning);
  land.damaged = new Set(damaged);
  land.forts = new Set(forts);
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
// level of each standing road, by edge key; a damaged one (`damaged`) adds
// only damage.effect of its bonus, and a mountain pass (a step into land
// only a road crosses, by `terrain`) passOutpostFactor times it.
export function roadLink(
  data: GameData,
  roads: ReadonlyMap<string, number>,
  from: Hex,
  to: Hex,
  damaged: ReadonlySet<string> = new Set(),
  terrain: ReadonlyMap<string, TerrainId> = new Map(),
): number {
  const levels = data.field.road.levels;
  const effect = data.field.road.damage.effect;
  const pass = (cell: Hex) => {
    const def = data.terrain.terrain[terrain.get(hexKey(cell)) as TerrainId];
    return def !== undefined && def.moveCost === null && (def.roadMoveCost ?? null) !== null;
  };
  const gain = (level: number, a: Hex, b: Hex) =>
    levels[Math.min(level, levels.length) - 1]!.outpostBonus *
    (damaged.has(edgeKey(a, b)) ? effect : 1) *
    (pass(a) || pass(b) ? data.field.road.passOutpostFactor : 1);
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
        const sum = here.sum + gain(level, cell, n);
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

// Whether the edges a|b and c|d meet at a corner: they share one hex, and
// their other two hexes are neighbours (a river can run on from one to the
// other).
export function edgesMeet(a: Hex, b: Hex, c: Hex, d: Hex): boolean {
  const k = [hexKey(a), hexKey(b)];
  const l = [hexKey(c), hexKey(d)];
  const shared = k.filter((x) => l.includes(x));
  if (shared.length !== 1) return false;
  const p = [a, b].find((h) => hexKey(h) !== shared[0])!;
  const q = [c, d].find((h) => hexKey(h) !== shared[0])!;
  return neighbors(p).some((n) => hexKey(n) === hexKey(q));
}

// The settlements of `cells` a march from the Holy City can reach over
// `land` (by their hexKey).
export function reachable(data: GameData, land: Land, cells: readonly Hex[]): Set<string> {
  const step = moveCostOn(data, land);
  const wanted = new Set(cells.map(hexKey));
  const seen = new Set([hexKey({ q: 0, r: 0 })]);
  const queue: Hex[] = [{ q: 0, r: 0 }];
  const out = new Set<string>();
  while (queue.length > 0) {
    const at = queue.shift()!;
    if (wanted.has(hexKey(at))) out.add(hexKey(at));
    for (const n of neighbors(at)) {
      const key = hexKey(n);
      if (seen.has(key) || step(at, n) === null) continue;
      seen.add(key);
      queue.push(n);
    }
  }
  return out;
}
