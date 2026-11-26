// The enemy lands beyond the map's edge (docs/enemy-lands.md, data/enemy-lands.json):
// rings past the heartland's radius on the sides of the active fronts, four
// bands deep, each front with its own terrain. They are not stored: the
// world's seed, radius and fronts make them, the same each time, so worlds
// started before them get them too. Hordes keep to the heartland; armies may
// walk in.
import { createNoise2D } from 'simplex-noise';
import type { GameData, TerrainId } from '../data/index.js';
import { hex, hexDistance, hexKey, hexToPixel, neighbors, ring, type Hex } from './hex.js';
import { fbm, frontOf, type Front } from './mapgen.js';
import { createRng } from './rng.js';

export interface EnemyHex {
  readonly cell: Hex;
  readonly terrain: TerrainId;
  readonly front: Front;
  // 1 (the march) to the deepest band.
  readonly band: number;
}

// Rings the enemy lands reach past the edge.
export function enemyRings(data: GameData): number {
  return data.enemyLands.bands.reduce((sum, b) => sum + b.rings, 0);
}

// Which band a hex lies in: 0 inside the map's radius, 1.. beyond it, null
// past the last band.
export function bandOf(data: GameData, cell: Hex, radius: number): number | null {
  let past = hexDistance(cell, hex(0, 0)) - radius;
  if (past <= 0) return 0;
  for (let i = 0; i < data.enemyLands.bands.length; i++) {
    past -= data.enemyLands.bands[i]!.rings;
    if (past <= 0) return i + 1;
  }
  return null;
}

const cache = new Map<string, readonly EnemyHex[]>();

// The enemy lands of a world, ring by ring outward (each ring in ring() order).
export function enemyLands(data: GameData, seed: number, radius: number, activeFronts: readonly Front[]): readonly EnemyHex[] {
  const key = `${seed}:${radius}:${activeFronts.join(',')}`;
  const known = cache.get(key);
  if (known) return known;
  const rng = createRng((seed ^ 0x3e7a11d5) >>> 0);
  const noise = fbm(createNoise2D(rng), 0.08);
  const out: EnemyHex[] = [];
  const active = (cell: Hex): boolean => activeFronts.includes(frontOf(cell));
  const depth = enemyRings(data);
  for (let d = radius + 1; d <= radius + depth; d++) {
    for (const cell of ring(hex(0, 0), d)) {
      const front = frontOf(cell);
      if (!activeFronts.includes(front)) continue;
      const band = bandOf(data, cell, radius)!;
      // Where another active front's lands touch, the seam.
      const seam = neighbors(cell).some((n) => hexDistance(n, hex(0, 0)) > radius && active(n) && frontOf(n) !== front);
      let terrain: TerrainId = data.enemyLands.seam;
      if (!seam) {
        const lands = data.enemyLands.fronts[front]!;
        const p = hexToPixel(cell, 1);
        const v = noise(p.x, p.y) + lands.shift * (band - 1);
        terrain = (lands.palette.find((e) => v < e.upTo) ?? lands.palette[lands.palette.length - 1]!).terrain;
      }
      out.push({ cell, terrain, front, band });
    }
  }
  if (cache.size > 64) cache.clear();
  cache.set(key, out);
  return out;
}

// A world's terrain with its enemy lands added (what armies walk on).
export function withEnemyLands<T extends ReadonlyMap<string, TerrainId>>(data: GameData, land: T, world: { seed: number; radius: number | null; activeFronts: readonly string[] }): T {
  if (world.radius === null) return land;
  const out = land as unknown as Map<string, TerrainId>;
  for (const e of enemyLands(data, world.seed, world.radius, world.activeFronts as Front[])) out.set(hexKey(e.cell), e.terrain);
  return land;
}

// How many bands of a front's lands the players see (deeper ones lie in fog).
export function sightOf(data: GameData, world: { enemySight?: Partial<Record<string, number>> }, front: string): number {
  return Math.min(data.enemyLands.bands.length, Math.max(data.enemyLands.sight, world.enemySight?.[front] ?? 0));
}

// The front and band of an enemy-lands hex (null: not in them).
export function enemyHexAt(data: GameData, cell: Hex, world: { seed: number; radius: number | null; activeFronts: readonly string[] }): EnemyHex | null {
  if (world.radius === null) return null;
  const key = hexKey(cell);
  return enemyLands(data, world.seed, world.radius, world.activeFronts as Front[]).find((e) => hexKey(e.cell) === key) ?? null;
}
