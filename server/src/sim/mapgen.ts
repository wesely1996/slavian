// World map generation (PLAN.md §4). Deterministic for a seed and player
// count. The server generates and stores the map; clients only render it.
import { createNoise2D, type NoiseFunction2D } from 'simplex-noise';
import type { GameData, TerrainId } from '../data/index.js';
import { findPath, hex, hexDistance, hexKey, hexToPixel, ring, spiral, type Hex } from './hex.js';
import { createRng } from './rng.js';

export const FRONTS = ['north', 'east', 'south', 'west'] as const;
export type Front = (typeof FRONTS)[number];

export const START_RING = 2;
const EDGE_BELT_WIDTH = 2;
const MAX_ATTEMPTS = 20;

export interface WorldMap {
  readonly seed: number;
  readonly radius: number;
  readonly activeFronts: readonly Front[];
  readonly terrain: ReadonlyMap<string, TerrainId>;
  readonly startSites: readonly Hex[];
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
    const map = generateCandidate(seed + attempt * 7919, playerCount);
    if (isPlayable(data, map)) return map;
  }
  throw new Error(`No playable map found for seed ${seed}`);
}

function generateCandidate(seed: number, playerCount: number): WorldMap {
  const rng = createRng(seed);
  const elevation = fbm(createNoise2D(rng), 0.09);
  const moisture = fbm(createNoise2D(rng), 0.07);
  const radius = radiusFor(playerCount);
  const activeFronts = activeFrontsFor(playerCount);
  const center = hex(0, 0);
  const terrain = new Map<string, TerrainId>();

  for (const cell of spiral(center, radius)) {
    const dist = hexDistance(cell, center);
    const p = hexToPixel(cell, 1);
    const e = elevation(p.x, p.y);
    const m = moisture(p.x, p.y);
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
  return { seed, radius, activeFronts, terrain, startSites };
}

// Every active front must be able to reach every start site and the Holy
// City, otherwise its waves would have nowhere to go.
function isPlayable(data: GameData, map: WorldMap): boolean {
  const cost = (_: Hex, to: Hex): number | null => {
    const type = map.terrain.get(hexKey(to));
    return type === undefined ? null : data.terrain.terrain[type].moveCost;
  };
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
