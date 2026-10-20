// World map generation (PLAN.md §4). Deterministic for a seed and player
// count. The server generates and stores the map; clients only render it.
import { createNoise2D, type NoiseFunction2D } from 'simplex-noise';
import type { GameData, TerrainId } from '../data/index.js';
import { findPath, hex, hexDistance, hexKey, hexToPixel, neighbors, ring, spiral, type Hex } from './hex.js';
import { commonNeighbors, edgeKey, landOf, moveCostOn, type Land } from './land.js';
import { createRng } from './rng.js';

export const FRONTS = ['north', 'east', 'south', 'west'] as const;
export type Front = (typeof FRONTS)[number];

export const START_RING = 2;
const EDGE_BELT_WIDTH = 2;
const MAX_ATTEMPTS = 20;
// How much lower a river reckons a step towards an older river (it joins it).
const JOIN_PULL = 0.25;

export interface WorldMap {
  readonly seed: number;
  readonly radius: number;
  readonly activeFronts: readonly Front[];
  readonly terrain: ReadonlyMap<string, TerrainId>;
  readonly startSites: readonly Hex[];
  // River edges between two hexes; only those with a bridge can be crossed.
  readonly rivers: readonly RiverEdge[];
}

export interface RiverEdge {
  readonly a: Hex;
  readonly b: Hex;
  readonly bridge: boolean;
  // 1 for a river from its source; each river that joins above adds 1.
  readonly size: number;
}

// Terrain a river flows into and never runs along.
export const WATER: readonly string[] = ['lake', 'ocean'];

// The land of a map: its terrain, and the river edges without a bridge.
export function landOfMap(map: Pick<WorldMap, 'terrain' | 'rivers'>): Land {
  return landOf(map.terrain, map.rivers.filter((e) => !e.bridge).map((e) => edgeKey(e.a, e.b)));
}

// PLAN.md §4.1: ~10 for 1-2 players, scaling up to ~16 for 6.
export function radiusFor(playerCount: number): number {
  return playerCount <= 2 ? 10 : Math.round(10 + (playerCount - 2) * 1.5);
}

// PLAN.md §4.4: solo faces North + South, 2 players add East, 3+ all four.
export function activeFrontsFor(playerCount: number): Front[] {
  if (playerCount <= 1) return ['north', 'south'];
  if (playerCount === 2) return ['north', 'south', 'east'];
  return ['north', 'east', 'south', 'west'];
}

// Which front a hex faces, by its angle from the centre (y grows downward).
export function frontOf(cell: Hex): Front {
  const p = hexToPixel(cell, 1);
  const angle = (Math.atan2(p.y, p.x) * 180) / Math.PI;
  if (angle >= -135 && angle < -45) return 'north';
  if (angle >= -45 && angle < 45) return 'east';
  if (angle >= 45 && angle < 135) return 'south';
  return 'west';
}

export function generateMap(data: GameData, seed: number, playerCount: number): WorldMap {
  // A seed occasionally produces a map where a front cannot reach a start
  // (e.g. walled off by mountains); derive a new seed and try again.
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const { map, elevation } = generateCandidate(seed + attempt * 7919, playerCount);
    const rivers = bridgeRoads(data, map, layRivers(map, elevation, createRng((seed + attempt * 7919) ^ 0x51a5)));
    const withRivers = { ...map, rivers };
    if (isPlayable(data, withRivers)) return withRivers;
  }
  throw new Error(`No playable map found for seed ${seed}`);
}

function generateCandidate(seed: number, playerCount: number): { map: WorldMap; elevation: Map<string, number> } {
  const rng = createRng(seed);
  const elevation = fbm(createNoise2D(rng), 0.09);
  const moisture = fbm(createNoise2D(rng), 0.07);
  const radius = radiusFor(playerCount);
  const activeFronts = activeFrontsFor(playerCount);
  const center = hex(0, 0);
  const terrain = new Map<string, TerrainId>();
  const heights = new Map<string, number>();

  for (const cell of spiral(center, radius)) {
    const dist = hexDistance(cell, center);
    const p = hexToPixel(cell, 1);
    const e = elevation(p.x, p.y);
    const m = moisture(p.x, p.y);
    heights.set(hexKey(cell), e);
    let type: TerrainId;
    if (dist === 0) {
      type = 'holy_city';
    } else if (dist > radius - EDGE_BELT_WIDTH) {
      type = edgeTerrain(frontOf(cell), activeFronts, dist === radius, m);
    } else {
      type = interiorTerrain(e, m);
      if (dist <= START_RING && !['plains', 'forest', 'hills'].includes(type)) type = 'plains';
    }
    terrain.set(hexKey(cell), type);
  }

  // Spread players evenly around the starting ring.
  const startRing = ring(center, START_RING);
  const startSites = Array.from(
    { length: playerCount },
    (_, i) => startRing[Math.round((i * startRing.length) / playerCount) % startRing.length]!,
  );
  return { map: { seed, radius, activeFronts, terrain, startSites, rivers: [] }, elevation: heights };
}

