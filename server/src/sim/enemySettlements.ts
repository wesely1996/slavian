// The enemy's settlements in its lands (data/enemy-lands.json settlements,
// docs/mechanics/18-enemy-lands.md): where each front founds its next one,
// the rivers that run through its lands, and what a settlement builds next.
// All of it from the world's seed and what stands, so the solo engine
// (client/scripts/local/enemy_settlements.gd) reckons it the same.
import type { GameData, TerrainId } from '../data/index.js';
import { enemyLands, type EnemyHex } from './enemyLands.js';
import { DIRECTIONS, hex, hexAdd, hexDistance, hexKey, neighbors, findPath, type Hex } from './hex.js';
import { commonNeighbors, edgeKey } from './land.js';
import { FRONTS, type Front } from './mapgen.js';
import type { RiverEdge } from './mapgen.js';
import { createRng } from './rng.js';

const MASK = 0xffffffff;

interface WorldShape {
  readonly seed: number;
  readonly radius: number | null;
  readonly activeFronts: readonly string[];
}

// The enemy-lands hexes of a world by key (made once per world's lands).
const byKey = new WeakMap<readonly EnemyHex[], Map<string, EnemyHex>>();
function landsByKey(data: GameData, world: WorldShape): Map<string, EnemyHex> {
  if (world.radius === null) return new Map();
  const lands = enemyLands(data, world.seed, world.radius, world.activeFronts as Front[]);
  let known = byKey.get(lands);
  if (!known) {
    known = new Map(lands.map((e) => [hexKey(e.cell), e]));
    byKey.set(lands, known);
  }
  return known;
}

// Open land of `front` a settlement, a wall or a river may stand on.
function open(data: GameData, lands: ReadonlyMap<string, EnemyHex>, cell: Hex, front: string): boolean {
  const e = lands.get(hexKey(cell));
  return !!e && e.front === front && data.terrain.terrain[e.terrain].moveCost !== null;
}

// The settlements a front founds, in order: [{kind, band}], the deepest
// band first (the North: its lairs).
export function foundingOrder(data: GameData, front: string): { kind: string; band: number }[] {
  const rules = data.enemyLands.settlements;
  if (front === 'north') return rules.lairs.flatMap((l) => Array.from({ length: l.max }, () => ({ kind: 'lair', band: l.band })));
  const kinds = Object.entries(rules.kinds).filter(([, k]) => k.band > 0 && k.max > 0);
  const deepest = [...kinds].sort((x, y) => y[1].band - x[1].band);
  return deepest.flatMap(([kind, k]) => Array.from({ length: k.max }, () => ({ kind, band: k.band })));
}

// Where a front's `index`-th settlement goes: a hex of its band, open land at
// least minApart from every other settlement (`taken`), picked by the
// world's seed; null when none is left.
export function settlementSite(data: GameData, world: WorldShape, front: string, index: number, taken: readonly Hex[]): { kind: string; band: number; cell: Hex } | null {
  const next = foundingOrder(data, front)[index];
  if (!next || world.radius === null) return null;
  const lands = landsByKey(data, world);
  const apart = data.enemyLands.settlements.minApart;
  const candidates = [...lands.values()].filter(
    (e) =>
      e.front === front &&
      e.band === next.band &&
      open(data, lands, e.cell, front) &&
      // Not on the lands' outer rim.
      neighbors(e.cell).every((n) => lands.has(hexKey(n)) || hexDistance(n, hex(0, 0)) <= world.radius!) &&
      taken.every((t) => hexDistance(t, e.cell) >= apart),
  );
  if (!candidates.length) return null;
  const rng = createRng((world.seed + 7919 * index + 104729 * FRONTS.indexOf(front as Front) + 0x5e7) & MASK);
  return { ...next, cell: candidates[Math.floor(rng() * candidates.length)]!.cell };
}

