// Founding new villages with settlers.
import type { GameData, TerrainId } from '../data/index.js';
import { hex, hexDistance, hexKey, ring, type Hex } from './hex.js';
import { START_RING } from './mapgen.js';

export const SETTLER = 'settler';

export interface SettleSite {
  readonly cell: Hex;
  readonly terrain: TerrainId | undefined;
  // The settlers' village.
  readonly home: Hex;
  readonly villages: readonly Hex[];
  // Hexes holding an outpost ("q,r").
  readonly outposts: ReadonlySet<string>;
}

// Why a village can't be founded on a hex, or null when it can.
export function settleProblem(data: GameData, site: SettleSite): string | null {
  const rules = data.expansion;
  if (!site.terrain) return 'That hex is not on the map';
  if (!data.terrain.terrain[site.terrain].settleable) {
    return `Villages can't be founded on ${data.terrain.terrain[site.terrain].name}`;
  }
  if (hexDistance(site.cell, site.home) > rules.maxDistance) {
    return `Settlers walk at most ${rules.maxDistance} hexes from their village`;
  }
  if (hexDistance(site.cell, hex(0, 0)) < rules.minHolyCityDistance) return 'Too close to the Holy City';
  if (site.villages.some((v) => hexDistance(v, site.cell) < rules.minVillageDistance)) {
    return `Villages stand at least ${rules.minVillageDistance} hexes apart`;
  }
  if (site.outposts.has(hexKey(site.cell))) return 'An outpost stands there';
  return null;
}

// Grain per hour (at world speed 1) the next village pays for its
// administration, given how many its owner already has.
export function adminUpkeepFor(data: GameData, villagesOwned: number): number {
  return data.expansion.adminUpkeepPerVillage * villagesOwned;
}

export function recommendedGarrison(data: GameData, villagesOwned: number): number {
  const { base, perVillage } = data.expansion.recommendedGarrison;
  return base + perVillage * Math.max(0, villagesOwned - 1);
}

// Where a player who joins a run under way founds their village: free,
// settleable ground at least `minVillageDistance` from every village, on
// the ring nearest the starting ring that has any, and there the spot
// farthest from the other villages (ties: the ring's order). `reachable`
// says whether a road leads from a hex to the Holy City.
export function joinSite(
  data: GameData,
  terrain: ReadonlyMap<string, TerrainId>,
  villages: readonly Hex[],
  taken: ReadonlySet<string>,
  reachable: (cell: Hex) => boolean,
): Hex | null {
  const rules = data.expansion;
  const radius = Math.max(0, ...[...terrain.keys()].map((key) => { const [q, r] = key.split(',').map(Number); return hexDistance(hex(q!, r!), hex(0, 0)); }));
  const nearest = (cell: Hex) => Math.min(Infinity, ...villages.map((v) => hexDistance(v, cell)));
  for (let d = Math.max(START_RING, rules.minHolyCityDistance); d <= radius; d++) {
    let best: Hex | null = null;
    for (const cell of ring(hex(0, 0), d)) {
      const type = terrain.get(hexKey(cell));
      if (!type || !data.terrain.terrain[type].settleable || taken.has(hexKey(cell))) continue;
      if (nearest(cell) < rules.minVillageDistance || (best && nearest(cell) <= nearest(best))) continue;
      if (reachable(cell)) best = cell;
    }
    if (best) return best;
  }
  return null;
}