// Rivers run along hex edges, from the hills and mountains downhill (by the
// elevation of the two hexes on either side). Each ends where water takes it:
// at a lake or the ocean, off the edge of the map, or in an older river it
// joins, which runs on wider below the meeting point. A river never runs
// along a lake's or the ocean's shore, so no bridge leads onto water.
function layRivers(map: WorldMap, elevation: ReadonlyMap<string, number>, rng: () => number): RiverEdge[] {
  const interior = (h: Hex) => hexDistance(h, hex(0, 0)) <= map.radius - EDGE_BELT_WIDTH;
  const type = (h: Hex) => map.terrain.get(hexKey(h));
  const water = (h: Hex) => WATER.includes(type(h) ?? '');
  const onMap = (h: Hex) => map.terrain.has(hexKey(h));
  // An edge a river may run along: land on both banks, off the Holy City.
  const bank = (h: Hex) => onMap(h) && !water(h) && type(h) !== 'holy_city';
  const height = (a: Hex, b: Hex) => ((elevation.get(hexKey(a)) ?? 0) + (elevation.get(hexKey(b)) ?? 0)) / 2;
  const corner = (...hs: Hex[]) => hs.map(hexKey).sort().join('/');
  // Every edge laid so far: the corner it flows into, the edge below it (none
  // at a mouth) and its size (1 for a stream, +1 for each river above it).
  const laid = new Map<string, { a: Hex; b: Hex; into: string; down: string | null; size: number }>();
  const sources: [Hex, Hex][] = [];
  for (const cell of spiral(hex(0, 0), map.radius - EDGE_BELT_WIDTH)) {
    if (!['hills', 'mountain'].includes(type(cell) ?? '')) continue;
    for (const n of neighbors(cell)) {
      if (hexKey(cell) < hexKey(n) && interior(n) && bank(cell) && bank(n)) sources.push([cell, n]);
    }
  }
  const order: string[] = [];
  const wanted = 2 + Math.floor(map.radius / 6);
  for (let tries = 0; tries < 60 && order.length < wanted * 8 && sources.length; tries++) {
    const [a0, b0] = sources.splice(Math.floor(rng() * sources.length), 1)[0]!;
    if (laid.has(edgeKey(a0, b0))) continue;
    // Walk from the lower of the edge's two ends.
    const ends0 = commonNeighbors(a0, b0);
    let [a, b] = [a0, b0];
    let ahead = (elevation.get(hexKey(ends0[0]!)) ?? 0) <= (elevation.get(hexKey(ends0[1]!)) ?? 0) ? ends0[0]! : ends0[1]!;
    const river: { a: Hex; b: Hex; into: string }[] = [{ a, b, into: corner(a, b, ahead) }];
    const seen = new Set([edgeKey(a, b)]);
    let mouth: 'water' | 'join' | null = null;
    let joins: string | null = null;
    for (let step = 0; step < map.radius * 4; step++) {
      // The corner ahead lies at water or off the map: the river flows out.
      if (!onMap(ahead) || water(ahead)) {
        mouth = 'water';
        break;
      }
      // An older river leaves this corner: join it.
      const here = corner(a, b, ahead);
      const leaving = [edgeKey(a, ahead), edgeKey(b, ahead)].find((k) => laid.has(k) && laid.get(k)!.into !== here);
      if (leaving) {
        mouth = 'join';
        joins = leaving;
        break;
      }
      // Go on along a-ahead or b-ahead, whichever runs lower; water draws
      // water, so a corner where an older river runs counts as lower still.
      const options = [[a, ahead], [b, ahead]] as [Hex, Hex][];
      const nearRiver = ([p, q]: [Hex, Hex]) =>
        commonNeighbors(p, q).some((h) => laid.has(edgeKey(p, h)) || laid.has(edgeKey(q, h))) ? JOIN_PULL : 0;
      const lowness = (x: [Hex, Hex]) => height(x[0], x[1]) - nearRiver(x);
      options.sort((x, y) => lowness(x) - lowness(y) + (rng() - 0.5) * 0.08);
      let moved = false;
      for (const [p, q] of options) {
        const key = edgeKey(p, q);
        if (seen.has(key) || laid.has(key) || !bank(p) || !bank(q)) continue;
        const other = p === a ? b : a;
        const next = commonNeighbors(p, q).find((h) => hexKey(h) !== hexKey(other));
        if (!next) continue;
        [a, b, ahead] = [p, q, next];
        river.push({ a, b, into: corner(a, b, ahead) });
        seen.add(key);
        moved = true;
        break;
      }
      if (!moved) break;
    }
    if (!mouth || river.length < 3) continue;
    for (const [i, e] of river.entries()) {
      const key = edgeKey(e.a, e.b);
      const below = river[i + 1];
      laid.set(key, { ...e, down: below ? edgeKey(below.a, below.b) : joins, size: 1 });
      order.push(key);
    }
    // Everything below the meeting point carries this river's water too.
    for (let k = joins; k; k = laid.get(k)!.down) laid.get(k)!.size += 1;
  }
  return order.map((key, i) => {
    const e = laid.get(key)!;
    // A bridge every few edges, so a river is never one long wall.
    return { a: e.a, b: e.b, bridge: (i + 2) % 5 === 0, size: e.size };
  });
}

