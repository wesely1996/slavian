// The gods' blessings (events.json blessings). The water god blesses a
// world whose rivers run long: its longest river line, measured like a
// longest road, river edges joined corner to corner; a lake on the way
// counts the fewest lake edges from where one river meets it to where the
// next leaves it.
import type { TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex } from './hex.js';

// A corner of the grid: the three hexes that meet there.
function cornerOf(a: Hex, b: Hex, c: Hex): string {
  return [hexKey(a), hexKey(b), hexKey(c)].sort().join('/');
}

// The two corners at the ends of the edge between neighbouring a and b.
function edgeCorners(a: Hex, b: Hex): [string, string] {
  const keysB = new Set(neighbors(b).map(hexKey));
  const common = neighbors(a)
    .filter((n) => keysB.has(hexKey(n)))
    .sort((x, y) => (hexKey(x) < hexKey(y) ? -1 : 1));
  return [cornerOf(a, b, common[0]!), cornerOf(a, b, common[1]!)];
}

interface Link {
  readonly u: string;
  readonly v: string;
  readonly w: number;
}

// The length of the longest river line: river edges joined corner to
// corner, each used once, through lakes at their shortest.
export function longestRiver(rivers: readonly { a: Hex; b: Hex }[], terrain: ReadonlyMap<string, TerrainId>): number {
  const links: Link[] = [];
  const riverCorners = new Set<string>();
  for (const e of rivers) {
    const [u, v] = edgeCorners(e.a, e.b);
    links.push({ u, v, w: 1 });
    riverCorners.add(u);
    riverCorners.add(v);
  }
  // Each lake: the corners of its hexes, joined by their edges.
  const seen = new Set<string>();
  const lakeKeys = [...terrain.entries()].filter(([, t]) => t === 'lake').map(([k]) => k).sort();
  for (const start of lakeKeys) {
    if (seen.has(start)) continue;
    const body: Hex[] = [];
    const queue = [start];
    seen.add(start);
    while (queue.length) {
      const [q, r] = queue.shift()!.split(',').map(Number) as [number, number];
      const cell = { q, r };
      body.push(cell);
      for (const n of neighbors(cell)) {
        const k = hexKey(n);
        if (!seen.has(k) && terrain.get(k) === 'lake') {
          seen.add(k);
          queue.push(k);
        }
      }
    }
    const graph = new Map<string, Set<string>>();
    for (const cell of body) {
      for (const n of neighbors(cell)) {
        const [u, v] = edgeCorners(cell, n);
        if (!graph.has(u)) graph.set(u, new Set());
        if (!graph.has(v)) graph.set(v, new Set());
        graph.get(u)!.add(v);
        graph.get(v)!.add(u);
      }
    }
    const mouths = [...graph.keys()].filter((c) => riverCorners.has(c)).sort();
    for (let i = 0; i < mouths.length; i++) {
      // Fewest lake edges from this mouth to each other one.
      const dist = new Map<string, number>([[mouths[i]!, 0]]);
      const bfs = [mouths[i]!];
      while (bfs.length) {
        const c = bfs.shift()!;
        for (const n of [...graph.get(c)!].sort()) {
          if (!dist.has(n)) {
            dist.set(n, dist.get(c)! + 1);
            bfs.push(n);
          }
        }
      }
      for (let j = i + 1; j < mouths.length; j++) {
        const d = dist.get(mouths[j]!);
        if (d !== undefined && d > 0) links.push({ u: mouths[i]!, v: mouths[j]!, w: d });
      }
    }
  }
  const byCorner = new Map<string, number[]>();
  links.forEach((l, i) => {
    for (const c of [l.u, l.v]) byCorner.set(c, [...(byCorner.get(c) ?? []), i]);
  });
  const used = new Set<number>();
  let best = 0;
  // Longest trail from `at`, each link once.
  const walk = (at: string, length: number): void => {
    if (length > best) best = length;
    for (const i of byCorner.get(at) ?? []) {
      if (used.has(i)) continue;
      const l = links[i]!;
      used.add(i);
      walk(l.u === at ? l.v : l.u, length + l.w);
      used.delete(i);
    }
  };
  for (const corner of [...byCorner.keys()].sort()) walk(corner, 0);
  return best;
}