// Rivers through each active front's lands: each from an edge in the
// deepest band, along edges towards the heartland, until it reaches the
// band nearest it, a rift or an earlier river. A ford every fordEvery edges.
export function enemyRivers(data: GameData, world: WorldShape): RiverEdge[] {
  if (world.radius === null) return [];
  const rules = data.enemyLands.rivers;
  const lands = landsByKey(data, world);
  const deepest = data.enemyLands.bands.length;
  const laid = new Set<string>();
  const out: RiverEdge[] = [];
  const centre = hex(0, 0);
  for (const front of world.activeFronts) {
    const bank = (h: Hex) => open(data, lands, h, front);
    const sources = [...lands.values()].filter((e) => e.front === front && e.band === deepest && bank(e.cell));
    for (let i = 0; i < rules.perFront; i++) {
      if (!sources.length) break;
      const rng = createRng((world.seed + 31337 + 7919 * i + 104729 * FRONTS.indexOf(front as Front)) & MASK);
      const start = sources[Math.floor(rng() * sources.length)]!.cell;
      const firsts = neighbors(start).filter((n) => bank(n) && !laid.has(edgeKey(start, n)));
      if (!firsts.length) continue;
      let [a, b] = [start, firsts[Math.floor(rng() * firsts.length)]!];
      // Flow towards the heartland: the corner nearer the centre first.
      const corners = commonNeighbors(a, b).sort((x, y) => hexDistance(x, centre) - hexDistance(y, centre));
      let ahead = corners[0]!;
      const river: { a: Hex; b: Hex }[] = [{ a, b }];
      const seen = new Set([edgeKey(a, b)]);
      for (let step = 0; step < deepest * 8; step++) {
        const e = lands.get(hexKey(ahead));
        // Out of its lands (the edge belt, a rift, another front): it ends.
        if (!e || e.front !== front || !bank(ahead) || e.band === 0) break;
        const options = ([[a, ahead], [b, ahead]] as [Hex, Hex][])
          .map(([p, q]) => {
            const other = hexKey(p) === hexKey(a) ? b : a;
            const next = commonNeighbors(p, q).find((h) => hexKey(h) !== hexKey(other))!;
            return { p, q, next, score: hexDistance(next, centre) + rng() * 0.9 };
          })
          .sort((x, y) => x.score - y.score);
        let moved = false;
        let joined = false;
        for (const o of options) {
          const key = edgeKey(o.p, o.q);
          if (laid.has(key)) {
            joined = true;
            break;
          }
          if (seen.has(key) || !bank(o.p) || !bank(o.q)) continue;
          [a, b, ahead] = [o.p, o.q, o.next];
          river.push({ a, b });
          seen.add(key);
          moved = true;
          break;
        }
        if (joined || !moved) break;
      }
      if (river.length < rules.minLength) continue;
      for (const [k, e] of river.entries()) {
        laid.add(edgeKey(e.a, e.b));
        out.push({ a: e.a, b: e.b, bridge: (k + 2) % rules.fordEvery === 0, size: 1 });
      }
    }
  }
  return out;
}

export interface SettlementSpot {
  readonly id: number;
  readonly front: string;
  readonly kind: string;
  readonly cell: Hex;
  // Its level now (settlementLevel).
  readonly level: number;
}

// A settlement grows a level every growHours game hours from its founding,
// up to maxLevel.
export function settlementLevel(data: GameData, foundedAt: Date, at: Date, worldSpeed: number): number {
  const rules = data.enemyLands.settlements;
  const hours = ((at.getTime() - foundedAt.getTime()) * worldSpeed) / 3_600_000;
  return Math.min(rules.maxLevel, 1 + Math.floor(Math.max(0, hours) / rules.growHours));
}

// The highest tier its walls rise to at `level`.
export function wallTierCap(data: GameData, kind: string, level: number): number {
  const rules = data.enemyLands.settlements;
  return Math.min(rules.kinds[kind]?.wallTier ?? 0, 1 + Math.floor((level - 1) / rules.levelsPerWallTier));
}

// What stands along the edges, by edge key.
export interface EdgeState {
  readonly walls: ReadonlyMap<string, { tier: number; gate: boolean }>;
  readonly roads: ReadonlySet<string>;
  // Rivers, and whether they are crossed there (a bridge or a ford).
  readonly rivers: ReadonlyMap<string, boolean>;
}

export type EnemyWork =
  | { kind: 'wall'; a: Hex; b: Hex }
  | { kind: 'raise'; a: Hex; b: Hex; tier: number }
  | { kind: 'road'; a: Hex; b: Hex; gates: { a: Hex; b: Hex }[] }
  | { kind: 'bridge'; a: Hex; b: Hex }
  | { kind: 'moat'; a: Hex; b: Hex; bridged: boolean };