// Every active front's road to each start and to the Holy City, and each
// start's road to the Holy City, gets a bridge wherever it crosses a river.
function bridgeRoads(data: GameData, map: WorldMap, rivers: RiverEdge[]): RiverEdge[] {
  const byEdge = new Map(rivers.map((e) => [edgeKey(e.a, e.b), e]));
  const terrainCost = moveCostOn(data, map.terrain);
  // Crossing an unbridged river costs extra, so roads look for a bridge first.
  const cost = (from: Hex, to: Hex): number | null => {
    const base = terrainCost(from, to);
    if (base === null) return null;
    const edge = byEdge.get(edgeKey(from, to));
    return edge && !edge.bridge ? base + 6 : base;
  };
  const roads: [Hex, Hex][] = map.startSites.map((s) => [s, hex(0, 0)]);
  for (const front of map.activeFronts) {
    const spawn = ring(hex(0, 0), map.radius).find((cell) => frontOf(cell) === front && terrainCost(cell, cell) !== null);
    if (!spawn) continue;
    for (const target of [hex(0, 0), ...map.startSites]) roads.push([spawn, target]);
  }
  for (const [from, to] of roads) {
    const path = findPath(from, to, cost);
    for (let i = 1; path && i < path.length; i++) {
      const key = edgeKey(path[i - 1]!, path[i]!);
      const edge = byEdge.get(key);
      if (edge && !edge.bridge) byEdge.set(key, { ...edge, bridge: true });
    }
  }
  return [...byEdge.values()];
}

// Every active front must be able to reach every start site and the Holy
// City, otherwise its waves would have nowhere to go.
function isPlayable(data: GameData, map: WorldMap): boolean {
  const cost = moveCostOn(data, landOfMap(map));
  const targets = [hex(0, 0), ...map.startSites];
  for (const front of map.activeFronts) {
    const spawn = ring(hex(0, 0), map.radius).find((cell) => frontOf(cell) === front && cost(cell, cell) !== null);
    if (!spawn) return false;
    for (const target of targets) {
      if (!findPath(spawn, target, cost)) return false;
    }
  }
  return true;
}

// Fractal noise in roughly [-1, 1].
function fbm(noise: NoiseFunction2D, frequency: number, octaves = 4): (x: number, y: number) => number {
  return (x, y) => {
    let sum = 0;
    let amplitude = 1;
    let norm = 0;
    let f = frequency;
    for (let i = 0; i < octaves; i++) {
      sum += noise(x * f, y * f) * amplitude;
      norm += amplitude;
      amplitude *= 0.5;
      f *= 2;
    }
    return sum / norm;
  };
}

function interiorTerrain(e: number, m: number): TerrainId {
  if (e > 0.38) return 'mountain';
  if (e > 0.2) return 'hills';
  if (e < -0.4 && m > 0) return 'lake';
  if (e < -0.15 && m > 0.3) return 'swamp';
  if (m > 0.05) return 'forest';
  return 'plains';
}

function edgeTerrain(front: Front, active: readonly Front[], outermost: boolean, m: number): TerrainId {
  if (!active.includes(front)) return 'ocean';
  switch (front) {
    case 'north':
      return outermost && m < 0.1 ? 'ice' : 'dark_forest';
    case 'east':
      return 'steppe';
    default:
      return 'hallowed';
  }
}
