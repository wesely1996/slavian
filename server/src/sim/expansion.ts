// Founding new villages with settlers.
import type { GameData, TerrainId } from '../data/index.js';
import { hex, hexDistance, hexKey, type Hex } from './hex.js';

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