// The older settlement of its front a settlement's road runs to: the nearest
// (the lower id on a tie); null for the first.
export function roadTarget(settlement: SettlementSpot, all: readonly SettlementSpot[]): SettlementSpot | null {
  let best: SettlementSpot | null = null;
  for (const s of all) {
    if (s.front !== settlement.front || s.id >= settlement.id) continue;
    if (!best || hexDistance(s.cell, settlement.cell) < hexDistance(best.cell, settlement.cell)) best = s;
  }
  return best;
}

// The road a settlement runs to its target: the cheapest by terrain, a river
// without a crossing counting 2 more, never through a wall but those of the
// two settlements' own hexes.
export function settlementRoad(data: GameData, world: WorldShape, from: Hex, to: Hex, front: string, state: EdgeState): Hex[] | null {
  const lands = landsByKey(data, world);
  const ends = new Set([hexKey(from), hexKey(to)]);
  return findPath(from, to, (p, q) => {
    if (!open(data, lands, q, front)) return null;
    const key = edgeKey(p, q);
    if (state.walls.has(key) && !state.walls.get(key)!.gate && !ends.has(hexKey(p)) && !ends.has(hexKey(q))) return null;
    const terrain = lands.get(hexKey(q))!.terrain as TerrainId;
    const cost = data.terrain.terrain[terrain].moveCost ?? 1;
    return (state.roads.has(key) ? cost * 0.5 : cost) + (state.rivers.has(key) && !state.rivers.get(key) ? 2 : 0);
  }, 0.5);
}

// The next work of a settlement that builds, or null with nothing left:
// palisades on its own edges, its road to `target` (bridging rivers; a
// wall where the road meets a settlement's hex becomes its gatehouse), its
// moat, then raising its walls to its kind's wallTier.
export function nextWork(data: GameData, world: WorldShape, s: SettlementSpot, target: Hex | null, state: EdgeState): EnemyWork | null {
  const kind = data.enemyLands.settlements.kinds[s.kind];
  if (!kind?.builds) return null;
  const lands = landsByKey(data, world);
  const bank = (h: Hex) => open(data, lands, h, s.front);
  // Palisades all round.
  for (const d of DIRECTIONS) {
    const n = hexAdd(s.cell, d);
    const key = edgeKey(s.cell, n);
    if (bank(n) && !state.walls.has(key) && !state.rivers.has(key)) return { kind: 'wall', a: s.cell, b: n };
  }
  // The road, an edge at a time.
  if (target) {
    const path = settlementRoad(data, world, s.cell, target, s.front, state);
    if (path) {
      for (let i = 1; i < path.length; i++) {
        const [p, q] = [path[i - 1]!, path[i]!];
        const key = edgeKey(p, q);
        if (state.roads.has(key)) continue;
        if (state.rivers.has(key) && !state.rivers.get(key)) return { kind: 'bridge', a: p, b: q };
        const gates = state.walls.has(key) && !state.walls.get(key)!.gate ? [{ a: p, b: q }] : [];
        return { kind: 'road', a: p, b: q, gates };
      }
    }
  }
  // The moat round its ring of neighbours.
  if (kind.moat) {
    for (const d of DIRECTIONS) {
      const n = hexAdd(s.cell, d);
      if (!bank(n)) continue;
      for (const m of neighbors(n)) {
        if (hexDistance(m, s.cell) !== 2 || !bank(m)) continue;
        const key = edgeKey(n, m);
        if (state.rivers.has(key) || state.walls.has(key)) continue;
        return { kind: 'moat', a: n, b: m, bridged: state.roads.has(key) };
      }
    }
  }
  // Its walls a tier higher (as high as its level allows), the lowest first.
  const cap = wallTierCap(data, s.kind, s.level);
  let lowest: { a: Hex; b: Hex; tier: number } | null = null;
  for (const d of DIRECTIONS) {
    const n = hexAdd(s.cell, d);
    const wall = state.walls.get(edgeKey(s.cell, n));
    if (wall && wall.tier < cap && (!lowest || wall.tier < lowest.tier)) lowest = { a: s.cell, b: n, tier: wall.tier };
  }
  return lowest ? { kind: 'raise', a: lowest.a, b: lowest.b, tier: lowest.tier + 1 } : null;
}

// What players call a settlement: its front's name for its kind.
export function settlementName(data: GameData, front: string, kind: string): string {
  return data.enemyLands.settlements.names[front]?.[kind] ?? kind;
}
